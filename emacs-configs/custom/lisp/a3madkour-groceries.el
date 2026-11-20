;;; a3madkour-groceries.el --- the grocery list  -*- lexical-binding: t; -*-

;;; Commentary:

;; One standing org file, groceries.org beside the ingredient registry, to
;; shop from in Emacs on the phone.  It is plain org: checkbox lines under one
;; heading per aisle, then "Other" (things with no aisle), "Extra" and
;; "Recipes".
;;
;; What is on it comes from three places:
;;
;; - the pantry: every registry ingredient tagged :out: or :low:;
;; - the recipes listed under "Recipes" (`a3-grocery-plan-recipe'): whatever
;;   they need that is not tagged :have:, with the amounts added up;
;; - the owner: lines typed under "Extra", which are carried over untouched.
;;
;; `a3-grocery-list' rebuilds the aisle sections, keeping ticks.  Anything
;; typed outside "Extra" that is not a current item is moved there rather than
;; dropped.  `a3-grocery-done' closes a trip: what was ticked becomes :have:
;; and every ticked line leaves the list.
;;
;; The registry is read through `a3madkour-ingredients/entries', `/aisles'
;; and `/lookup', and written only through `/set-entry-state' and
;; `/add-entry'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'a3madkour-ingredients)
(require 'a3madkour-recipes)
(require 'a3madkour-units)

(defconst a3madkour-groceries--other "Other"
  "Heading for things that carry no aisle tag.")
(defconst a3madkour-groceries--extra "Extra"
  "Heading of the section the owner types into.")
(defconst a3madkour-groceries--recipes "Recipes"
  "Heading of the section listing the recipes being shopped for; always last.")

(defconst a3madkour-groceries--checkbox-re
  "\\`\\([ \t]*\\)- \\[\\([ Xx-]\\)\\] +\\(.*?\\)[ \t]*\\'"
  "A checkbox line: indentation, the mark, the text.")

(defun a3madkour-groceries/file ()
  "The grocery list's path: groceries.org beside the ingredient registry."
  (expand-file-name
   "groceries.org"
   (file-name-directory
    (or a3madkour-ingredients/file
        (user-error "a3madkour-ingredients/file is not set")))))

(defun a3madkour-groceries/conflict-files ()
  "Sync-conflict copies of the grocery list.  Listed only, never touched."
  (let ((dir (file-name-directory (a3madkour-groceries/file))))
    (when (file-directory-p dir)
      (directory-files dir t "\\`groceries\\.sync-conflict-"))))

(defun a3madkour-groceries--heading (aisle)
  "The heading shown for AISLE tag: \"oils_vinegar\" is \"Oils vinegar\"."
  (let ((name (replace-regexp-in-string "_+" " " aisle)))
    (setq name (concat (upcase (substring name 0 1)) (substring name 1)))
    ;; An aisle must not pass for one of the list's own sections.
    (if (member (downcase name)
                (mapcar #'downcase (list a3madkour-groceries--extra
                                         a3madkour-groceries--recipes
                                         a3madkour-groceries--other)))
        (concat name " (aisle)")
      name)))

(defun a3madkour-groceries--ticked-p (mark)
  (member mark '("X" "x")))

;;; What is needed

(defun a3madkour-groceries--planned (lines)
  "The recipes that LINES (the Recipes section) link to, as (TITLE . FILE).
A line that links to no recipe file is ignored."
  (let ((dir (file-name-directory (a3madkour-groceries/file))) (out '()))
    (dolist (l lines)
      (when (string-match "\\[\\[file:\\([^]]+\\)\\]" l)
        (let* ((file (expand-file-name (match-string 1 l) dir))
               (title (and (file-exists-p file) (a3madkour-recipes/title file))))
          (when (and title (not (rassoc file out)))
            (push (cons title file) out)))))
    (nreverse out)))

(defun a3madkour-groceries--needs (planned)
  "What to buy, given PLANNED recipes ((TITLE . FILE) ...).
Return (LIST . TABLE): LIST is need plists in list order, TABLE maps each
need's :key to it.  A need has :key (a normalised name), :name, :aisle, :low,
:entry (its registry entry, or nil for a recipe item the registry does not
know), :amounts ((QTY . UNIT) ...) and :recipes (titles)."
  (let ((table (make-hash-table :test #'equal))
        (unknown '()))
    (dolist (e (a3madkour-ingredients/entries))
      (when (memq (plist-get e :state) '(out low))
        (puthash (a3madkour-ingredients/normalize (plist-get e :name))
                 (list :name (plist-get e :name) :aisle (plist-get e :aisle)
                       :low (eq (plist-get e :state) 'low) :entry e
                       :amounts nil :recipes nil)
                 table)))
    (dolist (recipe planned)
      (dolist (row (a3madkour-recipes/rows (cdr recipe)))
        (let* ((entry (a3madkour-ingredients/lookup (plist-get row :item)))
               (key (a3madkour-ingredients/normalize
                     (if entry (plist-get entry :name) (plist-get row :item)))))
          ;; What the pantry has is not bought again.
          (unless (and entry (eq (plist-get entry :state) 'have))
            (let ((need (gethash key table)))
              (unless need
                (setq need (list :name (if entry (plist-get entry :name) (plist-get row :item))
                                 :aisle (and entry (plist-get entry :aisle))
                                 :low nil :entry entry :amounts nil :recipes nil))
                (puthash key need table)
                (unless entry (push key unknown)))
              (plist-put need :amounts
                         (append (plist-get need :amounts)
                                 (list (cons (a3madkour-units/parse-qty (plist-get row :qty))
                                             (plist-get row :unit)))))
              (unless (member (car recipe) (plist-get need :recipes))
                (plist-put need :recipes
                           (append (plist-get need :recipes) (list (car recipe))))))))))
    (maphash (lambda (key need) (plist-put need :key key)) table)
    ;; Registry order first, then what the registry does not know.
    (cons (append
           (delq nil (mapcar (lambda (e)
                               (gethash (a3madkour-ingredients/normalize (plist-get e :name))
                                        table))
                             (a3madkour-ingredients/entries)))
           (mapcar (lambda (key) (gethash key table)) (nreverse unknown)))
          table)))

(defun a3madkour-groceries--strip-note (text)
  "TEXT without its last top-level bracketed group and the space before it.
Nil when trimmed TEXT does not end in a balanced \"(...)\" group."
  (let* ((text (string-trim-right text))
         (i (1- (length text))) (depth 0) (start nil))
    (when (and (>= i 0) (eq (aref text i) ?\)))
      (while (and (>= i 0) (not start))
        (pcase (aref text i)
          (?\) (setq depth (1+ depth)))
          (?\( (setq depth (1- depth))
               (when (zerop depth) (setq start i))))
        (setq i (1- i)))
      (and start (string-trim-right (substring text 0 start))))))

(defun a3madkour-groceries--resolve (text table)
  "What checkbox TEXT names, as (KEY . ENTRY), or nil.
KEY is in TABLE (a need) or ENTRY is a registry entry, or both.  TEXT may end
in notes in brackets, \"(low)\" or \"(2 tbsp: Toast)\"; they are dropped from
the right until a name is recognised, so a name with brackets of its own
still matches."
  (let ((candidate (string-trim text)) (found nil) (done nil))
    (while (not done)
      (let* ((entry (a3madkour-ingredients/lookup candidate))
             (key (a3madkour-ingredients/normalize
                   (if entry (plist-get entry :name) candidate))))
        (cond
         ((or entry (and table (gethash key table)))
          (setq found (cons key entry) done t))
         ((a3madkour-groceries--strip-note candidate)
          (setq candidate (a3madkour-groceries--strip-note candidate)))
         (t (setq done t)))))
    found))

;;; Reading and writing the list

(defun a3madkour-groceries--trim-blank-tail (lines)
  "LINES (newest first) without the blank lines at its head; in file order."
  (while (and lines (string-match-p "\\`[ \t]*\\'" (car lines)))
    (pop lines))
  (nreverse lines))

(defun a3madkour-groceries--sections (text)
  "Split grocery list TEXT.
Return a plist: :extra and :recipes, those sections' lines as written;
:lines, every other non-blank line outside them, in file order, each either
\(item TICKED TEXT LINE) for a checkbox or (stray LINE) for anything else."
  (let ((section nil) (extra '()) (recipes '()) (lines '()))
    (dolist (l (split-string text "\n"))
      (cond
       ((string-match "\\`\\* +\\(.*?\\)[ \t]*\\'" l)
        (setq section (cond ((string= (match-string 1 l) a3madkour-groceries--extra) 'extra)
                            ((string= (match-string 1 l) a3madkour-groceries--recipes) 'recipes)
                            (t 'aisle))))
       ((eq section 'extra) (push l extra))
       ((eq section 'recipes) (push l recipes))
       ((string-match-p "\\`[ \t]*\\'" l))
       ((string-match-p "\\`#\\+" l))
       ((string-match a3madkour-groceries--checkbox-re l)
        (push (list 'item (and (a3madkour-groceries--ticked-p (match-string 2 l)) t)
                    (match-string 3 l) l)
              lines))
       (t (push (list 'stray l) lines))))
    (list :extra (a3madkour-groceries--trim-blank-tail extra)
          :recipes (a3madkour-groceries--trim-blank-tail recipes)
          :lines (nreverse lines))))

(defun a3madkour-groceries--items (parts)
  "The checkbox lines of PARTS outside Extra and Recipes, as (TICKED TEXT LINE)."
  (mapcar #'cdr (cl-remove-if-not (lambda (l) (eq (car l) 'item))
                                  (plist-get parts :lines))))

(defun a3madkour-groceries--recipe-item-p (text)
  "Non-nil when checkbox TEXT names an ingredient of some recipe.
Such a line was written by this list for a recipe that is no longer shopped
for, not typed by the owner.  Notes in brackets are dropped as in
`a3madkour-groceries--resolve'."
  (let ((names (make-hash-table :test #'equal))
        (candidate (string-trim text)) (found nil) (done nil))
    (dolist (recipe (a3madkour-recipes/files))
      (dolist (row (a3madkour-recipes/rows (cdr recipe)))
        (puthash (a3madkour-ingredients/normalize (plist-get row :item)) t names)))
    (while (not done)
      (cond
       ((gethash (a3madkour-ingredients/normalize candidate) names)
        (setq found t done t))
       ((a3madkour-groceries--strip-note candidate)
        (setq candidate (a3madkour-groceries--strip-note candidate)))
       (t (setq done t))))
    found))

(defun a3madkour-groceries--render (parts)
  "The grocery list's text, built from the registry and PARTS.
PARTS is what `a3madkour-groceries--sections' returns for the old text."
  (let* ((needs (a3madkour-groceries--needs
                 (a3madkour-groceries--planned (plist-get parts :recipes))))
         (table (cdr needs))
         (ticked '()) (strays '())
         (sections (append (mapcar (lambda (a) (cons a (a3madkour-groceries--heading a)))
                                   (a3madkour-ingredients/aisles))
                           (list (cons nil a3madkour-groceries--other)))))
    ;; An old item that is still needed keeps its tick.  One the registry
    ;; knows, or that some recipe lists, but that is no longer needed is gone.
    ;; Anything else was typed by the owner in the wrong place: it moves to
    ;; Extra, in the order it was written.
    (dolist (line (plist-get parts :lines))
      (pcase line
        (`(stray ,l) (push l strays))
        (`(item ,was-ticked ,text ,l)
         (let ((hit (a3madkour-groceries--resolve text table)))
           (cond ((and hit (gethash (car hit) table))
                  (when was-ticked (push (car hit) ticked)))
                 (hit)
                 ((a3madkour-groceries--recipe-item-p text))
                 (t (push l strays)))))))
    (setq strays (nreverse strays))
    (with-temp-buffer
      (insert "#+TITLE: Groceries\n\n")
      (dolist (section sections)
        (let ((items (cl-remove-if-not
                      (lambda (n) (equal (plist-get n :aisle) (car section)))
                      (car needs))))
          (when items
            (insert "* " (cdr section) "\n")
            (dolist (n items)
              (insert "- [" (if (member (plist-get n :key) ticked) "X" " ") "] "
                      (plist-get n :name)
                      (if (plist-get n :low) " (low)" ""))
              (when (plist-get n :recipes)
                (let ((amount (a3madkour-units/format
                               (a3madkour-units/sum
                                (plist-get n :amounts)
                                (plist-get (plist-get n :entry) :unit)))))
                  (insert " (" (if amount (concat amount ": ") "")
                          (string-join (plist-get n :recipes) ", ") ")")))
              (insert "\n")))))
      (insert "* " a3madkour-groceries--extra "\n")
      (dolist (l (append (plist-get parts :extra) strays))
        (insert l "\n"))
      (when (plist-get parts :recipes)
        (insert "* " a3madkour-groceries--recipes "\n")
        (dolist (l (plist-get parts :recipes))
          (insert l "\n")))
      (buffer-string))))

(defun a3madkour-groceries--count (text)
  "(:to-buy N :ticked M): TEXT's unticked and ticked checkbox lines."
  (let ((to-buy 0) (ticked 0))
    (dolist (l (split-string text "\n"))
      (when (string-match a3madkour-groceries--checkbox-re l)
        (if (a3madkour-groceries--ticked-p (match-string 2 l))
            (cl-incf ticked)
          (cl-incf to-buy))))
    (list :to-buy to-buy :ticked ticked)))

(defun a3madkour-groceries--buffer ()
  "The buffer visiting the grocery list, holding the newest text there is.
Ticks synced in from the phone under an unmodified buffer are reverted in.
Unsaved edits plus a newer file cannot both be kept: refuse."
  (let* ((file (a3madkour-groceries/file))
         (buf (or (get-file-buffer file)
                  (progn (make-directory (file-name-directory file) t)
                         (find-file-noselect file)))))
    (with-current-buffer buf
      (when (and (file-exists-p file)
                 (not (verify-visited-file-modtime buf)))
        (when (buffer-modified-p)
          (user-error "The grocery list has unsaved changes and the file changed on disk; save or revert it first"))
        (revert-buffer t t t)))
    buf))

(defun a3madkour-groceries--text ()
  "The grocery list's current text."
  (with-current-buffer (a3madkour-groceries--buffer)
    (save-restriction
      (widen)
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun a3madkour-groceries--rewrite (transform)
  "Replace the list's text with (TRANSFORM old-text), save, return the new text."
  (with-current-buffer (a3madkour-groceries--buffer)
    (save-restriction
      (widen)
      (let* ((old (buffer-substring-no-properties (point-min) (point-max)))
             (new (funcall transform old)))
        (unless (string= old new)
          (let ((line (line-number-at-pos)))
            (erase-buffer)
            (insert new)
            (goto-char (point-min))
            (forward-line (1- line))))
        (when (or (buffer-modified-p) (not (file-exists-p (buffer-file-name))))
          (set-buffer-modified-p t)
          (save-buffer))
        new))))

(defun a3madkour-groceries/refresh (&optional alter)
  "Rebuild the grocery list from the registry and its recipes, and save it.
ALTER, when given, is called with the old list's parts (see
`a3madkour-groceries--sections') and returns the parts to build from.
Return (:to-buy N :ticked M), counting every checkbox line on the list."
  (a3madkour-groceries--count
   (a3madkour-groceries--rewrite
    (lambda (old)
      (let ((parts (a3madkour-groceries--sections old)))
        (a3madkour-groceries--render (if alter (funcall alter parts) parts)))))))

(defun a3madkour-groceries/toggle-recipe (file)
  "Start or stop shopping for recipe FILE, and refresh the list.
Return non-nil when the recipe is now on the list."
  (let* ((title (or (a3madkour-recipes/title file)
                    (user-error "Not a recipe: %s" file)))
         (dir (file-name-directory (a3madkour-groceries/file)))
         (file (expand-file-name file))
         (now-planned nil))
    (a3madkour-groceries/refresh
     (lambda (parts)
       (let* ((lines (plist-get parts :recipes))
              (mine (lambda (l)
                      (and (string-match "\\[\\[file:\\([^]]+\\)\\]" l)
                           (string= (expand-file-name (match-string 1 l) dir) file))))
              (kept (cl-remove-if mine lines)))
         (setq now-planned (= (length kept) (length lines)))
         (plist-put (copy-sequence parts) :recipes
                    (if now-planned
                        (append lines
                                (list (format "- [[file:%s][%s]]"
                                              (file-relative-name file dir) title)))
                      kept)))))
    now-planned))

(defun a3madkour-groceries--conflict-note ()
  "\"; sync conflict copy: FILE\" when there is one, else the empty string."
  (let ((copies (a3madkour-groceries/conflict-files)))
    (if copies (concat "; sync conflict copy: " (car copies)) "")))

;;; Commands

;;;###autoload
(defun a3-grocery-list ()
  "Refresh the grocery list from the pantry and the planned recipes; open it."
  (interactive)
  (let ((counts (a3madkour-groceries/refresh)))
    (switch-to-buffer (a3madkour-groceries--buffer))
    (message "%s%s"
             (if (and (= 0 (plist-get counts :to-buy)) (= 0 (plist-get counts :ticked)))
                 "Nothing to buy"
               (format "%d to buy, %d ticked"
                       (plist-get counts :to-buy) (plist-get counts :ticked)))
             (a3madkour-groceries--conflict-note))))

;;;###autoload
(defun a3-grocery-plan-recipe (file)
  "Put recipe FILE's missing ingredients on the grocery list, or take them off.
In a recipe buffer that recipe is the default."
  (interactive
   (let* ((recipes (or (a3madkour-recipes/files)
                       (user-error "No recipes beside the ingredient registry")))
          (here (car (rassoc (and (buffer-file-name)
                                  (expand-file-name (buffer-file-name)))
                             recipes)))
          (title (completing-read
                  (if here (format "Recipe to shop for (default %s): " here)
                    "Recipe to shop for: ")
                  (mapcar #'car recipes) nil t nil nil here)))
     (list (cdr (assoc title recipes)))))
  (let ((title (a3madkour-recipes/title file)))
    (if (a3madkour-groceries/toggle-recipe file)
        (message "Shopping for %s: %d to buy" title
                 (plist-get (a3madkour-groceries--count (a3madkour-groceries--text))
                            :to-buy))
      (message "No longer shopping for %s" title))))

;;;###autoload
(defun a3-grocery-done ()
  "Close the shopping trip.
Ticked items become :have: in the registry: ingredients it knows, wherever on
the list they were ticked, and recipe items it did not know, which are added.
Every ticked line leaves the list, which is then refreshed."
  (interactive)
  (let* ((text (a3madkour-groceries--text))
         (parts (a3madkour-groceries--sections text))
         (table (cdr (a3madkour-groceries--needs
                      (a3madkour-groceries--planned (plist-get parts :recipes)))))
         (ticked (plist-get (a3madkour-groceries--count text) :ticked))
         (known '()) (new '()))
    (dolist (item (a3madkour-groceries--items parts))
      (when (car item)
        (let ((hit (a3madkour-groceries--resolve (nth 1 item) table)))
          (cond ((cdr hit) (cl-pushnew (plist-get (cdr hit) :name) known :test #'string=))
                (hit (cl-pushnew (plist-get (gethash (car hit) table) :name) new
                                 :test #'string=))))))
    ;; Under Extra only what the registry already knows counts.
    (dolist (l (plist-get parts :extra))
      (when (and (string-match a3madkour-groceries--checkbox-re l)
                 (a3madkour-groceries--ticked-p (match-string 2 l)))
        (let ((hit (a3madkour-groceries--resolve (match-string 3 l) nil)))
          (when (cdr hit)
            (cl-pushnew (plist-get (cdr hit) :name) known :test #'string=)))))
    (cond
     ((= 0 ticked) (message "Nothing is ticked"))
     ((y-or-n-p (format "Mark %d ticked item%s as bought? "
                        ticked (if (= 1 ticked) "" "s")))
      (let ((marked 0))
        (dolist (name known)
          (a3madkour-ingredients/set-entry-state name 'have)
          (cl-incf marked))
        (dolist (name new)
          ;; A name the registry cannot hold stays a recipe matter.
          (condition-case nil
              (progn (a3madkour-ingredients/add-entry name nil nil nil 'have)
                     (cl-incf marked))
            (user-error nil)))
        (a3madkour-groceries--rewrite
         (lambda (old)
           (mapconcat
            #'identity
            (cl-remove-if
             (lambda (l)
               (and (string-match a3madkour-groceries--checkbox-re l)
                    (a3madkour-groceries--ticked-p (match-string 2 l))))
             (split-string old "\n"))
            "\n")))
        (let ((counts (a3madkour-groceries/refresh)))
          (message "Marked %d as have; %d still to buy%s"
                   marked (plist-get counts :to-buy)
                   (a3madkour-groceries--conflict-note))))))))

(provide 'a3madkour-groceries)
;;; a3madkour-groceries.el ends here
