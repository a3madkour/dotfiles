;;; a3madkour-publish-multi.el --- D.2 multi-target export orchestrator -*- lexical-binding: t; -*-

;;; Commentary:

;; D.2 orchestrator.  Dispatches PDF + Word backends with `condition-case'
;; isolation, then patches the Hugo bundle's frontmatter with the resulting
;; downloads dict.  Auto-trigger from B.4's after-essay-publish hook lands
;; in Task 14.
;;
;; Carry-forward 1 (Task 6 review): `#+EXPORT_FILE_NAME:' alignment.
;; The PDF backend dispatches against a prepared copy of the source that
;; pins the keyword to slug, so ox-latex's output filename always matches.
;;
;; Carry-forward 2 (Task 11 review): nil bib-path guard.
;; `--invoke-pandoc' in multi-word.el skips `--bibliography' when bib-path
;; is nil or empty, so no opaque pandoc error when source has no citations.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish-multi-filter)
(require 'a3madkour-publish-multi-pdf)
(require 'a3madkour-publish-multi-word)

(defcustom a3madkour-pub-multi-templates-dir nil
  "Directory containing `madkour-paper.cls', `reference.docx', `d2-blocks.lua'.
When nil, resolves to `<SITE_ROOT>/tools/templates/' via
`a3madkour-pub-essays--site-root'."
  :type '(choice (const :tag "Auto from site-root" nil) directory)
  :group 'a3madkour-pub-multi)

(defun a3madkour-pub-multi--templates-dir ()
  "Return the templates directory absolute path with trailing slash."
  (or a3madkour-pub-multi-templates-dir
      (file-name-as-directory
       (expand-file-name "tools/templates"
                         (a3madkour-pub-essays--site-root)))))

(defun a3madkour-pub-multi--bib-path ()
  "Return the bibliography path from F.1's defcustom, or nil if missing/unreadable.
Reads `a3madkour-pub-bib/library-path' with a `boundp' guard so this module
loads even when the F.1 bib module is not on load-path."
  (when (and (boundp 'a3madkour-pub-bib/library-path)
             a3madkour-pub-bib/library-path
             (file-readable-p a3madkour-pub-bib/library-path))
    a3madkour-pub-bib/library-path))

(defun a3madkour-pub-multi--has-citations-p (source-file)
  "Return non-nil if SOURCE-FILE contains any `[cite:@…]' refs."
  (with-temp-buffer
    (insert-file-contents source-file)
    (re-search-forward "\\[cite:@[^]]+\\]" nil t)))

;;; -------------------------------------------------------------------
;;; Carry-forward 1 (from Task 6 review): #+EXPORT_FILE_NAME alignment.
;;;
;;; multi-pdf/run computes the post-export `.tex' path as
;;; `<source-dir>/<slug>.tex', assuming ox-latex honors the slug.  If the
;;; source carries its own `#+EXPORT_FILE_NAME:' keyword, ox-latex writes
;;; that name instead — the placement step silently misses.  Fix is to
;;; produce a temp copy with the keyword set to slug, and dispatch the
;;; PDF backend against the temp copy.  We do not mutate the user's source.

(defun a3madkour-pub-multi--prepare-source-for-pdf (source-file slug work-dir)
  "Copy SOURCE-FILE into WORK-DIR as `<slug>.org', injecting / overriding
`#+EXPORT_FILE_NAME: <slug>' so ox-latex's output filename matches SLUG.
Returns the path of the prepared source."
  (let ((prepared (expand-file-name (concat slug ".org") work-dir)))
    (make-directory work-dir t)
    (with-temp-buffer
      (insert-file-contents source-file)
      (goto-char (point-min))
      (if (re-search-forward "^#\\+EXPORT_FILE_NAME:.*$" nil t)
          (replace-match (format "#+EXPORT_FILE_NAME: %s" slug) t t)
        ;; Insert the keyword after the first block of `#+...' lines, or at point-min.
        (goto-char (point-min))
        (insert (format "#+EXPORT_FILE_NAME: %s\n" slug)))
      (write-region (point-min) (point-max) prepared nil 'silent))
    prepared))

(defun a3madkour-pub-multi/orchestrate (source-file slug bundle-dir)
  "Dispatch PDF + Word backends for SOURCE-FILE / SLUG → BUNDLE-DIR.
Each backend runs in `condition-case'.  Returns a plist:
  (:pdf <abs-path-or-nil> :word <abs-path-or-nil>)"
  (let* ((tpl-dir (a3madkour-pub-multi--templates-dir))
         (bib-path (a3madkour-pub-multi--bib-path))
         (has-citations (a3madkour-pub-multi--has-citations-p source-file))
         (work-dir (expand-file-name (format "multi-export-%s/" slug)
                                     temporary-file-directory))
         pdf-out word-out)
    ;; PDF backend — use a prepared copy that pins #+EXPORT_FILE_NAME to slug.
    (setq pdf-out
          (condition-case err
              (let ((prepared (a3madkour-pub-multi--prepare-source-for-pdf
                               source-file slug work-dir)))
                (a3madkour-pub-multi-pdf/run prepared slug bundle-dir tpl-dir))
            (error
             (message "multi-export pdf backend error: %s" err)
             nil)))
    ;; Word backend — skip if citations present but no bib available.
    ;; When skipped, word-out remains nil (not an error, just absent).
    (when (or (not has-citations) bib-path)
      (setq word-out
            (condition-case err
                (a3madkour-pub-multi-word/run source-file slug bundle-dir tpl-dir bib-path)
              (error
               (message "multi-export word backend error: %s" err)
               nil))))
    ;; Patch downloads frontmatter (idempotent).
    (a3madkour-pub-multi--patch-downloads-frontmatter
     (expand-file-name "index.md" bundle-dir) slug pdf-out word-out)
    (list :pdf pdf-out :word word-out)))

;; Stub — implemented in Task 13.
(defun a3madkour-pub-multi--patch-downloads-frontmatter (_index-path _slug _pdf _word)
  "Stub for Task 13."
  t)

(provide 'a3madkour-publish-multi)
;;; a3madkour-publish-multi.el ends here
