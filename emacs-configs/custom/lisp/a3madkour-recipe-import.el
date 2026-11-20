;;; a3madkour-recipe-import.el --- import recipes into the org format  -*- lexical-binding: t; -*-

;;; Commentary:

;; Two ways in, both producing a private recipe file beside the ingredient
;; registry, in the format `a3-recipe-new' writes:
;;
;; - `a3-recipe-import' reads a web page.  Most recipe sites embed the recipe
;;   as schema.org JSON-LD for search engines; that block is read, never the
;;   page's prose.  A page without one is refused.
;; - `a3-recipe-import-org-chef' converts the org-chef entry at point (a
;;   heading with an Ingredients list and a Directions list).
;;
;; Ingredient lines are free text ("1 ½ Tbsp olive oil, divided"), so they are
;; split into qty / unit / item / note by rule of thumb.  The result is a
;; first draft: `a3-ingredient-resolve-recipe' then ties the items to the
;; registry.  Needs nothing beyond Emacs.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'url)
(require 'url-parse)
(require 'org)
(require 'org-id)
(require 'org-table)
(require 'a3madkour-ingredients)
(require 'a3madkour-recipes)
(require 'a3madkour-units)

;;; Text clean-up

(defconst a3madkour-recipe-import--entities
  '(("amp" . "&") ("quot" . "\"") ("apos" . "'") ("lt" . "<") ("gt" . ">")
    ("nbsp" . " ") ("frac12" . "½") ("frac14" . "¼") ("frac34" . "¾")
    ("deg" . "°") ("ndash" . "–") ("mdash" . "—") ("rsquo" . "’")
    ("lsquo" . "‘") ("rdquo" . "”") ("ldquo" . "“") ("hellip" . "…")))

(defun a3madkour-recipe-import--clean (string)
  "STRING as one line of plain text: tags and entities gone, spaces collapsed."
  (let ((s (or string "")))
    (setq s (replace-regexp-in-string "<[^>]*>" " " s))
    (setq s (replace-regexp-in-string
             "&#\\(x?\\)\\([0-9a-fA-F]+\\);"
             (lambda (m)
               (save-match-data
                 (string-match "&#\\(x?\\)\\([0-9a-fA-F]+\\);" m)
                 (string (string-to-number (match-string 2 m)
                                           (if (string-empty-p (match-string 1 m)) 10 16)))))
             s t t))
    (setq s (replace-regexp-in-string
             "&\\([a-zA-Z0-9]+\\);"
             (lambda (m)
               (or (cdr (assoc (substring m 1 -1) a3madkour-recipe-import--entities)) m))
             s t t))
    (string-join (split-string s "[[:space:]\u00a0]+" t) " ")))

(defun a3madkour-recipe-import--cell (string)
  "STRING made safe for an org table cell."
  (replace-regexp-in-string "|" "/" (or string "")))

;;; Splitting an ingredient line

(defconst a3madkour-recipe-import--count-units
  '("clove" "cloves" "can" "cans" "pinch" "pinches" "bunch" "bunches" "slice"
    "slices" "stick" "sticks" "sprig" "sprigs" "handful" "handfuls" "piece"
    "pieces" "head" "heads" "stalk" "stalks" "dash" "dashes" "package"
    "packages" "jar" "jars" "bottle" "bottles")
  "Words that count things; kept as units as written (downcased).")

(defconst a3madkour-recipe-import--sizes
  '("small" "medium" "large" "big" "heaping" "heaped" "scant" "healthy"
    "generous" "level")
  "Words between a quantity and what it counts; they go to the note.")

(defconst a3madkour-recipe-import--qty-re
  (let* ((frac "[½¼¾⅓⅔⅛⅜⅝⅞]")
         (num (concat "\\(?:[0-9]+\\(?:[./][0-9]+\\)?\\|" frac "\\)"))
         (mixed (concat num "\\(?:[ \t]*\\(?:[0-9]+/[0-9]+\\|" frac "\\)\\)?")))
    (concat "\\`\\(" mixed "\\)\\(?:[ \t]*\\(?:-\\|–\\|—\\|to\\b\\)[ \t]*\\(" mixed "\\)\\)?[ \t]*"))
  "A leading quantity, optionally a range.")

(defun a3madkour-recipe-import/parse-ingredient (line)
  "Split free-text ingredient LINE into (:qty :unit :item :note).
Each is a string or nil.  :qty is a plain number the publisher accepts; a
range becomes its upper end and is kept verbatim in the note."
  (let ((s (a3madkour-recipe-import--clean line))
        (qty nil) (unit nil) (notes '()) (looking t))
    ;; Some sites double their brackets: "oil ((or butter))".
    (setq s (replace-regexp-in-string "(\\s-*(+" "(" s))
    (setq s (replace-regexp-in-string ")\\s-*)+" ")" s))
    (when (string-match a3madkour-recipe-import--qty-re s)
      ;; Take everything from the match before parsing clobbers it.
      (let* ((whole (string-trim (match-string 0 s)))
             (range (match-string 2 s))
             (end (match-end 0))
             (value (a3madkour-units/parse-qty whole)))
        (when value
          (setq qty (a3madkour-units/format-qty value))
          (when range (push whole notes))
          (setq s (substring s end)))))
    ;; Between the quantity and the name: bracketed asides, sizes, a unit.
    (while looking
      (cond
       ((string-match "\\`(\\([^)]*\\))[ \t]*" s)
        (let ((aside (match-string 1 s)) (end (match-end 0)))
          (push (string-trim aside) notes)
          (setq s (substring s end))))
       ((and (string-match "\\`\\([[:alpha:]]+\\)[ \t]+" s)
             (member (downcase (match-string 1 s)) a3madkour-recipe-import--sizes))
        (let ((size (match-string 1 s)) (end (match-end 0)))
          (push (downcase size) notes)
          (setq s (substring s end))))
       (t (setq looking nil))))
    (when qty
      (cond
       ((string-match "\\`fl\\.? ?oz\\.?[ \t]+" s)
        (setq unit "floz" s (substring s (match-end 0))))
       ((string-match "\\`\\([[:alpha:]]+\\)\\.?[ \t]+" s)
        (let* ((word (downcase (match-string 1 s)))
               (end (match-end 0))
               (canonical (a3madkour-units/canonical word)))
          (cond ((member word a3madkour-recipe-import--count-units)
                 (setq unit word s (substring s end)))
                ((not (string= canonical word))
                 (setq unit canonical s (substring s end)))
                ((assoc word a3madkour-units--names)
                 (setq unit word s (substring s end))))))))
    (setq s (replace-regexp-in-string "\\`of[ \t]+" "" s))
    ;; After the name: bracketed asides, then whatever follows a comma.
    (while (string-match "\\`\\(.*?\\)[ \t]*(\\([^()]*\\))[ \t]*\\'" s)
      (let ((aside (match-string 2 s)) (head (match-string 1 s)))
        (setq s head aside (string-trim aside))
        (unless (string-empty-p aside) (setq notes (append notes (list aside))))))
    (when (string-match "\\`\\([^,]*\\),[ \t]*\\(.*\\)\\'" s)
      (let ((tail (match-string 2 s)) (head (match-string 1 s)))
        (setq s head tail (string-trim tail))
        (unless (string-empty-p tail) (setq notes (cons tail notes)))))
    (setq s (string-trim (replace-regexp-in-string "\\*+\\'" "" (string-trim s))))
    (list :qty qty :unit unit
          :item (unless (string-empty-p s) s)
          :note (and notes (string-join notes "; ")))))

;;; Reading schema.org JSON-LD

(defun a3madkour-recipe-import--recipe-node (data)
  "The first schema.org Recipe object inside parsed JSON DATA, or nil."
  (cond
   ((and (consp data) (consp (car data)) (symbolp (caar data)))
    ;; An object (alist).
    (let ((type (alist-get '@type data)))
      (if (or (equal type "Recipe") (and (listp type) (member "Recipe" type)))
          data
        (cl-some (lambda (pair) (a3madkour-recipe-import--recipe-node (cdr pair)))
                 data))))
   ((listp data) (cl-some #'a3madkour-recipe-import--recipe-node data))))

(defun a3madkour-recipe-import--minutes (duration)
  "ISO 8601 DURATION (\"PT1H30M\") in whole minutes, or nil."
  (when (and (stringp duration)
             (string-match
              "\\`P\\(?:\\([0-9]+\\)D\\)?\\(?:T\\(?:\\([0-9]+\\)H\\)?\\(?:\\([0-9]+\\)M\\)?\\(?:[0-9.]+S\\)?\\)?\\'"
              duration))
    (let ((total (+ (* 1440 (string-to-number (or (match-string 1 duration) "0")))
                    (* 60 (string-to-number (or (match-string 2 duration) "0")))
                    (string-to-number (or (match-string 3 duration) "0")))))
      (when (> total 0) total))))

(defun a3madkour-recipe-import--first-string (value)
  "VALUE, or its first element, as cleaned text; nil when there is none."
  (let ((v (if (and (listp value)
                    ;; A list of values, not one object (an alist).
                    (not (and (consp (car value)) (symbolp (caar value)))))
               (car value)
             value)))
    (cond ((stringp v) (let ((s (a3madkour-recipe-import--clean v)))
                         (unless (string-empty-p s) s)))
          ((numberp v) (number-to-string v)))))

(defun a3madkour-recipe-import--servings (yield)
  "The first whole number in recipeYield YIELD, as a string, or nil."
  (cl-some (lambda (v)
             (let ((s (cond ((numberp v) (number-to-string v)) ((stringp v) v))))
               (and s (string-match "[0-9]+" s) (match-string 0 s))))
           (if (listp yield) yield (list yield))))

(defun a3madkour-recipe-import--steps (instructions)
  "recipeInstructions INSTRUCTIONS flattened to a list of step strings."
  (cond
   ((stringp instructions)
    (cl-remove-if #'string-empty-p
                  (mapcar #'a3madkour-recipe-import--clean
                          (split-string instructions "\n\\|</p>\\|</li>\\|<br ?/?>" t))))
   ((and (consp (car-safe instructions)) (symbolp (caar instructions)))
    ;; One object: a step, or a section holding steps.
    (if (alist-get 'itemListElement instructions)
        (a3madkour-recipe-import--steps (alist-get 'itemListElement instructions))
      (a3madkour-recipe-import--steps
       (or (alist-get 'text instructions) (alist-get 'name instructions)))))
   ((listp instructions)
    (apply #'append (mapcar #'a3madkour-recipe-import--steps instructions)))))

(defun a3madkour-recipe-import/from-html (html)
  "The recipe embedded in page HTML as JSON-LD, as a plist, or nil.
Keys: :title :summary :servings :prep :cook :total (minutes) :cuisine
:category :ingredients (strings) :steps (strings)."
  (let ((start 0) (node nil))
    (while (and (not node)
                (string-match
                 "<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>\\(\\(?:.\\|\n\\)*?\\)</script>"
                 html start))
      (setq start (match-end 0))
      (let ((data (condition-case nil
                      (json-parse-string (match-string 1 html)
                                         :object-type 'alist :array-type 'list
                                         :null-object nil :false-object nil)
                    (error nil))))
        (setq node (a3madkour-recipe-import--recipe-node data))))
    (when node
      (list :title (a3madkour-recipe-import--first-string (alist-get 'name node))
            :summary (a3madkour-recipe-import--first-string (alist-get 'description node))
            :servings (a3madkour-recipe-import--servings (alist-get 'recipeYield node))
            :prep (a3madkour-recipe-import--minutes (alist-get 'prepTime node))
            :cook (a3madkour-recipe-import--minutes (alist-get 'cookTime node))
            :total (a3madkour-recipe-import--minutes (alist-get 'totalTime node))
            :cuisine (a3madkour-recipe-import--first-string (alist-get 'recipeCuisine node))
            :category (a3madkour-recipe-import--first-string (alist-get 'recipeCategory node))
            :ingredients (cl-remove-if
                          #'string-empty-p
                          (mapcar #'a3madkour-recipe-import--clean
                                  (let ((v (alist-get 'recipeIngredient node)))
                                    (if (stringp v) (list v) v))))
            :steps (a3madkour-recipe-import--steps
                    (alist-get 'recipeInstructions node))))))

;;; Writing the recipe

(defun a3madkour-recipe-import--render (recipe title source)
  "The org text of RECIPE (a plist as above) titled TITLE.
SOURCE is the Sources line's text, or nil."
  (with-temp-buffer
    (insert ":PROPERTIES:\n:ID:       " (org-id-new) "\n"
            ":servings:" (if (plist-get recipe :servings)
                             (concat " " (plist-get recipe :servings)) "")
            "\n")
    (dolist (field '((:prep . "prep-time") (:cook . "cook-time") (:total . "total-time")
                     (:cuisine . "cuisine") (:category . "category")))
      (let ((v (plist-get recipe (car field))))
        (when v (insert ":" (cdr field) ": " (format "%s" v) "\n"))))
    (insert ":END:\n#+TITLE: " title "\n#+HUGO_SECTION: recipes\n#+HUGO_PUBLISH: nil\n"
            "#+HUGO_SUMMARY:" (if (plist-get recipe :summary)
                                  (concat " " (plist-get recipe :summary)) "")
            "\n\n** Ingredients\n"
            "| qty | unit | item | group | note | alt |\n|-\n")
    (dolist (line (or (plist-get recipe :ingredients) '("")))
      (let ((p (a3madkour-recipe-import/parse-ingredient line)))
        (insert "| " (or (plist-get p :qty) "") " | " (or (plist-get p :unit) "") " | "
                (a3madkour-recipe-import--cell (plist-get p :item)) " | | "
                (a3madkour-recipe-import--cell (plist-get p :note)) " | |\n")))
    (insert "** Steps\n")
    (let ((n 0))
      (dolist (step (or (plist-get recipe :steps) '("")))
        (insert (format "%d. %s\n" (cl-incf n) step))))
    (insert "** Sources\n- " (or source "") "\n")
    ;; Align the table the way org would, so the file is tidy before any edit.
    (let ((org-inhibit-startup t)) (delay-mode-hooks (org-mode)))
    (goto-char (point-min))
    (re-search-forward "^| qty")
    (org-table-align)
    ;; No trailing spaces left behind by empty list items.
    (goto-char (point-min))
    (while (re-search-forward "[ \t]+$" nil t) (replace-match ""))
    (buffer-string)))

(defun a3madkour-recipe-import--create (recipe title source)
  "Write RECIPE as a new recipe file titled TITLE and visit it.
Say how many of its ingredients the registry does not know."
  (let* ((new (a3madkour-recipes/new-file title))
         (file (a3madkour-recipes/write-and-visit
                (cdr new)
                (a3madkour-recipe-import--render recipe (car new) source)))
         (unknown (length (a3madkour-ingredients/unknown-items))))
    (message "Imported %s: %d ingredient%s%s"
             (car new)
             (length (plist-get recipe :ingredients))
             (if (= 1 (length (plist-get recipe :ingredients))) "" "s")
             (if (> unknown 0)
                 (format ", %d not in the registry (resolve them with a3-ingredient-resolve-recipe)"
                         unknown)
               ""))
    file))

(defun a3madkour-recipe-import--fetch (url)
  "The body of the page at URL, decoded as UTF-8."
  (let ((buf (url-retrieve-synchronously url t t 30)))
    (unless buf (user-error "Could not fetch %s" url))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (re-search-forward "\r?\n\r?\n" nil 'move)
          (decode-coding-string
           (buffer-substring-no-properties (point) (point-max)) 'utf-8))
      (kill-buffer buf))))

;;;###autoload
(defun a3-recipe-import (url)
  "Import the recipe on the web page at URL as a new private recipe.
Reads the page's embedded schema.org recipe data; a page without it is
refused.  Return the new file's name."
  (interactive (list (string-trim (read-string "Recipe URL: "))))
  (unless (string-match-p "\\`https?://" url)
    (user-error "Not a web address: %s" url))
  ;; Fail on an unset registry before going to the network.
  (a3madkour-recipes/new-file "x")
  (let ((recipe (or (a3madkour-recipe-import/from-html
                     (a3madkour-recipe-import--fetch url))
                    (user-error "No recipe data found at %s" url))))
    (a3madkour-recipe-import--create
     recipe
     (or (plist-get recipe :title) (user-error "The recipe at %s has no name" url))
     (format "[[%s][%s]]" url
             (or (url-host (url-generic-parse-url url)) url)))))

;;;###autoload
(defun a3-recipe-import-org-chef ()
  "Convert the org-chef recipe at point into a new private recipe.
The entry is a heading with an Ingredients list and a Directions list below
it, and optionally :source-url: and :servings: properties.  It is left as it
is.  Return the new file's name."
  (interactive)
  (unless (derived-mode-p 'org-mode) (user-error "Not an org buffer"))
  (let (title url servings (ingredients '()) (steps '()))
    (save-excursion
      (save-restriction
        (widen)
        (org-back-to-heading t)
        ;; Climb from Ingredients / Directions to the recipe's own heading.
        (while (and (member (downcase (org-get-heading t t t t))
                            '("ingredients" "directions"))
                    (org-up-heading-safe)))
        (setq title (org-get-heading t t t t)
              url (org-entry-get nil "source-url")
              servings (org-entry-get nil "servings"))
        (let ((end (save-excursion (org-end-of-subtree t t) (point)))
              (section nil))
          (forward-line 1)
          (while (< (point) end)
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (cond
               ((string-match "\\`\\*+ +\\(.*?\\)[ \t]*\\'" line)
                (setq section (downcase (match-string 1 line))))
               ((string-match "\\`[ \t]*\\(?:[-+]\\|[0-9]+[.)]\\)[ \t]+\\(.*\\)\\'" line)
                (let ((text (a3madkour-recipe-import--clean (match-string 1 line))))
                  (unless (string-empty-p text)
                    (pcase section
                      ("ingredients" (push text ingredients))
                      ("directions" (push text steps))))))))
            (forward-line 1)))))
    (unless ingredients
      (user-error "No Ingredients list under \"%s\"" title))
    (a3madkour-recipe-import--create
     (list :servings (and servings (string-match "[0-9]+" servings) (match-string 0 servings))
           :ingredients (nreverse ingredients)
           :steps (nreverse steps))
     title
     (and url (not (string-empty-p url))
          (format "[[%s][%s]]" url (or (url-host (url-generic-parse-url url)) url))))))

(provide 'a3madkour-recipe-import)
;;; a3madkour-recipe-import.el ends here
