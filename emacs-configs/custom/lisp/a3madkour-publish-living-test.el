;;; a3madkour-publish-living-test.el --- tests for -living.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the publish-living top-level command.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-living)

(ert-deftest a3madkour-pub-living-test/command-defined-and-interactive ()
  "B.0 — `a3-publish-living' is defined and interactive."
  (should (fboundp 'a3-publish-living))
  (should (commandp 'a3-publish-living)))

(ert-deftest a3madkour-pub-living-test/empty-handler-set-runs-lifecycle-clean ()
  "B.0 — with no per-section handlers registered, running publish-living
walks the (empty) handler set, calls begin/finish, and exits cleanly.
No commits to the manifest; snapshot is cleared at end."
  (let ((tmp-data (make-temp-file "b0-living-" t)))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data)
              (a3madkour-pub/org-notes-dir tmp-data))
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes: []\n"))
          (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
            (a3-publish-living))
          ;; Snapshot cleared at end of finish-publish.
          (should-not a3madkour-pub--manifest-snapshot)
          ;; Accumulator empty (no record-publish calls happened).
          (should (zerop (hash-table-count a3madkour-pub--publish-run-accumulator))))
      (delete-directory tmp-data t))))

(provide 'a3madkour-publish-living-test)
;;; a3madkour-publish-living-test.el ends here
