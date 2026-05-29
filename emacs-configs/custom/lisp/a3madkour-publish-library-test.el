;;; a3madkour-publish-library-test.el --- tests for library handler  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-library)

(defun a3madkour-pub-library-test--parse-headline (org-text)
  "Helper: parse ORG-TEXT and return the first top-level headline element."
  (with-temp-buffer
    (insert org-text)
    (org-mode)
    (car (org-element-map (org-element-parse-buffer) 'headline #'identity nil nil nil))))

(ert-deftest a3madkour-pub-library--module-loads ()
  "Smoke: module loadable and exposes publish-library-file."
  (should (fboundp 'a3madkour-pub-library/publish-library-file)))

(ert-deftest a3madkour-pub-library--config-table-shape ()
  "Per-medium config table has all 4 library sections with the right shape."
  (dolist (section '(library-reading library-listening library-playing library-watching))
    (let ((cfg (a3madkour-pub-library--config-for section)))
      (should (= 4 (length cfg)))
      (should (stringp (nth 0 cfg)))           ; yaml filename
      (should (stringp (nth 1 cfg)))           ; default media_type
      (should (listp (nth 2 cfg)))             ; allowed media_types
      (should (listp (nth 3 cfg)))             ; allowed statuses
      (should (member (nth 1 cfg) (nth 2 cfg))))) ; default ∈ allowed
  (should-error (a3madkour-pub-library--config-for 'bogus)))

(ert-deftest a3madkour-pub-library--title-to-slug ()
  "Title-to-slug derivation covers spec §5 edge cases."
  (should (equal (a3madkour-pub-library--title-to-slug "Pride and Prejudice")
                 "pride-and-prejudice"))
  (should (equal (a3madkour-pub-library--title-to-slug "L'Étranger")
                 "l-etranger"))
  (should (equal (a3madkour-pub-library--title-to-slug "Köyaanisqatsi")
                 "koyaanisqatsi"))
  (should (equal (a3madkour-pub-library--title-to-slug "Crime & Punishment")
                 "crime-punishment"))
  (should (equal (a3madkour-pub-library--title-to-slug "Dune: Part One")
                 "dune-part-one"))
  (should (equal (a3madkour-pub-library--title-to-slug "Maximum a Posteriori (MAP)")
                 "maximum-a-posteriori-map"))
  (should (equal (a3madkour-pub-library--title-to-slug "1984")
                 "1984"))
  (should (equal (a3madkour-pub-library--title-to-slug "  Leading-Trailing  ")
                 "leading-trailing"))
  (should (equal (a3madkour-pub-library--title-to-slug "!?!")
                 ""))
  (should (equal (a3madkour-pub-library--title-to-slug "Severance S2")
                 "severance-s2")))

(ert-deftest a3madkour-pub-library--normalize-required-fields ()
  "Required-field happy path covers title, slug, creator, year, media_type, status."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Pride and Prejudice
:PROPERTIES:
:CREATOR: Jane Austen
:YEAR: 1813
:STATUS: finished
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org")))
    (should (equal (plist-get row :slug) "pride-and-prejudice"))
    (should (equal (plist-get row :title) "Pride and Prejudice"))
    (should (equal (plist-get row :creator) "Jane Austen"))
    (should (equal (plist-get row :year) 1813))
    (should (equal (plist-get row :media_type) "book"))
    (should (equal (plist-get row :status) "finished"))))

(ert-deftest a3madkour-pub-library--normalize-slug-override ()
  "Explicit :SLUG: drawer overrides title-derived fallback."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* L'Étranger
:PROPERTIES:
:SLUG: the-stranger
:CREATOR: Camus
:YEAR: 1942
:STATUS: finished
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org")))
    (should (equal (plist-get row :slug) "the-stranger"))))

(ert-deftest a3madkour-pub-library--normalize-media-type-default ()
  "Missing :MEDIA_TYPE: defaults to the section default (book/album/game/film)."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Untitled
:PROPERTIES:
:CREATOR: Someone
:YEAR: 2024
:STATUS: queued
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-watching))
         (row (a3madkour-pub-library--normalize-item src 'library-watching cfg "/tmp/x.org")))
    (should (equal (plist-get row :media_type) "film"))))

(ert-deftest a3madkour-pub-library--normalize-media-type-override ()
  "Explicit :MEDIA_TYPE: overrides the section default."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Severance S2
:PROPERTIES:
:MEDIA_TYPE: series
:CREATOR: Apple TV+
:YEAR: 2025
:STATUS: finished
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-watching))
         (row (a3madkour-pub-library--normalize-item src 'library-watching cfg "/tmp/x.org")))
    (should (equal (plist-get row :media_type) "series"))))

(ert-deftest a3madkour-pub-library--normalize-status-enum-warn ()
  "Out-of-enum :STATUS: WARNs but still emits the value (linter catches)."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Bogus
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: to-read
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (warnings '())
         (row (cl-letf (((symbol-function 'message)
                         (lambda (fmt &rest args)
                           (push (apply #'format fmt args) warnings))))
                (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org"))))
    (should (equal (plist-get row :status) "to-read"))
    (should (seq-some (lambda (m) (string-match-p "status.*to-read.*not in" m)) warnings))))

(ert-deftest a3madkour-pub-library--normalize-optional-passthroughs ()
  "Optional drawer fields pass through unchanged."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Item
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: finished
:STARTED: 2024-01-01
:FINISHED: 2024-06-15
:SPOILER_LEVEL: light
:CITE_KEY: doe2024
:CANONICAL_URL: https://example.com/item
:NOTE_SLUG: my-note
:PREVIEW: A short annotation.
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org")))
    (should (equal (plist-get row :started) "2024-01-01"))
    (should (equal (plist-get row :finished) "2024-06-15"))
    (should (equal (plist-get row :spoiler_level) "light"))
    (should (equal (plist-get row :cite_key) "doe2024"))
    (should (equal (plist-get row :canonical_url) "https://example.com/item"))
    (should (equal (plist-get row :note_slug) "my-note"))
    (should (equal (plist-get row :preview) "A short annotation."))))

(ert-deftest a3madkour-pub-library--normalize-optional-absent ()
  "Absent optional drawers don't appear in the row plist."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Item
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: queued
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org")))
    (should-not (plist-member row :started))
    (should-not (plist-member row :finished))
    (should-not (plist-member row :preview))))

(ert-deftest a3madkour-pub-library--normalize-tags-roundtrip ()
  "Per-heading org tags round-trip via filter-editorial-tags."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Pride and Prejudice :classics:romance:
:PROPERTIES:
:CREATOR: Austen
:YEAR: 1813
:STATUS: finished
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org")))
    (should (equal (plist-get row :tags) '("classics" "romance")))))

(ert-deftest a3madkour-pub-library--normalize-tags-strips-editorial ()
  "TODO/NOEXPORT/etc. on per-heading tags are stripped."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Item :classics:TODO:fiction:NOEXPORT:
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: queued
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org")))
    (should (equal (plist-get row :tags) '("classics" "fiction")))))

(ert-deftest a3madkour-pub-library--normalize-tags-empty-after-filter ()
  "All-editorial tag list → :tags key still present with empty list (linter needs the key)."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Item :TODO:NOEXPORT:
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: queued
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org")))
    (should (equal (plist-get row :tags) '()))))

(ert-deftest a3madkour-pub-library--normalize-last-modified-drawer ()
  "Per-heading :LAST_MODIFIED: drawer beats git-mtime fallback."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Item
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: queued
:LAST_MODIFIED: 2025-03-14
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org")))
    (should (equal (plist-get row :last_modified) "2025-03-14"))))

(ert-deftest a3madkour-pub-library--normalize-last-modified-git-mtime-fallback ()
  "Absent :LAST_MODIFIED: falls back to git-mtime-of-file."
  (let* ((tmpdir (make-temp-file "a3-pub-libmtime-" t))
         (file (expand-file-name "x.org" tmpdir)))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
                   (lambda (f) (ignore f) "2026-01-15")))
          (let* ((src (a3madkour-pub-library-test--parse-headline
                       "* Item
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: queued
:END:
"))
                 (cfg (a3madkour-pub-library--config-for 'library-reading))
                 (row (a3madkour-pub-library--normalize-item src 'library-reading cfg file)))
            (should (equal (plist-get row :last_modified) "2026-01-15"))))
      (delete-directory tmpdir t))))

(ert-deftest a3madkour-pub-library--normalize-extras-book ()
  "Book extras: ISBN + progress_pct/progress_label + universal covers."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Item
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: reading
:ISBN: 9780141439518
:PROGRESS_PCT: 42
:PROGRESS_LABEL: p. 84 / 200
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org"))
         (extras (plist-get row :extras)))
    (should (equal (plist-get extras :isbn) "9780141439518"))
    (should (equal (plist-get extras :progress_pct) 42))
    (should (equal (plist-get extras :progress_label) "p. 84 / 200"))))

(ert-deftest a3madkour-pub-library--normalize-extras-game ()
  "Game extras: igdb_id (int) + hours_played (int) + platform."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Outer Wilds
:PROPERTIES:
:CREATOR: Mobius
:YEAR: 2019
:STATUS: playing
:IGDB_ID: 12345
:HOURS_PLAYED: 22
:PLATFORM: PC
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-playing))
         (row (a3madkour-pub-library--normalize-item src 'library-playing cfg "/tmp/x.org"))
         (extras (plist-get row :extras)))
    (should (equal (plist-get extras :igdb_id) 12345))
    (should (equal (plist-get extras :hours_played) 22))
    (should (equal (plist-get extras :platform) "PC"))))

(ert-deftest a3madkour-pub-library--normalize-extras-series ()
  "Series extras: episode_count + current_episode + current_season + tmdb_id."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Severance S2
:PROPERTIES:
:MEDIA_TYPE: series
:CREATOR: Apple TV+
:YEAR: 2025
:STATUS: finished
:EPISODE_COUNT: 10
:CURRENT_EPISODE: 4
:CURRENT_SEASON: 2
:TMDB_ID: 67890
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-watching))
         (row (a3madkour-pub-library--normalize-item src 'library-watching cfg "/tmp/x.org"))
         (extras (plist-get row :extras)))
    (should (equal (plist-get extras :episode_count) 10))
    (should (equal (plist-get extras :current_episode) 4))
    (should (equal (plist-get extras :current_season) 2))
    (should (equal (plist-get extras :tmdb_id) 67890))))

(ert-deftest a3madkour-pub-library--normalize-extras-ignored-cross-medium ()
  ":ISBN: on an album is silently ignored (forward-compatible)."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Album
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: listening
:ISBN: 9780000000000
:MBID: aaaaaaaa-bbbb
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-listening))
         (row (a3madkour-pub-library--normalize-item src 'library-listening cfg "/tmp/x.org"))
         (extras (plist-get row :extras)))
    (should-not (plist-member extras :isbn))
    (should (equal (plist-get extras :musicbrainz_release_group) "aaaaaaaa-bbbb"))))

(ert-deftest a3madkour-pub-library--normalize-cover-file-existence-warn ()
  "Missing cover file → WARN, but :cover_file key still emitted."
  (let* ((src (a3madkour-pub-library-test--parse-headline
               "* Item
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: reading
:COVER_FILE: nonexistent.jpg
:END:
"))
         (cfg (a3madkour-pub-library--config-for 'library-reading))
         (warnings '())
         ;; Stub: --site-static-dir-of returns a tmp dir with no cover file.
         (tmpdir (make-temp-file "a3-pub-covers-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-library--site-static-dir-of)
                   (lambda (file) (ignore file) tmpdir))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (push (apply #'format fmt args) warnings))))
          (let* ((row (a3madkour-pub-library--normalize-item src 'library-reading cfg "/tmp/x.org"))
                 (extras (plist-get row :extras)))
            (should (equal (plist-get extras :cover_file) "nonexistent.jpg"))
            (should (seq-some (lambda (m) (string-match-p "cover.*missing" m)) warnings))))
      (delete-directory tmpdir t))))

(provide 'a3madkour-publish-library-test)

;;; a3madkour-publish-library-test.el ends here
