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

;;; Entry point

(defun a3madkour-pub-research/publish-research-file (file)
  "Publish a single research FILE to content/research/<type>/<slug>/index.md.

Stub (Task 3): signature only; real implementation lands in Tasks 4-10."
  (ignore file)
  nil)

(provide 'a3madkour-publish-research)

;;; a3madkour-publish-research.el ends here
