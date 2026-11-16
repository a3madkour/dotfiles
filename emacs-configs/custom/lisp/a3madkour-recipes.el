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

;;;###autoload
(defun a3-recipe-new (title)
  "Create an empty recipe titled TITLE and visit it.  Return its file name.
The file goes beside the ingredient registry, named after the title, and is
never written over an existing one.  Point is left in the first `item' cell."
  (interactive (list (read-string "Recipe title: ")))
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
    (make-directory dir t)
    ;; `excl': lose the race rather than overwrite a file that just synced in.
    (write-region (format a3madkour-recipes--skeleton (org-id-new) title)
                  nil file nil 'silent nil 'excl)
    (find-file file)
    (goto-char (point-min))
    (re-search-forward "^|-")
    (forward-line 1)
    (org-table-goto-column 3)
    file))

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
          (with-current-buffer (get-buffer-create "*Recipe problems*")
            (let ((inhibit-read-only t))
              (erase-buffer)
              (insert (string-join problems "\n") "\n"))
            (goto-char (point-min))
            (display-buffer (current-buffer)))
          (user-error "Not marked for publishing: %d problem%s (see *Recipe problems*)"
                      (length problems) (if (= 1 (length problems)) "" "s"))))
      (a3madkour-recipes--set-keyword "HUGO_PUBLISH" "t" "HUGO_SECTION")
      (save-buffer)
      (message "Marked for publishing: %s" title))))

(provide 'a3madkour-recipes)
;;; a3madkour-recipes.el ends here
