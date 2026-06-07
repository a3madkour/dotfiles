;;; a3madkour-publish-multi-pdf.el --- D.2 PDF backend (ox-latex + xelatex + biber) -*- lexical-binding: t; -*-

;;; Commentary:

;; D.2 PDF backend. Wraps ox-latex export + xelatex/biber compile loop.
;; Tool paths come from defcustoms in the `a3madkour-pub-multi' group.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish-multi-filter)
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
  (let (missing)
    (dolist (cmd (list a3madkour-pub-multi-xelatex-command
                       a3madkour-pub-multi-biber-command
                       a3madkour-pub-multi-rsvg-convert-command))
      (unless (executable-find cmd)
        (push cmd missing)))
    (nreverse missing)))

(defun a3madkour-pub-multi-pdf--convert-svg (src dst)
  "Convert SVG at SRC to PDF at DST via `rsvg-convert -f pdf'.
Returns 0 on success."
  (make-directory (file-name-directory dst) t)
  (call-process a3madkour-pub-multi-rsvg-convert-command nil nil nil
                "-f" "pdf" src "-o" dst))

(defun a3madkour-pub-multi-pdf--compile-tex (tex-path)
  "Run xelatex → biber → xelatex → xelatex on TEX-PATH in its own directory.
Returns t iff `<base>.pdf' exists after the run.

xelatex routinely exits non-zero on harmless warnings (e.g. \"Label(s) may
have changed\" on the first pass, font shape substitutions, etc.) even when
the PDF builds successfully.  Biber exits 0 even when it has nothing to do
(no `.bcf').  So we run all four passes unconditionally and gate success
on the existence of the produced PDF, not on exit codes."
  (let* ((dir (file-name-directory tex-path))
         (base (file-name-base tex-path))
         (default-directory dir)
         (pdf-path (expand-file-name (concat base ".pdf") dir))
         (seq (list a3madkour-pub-multi-xelatex-command
                    a3madkour-pub-multi-biber-command
                    a3madkour-pub-multi-xelatex-command
                    a3madkour-pub-multi-xelatex-command)))
    (dolist (cmd seq)
      (let ((arg (if (string= cmd a3madkour-pub-multi-biber-command)
                     base
                   (concat base ".tex"))))
        (call-process cmd nil nil nil "-interaction=nonstopmode" arg)))
    (file-exists-p pdf-path)))

(defun a3madkour-pub-multi-pdf--list-svg-figures (source-file)
  "Return list of absolute SVG paths referenced by SOURCE-FILE via `[[file:…]]'.
Delegates to B.4's existing asset walker if available; falls back to nil."
  (when (fboundp 'a3madkour-pub-assets/list-referenced-files)
    (cl-remove-if-not
     (lambda (p) (string= "svg" (file-name-extension p)))
     (a3madkour-pub-assets/list-referenced-files source-file))))

(cl-defun a3madkour-pub-multi-pdf--convert-svgs-fan (pairs &key on-done)
  "PAIRS is a list of (SRC DST).  Fan out one run-process per pair.
ON-DONE fires (with the list of exit codes) when all complete."
  (let ((n (length pairs)))
    (if (zerop n)
        (when on-done (funcall on-done nil))
      (let ((report (a3-pub-async/barrier n :on-all-done on-done)))
        (dolist (pair pairs)
          (let ((src (car pair)) (dst (cadr pair)))
            (make-directory (file-name-directory dst) t)
            (a3-pub-async/run-process
             a3madkour-pub-multi-rsvg-convert-command
             (list "-f" "pdf" src "-o" dst)
             :name (format "rsvg-%s" (file-name-base src))
             :on-done (lambda (rc _tail) (funcall report rc)))))))))

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
                  (run-next (cdr remaining))))))))
      (run-next seq))))

(cl-defun a3madkour-pub-multi-pdf/run (source-file slug bundle-dir templates-dir
                                       &key run on-done)
  "Async PDF backend.  RUN is the a3-pub-async-run handle (for log-step).
ON-DONE is called with (:status 'ok :path target) or (:status 'err :err-snippet …)."
  (let* ((work-dir (expand-file-name (format "multi-export-%s/" slug)
                                     temporary-file-directory))
         (fig-dir (expand-file-name "figures/" work-dir))
         (tex-path (expand-file-name (concat slug ".tex") work-dir))
         (svgs (a3madkour-pub-multi-pdf--list-svg-figures source-file))
         (svg-pairs (mapcar (lambda (svg)
                              (list svg (expand-file-name
                                         (concat (file-name-base svg) ".pdf")
                                         fig-dir)))
                            svgs)))
    (make-directory fig-dir t)
    (copy-file (expand-file-name "madkour-paper.cls" templates-dir)
               (expand-file-name "madkour-paper.cls" work-dir) t)
    (when run (push work-dir (a3-pub-async-run-tmp-dirs run)))
    ;; Phase 1: ox-latex export (sync, instrumented).
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
    ;; Move produced .tex into work dir.
    (let ((source-tex (expand-file-name (concat slug ".tex")
                                        (file-name-directory source-file))))
      (when (file-exists-p source-tex)
        (rename-file source-tex tex-path t)))
    ;; Phase 2: SVG fan → xelatex chain → place.
    (a3madkour-pub-multi-pdf--convert-svgs-fan
     svg-pairs
     :on-done
     (lambda (_svg-rcs)
       (when run
         (a3-pub-async/log-step run "svgs" :ok
                                :detail (format "%d files" (length svg-pairs))))
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
  (with-current-buffer buf
    (goto-char (point-max))
    (if successp
        (insert (format "  [✓] pdf    → %s   (%.1fs)\n" path elapsed))
      (insert (format "  [✗] pdf    → exit %.1fs\n" elapsed))
      (when err-snippet
        (insert (format "              %s\n" err-snippet))))))

(provide 'a3madkour-publish-multi-pdf)
;;; a3madkour-publish-multi-pdf.el ends here
