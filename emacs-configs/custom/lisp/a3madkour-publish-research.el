;;; a3madkour-publish-research.el --- research per-page bundle handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; B.3: research per-page bundle handler.  Two cascade types share one
;; handler function: themes (research-themes) and questions
;; (research-questions).  Both emit per-page Hugo bundles at
;; content/research/<themes|questions>/<slug>/index.md.
;;
;; Internal branch on #+HUGO_SECTION: selects per-type frontmatter
;; normalizer + the outputs-table parse (question-only).  Everything
;; else — ox-hugo export, link-rewrite, asset-copy, write-if-different,
;; record-publish — is shared with garden.
;;
;; Registered into `a3madkour-pub-living--handlers' as two entries
;; (one per cascade type, both pointing at the same `publish-research-file'
;; entry point) by `a3madkour-publish-living'.

;;; Code:

(require 'cl-lib)
(require 'org-element)
(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)

;;; Task 7 — outputs-table parser

(defconst a3madkour-pub-research--output-kinds
  '("paper" "talk" "code")
  "Allowed kind values in the outputs table
(per check_research_fixtures.py:20 OUTPUT_KINDS).")

(defconst a3madkour-pub-research--output-cols
  '("kind" "title" "url" "year")
  "Required columns in the outputs table header row.")

(defun a3madkour-pub-research--warn (file fmt &rest args)
  "Emit a WARN message with FILE context."
  (apply #'message (concat "a3madkour-pub-research WARN [%s]: " fmt)
         (if file (file-name-nondirectory file) "unknown") args))

(defun a3madkour-pub-research--find-outputs-heading (ast)
  "Find the first headline in AST whose raw value matches 'Outputs' (case-insensitive).
Returns the headline element or nil."
  (cl-loop for hl in (org-element-map ast 'headline #'identity)
           for raw = (org-element-property :raw-value hl)
           when (and raw (string-equal (downcase raw) "outputs"))
           return hl))

(defun a3madkour-pub-research--find-table-under (headline)
  "Return the first table element under HEADLINE, or nil.
Org wraps headline body in a section element; we look one level into that
section rather than iterating HEADLINE's direct children."
  (let ((section (cl-loop for child in (org-element-contents headline)
                          when (eq (org-element-type child) 'section)
                          return child)))
    (when section
      (cl-loop for child in (org-element-contents section)
               when (eq (org-element-type child) 'table)
               return child))))

(defun a3madkour-pub-research--table-rows (table)
  "Return TABLE's data rows as list-of-list-of-cell-strings.
Skips horizontal-rule rows; the header row is the first standard row."
  (cl-loop for row in (org-element-map table 'table-row #'identity)
           when (eq (org-element-property :type row) 'standard)
           collect (mapcar (lambda (cell)
                             (let ((c (car (org-element-contents cell))))
                               (cond
                                ((stringp c) (string-trim c))
                                ((null c) "")
                                (t (string-trim
                                    (substring-no-properties
                                     (org-element-interpret-data c)))))))
                           (org-element-contents row))))

(defun a3madkour-pub-research--coerce-year (raw _file)
  "Coerce year RAW to int.  Float-trip to dodge octal trap on '08'/'09'."
  (when (and raw (stringp raw))
    (let ((cleaned (string-trim raw)))
      (when (string-match-p "^[0-9]+$" cleaned)
        (truncate (string-to-number cleaned))))))

(cl-defun a3madkour-pub-research--parse-outputs-table (ast file)
  "Parse the * Outputs table in AST.  Returns list of plists, or nil.
WARNs on heading-without-table, missing columns, unknown kinds.
Row order preserved.  See spec §6 for the table contract."
  (let ((heading (a3madkour-pub-research--find-outputs-heading ast)))
    (unless heading
      (cl-return-from a3madkour-pub-research--parse-outputs-table nil))
    (let ((table (a3madkour-pub-research--find-table-under heading)))
      (unless table
        (a3madkour-pub-research--warn file "outputs heading present but no table")
        (cl-return-from a3madkour-pub-research--parse-outputs-table nil))
      (let* ((rows (a3madkour-pub-research--table-rows table))
             (header (mapcar #'downcase (car rows)))
             (data-rows (cdr rows))
             (col-indices (mapcar (lambda (col)
                                    (cl-position col header :test #'string-equal))
                                  a3madkour-pub-research--output-cols))
             (results '()))
        ;; Verify all required columns present.
        (cl-loop for col in a3madkour-pub-research--output-cols
                 for idx in col-indices
                 unless idx
                 do (a3madkour-pub-research--warn
                     file "outputs table missing column %S" col))
        (when (memq nil col-indices)
          (cl-return-from a3madkour-pub-research--parse-outputs-table nil))
        ;; Build per-row plists.
        (dolist (row data-rows)
          (let* ((kind (nth (nth 0 col-indices) row))
                 (title (nth (nth 1 col-indices) row))
                 (url (nth (nth 2 col-indices) row))
                 (year-raw (nth (nth 3 col-indices) row))
                 (year (a3madkour-pub-research--coerce-year year-raw file)))
            (cond
             ((not (member kind a3madkour-pub-research--output-kinds))
              (a3madkour-pub-research--warn
               file "outputs row kind=%s not in %S; skipping"
               kind a3madkour-pub-research--output-kinds))
             (t
              (push (list :kind kind :title title :url url :year year) results)))))
        (when results (nreverse results))))))

;;; Task 8 — strip-outputs-subtree helper

(defun a3madkour-pub-research--strip-outputs-subtree (org-text)
  "Return ORG-TEXT with any top-level * Outputs subtree removed.
Case-insensitive heading match.  No-op if no Outputs heading found.

Pure-functional: operates on a temp buffer, returns the new string."
  (with-temp-buffer
    (insert org-text)
    (org-mode)
    (let* ((ast (org-element-parse-buffer))
           (heading (a3madkour-pub-research--find-outputs-heading ast)))
      (if (not heading)
          org-text
        (let ((begin (org-element-property :begin heading))
              (end (org-element-property :end heading)))
          (delete-region begin end)
          (buffer-substring-no-properties (point-min) (point-max)))))))

;;; Task 9 — rendering helpers (garden-parallel; private)

(defconst a3madkour-pub-research--date-re
  "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
  "Regex for bare YYYY-MM-DD date strings.
Emitted unquoted so PyYAML / Hugo parse them as native date objects.")

(defun a3madkour-pub-research--render-yaml-value (v)
  "Render V as a YAML value.  Lists of strings render as [...].
Lists must contain only strings; for structured lists (list of plists,
e.g. outputs), use `--render-outputs-yaml' instead."
  (cond
   ((null v)    "false")
   ((eq v t)    "true")
   ((and (stringp v)
         (string-match-p a3madkour-pub-research--date-re v))
    v)
   ((stringp v) (format "\"%s\"" v))
   ((numberp v) (format "%s" v))
   ((listp v)
    (unless (cl-every #'stringp v)
      (error "a3madkour-pub-research--render-yaml-value: list contains \
non-string element; caller must use --render-outputs-yaml for structured lists"))
    (format "[%s]"
            (mapconcat (lambda (s) (format "\"%s\"" s)) v ", ")))))

(defun a3madkour-pub-research--render-output-row (row)
  "Render a single output ROW plist as an inline YAML map.
ROW has keys :kind :title :url :year."
  (let ((kind  (plist-get row :kind))
        (title (plist-get row :title))
        (url   (plist-get row :url))
        (year  (plist-get row :year)))
    (format "{ kind: %s, title: %s, url: %s, year: %s }"
            (if kind kind "")
            (if title (format "\"%s\"" title) "\"\"")
            (if url (format "\"%s\"" url) "\"\"")
            (if year (format "%s" year) ""))))

(defun a3madkour-pub-research--render-outputs-yaml (outputs)
  "Render OUTPUTS (list of plists) as a YAML block sequence string.
Each item is `  - { kind: ..., title: ..., url: ..., year: ... }'.
Returns a multiline string starting with a newline (caller emits the key
`outputs:' without a value; the value is this string)."
  (mapconcat (lambda (row)
               (concat "  - " (a3madkour-pub-research--render-output-row row)))
             outputs "\n"))

(defun a3madkour-pub-research--render-frontmatter (alist)
  "Render ALIST as YAML frontmatter (alphabetical key order; deterministic).
Returns a string with leading/trailing `---' delimiters.
Handles the `outputs' key specially (block-sequence YAML)."
  (let* ((sorted (sort (copy-sequence alist)
                       (lambda (a b)
                         (string< (symbol-name (car a)) (symbol-name (car b))))))
         (lines (mapcar
                 (lambda (cell)
                   (let ((k (symbol-name (car cell)))
                         (v (cdr cell)))
                     (if (string= k "outputs")
                         (if (and v (listp v))
                             (format "outputs:\n%s" (a3madkour-pub-research--render-outputs-yaml v))
                           ;; nil or empty outputs: omit the key entirely — handled by filtering below.
                           nil)
                       (format "%s: %s" k
                               (a3madkour-pub-research--render-yaml-value v)))))
                 sorted)))
    (concat "---\n"
            (mapconcat #'identity (delq nil lines) "\n")
            "\n---\n")))

;;; Task 9 — site-root + bundle-dir helpers

(defun a3madkour-pub-research--site-root ()
  "Derive the Hugo site root from `a3madkour-pub/site-data-dir'.
Convention: site-data-dir is `<root>/data/'; site root is its parent."
  (file-name-as-directory
   (directory-file-name
    (file-name-directory
     (directory-file-name
      (file-name-as-directory a3madkour-pub/site-data-dir))))))

(defun a3madkour-pub-research--write-if-different (path content)
  "Write CONTENT to PATH only if it differs from existing on-disk content.
Returns t if a write happened, nil if no-op."
  (let ((existing (when (file-exists-p path)
                    (with-temp-buffer
                      (insert-file-contents path)
                      (buffer-string)))))
    (unless (string= existing content)
      (make-directory (file-name-directory path) t)
      (with-temp-file path (insert content))
      t)))

(defun a3madkour-pub-research--section-to-content-subdir (section-str)
  "Map SECTION-STR (e.g. \"research/themes\") to content subdir path.
Returns e.g. \"research/themes\".

The section string already encodes the nested path so this is identity,
but we centralize the mapping here for clarity and future-proofing."
  section-str)

(defun a3madkour-pub-research--section-to-normalize-sym (section-str)
  "Convert SECTION-STR (e.g. \"research/themes\") to the normalize-dispatch symbol.
\"research/themes\" → 'research-themes
\"research/questions\" → 'research-questions"
  (intern (replace-regexp-in-string "/" "-" section-str)))

;;; Task 9 — outputs injection into normalized alist

(defun a3madkour-pub-research--inject-outputs (alist outputs)
  "Set the `outputs' key in ALIST to OUTPUTS (a list of plists), or remove it.
Returns a new alist.  When OUTPUTS is nil, removes the `outputs' key.
When non-nil, sets it.  Does not modify ALIST in-place."
  (let ((out (copy-alist alist)))
    (setq out (assq-delete-all 'outputs out))
    (when outputs
      (push (cons 'outputs outputs) out))
    out))

;;; Task 9 — question-only: parse outputs from org source then strip subtree

(defun a3madkour-pub-research--question-outputs-from-file (file)
  "Parse the * Outputs table from FILE.  Returns list of output plists or nil.
Reads FILE into a temp buffer, activates `org-mode', parses AST."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (let ((ast (org-element-parse-buffer)))
      (a3madkour-pub-research--parse-outputs-table ast file))))

;;; Entry point

(defun a3madkour-pub-research/publish-research-file (file)
  "Publish a single research FILE to content/research/<type>/<slug>/index.md.

Pipeline (spec §3):
  pre-export-rewrite-links → outputs-parse (question-only) →
  strip-outputs-subtree (question-only) → export →
  inject-description → normalize → inject-outputs (question-only) →
  asset-copy → write-if-different → record-publish.

Two cascade types share this function; the internal branch on #+HUGO_SECTION:
selects the per-type normalizer symbol and controls whether the outputs
parse/strip steps run."
  (let* ((md        (a3madkour-pub/note-metadata file))
         (id        (plist-get md :id))
         (slug      (plist-get md :slug))
         (section   (plist-get md :section))   ; e.g. "research/themes"
         (new-url   (a3madkour-pub/note-url file))
         (site-root (a3madkour-pub-research--site-root))
         (content-subdir (a3madkour-pub-research--section-to-content-subdir section))
         (bundle-dir (expand-file-name
                      (format "content/%s/%s/" content-subdir slug)
                      site-root))
         (out-path   (expand-file-name "index.md" bundle-dir))
         (norm-sym   (a3madkour-pub-research--section-to-normalize-sym section))
         (question-p (string= section "research/questions"))
         ;; Step 1: For questions, parse outputs BEFORE the body is stripped.
         (outputs    (when question-p
                       (a3madkour-pub-research--question-outputs-from-file file)))
         ;; Step 2: pre-export rewrite.  For questions, we also need to strip
         ;; the outputs subtree from the file before ox-hugo sees it.
         (tmp-src    (a3madkour-pub-rewrite/rewrite-to-tmp-file
                      file id "a3-pub-research"))
         ;; Step 3: If question, strip outputs subtree from the temp source.
         ;; We do this by rewriting tmp-src in-place (new write to same path).
         (exported
          (unwind-protect
              (progn
                (when question-p
                  (let ((stripped (a3madkour-pub-research--strip-outputs-subtree
                                   (with-temp-buffer
                                     (insert-file-contents tmp-src)
                                     (buffer-string)))))
                    (with-temp-file tmp-src (insert stripped))))
                ;; Step 4: ox-hugo export.
                (a3madkour-pub-export/export-file tmp-src))
            ;; Always delete the tmp file.
            (when (file-exists-p tmp-src)
              (delete-file tmp-src))))
         ;; Step 5: inject description before normalize.
         (with-desc  (a3madkour-pub-frontmatter--inject-description
                      (plist-get exported :frontmatter) file))
         ;; Step 6: per-type normalize.
         (normalized (a3madkour-pub-frontmatter/normalize
                      norm-sym with-desc file))
         ;; Step 7 (question-only): inject parsed outputs into frontmatter.
         (final-fm   (a3madkour-pub-research--inject-outputs normalized outputs))
         (body       (plist-get exported :body)))
    ;; Step 8: asset copy.
    (a3madkour-pub/asset-validate-and-copy file bundle-dir)
    ;; Step 9: write bundle.
    (a3madkour-pub-research--write-if-different
     out-path
     (concat (a3madkour-pub-research--render-frontmatter final-fm) body))
    ;; Step 10: record publish.
    (a3madkour-pub-history/record-publish id new-url 'live)))

(provide 'a3madkour-publish-research)

;;; a3madkour-publish-research.el ends here
