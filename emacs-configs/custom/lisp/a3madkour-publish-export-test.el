;;; a3madkour-publish-export-test.el --- tests for -export.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the ox-hugo export wrapper.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-export)

(ert-deftest a3madkour-pub-export-test/export-file-returns-plist-shape ()
  "B.0 — `export-file' returns a plist with :body, :frontmatter, :warnings keys.
B.0 ships a skeleton that returns empty values; B.1 wires real ox-hugo."
  (let ((tmp (make-temp-file "b0-export-" nil ".org")))
    (unwind-protect
        (let ((result (a3madkour-pub-export/export-file tmp)))
          (should (plistp result))
          (should (memq :body result))
          (should (memq :frontmatter result))
          (should (memq :warnings result))
          ;; B.0 skeleton: body is empty string, frontmatter is nil, warnings is nil.
          (should (stringp (plist-get result :body)))
          (should (null (plist-get result :frontmatter)))
          (should (null (plist-get result :warnings))))
      (delete-file tmp))))

(provide 'a3madkour-publish-export-test)
;;; a3madkour-publish-export-test.el ends here
