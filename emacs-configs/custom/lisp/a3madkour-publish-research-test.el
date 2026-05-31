;;; a3madkour-publish-research-test.el --- tests for research handler  -*- lexical-binding: t; -*-

(require 'ert)
(require 'a3madkour-publish-research)

(ert-deftest a3madkour-pub-research--module-loads ()
  "Smoke: module loadable and exposes publish-research-file."
  (should (fboundp 'a3madkour-pub-research/publish-research-file)))

(provide 'a3madkour-publish-research-test)

;;; a3madkour-publish-research-test.el ends here
