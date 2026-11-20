;;; a3madkour-org-test.el --- Tests for a3madkour-org -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'a3madkour-org)

(ert-deftest a3madkour-org-test-keyword ()
  (with-temp-buffer
    (insert "#+TITLE:  Toast \n#+hugo_section: recipes\n#+EMPTY:\n* H\n")
    (narrow-to-region (point-max) (point-max))
    (should (equal (a3madkour-org-keyword "TITLE") "Toast"))
    (should (equal (a3madkour-org-keyword "HUGO_SECTION") "recipes"))
    (should (equal (a3madkour-org-keyword "EMPTY") ""))
    (should (null (a3madkour-org-keyword "MISSING")))))

(ert-deftest a3madkour-org-test-keyword-in-string ()
  (should (equal (a3madkour-org-keyword-in-string "x\n#+title: A b \n" "TITLE") "A b"))
  (should (equal (a3madkour-org-keyword-in-string "#+EMPTY:\n" "EMPTY") ""))
  (should (null (a3madkour-org-keyword-in-string "no keywords" "TITLE"))))

(ert-deftest a3madkour-org-test-ast-keyword ()
  (let ((ast (with-temp-buffer
               (insert "#+hugo_section: works/games\n#+TITLE: T\n")
               (org-mode) (org-element-parse-buffer))))
    (should (equal (a3madkour-org-ast-keyword ast "HUGO_SECTION") "works/games"))
    (should (null (a3madkour-org-ast-keyword ast "MISSING")))))

(provide 'a3madkour-org-test)
;;; a3madkour-org-test.el ends here
