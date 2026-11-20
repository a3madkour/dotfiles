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

(ert-deftest a3madkour-pub-recipes--parse-source-item-emdash-in-link ()
  "Regression: an em-dash INSIDE the link description must not be taken as the
note separator (the spec's own canonical source example)."
  (should (equal (a3madkour-pub-recipes--parse-source-item
                  "[[https://example.com/lorem][Example Cooking — Lorem]] — adapted")
                 '(:name "Example Cooking — Lorem" :url "https://example.com/lorem" :note "adapted")))
  (should (equal (a3madkour-pub-recipes--parse-source-item "[[https://x][A — B]]")
                 '(:name "A — B" :url "https://x"))))

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

(ert-deftest a3madkour-pub-recipes--parse-metadata ()
  (let* ((ast (a3madkour-pub-recipes-test--parse "
:PROPERTIES:
:servings:   4
:yield-unit: servings
:prep-time:  10
:cook-time:  25
:cuisine:    North African
:category:   Main
:video:      dQw4w9WgXcQ
:image:      hero.svg
:END:
Headnote.
* R
** Steps
1. x
"))
         (md (a3madkour-pub-recipes--parse-metadata ast)))
    (should (equal (alist-get 'servings md) 4))
    (should (equal (alist-get 'yield_unit md) "servings"))
    (should (equal (alist-get 'prep_minutes md) 10))
    (should (equal (alist-get 'cook_minutes md) 25))
    (should (equal (alist-get 'total_minutes md) 35))
    (should (equal (alist-get 'cuisine md) "North African"))
    (should (equal (alist-get 'category md) "Main"))
    (should (equal (alist-get 'video md) "dQw4w9WgXcQ"))
    (should (equal (alist-get 'image md) "hero.svg"))))

(ert-deftest a3madkour-pub-recipes--parse-metadata-minimal ()
  (let* ((ast (a3madkour-pub-recipes-test--parse
               ":PROPERTIES:\n:servings: 2\n:END:\nx\n"))
         (md (a3madkour-pub-recipes--parse-metadata ast)))
    (should (equal (alist-get 'servings md) 2))
    (should-not (assq 'total_minutes md))
    (should-not (assq 'cuisine md))))

(ert-deftest a3madkour-pub-recipes--parse-metadata-keywords-first ()
  "Regression: drawer AFTER #+TITLE:/#+HUGO_SUMMARY: still yields metadata
(org-element does not tag it `property-drawer'; extraction must be position-robust)."
  (let* ((ast (a3madkour-pub-recipes-test--parse "#+TITLE: Shakshuka
#+HUGO_SUMMARY: A dish.
:PROPERTIES:
:servings: 4
:cuisine: North African
:prep-time: 10
:cook-time: 25
:END:
Headnote.
** Steps
1. x
"))
         (md (a3madkour-pub-recipes--parse-metadata ast)))
    (should (equal (alist-get 'servings md) 4))
    (should (equal (alist-get 'cuisine md) "North African"))
    (should (equal (alist-get 'total_minutes md) 35))))

(ert-deftest a3madkour-pub-recipes--render-ingredient ()
  (should (equal (a3madkour-pub-recipes--render-ingredient
                  '(:qty 2 :unit "tbsp" :item "olive oil" :group "base" :note nil :alt nil))
                 "{ group: \"base\", qty: 2, unit: \"tbsp\", item: \"olive oil\" }"))
  (should (equal (a3madkour-pub-recipes--render-ingredient
                  '(:qty nil :unit nil :item "salt" :group nil :note "to taste" :alt nil))
                 "{ qty: null, unit: null, item: \"salt\", note: \"to taste\" }")))

(ert-deftest a3madkour-pub-recipes--render-source ()
  (should (equal (a3madkour-pub-recipes--render-source '(:name "NYT" :url "https://x" :note "adapted"))
                 "{ name: \"NYT\", url: \"https://x\", note: \"adapted\" }"))
  (should (equal (a3madkour-pub-recipes--render-source '(:name "Book"))
                 "{ name: \"Book\" }")))

(ert-deftest a3madkour-pub-recipes--render-frontmatter-blocks ()
  (let ((out (a3madkour-pub-recipes--render-frontmatter
              '((title . "Shakshuka")
                (servings . 4)
                (steps . ("Heat oil." "[02:30] Add tomatoes."))
                (ingredients . ((:qty 2 :unit "tbsp" :item "oil" :group nil :note nil :alt nil)))
                (sources . ((:name "NYT" :url "https://x" :note nil)))))))
    (should (string-match-p "steps:\n  - \"Heat oil.\"\n  - \"\\[02:30\\] Add tomatoes.\"" out))
    (should (string-match-p "ingredients:\n  - { qty: 2, unit: \"tbsp\", item: \"oil\" }" out))
    (should (string-match-p "sources:\n  - { name: \"NYT\", url: \"https://x\" }" out))
    (should (string-match-p "servings: 4" out))
    (should (string-match-p "title: \"Shakshuka\"" out))))

(ert-deftest a3madkour-pub-recipes--strip-subtrees ()
  (let ((out (a3madkour-pub-recipes--strip-data-subtrees "* R
Headnote paragraph.
** Ingredients
| qty | item |
| 1   | x    |
** Steps
1. Do it.
** Sources
- A book
")))
    (should (string-match-p "Headnote paragraph." out))
    (should-not (string-match-p "Ingredients" out))
    (should-not (string-match-p "Steps" out))
    (should-not (string-match-p "Sources" out))))

(ert-deftest a3madkour-pub-recipes--strip-drawer-keywords-first ()
  "Regression: the file-level :PROPERTIES: drawer (generic when keywords precede
it) must be stripped before ox-hugo export, so its lines don't leak into the body."
  (let ((out (a3madkour-pub-recipes--strip-data-subtrees "#+TITLE: R
#+HUGO_SUMMARY: y
:PROPERTIES:
:servings: 4
:cuisine: Example North
:END:
Headnote text here.
** Ingredients
#+NAME: ingredients
| qty | item |
| 1   | x    |
** Steps
1. do it
** Sources
- A book
")))
    (should (string-match-p "Headnote text here." out))
    (should-not (string-match-p ":servings:" out))
    (should-not (string-match-p ":PROPERTIES:" out))
    (should-not (string-match-p ":cuisine:" out))
    (should-not (string-match-p "Ingredients" out))))

(ert-deftest a3madkour-pub-recipes--assemble-frontmatter ()
  (let* ((ast (a3madkour-pub-recipes-test--parse "
:PROPERTIES:
:servings: 4
:cuisine: North African
:END:
Headnote.
** Ingredients
#+NAME: ingredients
| qty | unit | item | group | note | alt |
| 2   | tbsp | oil  | base  |      |     |
** Steps
1. [02:30] Add tomatoes.
** Sources
- [[https://x.test][NYT]] — adapted
"))
         (normalized '((title . "Shakshuka") (date . "2026-07-09")
                       (lastmod . "2026-07-09") (draft . nil)
                       (summary . "A dish.") (tags . ("example"))))
         (fm (a3madkour-pub-recipes--assemble-frontmatter ast normalized))
         (out (a3madkour-pub-recipes--render-frontmatter fm)))
    (should (equal (alist-get 'servings fm) 4))
    (should (equal (alist-get 'cuisine fm) "North African"))
    (should (= 1 (length (alist-get 'ingredients fm))))
    (should (equal (alist-get 'steps fm) '("[02:30] Add tomatoes.")))
    (should (string-match-p "ingredients:\n  - { group: \"base\", qty: 2" out))
    (should (string-match-p "sources:\n  - { name: \"NYT\", url: \"https://x.test\", note: \"adapted\" }" out))
    (should (string-match-p "servings: 4" out))))

(ert-deftest a3madkour-pub-recipes--copy-drawer-image-present ()
  "Copies a beside-source image into the bundle and returns non-nil."
  (let* ((dir (make-temp-file "recipe-img-" t))
         (src (expand-file-name "shakshuka.org" dir))
         (img (expand-file-name "hero.svg" dir))
         (bundle (expand-file-name "bundle/" dir)))
    (with-temp-file src (insert "x"))
    (with-temp-file img (insert "<svg/>"))
    (should (a3madkour-pub-recipes--copy-drawer-image src "hero.svg" bundle))
    (should (file-exists-p (expand-file-name "hero.svg" bundle)))))

(ert-deftest a3madkour-pub-recipes--copy-drawer-image-absent ()
  "Returns nil when the image file does not exist beside the source (caller omits the key)."
  (let* ((dir (make-temp-file "recipe-img-" t))
         (src (expand-file-name "shakshuka.org" dir))
         (bundle (expand-file-name "bundle/" dir)))
    (with-temp-file src (insert "x"))
    (should-not (a3madkour-pub-recipes--copy-drawer-image src "missing.svg" bundle))
    (should-not (a3madkour-pub-recipes--copy-drawer-image src nil bundle))))

(ert-deftest a3madkour-pub-recipes-test-publish-never-moves-body-images ()
  "Publishing a recipe never moves a body-linked image out of the recipes
folder, even with auto-remediation on: the image stays beside the recipe,
the recipe source is unchanged, and the asset walk warns instead.
Export, frontmatter and history are stubbed (they need the site's section
contract); the asset walk itself is the real one."
  (let* ((root (make-temp-file "a3-pub-recipes-assets-" t))
         (recipes (expand-file-name "recipes" root))
         (recipe (expand-file-name "toast.org" recipes))
         (image (expand-file-name "photo.png" recipes))
         (asset-root (expand-file-name "notes/assets" root))
         (site-root (expand-file-name "site" root))
         (orig-walk (symbol-function 'a3madkour-pub/asset-validate-and-copy))
         (a3madkour-pub-canonical-asset-root asset-root)
         (a3madkour-pub-asset-auto-remediate t)
         (a3madkour-recipe-lint-enabled nil)
         walk-result outcome before)
    (unwind-protect
        (progn
          (make-directory recipes t)
          (make-directory asset-root t)
          (with-temp-file image (insert "data"))
          (with-temp-file recipe
            (insert ":PROPERTIES:\n:ID: R1\n:END:\n#+TITLE: Toast\n"
                    "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: recipes\n\n"
                    "[[./photo.png][the toast]]\n"))
          (setq before (with-temp-buffer
                         (insert-file-contents-literally recipe)
                         (buffer-string)))
          (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
                     (lambda (_) '(:id "R1" :state live)))
                    ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "toast"))
                    ((symbol-function 'a3madkour-pub/note-url)
                     (lambda (_) "/recipes/toast/"))
                    ((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil))
                    ((symbol-function 'vc-backend) (lambda (_) nil))
                    ((symbol-function 'a3madkour-pub-yaml/site-root)
                     (lambda () site-root))
                    ((symbol-function 'a3madkour-pub-rewrite/rewrite-to-tmp-file)
                     (lambda (&rest _) (make-temp-file "a3-pub-recipes-tmp-" nil ".org")))
                    ((symbol-function 'a3madkour-pub-export/export-file)
                     (lambda (_) '(:frontmatter nil :body "body\n")))
                    ((symbol-function 'a3madkour-pub-history/recorded-last-modified)
                     (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-frontmatter/normalize)
                     (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-recipes--assemble-frontmatter)
                     (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-recipes--copy-drawer-image)
                     (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-recipes--render-frontmatter)
                     (lambda (_) ""))
                    ((symbol-function 'a3madkour-pub-yaml/write-if-different)
                     (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-history/record-publish)
                     (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
                     (lambda (&rest args)
                       (setq walk-result (apply orig-walk args)))))
            (a3madkour-pub-recipes/publish-recipe-file
             recipe nil :on-done (lambda (status) (setq outcome status))))
          (should (eq outcome 'ok))
          (should (file-exists-p image))
          (should-not (file-exists-p (expand-file-name "page/toast/photo.png" asset-root)))
          (should (equal before (with-temp-buffer
                                  (insert-file-contents-literally recipe)
                                  (buffer-string))))
          (should (cl-find-if (lambda (w) (string-match-p "out-of-canonical-root" w))
                              (plist-get walk-result :warnings))))
      (delete-directory root t))))
