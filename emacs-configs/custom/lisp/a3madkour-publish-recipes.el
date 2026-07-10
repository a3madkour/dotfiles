;;; a3madkour-publish-recipes.el --- recipes per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; Slice 2: recipes per-file publish handler.  Parses drawer metadata plus
;; the ** Ingredients (org table) / ** Steps / ** Sources subtrees, routes the
;; standard frontmatter fields through the `recipes' normalize branch, injects
;; the recipe-specific keys, and writes content/recipes/<slug>/index.md.
;; Structural peer of a3madkour-publish-research.el.

;;; Code:

(require 'cl-lib)
(require 'org-element)
(require 'a3madkour-publish)
(require 'a3madkour-publish-yaml)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)
(require 'a3madkour-recipe-lint)

(defcustom a3madkour-pub-recipes/section-dir-name "recipes"
  "Hugo content section directory name for recipes (relative to site root)."
  :type 'string :group 'a3madkour-pub)

(defun a3madkour-pub-recipes--warn (file fmt &rest args)
  "Emit a WARN with FILE context."
  (apply #'a3madkour-pub/warn "recipes" file fmt args))

(defun a3madkour-pub-recipes--find-heading-named (ast name)
  "First headline in AST whose raw value = NAME (case-insensitive), or nil."
  (cl-loop for hl in (org-element-map ast 'headline #'identity)
           for raw = (org-element-property :raw-value hl)
           when (and raw (string-equal (downcase raw) (downcase name)))
           return hl))

(defun a3madkour-pub-recipes--strip-data-subtrees (org-text)
  "Return ORG-TEXT with the ** Ingredients / ** Steps / ** Sources subtrees removed.
Re-parses after each deletion so element positions stay valid."
  (with-temp-buffer
    (insert org-text)
    (org-mode)
    (dolist (name '("ingredients" "steps" "sources"))
      (let* ((ast (org-element-parse-buffer))
             (hl (a3madkour-pub-recipes--find-heading-named ast name)))
        (when hl
          (delete-region (org-element-property :begin hl)
                         (org-element-property :end hl)))))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun a3madkour-pub-recipes--find-table-under (headline)
  "First table element under HEADLINE (one level into its section), or nil."
  (let ((section (cl-loop for child in (org-element-contents headline)
                          when (eq (org-element-type child) 'section) return child)))
    (when section
      (cl-loop for child in (org-element-contents section)
               when (eq (org-element-type child) 'table) return child))))

(defun a3madkour-pub-recipes--table-rows (table)
  "TABLE's standard rows as list-of-list-of-cell-strings (hlines skipped)."
  (cl-loop for row in (org-element-map table 'table-row #'identity)
           when (eq (org-element-property :type row) 'standard)
           collect (mapcar (lambda (cell)
                             (let ((c (car (org-element-contents cell))))
                               (cond ((stringp c) (string-trim c))
                                     ((null c) "")
                                     (t (string-trim
                                         (substring-no-properties
                                          (org-element-interpret-data c)))))))
                           (org-element-contents row))))

(defun a3madkour-pub-recipes--top-level-items (headline)
  "Direct `item' elements of the first plain-list under HEADLINE, in order."
  (let ((section (cl-loop for child in (org-element-contents headline)
                          when (eq (org-element-type child) 'section) return child)))
    (when section
      (let ((plain-list (cl-loop for child in (org-element-contents section)
                                 when (eq (org-element-type child) 'plain-list) return child)))
        (when plain-list
          (cl-loop for child in (org-element-contents plain-list)
                   when (eq (org-element-type child) 'item) collect child))))))

(defun a3madkour-pub-recipes--item-text (item)
  "Text of an ITEM's paragraph, org markup preserved, nested lists dropped."
  (string-trim
   (substring-no-properties
    (org-element-interpret-data
     (cl-remove-if (lambda (c) (eq (org-element-type c) 'plain-list))
                   (org-element-contents item))))))

(defconst a3madkour-pub-recipes--ingredient-cols
  '("qty" "unit" "item" "group" "note" "alt")
  "Expected ingredient-table columns (header row, any order).")

(defun a3madkour-pub-recipes--coerce-qty (raw)
  "Coerce a qty cell RAW to a number, or nil for empty/non-numeric.
Supports integers, decimals, and `a/b' fractions."
  (when (and raw (stringp raw))
    (let ((s (string-trim raw)))
      (cond
       ((string-empty-p s) nil)
       ((string-match "\\`\\([0-9]+\\)/\\([0-9]+\\)\\'" s)
        (/ (float (string-to-number (match-string 1 s)))
           (string-to-number (match-string 2 s))))
       ((string-match-p "\\`[0-9]+\\'" s) (string-to-number s))
       ((string-match-p "\\`[0-9]*\\.[0-9]+\\'" s) (string-to-number s))
       (t nil)))))

(defun a3madkour-pub-recipes--cell (row header col)
  "Value of column COL in ROW per HEADER, trimmed; nil when blank/absent."
  (let ((i (cl-position col header :test #'string-equal)))
    (when i
      (let ((v (nth i row)))
        (when (and v (not (string-empty-p (string-trim v)))) (string-trim v))))))

(cl-defun a3madkour-pub-recipes--parse-ingredients (ast file)
  "Parse the ** Ingredients table in AST → list of plists, or nil.
WARNs on heading-without-table."
  (let ((heading (a3madkour-pub-recipes--find-heading-named ast "ingredients")))
    (unless heading (cl-return-from a3madkour-pub-recipes--parse-ingredients nil))
    (let ((table (a3madkour-pub-recipes--find-table-under heading)))
      (unless table
        (a3madkour-pub-recipes--warn file "ingredients heading present but no table")
        (cl-return-from a3madkour-pub-recipes--parse-ingredients nil))
      (let* ((rows (a3madkour-pub-recipes--table-rows table))
             (header (mapcar #'downcase (car rows)))
             (data (cdr rows)))
        (cl-loop for row in data
                 collect (list :qty   (a3madkour-pub-recipes--coerce-qty
                                       (a3madkour-pub-recipes--cell row header "qty"))
                               :unit  (a3madkour-pub-recipes--cell row header "unit")
                               :item  (a3madkour-pub-recipes--cell row header "item")
                               :group (a3madkour-pub-recipes--cell row header "group")
                               :note  (a3madkour-pub-recipes--cell row header "note")
                               :alt   (a3madkour-pub-recipes--cell row header "alt")))))))

(defun a3madkour-pub-recipes--parse-steps (ast)
  "Parse ** Steps ordered list in AST → list of step strings, or nil."
  (let ((heading (a3madkour-pub-recipes--find-heading-named ast "steps")))
    (when heading
      (mapcar #'a3madkour-pub-recipes--item-text
              (a3madkour-pub-recipes--top-level-items heading)))))

(defun a3madkour-pub-recipes--parse-source-item (text)
  "Parse a source list-item TEXT into a plist (:name :url :note).
Forms: `[[url][name]] — note', `[[url][name]]', `name — note', `name'.
The org link is matched FIRST (its description may itself contain the em-dash
separator), then a trailing `— note' / ` -- note' is taken from the remainder."
  (let ((body (string-trim text)) (name nil) (url nil) (note nil) (tail nil))
    (cond
     ;; [[url][name]] ...tail
     ((string-match "\\`\\[\\[\\([^]]*\\)\\]\\[\\(.*?\\)\\]\\]" body)
      (setq url (match-string 1 body)
            name (match-string 2 body)
            tail (substring body (match-end 0))))
     ;; [[url]] ...tail
     ((string-match "\\`\\[\\[\\([^]]*\\)\\]\\]" body)
      (setq url (match-string 1 body)
            name (match-string 1 body)
            tail (substring body (match-end 0))))
     ;; plain text: no link
     (t (setq tail body)))
    (if name
        ;; Link already gave name/url; a trailing "— note" may remain in tail.
        (when (string-match "\\(?:—\\|--\\)[ \t]*\\(.+\\)\\'" tail)
          (setq note (string-trim (match-string 1 tail))))
      ;; No link: split the plain text on the first separator into name/note.
      (if (string-match "[ \t]+\\(?:—\\|--\\)[ \t]+\\(.+\\)\\'" tail)
          (setq name (string-trim (substring tail 0 (match-beginning 0)))
                note (string-trim (match-string 1 tail)))
        (setq name (string-trim tail))))
    (append (list :name name)
            (when url (list :url url))
            (when (and note (not (string-empty-p note))) (list :note note)))))

(defun a3madkour-pub-recipes--parse-sources (ast)
  "Parse ** Sources list in AST → list of source plists, or nil."
  (let ((heading (a3madkour-pub-recipes--find-heading-named ast "sources")))
    (when heading
      (mapcar (lambda (item)
                (a3madkour-pub-recipes--parse-source-item
                 (a3madkour-pub-recipes--item-text item)))
              (a3madkour-pub-recipes--top-level-items heading)))))

(defconst a3madkour-pub-recipes--drawer-map
  '(("SERVINGS"   servings      int)
    ("YIELD-UNIT" yield_unit    nil)
    ("PREP-TIME"  prep_minutes  int)
    ("COOK-TIME"  cook_minutes  int)
    ("TOTAL-TIME" total_minutes int)
    ("CUISINE"    cuisine       nil)
    ("CATEGORY"   category      nil)
    ("VIDEO"      video         nil)
    ("IMAGE"      image         nil))
  "Property-drawer KEY → (frontmatter-symbol coercion).  KEY is upcased.")

(defun a3madkour-pub-recipes--parse-property-lines (text)
  "Parse `:KEY: value' lines in TEXT → alist of (UPCASED-KEY . trimmed-VALUE)."
  (let ((out '()) (start 0))
    (while (string-match "^[ \t]*:\\([A-Za-z0-9_-]+\\):[ \t]*\\(.*?\\)[ \t]*$" text start)
      (push (cons (upcase (match-string 1 text)) (match-string 2 text)) out)
      (setq start (match-end 0)))
    (nreverse out)))

(defun a3madkour-pub-recipes--drawer-alist (ast)
  "Alist of (UPCASED-KEY . VALUE) from the recipe's :PROPERTIES: drawer.
Position-robust: org-element only tags a file-leading :PROPERTIES: block as a
`property-drawer' when it is the buffer's first element (before #+TITLE: etc.);
authored with keywords first, the same block parses as a generic `drawer'.  We
extract from the interpreted org text so drawer position no longer matters."
  (let ((text (substring-no-properties (org-element-interpret-data ast))))
    (when (string-match ":PROPERTIES:\\(\\(?:.\\|\n\\)*?\\):END:" text)
      (a3madkour-pub-recipes--parse-property-lines (match-string 1 text)))))

(defun a3madkour-pub-recipes--parse-metadata (ast)
  "Extract recipe-specific frontmatter keys from AST's property drawer.
Returns an alist; only present keys are included."
  (let* ((drawer (a3madkour-pub-recipes--drawer-alist ast))
         (out '()))
    (dolist (spec a3madkour-pub-recipes--drawer-map)
      (let* ((raw (cdr (assoc (car spec) drawer)))
             (sym (nth 1 spec))
             (coerce (nth 2 spec)))
        (when (and raw (not (string-empty-p (string-trim raw))))
          (setf (alist-get sym out)
                (if (eq coerce 'int) (string-to-number (string-trim raw))
                  (string-trim raw))))))
    ;; Derive total_minutes when absent but prep+cook both present.
    (when (and (not (assq 'total_minutes out))
               (assq 'prep_minutes out) (assq 'cook_minutes out))
      (setf (alist-get 'total_minutes out)
            (+ (alist-get 'prep_minutes out) (alist-get 'cook_minutes out))))
    out))

(defun a3madkour-pub-recipes--scalar (v)
  "Render V as a flow-map value: number bare, nil → null, string quoted."
  (cond ((null v) "null")
        ((numberp v) (format "%s" v))
        (t (format "\"%s\"" (a3madkour-pub/yaml-escape-scalar v)))))

(defun a3madkour-pub-recipes--render-ingredient (ing)
  "Render an ingredient plist ING as an inline YAML map.
Order: group qty unit item note alt.  qty/unit/item always; others when non-nil."
  (let ((parts '()))
    (when (plist-get ing :group) (push (format "group: %s" (a3madkour-pub-recipes--scalar (plist-get ing :group))) parts))
    (push (format "qty: %s"  (a3madkour-pub-recipes--scalar (plist-get ing :qty))) parts)
    (push (format "unit: %s" (a3madkour-pub-recipes--scalar (plist-get ing :unit))) parts)
    (push (format "item: %s" (a3madkour-pub-recipes--scalar (plist-get ing :item))) parts)
    (when (plist-get ing :note) (push (format "note: %s" (a3madkour-pub-recipes--scalar (plist-get ing :note))) parts))
    (when (plist-get ing :alt)  (push (format "alt: %s"  (a3madkour-pub-recipes--scalar (plist-get ing :alt))) parts))
    (format "{ %s }" (mapconcat #'identity (nreverse parts) ", "))))

(defun a3madkour-pub-recipes--render-source (src)
  "Render a source plist SRC as an inline YAML map.  name always; url/note when non-nil."
  (let ((parts (list (format "name: %s" (a3madkour-pub-recipes--scalar (plist-get src :name))))))
    (when (plist-get src :url)  (setq parts (append parts (list (format "url: %s" (a3madkour-pub-recipes--scalar (plist-get src :url)))))))
    (when (plist-get src :note) (setq parts (append parts (list (format "note: %s" (a3madkour-pub-recipes--scalar (plist-get src :note)))))))
    (format "{ %s }" (mapconcat #'identity parts ", "))))

(defun a3madkour-pub-recipes--render-block (label render-fn items)
  "Render `LABEL:' + a block sequence of ITEMS via RENDER-FN."
  (format "%s:\n%s" label
          (mapconcat (lambda (it) (concat "  - " (funcall render-fn it))) items "\n")))

(defun a3madkour-pub-recipes--key-hook (k v)
  "render-frontmatter KEY-HOOK for the three structured recipe keys."
  (cond
   ((eq k 'ingredients)
    (if (and v (listp v)) (a3madkour-pub-recipes--render-block "ingredients" #'a3madkour-pub-recipes--render-ingredient v) :omit))
   ((eq k 'sources)
    (if (and v (listp v)) (a3madkour-pub-recipes--render-block "sources" #'a3madkour-pub-recipes--render-source v) :omit))
   ((eq k 'steps)
    (if (and v (listp v))
        (format "steps:\n%s" (mapconcat (lambda (s) (format "  - \"%s\"" (a3madkour-pub/yaml-escape-scalar s))) v "\n"))
      :omit))))

(defun a3madkour-pub-recipes--render-frontmatter (alist)
  "Render ALIST as recipe frontmatter (structured keys via the key-hook)."
  (a3madkour-pub-yaml/render-frontmatter
   alist
   :key-hook #'a3madkour-pub-recipes--key-hook
   :value-fn #'a3madkour-pub-yaml/render-value))

(defun a3madkour-pub-recipes--assemble-frontmatter (ast normalized)
  "Merge NORMALIZED standard fields with recipe-specific keys parsed from AST."
  (let ((out (copy-alist normalized)))
    (dolist (cell (a3madkour-pub-recipes--parse-metadata ast))
      (setf (alist-get (car cell) out) (cdr cell)))
    (setf (alist-get 'ingredients out) (a3madkour-pub-recipes--parse-ingredients ast "recipe"))
    (setf (alist-get 'steps out) (a3madkour-pub-recipes--parse-steps ast))
    (setf (alist-get 'sources out) (a3madkour-pub-recipes--parse-sources ast))
    out))

(cl-defun a3madkour-pub-recipes/publish-recipe-file (file run &key on-done)
  "Publish a single recipe FILE to content/recipes/<slug>/index.md.
Pipeline: lint → parse → strip-subtrees → ox-hugo body export →
normalize standard fields → inject recipe keys → render → asset-copy →
write-if-different → record-publish."
  (ignore run)
  (condition-case _err
      (progn
        ;; Step 1: lint gate.
        (when a3madkour-recipe-lint-enabled
          (let ((errs (a3madkour-recipe-lint/lint-file file)))
            (when errs
              (error "a3madkour-pub-recipes: lint failed for %s:\n%s"
                     file (mapconcat #'identity errs "\n")))))
        (let* ((md        (a3madkour-pub/note-metadata file))
               (id        (plist-get md :id))
               (slug      (a3madkour-pub/note-slug file))
               (new-url   (a3madkour-pub/note-url file))
               (site-root (a3madkour-pub-yaml/site-root))
               (bundle-dir (expand-file-name
                            (format "content/%s/%s/"
                                    a3madkour-pub-recipes/section-dir-name slug)
                            site-root))
               (out-path   (expand-file-name "index.md" bundle-dir))
               ;; Parse the structured data from the ORIGINAL source.
               (src-ast    (with-temp-buffer
                             (insert-file-contents file) (org-mode)
                             (org-element-parse-buffer)))
               ;; Body export: rewrite links → strip data subtrees → ox-hugo.
               (tmp-src    (a3madkour-pub-rewrite/rewrite-to-tmp-file file id "a3-pub-recipes"))
               (exported   (unwind-protect
                               (progn
                                 (let ((stripped (a3madkour-pub-recipes--strip-data-subtrees
                                                  (with-temp-buffer
                                                    (insert-file-contents tmp-src)
                                                    (buffer-string)))))
                                   (with-temp-file tmp-src (insert stripped)))
                                 (a3madkour-pub-export/export-file tmp-src))
                             (when (file-exists-p tmp-src) (delete-file tmp-src))))
               ;; Normalize standard fields; P2.14 stable-date.
               (normalized (let ((a3madkour-pub-frontmatter--prior-last-modified
                                  (a3madkour-pub-history/recorded-last-modified id new-url)))
                             (a3madkour-pub-frontmatter/normalize
                              'recipes (plist-get exported :frontmatter) file)))
               (final-fm   (a3madkour-pub-recipes--assemble-frontmatter src-ast normalized))
               (body       (plist-get exported :body)))
          (a3madkour-pub/asset-validate-and-copy file bundle-dir id)
          (a3madkour-pub-yaml/write-if-different
           out-path
           (concat (a3madkour-pub-recipes--render-frontmatter final-fm) body))
          (a3madkour-pub-history/record-publish id new-url (or (plist-get md :state) 'live)
                                                :last-modified (alist-get 'lastmod final-fm)))
        (when on-done (funcall on-done 'ok)))
    (error
     (message "%s" (error-message-string _err))
     (when on-done (funcall on-done 'err)))))

(defun a3madkour-pub-recipes/planned-steps (_file)
  "Return rough step count for the recipes handler."
  3)

(provide 'a3madkour-publish-recipes)

;;; a3madkour-publish-recipes.el ends here
