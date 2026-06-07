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
(require 'a3madkour-publish-async)
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

(cl-defun a3madkour-pub-multi/export-bundle (source-file slug bundle-dir
                                                         &key run on-done)
  "Async D.2 multi-export.  Dispatches PDF + Word backends in parallel
via barrier; ON-DONE fires once with a plist:
  (:status 'ok|'err :pdf <path-or-nil> :word <path-or-nil> :results <list>)

When complete, patches downloads frontmatter on BUNDLE-DIR/index.md from
the per-backend result paths.  When citations are present but no bib is
available, the Word backend is skipped (barrier sized to 1).

RUN is the optional `a3-pub-async-run' handle threaded to backends for
log-step instrumentation."
  (let* ((tpl-dir (a3madkour-pub-multi--templates-dir))
         (bib-path (a3madkour-pub-multi--bib-path))
         (has-citations (a3madkour-pub-multi--has-citations-p source-file))
         (work-dir (expand-file-name (format "multi-export-%s/" slug)
                                     temporary-file-directory))
         (skip-word (and has-citations (null bib-path)))
         ;; PDF uses a prepared copy that pins #+EXPORT_FILE_NAME to slug.
         (prepared
          (condition-case err
              (a3madkour-pub-multi--prepare-source-for-pdf source-file slug work-dir)
            (error
             (message "multi-export prepare-source error: %s" err)
             source-file)))
         (n (if skip-word 1 2))
         (report
          (a3-pub-async/barrier
           n :on-all-done
           (lambda (results)
             (let* ((pdf-result (cl-find-if (lambda (r) (eq (plist-get r :backend) 'pdf))
                                            results))
                    (word-result (cl-find-if (lambda (r) (eq (plist-get r :backend) 'word))
                                             results))
                    (pdf-path (plist-get pdf-result :path))
                    (word-path (plist-get word-result :path))
                    (any-err (cl-some (lambda (r) (eq (plist-get r :status) 'err))
                                      results))
                    (status (if any-err 'err 'ok)))
               (condition-case err
                   (a3madkour-pub-multi--patch-downloads-frontmatter
                    (expand-file-name "index.md" bundle-dir) slug pdf-path word-path)
                 (error
                  (message "multi-export frontmatter patch error: %s" err)))
               (when on-done
                 (funcall on-done (list :status status
                                        :pdf pdf-path
                                        :word word-path
                                        :results results))))))))
    (a3madkour-pub-multi-pdf/run prepared slug bundle-dir tpl-dir
                                 :run run
                                 :on-done
                                 (lambda (r)
                                   (funcall report (append (list :backend 'pdf) r))))
    (unless skip-word
      (a3madkour-pub-multi-word/run source-file slug bundle-dir tpl-dir bib-path
                                    :run run
                                    :on-done
                                    (lambda (r)
                                      (funcall report (append (list :backend 'word) r)))))))

(defun a3madkour-pub-multi--render-downloads-line (pdf word)
  "Return a YAML inline-flow `downloads: {…}' line, or nil if both missing."
  (let ((parts nil))
    (when pdf (push (format "pdf: \"%s.pdf\"" (file-name-base pdf)) parts))
    (when word (push (format "word: \"%s.docx\"" (file-name-base word)) parts))
    (when parts
      (format "downloads: {%s}" (string-join (nreverse parts) ", ")))))

(defun a3madkour-pub-multi--patch-downloads-frontmatter (index-path slug pdf word)
  "Patch INDEX-PATH frontmatter with `multi_export:' + `downloads:' keys.
INDEX-PATH is a Hugo bundle's index.md.  SLUG names the artifacts.
PDF / WORD are absolute paths to placed artifacts, or nil if missing.
Idempotent — writes only when content differs."
  (unless (file-exists-p index-path)
    (error "Cannot patch frontmatter — %s does not exist" index-path))
  (let* ((original (with-temp-buffer
                     (insert-file-contents index-path)
                     (buffer-string)))
         (success (or pdf word))
         (downloads-line (a3madkour-pub-multi--render-downloads-line pdf word))
         (multi-line (format "multi_export: %s" (if success "true" "false")))
         updated)
    (with-temp-buffer
      (insert original)
      (goto-char (point-min))
      ;; Drop existing multi_export / downloads lines first.
      (while (re-search-forward "^multi_export:.*\n" nil t) (replace-match ""))
      (goto-char (point-min))
      (while (re-search-forward "^downloads:.*\n" nil t) (replace-match ""))
      ;; Insert before closing `---' of frontmatter.
      (goto-char (point-min))
      (when (re-search-forward "^---\n" nil t)
        (when (re-search-forward "^---\n" nil t)
          (goto-char (match-beginning 0))
          (insert multi-line "\n")
          (when downloads-line
            (insert downloads-line "\n"))))
      (setq updated (buffer-string)))
    (unless (string= original updated)
      (with-temp-file index-path (insert updated)))))

(provide 'a3madkour-publish-multi)
;;; a3madkour-publish-multi.el ends here
