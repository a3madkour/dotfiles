;;; a3madkour-publish-garden-test.el --- tests for garden handler  -*- lexical-binding: t; -*-

(require 'ert)
(require 'a3madkour-publish-garden)

(ert-deftest a3madkour-pub-garden--module-loads ()
  "Smoke: module is loadable and exposes publish-garden-file."
  (should (fboundp 'a3madkour-pub-garden/publish-garden-file)))

(provide 'a3madkour-publish-garden-test)

;;; a3madkour-publish-garden-test.el ends here
