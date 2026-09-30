;;; a3madkour-publish-works-test.el --- tests for the works handler  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-works)
(require 'a3madkour-publish-living)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-async)

(defun a3madkour-pub-works-test--parse (org-text)
  "Parse ORG-TEXT and return its element AST."
  (with-temp-buffer (insert org-text) (org-mode) (org-element-parse-buffer)))

(ert-deftest a3madkour-pub-works--module-loads ()
  (should (fboundp 'a3madkour-pub-works/publish-works-file)))

(ert-deftest a3madkour-pub-works--parse-tracks-basic ()
  (let* ((ast (a3madkour-pub-works-test--parse "
#+NAME: tracks
| title     | duration |
|-----------+----------|
| Lorem One | 3:14     |
| Lorem Two | 4:20     |
"))
         (tracks (a3madkour-pub-works--parse-tracks ast)))
    (should (equal (length tracks) 2))
    (should (equal (alist-get 'title (car tracks)) "Lorem One"))
    (should (equal (alist-get 'duration (car tracks)) "3:14"))
    (should (equal (alist-get 'duration (nth 1 tracks)) "4:20"))))

(ert-deftest a3madkour-pub-works--parse-tracks-absent-is-nil ()
  (should (null (a3madkour-pub-works--parse-tracks
                 (a3madkour-pub-works-test--parse "Just a body.")))))

;; Review Focus #4 — header row only must yield nil, not an empty list,
;; so the key is omitted rather than emitted as `tracks: []'.
(ert-deftest a3madkour-pub-works--parse-tracks-header-only-is-nil ()
  (should (null (a3madkour-pub-works--parse-tracks
                 (a3madkour-pub-works-test--parse "
#+NAME: tracks
| title | duration |
|-------+----------|
")))))

(ert-deftest a3madkour-pub-works--parse-tracks-trims-cells ()
  (let ((tracks (a3madkour-pub-works--parse-tracks
                 (a3madkour-pub-works-test--parse "
#+NAME: tracks
| title       | duration |
|-------------+----------|
|   Padded    |   1:05   |
"))))
    (should (equal (alist-get 'title (car tracks)) "Padded"))))

;; Guard mutation test: verify both-empty-drop logic at line 61 (and vs or).
;; Row with title but empty duration is kept; row with both empty is dropped.
(ert-deftest a3madkour-pub-works--parse-tracks-filters-all-empty-rows ()
  (let ((tracks (a3madkour-pub-works--parse-tracks
                 (a3madkour-pub-works-test--parse "
#+NAME: tracks
| title      | duration |
|------------+----------|
| Song One   |          |
|            |          |
| Song Two   | 2:30     |
"))))
    (should (equal (length tracks) 2))
    (should (equal (alist-get 'title (car tracks)) "Song One"))
    (should (equal (alist-get 'duration (car tracks)) ""))
    (should (equal (alist-get 'title (nth 1 tracks)) "Song Two"))
    (should (equal (alist-get 'duration (nth 1 tracks)) "2:30"))))

(ert-deftest a3madkour-pub-works--renders-tracks-block ()
  (let ((out (a3madkour-pub-works--render-frontmatter
              '((title . "M")
                (tracks . (((title . "Lorem One") (duration . "3:14"))
                           ((title . "Lorem Two") (duration . "4:20"))))))))
    (should (string-match-p "tracks:\n" out))
    (should (string-match-p
             "  - { title: \"Lorem One\", duration: \"3:14\" }" out))
    (should (string-match-p
             "  - { title: \"Lorem Two\", duration: \"4:20\" }" out))))

(ert-deftest a3madkour-pub-works--renders-platform-embed-map ()
  (let ((out (a3madkour-pub-works--render-frontmatter
              '((title . "M")
                (platform_embed . ((kind . "bandcamp")
                                   (url . "https://example.bandcamp.com/album/x")))))))
    (should (string-match-p
             "platform_embed: { kind: bandcamp, url: \"https://example.bandcamp.com/album/x\" }"
             out))))

(ert-deftest a3madkour-pub-works--omits-empty-structured-keys ()
  (let ((out (a3madkour-pub-works--render-frontmatter
              '((title . "M") (tracks . nil) (platform_embed . nil)))))
    (should-not (string-match-p "tracks:" out))
    (should-not (string-match-p "platform_embed:" out))))

;; Strengthened from the brief's draft: the brief only asserted the absence
;; of the *unescaped* line, which passes trivially if rendering changes
;; shape for an unrelated reason.  This pins the actual escaped output that
;; `a3madkour-pub/yaml-escape-scalar' produces (backslash-quote each `"'),
;; so the test fails if escaping regresses to no-op, double-escapes, or
;; drops a character -- not just if the naive unescaped form reappears.
(ert-deftest a3madkour-pub-works--escapes-quotes-in-track-titles ()
  (let ((out (a3madkour-pub-works--render-frontmatter
              '((title . "M")
                (tracks . (((title . "He said \"hi\"") (duration . "1:00"))))))))
    (should-not (string-match-p "title: \"He said \"hi\"\"" out))
    (should (string-match-p
             (regexp-quote
              "  - { title: \"He said \\\"hi\\\"\", duration: \"1:00\" }")
             out))))

(ert-deftest a3madkour-pub-works--registers-both-sections ()
  (should (equal (cdr (assoc "works/games" a3madkour-pub-living--handlers))
                 'a3madkour-pub-works/publish-works-file))
  (should (equal (cdr (assoc "works/music" a3madkour-pub-living--handlers))
                 'a3madkour-pub-works/publish-works-file)))

(ert-deftest a3madkour-pub-works--bundle-dir-for-section ()
  (should (equal (a3madkour-pub-works--bundle-subdir "works/games") "works/games"))
  (should (equal (a3madkour-pub-works--bundle-subdir "works/music") "works/music"))
  (should-error (a3madkour-pub-works--bundle-subdir "works/poetry")))

(ert-deftest a3madkour-pub-works--normalize-symbol-for-section ()
  "Two-symbol convention: slash on the wire, hyphen into normalize."
  (should (eq (a3madkour-pub-works--normalize-symbol "works/games") 'works-games))
  (should (eq (a3madkour-pub-works--normalize-symbol "works/music") 'works-music)))

;; Review Focus #3 — two titles that slugify identically must not silently
;; overwrite one another.
(ert-deftest a3madkour-pub-works--duplicate-slug-is-refused ()
  (let ((seen (make-hash-table :test #'equal)))
    (should (a3madkour-pub-works--claim-slug seen "mnemosyne" "/tmp/a.org"))
    (should-error (a3madkour-pub-works--claim-slug seen "mnemosyne" "/tmp/b.org"))))

;; Review Focus #5 — section set but publish flag absent must not publish.
;; Investigated: `a3madkour-pub/note-section' routes through
;; `a3madkour-pub/note-metadata', which returns nil whenever `:state' is nil
;; -- and `:state' is nil whenever `#+HUGO_PUBLISH:' is not literally "t"
;; (see `a3madkour-pub--parse-file'  / `a3madkour-pub-keywords/boolean-p').
;; So `note-section' itself already returns nil for an unmarked file --
;; there is no pre-existing defect here, and `collect-triples' (which
;; compares directly against `note-section''s return value) is safe as
;; written.  This test is unchanged from the brief's draft because the
;; assertion it makes is the true behavior, not a workaround.
(ert-deftest a3madkour-pub-works--unmarked-file-is-not-collected ()
  (let* ((dir (make-temp-file "a3-works-unmarked" t))
         (f (expand-file-name "g.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert "#+TITLE: G\n#+HUGO_SECTION: works/games\n"))
          (should-not (equal (a3madkour-pub/note-section f) "works/games")))
      (delete-directory dir t))))

;; Guard-effectiveness test for the slug-table reset scope (fixing the
;; defect the brief documents but never wires up): the table must clear
;; once per RUN (eq-identity), not on every call (that would let a genuine
;; in-run duplicate slide through) and not never (that would let a stale
;; claim from a *previous* run block a renamed file forever).
(ert-deftest a3madkour-pub-works--slugs-seen-resets-per-run-not-per-file ()
  (let ((a3madkour-pub-works--slugs-seen (make-hash-table :test #'equal))
        (a3madkour-pub-works--slugs-seen-run 'a3madkour-pub-works--no-run-yet)
        (run-1 (make-a3-pub-async-run))
        (run-2 (make-a3-pub-async-run)))
    ;; First call of run-1 claims "a" for file-a.
    (a3madkour-pub-works--maybe-reset-slugs-seen run-1)
    (should (a3madkour-pub-works--claim-slug
             a3madkour-pub-works--slugs-seen "a" "/tmp/file-a.org"))
    ;; A second call within the SAME run must not reset the table: a real
    ;; duplicate slug inside one run still has to collide.
    (a3madkour-pub-works--maybe-reset-slugs-seen run-1)
    (should-error (a3madkour-pub-works--claim-slug
                   a3madkour-pub-works--slugs-seen "a" "/tmp/file-b.org"))
    ;; A NEW run clears the table -- a renamed file (new path, same slug)
    ;; must not collide with the previous run's now-stale claim.
    (a3madkour-pub-works--maybe-reset-slugs-seen run-2)
    (should (a3madkour-pub-works--claim-slug
             a3madkour-pub-works--slugs-seen "a" "/tmp/file-a-renamed.org"))))

(defun a3madkour-pub-works-test--write-game-fixture (src site-dir)
  "Write a minimal works/games org fixture at SRC targeting SITE-DIR."
  (with-temp-file src
    (insert ":PROPERTIES:\n"
            ":ID: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n"
            ":END:\n"
            "#+title: Example Game\n"
            "#+HUGO_PUBLISH: t\n"
            "#+HUGO_SECTION: works/games\n"
            "#+HUGO_BASE_DIR: " site-dir "\n"
            "Body text.\n")))

;; End-to-end: two successive publish runs over the same file both succeed.
;; This is the case the brief's undone `slugs-seen' clearing was meant to
;; guard without breaking -- a naive "block anything already claimed" guard
;; would make this fail on the second run once the hash carries the first
;; run's entry indefinitely.  `--claim-slug' alone tolerates a same-file
;; re-claim regardless of clearing (prior equals file), so this test by
;; itself would pass even with the never-cleared defect; the reset-scope
;; test above is what actually pins the fix.  Kept per the task instruction
;; because it is the literal scenario named there and documents the
;; run-over-run idempotence contract end to end.
(ert-deftest a3madkour-pub-works--two-successive-runs-over-same-file-both-succeed ()
  (let* ((notes-dir (make-temp-file "a3-pub-works-notes-" t))
         (site-dir  (make-temp-file "a3-pub-works-site-" t))
         (src       (expand-file-name "example-game.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (make-directory (expand-file-name "content/works/games" site-dir) t)
          (a3madkour-pub-works-test--write-game-fixture src site-dir)
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir)
                (a3madkour-works-lint-enabled nil)
                (done-1 'unset)
                (done-2 'unset))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-works/publish-works-file
               src (make-a3-pub-async-run)
               :on-done (lambda (s) (setq done-1 s)))
              (a3madkour-pub/finish-publish)
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-works/publish-works-file
               src (make-a3-pub-async-run)
               :on-done (lambda (s) (setq done-2 s)))
              (a3madkour-pub/finish-publish))
            (should (eq done-1 'ok))
            (should (eq done-2 'ok))
            (let ((out (expand-file-name
                        "content/works/games/example-game/index.md" site-dir)))
              (should (file-exists-p out))
              (with-temp-buffer
                (insert-file-contents out)
                (should (string-match-p "title:" (buffer-string)))
                (should (string-match-p "Body text" (buffer-string)))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(provide 'a3madkour-publish-works-test)

;;; a3madkour-publish-works-test.el ends here
