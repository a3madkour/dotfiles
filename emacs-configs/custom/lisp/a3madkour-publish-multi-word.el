;;; a3madkour-publish-multi-word.el --- D.2 Word backend (pandoc) -*- lexical-binding: t; -*-

;;; Commentary:

;; D.2 Word backend.  Wraps pandoc org→docx with a Lua filter that handles
;; D.1 vocab numbering+styling, plus SVG→PNG conversion for figures.
;;
;; Filter serialization note: pandoc cannot see Emacs'
;; `org-export-before-processing-functions' hook.  The Word backend therefore
;; explicitly applies the 3 filter passes (visibility + vocab + crossref) in a
;; `with-temp-buffer', writes the result to a temp .org file, and hands that
;; file directly to pandoc.  This means the `#+EXPORT_FILE_NAME:' mismatch
;; concern that affects the PDF backend (where ox-latex's file naming is driven
;; by the keyword) does NOT apply here: we tell pandoc exactly which input file
;; to read, independent of any export keyword in the org source.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish-multi-filter)
(require 'a3madkour-publish-multi-pdf)  ;; for shared defgroup + rsvg-convert defcustom

(defcustom a3madkour-pub-multi-pandoc-command "pandoc"
  "External `pandoc' command name or absolute path."
  :type 'string :group 'a3madkour-pub-multi)

(defun a3madkour-pub-multi-word--probe-tools ()
  "Return list of missing required commands (pandoc/rsvg-convert), or nil if all present."
  (let (missing)
    (dolist (cmd (list a3madkour-pub-multi-pandoc-command
                       a3madkour-pub-multi-rsvg-convert-command))
      (unless (executable-find cmd) (push cmd missing)))
    (nreverse missing)))

(defun a3madkour-pub-multi-word--convert-svg (src dst)
  "Convert SVG at SRC to PNG at DST via `rsvg-convert -f png -d 192'.
Returns the exit code from `rsvg-convert'."
  (make-directory (file-name-directory dst) t)
  (call-process a3madkour-pub-multi-rsvg-convert-command nil nil nil
                "-f" "png" "-d" "192" src "-o" dst))

(defun a3madkour-pub-multi-word--invoke-pandoc (input-org output-docx
                                                 reference-doc lua-filter bib-path)
  "Run pandoc to convert INPUT-ORG → OUTPUT-DOCX using REFERENCE-DOC,
LUA-FILTER, and BIB-PATH (bibliography).  BIB-PATH may be nil when the
source has no citations; in that case the `--bibliography' flag is omitted
(passing nil or the empty string would cause an opaque pandoc error).
Returns the pandoc exit code."
  (let ((args (append (list "-f" "org" "-t" "docx"
                            (format "--reference-doc=%s" reference-doc)
                            (format "--lua-filter=%s" lua-filter)
                            "--citeproc")
                      (when (and bib-path (not (string= bib-path "")))
                        (list (format "--bibliography=%s" bib-path)))
                      (list input-org "-o" output-docx))))
    (apply #'call-process a3madkour-pub-multi-pandoc-command nil nil nil args)))

(defun a3madkour-pub-multi-word--serialize-filtered (source-file out-org backend)
  "Read SOURCE-FILE, apply visibility + vocab + crossref filters for BACKEND,
write the result to OUT-ORG.  Pandoc cannot see Emacs' export hooks, so this
serializes the post-filter buffer for pandoc input.  Must mirror the steps in
`a3madkour-pub-multi-filter--before-processing' — `--strip-visibility-tags'
included — or backend-specific visibility tags would leak into the docx."
  (with-temp-buffer
    (insert-file-contents source-file)
    (org-mode)
    (a3madkour-pub-multi-filter--apply-visibility backend)
    (a3madkour-pub-multi-filter--strip-visibility-tags)
    (a3madkour-pub-multi-filter--translate-vocab backend)
    (a3madkour-pub-multi-filter--rewrite-crossrefs backend)
    (write-region (point-min) (point-max) out-org nil 'silent)))

(defun a3madkour-pub-multi-word/run (source-file slug bundle-dir templates-dir bib-path)
  "Run the Word backend for SOURCE-FILE / SLUG → BUNDLE-DIR/SLUG.docx.
TEMPLATES-DIR is the path to `tools/templates/' (contains `reference.docx'
and `d2-blocks.lua').  BIB-PATH is the absolute path to the .bib bibliography
file (provided by the orchestrator from F.1's `a3madkour-pub-bib-path').
Returns the absolute path of the placed Word file on success, nil on failure."
  (let* ((work-dir (expand-file-name (format "multi-export-%s/" slug)
                                     temporary-file-directory))
         (fig-dir (expand-file-name "figures/" work-dir))
         (filtered-org (expand-file-name (concat slug "-filtered.org") work-dir))
         (out-docx (expand-file-name (concat slug ".docx") work-dir))
         (target (expand-file-name (concat slug ".docx") bundle-dir))
         (reference-doc (expand-file-name "reference.docx" templates-dir))
         (lua-filter (expand-file-name "d2-blocks.lua" templates-dir)))
    (make-directory fig-dir t)
    ;; Convert referenced SVGs to PNG for Word embedding.
    (when (fboundp 'a3madkour-pub-assets/list-referenced-files)
      (dolist (svg (cl-remove-if-not
                    (lambda (p) (string= "svg" (file-name-extension p)))
                    (a3madkour-pub-assets/list-referenced-files source-file)))
        (a3madkour-pub-multi-word--convert-svg
         svg (expand-file-name (concat (file-name-base svg) ".png") fig-dir))))
    ;; Serialize the post-filter buffer so pandoc sees the transformed source.
    (a3madkour-pub-multi-word--serialize-filtered source-file filtered-org 'pandoc)
    ;; Invoke pandoc on the filtered org file.
    (when (zerop (a3madkour-pub-multi-word--invoke-pandoc
                  filtered-org out-docx reference-doc lua-filter bib-path))
      (when (file-exists-p out-docx)
        (rename-file out-docx target t)
        target))))

(defun a3madkour-pub-multi-word--log-line (buf successp path elapsed err-snippet)
  "Append a single log line to BUF for the Word backend.
SUCCESSP is t for ✓ / nil for ✗.  PATH is target path on success.
ELAPSED is seconds (float).  ERR-SNIPPET is the stderr tail to inline on failure."
  (with-current-buffer buf
    (goto-char (point-max))
    (if successp
        (insert (format "  [✓] word   → %s   (%.1fs)\n" path elapsed))
      (insert (format "  [✗] word   → exit %.1fs\n" elapsed))
      (when err-snippet
        (insert (format "              %s\n" err-snippet))))))

(provide 'a3madkour-publish-multi-word)
;;; a3madkour-publish-multi-word.el ends here
