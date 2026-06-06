;;; a3madkour-publish-async-test.el --- tests for -async.el  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-async)

(ert-deftest a3-pub-async-test/synchronous-p-defaults-nil ()
  "Async mode is the default; tests opt into sync mode."
  (should-not a3-pub-async--synchronous-p))

(ert-deftest a3-pub-async-test/synchronous-p-can-be-let-bound ()
  (let ((a3-pub-async--synchronous-p t))
    (should a3-pub-async--synchronous-p)))

(provide 'a3madkour-publish-async-test)
;;; a3madkour-publish-async-test.el ends here
