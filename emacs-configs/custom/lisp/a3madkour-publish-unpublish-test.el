;;; a3madkour-publish-unpublish-test.el --- Tests for unpublish module -*- lexical-binding: t; -*-
;;
;;; Commentary:
;; ert tests for `a3madkour-publish-unpublish.el' (sub-project A.1.d).
;;
;;; Code:

(require 'ert)
(require 'a3madkour-publish-unpublish)

(ert-deftest a3madkour-pub-unpublish-test/skeleton-loaded ()
  "The unpublish module loads and its provide marker is registered."
  (should (featurep 'a3madkour-publish-unpublish)))

(provide 'a3madkour-publish-unpublish-test)
;;; a3madkour-publish-unpublish-test.el ends here
