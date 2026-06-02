;;; a3madkour-publish-multi-filter-test.el --- Tests for multi-export filter -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-multi-filter)

(ert-deftest a3madkour-pub-multi-filter/detects-opt-in-keyword ()
  "Buffer with `#+multi_export: t` is recognized as multi-export."
  (with-temp-buffer
    (insert "#+title: Demo\n#+multi_export: t\n\n* Heading\n")
    (org-mode)
    (should (a3madkour-pub-multi-filter--doc-p))))

(ert-deftest a3madkour-pub-multi-filter/rejects-missing-keyword ()
  "Buffer without `#+multi_export:` is not multi-export."
  (with-temp-buffer
    (insert "#+title: Demo\n\n* Heading\n")
    (org-mode)
    (should-not (a3madkour-pub-multi-filter--doc-p))))

(ert-deftest a3madkour-pub-multi-filter/rejects-falsy-value ()
  "Buffer with `#+multi_export: nil` (or any non-t value) is not multi-export."
  (with-temp-buffer
    (insert "#+multi_export: nil\n")
    (org-mode)
    (should-not (a3madkour-pub-multi-filter--doc-p))))

(provide 'a3madkour-publish-multi-filter-test)
;;; a3madkour-publish-multi-filter-test.el ends here
