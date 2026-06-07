;;; a3madkour-publish-multi-pdf-test.el --- Tests for PDF backend -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-multi-pdf)
(require 'a3madkour-publish-async)

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

(ert-deftest a3madkour-pub-multi-pdf/svg-fan-uses-barrier ()
  "N SVGs convert via run-process; barrier fires once with all results.
Sync shim makes this deterministic."
  (let ((calls nil) (done nil))
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd &rest _) (push cmd calls) 0))
              ((symbol-function 'make-directory) (lambda (&rest _) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf--convert-svgs-fan
        '(("/a.svg" "/a.pdf") ("/b.svg" "/b.pdf"))
        :on-done (lambda (_results) (setq done t)))))
    (should (= 2 (length calls)))
    (should done)))

(ert-deftest a3madkour-pub-multi-pdf/svg-fan-empty-list-fires-immediately ()
  "Empty pair list still fires on-done."
  (let ((done nil))
    (with-a3-pub-async-sync
     (a3madkour-pub-multi-pdf--convert-svgs-fan
      nil :on-done (lambda (_) (setq done t))))
    (should done)))

(ert-deftest a3madkour-pub-multi-pdf/compile-chain-runs-four-passes ()
  "compile-tex-async invokes the 4-pass sequence and fires on-done."
  (let (cmds done)
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd &rest _) (push cmd cmds) 0))
              ((symbol-function 'file-exists-p) (lambda (_) t)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf--compile-tex-async
        "/tmp/x/foo.tex"
        :on-done (lambda (ok) (setq done ok)))))
    (should (= 4 (length cmds)))
    (should done)))

(ert-deftest a3madkour-pub-multi-pdf/compile-chain-no-pdf-returns-nil ()
  "When no PDF exists after the 4 passes, on-done fires with nil."
  (let (done)
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 0))
              ((symbol-function 'file-exists-p) (lambda (_) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf--compile-tex-async
        "/tmp/x/foo.tex"
        :on-done (lambda (ok) (setq done ok)))))
    (should-not done)))

(ert-deftest a3madkour-pub-multi-pdf/run-async-fires-on-done-with-status ()
  (let (status)
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 0))
              ((symbol-function 'file-exists-p) (lambda (_) t))
              ((symbol-function 'rename-file) (lambda (&rest _) nil))
              ((symbol-function 'copy-file) (lambda (&rest _) nil))
              ((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'find-file-noselect)
               (lambda (_) (get-buffer-create "*pdf-test*")))
              ((symbol-function 'org-latex-export-to-latex) (lambda (&rest _) nil))
              ((symbol-function 'a3madkour-pub-multi-pdf--list-svg-figures)
               (lambda (_) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf/run
        "/tmp/x.org" "x" "/tmp/bundle/" "/tmp/templates/"
        :run (make-a3-pub-async-run :buffer (a3-pub-async/buffer))
        :on-done (lambda (s) (setq status s)))))
    (should (or (eq (plist-get status :status) 'ok)
                (eq status 'ok)))))

(provide 'a3madkour-publish-multi-pdf-test)
;;; a3madkour-publish-multi-pdf-test.el ends here
