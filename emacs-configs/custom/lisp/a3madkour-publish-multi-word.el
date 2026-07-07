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
(require 'a3madkour-publish-multi-backend)
(require 'a3madkour-publish-async)

(defcustom a3madkour-pub-multi-pandoc-command "pandoc"
  "External `pandoc' command name or absolute path."
  :type 'string :group 'a3madkour-pub-multi)

(defun a3madkour-pub-multi-word--probe-tools ()
  "Return list of missing required commands (pandoc/rsvg-convert), or nil if all present."
  (a3madkour-pub-multi-backend/probe-tools
   (list a3madkour-pub-multi-pandoc-command
         a3madkour-pub-multi-rsvg-convert-command)))

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

(cl-defun a3madkour-pub-multi-word--convert-svgs-fan (pairs &key on-done)
  "PAIRS is (SRC DST) for SVG→PNG via rsvg-convert -f png -d 192."
  (a3madkour-pub-multi-backend/convert-svgs-fan
   pairs a3madkour-pub-multi-rsvg-convert-command '("-f" "png" "-d" "192")
   :name-prefix "rsvg-png" :on-done on-done))

(cl-defun a3madkour-pub-multi-word/run (source-file slug bundle-dir
                                        templates-dir bib-path
                                        &key run on-done)
  "Async Word backend.  RUN is the run handle; ON-DONE called with
(:status 'ok :path target) or (:status 'err :err-snippet …).

P3.3: the outer figures/SVG-conversion skeleton is shared via
`a3madkour-pub-multi-backend/run-scaffold'; the Word-specific pandoc→docx
compile step is injected as the `:compile' closure.  Word always lists SVG
figures from the real SOURCE-FILE (no temp-copy relocation, so no P2.3 seam)."
  (let ((target (expand-file-name (concat slug ".docx") bundle-dir))
        (reference-doc (expand-file-name "reference.docx" templates-dir))
        (lua-filter (expand-file-name "d2-blocks.lua" templates-dir)))
    (a3madkour-pub-multi-backend/run-scaffold
     slug
     :run run
     :svg-source source-file
     :svg-list-fn
     (lambda (src)
       (when (fboundp 'a3madkour-pub-assets/list-referenced-files)
         (cl-remove-if-not
          (lambda (p) (string= "svg" (file-name-extension p)))
          (a3madkour-pub-assets/list-referenced-files src))))
     :svg-ext "png"
     :svg-fan-fn #'a3madkour-pub-multi-word--convert-svgs-fan
     :svgs-step "svgs (png)"
     :compile
     (lambda (work-dir _fig-dir _svg-pairs)
       (let ((filtered-org (expand-file-name (concat slug "-filtered.org") work-dir))
             (out-docx (expand-file-name (concat slug ".docx") work-dir)))
         ;; Serialize the post-filter buffer so pandoc sees the transformed source.
         (a3madkour-pub-multi-word--serialize-filtered source-file filtered-org 'pandoc)
         (let ((pandoc-args (append
                             (list "-f" "org" "-t" "docx"
                                   (format "--reference-doc=%s" reference-doc)
                                   (format "--lua-filter=%s" lua-filter)
                                   "--citeproc")
                             (when (and bib-path (not (string= bib-path "")))
                               (list (format "--bibliography=%s" bib-path)))
                             (list filtered-org "-o" out-docx))))
           (a3-pub-async/run-process
            a3madkour-pub-multi-pandoc-command
            pandoc-args
            :name (format "pandoc-%s" slug)
            :on-done
            (lambda (rc _tail)
              (cond
               ((not (zerop rc))
                (when run
                  (a3-pub-async/log-step run "pandoc" :err :err-snippet (format "rc=%d" rc)))
                (when on-done
                  (funcall on-done (list :status 'err :err-snippet (format "pandoc rc=%d" rc)))))
               ((file-exists-p out-docx)
                (rename-file out-docx target t)
                (when run (a3-pub-async/log-step run "docx" :ok :detail target))
                (when on-done
                  (funcall on-done (list :status 'ok :path target))))
               (t
                (when on-done
                  (funcall on-done '(:status err :err-snippet "docx not produced")))))))))))))

(provide 'a3madkour-publish-multi-word)
;;; a3madkour-publish-multi-word.el ends here
