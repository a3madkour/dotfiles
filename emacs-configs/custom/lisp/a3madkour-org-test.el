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

(ert-deftest a3madkour-org-test-table-line-helpers ()
  (should (a3madkour-org-table-rule-line-p "  |---+---|"))
  (should-not (a3madkour-org-table-rule-line-p "| a | b |"))
  (should (equal (a3madkour-org-table-row-cells "  | 2 | egg |  ") '("2" "egg")))
  (should (equal (a3madkour-org-table-row-cells "| a |  | b |") '("a" "" "b"))))

(defun a3madkour-org-test--stale-fixture (unsaved fn)
  "Visit a temp file holding \"old\", optionally add an unsaved edit, rewrite
it on disk as \"new\" with a later mtime, then call FN with (FILE BUFFER)."
  (let* ((dir (make-temp-file "a3org-sync" t))
         (f (expand-file-name "l.org" dir))
         (buf nil))
    (unwind-protect
        (progn
          (write-region "old" nil f nil 'silent)
          (setq buf (find-file-noselect f))
          (when unsaved
            (with-current-buffer buf (goto-char (point-max)) (insert "edit")))
          (write-region "new" nil f nil 'silent)
          (set-file-times f (time-add (current-time) 10))
          (funcall fn f buf))
      (when (buffer-live-p buf)
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (delete-directory dir t))))

(ert-deftest a3madkour-org-test-synced-buffer-reverts-stale ()
  (a3madkour-org-test--stale-fixture
   nil
   (lambda (f _buf)
     (should (equal (with-current-buffer (a3madkour-org-synced-buffer f "The list")
                      (buffer-string))
                    "new")))))

(ert-deftest a3madkour-org-test-synced-buffer-refuses-unsaved ()
  (a3madkour-org-test--stale-fixture
   t
   (lambda (f buf)
     (let ((err (should-error (a3madkour-org-synced-buffer f "The list")
                              :type 'user-error)))
       (should (equal (cadr err)
                      "The list has unsaved changes and the file changed on disk; save or revert it first")))
     (should (string-match-p "edit" (with-current-buffer buf (buffer-string))))
     (should (equal (with-temp-buffer (insert-file-contents f) (buffer-string))
                    "new")))))

(ert-deftest a3madkour-org-test-synced-buffer-creates-directory ()
  (let* ((dir (make-temp-file "a3org-sync" t))
         (buf nil))
    (unwind-protect
        (progn
          (setq buf (a3madkour-org-synced-buffer (expand-file-name "sub/new.org" dir) "X"))
          (should (bufferp buf))
          (should (file-directory-p (expand-file-name "sub" dir))))
      (when (buffer-live-p buf) (kill-buffer buf))
      (delete-directory dir t))))

(ert-deftest a3madkour-org-test-bracket-link-re ()
  (let ((re a3madkour-org-bracket-link-re))
    (should (string-match re "a [[file:x.png]] b"))
    (should (equal (match-string 1 "a [[file:x.png]] b") "file:x.png"))
    (should (null (match-string 2 "a [[file:x.png]] b")))
    (should (string-match re "[[id:u][the text]]"))
    (should (equal (match-string 2 "[[id:u][the text]]") "the text"))
    (should-not (string-match re "[[a][b [c]]]"))))

(provide 'a3madkour-org-test)
;;; a3madkour-org-test.el ends here
