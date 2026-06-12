;;; a3madkour-publish-poetry-test.el --- ert tests for works-poetry handler  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-poetry)
(require 'a3madkour-publish-deliberate)

(ert-deftest a3madkour-pub-poetry-test/module-provides ()
  "The poetry module loads and provides its feature."
  (should (featurep 'a3madkour-publish-poetry)))

(ert-deftest a3madkour-pub-poetry-test/dispatch-registered ()
  "The deliberate dispatch alist contains a works-poetry entry."
  (should (eq (cdr (assq 'works-poetry a3madkour-pub-deliberate--handlers))
              'a3madkour-pub-poetry/publish-poetry-file)))

(ert-deftest a3madkour-pub-poetry-test/section-dir-default ()
  "`section-dir-name' defaults to \"works/poetry\" (relative to site root)."
  (should (equal a3madkour-pub-poetry/section-dir-name "works/poetry")))

(provide 'a3madkour-publish-poetry-test)

;;; a3madkour-publish-poetry-test.el ends here
