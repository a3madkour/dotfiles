;;; a3madkour-publish-id-test.el --- Tests for ID dispatching -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-id)

(ert-deftest a3madkour-pub-id-test/id-to-file-resolves-known-uuid ()
  "--id-to-file returns the file path for a UUID known to org-roam."
  (cl-letf (((symbol-function 'org-roam-id-find)
             (lambda (id) (and (equal id "abc") "/tmp/known.org"))))
    (should (equal (a3madkour-pub--id-to-file "abc") "/tmp/known.org"))))

(ert-deftest a3madkour-pub-id-test/id-to-file-returns-nil-for-unknown ()
  "--id-to-file returns nil for an unknown UUID."
  (cl-letf (((symbol-function 'org-roam-id-find)
             (lambda (_id) nil)))
    (should-not (a3madkour-pub--id-to-file "not-a-real-uuid"))))

(ert-deftest a3madkour-pub-id-test/id-to-file-returns-nil-for-non-string ()
  "--id-to-file rejects non-string input gracefully."
  (should-not (a3madkour-pub--id-to-file nil))
  (should-not (a3madkour-pub--id-to-file 42)))

(ert-deftest a3madkour-pub-id-test/id-to-file-extracts-car-from-cons ()
  "Real org-roam-id-find returns (FILE . POS); the wrapper returns FILE.
Regression: A.1.b session-handoff flagged this as a latent risk because
the original cl-letf stubs returned plain strings; Task 19 spot-check
hit the cons shape against the real installed org-roam and erred in
`expand-file-name'.  This test pins the cons-handling."
  (cl-letf (((symbol-function 'org-roam-id-find)
             (lambda (id)
               (and (equal id "real-uuid") (cons "/abs/path/foo.org" 42)))))
    (should (equal (a3madkour-pub--id-to-file "real-uuid") "/abs/path/foo.org"))))

(ert-deftest a3madkour-pub-id-test/id-to-file-errors-on-unexpected-return ()
  "If a future org-roam version returns something other than nil/cons/string,
the wrapper errors loudly rather than silently corrupting downstream code."
  (cl-letf (((symbol-function 'org-roam-id-find)
             (lambda (_id) [vector "node" "struct"])))
    (should-error (a3madkour-pub--id-to-file "any") :type 'error)))

(provide 'a3madkour-publish-id-test)

;;; a3madkour-publish-id-test.el ends here
