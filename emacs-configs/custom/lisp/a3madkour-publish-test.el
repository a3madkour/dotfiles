;;; a3madkour-publish-test.el --- Tests for a3madkour-publish -*- lexical-binding: t; -*-

;;; Commentary:

;; ert tests for a3madkour-publish.  Run via the `run-tests.sh' wrapper
;; in this directory, or directly:
;;
;;   emacs --batch -L . -l ert -l a3madkour-publish-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
;; Pre-require org-roam so `cl-letf' stubs of `org-roam-db-sync' in the
;; `begin-publish' tests aren't clobbered by a deferred `(require 'org-roam)'
;; inside the function-under-test (the first such require would load the
;; real org-roam.el and re-`defun' the stubbed symbol).
(require 'org-roam)
(require 'a3madkour-publish)

(ert-deftest a3madkour-pub-test/library-loads ()
  "Smoke test: the library loads and exposes its version constant."
  (should (stringp a3madkour-pub/version))
  (should (string-match-p "^[0-9]+\\.[0-9]+\\." a3madkour-pub/version)))

;; -- Section enum --

(ert-deftest a3madkour-pub-test/sections-includes-known-values ()
  "The section enum includes every section documented in the design spec."
  (dolist (s '("essays" "garden"
               "research/themes" "research/questions"
               "works/games" "works/music" "works/poetry"
               "library/reading" "library/listening" "library/playing" "library/watching"
               "streams" "about"))
    (should (a3madkour-pub/valid-section-p s))))

(ert-deftest a3madkour-pub-test/sections-rejects-unknown-values ()
  "The section enum rejects typos and unknown values."
  (should-not (a3madkour-pub/valid-section-p "esays"))
  (should-not (a3madkour-pub/valid-section-p "garden/topic"))
  (should-not (a3madkour-pub/valid-section-p ""))
  (should-not (a3madkour-pub/valid-section-p nil)))

;; -- published-p --

(defun a3madkour-pub-test--with-org-file (content thunk)
  "Write CONTENT to a tmp .org file and call THUNK with the file path.
Cleans up the tmp file afterwards."
  (let ((tmp (make-temp-file "a3-pub-test-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert content))
          (funcall thunk tmp))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-test/published-p-live ()
  "File with HUGO_PUBLISH: t + valid HUGO_SECTION + no HUGO_DRAFT → 'live."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f) (should (eq 'live (a3madkour-pub/published-p f))))))

(ert-deftest a3madkour-pub-test/published-p-draft ()
  "Add HUGO_DRAFT: t → 'draft."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+HUGO_DRAFT: t\n* Body\n"
   (lambda (f) (should (eq 'draft (a3madkour-pub/published-p f))))))

(ert-deftest a3madkour-pub-test/published-p-private-missing-publish ()
  "No HUGO_PUBLISH → nil."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f) (should (null (a3madkour-pub/published-p f))))))

(ert-deftest a3madkour-pub-test/published-p-publish-without-section-errors ()
  "HUGO_PUBLISH without HUGO_SECTION → user-error.
Default-deny means both keywords are required; setting just one is a likely
typo that should not silently succeed nor silently fail-private."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n* Body\n"
   (lambda (f) (should-error (a3madkour-pub/published-p f) :type 'user-error))))

(ert-deftest a3madkour-pub-test/published-p-unknown-section-errors ()
  "Unknown section value → user-error."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: gardn\n* Body\n"
   (lambda (f) (should-error (a3madkour-pub/published-p f) :type 'user-error))))

;; -- note-slug / note-section / note-url --

(ert-deftest a3madkour-pub-test/note-slug-uses-title-by-default ()
  (a3madkour-pub-test--with-org-file
   "#+title: Bayesian Statistics\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f)
     (should (equal "bayesian-statistics" (a3madkour-pub/note-slug f))))))

(ert-deftest a3madkour-pub-test/note-slug-honors-override ()
  (a3madkour-pub-test--with-org-file
   "#+title: Tractable Boolean Arithmetic\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+HUGO_SLUG: tba-2022\n* Body\n"
   (lambda (f)
     (should (equal "tba-2022" (a3madkour-pub/note-slug f))))))

(ert-deftest a3madkour-pub-test/note-section-returns-string-or-nil ()
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f) (should (equal "garden" (a3madkour-pub/note-section f)))))
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n* Body\n"
   (lambda (f) (should (null (a3madkour-pub/note-section f))))))

(ert-deftest a3madkour-pub-test/note-url-shape ()
  (a3madkour-pub-test--with-org-file
   "#+title: Bayesian Statistics\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f)
     (should (equal "/garden/bayesian-statistics/" (a3madkour-pub/note-url f))))))

(ert-deftest a3madkour-pub-test/note-url-with-nested-section ()
  (a3madkour-pub-test--with-org-file
   "#+title: Q One\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: research/questions\n* Body\n"
   (lambda (f)
     (should (equal "/research/questions/q-one/" (a3madkour-pub/note-url f))))))

(ert-deftest a3madkour-pub-test/note-url-nil-for-private ()
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n* Body\n"
   (lambda (f) (should (null (a3madkour-pub/note-url f))))))

;; -- note-metadata --

(ert-deftest a3madkour-pub-test/note-metadata-returns-plist ()
  "note-metadata returns a plist with :id :section :slug :state :file :title."
  (let ((file (make-temp-file "a3pub-meta-" nil ".org"
                              "#+title: My Note
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
:PROPERTIES:
:ID: 11111111-1111-1111-1111-111111111111
:END:
")))
    (unwind-protect
        (let ((md (a3madkour-pub/note-metadata file)))
          (should (equal (plist-get md :section) "garden"))
          (should (equal (plist-get md :slug) "my-note"))
          (should (equal (plist-get md :state) 'live))
          (should (equal (plist-get md :file) file))
          (should (equal (plist-get md :title) "My Note"))
          (should (equal (plist-get md :id) "11111111-1111-1111-1111-111111111111")))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/note-metadata-returns-nil-for-unpublished ()
  "note-metadata returns nil when HUGO_PUBLISH is absent."
  (let ((file (make-temp-file "a3pub-meta-" nil ".org" "#+title: Plain note\n")))
    (unwind-protect
        (should-not (a3madkour-pub/note-metadata file))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/note-metadata-draft-state ()
  "note-metadata returns :state 'draft when HUGO_DRAFT: t."
  (let ((file (make-temp-file "a3pub-meta-" nil ".org"
                              "#+title: Draft
#+HUGO_PUBLISH: t
#+HUGO_SECTION: essays
#+HUGO_DRAFT: t
")))
    (unwind-protect
        (should (equal (plist-get (a3madkour-pub/note-metadata file) :state) 'draft))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/note-metadata-cache-hit ()
  "A second call to note-metadata on the same FILE returns cached value
without re-parsing the file (verified by mutating the file between
calls and observing the original value still returned)."
  (let ((file (make-temp-file "a3pub-cache-" nil ".org"
                              "#+title: V1
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
")))
    (unwind-protect
        (progn
          (a3madkour-pub--reset-metadata-cache)  ; start clean
          (let ((md1 (a3madkour-pub/note-metadata file)))
            (should (equal (plist-get md1 :title) "V1"))
            ;; Mutate file under the cache's feet
            (with-temp-file file
              (insert "#+title: V2\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n"))
            (let ((md2 (a3madkour-pub/note-metadata file)))
              ;; Cache hit: still V1, not V2
              (should (equal (plist-get md2 :title) "V1")))))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/note-metadata-cache-explicit-reset ()
  "After --reset-metadata-cache, the next note-metadata call re-parses."
  (let ((file (make-temp-file "a3pub-cache-" nil ".org"
                              "#+title: V1
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
")))
    (unwind-protect
        (progn
          (a3madkour-pub--reset-metadata-cache)
          (a3madkour-pub/note-metadata file)  ; populate
          (with-temp-file file
            (insert "#+title: V2\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n"))
          (a3madkour-pub--reset-metadata-cache)  ; reset
          (should (equal (plist-get (a3madkour-pub/note-metadata file) :title) "V2")))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/note-metadata-cache-multiple-files ()
  "The cache distinguishes between multiple files keyed by abs path."
  (let ((f1 (make-temp-file "a3pub-multi-1-" nil ".org"
                            "#+title: One
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
"))
        (f2 (make-temp-file "a3pub-multi-2-" nil ".org"
                            "#+title: Two
#+HUGO_PUBLISH: t
#+HUGO_SECTION: essays
")))
    (unwind-protect
        (progn
          (a3madkour-pub--reset-metadata-cache)
          (should (equal (plist-get (a3madkour-pub/note-metadata f1) :title) "One"))
          (should (equal (plist-get (a3madkour-pub/note-metadata f2) :title) "Two"))
          (should (equal (plist-get (a3madkour-pub/note-metadata f1) :section) "garden"))
          (should (equal (plist-get (a3madkour-pub/note-metadata f2) :section) "essays")))
      (delete-file f1)
      (delete-file f2))))

;; -- begin-publish entry-point --

(ert-deftest a3madkour-pub-test/begin-publish-resets-cache ()
  "begin-publish clears the metadata cache."
  (puthash "/some/file" '(:title "stale") a3madkour-pub--metadata-cache)
  (let ((a3madkour-pub--manifest-snapshot nil))
    (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil))
              ((symbol-function 'a3madkour-pub-history/read-manifest)
               (lambda () '((notes . [])))))
      (a3madkour-pub/begin-publish)))
  (should (zerop (hash-table-count a3madkour-pub--metadata-cache))))

(ert-deftest a3madkour-pub-test/begin-publish-invokes-org-roam-db-sync ()
  "begin-publish calls (org-roam-db-sync) to snapshot ID resolution state.
Binds `org-roam-directory' to a real tmp dir so the missing-dir gate
introduced in `begin-publish' doesn't short-circuit the sync call."
  (let* ((real-dir (file-name-as-directory
                    (make-temp-file "a3-pub-org-roam-dir-" t)))
         (org-roam-directory real-dir)
         (a3madkour-pub--manifest-snapshot nil)
         (called nil))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () (setq called t)))
                    ((symbol-function 'a3madkour-pub-history/read-manifest)
                     (lambda () '((notes . [])))))
            (a3madkour-pub/begin-publish))
          (should called))
      (delete-directory real-dir t))))

(ert-deftest a3madkour-pub-test/begin-publish-skips-org-roam-db-sync-when-dir-missing ()
  "begin-publish must NOT call `org-roam-db-sync' when `org-roam-directory'
does not point to an existing directory on disk.

This guards the batch-publish path: shell/CI invocations of the publisher
run via `emacs --batch' without the author's interactive config, so
`org-roam-directory' may still be the package default (~/org-roam/) even
when the real notes live elsewhere.  Calling `org-roam-db-sync' against a
non-existent dir crashes the run.  See A.1.d known limitations."
  (let* ((bogus-dir (expand-file-name
                     (format "definitely-does-not-exist-%d-%d/"
                             (emacs-pid) (random 1000000))
                     temporary-file-directory))
         (org-roam-directory bogus-dir)
         (a3madkour-pub--manifest-snapshot nil))
    (should-not (file-directory-p bogus-dir))
    (cl-letf (((symbol-function 'org-roam-db-sync)
               (lambda ()
                 (error "org-roam-db-sync was called despite missing dir %s"
                        bogus-dir)))
              ((symbol-function 'a3madkour-pub-history/read-manifest)
               (lambda () '((notes . [])))))
      ;; Should complete cleanly; the tripwire would raise if the gate is missing.
      (a3madkour-pub/begin-publish))))

(ert-deftest a3madkour-pub-test/begin-publish-calls-org-roam-db-sync-when-dir-exists ()
  "begin-publish must still call `org-roam-db-sync' when `org-roam-directory'
points to a real directory on disk.

Complements the missing-dir test: confirms the gate doesn't accidentally
suppress the sync in the normal author workflow where ~/org-roam/ (or the
configured equivalent) does exist."
  (let* ((real-dir (file-name-as-directory
                    (make-temp-file "a3-pub-org-roam-dir-" t)))
         (org-roam-directory real-dir)
         (a3madkour-pub--manifest-snapshot nil)
         (called nil))
    (unwind-protect
        (progn
          (should (file-directory-p real-dir))
          (cl-letf (((symbol-function 'org-roam-db-sync)
                     (lambda () (setq called t)))
                    ((symbol-function 'a3madkour-pub-history/read-manifest)
                     (lambda () '((notes . [])))))
            (a3madkour-pub/begin-publish))
          (should called))
      (delete-directory real-dir t))))

;; -- file-or-id dispatch --
;;
;; The accessors (published-p, note-section, note-slug, note-url) accept
;; EITHER a file path OR an org-roam UUID string.  Dispatch is by RFC 4122
;; shape (8-4-4-4-12 hex), so test inputs must use real UUID-shaped values;
;; placeholder strings like "uuid-abc" would slip through the regex and be
;; treated as file paths.

(ert-deftest a3madkour-pub-test/published-p-accepts-uuid ()
  "published-p resolves a UUID via --id-to-file, then dispatches to file path."
  (let ((file (make-temp-file "a3pub-uuid-" nil ".org"
                              "#+title: UUID note
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                   (lambda (id)
                     (and (equal id "11111111-1111-1111-1111-111111111111") file))))
          (a3madkour-pub--reset-metadata-cache)
          (should (equal (a3madkour-pub/published-p
                          "11111111-1111-1111-1111-111111111111")
                         'live)))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/note-url-accepts-uuid ()
  "note-url resolves a UUID and returns the published URL."
  (let ((file (make-temp-file "a3pub-uuid-" nil ".org"
                              "#+title: UUID note
#+HUGO_PUBLISH: t
#+HUGO_SECTION: essays
")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                   (lambda (id)
                     (and (equal id "22222222-2222-2222-2222-222222222222") file))))
          (a3madkour-pub--reset-metadata-cache)
          (should (equal (a3madkour-pub/note-url
                          "22222222-2222-2222-2222-222222222222")
                         "/essays/uuid-note/")))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/note-section-accepts-uuid ()
  "note-section resolves a UUID and returns the section string."
  (let ((file (make-temp-file "a3pub-uuid-" nil ".org"
                              "#+title: U
#+HUGO_PUBLISH: t
#+HUGO_SECTION: works/games
")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                   (lambda (id)
                     (and (equal id "33333333-3333-3333-3333-333333333333") file))))
          (a3madkour-pub--reset-metadata-cache)
          (should (equal (a3madkour-pub/note-section
                          "33333333-3333-3333-3333-333333333333")
                         "works/games")))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/note-slug-accepts-uuid ()
  "note-slug resolves a UUID and returns the derived slug."
  (let ((file (make-temp-file "a3pub-uuid-" nil ".org"
                              "#+title: Sluggable Title
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                   (lambda (id)
                     (and (equal id "44444444-4444-4444-4444-444444444444") file))))
          (a3madkour-pub--reset-metadata-cache)
          (should (equal (a3madkour-pub/note-slug
                          "44444444-4444-4444-4444-444444444444")
                         "sluggable-title")))
      (delete-file file))))

(ert-deftest a3madkour-pub-test/accessors-return-nil-for-unknown-uuid ()
  "Accessors return nil cleanly when --id-to-file returns nil."
  (cl-letf (((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil)))
    (a3madkour-pub--reset-metadata-cache)
    (should-not (a3madkour-pub/published-p
                 "55555555-5555-5555-5555-555555555555"))
    (should-not (a3madkour-pub/note-url
                 "55555555-5555-5555-5555-555555555555"))
    (should-not (a3madkour-pub/note-section
                 "55555555-5555-5555-5555-555555555555"))
    (should-not (a3madkour-pub/note-slug
                 "55555555-5555-5555-5555-555555555555"))))

;; -- A.1.d: publish-run-accumulator + begin-publish extension --

(ert-deftest a3madkour-pub-test/publish-run-accumulator-is-hash-table ()
  "The accumulator defvar is bound to a hash table with equal test."
  (should (hash-table-p a3madkour-pub--publish-run-accumulator))
  (should (eq (hash-table-test a3madkour-pub--publish-run-accumulator) 'equal)))

(ert-deftest a3madkour-pub-test/begin-publish-clears-accumulator ()
  "`begin-publish' empties the accumulator alongside the metadata cache."
  (puthash "stale-id" '("/garden/old/" . live) a3madkour-pub--publish-run-accumulator)
  (should (> (hash-table-count a3madkour-pub--publish-run-accumulator) 0))
  (let ((a3madkour-pub--manifest-snapshot nil))
    (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil))
              ((symbol-function 'a3madkour-pub-history/read-manifest)
               (lambda () '((notes . [])))))
      (a3madkour-pub/begin-publish)))
  (should (= 0 (hash-table-count a3madkour-pub--publish-run-accumulator))))

;; -- B.0: manifest-snapshot defvar --

(ert-deftest a3madkour-pub-test/manifest-snapshot-defvar-exists ()
  "B.0 — `a3madkour-pub--manifest-snapshot' defvar is defined and starts nil."
  (should (boundp 'a3madkour-pub--manifest-snapshot))
  (should (null a3madkour-pub--manifest-snapshot)))

(ert-deftest a3madkour-pub-test/begin-publish-populates-manifest-snapshot ()
  "B.0 — `begin-publish' reads url-history.yaml into the snapshot defvar.
Uses a temp data dir with a seeded manifest; stubs org-roam-db-sync."
  (let ((tmp-data (make-temp-file "b0-snapshot-" t))
        (a3madkour-pub--manifest-snapshot nil))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data))
          ;; Seed a minimal manifest on disk.
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes:\n  - id: abc-123\n    current_url: /garden/foo/\n    history: []\n    state: live\n"))
          ;; Stub org-roam to avoid touching the user's real DB.
          (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
            (a3madkour-pub/begin-publish))
          ;; Snapshot should now hold the manifest alist.
          (should a3madkour-pub--manifest-snapshot)
          (let* ((notes (alist-get 'notes a3madkour-pub--manifest-snapshot)))
            (should (= 1 (length notes)))
            (should (equal "abc-123" (alist-get 'id (aref notes 0))))))
      (delete-directory tmp-data t))))

(ert-deftest a3madkour-pub-test/essays-dir-defvar-exists ()
  "B.4 Task 1: `a3madkour-pub/essays-dir' must be a defcustom or defvar,
non-empty string, defaulting to a path under ~/org/."
  (should (boundp 'a3madkour-pub/essays-dir))
  (should (stringp a3madkour-pub/essays-dir))
  (should (not (string-empty-p a3madkour-pub/essays-dir)))
  (should (string-match-p "/org/essays" a3madkour-pub/essays-dir)))

(provide 'a3madkour-publish-test)

;;; a3madkour-publish-test.el ends here
