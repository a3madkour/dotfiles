;;; compare-features-probe.el --- exercise the non-publish commands  -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by compare-features.sh, once per version of the code, inside a
;; sandbox whose HOME holds a COPY of the notes.  It calls the grocery,
;; ingredient, recipe, import, lint and library entry points and writes every
;; return value, message and resulting file to $A3_COMPARE_OUT, one "== step"
;; section each.  The script diffs the two outputs.
;;
;; It writes freely: every path it touches is under the sandbox HOME.  It
;; refuses to run anywhere else.
;;
;; Only names that are stable entry points are called.  An entry point missing
;; from one version shows up as an (ERROR ...) answer in that version's output,
;; which is itself a difference worth seeing.
;;
;; Randomness is removed: new org ids are numbered, "today" is fixed.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'pp)
(require 'org)
(require 'org-id)

(unless (getenv "A3_COMPARE_OUT")
  (error "compare-features-probe: run it through compare-features.sh"))
(unless (string-match-p "/run/home/?\\'" (expand-file-name "~"))
  (error "compare-features-probe: HOME is %s, not a compare sandbox"
         (expand-file-name "~")))

(defvar cfp-out (generate-new-buffer " *compare-features*"))
(defvar cfp-messages nil "Messages raised by the step being run, newest first.")
(defvar cfp-id-counter 0)

(advice-add 'org-id-new :override
            (lambda (&rest _) (format "probe-id-%04d" (cl-incf cfp-id-counter))))
(advice-add 'message :before
            (lambda (fmt &rest args)
              (when (stringp fmt)
                (ignore-errors (push (apply #'format-message fmt args) cfp-messages)))))
;; A prompt has no one to answer it: yes to every yes/no question.
(advice-add 'y-or-n-p :override (lambda (&rest _) t))
(advice-add 'yes-or-no-p :override (lambda (&rest _) t))

(defun cfp-emit (label value)
  "Append a section LABEL holding VALUE to the output."
  (with-current-buffer cfp-out
    (goto-char (point-max))
    (insert "== " label "\n"
            (cond ((stringp value) value)
                  ((hash-table-p value) (pp-to-string (cfp-hash value)))
                  (t (pp-to-string value))))
    (unless (bolp) (insert "\n"))))

(defun cfp-hash (table)
  "TABLE as an alist sorted by key, so its print form does not depend on order."
  (let (out)
    (maphash (lambda (k v) (push (cons k v) out)) table)
    (sort out (lambda (a b) (string-lessp (format "%s" (car a)) (format "%s" (car b)))))))

(defun cfp-plain (value)
  "VALUE with hash tables anywhere inside it turned into sorted alists."
  (cond ((hash-table-p value) (cfp-hash value))
        ((consp value) (cons (cfp-plain (car value)) (cfp-plain (cdr value))))
        (t value)))

(defmacro cfp-step (label &rest body)
  "Run BODY; record its value (or its error) and its messages under LABEL."
  (declare (indent 1))
  `(let ((cfp-label ,label)
         (cfp-messages nil))
     (cfp-emit cfp-label
               (cfp-plain
                (condition-case err (progn ,@body)
                  (error (list 'ERROR (error-message-string err))))))
     (when cfp-messages
       (cfp-emit (concat cfp-label " [messages]")
                 (string-join (reverse cfp-messages) "\n")))))

(defun cfp-file (file)
  "FILE's text on disk, or a marker when it does not exist."
  (if (file-exists-p file)
      (with-temp-buffer (insert-file-contents file) (buffer-string))
    "<no such file>"))

(defun cfp-rel (file)
  "FILE relative to the sandbox HOME."
  (file-relative-name file (expand-file-name "~")))

(defun cfp-head (file bytes)
  "The first BYTES of FILE."
  (with-temp-buffer
    (insert-file-contents file nil 0 bytes)
    (buffer-string)))

;;; Modules

(dolist (feature '(a3madkour-units a3madkour-ingredients a3madkour-recipes
                   a3madkour-recipe-lint a3madkour-groceries
                   a3madkour-recipe-import a3madkour-library-items
                   a3madkour-works-lint))
  (cfp-step (format "load %s" feature) (require feature) t))

(defvar a3madkour-ingredients/file)
(defvar a3madkour-library/notes-dir)

(defconst cfp-registry a3madkour-ingredients/file)
(defconst cfp-recipes-dir (file-name-directory cfp-registry))
(defconst cfp-recipe-files
  (cl-remove-if (lambda (f) (string-match-p "\\.sync-conflict-" f))
                (directory-files cfp-recipes-dir t "\\`[^.].*\\.org\\'")))
(defconst cfp-groceries (expand-file-name "groceries.org" cfp-recipes-dir))

;;; Units

(defconst cfp-quantities
  '("" "1" "2" "1/2" "1 1/2" "1½" "½" "0.5" "2.0" ".5" "1-2" "1 - 2" "1 to 2"
    "2–3" "-2" "a-2" "1 2" "abc" "a pinch" "1/0" "10" "1,5" " 3 " "3x"))
(defconst cfp-units
  '("" "tbsp" "Tbsp" "tablespoon" "tablespoons" "tsp" "cup" "cups" "g" "kg"
    "ml" "l" "oz" "lb" "lbs" "clove" "cloves" "loaf" "pinch" "can" "nonsense"))

(cfp-step "units: parse-qty"
  (mapcar (lambda (q) (cons q (condition-case err (a3madkour-units/parse-qty q)
                                (error (list 'ERROR (error-message-string err))))))
          cfp-quantities))
(cfp-step "units: canonical"
  (mapcar (lambda (u) (cons u (a3madkour-units/canonical u))) cfp-units))
(cfp-step "units: format-qty"
  (mapcar (lambda (q) (cons q (ignore-errors (a3madkour-units/format-qty q))))
          '(0 1 2 0.5 1.5 0.25 0.333 2.75 10 100.0)))

;;; Ingredient registry: reading

(cfp-step "registry: entries" (a3madkour-ingredients/entries))
(cfp-step "registry: aisles" (a3madkour-ingredients/aisles))
(cfp-step "registry: problems" (a3madkour-ingredients/problems))
(cfp-step "registry: conflict files"
  (mapcar #'cfp-rel (a3madkour-ingredients/conflict-files)))
(cfp-step "registry: normalize"
  (mapcar (lambda (s) (cons s (a3madkour-ingredients/normalize s)))
          '("Olive Oil" "  olive   oil " "Crème fraîche" "JALAPEÑO" "red-pepper"
            "Tomatoes" "" "1 egg")))

;;; Recipes: reading, linting

(cfp-step "recipes: files"
  (mapcar (lambda (c) (cons (car c) (cfp-rel (cdr c)))) (a3madkour-recipes/files)))

(dolist (file cfp-recipe-files)
  (let ((name (file-name-nondirectory file)))
    (cfp-step (format "recipe %s: title" name) (a3madkour-recipes/title file))
    (cfp-step (format "recipe %s: rows" name) (a3madkour-recipes/rows file))
    (cfp-step (format "recipe %s: items" name)
      (with-current-buffer (find-file-noselect file)
        (a3madkour-ingredients/recipe-items)))
    (cfp-step (format "recipe %s: unknown items" name)
      (with-current-buffer (find-file-noselect file)
        (a3madkour-ingredients/unknown-items)))
    (cfp-step (format "recipe %s: lint" name)
      (a3madkour-recipe-lint/lint-file file))
    (cfp-step (format "recipe %s: quantities and lookups" name)
      (mapcar (lambda (row)
                (list (plist-get row :item)
                      :qty (and (plist-get row :qty)
                                (ignore-errors
                                  (a3madkour-units/parse-qty (plist-get row :qty))))
                      :unit (and (plist-get row :unit)
                                 (a3madkour-units/canonical (plist-get row :unit)))
                      :entry (a3madkour-ingredients/lookup (plist-get row :item))))
              (ignore-errors (a3madkour-recipes/rows file))))))

(cfp-step "recipes: slugs"
  (mapcar (lambda (title) (cons title (a3madkour-recipes--slug title)))
          '("Toast" "Crème Brûlée!" "  Mac & Cheese  " "!!!" "A/B test" "عدس")))
(cfp-step "recipes: new-file (nothing written)"
  (let ((new (a3madkour-recipes/new-file "  Compare Probe Unwritten  ")))
    (cons (car new) (cfp-rel (cdr new)))))
(cfp-step "recipes: new-file refuses an existing recipe"
  (a3madkour-recipes/new-file "Toast"))

;;; Grocery list

(cfp-step "groceries: file" (cfp-rel (a3madkour-groceries/file)))
(cfp-step "groceries: text before" (cfp-file cfp-groceries))
(cfp-step "groceries: sections"
  (a3madkour-groceries--sections (cfp-file cfp-groceries)))
(cfp-step "groceries: needs"
  (let ((parts (a3madkour-groceries--sections (cfp-file cfp-groceries))))
    (a3madkour-groceries--needs
     (a3madkour-groceries--planned (plist-get parts :recipes)))))
(cfp-step "groceries: a3-grocery-list" (a3-grocery-list))
(cfp-step "groceries: text after a3-grocery-list" (cfp-file cfp-groceries))

(dolist (recipe (ignore-errors (a3madkour-recipes/files)))
  (cfp-step (format "groceries: plan %s" (car recipe))
    (a3-grocery-plan-recipe (cdr recipe)))
  (cfp-step (format "groceries: text after planning %s" (car recipe))
    (cfp-file cfp-groceries)))

(cfp-step "groceries: tick the first three items"
  (with-current-buffer (find-file-noselect cfp-groceries)
    (save-excursion
      (goto-char (point-min))
      (let ((n 0))
        (while (and (< n 3) (re-search-forward "^\\([ \t]*\\)- \\[ \\] " nil t))
          (replace-match "\\1- [X] ")
          (cl-incf n))
        (save-buffer)
        n))))
(cfp-step "groceries: a3-grocery-done" (a3-grocery-done))
(cfp-step "groceries: text after a3-grocery-done" (cfp-file cfp-groceries))
(cfp-step "registry: text after a3-grocery-done" (cfp-file cfp-registry))

(dolist (recipe (ignore-errors (a3madkour-recipes/files)))
  (cfp-step (format "groceries: unplan %s" (car recipe))
    (a3-grocery-plan-recipe (cdr recipe))))
(cfp-step "groceries: text after unplanning everything" (cfp-file cfp-groceries))

;;; Ingredient registry: writing

(cfp-step "registry: add-entry"
  (a3madkour-ingredients/add-entry "Zz compare probe" nil nil nil 'low))
(cfp-step "registry: add-entry again is refused"
  (a3madkour-ingredients/add-entry "Zz compare probe"))
(cfp-step "registry: add-alias"
  (a3madkour-ingredients/add-alias "Zz compare probe" "zz probe alias"))
(cfp-step "registry: lookup by alias" (a3madkour-ingredients/lookup "ZZ Probe Alias"))
(cfp-step "registry: set-entry-state"
  (a3madkour-ingredients/set-entry-state "Zz compare probe" 'out))
(cfp-step "registry: set-entry-state on an unknown name"
  (a3madkour-ingredients/set-entry-state "No such ingredient at all" 'have))
(cfp-step "registry: text after the edits" (cfp-file cfp-registry))
(cfp-step "groceries: a3-grocery-list with the probe item out" (a3-grocery-list))
(cfp-step "groceries: text with the probe item out" (cfp-file cfp-groceries))

;;; Recipe import and new recipes

(defconst cfp-ingredient-lines
  '("2 tbsp olive oil" "1 1/2 cups flour, sifted" "½ tsp salt" "1 (14 oz) can chickpeas"
    "3 large eggs" "Salt and pepper to taste" "1-2 cloves garlic, minced"
    "200g dark chocolate" "1 loaf sourdough" "a pinch of saffron" "2 x 400 ml coconut milk"
    "Juice of 1 lemon" "" "1 tablespoon &amp; 1 teaspoon sugar"))

(cfp-step "import: parse-ingredient"
  (mapcar (lambda (l) (cons l (condition-case err (a3madkour-recipe-import/parse-ingredient l)
                                (error (list 'ERROR (error-message-string err))))))
          cfp-ingredient-lines))

(defconst cfp-recipe-html
  "<html><head>
<script type=\"application/ld+json\">{\"@type\": \"WebSite\", \"name\": \"A blog\"}</script>
<script type=\"application/ld+json\">not json at all</script>
<script type=\"application/ld+json\">
{\"@context\": \"https://schema.org\", \"@graph\": [
 {\"@type\": \"Recipe\", \"name\": \"Probe Lentil Soup\",
  \"description\": \"A soup &amp; a test.\",
  \"recipeYield\": [\"4\", \"4 servings\"],
  \"prepTime\": \"PT10M\", \"cookTime\": \"PT1H5M\", \"totalTime\": \"PT1H15M\",
  \"recipeCuisine\": \"Indian\", \"recipeCategory\": [\"Soup\", \"Dinner\"],
  \"recipeIngredient\": [\"1 cup red lentils\", \"2 tbsp olive oil\",
                         \"1 (14 oz) can coconut milk\", \"Salt, to taste\"],
  \"recipeInstructions\": [
    {\"@type\": \"HowToStep\", \"text\": \"Rinse the lentils.\"},
    {\"@type\": \"HowToSection\", \"name\": \"Cook\", \"itemListElement\": [
      {\"@type\": \"HowToStep\", \"text\": \"Simmer 20 minutes.\"}]},
    \"Serve hot.\"]}]}
</script></head><body></body></html>")

(cfp-step "import: from-html" (a3madkour-recipe-import/from-html cfp-recipe-html))
(cfp-step "import: from-html without a recipe"
  (a3madkour-recipe-import/from-html "<html><body>nothing here</body></html>"))
(cfp-step "import: render"
  (a3madkour-recipe-import--render
   (a3madkour-recipe-import/from-html cfp-recipe-html)
   "Probe Lentil Soup" "https://example.invalid/soup"))
(cfp-step "import: create"
  (cfp-rel (a3madkour-recipe-import--create
            (a3madkour-recipe-import/from-html cfp-recipe-html)
            "Compare Probe Import" "https://example.invalid/soup")))
(cfp-step "import: created file"
  (cfp-file (expand-file-name "compare-probe-import.org" cfp-recipes-dir)))

(cfp-step "recipes: a3-recipe-new" (cfp-rel (a3-recipe-new "Compare Probe New")))
(cfp-step "recipes: new file"
  (cfp-file (expand-file-name "compare-probe-new.org" cfp-recipes-dir)))
(cfp-step "recipes: a3-recipe-new again is refused" (a3-recipe-new "Compare Probe New"))

;; Publish toggling, twice on every recipe: there and back again.
(dolist (file (directory-files cfp-recipes-dir t "\\`[^.].*\\.org\\'"))
  (when (ignore-errors (a3madkour-recipes/title file))
    (let ((name (file-name-nondirectory file)))
      (dotimes (i 2)
        (cfp-step (format "recipe %s: a3-recipe-toggle-publish (%d)" name (1+ i))
          (with-current-buffer (find-file-noselect file)
            (a3-recipe-toggle-publish)
            (when (get-buffer "*Recipe problems*")
              (prog1 (with-current-buffer "*Recipe problems*" (buffer-string))
                (kill-buffer "*Recipe problems*")))))
        (cfp-step (format "recipe %s: keywords after toggle (%d)" name (1+ i))
          (cfp-head file 600))))))

;;; Library items

(defconst cfp-library-files
  (sort (cl-remove-if-not
         (lambda (f) (ignore-errors (a3madkour-library/item-p f)))
         (directory-files-recursively a3madkour-library/notes-dir "\\.org\\'"))
        #'string-lessp))

(cfp-step "library: items" (mapcar #'cfp-rel cfp-library-files))
(cfp-step "library: shelves and statuses"
  (mapcar (lambda (m)
            (condition-case err
                (list m (a3madkour-library/shelf-for m)
                      (a3madkour-library/statuses m)
                      (a3madkour-library/in-progress-status m))
              (error (list m 'ERROR (error-message-string err)))))
          '("book" "album" "track" "game" "film" "series" "nonsense")))
(cfp-step "library: clean-tags"
  (a3madkour-library/clean-tags '("Machine_Learning" "book" "site" "noexport" "AI" "to read")))

(dolist (file cfp-library-files)
  (let ((name (file-name-nondirectory file)))
    (cfp-step (format "library %s: properties" name) (a3madkour-library/properties file))
    (cfp-step (format "library %s: preview" name) (a3madkour-library/preview file))
    (cfp-step (format "library %s: site body" name) (a3madkour-library/site-body file))
    (cfp-step (format "library %s: site-only copy" name)
      (let ((tmp (a3madkour-library/site-only-copy file)))
        (prog1 (cfp-file tmp) (delete-file tmp))))
    (cfp-step (format "library %s: set-status" name)
      (with-current-buffer (find-file-noselect file)
        (let* ((media (alist-get "media_type" (a3madkour-library/properties file)
                                 nil nil #'equal))
               (status (a3madkour-library/in-progress-status media)))
          (list (a3madkour-library/set-status status "2026-01-01")
                (a3madkour-library/set-status "finished" "2026-01-02")
                (progn (save-buffer) (cfp-head file 900))))))
    (cfp-step (format "library %s: set-status refuses nonsense" name)
      (with-current-buffer (find-file-noselect file)
        (a3madkour-library/set-status "no-such-status")))))

;;; Works linter: every note filed under works

(dolist (file (sort (directory-files-recursively (expand-file-name "~/org") "\\.org\\'")
                    #'string-lessp))
  (when (and (not (string-match-p "\\.sync-conflict-" file))
             (let ((case-fold-search t))
               (string-match-p "^[ \t]*#\\+hugo_section:[ \t]*works"
                               (cfp-head file 4000))))
    (cfp-step (format "works lint: %s" (cfp-rel file))
      (a3madkour-works-lint/lint-file file))))

;;; Done

(with-current-buffer cfp-out
  (let ((coding-system-for-write 'utf-8-unix))
    (write-region (point-min) (point-max) (getenv "A3_COMPARE_OUT") nil 'silent)))

;;; compare-features-probe.el ends here
