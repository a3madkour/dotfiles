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
