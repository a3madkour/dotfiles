;;; a3madkour-publish-keywords-test.el --- Tests for keyword extraction -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'a3madkour-publish-keywords)

(ert-deftest a3madkour-pub-keywords-test/extract-finds-keyword-value ()
  "extract-keyword returns the value string for a present keyword."
  (with-temp-buffer
    (insert "#+title: My Note\n#+HUGO_PUBLISH: t\n* Body\n")
    (should (equal "My Note"
                   (a3madkour-pub-keywords/extract "title")))
    (should (equal "t"
                   (a3madkour-pub-keywords/extract "HUGO_PUBLISH")))))

(ert-deftest a3madkour-pub-keywords-test/extract-returns-nil-when-absent ()
  "extract-keyword returns nil if the keyword line is missing."
  (with-temp-buffer
    (insert "#+title: My Note\n* Body\n")
    (should (null (a3madkour-pub-keywords/extract "HUGO_PUBLISH")))))

(ert-deftest a3madkour-pub-keywords-test/extract-is-case-insensitive-on-key ()
  "Org keywords are case-insensitive; the helper matches both `HUGO_PUBLISH' and `hugo_publish'."
  (with-temp-buffer
    (insert "#+hugo_publish: t\n* Body\n")
    (should (equal "t" (a3madkour-pub-keywords/extract "HUGO_PUBLISH")))))

(ert-deftest a3madkour-pub-keywords-test/extract-trims-trailing-whitespace ()
  "Values are trimmed of leading/trailing whitespace."
  (with-temp-buffer
    (insert "#+HUGO_SECTION:  garden   \n* Body\n")
    (should (equal "garden"
                   (a3madkour-pub-keywords/extract "HUGO_SECTION")))))

(ert-deftest a3madkour-pub-keywords-test/extract-returns-empty-string-for-bare-keyword ()
  "Keyword with no value returns empty string, not nil."
  (with-temp-buffer
    (insert "#+HUGO_DRAFT:\n* Body\n")
    (should (equal "" (a3madkour-pub-keywords/extract "HUGO_DRAFT")))))

(ert-deftest a3madkour-pub-keywords-test/boolean-true ()
  "`t' (case-insensitive) is the only truthy value."
  (should (a3madkour-pub-keywords/boolean-p "t"))
  (should (a3madkour-pub-keywords/boolean-p "T"))
  (should-not (a3madkour-pub-keywords/boolean-p "true"))
  (should-not (a3madkour-pub-keywords/boolean-p "yes"))
  (should-not (a3madkour-pub-keywords/boolean-p "1"))
  (should-not (a3madkour-pub-keywords/boolean-p ""))
  (should-not (a3madkour-pub-keywords/boolean-p nil)))

(ert-deftest a3madkour-pub-keywords-test/aliases-splits-whitespace ()
  "HUGO_ALIASES values are whitespace-separated."
  (should (equal '("/garden/old/" "/garden/older/")
                 (a3madkour-pub-keywords/parse-aliases "/garden/old/ /garden/older/"))))

(ert-deftest a3madkour-pub-keywords-test/aliases-splits-commas-too ()
  "Commas are accepted as separators in addition to whitespace (forgiving)."
  (should (equal '("/garden/old/" "/garden/older/")
                 (a3madkour-pub-keywords/parse-aliases "/garden/old/, /garden/older/"))))

(ert-deftest a3madkour-pub-keywords-test/aliases-empty-input-nil ()
  (should (null (a3madkour-pub-keywords/parse-aliases nil)))
  (should (null (a3madkour-pub-keywords/parse-aliases "")))
  (should (null (a3madkour-pub-keywords/parse-aliases "   "))))

(ert-deftest a3madkour-pub-keywords-test/aliases-trims-empties ()
  (should (equal '("/garden/x/")
                 (a3madkour-pub-keywords/parse-aliases "  /garden/x/  ,  "))))

(provide 'a3madkour-publish-keywords-test)

;;; a3madkour-publish-keywords-test.el ends here
