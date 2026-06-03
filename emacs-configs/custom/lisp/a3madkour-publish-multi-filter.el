;;; a3madkour-publish-multi-filter.el --- D.2 multi-export visibility + vocab filter -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared filter module for the D.2 multi-target export pipeline.
;; Provides: opt-in detection, visibility-tag filter, D.1 vocab translation.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'a3madkour-publish-keywords)

(defconst a3madkour-pub-multi-filter--opt-in-keyword "MULTI_EXPORT"
  "Org buffer-keyword that opts a document into the multi-export pipeline.")

(defun a3madkour-pub-multi-filter--doc-p ()
  "Return non-nil iff current buffer carries `#+multi_export: t'."
  (a3madkour-pub-keywords/boolean-p
   (a3madkour-pub-keywords/extract
    a3madkour-pub-multi-filter--opt-in-keyword)))

(defconst a3madkour-pub-multi-filter--skip-rules
  '((hugo   . ("NOEXPORT_WEB"  "PAPER_ONLY"))
    (md     . ("NOEXPORT_WEB"  "PAPER_ONLY"))
    (latex  . ("NOEXPORT_PDF"  "WEB_ONLY"))
    (pandoc . ("NOEXPORT_WORD" "WEB_ONLY" "PAPER_ONLY")))
  "Alist of backend → list of tag names whose subtrees must be dropped.
Stock `:noexport:' is dropped natively by each backend and is not listed.")

(defun a3madkour-pub-multi-filter--skip-tags-for (backend)
  "Return the list of tag names to drop for BACKEND, or nil if unknown."
  (cdr (assq backend a3madkour-pub-multi-filter--skip-rules)))

(defun a3madkour-pub-multi-filter--apply-visibility (backend)
  "Delete subtrees in the current buffer that are tagged for BACKEND skip.
No-op when BACKEND has no rules.  Iterates from last to first so deletions
do not invalidate the position of earlier subtrees."
  (let ((skip-tags (a3madkour-pub-multi-filter--skip-tags-for backend)))
    (when skip-tags
      (save-excursion
        (let (positions)
          (org-map-entries
           (lambda ()
             (let ((tags (org-get-tags nil t)))
               (when (cl-some (lambda (tag) (member tag tags)) skip-tags)
                 (push (point) positions)))))
          (dolist (pos (sort positions #'>))
            (goto-char pos)
            (let ((inhibit-message t))
              (org-cut-subtree))))))))

(defconst a3madkour-pub-multi-filter--vocab-kinds
  '("theorem" "lemma" "corollary" "proposition"
    "definition" "proof" "remark" "example" "note"
    "claim" "conjecture" "axiom")
  "D.1 semantic block kinds the filter recognizes.")

(defun a3madkour-pub-multi-filter--parse-attr-shortcode (attr-line)
  "Parse `:title T :id S' from ATTR-LINE (the value after `#+attr_shortcode: ').
Returns (cons TITLE-OR-NIL ID-OR-NIL)."
  (let ((title (when (string-match
                      ":title[ \t]+\\(\"\\([^\"]+\\)\"\\|\\([^ \t\n]+\\)\\)"
                      attr-line)
                 (or (match-string 2 attr-line) (match-string 3 attr-line))))
        (id (when (string-match ":id[ \t]+\\([^ \t\n]+\\)" attr-line)
              (match-string 1 attr-line))))
    (cons title id)))

(defun a3madkour-pub-multi-filter--translate-vocab (backend)
  "Walk current buffer; for each D.1 special block preceded by `#+attr_shortcode:',
rewrite that attr line into BACKEND-appropriate org annotations.
Note: `#+attr_shortcode:' must immediately precede `#+begin_<kind>' (no blank
line between).  This matches the D.1 attr_shortcode convention.

Uses the collect-then-mutate pattern (same as `--apply-visibility'): scan the
whole buffer first to gather match positions, then mutate from end to start.
Mutating inside the search loop interacts poorly with `re-search-forward'
point semantics when the search and replacement land adjacent in the buffer."
  (when (memq backend '(latex pandoc))
    (save-excursion
      (goto-char (point-min))
      (let (matches)
        (while (re-search-forward
                "^#\\+attr_shortcode:[ \t]+\\(.*\\)\n#\\+begin_\\([a-z]+\\)" nil t)
          (let ((kind (match-string 2)))
            (when (member kind a3madkour-pub-multi-filter--vocab-kinds)
              (push (list (match-beginning 0)
                          (save-excursion
                            (goto-char (match-beginning 0))
                            (forward-line 1)
                            (point))
                          (match-string 1)
                          kind)
                    matches))))
        (dolist (m matches)
          (let* ((start     (nth 0 m))
                 (end       (nth 1 m))
                 (attr-line (nth 2 m))
                 (kind      (nth 3 m))
                 (parsed    (a3madkour-pub-multi-filter--parse-attr-shortcode attr-line))
                 (title     (car parsed))
                 (id        (cdr parsed)))
            (goto-char start)
            (delete-region start end)
            (pcase backend
              ('latex
               (when title
                 (insert (format "#+attr_latex: :options [%s]\n" title)))
               (when id
                 (insert (format "#+name: %s\n" id))))
              ('pandoc
               (insert "#+attr_html:")
               (insert (format " :class %s" kind))
               (when id (insert (format " :id %s" id)))
               (when title (insert (format " :data-title \"%s\"" title)))
               (insert "\n")))))))))

(defun a3madkour-pub-multi-filter--rewrite-crossrefs (backend)
  "Rewrite [[#id][text]] org links for BACKEND.
LaTeX: emit `@@latex:\\hyperref[id]{text}@@' (export snippet so backslashes
are not escaped by `org-latex-plain-text').  Other backends: no-op."
  (when (eq backend 'latex)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "\\[\\[#\\([a-zA-Z0-9_-]+\\)\\]\\[\\([^]]+\\)\\]\\]" nil t)
        (replace-match (format "@@latex:\\hyperref[%s]{%s}@@"
                               (match-string 1) (match-string 2))
                       t t)))))

(defun a3madkour-pub-multi-filter--before-processing (backend)
  "`org-export-before-processing-functions' entry point.
Runs only when buffer is multi-export-opted-in.  Applies visibility + vocab + crossref.

`inhibit-modification-hooks' is bound around the mutations so org-element's
cache invalidation (`org-element--cache-before-change') does not fire on
every `delete-region' / `insert' — that handler does a wide `re-search-forward'
that can spin into an effective hang on non-trivial buffers."
  (when (a3madkour-pub-multi-filter--doc-p)
    (let ((inhibit-modification-hooks t))
      (a3madkour-pub-multi-filter--apply-visibility backend)
      (a3madkour-pub-multi-filter--translate-vocab backend)
      (a3madkour-pub-multi-filter--rewrite-crossrefs backend))))

(defun a3madkour-pub-multi-filter-install ()
  "Install the multi-export filter on `org-export-before-processing-functions' (idempotent)."
  (add-hook 'org-export-before-processing-functions
            #'a3madkour-pub-multi-filter--before-processing))

(a3madkour-pub-multi-filter-install)

(provide 'a3madkour-publish-multi-filter)
;;; a3madkour-publish-multi-filter.el ends here
