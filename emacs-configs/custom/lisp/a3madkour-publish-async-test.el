;;; a3madkour-publish-async-test.el --- tests for -async.el  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-async)

(ert-deftest a3-pub-async-test/synchronous-p-defaults-nil ()
  "Async mode is the default; tests opt into sync mode."
  (should-not a3-pub-async--synchronous-p))

(ert-deftest a3-pub-async-test/synchronous-p-can-be-let-bound ()
  (let ((a3-pub-async--synchronous-p t))
    (should a3-pub-async--synchronous-p)))

(ert-deftest a3-pub-async-test/run-process-sync-calls-on-done-with-rc ()
  "In sync mode, run-process invokes call-process and fires on-done
inline with (rc stderr-tail)."
  (let ((calls nil) (result nil))
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd _ _ _ &rest args)
                 (push (cons cmd args) calls) 0)))
      (let ((a3-pub-async--synchronous-p t))
        (a3-pub-async/run-process "true" '("a" "b")
                                  :on-done (lambda (rc tail)
                                             (setq result (cons rc tail))))))
    (should (equal (car calls) '("true" "a" "b")))
    (should (= 0 (car result)))
    (should (or (null (cdr result)) (string-empty-p (cdr result))))))

(ert-deftest a3-pub-async-test/run-process-sync-nonzero-rc-passes-through ()
  "Non-zero exit code is reported as-is to on-done."
  (let ((rc-seen nil))
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 2)))
      (let ((a3-pub-async--synchronous-p t))
        (a3-pub-async/run-process "false" nil
                                  :on-done (lambda (rc _tail) (setq rc-seen rc)))))
    (should (= 2 rc-seen))))

(provide 'a3madkour-publish-async-test)
;;; a3madkour-publish-async-test.el ends here
