;;; a3madkour-publish-citations.el --- F citation pipeline -*- lexical-binding: t; -*-

;;; Commentary:

;; F sub-project orchestrator.  Owns:
;;   - pre-export buffer rewriter: [cite:@key] → @@hugo:{{< cite "key" >}}@@
;;   - per-run cite-key accumulator
;;   - notes_ref auto-detection
;;   - data/citations.yaml emitter (merge-on-publish, purge-on-sync)
;;   - M-x a3-sync-citations command

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-element)
(require 'a3madkour-publish-bib)

(defvar a3madkour-pub-citations--accumulator nil
  "Hash table mapping cite-key (string) to list of (SOURCE-FILE . POS)
pairs, populated by the rewriter during the publish run.")

(defun a3madkour-pub-citations--accumulator-init ()
  "Allocate a fresh empty accumulator hash."
  (setq a3madkour-pub-citations--accumulator
        (make-hash-table :test 'equal :size 64)))

(defun a3madkour-pub-citations--in-noexport-p (cite tree)
  "Return non-nil iff CITE element is inside a heading marked :noexport:."
  (let ((node (org-element-property :parent cite)))
    (while (and node
                (not (and (eq (org-element-type node) 'headline)
                          (member "noexport"
                                  (org-element-property :tags node)))))
      (setq node (org-element-property :parent node)))
    node))

(defun a3madkour-pub-citations--scan-buffer ()
  "Walk the current org buffer via `org-element-parse-buffer'; return a
list of (KEY . POS) pairs for every citation element.  POS is the
buffer position of the element's `begin' marker.  Multi-cite forms
return one pair per key in source order.  Style-overrides (`/text',
`/noauthor', `/locators') and prefix/suffix text are NOT filtered here
— Task 9's rewriter checks those and signals."
  (let ((tree (org-element-parse-buffer))
        (acc nil))
    (org-element-map tree 'citation
      (lambda (cite)
        (unless (a3madkour-pub-citations--in-noexport-p cite tree)
          (let ((begin (org-element-property :begin cite)))
            (dolist (ref (org-element-map cite 'citation-reference #'identity))
              (let ((key (org-element-property :key ref)))
                (when (and key (not (string-empty-p key)))
                  (push (cons key begin) acc))))))))
    (nreverse acc)))

;; ---------------------------------------------------------------------
;; rewrite-cite-keys-in-buffer (Task 9)
;; ---------------------------------------------------------------------

(defun a3madkour-pub-citations--shortcode-for-keys (keys)
  "Build `@@hugo:{{< cite \"k1\" >}}{{< cite \"k2\" >}}@@' for KEYS."
  (concat "@@hugo:"
          (mapconcat (lambda (k) (format "{{< cite \"%s\" >}}" k)) keys "")
          "@@"))

(defun a3madkour-pub-citations--source-line-of (pos source-file)
  "Compute the 1-indexed line number of POS for error messages.
SOURCE-FILE is included in the returned `FILE:LINE' string."
  (format "%s:%d"
          source-file
          (save-excursion
            (goto-char pos)
            (line-number-at-pos))))

(defun a3madkour-pub-citations--non-empty-interpret (obj)
  "Return non-nil iff OBJ, interpreted via `org-element-interpret-data', is non-empty.
Guards against OBJ being a non-list (e.g. a propertized string in newer org)."
  (when obj
    (let ((text (condition-case nil
                    (org-element-interpret-data obj)
                  (error nil))))
      (and (stringp text) (not (string-empty-p (string-trim text)))))))

(defun a3madkour-pub-citations--check-supported-form (cite source-file)
  "Signal if CITE uses style override, prefix, or suffix.  Returns t on OK.
Checks both the citation-level and citation-reference-level prefix/suffix
properties, as their location varies between org-element versions."
  (let* ((style (org-element-property :style cite))
         (pos (org-element-property :begin cite))
         (loc (a3madkour-pub-citations--source-line-of pos source-file)))
    ;; Style override check.
    (when (and style (not (string-empty-p style)))
      (error "%s: cite/style not supported in V1: [cite/%s:...]\n  hint: V1 supports [cite:@key] and [cite:@k1;@k2]. Style overrides, prefix, and suffix are tracked as F-follow-up work; see docs/superpowers/specs/2026-06-01-phase-3-f-citation-pipeline-design.md §1 non-goals."
             loc style))
    ;; Prefix/suffix check on citation element.
    (when (or (a3madkour-pub-citations--non-empty-interpret
               (org-element-property :prefix cite))
              (a3madkour-pub-citations--non-empty-interpret
               (org-element-property :suffix cite)))
      (error "%s: cite prefix/suffix not supported in V1\n  hint: V1 supports [cite:@key] and [cite:@k1;@k2]. Style overrides, prefix, and suffix are tracked as F-follow-up work."
             loc))
    ;; Prefix/suffix check on each citation-reference child (newer org-element
    ;; stores per-reference prefix/suffix on the reference node, not the parent).
    (org-element-map cite 'citation-reference
      (lambda (ref)
        (when (or (a3madkour-pub-citations--non-empty-interpret
                   (org-element-property :prefix ref))
                  (a3madkour-pub-citations--non-empty-interpret
                   (org-element-property :suffix ref)))
          (error "%s: cite prefix/suffix not supported in V1\n  hint: V1 supports [cite:@key] and [cite:@k1;@k2]. Style overrides, prefix, and suffix are tracked as F-follow-up work."
                 loc))))
    t))

(defun a3madkour-pub-citations--strip-print-bibliography ()
  "Remove any `#+print_bibliography:' line from the current buffer."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^\\s-*#\\+print_bibliography:.*$" nil t)
      (replace-match "" nil t))))

(defun a3madkour-pub-citations/rewrite-cite-keys-in-buffer (source-file)
  "Walk current buffer for [cite:...] forms; rewrite each to
`@@hugo:{{< cite \"k\" >}}@@'; populate the run accumulator.
SOURCE-FILE is the original path, used for error messages and
accumulator provenance.  Fail-fast on the first error.

Validation runs in forward (source) order so error messages cite the
first problematic key as the author encounters it.  Rewriting runs in
reverse order so earlier rewrites don't corrupt the buffer positions
recorded by org-element-parse-buffer."
  (unless a3madkour-pub-citations--accumulator
    (a3madkour-pub-citations--accumulator-init))
  (a3madkour-pub-citations--strip-print-bibliography)
  ;; Collect citation elements in forward order.
  (let* ((tree (org-element-parse-buffer))
         (cites
          (org-element-map tree 'citation
            (lambda (cite)
              (let ((begin (org-element-property :begin cite))
                    (end   (org-element-property :end   cite)))
                (list :cite cite :begin begin :end end))))))
    ;; Pass 1: validate in source order (fail-fast on first error).
    (dolist (info cites)
      (let* ((cite  (plist-get info :cite))
             (begin (plist-get info :begin))
             (_     (a3madkour-pub-citations--check-supported-form cite source-file))
             (keys
              (org-element-map cite 'citation-reference
                (lambda (ref) (org-element-property :key ref)))))
        (dolist (k keys)
          (unless (a3madkour-pub-bib/resolve k)
            (error "%s: cite key %s not found in library.bib"
                   (a3madkour-pub-citations--source-line-of begin source-file)
                   k)))))
    ;; Pass 2: accumulate + rewrite in reverse order (preserves positions).
    (dolist (info (nreverse cites))
      (let* ((cite   (plist-get info :cite))
             (begin  (plist-get info :begin))
             (end    (plist-get info :end))
             (keys
              (org-element-map cite 'citation-reference
                (lambda (ref) (org-element-property :key ref)))))
        ;; Accumulate.
        (dolist (k keys)
          (let ((current (gethash k a3madkour-pub-citations--accumulator)))
            (puthash k (cons (cons source-file begin) current)
                     a3madkour-pub-citations--accumulator)))
        ;; Replace [cite:...] span with the shortcode wrapper.  The
        ;; org-element `end' property includes trailing whitespace; trim
        ;; back to just past the closing `]'.
        (save-excursion
          (goto-char end)
          (skip-chars-backward " \t\n\r")
          (let ((replace-end (point)))
            (delete-region begin replace-end)
            (goto-char begin)
            (insert (a3madkour-pub-citations--shortcode-for-keys keys))))))))

(provide 'a3madkour-publish-citations)

;;; a3madkour-publish-citations.el ends here
