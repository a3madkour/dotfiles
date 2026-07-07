;;; a3madkour-publish-multi-pdf.el --- D.2 PDF backend (ox-latex + xelatex + biber) -*- lexical-binding: t; -*-

;;; Commentary:

;; D.2 PDF backend. Wraps ox-latex export + xelatex/biber compile loop.
;; Tool paths come from defcustoms in the `a3madkour-pub-multi' group.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish-multi-filter)
(require 'a3madkour-publish-multi-backend)
(require 'a3madkour-publish-async)

(defgroup a3madkour-pub-multi nil
  "D.2 multi-target export pipeline." :group 'org)

(with-eval-after-load 'ox-latex
  (let ((entry
         '("madkour-paper"
           "\\documentclass[11pt]{madkour-paper}
[NO-DEFAULT-PACKAGES]
[PACKAGES]
[EXTRA]"
           ("\\section{%s}" . "\\section*{%s}")
           ("\\subsection{%s}" . "\\subsection*{%s}")
           ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
           ("\\paragraph{%s}" . "\\paragraph*{%s}")
           ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))))
    (setf (alist-get "madkour-paper" org-latex-classes nil nil #'equal)
          (cdr entry))))

(defcustom a3madkour-pub-multi-xelatex-command "xelatex"
  "External `xelatex' command name or absolute path."
  :type 'string :group 'a3madkour-pub-multi)

(defcustom a3madkour-pub-multi-biber-command "biber"
  "External `biber' command name or absolute path."
  :type 'string :group 'a3madkour-pub-multi)

(defcustom a3madkour-pub-multi-rsvg-convert-command "rsvg-convert"
  "External `rsvg-convert' command name or absolute path."
  :type 'string :group 'a3madkour-pub-multi)

(defun a3madkour-pub-multi-pdf--probe-tools ()
  "Return list of missing required commands (xelatex/biber/rsvg-convert), or nil if all present."
  (a3madkour-pub-multi-backend/probe-tools
   (list a3madkour-pub-multi-xelatex-command
         a3madkour-pub-multi-biber-command
         a3madkour-pub-multi-rsvg-convert-command)))

(defun a3madkour-pub-multi-pdf--list-svg-figures (source-file)
  "Return list of absolute SVG paths referenced by SOURCE-FILE via `[[file:…]]'.
Delegates to B.4's existing asset walker if available; falls back to nil."
  (when (fboundp 'a3madkour-pub-assets/list-referenced-files)
    (cl-remove-if-not
     (lambda (p) (string= "svg" (file-name-extension p)))
     (a3madkour-pub-assets/list-referenced-files source-file))))

(cl-defun a3madkour-pub-multi-pdf--convert-svgs-fan (pairs &key on-done)
  "PAIRS is a list of (SRC DST).  Fan out one run-process per pair (SVG→PDF).
ON-DONE fires (with the list of exit codes) when all complete."
  (a3madkour-pub-multi-backend/convert-svgs-fan
   pairs a3madkour-pub-multi-rsvg-convert-command '("-f" "pdf")
   :name-prefix "rsvg" :on-done on-done))

(cl-defun a3madkour-pub-multi-pdf--compile-tex-async (tex-path &key on-done step-cb)
  "Async version of compile-tex.  Chains xelatex→biber→xelatex→xelatex.
STEP-CB, when non-nil, is called with (pass-label pass-rc) per pass.
ON-DONE is called with t/nil based on PDF existence after the run."
  (let* ((dir (file-name-directory tex-path))
         (base (file-name-base tex-path))
         (pdf-path (expand-file-name (concat base ".pdf") dir))
         (seq (list (cons a3madkour-pub-multi-xelatex-command "pass 1/4")
                    (cons a3madkour-pub-multi-biber-command   "biber")
                    (cons a3madkour-pub-multi-xelatex-command "pass 3/4")
                    (cons a3madkour-pub-multi-xelatex-command "pass 4/4"))))
    ;; P2.4a: the work dir is reused and never cleaned, so a stale
    ;; `<slug>.pdf' from a prior run would let a failing compile report
    ;; `:ok' (success is judged by `file-exists-p pdf-path' below).  Delete
    ;; any pre-existing PDF before the chain so existence means THIS run.
    (when (file-exists-p pdf-path)
      (delete-file pdf-path))
    (cl-labels
        ((run-next (remaining)
           (if (null remaining)
               (when on-done (funcall on-done (file-exists-p pdf-path)))
             (let* ((cmd-and-label (car remaining))
                    (cmd (car cmd-and-label))
                    (label (cdr cmd-and-label))
                    (arg (if (string= cmd a3madkour-pub-multi-biber-command)
                             base
                           (concat base ".tex"))))
               (a3-pub-async/run-process
                cmd (list "-interaction=nonstopmode" arg)
                :name (format "pdf-%s" label)
                :cwd dir
                :on-done
                (lambda (rc _tail)
                  (when step-cb (funcall step-cb label rc))
                  ;; P2.4b: a non-zero FIRST xelatex pass is fatal — later
                  ;; passes just compound the error and can leave a garbage
                  ;; PDF.  Abort the chain and report failure (on-done nil).
                  (if (and (string= label "pass 1/4") (not (zerop rc)))
                      (when on-done (funcall on-done nil))
                    (run-next (cdr remaining)))))))))
      (run-next seq))))

(cl-defun a3madkour-pub-multi-pdf/run (source-file slug bundle-dir templates-dir
                                       &key run on-done svg-source-file)
  "Async PDF backend.  RUN is the a3-pub-async-run handle (for log-step).
ON-DONE is called with (:status 'ok :path target) or (:status 'err :err-snippet …).

SOURCE-FILE drives the ox-latex export.  The orchestrator dispatches this
backend against a relocated temp copy (so ox-latex's `#+EXPORT_FILE_NAME:'
matches SLUG), but that copy lives outside the essays tree — its relative
`./assets/…' / `file:…' figure refs no longer resolve, so listing SVGs from
it silently drops every figure (bug P2.3).  SVG-SOURCE-FILE, when non-nil,
names the ORIGINAL source; SVG figures are resolved against it instead,
mirroring the Word backend which always lists from the real source."
  (a3madkour-pub-multi-backend/run-scaffold
   slug
   :run run
   ;; P2.3: resolve SVG figures against the ORIGINAL source, not the
   ;; relocated temp copy handed as SOURCE-FILE.
   :svg-source (or svg-source-file source-file)
   :svg-list-fn #'a3madkour-pub-multi-pdf--list-svg-figures
   :svg-ext "pdf"
   :svg-fan-fn #'a3madkour-pub-multi-pdf--convert-svgs-fan
   :svgs-step "svgs"
   ;; Pre-fan: copy the class file, run the ox-latex export (sync,
   ;; instrumented), then relocate the produced .tex into the work dir.
   :pre-fan
   (lambda (work-dir)
     (copy-file (expand-file-name "madkour-paper.cls" templates-dir)
                (expand-file-name "madkour-paper.cls" work-dir) t)
     (let ((start (current-time)))
       (with-current-buffer (find-file-noselect source-file)
         (let ((org-latex-with-hyperref t)
               (org-latex-default-class "madkour-paper")
               (org-export-show-temporary-export-buffer nil))
           (org-latex-export-to-latex)))
       (when run
         (a3-pub-async/log-step run "export" :ok :detail "org → latex"
                                :elapsed (float-time
                                          (time-subtract (current-time) start)))))
     (let ((source-tex (expand-file-name (concat slug ".tex")
                                         (file-name-directory source-file)))
           (tex-path (expand-file-name (concat slug ".tex") work-dir)))
       (when (file-exists-p source-tex)
         (rename-file source-tex tex-path t))))
   ;; Compile: xelatex chain → place built PDF at target.
   :compile
   (lambda (work-dir _fig-dir _svg-pairs)
     (let ((tex-path (expand-file-name (concat slug ".tex") work-dir)))
       (a3madkour-pub-multi-pdf--compile-tex-async
        tex-path
        :step-cb
        (lambda (label rc)
          (when run
            (a3-pub-async/log-step run "xelatex" (if (zerop rc) :ok :err)
                                   :detail label)))
        :on-done
        (lambda (ok)
          (if (not ok)
              (when on-done
                (funcall on-done '(:status err :err-snippet "PDF not produced")))
            (let ((built (expand-file-name (concat slug ".pdf") work-dir))
                  (target (expand-file-name (concat slug ".pdf") bundle-dir)))
              (if (file-exists-p built)
                  (progn
                    (rename-file built target t)
                    (when run
                      (a3-pub-async/log-step run "pdf" :ok :detail target))
                    (when on-done
                      (funcall on-done (list :status 'ok :path target))))
                (when on-done
                  (funcall on-done '(:status err :err-snippet "built PDF missing"))))))))))))

(defun a3madkour-pub-multi-pdf--log-line (buf successp path elapsed err-snippet)
  "Append a single log line to BUF for the PDF backend.
SUCCESSP is t for ✓ / nil for ✗.  PATH is target path on success.
ELAPSED is seconds (float).  ERR-SNIPPET is the stderr tail to inline on failure."
  (a3madkour-pub-multi-backend/log-line buf "pdf" successp path elapsed err-snippet))

(provide 'a3madkour-publish-multi-pdf)
;;; a3madkour-publish-multi-pdf.el ends here
