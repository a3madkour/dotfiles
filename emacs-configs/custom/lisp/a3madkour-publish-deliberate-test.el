;;; a3madkour-publish-deliberate-test.el --- tests for -deliberate.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the publish-deliberate top-level command.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-deliberate)

(ert-deftest a3madkour-pub-delib-test/command-defined-and-interactive ()
  "B.0 — `a3-publish-deliberate' is defined and interactive."
  (should (fboundp 'a3-publish-deliberate))
  (should (commandp 'a3-publish-deliberate)))

(ert-deftest a3madkour-pub-delib-test/unknown-section-errors-clean ()
  "B.0 — given an org file with #+HUGO_SECTION: <known section>, but no
handler registered, signals `error' with a clear message identifying the
section.  This is B.0's expected behavior; B.1+ adds handlers.

Mirrors `a3madkour-pub-living-test/empty-handler-set-runs-lifecycle-clean'
in setting up `site-data-dir' + `org-notes-dir' + a seeded URL-history
manifest + an `org-roam-db-sync' stub so `begin-publish' succeeds and
control reaches the dispatch."
  (let* ((tmp-data (make-temp-file "b0-delib-" t))
         (tmp (expand-file-name "test.org" tmp-data)))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data)
              (a3madkour-pub/org-notes-dir tmp-data))
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes: []\n"))
          (with-temp-file tmp
            (insert "#+title: Test\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n:PROPERTIES:\n:ID: test-id-001\n:END:\n\nbody\n"))
          (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
            (let ((err-data (should-error (a3-publish-deliberate tmp))))
              (should (string-match-p "garden" (cadr err-data))))))
      (delete-directory tmp-data t))))

(ert-deftest a3madkour-pub-deliberate-test/essays-handler-registered ()
  "B.4 Task 9: 'essays is registered in the deliberate handler alist."
  (require 'a3madkour-publish-deliberate)
  (should (eq (cdr (assq 'essays a3madkour-pub-deliberate--handlers))
              'a3madkour-pub-essays/publish-essay-file)))

;; -- F Task 13: deliberate triggers cite emit-yaml --

(ert-deftest a3madkour-pub-deliberate-test/citations-emit-fires-after-finish ()
  "F Task 13: a3-publish-deliberate calls emit-yaml after finish-publish.
Under the async lifecycle, the handler's :on-done callback flows into
`a3-pub-async/finish-publish', which calls the legacy
`a3madkour-pub/finish-publish' and then emit-yaml on (ok deliberate).
Stub begin-publish, finish-publish, resolve-file-or-id, note-section,
and emit-yaml; bind handlers to an essays entry that fires :on-done with
'ok.  Assert call order: finish first, then emit."
  (let ((calls nil)
        (a3madkour-pub-deliberate--handlers
         (list (cons 'essays
                     (lambda (_file _run &rest rest)
                       (funcall (plist-get rest :on-done) 'ok))))))
    (cl-letf (((symbol-function 'a3madkour-pub/begin-publish) (lambda () nil))
              ((symbol-function 'a3madkour-pub/finish-publish)
               (lambda (&rest _) (push 'finish calls)))
              ((symbol-function 'a3madkour-pub--resolve-file-or-id)
               (lambda (_) "/fake/file.org"))
              ((symbol-function 'a3madkour-pub/note-section)
               (lambda (_) "essays"))
              ((symbol-function 'a3madkour-pub-citations/emit-yaml)
               (lambda (&rest _) (push 'emit calls)))
              ((symbol-function 'require)
               (lambda (feat &rest _) (or (memq feat features) t))))
      (let ((a3-pub-async--in-flight-run nil))
        (with-a3-pub-async-sync
         (a3-publish-deliberate "/fake/file.org")))
      (should (equal (reverse calls) '(finish emit))))))

(require 'a3madkour-publish-async)

(ert-deftest a3madkour-pub-delib-test/async-handler-receives-run-and-on-done ()
  "After conversion, the handler is called with (file run :on-done …).
The handler invokes on-done synchronously under with-a3-pub-async-sync,
which flows through to finish-publish."
  (let ((calls nil) (run-seen nil))
    (cl-letf*
        (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil))
         ((symbol-function 'a3madkour-pub/finish-publish)
          (lambda (&rest args) (push (cons 'finish args) calls)))
         ((symbol-function 'a3madkour-pub--resolve-file-or-id)
          (lambda (x) x))
         ((symbol-function 'a3madkour-pub/note-section)
          (lambda (_) "essays"))
         ((symbol-function 'a3madkour-pub-essays/publish-essay-file)
          (lambda (_file run &rest rest)
            (setq run-seen run)
            (let ((on-done (plist-get rest :on-done)))
              (funcall on-done 'ok)))))
      (let ((a3-pub-async--in-flight-run nil))
        (with-a3-pub-async-sync
         (a3-publish-deliberate "/tmp/fake.org"))))
    (should (a3-pub-async-run-p run-seen))
    (should (cl-find 'finish calls :key #'car))))

;; -- Tier 5.1: a3-unpublish-deliberate recovery command --

(defmacro a3-pub-unpub-delib-test--with-fixture (vars &rest body)
  "Build the on-disk fixture for `a3-unpublish-deliberate' tests.

VARS is a let-bindings-like list of additional bindings to evaluate
inside the unwind-protect.  Inside BODY the following are bound:
  CONTENT-ROOT     content/ temp dir
  BUNDLE           content-root/essays/x/
  MANIFEST-PATH    temp YAML file backing the manifest
  MANIFEST-INIT    fn taking a manifest alist; writes it + stubs path"
  (declare (indent 1))
  `(let* ((content-root (make-temp-file "a3-pub-unpub-delib-content-" t))
          (bundle (expand-file-name "essays/x" content-root))
          (manifest-path (make-temp-file "a3-pub-unpub-delib-history-" nil ".yaml"))
          ,@vars)
     (unwind-protect
         (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                    (lambda () manifest-path))
                   ((symbol-function 'a3madkour-pub-history--now-iso)
                    (lambda () "2026-06-08T12:00:00Z")))
           ,@body)
       (when (file-exists-p manifest-path) (delete-file manifest-path))
       (when (file-directory-p content-root) (delete-directory content-root t)))))

(defun a3-pub-unpub-delib-test--seed-manifest (manifest-path manifest)
  "Write MANIFEST to MANIFEST-PATH via `a3madkour-pub-history/write-manifest'."
  (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
             (lambda () manifest-path)))
    (a3madkour-pub-history/write-manifest manifest)))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-command-defined ()
  "5.1: `a3-unpublish-deliberate' is defined and interactive."
  (should (fboundp 'a3-unpublish-deliberate))
  (should (commandp 'a3-unpublish-deliberate)))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-happy-path ()
  "5.1 happy: bundle deleted, manifest advanced to `removed', plist returned."
  (a3-pub-unpub-delib-test--with-fixture ()
    (let ((a3madkour-pub-site-content-dir content-root))
      (make-directory bundle t)
      (with-temp-file (expand-file-name "index.md" bundle) (insert "x"))
      (a3-pub-unpub-delib-test--seed-manifest
       manifest-path
       '((notes . [((id . "id-x")
                    (current_url . "/essays/x/")
                    (history . [])
                    (state . "live"))])))
      (let ((result (a3-unpublish-deliberate "id-x")))
        (should (equal (plist-get result :id) "id-x"))
        (should (equal (plist-get result :url) "/essays/x/"))
        (should (equal (plist-get result :section) "essays"))
        (should (equal (plist-get result :slug) "x")))
      (should-not (file-directory-p bundle))
      (let* ((m (a3madkour-pub-history/read-manifest))
             (note (aref (alist-get 'notes m) 0)))
        (should (equal (alist-get 'state note) "removed"))))))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-unknown-id-user-errors ()
  "5.1: unknown id → user-error, manifest unchanged."
  (a3-pub-unpub-delib-test--with-fixture ()
    (let ((a3madkour-pub-site-content-dir content-root))
      (a3-pub-unpub-delib-test--seed-manifest
       manifest-path '((notes . [])))
      (should-error
       (a3-unpublish-deliberate "00000000-0000-0000-0000-000000000000")
       :type 'user-error))))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-already-removed-user-errors ()
  "5.1: idempotent guard — calling on an already-removed entry errors."
  (a3-pub-unpub-delib-test--with-fixture ()
    (let ((a3madkour-pub-site-content-dir content-root))
      (a3-pub-unpub-delib-test--seed-manifest
       manifest-path
       '((notes . [((id . "id-x")
                    (current_url . "/essays/x/")
                    (history . [])
                    (state . "removed"))])))
      (should-error (a3-unpublish-deliberate "id-x")
                    :type 'user-error))))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-living-section-refused ()
  "5.1: garden / library / research live in publish-living, not deliberate.
The recovery command refuses to operate on them — author should unmark
`#+HUGO_PUBLISH:' in the source and re-run publish-living instead."
  (a3-pub-unpub-delib-test--with-fixture ()
    (let ((a3madkour-pub-site-content-dir content-root))
      (a3-pub-unpub-delib-test--seed-manifest
       manifest-path
       '((notes . [((id . "id-g")
                    (current_url . "/garden/g/")
                    (history . [])
                    (state . "live"))])))
      (should-error (a3-unpublish-deliberate "id-g")
                    :type 'user-error)
      (let* ((m (a3madkour-pub-history/read-manifest))
             (note (aref (alist-get 'notes m) 0)))
        (should (equal (alist-get 'state note) "live"))))))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-delete-failed-keeps-manifest ()
  "5.1: when --unpublish-delete-bundle returns 'failed, the command signals
user-error and leaves the manifest at its prior state (mirrors bug 1.1's
self-healing contract: the bundle stays on disk + the manifest stays live,
so a later run can retry)."
  (a3-pub-unpub-delib-test--with-fixture ()
    (let ((a3madkour-pub-site-content-dir content-root))
      (make-directory bundle t)
      (with-temp-file (expand-file-name "index.md" bundle) (insert "x"))
      (a3-pub-unpub-delib-test--seed-manifest
       manifest-path
       '((notes . [((id . "id-x")
                    (current_url . "/essays/x/")
                    (history . [])
                    (state . "live"))])))
      (cl-letf (((symbol-function 'delete-directory)
                 (lambda (&rest _) (error "permission denied"))))
        (should-error (a3-unpublish-deliberate "id-x")
                      :type 'user-error))
      (let* ((m (a3madkour-pub-history/read-manifest))
             (note (aref (alist-get 'notes m) 0)))
        (should (equal (alist-get 'state note) "live"))))))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-bundle-absent-self-heals ()
  "5.1: stale-manifest recovery — when the bundle is already absent (delete
returns nil, not 'failed), the manifest is STILL advanced to `removed' so
the state converges.  This is the canonical \"hand-deleted the bundle but
forgot to update the manifest\" recovery case."
  (a3-pub-unpub-delib-test--with-fixture ()
    (let ((a3madkour-pub-site-content-dir content-root))
      ;; NB: do NOT create the bundle directory.
      (a3-pub-unpub-delib-test--seed-manifest
       manifest-path
       '((notes . [((id . "id-x")
                    (current_url . "/essays/x/")
                    (history . [])
                    (state . "live"))])))
      (a3-unpublish-deliberate "id-x")
      (let* ((m (a3madkour-pub-history/read-manifest))
             (note (aref (alist-get 'notes m) 0)))
        (should (equal (alist-get 'state note) "removed"))))))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-resolver-uuid-passthrough ()
  "5.1 resolver: a UUID string is returned verbatim — no file lookup.
Recovery often runs after the source file is gone; the manifest is the
source of truth for the id↔url mapping."
  (let ((id "deadbeef-0000-0000-0000-000000000000"))
    (should (equal (a3madkour-pub-deliberate--resolve-to-id id) id))))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-resolver-non-uuid-id-passthrough ()
  "5.1 resolver: any non-empty string that isn't an existing file is treated
as an opaque id (manifest contract doesn't require UUID format)."
  (should (equal (a3madkour-pub-deliberate--resolve-to-id "id-from-fixture")
                 "id-from-fixture")))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-resolver-file-path-lookups-id ()
  "5.1 resolver: a real file path is resolved via `note-metadata'."
  (let ((tmp (make-temp-file "a3-pub-unpub-resolver-" nil ".org")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
                   (lambda (_file) '(:id "id-from-file"))))
          (should (equal (a3madkour-pub-deliberate--resolve-to-id tmp)
                         "id-from-file")))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest a3madkour-pub-deliberate-test/unpublish-resolver-bogus-input-nil ()
  "5.1 resolver: nil / non-string / empty string → nil."
  (should (null (a3madkour-pub-deliberate--resolve-to-id nil)))
  (should (null (a3madkour-pub-deliberate--resolve-to-id "")))
  (should (null (a3madkour-pub-deliberate--resolve-to-id 42))))

(provide 'a3madkour-publish-deliberate-test)
;;; a3madkour-publish-deliberate-test.el ends here
