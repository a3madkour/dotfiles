;;; a3madkour-publish-multi-pdf-test.el --- Tests for PDF backend -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-multi-pdf)

(ert-deftest a3madkour-pub-multi-pdf/defcustoms-defined ()
  (should (boundp 'a3madkour-pub-multi-xelatex-command))
  (should (boundp 'a3madkour-pub-multi-biber-command))
  (should (boundp 'a3madkour-pub-multi-rsvg-convert-command)))

(ert-deftest a3madkour-pub-multi-pdf/probe-tools-all-present ()
  "When all tools resolve, probe returns nil (no missing)."
  (cl-letf (((symbol-function 'executable-find) (lambda (_) "/usr/bin/x")))
    (should-not (a3madkour-pub-multi-pdf--probe-tools))))

(ert-deftest a3madkour-pub-multi-pdf/probe-tools-missing-xelatex ()
  "When xelatex is missing, probe returns a list containing it."
  (cl-letf (((symbol-function 'executable-find)
             (lambda (cmd) (unless (string= cmd "xelatex") "/usr/bin/x"))))
    (let ((missing (a3madkour-pub-multi-pdf--probe-tools)))
      (should (member "xelatex" missing)))))

(ert-deftest a3madkour-pub-multi-pdf/svg-to-pdf-builds-command ()
  "SVG → PDF helper builds `rsvg-convert -f pdf SRC -o DST'."
  (let (captured)
    (cl-letf (((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'call-process)
               (lambda (cmd _ _ _ &rest args) (push (cons cmd args) captured) 0)))
      (a3madkour-pub-multi-pdf--convert-svg "/src/a.svg" "/dst/a.pdf")
      (let ((call (car captured)))
        (should (string= (car call) a3madkour-pub-multi-rsvg-convert-command))
        (should (member "-f" (cdr call)))
        (should (member "pdf" (cdr call)))
        (should (member "/src/a.svg" (cdr call)))
        (should (member "/dst/a.pdf" (cdr call)))))))

(ert-deftest a3madkour-pub-multi-pdf/xelatex-loop-calls-four-times ()
  "Latex compile invokes xelatex/biber/xelatex/xelatex sequence (4 commands)."
  (let (cmd-log)
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd _ _ _ &rest _args) (push cmd cmd-log) 0)))
      (a3madkour-pub-multi-pdf--compile-tex "/tmp/x/foo.tex")
      (let ((sequence (nreverse cmd-log)))
        (should (= 4 (length sequence)))
        (should (string= (nth 0 sequence) a3madkour-pub-multi-xelatex-command))
        (should (string= (nth 1 sequence) a3madkour-pub-multi-biber-command))
        (should (string= (nth 2 sequence) a3madkour-pub-multi-xelatex-command))
        (should (string= (nth 3 sequence) a3madkour-pub-multi-xelatex-command))))))

(ert-deftest a3madkour-pub-multi-pdf/compile-tex-returns-nil-when-pdf-absent ()
  "When no .pdf exists after all 4 passes, compile-tex returns nil.
Exit codes are intentionally ignored — xelatex routinely returns non-zero on
harmless warnings; the only reliable success signal is the produced PDF."
  (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1))
            ((symbol-function 'file-exists-p) (lambda (_) nil)))
    (should-not (a3madkour-pub-multi-pdf--compile-tex "/tmp/x/foo.tex"))))

(ert-deftest a3madkour-pub-multi-pdf/compile-tex-returns-t-when-pdf-exists ()
  "When `<base>.pdf' exists after the 4 passes, compile-tex returns t even if
some passes exited non-zero (the common LaTeX-warning case)."
  (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1))
            ((symbol-function 'file-exists-p) (lambda (_) t)))
    (should (a3madkour-pub-multi-pdf--compile-tex "/tmp/x/foo.tex"))))

(ert-deftest a3madkour-pub-multi-pdf/log-success-line ()
  (let ((buf (generate-new-buffer "*log-test*")))
    (unwind-protect
        (progn
          (a3madkour-pub-multi-pdf--log-line buf t "/out/foo.pdf" 7.2 nil)
          (with-current-buffer buf
            (should (string-match-p "\\[✓\\] pdf .*foo\\.pdf .*(7.2s)"
                                    (buffer-string)))))
      (kill-buffer buf))))

(ert-deftest a3madkour-pub-multi-pdf/log-failure-snippet ()
  (let ((buf (generate-new-buffer "*log-test*")))
    (unwind-protect
        (progn
          (a3madkour-pub-multi-pdf--log-line buf nil nil 4.0 "! Undefined control sequence.")
          (with-current-buffer buf
            (let ((s (buffer-string)))
              (should (string-match-p "\\[✗\\] pdf" s))
              (should (string-match-p "Undefined control sequence" s)))))
      (kill-buffer buf))))

(provide 'a3madkour-publish-multi-pdf-test)
;;; a3madkour-publish-multi-pdf-test.el ends here
