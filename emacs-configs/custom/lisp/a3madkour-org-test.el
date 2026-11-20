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

(ert-deftest a3madkour-org-test-ast-table ()
  (let* ((ast (with-temp-buffer
                (insert "* R\n** Ingredients\ntext\n| qty | item |\n|-----+------|\n| 2 | [[id:x][egg]] |\n|   | *salt* |\n*** Sub\n| a |\n** Empty\n")
                (org-mode) (org-element-parse-buffer)))
         (hl (lambda (title)
               (org-element-map ast 'headline
                 (lambda (h) (and (equal (org-element-property :raw-value h) title) h))
                 nil t))))
    (should (equal (a3madkour-org-ast-table-rows
                    (a3madkour-org-ast-table-under (funcall hl "Ingredients")))
                   '(("qty" "item") ("2" "[[id:x][egg]]") ("" "*salt*"))))
    (should (null (a3madkour-org-ast-table-under (funcall hl "Empty"))))
    (should (null (a3madkour-org-ast-table-under (funcall hl "R"))))))

(ert-deftest a3madkour-org-test-table-rows-under ()
  (let ((p (lambda (line) (string-match-p "\\`\\*+ +Ingredients" line))))
    (with-temp-buffer
      (insert "* R\n** Ingredients :tag:\nnote\n  | qty | item |\n  |-----+------|\n  | 2 | egg |\n** Steps\n| x |\n")
      (should (equal (a3madkour-org-table-rows-under p) '(("qty" "item") ("2" "egg")))))
    (with-temp-buffer
      (insert "** Ingredients\nnone here\n** Steps\n| x |\n")
      (should (null (a3madkour-org-table-rows-under p))))
    (with-temp-buffer
      (insert "* Other\n| x |\n")
      (should (null (a3madkour-org-table-rows-under p))))))

(provide 'a3madkour-org-test)
;;; a3madkour-org-test.el ends here
