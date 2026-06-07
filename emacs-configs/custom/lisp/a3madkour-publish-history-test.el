;;; a3madkour-publish-history-test.el --- Tests for URL-history manifest -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-history)
;; A.1.d: bring in the publish-run-accumulator defvar so the new
;; record-publish tests below can clear/inspect it explicitly.
(require 'a3madkour-publish)
;; Task 22: async runtime for the new git-mtime-of-file-async sibling
;; and the with-a3-pub-async-sync test macro.
(require 'a3madkour-publish-async)

(defun a3madkour-pub-history-test--with-tmp-data-dir (thunk)
  "Create a tmp dir; let-bind `a3madkour-pub/site-data-dir' to it; call THUNK."
  (let ((tmp-dir (file-name-as-directory (make-temp-file "a3-pub-data-" t))))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-dir))
          (funcall thunk tmp-dir))
      (delete-directory tmp-dir t))))

(defmacro a3-pub-history-test--with-tmp-manifest (path-sym &rest body)
  "Create a tmp data dir + bind PATH-SYM to the manifest path; eval BODY.
A.1.d helper that mirrors the plan's BDD-style block form (vs. the older
thunk-based `--with-tmp-data-dir').  Sets `a3madkour-pub/site-data-dir' to
a fresh tmp dir; binds PATH-SYM to the resolved manifest path; tears down
the dir on exit."
  (declare (indent 1) (debug (sexp body)))
  `(let ((tmp-dir (file-name-as-directory (make-temp-file "a3-pub-data-" t))))
     (unwind-protect
         (let* ((a3madkour-pub/site-data-dir tmp-dir)
                (,path-sym (a3madkour-pub-history--manifest-path)))
           ,@body)
       (delete-directory tmp-dir t))))

(ert-deftest a3madkour-pub-history-test/site-data-dir-required ()
  "Manifest path requires `a3madkour-pub/site-data-dir' to be set."
  (let ((a3madkour-pub/site-data-dir nil))
    (should-error (a3madkour-pub-history--manifest-path) :type 'user-error)))

(ert-deftest a3madkour-pub-history-test/manifest-path-resolves ()
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (tmp-dir)
     (should (equal (expand-file-name "url-history.yaml" tmp-dir)
                    (a3madkour-pub-history--manifest-path))))))

(ert-deftest a3madkour-pub-history-test/read-empty-manifest ()
  "Reading a missing-or-empty manifest returns the empty shape `((notes . []))'."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (let ((m (a3madkour-pub-history/read-manifest)))
       (should (vectorp (alist-get 'notes m)))
       (should (= 0 (length (alist-get 'notes m))))))))

(ert-deftest a3madkour-pub-history-test/write-then-read-round-trip ()
  "Round-trip: write a manifest with one note → read back → matches."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (let ((manifest
            '((notes . [((id . "abc-123")
                         (current_url . "/garden/foo/")
                         (history . [])
                         (state . "live"))]))))
       (a3madkour-pub-history/write-manifest manifest)
       (let* ((readback (a3madkour-pub-history/read-manifest))
              (notes (alist-get 'notes readback))
              (note (aref notes 0)))
         (should (= 1 (length notes)))
         (should (equal "abc-123" (alist-get 'id note)))
         (should (equal "/garden/foo/" (alist-get 'current_url note)))
         (should (equal "live" (alist-get 'state note))))))))

(ert-deftest a3madkour-pub-history-test/read-returns-empty-when-file-missing ()
  "If url-history.yaml doesn't exist yet, read returns the empty shape — no error."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (tmp-dir)
     (should-not (file-exists-p (expand-file-name "url-history.yaml" tmp-dir)))
     (let ((m (a3madkour-pub-history/read-manifest)))
       (should (= 0 (length (alist-get 'notes m))))))))

(ert-deftest a3madkour-pub-history-test/record-new-note ()
  "Recording a publish for a not-yet-seen ID creates an entry with empty history."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (let* ((m (a3madkour-pub-history/read-manifest))
            (notes (alist-get 'notes m))
            (note (aref notes 0)))
       (should (= 1 (length notes)))
       (should (equal "abc-123" (alist-get 'id note)))
       (should (equal "/garden/foo/" (alist-get 'current_url note)))
       (should (equal "live" (alist-get 'state note)))
       (let ((hist (alist-get 'history note)))
         (should (or (null hist) (= 0 (length hist)))))))))

(ert-deftest a3madkour-pub-history-test/record-url-change-appends-history ()
  "Recording with a different URL appends the prior URL to history."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo-renamed/" 'live)
     (let* ((m (a3madkour-pub-history/read-manifest))
            (note (aref (alist-get 'notes m) 0))
            (hist (alist-get 'history note)))
       (should (equal "/garden/foo-renamed/" (alist-get 'current_url note)))
       (should (= 1 (length hist)))
       (let ((entry (aref hist 0)))
         (should (equal "/garden/foo/" (alist-get 'url entry)))
         (should (stringp (alist-get 'replaced_at entry)))
         (should (member (alist-get 'reason entry)
                         '("title_change" "slug_override" "section_change"))))))))

(ert-deftest a3madkour-pub-history-test/record-no-change-no-op ()
  "Recording the same URL/state twice does not append history."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (let* ((note (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
            (hist (alist-get 'history note)))
       (should (or (null hist) (= 0 (length hist))))))))

(ert-deftest a3madkour-pub-history-test/record-section-change ()
  "Section change → reason='section_change'."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/essays/foo/" 'live)
     (let* ((note (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
            (entry (aref (alist-get 'history note) 0)))
       (should (equal "section_change" (alist-get 'reason entry)))))))

(ert-deftest a3madkour-pub-history-test/aliases-for-empty ()
  "New note → no aliases."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (should (null (a3madkour-pub-history/aliases-for "abc-123"))))))

(ert-deftest a3madkour-pub-history-test/aliases-for-after-rename ()
  "After a URL change → the prior URL is in aliases-for."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo-v2/" 'live)
     (should (equal '("/garden/foo/")
                    (a3madkour-pub-history/aliases-for "abc-123"))))))

(ert-deftest a3madkour-pub-history-test/aliases-for-unknown-id ()
  "Unknown ID returns nil, not an error."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (should (null (a3madkour-pub-history/aliases-for "no-such-id"))))))

(ert-deftest a3madkour-pub-history-test/record-publish-slug-override-reason ()
  "Same-section URL change with `:had-slug-override-p t' → reason='slug_override'."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo-renamed/" 'live
                                           :had-slug-override-p t)
     (let* ((note (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
            (history (alist-get 'history note))
            (entry (aref history (1- (length history)))))
       (should (equal "slug_override" (alist-get 'reason entry)))))))

(ert-deftest a3madkour-pub-history-test/record-publish-title-change-reason ()
  "Same-section URL change without the flag → reason='title_change'."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo-renamed/" 'live)
     (let* ((note (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
            (history (alist-get 'history note))
            (entry (aref history (1- (length history)))))
       (should (equal "title_change" (alist-get 'reason entry)))))))

(ert-deftest a3madkour-pub-history-test/record-publish-section-change-wins ()
  "Section change beats `:had-slug-override-p t' → reason='section_change'."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/essays/foo/" 'live
                                           :had-slug-override-p t)
     (let* ((note (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
            (history (alist-get 'history note))
            (entry (aref history (1- (length history)))))
       (should (equal "section_change" (alist-get 'reason entry)))))))

;; -- A.1.d: republished reason path + accumulator append --

(ert-deftest a3madkour-pub-history-test/republished-flips-state-and-appends-event ()
  "A removed -> live transition flips state, appends a `republished' event."
  (a3-pub-history-test--with-tmp-manifest path
    ;; Seed manifest with one removed note (URL was /garden/foo/).
    (let ((m `((notes . [((id . "rep-id-1")
                          (current_url . nil)
                          (history . [((url . "/garden/foo/")
                                       (replaced_at . "2026-05-22T10:00:00Z")
                                       (reason . "removed"))])
                          (state . "removed"))]))))
      (a3madkour-pub-history/write-manifest m))
    ;; Clear accumulator (test isolation per Task 3 code-review minor).
    (unwind-protect
        (progn
          (clrhash a3madkour-pub--publish-run-accumulator)
          ;; Republish at the same URL.
          (cl-letf (((symbol-function 'a3madkour-pub-history--now-iso)
                     (lambda () "2026-05-24T12:00:00Z")))
            (a3madkour-pub-history/record-publish "rep-id-1" "/garden/foo/" 'live))
          ;; Check.
          (let* ((m (a3madkour-pub-history/read-manifest))
                 (note (aref (alist-get 'notes m) 0))
                 (hist (alist-get 'history note)))
            (should (equal (alist-get 'state note) "live"))
            (should (equal (alist-get 'current_url note) "/garden/foo/"))
            (should (= 2 (length hist)))
            (should (equal (alist-get 'reason (aref hist 1)) "republished"))
            (should (equal (alist-get 'url (aref hist 1)) nil))))
      (clrhash a3madkour-pub--publish-run-accumulator))))

(ert-deftest a3madkour-pub-history-test/republished-aliases-re-merged-from-prior ()
  "After republish, aliases-for surfaces the prior URL from history."
  (a3-pub-history-test--with-tmp-manifest path
    (let ((m `((notes . [((id . "rep-id-2")
                          (current_url . nil)
                          (history . [((url . "/garden/old/")
                                       (replaced_at . "2026-05-22T10:00:00Z")
                                       (reason . "removed"))])
                          (state . "removed"))]))))
      (a3madkour-pub-history/write-manifest m))
    (unwind-protect
        (progn
          (clrhash a3madkour-pub--publish-run-accumulator)
          (cl-letf (((symbol-function 'a3madkour-pub-history--now-iso)
                     (lambda () "2026-05-24T12:00:00Z")))
            (a3madkour-pub-history/record-publish "rep-id-2" "/garden/new/" 'live))
          (should (member "/garden/old/" (a3madkour-pub-history/aliases-for "rep-id-2"))))
      (clrhash a3madkour-pub--publish-run-accumulator))))

(ert-deftest a3madkour-pub-history-test/record-publish-appends-to-accumulator ()
  "Every record-publish call pushes (id . (url . state)) into the accumulator."
  (a3-pub-history-test--with-tmp-manifest path
    (unwind-protect
        (progn
          (clrhash a3madkour-pub--publish-run-accumulator)
          (a3madkour-pub-history/record-publish "acc-id-1" "/garden/x/" 'live)
          (a3madkour-pub-history/record-publish "acc-id-2" "/garden/y/" 'draft)
          (a3madkour-pub-history/record-publish "acc-id-3" nil 'removed)
          (should (= 3 (hash-table-count a3madkour-pub--publish-run-accumulator)))
          (should (equal (gethash "acc-id-1" a3madkour-pub--publish-run-accumulator)
                         '("/garden/x/" . live)))
          (should (equal (gethash "acc-id-2" a3madkour-pub--publish-run-accumulator)
                         '("/garden/y/" . draft)))
          (should (equal (gethash "acc-id-3" a3madkour-pub--publish-run-accumulator)
                         '(nil . removed))))
      (clrhash a3madkour-pub--publish-run-accumulator))))

(ert-deftest a3madkour-pub-history-test/republished-at-new-url-still-republished ()
  "Republishing a removed note at a DIFFERENT URL still emits `republished'
(not `title_change' / `slug_override' / `section_change') — the cond branch
that catches the removed → live transition takes precedence over the
bare url-changed-p branch."
  (a3-pub-history-test--with-tmp-manifest path
    (let ((m `((notes . [((id . "rep-new-url-id")
                          (current_url . nil)
                          (history . [((url . "/garden/old/")
                                       (replaced_at . "2026-05-22T10:00:00Z")
                                       (reason . "removed"))])
                          (state . "removed"))]))))
      (a3madkour-pub-history/write-manifest m))
    (unwind-protect
        (progn
          (clrhash a3madkour-pub--publish-run-accumulator)
          (cl-letf (((symbol-function 'a3madkour-pub-history--now-iso)
                     (lambda () "2026-05-24T12:00:00Z")))
            (a3madkour-pub-history/record-publish "rep-new-url-id" "/garden/new/" 'live))
          (let* ((m (a3madkour-pub-history/read-manifest))
                 (note (aref (alist-get 'notes m) 0))
                 (hist (alist-get 'history note)))
            (should (equal (alist-get 'state note) "live"))
            (should (equal (alist-get 'current_url note) "/garden/new/"))
            ;; Exactly 2 events: the original removed + the new republished.
            ;; NOT 3 (would happen if both republished AND a url-change event fired).
            (should (= 2 (length hist)))
            (should (equal (alist-get 'reason (aref hist 1)) "republished"))))
      (clrhash a3madkour-pub--publish-run-accumulator))))

(ert-deftest a3madkour-pub-history-test/removed-to-draft-no-republished ()
  "Removed → draft transition is a state change only — no `republished'
event is appended. (Author's draft preview hasn't truly republished from
a live-site perspective.)"
  (a3-pub-history-test--with-tmp-manifest path
    (let ((m `((notes . [((id . "rem-to-draft-id")
                          (current_url . nil)
                          (history . [((url . "/garden/x/")
                                       (replaced_at . "2026-05-22T10:00:00Z")
                                       (reason . "removed"))])
                          (state . "removed"))]))))
      (a3madkour-pub-history/write-manifest m))
    (unwind-protect
        (progn
          (clrhash a3madkour-pub--publish-run-accumulator)
          (cl-letf (((symbol-function 'a3madkour-pub-history--now-iso)
                     (lambda () "2026-05-24T12:00:00Z")))
            (a3madkour-pub-history/record-publish "rem-to-draft-id" "/garden/x/" 'draft))
          (let* ((m (a3madkour-pub-history/read-manifest))
                 (note (aref (alist-get 'notes m) 0))
                 (hist (alist-get 'history note)))
            ;; State flipped.
            (should (equal (alist-get 'state note) "draft"))
            (should (equal (alist-get 'current_url note) "/garden/x/"))
            ;; But NO new event — history still has just the original removed entry.
            (should (= 1 (length hist)))
            (should (equal (alist-get 'reason (aref hist 0)) "removed"))))
      (clrhash a3madkour-pub--publish-run-accumulator))))

;; -- B.0: read-manifest-snapshot-or-disk --

(ert-deftest a3madkour-pub-hist-test/read-manifest-snapshot-or-disk-prefers-snapshot ()
  "B.0 — `read-manifest-snapshot-or-disk' returns the snapshot defvar
when non-nil, ignoring disk."
  (let ((tmp-data (make-temp-file "b0-snapshot-prefer-" t))
        (a3madkour-pub--manifest-snapshot
         '((notes . [((id . "snap-id") (current_url . "/garden/from-snap/")
                      (history . []) (state . "live"))]))))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data))
          ;; Write a different manifest to disk to prove snapshot wins.
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes:\n  - id: disk-id\n    current_url: /garden/from-disk/\n    history: []\n    state: live\n"))
          (let* ((m (a3madkour-pub-history/read-manifest-snapshot-or-disk))
                 (notes (alist-get 'notes m)))
            (should (= 1 (length notes)))
            (should (equal "snap-id" (alist-get 'id (aref notes 0))))))
      (delete-directory tmp-data t))))

(ert-deftest a3madkour-pub-hist-test/read-manifest-snapshot-or-disk-falls-back ()
  "B.0 — `read-manifest-snapshot-or-disk' falls back to disk when snapshot is nil."
  (let ((tmp-data (make-temp-file "b0-snapshot-fallback-" t))
        (a3madkour-pub--manifest-snapshot nil))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data))
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes:\n  - id: disk-only\n    current_url: /garden/disk-only/\n    history: []\n    state: live\n"))
          (let* ((m (a3madkour-pub-history/read-manifest-snapshot-or-disk))
                 (notes (alist-get 'notes m)))
            (should (= 1 (length notes)))
            (should (equal "disk-only" (alist-get 'id (aref notes 0))))))
      (delete-directory tmp-data t))))

(ert-deftest a3madkour-pub-history--git-mtime-tracked-file ()
  "git-mtime-of-file returns YYYY-MM-DD for a git-tracked file."
  (let* ((tmpdir (make-temp-file "a3-pub-git-" t))
         (file (expand-file-name "tracked.org" tmpdir))
         (default-directory tmpdir))
    (unwind-protect
        (progn
          (call-process "git" nil nil nil "init" "-q")
          (call-process "git" nil nil nil "config" "user.email" "test@example.com")
          (call-process "git" nil nil nil "config" "user.name" "Test")
          (with-temp-file file (insert "content\n"))
          (call-process "git" nil nil nil "add" "tracked.org")
          (call-process "git" nil nil nil "commit" "-q" "-m" "init")
          (let ((result (a3madkour-pub-history/git-mtime-of-file file)))
            (should (stringp result))
            (should (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$" result))))
      (delete-directory tmpdir t))))

(ert-deftest a3madkour-pub-history--git-mtime-untracked-file ()
  "git-mtime-of-file returns nil for a file not under git."
  (let* ((tmpdir (make-temp-file "a3-pub-nogit-" t))
         (file (expand-file-name "untracked.org" tmpdir)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "content\n"))
          (should-not (a3madkour-pub-history/git-mtime-of-file file)))
      (delete-directory tmpdir t))))

(ert-deftest a3madkour-pub-history--filesystem-mtime-existing-file ()
  "filesystem-mtime-of-file returns YYYY-MM-DD for an existing file."
  (let* ((tmpdir (make-temp-file "a3-pub-fsmtime-" t))
         (file (expand-file-name "x.org" tmpdir)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "content\n"))
          (let ((result (a3madkour-pub-history/filesystem-mtime-of-file file)))
            (should (stringp result))
            (should (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$" result))))
      (delete-directory tmpdir t))))

(ert-deftest a3madkour-pub-history--filesystem-mtime-missing-file ()
  "filesystem-mtime-of-file returns nil for a missing file."
  (should-not (a3madkour-pub-history/filesystem-mtime-of-file
               "/nonexistent/path/x.org")))

(ert-deftest a3madkour-pub-history-test/canonicalize-entry-reorders-keys ()
  "Entry built in non-canonical order is re-ordered to id / current_url / history / state."
  (let* ((entry '((current_url . "/x/") (history . []) (state . "live") (id . "abc")))
         (got (a3madkour-pub-history--canonicalize-entry entry)))
    (should (equal '(id current_url history state) (mapcar #'car got)))))

(ert-deftest a3madkour-pub-history-test/canonicalize-entry-preserves-extras ()
  "Unknown keys are kept (appended after the canonical ones)."
  (let* ((entry '((state . "live") (id . "abc") (custom_field . "x")))
         (got (a3madkour-pub-history--canonicalize-entry entry)))
    (should (equal '(id state custom_field) (mapcar #'car got)))))

(ert-deftest a3madkour-pub-history-test/write-manifest-is-byte-stable ()
  "Two writes of equivalent-but-differently-ordered manifests produce
byte-identical YAML output."
  (a3-pub-history-test--with-tmp-manifest path
    (let ((m1 '((notes . [((current_url . "/a/") (history . []) (state . "live") (id . "1"))
                          ((state . "live") (history . []) (current_url . "/b/") (id . "2"))])))
          (m2 '((notes . [((id . "1") (current_url . "/a/") (history . []) (state . "live"))
                          ((id . "2") (current_url . "/b/") (history . []) (state . "live"))]))))
      (a3madkour-pub-history/write-manifest m1)
      (let ((bytes1 (with-temp-buffer (insert-file-contents path) (buffer-string))))
        (a3madkour-pub-history/write-manifest m2)
        (let ((bytes2 (with-temp-buffer (insert-file-contents path) (buffer-string))))
          (should (string= bytes1 bytes2)))))))

(ert-deftest a3madkour-pub-history/git-mtime-async-returns-date ()
  (let (date)
    (cl-letf (((symbol-function 'call-process)
               (lambda (_cmd _ buf _ &rest _)
                 (when (bufferp buf)
                   (with-current-buffer buf (insert "2026-06-06"))) 0))
              ((symbol-function 'file-exists-p) (lambda (_) t)))
      (with-a3-pub-async-sync
       (a3madkour-pub-history/git-mtime-of-file-async
        "/tmp/x.org" (lambda (d) (setq date d)))))
    (should (string= "2026-06-06" date))))

(ert-deftest a3madkour-pub-history/git-mtime-sync-wrapper-still-works ()
  "The existing sync entry-point is preserved via the wrapper."
  (cl-letf (((symbol-function 'call-process)
             (lambda (_cmd _ buf _ &rest _)
               (when (bufferp buf)
                 (with-current-buffer buf (insert "2026-01-15"))) 0))
            ((symbol-function 'file-exists-p) (lambda (_) t)))
    (should (string= "2026-01-15"
                     (a3madkour-pub-history/git-mtime-of-file "/tmp/x.org")))))

(provide 'a3madkour-publish-history-test)

;;; a3madkour-publish-history-test.el ends here
