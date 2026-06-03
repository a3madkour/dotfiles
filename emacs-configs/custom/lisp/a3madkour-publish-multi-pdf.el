;;; a3madkour-publish-multi-pdf.el --- D.2 PDF backend (ox-latex + xelatex + biber) -*- lexical-binding: t; -*-

;;; Commentary:

;; D.2 PDF backend. Wraps ox-latex export + xelatex/biber compile loop.
;; Tool paths come from defcustoms in the `a3madkour-pub-multi' group.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish-multi-filter)

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

(defun a3madkour-pub-multi-pdf/run (source-file slug bundle-dir templates-dir)
  "Run the PDF backend for SOURCE-FILE / SLUG → BUNDLE-DIR/SLUG.pdf.
TEMPLATES-DIR is the path to `tools/templates/' (contains `madkour-paper.cls').
Returns the absolute path of the placed PDF on success, nil on failure."
  (let* ((work-dir (expand-file-name (format "multi-export-%s/" slug)
                                     temporary-file-directory))
         (fig-dir (expand-file-name "figures/" work-dir))
         (tex-path (expand-file-name (concat slug ".tex") work-dir)))
    (make-directory fig-dir t)
    ;; Make madkour-paper.cls discoverable to xelatex (place a symlink/copy in work-dir).
    (copy-file (expand-file-name "madkour-paper.cls" templates-dir)
               (expand-file-name "madkour-paper.cls" work-dir) t)
    ;; Convert referenced SVGs to PDF for LaTeX.
    (dolist (svg (a3madkour-pub-multi-pdf--list-svg-figures source-file))
      (a3madkour-pub-multi-pdf--convert-svg
       svg (expand-file-name (concat (file-name-base svg) ".pdf") fig-dir)))
    ;; Export org → LaTeX (hooks fire automatically).
    (with-current-buffer (find-file-noselect source-file)
      (let ((org-latex-with-hyperref t)
            (org-latex-default-class "madkour-paper"))
        (org-latex-export-to-latex)))
    ;; Move the produced .tex into the work dir, then compile.
    (let ((source-tex (expand-file-name (concat slug ".tex")
                                        (file-name-directory source-file))))
      (when (file-exists-p source-tex)
        (rename-file source-tex tex-path t)))
    (when (a3madkour-pub-multi-pdf--compile-tex tex-path)
      (let ((built-pdf (expand-file-name (concat slug ".pdf") work-dir))
            (target (expand-file-name (concat slug ".pdf") bundle-dir)))
        (when (file-exists-p built-pdf)
          (rename-file built-pdf target t)
          target)))))

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
