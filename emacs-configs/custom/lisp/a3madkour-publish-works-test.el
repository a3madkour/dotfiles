;;; a3madkour-publish-works-test.el --- tests for the works handler  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-works)
(require 'a3madkour-publish-living)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-async)
;; The works normalizer reads its allowed-key contract from the site repo's
;; `data/works-vocab.json', so every temp site root below has to carry one.
(require 'a3madkour-works-vocab-fixture)

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
          (a3madkour-works-vocab-test/write site-dir)
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

;; Pins the 5th-positional (extra-refs) contract on
;; `a3madkour-pub/asset-validate-and-copy'.  A missing declared asset must
;; not ship a broken filename into the page frontmatter -- `hero' drops the
;; whole key when its file is absent.  That half alone, though, passes
;; identically whether the call is correct OR has `extra-refs' silently
;; shifted into the `dry-run' slot (dropping the positional `nil'): under
;; the shift, `extra-refs' becomes nil so the loop that would report
;; "extra-ref not found" never runs at all, and the missing asset still
;; ends up dropped by coincidence -- same visible outcome, wrong reason.
;; So this test ALSO declares a `screenshots' entry whose file DOES exist:
;; under correct code that file gets copied and the entry survives; under
;; the positional-shift mutation, `dry-run' becomes truthy (the non-nil
;; names list) and NOTHING gets copied, including the present file, so it
;; would wrongly disappear too.  That divergence is what actually catches
;; the mutation -- see the mutation transcript in the task-7 report.
(ert-deftest a3madkour-pub-works--drops-broken-asset-keys-and-keeps-landed-ones ()
  (let* ((notes-dir (make-temp-file "a3-pub-works-notes-" t))
         (site-dir  (make-temp-file "a3-pub-works-site-" t))
         (src       (expand-file-name "example-game-assets.org" notes-dir))
         (id        "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")
         (assets-dir (expand-file-name (format "assets/%s/" id) notes-dir)))
    (unwind-protect
        (progn
          (a3madkour-works-vocab-test/write site-dir)
          (make-directory (expand-file-name "content/works/games" site-dir) t)
          (make-directory assets-dir t)
          ;; present-shot.png exists on disk; missing-hero.png does not.
          (with-temp-file (expand-file-name "present-shot.png" assets-dir)
            (insert "not-really-a-png"))
          (with-temp-file src
            (insert ":PROPERTIES:\n"
                    ":ID: " id "\n"
                    ":END:\n"
                    "#+title: Example Game With Assets\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: works/games\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "#+HUGO_CUSTOM_FRONT_MATTER: :hero missing-hero.png\n"
                    "#+HUGO_CUSTOM_FRONT_MATTER: :screenshots present-shot.png\n"
                    "Body text.\n"))
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir)
                (a3madkour-works-lint-enabled nil)
                (done 'unset))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-works/publish-works-file
               src (make-a3-pub-async-run)
               :on-done (lambda (s) (setq done s)))
              (a3madkour-pub/finish-publish))
            (should (eq done 'ok))
            (let ((out (expand-file-name
                        "content/works/games/example-game-with-assets/index.md"
                        site-dir)))
              (should (file-exists-p out))
              (should (file-exists-p
                       (expand-file-name
                        "content/works/games/example-game-with-assets/present-shot.png"
                        site-dir)))
              (with-temp-buffer
                (insert-file-contents out)
                (let ((fm (buffer-string)))
                  ;; Missing asset: key dropped entirely.
                  (should-not (string-match-p "hero:" fm))
                  (should-not (string-match-p "missing-hero" fm))
                  ;; Present asset: survives and is actually referenced.
                  (should (string-match-p "present-shot.png" fm)))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

;;; --warn-stale-backlink (Task 9)

(defmacro a3madkour-pub-works-test--capture-warnings (&rest body)
  "Run BODY with `message' mocked; return (RESULT . WARNINGS)."
  (declare (indent 0))
  `(let ((warnings '()))
     (let ((result (cl-letf (((symbol-function 'message)
                              (lambda (fmt &rest args)
                                (push (apply #'format fmt args) warnings))))
                     ,@body)))
       (cons result warnings))))

(ert-deftest a3madkour-pub-works--warn-stale-backlink-fires-when-key-absent ()
  "Bundle exists but lacks `set_to_music:' → a WARN naming the fix command."
  (let* ((root (make-temp-file "a3-warn-stale" t))
         (bundle-dir (expand-file-name "content/works/poetry/tessellations/" root)))
    (unwind-protect
        (progn
          (make-directory bundle-dir t)
          (with-temp-file (expand-file-name "index.md" bundle-dir)
            (insert "---\ntitle: Tessellations\n---\nBody.\n"))
          (let* ((a3madkour-pub/poetry-dir root)
                 (out (a3madkour-pub-works-test--capture-warnings
                        (a3madkour-pub-works--warn-stale-backlink "tessellations" root))))
            (should (seq-some (lambda (m)
                                (string-match-p
                                 "lacks set_to_music.*--publish-deliberate.*tessellations\\.org"
                                 m))
                              (cdr out)))))
      (delete-directory root t))))

(ert-deftest a3madkour-pub-works--warn-stale-backlink-silent-when-key-present ()
  "Bundle already carries `set_to_music:' → no WARN."
  (let* ((root (make-temp-file "a3-warn-stale" t))
         (bundle-dir (expand-file-name "content/works/poetry/tessellations/" root)))
    (unwind-protect
        (progn
          (make-directory bundle-dir t)
          (with-temp-file (expand-file-name "index.md" bundle-dir)
            (insert "---\ntitle: Tessellations\nset_to_music: m\n---\nBody.\n"))
          (let* ((a3madkour-pub/poetry-dir root)
                 (out (a3madkour-pub-works-test--capture-warnings
                        (a3madkour-pub-works--warn-stale-backlink "tessellations" root))))
            (should-not (cdr out))))
      (delete-directory root t))))

(ert-deftest a3madkour-pub-works--warn-stale-backlink-silent-when-bundle-absent ()
  "No published bundle yet (poem never deliberate-published) → no WARN.
Not an error case: the lint already caught an org-source mismatch; a bundle
that has simply never been published is not what this warning is for."
  (let* ((root (make-temp-file "a3-warn-stale" t)))
    (unwind-protect
        (let* ((a3madkour-pub/poetry-dir root)
               (out (a3madkour-pub-works-test--capture-warnings
                      (a3madkour-pub-works--warn-stale-backlink "tessellations" root))))
          (should-not (cdr out)))
      (delete-directory root t))))


;;; Defect 5 (task-12 E2E) — the `#+NAME: tracks' table leaked into the body.
;;
;; It is parsed for the frontmatter from the ORIGINAL AST but was never removed
;; from the export input, so ox-hugo rendered it a second time as a raw,
;; unstyled table inside the About section, beside the templated Tracks
;; section.  Unit tests of `--parse-tracks' could not see this: it is the
;; exported BODY that is wrong, not the parse.

(ert-deftest a3madkour-pub-works--strip-named-table-removes-name-line-too ()
  "The `#+NAME:' affiliated keyword goes with the table, not just the rows."
  (let ((out (a3madkour-pub-works--strip-named-table
              "#+TITLE: M\nHeadnote.\n\n#+NAME: tracks\n| title | duration |\n|-------+----------|\n| One   | 3:14     |\n\nTail.\n"
              "tracks")))
    (should-not (string-match-p "#\\+NAME: tracks" out))
    (should-not (string-match-p "|" out))
    (should (string-match-p "Headnote\\." out))
    (should (string-match-p "Tail\\." out))))

(ert-deftest a3madkour-pub-works--strip-named-table-leaves-other-tables ()
  "Only the named table goes; an unrelated body table is content."
  (let ((out (a3madkour-pub-works--strip-named-table
              "#+NAME: tracks\n| title | duration |\n| One   | 3:14     |\n\n| keep | me |\n"
              "tracks")))
    (should-not (string-match-p "duration" out))
    (should (string-match-p "| keep | me |" out))))

(defun a3madkour-pub-works-test--write-music-fixture (src site-dir)
  "Write a works/music org fixture with a `#+NAME: tracks' table at SRC."
  (with-temp-file src
    (insert ":PROPERTIES:\n"
            ":ID: dddddddd-eeee-ffff-0000-111111111111\n"
            ":END:\n"
            "#+title: Example Release\n"
            "#+HUGO_PUBLISH: t\n"
            "#+HUGO_SECTION: works/music\n"
            "#+HUGO_BASE_DIR: " site-dir "\n"
            "#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026\n"
            "\n"
            "Headnote prose.\n"
            "\n"
            "#+NAME: tracks\n"
            "| title     | duration |\n"
            "|-----------+----------|\n"
            "| Lorem One | 3:14     |\n")))

(ert-deftest a3madkour-pub-works--tracks-table-does-not-leak-into-the-body ()
  "The tracks table reaches the frontmatter and NOT the rendered body."
  (let* ((notes-dir (make-temp-file "a3-pub-works-notes-" t))
         (site-dir  (make-temp-file "a3-pub-works-site-" t))
         (src       (expand-file-name "example-release.org" notes-dir)))
    (unwind-protect
        (progn
          (a3madkour-works-vocab-test/write site-dir)
          (make-directory (expand-file-name "content/works/music" site-dir) t)
          (a3madkour-pub-works-test--write-music-fixture src site-dir)
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir)
                (a3madkour-works-lint-enabled nil)
                (done 'unset))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-works/publish-works-file
               src (make-a3-pub-async-run) :on-done (lambda (st) (setq done st)))
              (a3madkour-pub/finish-publish))
            (should (eq done 'ok))
            (let ((out (expand-file-name
                        "content/works/music/example-release/index.md" site-dir)))
              (should (file-exists-p out))
              (with-temp-buffer
                (insert-file-contents out)
                (let* ((text (buffer-string))
                       ;; Split at the closing frontmatter fence so the body
                       ;; assertions cannot be satisfied by the frontmatter's
                       ;; own (correct, flow-map) rendering of the same data.
                       (body (progn
                               (goto-char (point-min))
                               (forward-line 1)
                               (if (re-search-forward "^---$" nil t)
                                   (buffer-substring-no-properties
                                    (point) (point-max))
                                 text))))
                  ;; The parse still happened: frontmatter carries the track.
                  (should (string-match-p "tracks:" text))
                  (should (string-match-p "Lorem One" text))
                  ;; The body carries the headnote and no table at all.
                  (should (string-match-p "Headnote prose" body))
                  (should-not (string-match-p "| title" body))
                  (should-not (string-match-p "Lorem One" body))
                  (should-not (string-match-p "table--tracks" body)))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))


;; Defect 6, the other end: the assembled shape has to satisfy the render
;; key-hook.  `renders-platform-embed-map' above hand-builds the nested alist
;; in elisp, which is precisely the step real authoring could never reach --
;; so it passed while the field was unreachable.  Chaining normalize into
;; render is what pins the authoring path end to end.
(ert-deftest a3madkour-pub-works--platform-embed-round-trips-from-flat-keys ()
  (a3madkour-works-vocab-test--with-root a3madkour-works-vocab-test--json
   (let* ((fm (a3madkour-pub-frontmatter/normalize
              'works-music
              '((title . "M") (year . "2026") (format . "album")
                (platform_kind . "bandcamp")
                (platform_url . "https://example.bandcamp.com/album/x"))
              "/tmp/a3-works-no-such-file.org"))
         (yaml (a3madkour-pub-works--render-frontmatter fm)))
    (should (string-match-p
             "platform_embed: { kind: bandcamp, url: \"https://example\\.bandcamp\\.com/album/x\" }"
             yaml))
    ;; Not the `:omit' branch, and not a quoted scalar.
    (should-not (string-match-p "platform_embed: \"" yaml)))))


;;; `#+HUGO_SUMMARY:' through a REAL export (final-review finding 1)
;;
;; `summary' is in both allowed key sets, so the filter was never the problem
;; — nothing ever put the value in.  ox-hugo has no built-in HUGO_SUMMARY
;; keyword, which is precisely why the essays and recipes normalizers read it
;; with `--read-org-keyword'; works did not, so the key was silently absent
;; from every published game and release.  The design's own §3.1 example org
;; file carries `#+HUGO_SUMMARY:' and `layouts/partials/works/tile.html'
;; renders `summary' as the tile pull-quote, so the documented path lost the
;; pull-quote with no error at any layer.
;;
;; These go through the REAL exporter, not a hand-built alist.  The test that
;; should have caught this — `works-games-keeps-every-legal-key' — fed
;; `(summary . "S")' into `normalize' directly, which is §8a defect 4's exact
;; pattern: the input already contained what the code under test was supposed
;; to supply.

(defun a3madkour-pub-works-test--frontmatter-of (path)
  "Return PATH's YAML frontmatter block (between the two `---' fences)."
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (forward-line 1)
    (let ((start (point)))
      (if (re-search-forward "^---$" nil t)
          (buffer-substring-no-properties start (match-beginning 0))
        (buffer-string)))))

(defmacro a3madkour-pub-works-test--with-published (fixture-body &rest body)
  "Publish one works org file and run BODY with `out' bound to its index.md.

FIXTURE-BODY is a form evaluated with `src' and `site-dir' bound, which must
write the org source.  `slug-path' must be bound by BODY's caller via
`a3madkour-pub-works-test--published-path'."
  (declare (indent 1))
  `(let* ((notes-dir (make-temp-file "a3-pub-works-notes-" t))
          (site-dir  (make-temp-file "a3-pub-works-site-" t))
          (src       (expand-file-name "example.org" notes-dir))
          (messages  '()))
     (unwind-protect
         (progn
           (a3madkour-works-vocab-test/write site-dir)
           (make-directory (expand-file-name "content/works/games" site-dir) t)
           (make-directory (expand-file-name "content/works/music" site-dir) t)
           ,fixture-body
           (let ((a3madkour-pub/site-data-dir
                  (file-name-as-directory (expand-file-name "data" site-dir)))
                 (a3madkour-pub/org-notes-dir notes-dir)
                 (a3madkour-works-lint-enabled nil)
                 (done 'unset))
             (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
               (a3madkour-pub/begin-publish)
               (cl-letf (((symbol-function 'message)
                          (lambda (fmt &rest args)
                            (push (apply #'format fmt args) messages))))
                 (a3madkour-pub-works/publish-works-file
                  src (make-a3-pub-async-run) :on-done (lambda (s) (setq done s))))
               (a3madkour-pub/finish-publish))
             (should (eq done 'ok))
             ,@body))
       (delete-directory notes-dir t)
       (delete-directory site-dir t))))

(ert-deftest a3madkour-pub-works--games-summary-survives-a-real-export ()
  (a3madkour-pub-works-test--with-published
      (with-temp-file src
        (insert ":PROPERTIES:\n"
                ":ID: 11111111-2222-3333-4444-555555555555\n"
                ":END:\n"
                "#+title: Mnemosyne\n"
                "#+HUGO_PUBLISH: t\n"
                "#+HUGO_SECTION: works/games\n"
                "#+HUGO_BASE_DIR: " site-dir "\n"
                "#+HUGO_SUMMARY: A memory-palace roguelike built for a thesis chapter.\n"
                "#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam\n"
                "#+HUGO_CUSTOM_FRONT_MATTER: :year 2026 :tagline T\n"
                "Body text.\n"))
    (let ((fm (a3madkour-pub-works-test--frontmatter-of
               (expand-file-name "content/works/games/mnemosyne/index.md"
                                 site-dir))))
      (should (string-match-p "memory-palace roguelike built for a thesis chapter"
                              fm)))))

(ert-deftest a3madkour-pub-works--music-summary-survives-a-real-export ()
  (a3madkour-pub-works-test--with-published
      (with-temp-file src
        (insert ":PROPERTIES:\n"
                ":ID: 22222222-3333-4444-5555-666666666666\n"
                ":END:\n"
                "#+title: Drone Studies\n"
                "#+HUGO_PUBLISH: t\n"
                "#+HUGO_SECTION: works/music\n"
                "#+HUGO_BASE_DIR: " site-dir "\n"
                "#+HUGO_SUMMARY: Forty-two minutes of tape-saturated drone.\n"
                "#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026\n"
                "Headnote.\n"))
    (let ((fm (a3madkour-pub-works-test--frontmatter-of
               (expand-file-name "content/works/music/drone-studies/index.md"
                                 site-dir))))
      (should (string-match-p "Forty-two minutes of tape-saturated drone" fm)))))


;;; Asset drops are reported, not swallowed (final-review finding 5)
;;
;; `--drop-broken-assets' reads only `:copied' and used to discard
;; `asset-validate-and-copy''s `:errors'.  With `--skip-works-check', or with
;; `a3madkour-works-lint-enabled' nil — which this file's own integration tests
;; set — a typo'd hero/screenshots/cover was dropped with ZERO output at any
;; layer.  Asserted on "extra-ref not found", the message the assets module
;; actually produces, rather than on the bare word "hero" that several other
;; paths also emit.

(ert-deftest a3madkour-pub-works--reports-dropped-assets-with-the-lint-off ()
  (a3madkour-pub-works-test--with-published
      (with-temp-file src
        (insert ":PROPERTIES:\n"
                ":ID: 33333333-4444-5555-6666-777777777777\n"
                ":END:\n"
                "#+title: Typo Hero Game\n"
                "#+HUGO_PUBLISH: t\n"
                "#+HUGO_SECTION: works/games\n"
                "#+HUGO_BASE_DIR: " site-dir "\n"
                "#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam\n"
                "#+HUGO_CUSTOM_FRONT_MATTER: :year 2026 :tagline T :hero heor.png\n"
                "Body text.\n"))
    ;; The key really was dropped (the pre-existing half) ...
    (let ((fm (a3madkour-pub-works-test--frontmatter-of
               (expand-file-name "content/works/games/typo-hero-game/index.md"
                                 site-dir))))
      (should-not (string-match-p "heor.png" fm)))
    ;; ... and the drop was reported, which is the part that was missing.
    (should (seq-some (lambda (m)
                        (and (string-match-p "asset dropped" m)
                             (string-match-p "extra-ref not found" m)
                             (string-match-p "heor\\.png" m)))
                      messages))))


;;; `--warn-stale-backlink' call-site wiring (final-review finding 9)
;;
;; The three tests above only call the helper directly, so the `(eq nsym
;; 'works-music)' gate in `publish-works-file' and its `lyrics_poem' read out
;; of `final-fm' were unpinned.  Deferred during execution on the grounds that
;; the end-to-end run might not happen; it did.

(ert-deftest a3madkour-pub-works--publish-fires-the-stale-backlink-warning ()
  (let ((poetry-dir (make-temp-file "a3-works-poetry-" t)))
    (unwind-protect
        (a3madkour-pub-works-test--with-published
            (progn
              ;; A published poem bundle that has NOT yet grown its back-link.
              (make-directory
               (expand-file-name "content/works/poetry/tessellations" site-dir) t)
              (with-temp-file (expand-file-name
                               "content/works/poetry/tessellations/index.md" site-dir)
                (insert "---\ntitle: Tessellations\n---\nBody.\n"))
              (with-temp-file (expand-file-name "tessellations.org" poetry-dir)
                (insert "#+TITLE: Tessellations\n"))
              (with-temp-file src
                (insert ":PROPERTIES:\n"
                        ":ID: 44444444-5555-6666-7777-888888888888\n"
                        ":END:\n"
                        "#+title: Set To Music\n"
                        "#+HUGO_PUBLISH: t\n"
                        "#+HUGO_SECTION: works/music\n"
                        "#+HUGO_BASE_DIR: " site-dir "\n"
                        "#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026\n"
                        "#+HUGO_CUSTOM_FRONT_MATTER: :lyrics_poem tessellations\n"
                        "Headnote.\n")))
          (should (seq-some
                   (lambda (m) (string-match-p "lacks set_to_music" m))
                   messages)))
      (delete-directory poetry-dir t))))

(ert-deftest a3madkour-pub-works--publish-is-silent-without-lyrics-poem ()
  "The gate is a gate: a music release declaring no poem warns about nothing."
  (a3madkour-pub-works-test--with-published
      (with-temp-file src
        (insert ":PROPERTIES:\n"
                ":ID: 55555555-6666-7777-8888-999999999999\n"
                ":END:\n"
                "#+title: No Poem Here\n"
                "#+HUGO_PUBLISH: t\n"
                "#+HUGO_SECTION: works/music\n"
                "#+HUGO_BASE_DIR: " site-dir "\n"
                "#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026\n"
                "Headnote.\n"))
    (should-not (seq-some (lambda (m) (string-match-p "lacks set_to_music" m))
                          messages))))


(provide 'a3madkour-publish-works-test)

;;; a3madkour-publish-works-test.el ends here
