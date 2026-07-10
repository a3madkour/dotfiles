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

(ert-deftest a3madkour-pub-recipes--coerce-qty-forms ()
  (should (equal (a3madkour-pub-recipes--coerce-qty "2") 2))
  (should (equal (a3madkour-pub-recipes--coerce-qty "800") 800))
  (should (equal (a3madkour-pub-recipes--coerce-qty "0.5") 0.5))
  (should (equal (a3madkour-pub-recipes--coerce-qty "1/2") 0.5))
  (should (equal (a3madkour-pub-recipes--coerce-qty "") nil))
  (should (equal (a3madkour-pub-recipes--coerce-qty "  ") nil)))

(ert-deftest a3madkour-pub-recipes--parse-ingredients-happy ()
  (let* ((ast (a3madkour-pub-recipes-test--parse "
* R
** Ingredients
#+NAME: ingredients
| qty | unit | item      | group | note  | alt     |
|-----+------+-----------+-------+-------+---------|
|   2 | tbsp | olive oil | base  |       |         |
|   1 |      | onion     | base  | diced | shallot |
|     |      | salt      |       | taste |         |
"))
         (ings (a3madkour-pub-recipes--parse-ingredients ast "/tmp/x.org")))
    (should (= 3 (length ings)))
    (should (equal (plist-get (nth 0 ings) :qty) 2))
    (should (equal (plist-get (nth 0 ings) :unit) "tbsp"))
    (should (equal (plist-get (nth 0 ings) :item) "olive oil"))
    (should (equal (plist-get (nth 0 ings) :group) "base"))
    (should (equal (plist-get (nth 1 ings) :alt) "shallot"))
    (should (equal (plist-get (nth 1 ings) :note) "diced"))
    (should (equal (plist-get (nth 2 ings) :qty) nil))
    (should (equal (plist-get (nth 2 ings) :unit) nil))
    (should (equal (plist-get (nth 2 ings) :group) nil))
    (should (equal (plist-get (nth 2 ings) :note) "taste"))))

(ert-deftest a3madkour-pub-recipes--parse-ingredients-none ()
  (let ((ast (a3madkour-pub-recipes-test--parse "* R\n** Steps\n1. x\n")))
    (should-not (a3madkour-pub-recipes--parse-ingredients ast "/tmp/x.org"))))

(ert-deftest a3madkour-pub-recipes--parse-steps ()
  (let* ((ast (a3madkour-pub-recipes-test--parse "
* R
** Steps
1. Heat the oil.
2. [02:30] Add tomatoes.
"))
         (steps (a3madkour-pub-recipes--parse-steps ast)))
    (should (equal steps '("Heat the oil." "[02:30] Add tomatoes.")))))

(ert-deftest a3madkour-pub-recipes--parse-source-item-forms ()
  (should (equal (a3madkour-pub-recipes--parse-source-item "[[https://x.test][NYT]] — adapted")
                 '(:name "NYT" :url "https://x.test" :note "adapted")))
  (should (equal (a3madkour-pub-recipes--parse-source-item "[[https://x.test][NYT]]")
                 '(:name "NYT" :url "https://x.test")))
  (should (equal (a3madkour-pub-recipes--parse-source-item "Grandma's notebook")
                 '(:name "Grandma's notebook")))
  (should (equal (a3madkour-pub-recipes--parse-source-item "Some book — p. 40")
                 '(:name "Some book" :note "p. 40"))))

(ert-deftest a3madkour-pub-recipes--parse-sources ()
  (let* ((ast (a3madkour-pub-recipes-test--parse "
* R
** Sources
- [[https://x.test][NYT]] — adapted
- Grandma's notebook
"))
         (srcs (a3madkour-pub-recipes--parse-sources ast)))
    (should (= 2 (length srcs)))
    (should (equal (plist-get (nth 0 srcs) :url) "https://x.test"))
    (should (equal (plist-get (nth 1 srcs) :name) "Grandma's notebook"))))
