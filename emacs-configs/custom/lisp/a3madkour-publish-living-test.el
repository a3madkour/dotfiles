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

(ert-deftest a3madkour-pub-living-test/garden-handler-registered ()
  "B.1 — loading a3madkour-publish-garden registers the garden handler in
`a3madkour-pub-living--handlers' via the after-load form at the bottom of
this file's parent module.  Handler-alist keys are STRINGS (the canonical
`#+HUGO_SECTION:' value), so we look up via `assoc' not `assq'."
  (require 'a3madkour-publish-garden)
  (should (eq (cdr (assoc "garden" a3madkour-pub-living--handlers))
              'a3madkour-pub-garden/publish-garden-file)))

(ert-deftest a3madkour-pub-living-test/library-handlers-registered ()
  "B.2 — loading a3madkour-publish-library registers all 4 library
sections (`library/reading', `library/listening', `library/playing',
`library/watching') in `a3madkour-pub-living--handlers', each pointing
at `a3madkour-pub-library/publish-library-file'."
  (require 'a3madkour-publish-library)
  (dolist (section '("library/reading" "library/listening"
                     "library/playing" "library/watching"))
    (should (eq (cdr (assoc section a3madkour-pub-living--handlers))
                'a3madkour-pub-library/publish-library-file))))

(ert-deftest a3madkour-pub-living-test/walk-section-dispatches-on-string-key ()
  "B.1 regression — walk-section compares the section STRING key
directly to `note-section''s STRING value.  Pre-Task-11 used symbol
keys + `symbol-name' bridge which silently no-op'd on slash-form
sections (`library/reading' would intern to `library/reading' which
is not what `note-section' returns)."
  (require 'a3madkour-publish-garden)
  (let* ((notes-dir (make-temp-file "living-dispatch-" t))
         (site-dir  (make-temp-file "living-dispatch-site-" t))
         (src       (expand-file-name "dispatch-note.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (make-directory (expand-file-name "content/garden" site-dir) t)
          (with-temp-file src
            (insert ":PROPERTIES:\n"
                    ":ID: cccccccc-dddd-eeee-ffff-000000000000\n"
                    ":END:\n"
                    "#+title: Dispatch Note\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " site-dir "/\n"
                    "* Body\nDispatch test body.\n"))
          (with-temp-file (expand-file-name "data/url-history.yaml" site-dir)
            (insert "notes: []\n"))
          (let ((a3madkour-pub/site-data-dir (file-name-as-directory
                                              (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
              (a3-publish-living)))
          (should (file-exists-p
                   (expand-file-name "content/garden/dispatch-note/index.md"
                                     site-dir))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(provide 'a3madkour-publish-living-test)
;;; a3madkour-publish-living-test.el ends here
