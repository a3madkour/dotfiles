;;; a3madkour-publish-recipes-test.el --- tests for recipes handler  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-recipes)

(defun a3madkour-pub-recipes-test--parse (org-text)
  "Parse ORG-TEXT and return its element AST."
  (with-temp-buffer (insert org-text) (org-mode) (org-element-parse-buffer)))

(ert-deftest a3madkour-pub-recipes--module-loads ()
  "Smoke: module loadable and exposes the entry point."
  (should (fboundp 'a3madkour-pub-recipes/publish-recipe-file)))

(ert-deftest a3madkour-pub-recipes--find-heading-and-table ()
  (let* ((ast (a3madkour-pub-recipes-test--parse "
* Recipe
** Ingredients
#+NAME: ingredients
| qty | item |
|-----+------|
|   2 | oil  |
** Steps
1. Do it.
"))
         (hl (a3madkour-pub-recipes--find-heading-named ast "ingredients"))
         (table (a3madkour-pub-recipes--find-table-under hl))
         (rows (a3madkour-pub-recipes--table-rows table)))
    (should hl)
    (should table)
    (should (equal (car rows) '("qty" "item")))
    (should (equal (nth 1 rows) '("2" "oil")))))

(ert-deftest a3madkour-pub-recipes--list-items ()
  (let* ((ast (a3madkour-pub-recipes-test--parse "
* Recipe
** Steps
1. First step.
2. [02:30] Second step.
"))
         (hl (a3madkour-pub-recipes--find-heading-named ast "steps"))
         (items (a3madkour-pub-recipes--top-level-items hl)))
    (should (= 2 (length items)))
    (should (equal (a3madkour-pub-recipes--item-text (nth 0 items)) "First step."))
    (should (equal (a3madkour-pub-recipes--item-text (nth 1 items)) "[02:30] Second step."))))
