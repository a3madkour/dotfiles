;;; a3madkour-publish-citations-test.el --- ert tests for F citations -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'a3madkour-publish-citations)

;; -- Helpers --

(defmacro a3madkour-pub-citations-test--with-org (org-string &rest body)
  "Insert ORG-STRING into a temp org buffer, run BODY there."
  (declare (indent 1))
  `(with-temp-buffer
     (org-mode)
     (insert ,org-string)
     (goto-char (point-min))
     ,@body))

;; -- Task 8: cite--scan-buffer --

(ert-deftest a3madkour-pub-citations-test/scan-bare-cite ()
  "F Task 8: a bare [cite:@k] is discovered."
  (a3madkour-pub-citations-test--with-org
      "* Heading\nBody [cite:@key1] more.\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should (= 1 (length pairs)))
      (should (equal "key1" (car (car pairs)))))))

(ert-deftest a3madkour-pub-citations-test/scan-multi-cite ()
  "F Task 8: [cite:@a;@b;@c] yields 3 pairs in source order."
  (a3madkour-pub-citations-test--with-org
      "Body [cite:@a;@b;@c] tail.\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should (= 3 (length pairs)))
      (should (equal '("a" "b" "c") (mapcar #'car pairs))))))

(ert-deftest a3madkour-pub-citations-test/scan-skips-src-blocks ()
  "F Task 8: [cite:@k] inside a #+BEGIN_SRC block is NOT discovered."
  (a3madkour-pub-citations-test--with-org
      "Body.\n#+BEGIN_SRC text\n[cite:@should-skip]\n#+END_SRC\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should-not pairs))))

(ert-deftest a3madkour-pub-citations-test/scan-skips-noexport-subtree ()
  "F Task 8: a :noexport: subtree is excluded from the scan."
  (a3madkour-pub-citations-test--with-org
      "* Public\nBody [cite:@public]\n* Private :noexport:\n[cite:@hidden]\n"
    (let* ((pairs (a3madkour-pub-citations--scan-buffer))
           (keys (mapcar #'car pairs)))
      ;; In org-element, :noexport: trees are still parsed; we filter them.
      ;; If org-element-parse-buffer does NOT filter them, this test pins
      ;; the requirement: scan must filter manually.
      (should (member "public" keys))
      (should-not (member "hidden" keys)))))

(ert-deftest a3madkour-pub-citations-test/scan-finds-cite-in-footnote ()
  "F Task 8: cite inside [fn:: ...] inline footnote is discovered."
  (a3madkour-pub-citations-test--with-org
      "Body[fn::See [cite:@fnkey].]\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should (member "fnkey" (mapcar #'car pairs))))))

(ert-deftest a3madkour-pub-citations-test/scan-finds-cite-in-table ()
  "F Task 8: cite inside a table cell is discovered."
  (a3madkour-pub-citations-test--with-org
      "| col |\n|-----|\n| [cite:@tab] |\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should (member "tab" (mapcar #'car pairs))))))

(ert-deftest a3madkour-pub-citations-test/scan-empty-buffer ()
  "F Task 8: empty buffer returns nil."
  (a3madkour-pub-citations-test--with-org ""
    (should-not (a3madkour-pub-citations--scan-buffer))))

(provide 'a3madkour-publish-citations-test)

;;; a3madkour-publish-citations-test.el ends here
