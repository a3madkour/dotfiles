;;; a3madkour-recipes.el --- recipe authoring commands  -*- lexical-binding: t; -*-

;;; Commentary:

;; Two commands for writing recipes in the format the recipes publish handler
;; and `a3madkour-recipe-lint' expect.
;;
;; `a3-recipe-new' creates an empty recipe beside the ingredient registry and
;; leaves point in the first `item' cell.  A new recipe is private
;; (#+HUGO_PUBLISH: nil): some recipes are only for cooking from and for the
;; grocery list, and a private recipe is never linted, so its blanks cost
;; nothing.  `a3-recipe-toggle-publish' marks a recipe for the website once
;; the linter is satisfied, or takes it private again.  It only marks; running
;; the publisher is a separate step.
;;
;; The keywords are written here rather than through `a3-publish-mark', which
;; needs the site's section contract and prompts for fields.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)
(require 'org-table)
(require 'a3madkour-ingredients)

(declare-function a3madkour-recipe-lint/lint-file "a3madkour-recipe-lint")

(defconst a3madkour-recipes--section "recipes"
  "The #+HUGO_SECTION: value that makes a file a recipe.")

(defconst a3madkour-recipes--skeleton
  ":PROPERTIES:
:ID:       %s
:servings:
:END:
#+TITLE: %s
#+HUGO_SECTION: recipes
#+HUGO_PUBLISH: nil
#+HUGO_SUMMARY:

** Ingredients
| qty | unit | item | group | note | alt |
|-----+------+------+-------+------+-----|
|     |      |      |       |      |     |
** Steps
1.
** Sources
-
"
  "A new recipe file; the two %s are its id and its title.")

(defun a3madkour-recipes--dir ()
  "The directory recipes live in: the one holding the ingredient registry."
  (file-name-directory
   (or a3madkour-ingredients/file
       (user-error "a3madkour-ingredients/file is not set"))))

(defun a3madkour-recipes--slug (title)
  "TITLE as a file name stem, or nil when nothing of it can be one.
Downcased, with every run of characters that are not letters or digits turned
into one hyphen: \"Mum's Shakshuka!\" is \"mum-s-shakshuka\"."
  (let ((slug (replace-regexp-in-string
               "\\`-+\\|-+\\'" ""
               (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase title)))))
    (unless (string-empty-p slug) slug)))

(defun a3madkour-recipes/new-file (title)
  "The file a new recipe titled TITLE goes in, as (TITLE . FILE).
TITLE comes back trimmed.  Signals a `user-error' for a title that cannot
name a file, or when that file already exists: nothing is ever overwritten."
  (let* ((dir (a3madkour-recipes--dir))
         (title (string-trim (or title "")))
         (slug nil) (file nil))
    (cond ((string-empty-p title) (user-error "Recipe title is empty"))
          ((string-match-p "\n" title)
           (user-error "A recipe title cannot span lines: %S" title)))
    (setq slug (or (a3madkour-recipes--slug title)
                   (user-error "Cannot make a file name from \"%s\"" title)))
    (setq file (expand-file-name (concat slug ".org") dir))
    (when (file-exists-p file)
      (user-error "A recipe file already exists: %s" file))
    (cons title file)))

(defun a3madkour-recipes/write-and-visit (file text)
  "Create FILE holding TEXT, visit it, and leave point in the first item cell."
  (make-directory (file-name-directory file) t)
  ;; `excl': lose the race rather than overwrite a file that just synced in.
  (write-region text nil file nil 'silent nil 'excl)
  (find-file file)
  (goto-char (point-min))
  (when (re-search-forward "^[ \t]*|[ \t]*qty[ \t]*|" nil t)
    (forward-line 1)
    (when (looking-at-p "[ \t]*|-") (forward-line 1))
    (when (looking-at-p "[ \t]*|")
      (org-table-goto-column 3)))
  file)

;;;###autoload
(defun a3-recipe-new (title)
  "Create an empty recipe titled TITLE and visit it.  Return its file name.
The file goes beside the ingredient registry, named after the title, and is
never written over an existing one.  Point is left in the first `item' cell."
  (interactive (list (read-string "Recipe title: ")))
  (let ((new (a3madkour-recipes/new-file title)))
    (a3madkour-recipes/write-and-visit
     (cdr new)
     (format a3madkour-recipes--skeleton (org-id-new) (car new)))))

;;; Reading the recipes beside the registry

(defun a3madkour-recipes--file-text (file)
  "FILE's text: from a buffer visiting it (unsaved edits count), else from disk."
  (let ((buf (get-file-buffer file)))
    (if buf
        (with-current-buffer buf
          (save-restriction
            (widen)
            (buffer-substring-no-properties (point-min) (point-max))))
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string)))))

(defun a3madkour-recipes--text-keyword (text key)
  "The trimmed value of the first #+KEY: line in TEXT, or nil."
  (let ((case-fold-search t))
    (when (string-match (format "^#\\+%s:\\(.*\\)$" (regexp-quote key)) text)
      (string-trim (match-string 1 text)))))

(defun a3madkour-recipes/title (file)
  "The title of recipe FILE, or nil when FILE is not a recipe.
A recipe is an org file whose #+HUGO_SECTION: is recipes, published or not."
  (when (and (file-regular-p file) (string-suffix-p ".org" file))
    (let ((text (a3madkour-recipes--file-text file)))
      (when (equal (a3madkour-recipes--text-keyword text "HUGO_SECTION")
                   a3madkour-recipes--section)
        (let ((title (a3madkour-recipes--text-keyword text "TITLE")))
          (if (or (null title) (string-empty-p title))
              (file-name-base file)
            title))))))

(defun a3madkour-recipes/files ()
  "Every recipe beside the registry, as (TITLE . FILE), sorted by title."
  (let ((dir (a3madkour-recipes--dir)) (out '()))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\`[^.].*\\.org\\'"))
        (unless (string-match-p "\\.sync-conflict-" file)
          (let ((title (a3madkour-recipes/title file)))
            (when title (push (cons title file) out))))))
    (sort out (lambda (a b) (string-lessp (downcase (car a)) (downcase (car b)))))))

(defun a3madkour-recipes/rows (file)
  "The ingredient rows of recipe FILE, as plists (:item :qty :unit).
Rows with an empty item are dropped; :qty and :unit are strings or nil."
  (let* ((rows (with-temp-buffer
                 (insert (a3madkour-recipes--file-text file))
                 (a3madkour-ingredients--recipe-rows)))
         (header (mapcar #'downcase (car rows)))
         (item-i (cl-position "item" header :test #'string=))
         (qty-i (cl-position "qty" header :test #'string=))
         (unit-i (cl-position "unit" header :test #'string=)))
    (cl-flet ((cell (row i)
                (let ((v (and i (nth i row))))
                  (and v (not (string-empty-p v)) v))))
      (when item-i
        (cl-loop for row in (cdr rows)
                 for item = (cell row item-i)
                 when item
                 collect (list :item item :qty (cell row qty-i) :unit (cell row unit-i)))))))

(defun a3madkour-recipes--keyword (key)
  "The trimmed value of the first #+KEY: line in the buffer, or nil."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward
               (format "^#\\+%s:\\(.*\\)$" (regexp-quote key)) nil t)
          (string-trim (match-string 1)))))))

(defun a3madkour-recipes--set-keyword (key value after)
  "Set the buffer's #+KEY: line to VALUE, adding it below #+AFTER: if absent."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (if (re-search-forward (format "^#\\+%s:.*$" (regexp-quote key)) nil t)
            (replace-match (format "#+%s: %s" key value) t t)
          (re-search-forward (format "^#\\+%s:.*$" (regexp-quote after)))
          (insert (format "\n#+%s: %s" key value)))))))

;;;###autoload
(defun a3-recipe-toggle-publish ()
  "Mark this recipe for the website, or take it private again.
Going public saves the buffer and runs the recipe linter: with problems they
are listed in *Recipe problems* and nothing changes."
  (interactive)
  (unless (and (derived-mode-p 'org-mode)
               (buffer-file-name)
               (equal (a3madkour-recipes--keyword "HUGO_SECTION")
                      a3madkour-recipes--section))
    (user-error "This buffer is not a recipe (no #+HUGO_SECTION: %s)"
                a3madkour-recipes--section))
  (let ((title (or (a3madkour-recipes--keyword "TITLE")
                   (file-name-base (buffer-file-name))))
        (public (let ((v (a3madkour-recipes--keyword "HUGO_PUBLISH")))
                  (and v (string-match-p "\\`[Tt]\\'" v)))))
    (if public
        (progn
          (a3madkour-recipes--set-keyword "HUGO_PUBLISH" "nil" "HUGO_SECTION")
          (save-buffer)
          (message "Private: %s" title))
      ;; The linter reads the file, so it must hold what is on screen.
      (save-buffer)
      (unless (fboundp 'a3madkour-recipe-lint/lint-file)
        (require 'a3madkour-recipe-lint))
      (let ((problems (a3madkour-recipe-lint/lint-file (buffer-file-name))))
        (when problems
          ;; A throwaway window along the bottom, as tall as the list;
          ;; `q' in it puts it away.
          (with-current-buffer (get-buffer-create "*Recipe problems*")
            (special-mode)
            (let ((inhibit-read-only t))
              (erase-buffer)
              (insert (string-join problems "\n") "\n"))
            (goto-char (point-min))
            (display-buffer (current-buffer)
                            '((display-buffer-reuse-window display-buffer-at-bottom)
                              (window-height . fit-window-to-buffer))))
          (user-error "Not marked for publishing: %d problem%s (see *Recipe problems*)"
                      (length problems) (if (= 1 (length problems)) "" "s"))))
      (a3madkour-recipes--set-keyword "HUGO_PUBLISH" "t" "HUGO_SECTION")
      (save-buffer)
      (message "Marked for publishing: %s" title))))

(provide 'a3madkour-recipes)
;;; a3madkour-recipes.el ends here
