;;; a3madkour-recipe-import-test.el --- tests for recipe import  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'a3madkour-recipe-import)

(defun a3madkour-recipe-import-test--split (line)
  (let ((p (a3madkour-recipe-import/parse-ingredient line)))
    (list (plist-get p :qty) (plist-get p :unit) (plist-get p :item) (plist-get p :note))))

(ert-deftest a3madkour-recipe-import--parse-ingredient ()
  (dolist (case '(("2 tablespoons olive oil, divided" "2" "tbsp" "olive oil" "divided")
                  ("1 ½ Tbsp curry powder* (DIY for best flavor)" "1.5" "tbsp" "curry powder" "DIY for best flavor")
                  ("1½ cups flour" "1.5" "cup" "flour" nil)
                  ("1/4 tsp. sea salt" "0.25" "tsp" "sea salt" nil)
                  ("2-3 cups chopped kale or baby spinach" "3" "cup" "chopped kale or baby spinach" "2-3")
                  ("1 medium yellow onion, diced (about 240 g)" "1" nil "yellow onion" "diced; medium; about 240 g")
                  ("4 cloves garlic, minced" "4" "cloves" "garlic" "minced")
                  ("1 (14.5-oz.) can diced tomatoes" "1" "can" "diced tomatoes" "14.5-oz.")
                  ("200 g of feta" "200" "g" "feta" nil)
                  ("1 Tbsp coconut oil ((or olive oil // if oil-free, sub water))" "1" "tbsp" "coconut oil" "or olive oil // if oil-free, sub water")
                  ("1 Tbsp coconut sugar ( optional )" "1" "tbsp" "coconut sugar" "optional")
                  ("1 (15-oz.) can chickpeas, drained and rinsed (1 can yields ~1 ½ cups)" "1" "can" "chickpeas" "drained and rinsed; 15-oz.; 1 can yields ~1 ½ cups")
                  ("3 eggs" "3" nil "eggs" nil)
                  ("Freshly chopped cilantro" nil nil "Freshly chopped cilantro" nil)
                  ("Salt &amp; pepper, to taste" nil nil "Salt & pepper" "to taste")
                  ("1 cup <b>milk</b> | cream" "1" "cup" "milk | cream" nil)
                  ("" nil nil nil nil)))
    (should (equal (a3madkour-recipe-import-test--split (car case)) (cdr case)))))

(defconst a3madkour-recipe-import-test--html "<html><head>
<script type=\"application/ld+json\">{\"@type\": \"WebSite\", \"name\": \"A blog\"}</script>
<script type=\"application/ld+json\">not json at all</script>
<script class=\"x\" type='application/ld+json'>
{\"@context\": \"https://schema.org\", \"@graph\": [
 {\"@type\": \"Article\", \"name\": \"About soup\"},
 {\"@type\": [\"Recipe\", \"Thing\"],
  \"name\": \"Lentil &amp; Kale Soup\",
  \"description\": \"A <em>hearty</em>\\nsoup.\",
  \"recipeYield\": [\"6\", \"6 servings\"],
  \"prepTime\": \"PT15M\", \"cookTime\": \"PT1H5M\", \"totalTime\": \"PT1H20M\",
  \"recipeCuisine\": [\"Indian-Inspired\", \"Vegan\"],
  \"recipeCategory\": \"Soup\",
  \"recipeIngredient\": [\"1 Tbsp coconut oil\", \"2 medium carrots, peeled\", \" \", \"Lemon juice\"],
  \"recipeInstructions\": [
    {\"@type\": \"HowToSection\", \"name\": \"Pot\", \"itemListElement\": [
      {\"@type\": \"HowToStep\", \"text\": \"Heat the <a href='x'>pot</a>.\"},
      {\"@type\": \"HowToStep\", \"text\": \"Add everything.\"}]},
    {\"@type\": \"HowToStep\", \"text\": \"Serve.\"},
    \"Eat.\"]}]}
</script></head><body>prose</body></html>")

(ert-deftest a3madkour-recipe-import--from-html ()
  (let ((r (a3madkour-recipe-import/from-html a3madkour-recipe-import-test--html)))
    (should (equal (plist-get r :title) "Lentil & Kale Soup"))
    (should (equal (plist-get r :summary) "A hearty soup."))
    (should (equal (plist-get r :servings) "6"))
    (should (equal (list (plist-get r :prep) (plist-get r :cook) (plist-get r :total))
                   '(15 65 80)))
    (should (equal (plist-get r :cuisine) "Indian-Inspired"))
    (should (equal (plist-get r :category) "Soup"))
    (should (equal (plist-get r :ingredients)
                   '("1 Tbsp coconut oil" "2 medium carrots, peeled" "Lemon juice")))
    (should (equal (plist-get r :steps)
                   '("Heat the pot ." "Add everything." "Serve." "Eat."))))
  ;; Instructions as one string; a page with no recipe.
  (should (equal (plist-get (a3madkour-recipe-import/from-html
                             "<script type=\"application/ld+json\">{\"@type\":\"Recipe\",\"name\":\"X\",\"recipeInstructions\":\"One.\\nTwo.\"}</script>")
                            :steps)
                 '("One." "Two.")))
  (should-not (a3madkour-recipe-import/from-html "<html><body>Just words.</body></html>"))
  (should-not (a3madkour-recipe-import/from-html a3madkour-recipe-import-test--html-no-recipe)))

(defconst a3madkour-recipe-import-test--html-no-recipe
  "<script type=\"application/ld+json\">{\"@type\": \"WebSite\", \"name\": \"A blog\"}</script>")

(defmacro a3madkour-recipe-import-test--with (&rest body)
  (declare (indent 0))
  `(let* ((dir (file-name-as-directory (make-temp-file "import" t)))
          (a3madkour-ingredients/file (expand-file-name "ingredients.org" dir))
          (said nil))
     (ignore said)
     (unwind-protect
         (cl-letf (((symbol-function 'org-id-new) (lambda (&rest _) "TEST-ID"))
                   ((symbol-function 'message)
                    (lambda (fmt &rest args) (setq said (apply #'format fmt args)))))
           (with-temp-file a3madkour-ingredients/file
             (insert "* coconut oil :have:\n* carrots :out:\n"))
           ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b) (string-prefix-p dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory dir t))))

(defun a3madkour-recipe-import-test--text (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest a3madkour-recipe-import--import-writes-a-private-recipe ()
  (a3madkour-recipe-import-test--with
    (let ((asked nil))
      (cl-letf (((symbol-function 'a3madkour-recipe-import--fetch)
                 (lambda (url) (setq asked url) a3madkour-recipe-import-test--html)))
        (let ((file (a3-recipe-import "https://example.com/soup/")))
          (should (equal asked "https://example.com/soup/"))
          (should (equal file (expand-file-name "lentil-kale-soup.org" dir)))
          (should (equal (a3madkour-recipe-import-test--text file) ":PROPERTIES:
:ID:       TEST-ID
:servings: 6
:prep-time: 15
:cook-time: 65
:total-time: 80
:cuisine: Indian-Inspired
:category: Soup
:END:
#+TITLE: Lentil & Kale Soup
#+HUGO_SECTION: recipes
#+HUGO_PUBLISH: nil
#+HUGO_SUMMARY: A hearty soup.

** Ingredients
| qty | unit | item        | group | note           | alt |
|-----+------+-------------+-------+----------------+-----|
|   1 | tbsp | coconut oil |       |                |     |
|   2 |      | carrots     |       | peeled; medium |     |
|     |      | Lemon juice |       |                |     |
** Steps
1. Heat the pot .
2. Add everything.
3. Serve.
4. Eat.
** Sources
- [[https://example.com/soup/][example.com]]
"))
          (should (equal (buffer-file-name) file))
          (should (a3madkour-ingredients--item-cell))
          (should (equal said "Imported Lentil & Kale Soup: 3 ingredients, 1 not in the registry (resolve them with a3-ingredient-resolve-recipe)"))
          ;; It reads back as a recipe, private.
          (should (equal (a3madkour-recipes/title file) "Lentil & Kale Soup"))
          (should (equal (mapcar (lambda (r) (plist-get r :item)) (a3madkour-recipes/rows file))
                         '("coconut oil" "carrots" "Lemon juice")))
          ;; A second import of the same recipe overwrites nothing.
          (let ((before (a3madkour-recipe-import-test--text file)))
            (should-error (a3-recipe-import "https://example.com/soup/") :type 'user-error)
            (should (equal (a3madkour-recipe-import-test--text file) before))))))))

(ert-deftest a3madkour-recipe-import--import-refuses ()
  (a3madkour-recipe-import-test--with
    (let ((fetched nil))
      (cl-letf (((symbol-function 'a3madkour-recipe-import--fetch)
                 (lambda (_url) (setq fetched t) "<html>nothing here</html>")))
        (should (equal (cadr (should-error (a3-recipe-import "ftp://x") :type 'user-error))
                       "Not a web address: ftp://x"))
        (should-not fetched)
        (should (equal (cadr (should-error (a3-recipe-import "https://example.com/a") :type 'user-error))
                       "No recipe data found at https://example.com/a"))
        (should (equal (directory-files dir nil "\\.org\\'") '("ingredients.org")))
        ;; No registry path: refused before anything is fetched.
        (setq fetched nil)
        (let ((a3madkour-ingredients/file nil))
          (should-error (a3-recipe-import "https://example.com/a") :type 'user-error))
        (should-not fetched)))))

(defconst a3madkour-recipe-import-test--org-chef "* Something else
* Curried Lentil Soup (Indian-Inspired)
:PROPERTIES:
:source-url: https://example.com/curried-lentil-soup/
:servings:
:prep-time:
:END:
** Ingredients

- 1   Tbsp   coconut oil   (or olive oil)
- 2   medium   carrots, peeled and chopped
- Lemon juice
** Directions

1. Turn it on.
2. Serve.
* After
- 9 cups nothing
")

(ert-deftest a3madkour-recipe-import--org-chef-entry ()
  (a3madkour-recipe-import-test--with
    (let ((src (expand-file-name "cookbook.org" dir)))
      (with-temp-file src (insert a3madkour-recipe-import-test--org-chef))
      (find-file src)
      (goto-char (point-min))
      (search-forward "Turn it on")
      (let ((file (a3-recipe-import-org-chef)))
        (should (equal file (expand-file-name "curried-lentil-soup-indian-inspired.org" dir)))
        (should (equal (a3madkour-recipe-import-test--text file) ":PROPERTIES:
:ID:       TEST-ID
:servings:
:END:
#+TITLE: Curried Lentil Soup (Indian-Inspired)
#+HUGO_SECTION: recipes
#+HUGO_PUBLISH: nil
#+HUGO_SUMMARY:

** Ingredients
| qty | unit | item        | group | note                       | alt |
|-----+------+-------------+-------+----------------------------+-----|
|   1 | tbsp | coconut oil |       | or olive oil               |     |
|   2 |      | carrots     |       | peeled and chopped; medium |     |
|     |      | Lemon juice |       |                            |     |
** Steps
1. Turn it on.
2. Serve.
** Sources
- [[https://example.com/curried-lentil-soup/][example.com]]
"))
        ;; The original entry is untouched.
        (should (equal (a3madkour-recipe-import-test--text src)
                       a3madkour-recipe-import-test--org-chef))))
    ;; Somewhere with no ingredients list.
    (find-file (expand-file-name "cookbook.org" dir))
    (goto-char (point-min))
    (should-error (a3-recipe-import-org-chef) :type 'user-error)))

(provide 'a3madkour-recipe-import-test)
;;; a3madkour-recipe-import-test.el ends here
