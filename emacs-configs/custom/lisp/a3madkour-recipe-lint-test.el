;;; a3madkour-recipe-lint-test.el --- tests for the recipe linter  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-recipe-lint)

(defun a3madkour-recipe-lint-test--write (org-text)
  "Write ORG-TEXT to a temp .org file; return its path."
  (let ((f (make-temp-file "recipe-lint-" nil ".org")))
    (with-temp-file f (insert org-text)) f))

(defconst a3madkour-recipe-lint-test--good "#+TITLE: Shakshuka
#+HUGO_SUMMARY: A dish.
:PROPERTIES:
:servings: 4
:video: dQw4w9WgXcQ
:END:
Headnote.
** Ingredients
#+NAME: ingredients
| qty | unit | item | group | note | alt |
|-----+------+------+-------+------+-----|
| 2   | tbsp | oil  |       |      |     |
** Steps
1. [02:30] Add tomatoes.
** Sources
- A book
")

(ert-deftest a3madkour-recipe-lint--clean ()
  (let ((f (a3madkour-recipe-lint-test--write a3madkour-recipe-lint-test--good)))
    (unwind-protect (should-not (a3madkour-recipe-lint/lint-file f))
      (delete-file f))))

(ert-deftest a3madkour-recipe-lint--missing-steps ()
  (let ((f (a3madkour-recipe-lint-test--write "#+TITLE: X
#+HUGO_SUMMARY: y
:PROPERTIES:\n:servings: 2\n:END:
** Ingredients
#+NAME: ingredients
| qty | unit | item | group | note | alt |
| 1   |      | x    |       |      |     |
** Sources
- A
")))
    (unwind-protect
        (should (seq-some (lambda (m) (string-match-p "Steps" m))
                          (a3madkour-recipe-lint/lint-file f)))
      (delete-file f))))

(ert-deftest a3madkour-recipe-lint--bad-qty ()
  (let ((f (a3madkour-recipe-lint-test--write "#+TITLE: X
#+HUGO_SUMMARY: y
:PROPERTIES:\n:servings: 2\n:END:
** Ingredients
#+NAME: ingredients
| qty       | unit | item | group | note | alt |
| a couple  |      | x    |       |      |     |
** Steps
1. Do it.
** Sources
- A
")))
    (unwind-protect
        (should (seq-some (lambda (m) (string-match-p "qty" m))
                          (a3madkour-recipe-lint/lint-file f)))
      (delete-file f))))

(ert-deftest a3madkour-recipe-lint--bad-timecode ()
  (let ((f (a3madkour-recipe-lint-test--write "#+TITLE: X
#+HUGO_SUMMARY: y
:PROPERTIES:\n:servings: 2\n:END:
** Ingredients
#+NAME: ingredients
| qty | unit | item | group | note | alt |
| 1   |      | x    |       |      |     |
** Steps
1. [2:3] Bad.
** Sources
- A
")))
    (unwind-protect
        (should (seq-some (lambda (m) (string-match-p "\\[mm:ss\\]\\|timecode" m))
                          (a3madkour-recipe-lint/lint-file f)))
      (delete-file f))))

(ert-deftest a3madkour-recipe-lint--missing-summary ()
  (let ((f (a3madkour-recipe-lint-test--write "#+TITLE: X
:PROPERTIES:\n:servings: 2\n:END:
** Ingredients
#+NAME: ingredients
| qty | unit | item | group | note | alt |
| 1   |      | x    |       |      |     |
** Steps
1. Do it.
** Sources
- A
")))
    (unwind-protect
        (should (seq-some (lambda (m) (string-match-p "HUGO_SUMMARY\\|summary" m))
                          (a3madkour-recipe-lint/lint-file f)))
      (delete-file f))))

;;; Rule 7: every item is in the ingredient registry

(defmacro a3madkour-recipe-lint-test--with-registry (text &rest body)
  "Run BODY with the good recipe written to F (base name BASE) and
`a3madkour-ingredients/file' bound to a temp registry holding TEXT.
With TEXT nil the registry path is set but the file does not exist."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "ingr" t))
          (a3madkour-ingredients/file (expand-file-name "ingredients.org" dir))
          (f (a3madkour-recipe-lint-test--write a3madkour-recipe-lint-test--good))
          (base (file-name-nondirectory f)))
     (ignore base)
     (unwind-protect
         (progn (when ,text (with-temp-file a3madkour-ingredients/file (insert ,text)))
                ,@body)
       (delete-file f)
       (delete-directory dir t))))

(ert-deftest a3madkour-recipe-lint--registry-hit ()
  (a3madkour-recipe-lint-test--with-registry "* oil :have:\n"
    (should-not (a3madkour-recipe-lint/lint-file f))))

(ert-deftest a3madkour-recipe-lint--registry-alias-hit ()
  (a3madkour-recipe-lint-test--with-registry
      "* olive oil :have:\n:PROPERTIES:\n:ALIASES: oil\n:END:\n"
    (should-not (a3madkour-recipe-lint/lint-file f))))

(ert-deftest a3madkour-recipe-lint--registry-miss ()
  (a3madkour-recipe-lint-test--with-registry "* salt :have:\n"
    (should (equal (a3madkour-recipe-lint/lint-file f)
                   (list (format "%s:9: ingredient \"oil\" is not in the registry" base))))))

(ert-deftest a3madkour-recipe-lint--registry-empty-registry ()
  (a3madkour-recipe-lint-test--with-registry "#+TITLE: Ingredients\n#+TAGS: { have(h) low(l) out(o) }\n"
    (should (equal (a3madkour-recipe-lint/lint-file f)
                   (list (format "%s:9: ingredient \"oil\" is not in the registry" base))))))

(ert-deftest a3madkour-recipe-lint--registry-missing ()
  (a3madkour-recipe-lint-test--with-registry nil
    (should (equal (a3madkour-recipe-lint/lint-file f)
                   (list (format "%s:1: ingredient registry not found: %s"
                                 base a3madkour-ingredients/file))))))

(ert-deftest a3madkour-recipe-lint--registry-problem ()
  (a3madkour-recipe-lint-test--with-registry "* oil :have:\n* Oil :out:\n"
    (should (equal (a3madkour-recipe-lint/lint-file f)
                   '("ingredients.org:2: duplicate name \"oil\" (also line 1)")))))

(ert-deftest a3madkour-recipe-lint--registry-unset ()
  (let ((a3madkour-ingredients/file nil)
        (f (a3madkour-recipe-lint-test--write a3madkour-recipe-lint-test--good)))
    (unwind-protect (should-not (a3madkour-recipe-lint/lint-file f))
      (delete-file f))))

;; A recipe written by `a3-recipe-new' has the keyword, the headings and the
;; list bullets but nothing in them; none of that is publishable.
(defun a3madkour-recipe-lint-test--messages (from to)
  "Lint the good recipe with FROM replaced by TO, no registry.
Return the messages without their file:line prefix."
  (let ((f (a3madkour-recipe-lint-test--write
            (string-replace from to a3madkour-recipe-lint-test--good)))
        (a3madkour-ingredients/file nil))
    (unwind-protect
        (mapcar (lambda (m) (replace-regexp-in-string "\\`[^:]*:[0-9]+: " "" m))
                (a3madkour-recipe-lint/lint-file f))
      (delete-file f))))

(ert-deftest a3madkour-recipe-lint--blank-summary ()
  (should (equal (a3madkour-recipe-lint-test--messages " A dish." "")
                 '("empty #+HUGO_SUMMARY:"))))

(ert-deftest a3madkour-recipe-lint--blank-steps ()
  (dolist (steps '("1.\n" "1. \n2.\n" ""))
    (should (equal (a3madkour-recipe-lint-test--messages
                    "1. [02:30] Add tomatoes.\n" steps)
                   '("** Steps has no steps")))))

(ert-deftest a3madkour-recipe-lint--blank-sources ()
  (should (equal (a3madkour-recipe-lint-test--messages "- A book\n" "-\n")
                 '("** Sources has no list items"))))
