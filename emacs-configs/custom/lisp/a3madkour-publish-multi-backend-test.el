;;; a3madkour-publish-multi-backend-test.el --- Tests for shared D.2 backend scaffold (P3.3) -*- lexical-binding: t; -*-
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-multi-backend)

(ert-deftest a3madkour-pub-multi-backend-test/probe-tools ()
  "probe-tools returns the unresolvable commands in order; nil when all resolve."
  (cl-letf (((symbol-function 'executable-find)
             (lambda (cmd) (member cmd '("xelatex" "pandoc")))))
    (should (null (a3madkour-pub-multi-backend/probe-tools '("xelatex" "pandoc"))))
    (should (equal (a3madkour-pub-multi-backend/probe-tools '("xelatex" "biber" "rsvg-convert"))
                   '("biber" "rsvg-convert")))))

(ert-deftest a3madkour-pub-multi-backend-test/convert-svgs-fan-empty-fires-immediately ()
  "An empty PAIRS list invokes ON-DONE right away (with nil), no processes."
  (let ((fired 'no))
    (a3madkour-pub-multi-backend/convert-svgs-fan
     nil "rsvg-convert" '("-f" "pdf")
     :on-done (lambda (rcs) (setq fired rcs)))
    (should (null fired))))

(ert-deftest a3madkour-pub-multi-backend-test/convert-svgs-fan-splices-fmt-args ()
  "Each spawn runs COMMAND with FMT-ARGS spliced ahead of `SRC -o DST'."
  (let (captured)
    (cl-letf (((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'a3-pub-async/barrier)
               (lambda (_n &key on-all-done) (lambda (_rc) (funcall on-all-done '(0)))))
              ((symbol-function 'a3-pub-async/run-process)
               (lambda (cmd args &rest _) (push (cons cmd args) captured))))
      (a3madkour-pub-multi-backend/convert-svgs-fan
       '(("/a/fig.svg" "/out/fig.png")) "rsvg-convert" '("-f" "png" "-d" "192")
       :name-prefix "rsvg-png" :on-done #'ignore))
    (should (equal (car captured)
                   '("rsvg-convert" "-f" "png" "-d" "192" "/a/fig.svg" "-o" "/out/fig.png")))))

(ert-deftest a3madkour-pub-multi-backend-test/log-line-success-and-failure ()
  "log-line emits a ✓ line with the path on success, ✗ + snippet on failure."
  (with-temp-buffer
    (a3madkour-pub-multi-backend/log-line (current-buffer) "pdf" t "/out/x.pdf" 7.2 nil)
    (should (string-match-p "\\[✓\\] pdf" (buffer-string)))
    (should (string-match-p "/out/x.pdf" (buffer-string))))
  (with-temp-buffer
    (a3madkour-pub-multi-backend/log-line (current-buffer) "word" nil nil 4.0 "boom")
    (should (string-match-p "\\[✗\\] word" (buffer-string)))
    (should (string-match-p "boom" (buffer-string)))))

(provide 'a3madkour-publish-multi-backend-test)
;;; a3madkour-publish-multi-backend-test.el ends here
