;;; a3madkour-publish-unpublish-test.el --- Tests for unpublish module -*- lexical-binding: t; -*-
;;
;;; Commentary:
;; ert tests for `a3madkour-publish-unpublish.el' (sub-project A.1.d).
;;
;;; Code:

(require 'ert)
(require 'a3madkour-publish-unpublish)

(ert-deftest a3madkour-pub-unpublish-test/skeleton-loaded ()
  "The unpublish module loads and its provide marker is registered."
  (should (featurep 'a3madkour-publish-unpublish)))

;; -- diff-published-set: pure diff over manifest live+draft vs new-set --

(defmacro a3-pub-unpublish-test--with-manifest (manifest &rest body)
  "Stub pub-history/read-manifest to return MANIFEST for BODY."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'a3madkour-pub-history/read-manifest)
              (lambda () ,manifest)))
     ,@body))

(defun a3-pub-unpublish-test--mk-new-set (&rest entries)
  "Build a hash table id → (url . state) from ENTRIES of (id url state)."
  (let ((h (make-hash-table :test 'equal)))
    (dolist (e entries)
      (puthash (nth 0 e) (cons (nth 1 e) (nth 2 e)) h))
    h))

(ert-deftest a3madkour-pub-unpublish-test/diff-added-only ()
  "New ids that aren't in manifest land in :added."
  (a3-pub-unpublish-test--with-manifest '((notes . []))
    (let* ((new (a3-pub-unpublish-test--mk-new-set
                 '("id-new" "/garden/x/" live)))
           (d (a3madkour-pub/diff-published-set new)))
      (should (equal (plist-get d :added) '("id-new")))
      (should (null (plist-get d :removed)))
      (should (null (plist-get d :stayed)))
      (should (null (plist-get d :slug-shifted))))))

(ert-deftest a3madkour-pub-unpublish-test/diff-removed-only ()
  "Manifest ids absent from new-set land in :removed."
  (a3-pub-unpublish-test--with-manifest
      '((notes . [((id . "id-gone") (current_url . "/garden/g/")
                   (history . []) (state . "live"))]))
    (let* ((new (a3-pub-unpublish-test--mk-new-set))
           (d (a3madkour-pub/diff-published-set new)))
      (should (equal (plist-get d :removed) '("id-gone"))))))

(ert-deftest a3madkour-pub-unpublish-test/diff-stayed-only ()
  "Ids present in both with identical URLs land in :stayed (not :slug-shifted)."
  (a3-pub-unpublish-test--with-manifest
      '((notes . [((id . "id-same") (current_url . "/garden/x/")
                   (history . []) (state . "live"))]))
    (let* ((new (a3-pub-unpublish-test--mk-new-set
                 '("id-same" "/garden/x/" live)))
           (d (a3madkour-pub/diff-published-set new)))
      (should (equal (plist-get d :stayed) '("id-same")))
      (should (null (plist-get d :slug-shifted))))))

(ert-deftest a3madkour-pub-unpublish-test/diff-slug-shifted ()
  "Ids present in both with different URLs land in :slug-shifted (+ also in :stayed)."
  (a3-pub-unpublish-test--with-manifest
      '((notes . [((id . "id-shift") (current_url . "/garden/foo/")
                   (history . []) (state . "live"))]))
    (let* ((new (a3-pub-unpublish-test--mk-new-set
                 '("id-shift" "/garden/foo-v2/" live)))
           (d (a3madkour-pub/diff-published-set new)))
      (should (equal (plist-get d :stayed) '("id-shift")))
      (should (equal (plist-get d :slug-shifted)
                     '(("id-shift" "/garden/foo/" "/garden/foo-v2/")))))))

(ert-deftest a3madkour-pub-unpublish-test/diff-mixed ()
  "Mixed scenario: 1 added + 1 removed + 1 stayed + 1 slug-shifted."
  (a3-pub-unpublish-test--with-manifest
      '((notes . [((id . "id-gone")  (current_url . "/garden/g/")
                   (history . []) (state . "live"))
                  ((id . "id-same")  (current_url . "/garden/s/")
                   (history . []) (state . "live"))
                  ((id . "id-shift") (current_url . "/garden/a/")
                   (history . []) (state . "live"))]))
    (let* ((new (a3-pub-unpublish-test--mk-new-set
                 '("id-new"   "/garden/n/" live)
                 '("id-same"  "/garden/s/" live)
                 '("id-shift" "/garden/b/" live)))
           (d (a3madkour-pub/diff-published-set new)))
      (should (equal (sort (plist-get d :added) #'string<) '("id-new")))
      (should (equal (plist-get d :removed) '("id-gone")))
      (should (member "id-same" (plist-get d :stayed)))
      (should (member "id-shift" (plist-get d :stayed)))
      (should (equal (plist-get d :slug-shifted)
                     '(("id-shift" "/garden/a/" "/garden/b/")))))))

(ert-deftest a3madkour-pub-unpublish-test/diff-ignores-removed-state-in-manifest ()
  "Manifest entries already in state `removed' are not in old-set; not :removed-again."
  (a3-pub-unpublish-test--with-manifest
      '((notes . [((id . "id-old-removed") (current_url . nil)
                   (history . [((url . "/garden/x/") (replaced_at . "t")
                                (reason . "removed"))])
                   (state . "removed"))]))
    (let* ((new (a3-pub-unpublish-test--mk-new-set))
           (d (a3madkour-pub/diff-published-set new)))
      (should (null (plist-get d :removed))))))

;; -- walk-published-source-set: standalone-mode driver --

(defmacro a3-pub-unpublish-test--with-tmp-notes-dir (dir-var &rest body)
  "Bind DIR-VAR to a fresh tmpdir + bind `a3madkour-pub/org-notes-dir' to it."
  (declare (indent 1))
  `(let* ((,dir-var (make-temp-file "a3-pub-walk-" t))
          (a3madkour-pub/org-notes-dir ,dir-var))
     (unwind-protect (progn ,@body)
       (delete-directory ,dir-var t))))

(defun a3-pub-unpublish-test--write-org (dir relpath body)
  "Write BODY to DIR/RELPATH (creating parent dirs as needed)."
  (let ((full (expand-file-name relpath dir)))
    (make-directory (file-name-directory full) t)
    (with-temp-file full (insert body))))

(ert-deftest a3madkour-pub-unpublish-test/walk-empty-dir ()
  "Empty notes dir → empty hash table."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (let ((result (a3madkour-pub/walk-published-source-set)))
      (should (hash-table-p result))
      (should (= 0 (hash-table-count result))))))

(ert-deftest a3madkour-pub-unpublish-test/walk-respects-hugo-publish-gate ()
  "Notes without `#+HUGO_PUBLISH: t' are skipped."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (a3-pub-unpublish-test--write-org d "yes.org"
      ":PROPERTIES:\n:ID: yes-id-1\n:END:\n#+TITLE: Yes\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\nbody\n")
    (a3-pub-unpublish-test--write-org d "no.org"
      ":PROPERTIES:\n:ID: no-id-1\n:END:\n#+TITLE: No\nbody\n")
    (let ((result (a3madkour-pub/walk-published-source-set)))
      (should (= 1 (hash-table-count result)))
      (should (gethash "yes-id-1" result))
      (should (null (gethash "no-id-1" result))))))

(ert-deftest a3madkour-pub-unpublish-test/walk-distinguishes-live-vs-draft ()
  "`#+HUGO_DRAFT: t' yields state `draft'; absent yields `live'."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (a3-pub-unpublish-test--write-org d "live.org"
      ":PROPERTIES:\n:ID: live-id-1\n:END:\n#+TITLE: Live\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\nbody\n")
    (a3-pub-unpublish-test--write-org d "draft.org"
      ":PROPERTIES:\n:ID: draft-id-1\n:END:\n#+TITLE: Draft\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+HUGO_DRAFT: t\nbody\n")
    (let ((result (a3madkour-pub/walk-published-source-set)))
      (should (equal (cdr (gethash "live-id-1" result)) 'live))
      (should (equal (cdr (gethash "draft-id-1" result)) 'draft)))))

(ert-deftest a3madkour-pub-unpublish-test/walk-skips-files-without-id ()
  "Files missing :ID: are skipped (not in result)."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (a3-pub-unpublish-test--write-org d "noid.org"
      "#+TITLE: No id\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\nbody\n")
    (let ((result (a3madkour-pub/walk-published-source-set)))
      (should (= 0 (hash-table-count result))))))

;; -- unpublish--delete-bundle helper --

(ert-deftest a3madkour-pub-unpublish-test/delete-bundle-happy ()
  "Existing bundle dir is removed recursively."
  (let* ((root (make-temp-file "a3-pub-content-" t))
         (bundle (expand-file-name "garden/foo" root)))
    (unwind-protect
        (progn
          (make-directory bundle t)
          (with-temp-file (expand-file-name "index.md" bundle) (insert "x"))
          (should (file-directory-p bundle))
          (a3madkour-pub--unpublish-delete-bundle "garden" "foo" root)
          (should-not (file-directory-p bundle)))
      (delete-directory root t))))

(ert-deftest a3madkour-pub-unpublish-test/delete-bundle-missing-dir-silent ()
  "Missing bundle dir is not an error (info log only)."
  (let ((root (make-temp-file "a3-pub-content-" t)))
    (unwind-protect
        ;; Should not raise:
        (a3madkour-pub--unpublish-delete-bundle "garden" "never-existed" root)
      (delete-directory root t))))

(ert-deftest a3madkour-pub-unpublish-test/delete-bundle-permission-error-returns-failed ()
  "Errors raised by delete-directory are caught; returns 'failed (not propagated).

B.1.1: prior contract was to propagate; updated to catch + WARN."
  (let* ((root (make-temp-file "a3-pub-content-" t))
         (bundle (expand-file-name "garden/foo" root)))
    (unwind-protect
        (progn
          (make-directory bundle t)
          (cl-letf (((symbol-function 'delete-directory)
                     (lambda (&rest _) (error "permission denied"))))
            (should (eq 'failed
                        (a3madkour-pub--unpublish-delete-bundle "garden" "foo" root)))))
      (delete-directory root t))))

;; -- url-to-section-slug: URL parser edge cases --

(ert-deftest a3madkour-pub-unpublish-test/url-to-section-slug-cases ()
  "URL parser covers nested sections + nil/empty/malformed edge cases."
  ;; Happy paths.
  (should (equal (a3madkour-pub--unpublish-url-to-section-slug "/garden/foo/")
                 '("garden" . "foo")))
  (should (equal (a3madkour-pub--unpublish-url-to-section-slug "/research/questions/q/")
                 '("research/questions" . "q")))
  (should (equal (a3madkour-pub--unpublish-url-to-section-slug "/works/games/pong/")
                 '("works/games" . "pong")))
  ;; Edge cases — all return nil.
  (should (null (a3madkour-pub--unpublish-url-to-section-slug nil)))
  (should (null (a3madkour-pub--unpublish-url-to-section-slug "")))
  (should (null (a3madkour-pub--unpublish-url-to-section-slug "no-leading-slash/foo/")))
  (should (null (a3madkour-pub--unpublish-url-to-section-slug "/single-segment/")))
  ;; Trailing slashes are stripped; multiple internal slashes tolerated.
  (should (equal (a3madkour-pub--unpublish-url-to-section-slug "/garden/foo")
                 '("garden" . "foo")))
  (should (equal (a3madkour-pub--unpublish-url-to-section-slug "//garden//foo//")
                 '("garden" . "foo"))))

;; -- finish-publish: Step A skeleton --

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-step-a-happy ()
  "Step A: one removed note → bundle deleted, manifest mutated, :removed populated."
  (let* ((content-root (make-temp-file "a3-pub-content-" t))
         (bundle (expand-file-name "garden/gone" content-root))
         (manifest-path (make-temp-file "a3-pub-history-" nil ".yaml")))
    (unwind-protect
        (progn
          (make-directory bundle t)
          (with-temp-file (expand-file-name "index.md" bundle) (insert "x"))
          (let ((a3madkour-pub-site-content-dir content-root)
                (manifest `((notes . [((id . "id-gone")
                                       (current_url . "/garden/gone/")
                                       (history . [])
                                       (state . "live"))]))))
            (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                       (lambda () manifest-path))
                      ((symbol-function 'a3madkour-pub-history--now-iso)
                       (lambda () "2026-05-24T12:00:00Z")))
              (a3madkour-pub-history/write-manifest manifest)
              ;; Empty accumulator + nothing in new-set → id-gone is removed.
              (clrhash a3madkour-pub--publish-run-accumulator)
              (cl-letf (((symbol-function 'a3madkour-pub/walk-published-source-set)
                         (lambda () (make-hash-table :test 'equal))))
                (let ((result (a3madkour-pub/finish-publish)))
                  (should (equal (plist-get result :removed) '("id-gone")))
                  (should-not (file-directory-p bundle))
                  (let* ((m (a3madkour-pub-history/read-manifest))
                         (note (aref (alist-get 'notes m) 0)))
                    (should (equal (alist-get 'state note) "removed"))))))))
      (when (file-exists-p manifest-path) (delete-file manifest-path))
      (delete-directory content-root t))))

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-dry-run-no-mutation ()
  ":dry-run t skips bundle delete AND manifest mutation; still reports :removed."
  (let* ((content-root (make-temp-file "a3-pub-content-" t))
         (bundle (expand-file-name "garden/gone" content-root))
         (manifest-path (make-temp-file "a3-pub-history-" nil ".yaml")))
    (unwind-protect
        (progn
          (make-directory bundle t)
          (with-temp-file (expand-file-name "index.md" bundle) (insert "x"))
          (let ((a3madkour-pub-site-content-dir content-root)
                (manifest `((notes . [((id . "id-gone")
                                       (current_url . "/garden/gone/")
                                       (history . [])
                                       (state . "live"))]))))
            (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                       (lambda () manifest-path)))
              (a3madkour-pub-history/write-manifest manifest)
              (clrhash a3madkour-pub--publish-run-accumulator)
              (cl-letf (((symbol-function 'a3madkour-pub/walk-published-source-set)
                         (lambda () (make-hash-table :test 'equal))))
                (let ((result (a3madkour-pub/finish-publish :dry-run t)))
                  (should (equal (plist-get result :removed) '("id-gone")))
                  ;; Bundle still present (dry-run skipped delete).
                  (should (file-directory-p bundle))
                  ;; Manifest still says live (dry-run skipped record-publish).
                  (let* ((m (a3madkour-pub-history/read-manifest))
                         (note (aref (alist-get 'notes m) 0)))
                    (should (equal (alist-get 'state note) "live"))))))))
      (when (file-exists-p manifest-path) (delete-file manifest-path))
      (delete-directory content-root t))))

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-empty-diff ()
  "Empty diff (no removes, no shifts) → :removed nil; no side effects."
  (let ((manifest-path (make-temp-file "a3-pub-history-" nil ".yaml")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                   (lambda () manifest-path)))
          (a3madkour-pub-history/write-manifest '((notes . [])))
          (clrhash a3madkour-pub--publish-run-accumulator)
          (cl-letf (((symbol-function 'a3madkour-pub/walk-published-source-set)
                     (lambda () (make-hash-table :test 'equal))))
            (let ((result (a3madkour-pub/finish-publish)))
              (should (null (plist-get result :removed)))
              (should (null (plist-get result :slug-shifted)))
              (should (null (plist-get result :orphan-warnings))))))
      (when (file-exists-p manifest-path) (delete-file manifest-path)))))

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-prefers-accumulator-over-walk ()
  "Non-empty accumulator is used as new-set; walk is NOT called."
  (let ((manifest-path (make-temp-file "a3-pub-history-" nil ".yaml"))
        (walk-called nil))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                   (lambda () manifest-path)))
          (a3madkour-pub-history/write-manifest '((notes . [])))
          (clrhash a3madkour-pub--publish-run-accumulator)
          (puthash "id-from-acc" '("/garden/x/" . live)
                   a3madkour-pub--publish-run-accumulator)
          (cl-letf (((symbol-function 'a3madkour-pub/walk-published-source-set)
                     (lambda () (setq walk-called t)
                                (make-hash-table :test 'equal))))
            (let ((result (a3madkour-pub/finish-publish)))
              (should-not walk-called)
              ;; id-from-acc is new → :added; no :removed.
              (should (member "id-from-acc" (plist-get result :added))))))
      (when (file-exists-p manifest-path) (delete-file manifest-path)))))

;; -- unpublish--rename-asset-dir helper --

(ert-deftest a3madkour-pub-unpublish-test/rename-asset-dir-source-missing-silent ()
  "Source dir doesn't exist → :skipped-no-source (no error)."
  (let ((root (make-temp-file "a3-pub-assets-" t)))
    (unwind-protect
        (should (eq :skipped-no-source
                    (a3madkour-pub--unpublish-rename-asset-dir
                     "never-existed" "new-slug" root)))
      (delete-directory root t))))

(ert-deftest a3madkour-pub-unpublish-test/rename-asset-dir-target-exists-warn ()
  "Target dir already exists → :skipped-target-exists (no error)."
  (let* ((root (make-temp-file "a3-pub-assets-" t))
         (old-dir (expand-file-name "page/foo" root))
         (new-dir (expand-file-name "page/foo-v2" root)))
    (unwind-protect
        (progn
          (make-directory old-dir t)
          (make-directory new-dir t)
          (should (eq :skipped-target-exists
                      (a3madkour-pub--unpublish-rename-asset-dir
                       "foo" "foo-v2" root))))
      (delete-directory root t))))

(ert-deftest a3madkour-pub-unpublish-test/rename-asset-dir-untracked-uses-rename-file ()
  "Untracked source dir → rename-file, returns :renamed-mv."
  (let* ((root (make-temp-file "a3-pub-assets-" t))
         (old-dir (expand-file-name "page/foo" root))
         (new-dir (expand-file-name "page/foo-v2" root)))
    (unwind-protect
        (progn
          (make-directory old-dir t)
          (with-temp-file (expand-file-name "x.png" old-dir) (insert "data"))
          (cl-letf (((symbol-function 'vc-backend) (lambda (_) nil)))
            (should (eq :renamed-mv
                        (a3madkour-pub--unpublish-rename-asset-dir
                         "foo" "foo-v2" root))))
          (should (file-directory-p new-dir))
          (should-not (file-directory-p old-dir))
          (should (file-exists-p (expand-file-name "x.png" new-dir))))
      (delete-directory root t))))

(ert-deftest a3madkour-pub-unpublish-test/rename-asset-dir-tracked-uses-git-mv ()
  "Git-tracked source dir → shell-command \"git mv\", returns :renamed-git."
  (let* ((root (make-temp-file "a3-pub-assets-" t))
         (old-dir (expand-file-name "page/foo" root))
         (git-cmd-captured nil))
    (unwind-protect
        (progn
          (make-directory old-dir t)
          (cl-letf (((symbol-function 'vc-backend) (lambda (_) 'Git))
                    ((symbol-function 'shell-command)
                     (lambda (cmd &rest _)
                       (setq git-cmd-captured cmd)
                       ;; Simulate successful git mv by doing rename-file.
                       (rename-file old-dir
                                    (expand-file-name "page/foo-v2" root))
                       0)))
            (should (eq :renamed-git
                        (a3madkour-pub--unpublish-rename-asset-dir
                         "foo" "foo-v2" root))))
          (should (string-match-p "git mv" git-cmd-captured)))
      (when (file-directory-p (expand-file-name "page/foo-v2" root))
        (delete-directory (expand-file-name "page/foo-v2" root) t))
      (delete-directory root t))))

;; -- unpublish--bulk-rewrite-source-links helper --

(ert-deftest a3madkour-pub-unpublish-test/bulk-rewrite-three-link-forms ()
  "All three link forms (relative ./assets/, ~-absolute, $HOME-absolute) rewrite."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (let ((home-prefix (expand-file-name "~/")))
      (a3-pub-unpublish-test--write-org d "rel.org"
        "See [[./assets/page/foo/x.png][x]]\n")
      (a3-pub-unpublish-test--write-org d "tilde.org"
        "See [[~/org/notes/assets/page/foo/y.png][y]]\n")
      (a3-pub-unpublish-test--write-org d "abs.org"
        (format "See [[%sorg/notes/assets/page/foo/z.png][z]]\n" home-prefix))
      (let ((result (a3madkour-pub--unpublish-bulk-rewrite-source-links
                     "foo" "foo-v2" d)))
        (should (= 3 (length (plist-get result :modified))))
        (should (null (plist-get result :warnings))))
      (should (string-match-p "./assets/page/foo-v2/x.png"
                              (with-temp-buffer
                                (insert-file-contents (expand-file-name "rel.org" d))
                                (buffer-string))))
      (should (string-match-p "~/org/notes/assets/page/foo-v2/y.png"
                              (with-temp-buffer
                                (insert-file-contents (expand-file-name "tilde.org" d))
                                (buffer-string))))
      (should (string-match-p "assets/page/foo-v2/z.png"
                              (with-temp-buffer
                                (insert-file-contents (expand-file-name "abs.org" d))
                                (buffer-string)))))))

(ert-deftest a3madkour-pub-unpublish-test/bulk-rewrite-idempotent ()
  "Second invocation after a complete first pass yields zero modifications."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (a3-pub-unpublish-test--write-org d "a.org"
      "[[./assets/page/foo/x.png][x]]\n")
    ;; First pass: 1 modification.
    (let ((r1 (a3madkour-pub--unpublish-bulk-rewrite-source-links "foo" "foo-v2" d)))
      (should (= 1 (length (plist-get r1 :modified)))))
    ;; Second pass: zero modifications.
    (let ((r2 (a3madkour-pub--unpublish-bulk-rewrite-source-links "foo" "foo-v2" d)))
      (should (null (plist-get r2 :modified))))))

(ert-deftest a3madkour-pub-unpublish-test/bulk-rewrite-no-matches-not-modified ()
  "Files without matching references stay untouched."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (a3-pub-unpublish-test--write-org d "other.org"
      "Plain text without any asset references.\n")
    (let ((result (a3madkour-pub--unpublish-bulk-rewrite-source-links "foo" "foo-v2" d)))
      (should (null (plist-get result :modified))))))

(ert-deftest a3madkour-pub-unpublish-test/bulk-rewrite-mixed-partial ()
  "Files with multiple matches get all-or-nothing rewrites in one pass."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (a3-pub-unpublish-test--write-org d "mixed.org"
      "[[./assets/page/foo/a.png][a]]\n[[./assets/page/foo/b.png][b]]\n[[./assets/page/bar/c.png][c]]\n")
    (let ((result (a3madkour-pub--unpublish-bulk-rewrite-source-links "foo" "foo-v2" d)))
      (should (= 1 (length (plist-get result :modified)))))
    (let ((content (with-temp-buffer
                     (insert-file-contents (expand-file-name "mixed.org" d))
                     (buffer-string))))
      (should (string-match-p "page/foo-v2/a.png" content))
      (should (string-match-p "page/foo-v2/b.png" content))
      ;; Unrelated `bar' slug untouched.
      (should (string-match-p "page/bar/c.png" content)))))

(ert-deftest a3madkour-pub-unpublish-test/bulk-rewrite-unwritable-warn ()
  "Files that fail to write back are captured in :warnings, not raised."
  (a3-pub-unpublish-test--with-tmp-notes-dir d
    (a3-pub-unpublish-test--write-org d "a.org"
      "[[./assets/page/foo/x.png][x]]\n")
    (cl-letf (((symbol-function 'write-region)
               (lambda (&rest _) (error "permission denied"))))
      (let ((result (a3madkour-pub--unpublish-bulk-rewrite-source-links "foo" "foo-v2" d)))
        (should (= 1 (length (plist-get result :warnings))))
        (should (string-match-p "a.org" (car (plist-get result :warnings))))))))

;; -- finish-publish: Step B integration --

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-step-b-happy ()
  "Step B: slug shift triggers asset-dir rename + source-link rewrite."
  (let* ((notes-dir (make-temp-file "a3-pub-notes-" t))
         (asset-root (make-temp-file "a3-pub-assets-" t))
         (old-asset-dir (expand-file-name "page/foo" asset-root))
         (manifest-path (make-temp-file "a3-pub-history-" nil ".yaml")))
    (unwind-protect
        (progn
          (make-directory old-asset-dir t)
          (with-temp-file (expand-file-name "x.png" old-asset-dir) (insert "data"))
          (a3-pub-unpublish-test--write-org notes-dir "note.org"
            "[[./assets/page/foo/x.png][x]]\n")
          (let ((a3madkour-pub-canonical-asset-root asset-root)
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                       (lambda () manifest-path))
                      ((symbol-function 'vc-backend) (lambda (_) nil)))
              ;; Seed manifest: note was at /garden/foo/, now (per accumulator) at /garden/foo-v2/.
              (a3madkour-pub-history/write-manifest
               '((notes . [((id . "id-shift") (current_url . "/garden/foo/")
                            (history . []) (state . "live"))])))
              (clrhash a3madkour-pub--publish-run-accumulator)
              (puthash "id-shift" '("/garden/foo-v2/" . live)
                       a3madkour-pub--publish-run-accumulator)
              (let ((result (a3madkour-pub/finish-publish)))
                (should (equal (plist-get result :slug-shifted)
                               '(("foo" . "foo-v2"))))
                ;; Asset dir renamed.
                (should-not (file-directory-p old-asset-dir))
                (should (file-directory-p (expand-file-name "page/foo-v2" asset-root)))
                ;; Source link rewritten.
                (let ((content (with-temp-buffer
                                 (insert-file-contents (expand-file-name "note.org" notes-dir))
                                 (buffer-string))))
                  (should (string-match-p "page/foo-v2/x.png" content)))))))
      (delete-directory notes-dir t)
      (delete-directory asset-root t)
      (when (file-exists-p manifest-path) (delete-file manifest-path)))))

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-step-b-dry-run ()
  ":dry-run t skips both asset rename and source rewrite."
  (let* ((notes-dir (make-temp-file "a3-pub-notes-" t))
         (asset-root (make-temp-file "a3-pub-assets-" t))
         (old-asset-dir (expand-file-name "page/foo" asset-root))
         (manifest-path (make-temp-file "a3-pub-history-" nil ".yaml")))
    (unwind-protect
        (progn
          (make-directory old-asset-dir t)
          (with-temp-file (expand-file-name "x.png" old-asset-dir) (insert "data"))
          (a3-pub-unpublish-test--write-org notes-dir "note.org"
            "[[./assets/page/foo/x.png][x]]\n")
          (let ((a3madkour-pub-canonical-asset-root asset-root)
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                       (lambda () manifest-path))
                      ((symbol-function 'vc-backend) (lambda (_) nil)))
              (a3madkour-pub-history/write-manifest
               '((notes . [((id . "id-shift") (current_url . "/garden/foo/")
                            (history . []) (state . "live"))])))
              (clrhash a3madkour-pub--publish-run-accumulator)
              (puthash "id-shift" '("/garden/foo-v2/" . live)
                       a3madkour-pub--publish-run-accumulator)
              (let ((result (a3madkour-pub/finish-publish :dry-run t)))
                ;; Reports the would-do.
                (should (equal (plist-get result :slug-shifted)
                               '(("foo" . "foo-v2"))))
                ;; But no FS mutation.
                (should (file-directory-p old-asset-dir))
                (let ((content (with-temp-buffer
                                 (insert-file-contents (expand-file-name "note.org" notes-dir))
                                 (buffer-string))))
                  (should (string-match-p "page/foo/x.png" content)))))))
      (delete-directory notes-dir t)
      (delete-directory asset-root t)
      (when (file-exists-p manifest-path) (delete-file manifest-path)))))

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-step-b-deletes-old-bundle ()
  "Step B: slug shift deletes orphan old Hugo content bundle at old slug.

Scenario:
  - Manifest has note id-shift at /garden/slug-a/.
  - A stub handler writes a new bundle at content/garden/slug-b/ to simulate
    the per-section handler having already published at the new slug.
  - finish-publish Step B detects the slug shift and must delete
    content/garden/slug-a/ (the orphan old bundle).

Asserts:
  - content/garden/slug-a/ is removed.
  - content/garden/slug-b/ still exists."
  (let* ((content-root (make-temp-file "a3-pub-content-" t))
         (asset-root   (make-temp-file "a3-pub-assets-" t))
         (notes-dir    (make-temp-file "a3-pub-notes-" t))
         (manifest-path (make-temp-file "a3-pub-history-" nil ".yaml"))
         ;; Old bundle (slug-a) — simulates what was written in the prior publish.
         (old-bundle (expand-file-name "garden/slug-a" content-root))
         ;; New bundle (slug-b) — simulates what the per-section handler wrote
         ;; earlier this publish run.
         (new-bundle (expand-file-name "garden/slug-b" content-root)))
    (unwind-protect
        (progn
          (make-directory old-bundle t)
          (with-temp-file (expand-file-name "index.md" old-bundle) (insert "old"))
          (make-directory new-bundle t)
          (with-temp-file (expand-file-name "index.md" new-bundle) (insert "new"))
          (let ((a3madkour-pub-site-content-dir content-root)
                (a3madkour-pub-canonical-asset-root asset-root)
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                       (lambda () manifest-path))
                      ((symbol-function 'vc-backend) (lambda (_) nil)))
              ;; Seed manifest: note was at /garden/slug-a/.
              (a3madkour-pub-history/write-manifest
               '((notes . [((id . "id-shift") (current_url . "/garden/slug-a/")
                            (history . []) (state . "live"))])))
              ;; Accumulator: note now at /garden/slug-b/.
              (clrhash a3madkour-pub--publish-run-accumulator)
              (puthash "id-shift" '("/garden/slug-b/" . live)
                       a3madkour-pub--publish-run-accumulator)
              (let ((result (a3madkour-pub/finish-publish)))
                (should (equal (plist-get result :slug-shifted)
                               '(("slug-a" . "slug-b"))))
                ;; Old bundle must be gone.
                (should-not (file-directory-p old-bundle))
                ;; New bundle must still exist.
                (should (file-directory-p new-bundle))))))
      (delete-directory content-root t)
      (delete-directory asset-root t)
      (delete-directory notes-dir t)
      (when (file-exists-p manifest-path) (delete-file manifest-path)))))

;; -- unpublish--recheck-live-note-links helper --

(defmacro a3-pub-unpublish-test--with-tmp-source (file-var body-content &rest setup-body)
  "Write BODY-CONTENT to a tmpfile bound to FILE-VAR; run SETUP-BODY; cleanup."
  (declare (indent 2))
  `(let ((,file-var (make-temp-file "a3-pub-source-" nil ".org")))
     (unwind-protect
         (progn
           (with-temp-file ,file-var (insert ,body-content))
           ,@setup-body)
       (when (file-exists-p ,file-var) (delete-file ,file-var)))))

(ert-deftest a3madkour-pub-unpublish-test/recheck-live-link-to-removed-warns ()
  "Live note with [[id:...]] link to removed target produces WARN."
  (a3-pub-unpublish-test--with-tmp-source src
      "Some text [[id:tgt-removed][link]] more text.\n"
    (let ((removed-set (make-hash-table :test 'equal)))
      (puthash "tgt-removed" t removed-set)
      (cl-letf (((symbol-function 'a3madkour-pub-history/read-manifest)
                 (lambda ()
                   `((notes . [((id . "live-note") (current_url . "/garden/x/")
                                (history . []) (state . "live"))
                               ((id . "tgt-removed") (current_url . nil)
                                (history . [((url . "/garden/old/") (replaced_at . "t")
                                             (reason . "removed"))])
                                (state . "removed"))]))))
                ((symbol-function 'org-roam-id-find)
                 (lambda (id &optional _)
                   (when (equal id "live-note") (cons src 1)))))
        (let ((warnings (a3madkour-pub--unpublish-recheck-live-note-links removed-set)))
          (should (= 1 (length warnings)))
          (should (string-match-p "live-note" (car warnings)))
          (should (string-match-p "tgt-removed" (car warnings))))))))

(ert-deftest a3madkour-pub-unpublish-test/recheck-link-to-live-no-warn ()
  "Live note with link to another live target → no WARN."
  (a3-pub-unpublish-test--with-tmp-source src
      "[[id:tgt-live][link]]\n"
    (let ((removed-set (make-hash-table :test 'equal)))
      (cl-letf (((symbol-function 'a3madkour-pub-history/read-manifest)
                 (lambda ()
                   `((notes . [((id . "live-note") (current_url . "/garden/x/")
                                (history . []) (state . "live"))]))))
                ((symbol-function 'org-roam-id-find)
                 (lambda (id &optional _)
                   (when (equal id "live-note") (cons src 1)))))
        (should (null (a3madkour-pub--unpublish-recheck-live-note-links removed-set)))))))

(ert-deftest a3madkour-pub-unpublish-test/recheck-unparseable-source-warns ()
  "If source file is missing, WARN names the file but continues."
  (let ((removed-set (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'a3madkour-pub-history/read-manifest)
               (lambda ()
                 `((notes . [((id . "ghost") (current_url . "/garden/g/")
                              (history . []) (state . "live"))]))))
              ((symbol-function 'org-roam-id-find)
               (lambda (id &optional _)
                 (when (equal id "ghost") (cons "/nonexistent/path.org" 1)))))
      (let ((warnings (a3madkour-pub--unpublish-recheck-live-note-links removed-set)))
        (should (= 1 (length warnings)))
        (should (string-match-p "ghost" (car warnings)))))))

(ert-deftest a3madkour-pub-unpublish-test/recheck-multi-link-per-note ()
  "Multiple links per note are all checked; each removed target → own WARN."
  (a3-pub-unpublish-test--with-tmp-source src
      "[[id:rem-1][a]] and [[id:rem-2][b]] and [[id:live-tgt][c]]\n"
    (let ((removed-set (make-hash-table :test 'equal)))
      (puthash "rem-1" t removed-set)
      (puthash "rem-2" t removed-set)
      (cl-letf (((symbol-function 'a3madkour-pub-history/read-manifest)
                 (lambda ()
                   `((notes . [((id . "src-note") (current_url . "/garden/s/")
                                (history . []) (state . "live"))]))))
                ((symbol-function 'org-roam-id-find)
                 (lambda (id &optional _)
                   (when (equal id "src-note") (cons src 1)))))
        (let ((warnings (a3madkour-pub--unpublish-recheck-live-note-links removed-set)))
          (should (= 2 (length warnings))))))))

;; -- finish-publish: Step C integration --

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-step-c-orphan-warn ()
  "End-to-end: removed note linked from a live note → :orphan-warnings populated."
  (let* ((manifest-path (make-temp-file "a3-pub-history-" nil ".yaml"))
         (live-src (make-temp-file "a3-pub-src-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file live-src
            (insert "Hello, see [[id:tgt-id][gone]] now.\n"))
          (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                     (lambda () manifest-path))
                    ((symbol-function 'org-roam-id-find)
                     (lambda (id &optional _)
                       (when (equal id "live-id") (cons live-src 1)))))
            (a3madkour-pub-history/write-manifest
             '((notes . [((id . "live-id") (current_url . "/garden/live/")
                          (history . []) (state . "live"))
                         ((id . "tgt-id") (current_url . "/garden/tgt/")
                          (history . []) (state . "live"))])))
            (clrhash a3madkour-pub--publish-run-accumulator)
            (puthash "live-id" '("/garden/live/" . live)
                     a3madkour-pub--publish-run-accumulator)
            ;; tgt-id NOT in accumulator → will be classified as removed.
            (cl-letf (((symbol-function 'a3madkour-pub--unpublish-delete-bundle)
                       (lambda (&rest _) nil)))  ; stub FS delete
              (let* ((result (a3madkour-pub/finish-publish))
                     (warnings (plist-get result :orphan-warnings)))
                (should (= 1 (length warnings)))
                (should (string-match-p "live-id" (car warnings)))
                (should (string-match-p "tgt-id" (car warnings)))))))
      (when (file-exists-p manifest-path) (delete-file manifest-path))
      (when (file-exists-p live-src) (delete-file live-src)))))

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-step-c-dry-run-still-warns ()
  "Step C is read-only; dry-run still produces :orphan-warnings."
  (let* ((manifest-path (make-temp-file "a3-pub-history-" nil ".yaml"))
         (live-src (make-temp-file "a3-pub-src-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file live-src (insert "[[id:tgt-id][x]]\n"))
          (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                     (lambda () manifest-path))
                    ((symbol-function 'org-roam-id-find)
                     (lambda (id &optional _)
                       (when (equal id "live-id") (cons live-src 1)))))
            (a3madkour-pub-history/write-manifest
             '((notes . [((id . "live-id") (current_url . "/garden/live/")
                          (history . []) (state . "live"))
                         ((id . "tgt-id") (current_url . "/garden/tgt/")
                          (history . []) (state . "live"))])))
            (clrhash a3madkour-pub--publish-run-accumulator)
            (puthash "live-id" '("/garden/live/" . live)
                     a3madkour-pub--publish-run-accumulator)
            (let ((result (a3madkour-pub/finish-publish :dry-run t)))
              (should (= 1 (length (plist-get result :orphan-warnings)))))))
      (when (file-exists-p manifest-path) (delete-file manifest-path))
      (when (file-exists-p live-src) (delete-file live-src)))))

(ert-deftest a3madkour-pub-unpublish-test/finish-publish-empty-removed-empty-warnings ()
  "Empty :removed → :orphan-warnings nil (Step C short-circuits)."
  (let ((manifest-path (make-temp-file "a3-pub-history-" nil ".yaml")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                   (lambda () manifest-path)))
          (a3madkour-pub-history/write-manifest '((notes . [])))
          (clrhash a3madkour-pub--publish-run-accumulator)
          (cl-letf (((symbol-function 'a3madkour-pub/walk-published-source-set)
                     (lambda () (make-hash-table :test 'equal))))
            (let ((result (a3madkour-pub/finish-publish)))
              (should (null (plist-get result :orphan-warnings))))))
      (when (file-exists-p manifest-path) (delete-file manifest-path)))))

;; -- check-orphans thin alias --

(ert-deftest a3madkour-pub-unpublish-test/check-orphans-parity-with-dry-run ()
  "`check-orphans' is identical to `(finish-publish :dry-run t)'."
  (let ((manifest-path (make-temp-file "a3-pub-history-" nil ".yaml")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-history--manifest-path)
                   (lambda () manifest-path)))
          (a3madkour-pub-history/write-manifest '((notes . [])))
          (clrhash a3madkour-pub--publish-run-accumulator)
          (cl-letf (((symbol-function 'a3madkour-pub/walk-published-source-set)
                     (lambda () (make-hash-table :test 'equal))))
            (let ((a (a3madkour-pub/finish-publish :dry-run t))
                  (b (a3madkour-pub/check-orphans)))
              (should (equal a b)))))
      (when (file-exists-p manifest-path) (delete-file manifest-path)))))

(ert-deftest a3madkour-pub-unpub-test/finish-publish-clears-manifest-snapshot ()
  "B.0 — `finish-publish' clears `a3madkour-pub--manifest-snapshot' at end.
Set up a tmp data dir, run begin-publish (which populates the snapshot),
then finish-publish, then assert snapshot is nil."
  (let ((tmp-data (make-temp-file "b0-snapshot-clear-" t))
        (a3madkour-pub--manifest-snapshot nil))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data)
              (a3madkour-pub/org-notes-dir tmp-data))  ; redirect walk away from real notes
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes: []\n"))
          (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
            (a3madkour-pub/begin-publish)
            (should a3madkour-pub--manifest-snapshot)
            (a3madkour-pub/finish-publish)
            (should-not a3madkour-pub--manifest-snapshot)))
      (delete-directory tmp-data t))))

(ert-deftest a3madkour-pub-unpub-test/snapshot-fix-preserves-slug-shift-detection ()
  "B.0 regression — calling record-publish mid-publish (B-coupled mode)
must NOT prevent diff-published-set from seeing the old URL.

Scenario:
  - Manifest has note ID 'shifter at /garden/old-name/.
  - During a publish run, we call record-publish to move it to /garden/new-name/.
  - Then we call diff-published-set with a new-set that still has 'shifter
    (because the source file still exists, just under a new slug).
  - Expectation: :slug-shifted contains ('shifter \"/garden/old-name/\" \"/garden/new-name/\").

Pre-fix: this would have reported the URL as unchanged because
diff-published-set re-read disk and saw the new URL already there."
  (let ((tmp-data (make-temp-file "b0-regression-" t))
        (a3madkour-pub--manifest-snapshot nil))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data))
          ;; Seed manifest at the OLD url.
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes:\n  - id: shifter\n    current_url: /garden/old-name/\n    history: []\n    state: live\n"))
          (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
            (a3madkour-pub/begin-publish))
          ;; Mid-publish: record-publish writes the new URL to disk eagerly.
          (a3madkour-pub-history/record-publish "shifter" "/garden/new-name/" 'live)
          ;; Build new-set for diff-published-set (B handlers would do this
          ;; via the accumulator in real publish; here we construct one
          ;; directly for the test).
          (let* ((new-set (make-hash-table :test 'equal)))
            (puthash "shifter" (cons "/garden/new-name/" 'live) new-set)
            (let* ((diff (a3madkour-pub/diff-published-set new-set))
                   (shifted (plist-get diff :slug-shifted)))
              (should (= 1 (length shifted)))
              (should (equal '("shifter" "/garden/old-name/" "/garden/new-name/")
                             (car shifted)))))
          (a3madkour-pub/finish-publish))
      (delete-directory tmp-data t))))

(ert-deftest a3madkour-pub-unpub-test/site-content-dir-derives-from-site-data-dir ()
  "B.1 regression — when `a3madkour-pub-site-content-dir' is nil (the new
default), `--site-content-dir-effective' derives the path from
`a3madkour-pub/site-data-dir' by replacing `data/' with `content/'.

This avoids hardcoding a machine-specific path in the defcustom default,
which previously leaked the other machine's `/Stuff/...' path into the
delete-bundle code path on this machine."
  (let ((a3madkour-pub-site-content-dir nil))
    ;; Derive: site-data-dir is `<root>/data/' → content is `<root>/content/'.
    (let ((a3madkour-pub/site-data-dir "/tmp/site-A/data/"))
      (should (equal (a3madkour-pub--site-content-dir-effective)
                     "/tmp/site-A/content/")))
    ;; Trailing-slash variations: with or without should both work.
    (let ((a3madkour-pub/site-data-dir "/tmp/site-B/data"))
      (should (equal (a3madkour-pub--site-content-dir-effective)
                     "/tmp/site-B/content/")))
    ;; Both nil → nil (caller's burden to error if they need a value).
    (let ((a3madkour-pub/site-data-dir nil))
      (should (null (a3madkour-pub--site-content-dir-effective)))))
  ;; Explicit override wins over derivation.
  (let ((a3madkour-pub-site-content-dir "/explicit/override/content/")
        (a3madkour-pub/site-data-dir "/tmp/different/data/"))
    (should (equal (a3madkour-pub--site-content-dir-effective)
                   "/explicit/override/content/"))))

(ert-deftest a3madkour-pub-unpublish-test/delete-bundle-warns-on-failure ()
  "When `delete-directory' errors, --unpublish-delete-bundle returns 'failed
and emits a [a3-pub] WARN message including the bundle path."
  (let* ((root (make-temp-file "a3-pub-content-" t))
         (bundle (expand-file-name "garden/locked-bundle" root))
         captured-messages)
    (unwind-protect
        (progn
          (make-directory bundle t)
          (cl-letf (((symbol-function 'delete-directory)
                     (lambda (&rest _) (error "permission denied (test stub)")))
                    ((symbol-function 'message)
                     (lambda (fmt &rest args)
                       (push (apply #'format fmt args) captured-messages))))
            (let ((result (a3madkour-pub--unpublish-delete-bundle
                           "garden" "locked-bundle" root)))
              (should (eq result 'failed))
              (should (cl-some (lambda (m)
                                 (string-match-p "\\[a3-pub\\] delete-bundle FAILED" m))
                               captured-messages))
              (should (cl-some (lambda (m)
                                 (string-match-p "locked-bundle" m))
                               captured-messages)))))
      (delete-directory root t))))

(provide 'a3madkour-publish-unpublish-test)
;;; a3madkour-publish-unpublish-test.el ends here
