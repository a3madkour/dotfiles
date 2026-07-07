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

;; P5.3: the PDF-specific `--log-line' wrapper was dead production code (its
;; only callers were these two tests).  The formatting it delegated to —
;; `a3madkour-pub-multi-backend/log-line' — is covered by
;; `a3madkour-pub-multi-backend-test/log-line-success-and-failure' (✓/✗ glyph,
;; path, elapsed, snippet), so removing the wrapper + these tests loses no
;; coverage.

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

;;; -------------------------------------------------------------------
;;; Bug P2.3 — SVG figures must resolve against the ORIGINAL source,
;;; not the relocated temp copy that `export-bundle' hands the PDF
;;; backend.  The Word backend already lists SVGs from the real source.

(ert-deftest a3madkour-pub-multi-pdf/run-lists-svgs-from-original-source-not-temp-copy ()
  "P2.3: SVG figures are resolved against the ORIGINAL source-file, not the
relocated temp copy passed as SOURCE-FILE.  When `:svg-source-file' names the
real source, its SVGs flow into the convert fan; the temp copy resolves none."
  (let ((real-src "/essays/foo/index.org")
        (temp-copy "/tmp/multi-export-foo/foo.org")
        captured-srcs)
    (cl-letf (((symbol-function 'a3madkour-pub-multi-pdf--list-svg-figures)
               ;; Only the real source resolves the figure; the temp copy's
               ;; relative refs point at a dir with no such file.
               (lambda (src)
                 (when (string= src real-src)
                   (list "/essays/foo/assets/fig.svg"))))
              ((symbol-function 'a3madkour-pub-multi-pdf--convert-svgs-fan)
               (lambda (pairs &rest kw)
                 (setq captured-srcs (mapcar #'car pairs))
                 (let ((on-done (plist-get kw :on-done)))
                   (when on-done (funcall on-done nil)))))
              ((symbol-function 'a3madkour-pub-multi-pdf--compile-tex-async)
               (lambda (_tex &rest kw)
                 (let ((on-done (plist-get kw :on-done)))
                   (when on-done (funcall on-done nil)))))
              ((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'copy-file) (lambda (&rest _) nil))
              ((symbol-function 'rename-file) (lambda (&rest _) nil))
              ((symbol-function 'file-exists-p) (lambda (_) nil))
              ((symbol-function 'find-file-noselect)
               (lambda (_) (get-buffer-create "*pdf-p23*")))
              ((symbol-function 'org-latex-export-to-latex) (lambda (&rest _) nil)))
      (a3madkour-pub-multi-pdf/run
       temp-copy "foo" "/tmp/bundle/" "/tmp/templates/"
       :svg-source-file real-src
       :on-done (lambda (_) nil)))
    (should (member "/essays/foo/assets/fig.svg" captured-srcs))))

;;; -------------------------------------------------------------------
;;; Bug P2.4 — the xelatex chain must honor exit codes and never reuse a
;;; stale PDF: (a) delete any pre-existing PDF before the chain, and
;;; (b) abort + report :err when the first xelatex pass returns non-zero.

(ert-deftest a3madkour-pub-multi-pdf/compile-chain-aborts-on-first-pass-failure ()
  "P2.4b: a non-zero first xelatex pass aborts the chain (on-done nil) and
does not run the remaining passes."
  (let (cmds done (first t))
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd &rest _)
                 (push cmd cmds)
                 (prog1 (if first 1 0) (setq first nil))))
              ((symbol-function 'file-exists-p) (lambda (_) nil))
              ((symbol-function 'delete-file) (lambda (&rest _) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf--compile-tex-async
        "/tmp/x/foo.tex"
        :on-done (lambda (ok) (setq done (list 'called ok))))))
    (should (= 1 (length cmds)))
    (should (equal done '(called nil)))))

(ert-deftest a3madkour-pub-multi-pdf/run-stale-pdf-failing-first-pass-reports-err ()
  "P2.4a+b: a leftover PDF from a prior run must not mask a failing compile.
First xelatex pass returns non-zero → result is :err, and the stale PDF is
deleted before the chain starts."
  (let (status deleted (first t))
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _) (prog1 (if first 1 0) (setq first nil))))
              ((symbol-function 'file-exists-p) (lambda (_) t))
              ((symbol-function 'delete-file) (lambda (p &rest _) (push p deleted)))
              ((symbol-function 'rename-file) (lambda (&rest _) nil))
              ((symbol-function 'copy-file) (lambda (&rest _) nil))
              ((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'find-file-noselect)
               (lambda (_) (get-buffer-create "*pdf-p24a*")))
              ((symbol-function 'org-latex-export-to-latex) (lambda (&rest _) nil))
              ((symbol-function 'a3madkour-pub-multi-pdf--list-svg-figures)
               (lambda (&rest _) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf/run
        "/tmp/x.org" "x" "/tmp/bundle/" "/tmp/templates/"
        :run (make-a3-pub-async-run :buffer (a3-pub-async/buffer))
        :on-done (lambda (s) (setq status s)))))
    (should (eq (plist-get status :status) 'err))
    (should (cl-some (lambda (p) (string-match-p "x\\.pdf" p)) deleted))))

(ert-deftest a3madkour-pub-multi-pdf/run-clean-chain-reports-ok ()
  "P2.4: a clean run (all passes rc=0, PDF produced) still reports :ok."
  (let (status)
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 0))
              ((symbol-function 'file-exists-p) (lambda (_) t))
              ((symbol-function 'delete-file) (lambda (&rest _) nil))
              ((symbol-function 'rename-file) (lambda (&rest _) nil))
              ((symbol-function 'copy-file) (lambda (&rest _) nil))
              ((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'find-file-noselect)
               (lambda (_) (get-buffer-create "*pdf-p24b*")))
              ((symbol-function 'org-latex-export-to-latex) (lambda (&rest _) nil))
              ((symbol-function 'a3madkour-pub-multi-pdf--list-svg-figures)
               (lambda (&rest _) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf/run
        "/tmp/x.org" "x" "/tmp/bundle/" "/tmp/templates/"
        :run (make-a3-pub-async-run :buffer (a3-pub-async/buffer))
        :on-done (lambda (s) (setq status s)))))
    (should (eq (plist-get status :status) 'ok))))

(provide 'a3madkour-publish-multi-pdf-test)
;;; a3madkour-publish-multi-pdf-test.el ends here
