;;; a3madkour-publish-test.el --- Tests for a3madkour-publish -*- lexical-binding: t; -*-

;;; Commentary:

;; ert tests for a3madkour-publish.  Run via the `run-tests.sh' wrapper
;; in this directory, or directly:
;;
;;   emacs --batch -L . -l ert -l a3madkour-publish-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'a3madkour-publish)

(ert-deftest a3madkour-pub-test/library-loads ()
  "Smoke test: the library loads and exposes its version constant."
  (should (stringp a3madkour-pub/version))
  (should (string-match-p "^[0-9]+\\.[0-9]+\\." a3madkour-pub/version)))

(provide 'a3madkour-publish-test)

;;; a3madkour-publish-test.el ends here
