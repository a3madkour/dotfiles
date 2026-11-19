;;; a3madkour-recipes-test.el --- tests for recipe authoring commands  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'a3madkour-recipes)

(defmacro a3madkour-recipes-test--with (&rest body)
  "Run BODY with the registry path bound inside a fresh temp recipes dir.
Buffers visiting files in that dir are killed afterwards."
  (declare (indent 0))
  `(let* ((dir (file-name-as-directory (make-temp-file "recipes" t)))
          (a3madkour-ingredients/file (expand-file-name "ingredients.org" dir)))
     (unwind-protect
         (cl-letf (((symbol-function 'org-id-new) (lambda (&rest _) "TEST-ID")))
           ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (string-prefix-p dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory dir t))))

(defun a3madkour-recipes-test--text (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defconst a3madkour-recipes-test--skeleton ":PROPERTIES:
:ID:       TEST-ID
:servings:
:END:
#+TITLE: Mum's Shakshuka!
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
")

(ert-deftest a3madkour-recipes--slug ()
  (should (equal (a3madkour-recipes--slug "Mum's Shakshuka!") "mum-s-shakshuka"))
  (should (equal (a3madkour-recipes--slug "  Crème   Fraîche 2 ") "crème-fraîche-2"))
  (should-not (a3madkour-recipes--slug " !?! ")))

(ert-deftest a3madkour-recipes--new-writes-the-skeleton ()
  (a3madkour-recipes-test--with
    (let ((file (a3-recipe-new " Mum's Shakshuka! ")))
      (should (equal file (expand-file-name "mum-s-shakshuka.org" dir)))
      (should (equal (a3madkour-recipes-test--text file) a3madkour-recipes-test--skeleton))
      ;; The new file is the current buffer, saved, with point in the first
      ;; (empty) item cell, where ingredient completion works.
      (should (equal (buffer-file-name) file))
      (should-not (buffer-modified-p))
      (should (derived-mode-p 'org-mode))
      (let ((cell (a3madkour-ingredients--item-cell)))
        (should cell)
        (should (string-blank-p (buffer-substring (car cell) (cdr cell))))
        (should (= (line-number-at-pos) 13))))))

(ert-deftest a3madkour-recipes--new-refuses ()
  (a3madkour-recipes-test--with
    (should (equal (cadr (should-error (a3-recipe-new "  ") :type 'user-error))
                   "Recipe title is empty"))
    (should-error (a3-recipe-new "two\nlines") :type 'user-error)
    (should (equal (cadr (should-error (a3-recipe-new "!!") :type 'user-error))
                   "Cannot make a file name from \"!!\""))
    ;; An existing file is never overwritten.
    (let ((file (expand-file-name "toast.org" dir)))
      (with-temp-file file (insert "mine"))
      (should (equal (cadr (should-error (a3-recipe-new "Toast") :type 'user-error))
                     (concat "A recipe file already exists: " file)))
      (should (equal (a3madkour-recipes-test--text file) "mine"))
      (should-not (get-file-buffer file))))
  (let ((a3madkour-ingredients/file nil))
    (should (equal (cadr (should-error (a3-recipe-new "Toast") :type 'user-error))
                   "a3madkour-ingredients/file is not set"))))

(ert-deftest a3madkour-recipes--new-creates-the-recipes-dir ()
  (a3madkour-recipes-test--with
    (let ((a3madkour-ingredients/file (expand-file-name "sub/ingredients.org" dir)))
      (should (file-exists-p (a3-recipe-new "Toast"))))))

(defmacro a3madkour-recipes-test--linting (problems &rest body)
  "Run BODY with the recipe linter stubbed to return PROBLEMS."
  (declare (indent 1))
  `(let ((linted '()) (said nil))
     (ignore said)
     (cl-letf (((symbol-function 'a3madkour-recipe-lint/lint-file)
                (lambda (f) (push f linted) ,problems))
               ((symbol-function 'message)
                (lambda (fmt &rest args) (setq said (apply #'format fmt args)))))
       ,@body)))

(ert-deftest a3madkour-recipes--toggle-publishes-a-clean-recipe ()
  (a3madkour-recipes-test--with
    (let ((file (a3-recipe-new "Toast")))
      (a3madkour-recipes-test--linting nil
        (a3-recipe-toggle-publish)
        (should (equal linted (list file)))
        (should (equal said "Marked for publishing: Toast"))
        (should (string-match-p "^#\\+HUGO_PUBLISH: t$" (a3madkour-recipes-test--text file)))
        (should-not (buffer-modified-p))
        ;; And back; going private needs no lint.
        (a3-recipe-toggle-publish)
        (should (equal linted (list file)))
        (should (equal said "Private: Toast"))
        (should (string-match-p "^#\\+HUGO_PUBLISH: nil$" (a3madkour-recipes-test--text file)))))))

(ert-deftest a3madkour-recipes--toggle-keeps-a-recipe-with-problems-private ()
  (a3madkour-recipes-test--with
    (let ((file (a3-recipe-new "Toast")))
      (insert "typed but not saved")
      (a3madkour-recipes-test--linting '("toast.org:1: missing or non-positive :servings:"
                                         "toast.org:16: ** Sources has no list items")
        (should (equal (cadr (should-error (a3-recipe-toggle-publish) :type 'user-error))
                       "Not marked for publishing: 2 problems (see *Recipe problems*)"))
        ;; The buffer was saved first, so the linter saw what is on screen.
        (should (string-match-p "typed but not saved" (a3madkour-recipes-test--text file)))
        (should (string-match-p "^#\\+HUGO_PUBLISH: nil$" (a3madkour-recipes-test--text file)))
        (should (equal (with-current-buffer "*Recipe problems*" (buffer-string))
                       "toast.org:1: missing or non-positive :servings:\ntoast.org:16: ** Sources has no list items\n"))
        ;; A throwaway buffer: read-only, and `q' puts its window away.
        (with-current-buffer "*Recipe problems*"
          (should (derived-mode-p 'special-mode))
          (should buffer-read-only))))))

(ert-deftest a3madkour-recipes--toggle-adds-a-missing-publish-line ()
  (a3madkour-recipes-test--with
    (let ((file (expand-file-name "old.org" dir)))
      (with-temp-file file (insert "#+title: Old\n#+hugo_section: recipes\n\n** Ingredients\n"))
      (find-file file)
      (a3madkour-recipes-test--linting nil
        (a3-recipe-toggle-publish)
        (should (equal (a3madkour-recipes-test--text file)
                       "#+title: Old\n#+hugo_section: recipes\n#+HUGO_PUBLISH: t\n\n** Ingredients\n"))))))

(ert-deftest a3madkour-recipes--toggle-refuses-what-is-not-a-recipe ()
  (a3madkour-recipes-test--with
    (let ((file (expand-file-name "note.org" dir)))
      (with-temp-file file (insert "#+TITLE: Note\n#+HUGO_SECTION: garden\n"))
      (find-file file)
      (a3madkour-recipes-test--linting nil
        (should (equal (cadr (should-error (a3-recipe-toggle-publish) :type 'user-error))
                       "This buffer is not a recipe (no #+HUGO_SECTION: recipes)"))
        (should-not linted)))
    (with-temp-buffer
      (should-error (a3-recipe-toggle-publish) :type 'user-error))))

(ert-deftest a3madkour-recipes--a-filled-in-skeleton-passes-the-linter ()
  "The real linter accepts what the command writes, once the blanks are filled."
  (skip-unless (and (locate-library "yaml") (locate-library "a3madkour-recipe-lint")))
  (require 'a3madkour-recipe-lint)
  (a3madkour-recipes-test--with
    (with-temp-file a3madkour-ingredients/file (insert "* oil :have:\n"))
    (let ((file (a3-recipe-new "Toast")))
      ;; Untouched, it is not publishable: every blank is named.
      (should (equal (sort (mapcar (lambda (m)
                                     (replace-regexp-in-string "\\`[^:]*:[0-9]+: " "" m))
                                   (a3madkour-recipe-lint/lint-file file))
                           #'string<)
                     '("** Sources has no list items"
                       "** Steps has no steps"
                       "empty #+HUGO_SUMMARY:"
                       "ingredient row missing item"
                       "missing or non-positive :servings:")))
      (dolist (edit '((":servings:" . ":servings: 2")
                      ("#+HUGO_SUMMARY:" . "#+HUGO_SUMMARY: Bread, heated.")
                      ("|     |      |      |       |      |     |" . "| 1 | tbsp | oil | | | |")
                      ("\n1.\n" . "\n1. Toast it.\n")
                      ("\n-\n" . "\n- A book\n")))
        (goto-char (point-min))
        (search-forward (car edit))
        (replace-match (cdr edit) t t))
      (save-buffer)
      (should-not (a3madkour-recipe-lint/lint-file file)))))

(provide 'a3madkour-recipes-test)
;;; a3madkour-recipes-test.el ends here
