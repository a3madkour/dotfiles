;;; a3madkour-publish-library-test.el --- tests for library handler  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-library)
(require 'a3madkour-publish-async)

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
  "Per-medium config table has all 4 library sections with the right shape.
Keys are strings (the canonical `#+HUGO_SECTION:' slash-form)."
  (dolist (section '("library/reading" "library/listening" "library/playing" "library/watching"))
    (let ((cfg (a3madkour-pub-library--config-for section)))
      (should (= 4 (length cfg)))
      (should (stringp (nth 0 cfg)))           ; yaml filename
      (should (stringp (nth 1 cfg)))           ; default media_type
      (should (listp (nth 2 cfg)))             ; allowed media_types
      (should (listp (nth 3 cfg)))             ; allowed statuses
      (should (member (nth 1 cfg) (nth 2 cfg))))) ; default ∈ allowed
  (should-error (a3madkour-pub-library--config-for "bogus")))

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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/watching"))
         (row (a3madkour-pub-library--normalize-item src "library/watching" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/watching"))
         (row (a3madkour-pub-library--normalize-item src "library/watching" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (warnings '())
         (row (cl-letf (((symbol-function 'message)
                         (lambda (fmt &rest args)
                           (push (apply #'format fmt args) warnings))))
                (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org"))))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org")))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org")))
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
                 (cfg (a3madkour-pub-library--config-for "library/reading"))
                 (row (a3madkour-pub-library--normalize-item src "library/reading" cfg file)))
            (should (equal (plist-get row :last_modified) "2026-01-15"))))
      (delete-directory tmpdir t))))

(ert-deftest a3madkour-pub-library--normalize-last-modified-cascade-fallthrough ()
  "Bug 1.5: when drawer + git-mtime both absent, cascade falls through to
filesystem mtime / today instead of returning nil.  Pre-fix the library
handler used a 2-step `or' that returned nil → :last_modified omitted →
site linter rejected the row.  Post-fix the cascade always returns a
YYYY-MM-DD string."
  (let* ((tmpdir (make-temp-file "a3-pub-libcascade-" t))
         (file (expand-file-name "x.org" tmpdir)))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
                   ;; Simulate a file NOT tracked by git (no commits touch it).
                   (lambda (_) nil))
                  ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
                   (lambda (_) "2026-06-07")))
          (let* ((src (a3madkour-pub-library-test--parse-headline
                       "* Item
:PROPERTIES:
:CREATOR: x
:YEAR: 2024
:STATUS: queued
:END:
"))
                 (cfg (a3madkour-pub-library--config-for "library/reading"))
                 (row (a3madkour-pub-library--normalize-item src "library/reading" cfg file)))
            ;; Must be non-nil + the fs-mtime stub return.
            (should (equal (plist-get row :last_modified) "2026-06-07"))))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org"))
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
         (cfg (a3madkour-pub-library--config-for "library/playing"))
         (row (a3madkour-pub-library--normalize-item src "library/playing" cfg "/tmp/x.org"))
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
         (cfg (a3madkour-pub-library--config-for "library/watching"))
         (row (a3madkour-pub-library--normalize-item src "library/watching" cfg "/tmp/x.org"))
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
         (cfg (a3madkour-pub-library--config-for "library/listening"))
         (row (a3madkour-pub-library--normalize-item src "library/listening" cfg "/tmp/x.org"))
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
         (cfg (a3madkour-pub-library--config-for "library/reading"))
         (warnings '())
         ;; Stub: --site-static-dir-of returns a tmp dir with no cover file.
         (tmpdir (make-temp-file "a3-pub-covers-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-library--site-static-dir-of)
                   (lambda (file) (ignore file) tmpdir))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (push (apply #'format fmt args) warnings))))
          (let* ((row (a3madkour-pub-library--normalize-item src "library/reading" cfg "/tmp/x.org"))
                 (extras (plist-get row :extras)))
            (should (equal (plist-get extras :cover_file) "nonexistent.jpg"))
            (should (seq-some (lambda (m) (string-match-p "cover.*missing" m)) warnings))))
      (delete-directory tmpdir t))))

(ert-deftest a3madkour-pub-library--render-yaml-shape ()
  "Renders a yaml file PyYAML can parse, matching existing fixture shape."
  (let* ((rows (list (list :slug "abc"
                           :title "Abc Title"
                           :creator "Author A"
                           :year 2024
                           :media_type "book"
                           :status "reading"
                           :last_modified "2026-05-01"
                           :tags '("alpha" "beta"))
                     (list :slug "def"
                           :title "Def Title"
                           :creator "Author B"
                           :year 2023
                           :media_type "book"
                           :status "finished"
                           :last_modified "2026-04-15"
                           :finished "2026-04-14"
                           :tags '())))
         (out (a3madkour-pub-library--render-library-yaml
               rows "library-reading.org")))
    ;; Header comment present + items: top-level key.
    (should (string-match-p "# Generated by a3madkour-publish-library" out))
    (should (string-match-p "^items:" out))
    ;; Source-file-order (abc before def) and alphabetical within row.
    (let ((abc-pos (string-match-p "slug: abc" out))
          (def-pos (string-match-p "slug: def" out)))
      (should (and abc-pos def-pos (< abc-pos def-pos))))
    ;; Dates emitted unquoted (PyYAML loads as datetime.date).
    (should (string-match-p "last_modified: 2026-05-01" out))
    (should-not (string-match-p "last_modified: \"" out))
    ;; Tags inline array.
    (should (string-match-p "tags: \\[alpha, beta\\]" out))
    ;; Empty-tag row renders as empty inline array.
    (should (string-match-p "tags: \\[\\]" out))))

(ert-deftest a3madkour-pub-library--render-yaml-extras-nested ()
  "Extras render as a nested map."
  (let* ((rows (list (list :slug "x" :title "X" :creator "y" :year 2024
                           :media_type "game" :status "playing"
                           :last_modified "2026-05-01"
                           :tags '("puzzle")
                           :extras (list :igdb_id 12345
                                         :hours_played 22
                                         :platform "PC"))))
         (out (a3madkour-pub-library--render-library-yaml rows "library-playing.org")))
    (should (string-match-p "extras:" out))
    (should (string-match-p "  igdb_id: 12345" out))
    (should (string-match-p "  hours_played: 22" out))
    (should (string-match-p "  platform: PC" out))))

(ert-deftest a3madkour-pub-library--render-yaml-deterministic ()
  "Same input produces byte-identical output across calls."
  (let* ((rows (list (list :slug "x" :title "X" :creator "y" :year 2024
                           :media_type "book" :status "queued"
                           :last_modified "2026-05-01" :tags '("a")))))
    (should (string= (a3madkour-pub-library--render-library-yaml rows "x.org")
                     (a3madkour-pub-library--render-library-yaml rows "x.org")))))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-embedded-double-quote ()
  "Embedded double-quote in string with `:' or `#' → single-quoted yaml output."
  ;; `:#` branch
  (should (equal (a3madkour-pub-library--render-scalar "He said \"hello\": fine.")
                 "'He said \"hello\": fine.'"))
  ;; URL branch
  (should (equal (a3madkour-pub-library--render-scalar "http://example.com/path?q=\"foo\"")
                 "'http://example.com/path?q=\"foo\"'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-embedded-single-quote ()
  "Embedded `'' inside a single-quoted yaml scalar is doubled to `'''."
  ;; `:#` branch with single-quote
  (should (equal (a3madkour-pub-library--render-scalar "title: It's fine.")
                 "'title: It''s fine.'"))
  ;; URL branch with single-quote
  (should (equal (a3madkour-pub-library--render-scalar "http://example.com/it's/here")
                 "'http://example.com/it''s/here'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-leading-indicator ()
  "Strings starting with `\"' or `'' are single-quoted to avoid YAML indicator confusion."
  ;; Real-world example from the bug report: \"Hello,\" He Lied.
  (should (equal (a3madkour-pub-library--render-scalar "\"Hello,\" He Lied")
                 "'\"Hello,\" He Lied'"))
  ;; Leading single-quote (embedded `'' doubled).
  (should (equal (a3madkour-pub-library--render-scalar "'tis a title")
                 "'''tis a title'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-leading-bracket ()
  "Leading `[' triggers single-quoted yaml output (would corrupt as flow-seq otherwise)."
  (should (equal (a3madkour-pub-library--render-scalar "[Insert Title Here]")
                 "'[Insert Title Here]'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-leading-asterisk ()
  "Leading `*' triggers single-quoted yaml output (would break as alias otherwise)."
  (should (equal (a3madkour-pub-library--render-scalar "*Asterisk Author*")
                 "'*Asterisk Author*'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-leading-blockscalar ()
  "Leading `>' / `|' (block scalar indicators) trigger single-quoted output."
  (should (equal (a3madkour-pub-library--render-scalar "> Quoted Opening")
                 "'> Quoted Opening'"))
  (should (equal (a3madkour-pub-library--render-scalar "| Pipe Title")
                 "'| Pipe Title'")))

(ert-deftest a3madkour-pub-library--render-scalar-fallback-hashtable-single-quoted ()
  "Tier 4.4: the `%S' fallback wraps non-scalar values (hashtable, struct,
vector) in a YAML single-quoted scalar so the row remains parseable. Without
the wrapper the raw `%S' print form contains `#<...>' / `#s(...)' / `[...]'
sequences that PyYAML rejects."
  (let ((ht (make-hash-table :test 'equal)))
    (puthash "k" "v" ht)
    (let ((out (a3madkour-pub-library--render-scalar ht)))
      (should (string-prefix-p "'" out))
      (should (string-suffix-p "'" out)))))

(ert-deftest a3madkour-pub-library--render-scalar-fallback-vector-single-quoted ()
  "Tier 4.4: vector input falls through to the wrapped `%S' branch."
  (let ((out (a3madkour-pub-library--render-scalar [1 2 3])))
    (should (string-prefix-p "'" out))
    (should (string-suffix-p "'" out))
    ;; Single-quote-doubling rule still applies to any embedded `''.
    (should (string-match-p "1 2 3" out))))

(ert-deftest a3madkour-pub-library--publish-library-file-end-to-end ()
  "publish-library-file walks headings + writes data/<medium>.yaml."
  (let* ((notes-dir (make-temp-file "a3-pub-libnotes-" t))
         (site-dir  (make-temp-file "a3-pub-libsite-" t))
         (src       (expand-file-name "library-reading.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (with-temp-file src
            (insert "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: library/reading\n\n"
                    "* Pride and Prejudice :classics:romance:\n"
                    ":PROPERTIES:\n"
                    ":CREATOR: Jane Austen\n"
                    ":YEAR: 1813\n"
                    ":STATUS: finished\n"
                    ":FINISHED: 2024-12-15\n"
                    ":LAST_MODIFIED: 2024-12-16\n"
                    ":END:\n\n"
                    "* Lord Jim :classics:\n"
                    ":PROPERTIES:\n"
                    ":CREATOR: Joseph Conrad\n"
                    ":YEAR: 1900\n"
                    ":STATUS: reading\n"
                    ":LAST_MODIFIED: 2025-04-01\n"
                    ":END:\n"))
          (let ((a3madkour-pub/site-data-dir (expand-file-name "data/" site-dir)))
            (a3madkour-pub-library/publish-library-file
             src (make-a3-pub-async-run) :on-done (lambda (_) nil)))
          (let ((out (expand-file-name "data/reading.yaml" site-dir)))
            (should (file-exists-p out))
            (with-temp-buffer
              (insert-file-contents out)
              (should (string-match-p "slug: pride-and-prejudice" (buffer-string)))
              (should (string-match-p "slug: lord-jim" (buffer-string)))
              (should (string-match-p "title: Pride and Prejudice" (buffer-string)))
              (should (string-match-p "tags: \\[classics, romance\\]" (buffer-string)))
              ;; Source-file-order: P comes before L.
              (let ((p-pos (string-match-p "slug: pride-and-prejudice" (buffer-string)))
                    (l-pos (string-match-p "slug: lord-jim" (buffer-string))))
                (should (< p-pos l-pos))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(ert-deftest a3madkour-pub-library--publish-library-file-slug-collision ()
  "Slug collision within file → WARN, skip second occurrence."
  (let* ((notes-dir (make-temp-file "a3-pub-libnotes-" t))
         (site-dir  (make-temp-file "a3-pub-libsite-" t))
         (src       (expand-file-name "library-reading.org" notes-dir))
         (warnings '()))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (with-temp-file src
            (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: library/reading\n\n"
                    "* Same Title\n:PROPERTIES:\n:CREATOR: x\n:YEAR: 2024\n:STATUS: queued\n:END:\n"
                    "* Same Title\n:PROPERTIES:\n:CREATOR: y\n:YEAR: 2025\n:STATUS: queued\n:END:\n"))
          (cl-letf (((symbol-function 'message)
                     (lambda (fmt &rest args)
                       (push (apply #'format fmt args) warnings))))
            (let ((a3madkour-pub/site-data-dir (expand-file-name "data/" site-dir)))
              (a3madkour-pub-library/publish-library-file
               src (make-a3-pub-async-run) :on-done (lambda (_) nil))))
          ;; Yaml only has one row.
          (let* ((content (with-temp-buffer
                            (insert-file-contents (expand-file-name "data/reading.yaml" site-dir))
                            (buffer-string)))
                 (row-count (cl-count-if (lambda (line) (string-prefix-p "  - slug:" line))
                                         (split-string content "\n"))))
            (should (= 1 row-count))
            (should (seq-some (lambda (m) (string-match-p "slug collision" m)) warnings))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(ert-deftest a3madkour-pub-library--publish-library-file-idempotent ()
  "Second publish run on unchanged source → file mtime unchanged."
  (let* ((notes-dir (make-temp-file "a3-pub-libnotes-" t))
         (site-dir  (make-temp-file "a3-pub-libsite-" t))
         (src       (expand-file-name "library-reading.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (with-temp-file src
            (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: library/reading\n\n"
                    "* Item\n:PROPERTIES:\n:CREATOR: x\n:YEAR: 2024\n:STATUS: queued\n"
                    ":LAST_MODIFIED: 2025-01-01\n:END:\n"))
          (let ((a3madkour-pub/site-data-dir (expand-file-name "data/" site-dir)))
            (a3madkour-pub-library/publish-library-file
             src (make-a3-pub-async-run) :on-done (lambda (_) nil))
            (let* ((out (expand-file-name "data/reading.yaml" site-dir))
                   (mtime1 (file-attribute-modification-time
                            (file-attributes out))))
              (sleep-for 1.1)
              (a3madkour-pub-library/publish-library-file
               src (make-a3-pub-async-run) :on-done (lambda (_) nil))
              (let ((mtime2 (file-attribute-modification-time
                             (file-attributes out))))
                (should (equal mtime1 mtime2))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

;;; -- Task 15: handler async signature --

(ert-deftest a3madkour-pub-library-test/handler-async-signature ()
  "publish-library-file accepts (file run &key on-done) and calls on-done."
  (let (done-status)
    (with-a3-pub-async-sync
     (condition-case _
         (a3madkour-pub-library/publish-library-file
          "/tmp/fake.org" (make-a3-pub-async-run)
          :on-done (lambda (s) (setq done-status s)))
       (error (setq done-status 'err))))
    (should (memq done-status '(ok err)))))

(ert-deftest a3madkour-pub-library-test/handler-async-error-routes-on-done-err ()
  "When the sync pipeline throws, on-done fires with 'err."
  (let (done-status)
    (cl-letf (((symbol-function 'a3madkour-pub/note-section)
               (lambda (_) (error "boom"))))
      (with-a3-pub-async-sync
       (a3madkour-pub-library/publish-library-file
        "/tmp/fake.org" (make-a3-pub-async-run)
        :on-done (lambda (s) (setq done-status s)))))
    (should (eq done-status 'err))))

(provide 'a3madkour-publish-library-test)

;;; a3madkour-publish-library-test.el ends here
