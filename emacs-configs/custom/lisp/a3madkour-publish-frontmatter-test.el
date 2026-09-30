;;; a3madkour-publish-frontmatter-test.el --- tests for -frontmatter.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the per-section frontmatter normalizer dispatch.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-frontmatter)
;; `a3madkour-works-vocab-test--with-root' / `--json': the one vocabulary
;; fixture, shared with the works lint + handler test files.  The works
;; normalizer reads its allowed-key contract from that file, so every
;; works normalize call below needs a site root that carries one.
(require 'a3madkour-works-vocab-fixture)

(ert-deftest a3madkour-pub-fm-test/normalize-returns-alist-with-section ()
  "B.0 — `normalize' returns the input alist annotated with section symbol.
Per-section transforms land in B.1+; B.0 ships pass-through behavior."
  (let* ((raw '((title . "Hello") (tags . ("a" "b"))))
         (result (a3madkour-pub-frontmatter/normalize 'garden raw "/tmp/foo.org")))
    (should (listp result))
    (should (equal "Hello" (alist-get 'title result)))
    (should (equal '("a" "b") (alist-get 'tags result)))))

(ert-deftest a3madkour-pub-fm-test/normalize-accepts-all-known-sections ()
  "B.0 — `normalize' dispatches without error for every section enum value.

Wrapped in the vocabulary fixture because works-games / works-music read
their allowed-key contract from `data/works-vocab.json' and fail closed
without it."
  (a3madkour-works-vocab-test--with-root a3madkour-works-vocab-test--json
    (dolist (section '(garden essays research-themes research-questions
                       works-games works-music works-poetry
                       streams about
                       library-reading library-listening
                       library-playing library-watching))
      (should (a3madkour-pub-frontmatter/normalize section '((title . "X")) "/tmp/x.org")))))

(ert-deftest a3madkour-pub-fm-test/normalize-errors-on-unknown-section ()
  "B.0 — `normalize' signals an error for unknown section symbol."
  (should-error (a3madkour-pub-frontmatter/normalize 'made-up-section '() "/tmp/x.org")))

(ert-deftest a3madkour-pub-frontmatter--dispatch-routes-by-section ()
  "normalize dispatches to per-section logic; unknown sections still error."
  (should-error
   (a3madkour-pub-frontmatter/normalize 'bogus '((title . "x")) "/tmp/x.org"))
  ;; B.4 adds the real essays normalizer; verify it returns an alist with title.
  (let ((out (a3madkour-pub-frontmatter/normalize 'essays
                                                   '((title . "Hi"))
                                                   "/tmp/x.org")))
    (should (listp out))
    (should (equal (alist-get 'title out) "Hi"))))

(ert-deftest a3madkour-pub-frontmatter--growth-stage-from-progress ()
  "PROGRESS property maps to growth_stage per spec §7."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (progn
          ;; none / unset
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "seedling"))
          ;; highlighting → seedling
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :PROGRESS: highlighting\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "seedling"))
          ;; ref-notes → budding
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :PROGRESS: ref-notes\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "budding"))
          ;; main-notes → evergreen
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :PROGRESS: main-notes\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "evergreen"))
          ;; done → evergreen
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :PROGRESS: done\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "evergreen")))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--growth-stage-keyword-override ()
  "HUGO_GROWTH_STAGE keyword overrides PROGRESS derivation."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "#+HUGO_GROWTH_STAGE: budding\n"
                    "* Note\n  :PROPERTIES:\n  :PROGRESS: done\n  :END:\n"))
          ;; ox-hugo would have parsed HUGO_GROWTH_STAGE into the alist.
          ;; We simulate that here by pre-populating raw-alist.
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden
                                     '((growth_stage . "budding"))
                                     src))
                         "budding")))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--garden-flavor-inference ()
  "media_type passes through; flavor is NOT emitted to frontmatter.
The linter derives flavor internally from media_type, so emitting
flavor: to the YAML frontmatter is forbidden (check_garden_fixtures.py
rejects it on concept notes).  The --infer-flavor helper stays pure
and available for internal use, but the normalizer must suppress the
flavor key from the output alist."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (let ((cases '(nil "book" "album" "track" "game" "film" "series"
                       "paper" "video" "article" "talk")))
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :END:\n"))
          (dolist (mt cases)
            (let* ((raw (if mt `((media_type . ,mt)) '()))
                   (out (a3madkour-pub-frontmatter/normalize 'garden raw src)))
              ;; media_type passes through when present.
              (when mt
                (should (equal (alist-get 'media_type out) mt)))
              ;; flavor must NOT appear in output.
              (should-not (assq 'flavor out)))))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--garden-author-stripped ()
  "author key is stripped from output; creator is kept if both present.
ox-hugo may emit `author' from #+author: or :AUTHOR: properties, but
check_garden_fixtures.py's CONCEPT_FIELDS does not include `author'.
The normalizer must drop it silently."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :END:\n"))
          ;; author alone → stripped.
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'garden '((author . "Someone")) src)))
            (should-not (assq 'author out)))
          ;; creator alone → kept.
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'garden '((creator . "Jane Austen")) src)))
            (should (equal (alist-get 'creator out) "Jane Austen")))
          ;; both author + creator → creator survives, author dropped.
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'garden '((author . "Wrong") (creator . "Right")) src)))
            (should-not (assq 'author out))
            (should (equal (alist-get 'creator out) "Right"))))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--garden-last-modified-derived ()
  "last_modified is derived from file mtime when absent from raw-alist.
If raw-alist already has last_modified (e.g. from #+HUGO_LASTMOD:), that
value is honored unchanged."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :END:\n"))
          ;; Not in raw-alist → derived from mtime (format YYYY-MM-DD).
          (let* ((out (a3madkour-pub-frontmatter/normalize 'garden '() src))
                 (lm  (alist-get 'last_modified out)))
            (should (stringp lm))
            (should (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$" lm)))
          ;; Already in raw-alist → honored, not overridden.
          (let* ((out (a3madkour-pub-frontmatter/normalize
                       'garden '((last_modified . "2025-01-15")) src))
                 (lm  (alist-get 'last_modified out)))
            (should (equal lm "2025-01-15"))))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--garden-lastmod-renamed-to-last-modified ()
  "ox-hugo emits `#+HUGO_LASTMOD:' as `lastmod:' but the linter only accepts
`last_modified:'. The normalizer renames lastmod → last_modified and strips
the original key. ox-hugo's ISO-datetime form is truncated to YYYY-MM-DD."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :END:\n"))
          ;; ox-hugo ISO datetime form → YYYY-MM-DD prefix.
          (let* ((out (a3madkour-pub-frontmatter/normalize
                       'garden
                       '((lastmod . "2024-12-18T00:00:00-08:00"))
                       src)))
            (should-not (assq 'lastmod out))
            (should (equal (alist-get 'last_modified out) "2024-12-18")))
          ;; lastmod that is already plain YYYY-MM-DD passes through unchanged.
          (let* ((out (a3madkour-pub-frontmatter/normalize
                       'garden '((lastmod . "2024-12-18")) src)))
            (should-not (assq 'lastmod out))
            (should (equal (alist-get 'last_modified out) "2024-12-18")))
          ;; If both lastmod AND last_modified are present, last_modified wins
          ;; (explicit override) and lastmod is dropped.
          (let* ((out (a3madkour-pub-frontmatter/normalize
                       'garden
                       '((lastmod . "2024-12-18T00:00:00Z")
                         (last_modified . "2025-06-01"))
                       src)))
            (should-not (assq 'lastmod out))
            (should (equal (alist-get 'last_modified out) "2025-06-01"))))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--garden-topic-map-list ()
  "topic_map: list pass-through; string split on whitespace; missing → no key emitted."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :END:\n"))
          ;; List form pass-through.
          (should (equal (alist-get 'topic_map
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '((topic_map . ("a" "b" "c"))) src))
                         '("a" "b" "c")))
          ;; String form split on whitespace.
          (should (equal (alist-get 'topic_map
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '((topic_map . "a b c")) src))
                         '("a" "b" "c")))
          ;; Missing → not emitted at all.
          (should-not (assq 'topic_map
                            (a3madkour-pub-frontmatter/normalize
                             'garden '() src))))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--garden-passthrough-keywords ()
  "Per-keyword string fields pass through; year and weight coerce string→int."
  (let* ((src (make-temp-file "garden-" nil ".org"))
         (raw '((creator       . "Jane Austen")
                (status        . "finished")
                (started       . "2024-11-02")
                (finished      . "2024-12-15")
                (spoiler_level . "mild")
                (original_url  . "https://example.com/post")
                (year          . "1813")
                (weight        . "5"))))
    (unwind-protect
        (progn
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :END:\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize 'garden raw src)))
            (should (equal (alist-get 'creator out) "Jane Austen"))
            (should (equal (alist-get 'status out) "finished"))
            (should (equal (alist-get 'started out) "2024-11-02"))
            (should (equal (alist-get 'finished out) "2024-12-15"))
            (should (equal (alist-get 'spoiler_level out) "mild"))
            (should (equal (alist-get 'original_url out) "https://example.com/post"))
            (should (eq (alist-get 'year out) 1813))
            (should (eq (alist-get 'weight out) 5))))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--filter-editorial-tags-defaults ()
  "Editorial tags TODO/DONE/WAIT/CANCELED/HOLD/NOEXPORT/ATTACH stripped by default."
  (should (equal (a3madkour-pub-frontmatter/filter-editorial-tags
                  '("alpha" "TODO" "beta" "NOEXPORT" "gamma"))
                 '("alpha" "beta" "gamma")))
  (should (equal (a3madkour-pub-frontmatter/filter-editorial-tags
                  '("TODO" "DONE" "WAIT" "CANCELED" "HOLD" "NOEXPORT" "ATTACH"))
                 nil))
  (should (equal (a3madkour-pub-frontmatter/filter-editorial-tags '()) nil))
  (should (equal (a3madkour-pub-frontmatter/filter-editorial-tags '("clean"))
                 '("clean"))))

(ert-deftest a3madkour-pub-frontmatter--filter-editorial-tags-extra-exclusions ()
  "Per-call extra-exclusions list merges with the defcustom defaults."
  (should (equal (a3madkour-pub-frontmatter/filter-editorial-tags
                  '("alpha" "DRAFT" "beta" "TODO")
                  '("DRAFT"))
                 '("alpha" "beta"))))

(ert-deftest a3madkour-pub-frontmatter--garden-tags-strip-editorial ()
  "Garden normalizer applies the editorial-tag filter (closes B.1.1 #6)."
  (let* ((raw '((title . "Note")
                (tags  . ("Bayesian" "TODO" "stats"))))
         (out (a3madkour-pub-frontmatter/normalize 'garden raw "/tmp/x.org")))
    (should (equal (alist-get 'tags out) '("Bayesian" "stats")))))

(ert-deftest a3madkour-pub-frontmatter--garden-strips-slug ()
  "Bug 1.6: garden normalizer drops `slug' before emitting frontmatter.
ox-hugo emits `slug:' from `:CUSTOM_ID:' / `#+HUGO_SLUG:' / title-derivation,
but `tools/check_garden_fixtures.py' CONCEPT_FIELDS allowlist forbids it
on every garden flavor (concept / media / reference) — the URL comes
from the bundle directory name in B's `publish-garden-file' path, so
emitting `slug:' is both redundant and a CI-fail trigger on every
ref-note→garden promotion (see `project_b_slug_on_concept_followup.md').

Mirror the existing `flavor' / `author' strip pattern in --normalize-garden."
  (let* ((raw '((title . "Note")
                (slug  . "incoming-from-ox-hugo")
                (tags  . ("clean"))))
         (out (a3madkour-pub-frontmatter/normalize 'garden raw "/tmp/x.org")))
    (should (null (assq 'slug out)))
    ;; Companion keys still pass through.
    (should (equal (alist-get 'title out) "Note"))
    (should (equal (alist-get 'tags out) '("clean")))))

(ert-deftest a3madkour-pub-frontmatter--last-modified-cascade-drawer-wins ()
  ":LAST_MODIFIED: drawer beats keyword + git-mtime + fs-mtime."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2024-01-01"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2025-01-01")))
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade
                    "/tmp/x.org" :drawer "2026-05-30" :keyword "2026-05-29")
                   "2026-05-30"))))

(ert-deftest a3madkour-pub-frontmatter--last-modified-cascade-keyword-second ()
  "#+HUGO_LASTMOD: keyword wins when drawer absent."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2024-01-01"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2025-01-01")))
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade
                    "/tmp/x.org" :keyword "2026-05-29")
                   "2026-05-29"))))

(ert-deftest a3madkour-pub-frontmatter--last-modified-cascade-git-third ()
  "git-mtime wins when drawer + keyword absent."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2024-01-01"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2025-01-01")))
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade "/tmp/x.org")
                   "2024-01-01"))))

(ert-deftest a3madkour-pub-frontmatter--last-modified-cascade-fs-fourth ()
  "fs-mtime wins when drawer + keyword + git absent."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) nil))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2025-01-01")))
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade "/tmp/x.org")
                   "2025-01-01"))))

(ert-deftest a3madkour-pub-frontmatter--last-modified-cascade-prior-recorded-beats-fs ()
  "P2.14: a prior-recorded last_modified is preferred over the filesystem
mtime, so a never-committed note republished before its first commit keeps a
STABLE date instead of churning to today every run (defeating idempotence).
git-mtime still wins over it (committed history is authoritative)."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) nil))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2099-12-31")))
    ;; prior-recorded beats the churning fs mtime.
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade
                    "/tmp/x.org" :prior-recorded "2026-01-01")
                   "2026-01-01")))
  ;; ...but a real git-mtime still outranks the prior-recorded value.
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2027-05-05"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2099-12-31")))
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade
                    "/tmp/x.org" :prior-recorded "2026-01-01")
                   "2027-05-05"))))

(ert-deftest a3madkour-pub-frontmatter--last-modified-cascade-today-fallback ()
  "today is the ultimate fallback when nothing else resolves."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) nil))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) nil)))
    (let ((result (a3madkour-pub-frontmatter/last-modified-cascade "/tmp/x.org"))
          (today (format-time-string "%Y-%m-%d")))
      (should (equal result today)))))

(ert-deftest a3madkour-pub-frontmatter--last-modified-cascade-empty-strings-fallthrough ()
  "Empty-string drawer and keyword values fall through to git/fs/today fallbacks."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2024-01-01"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2025-01-01")))
    ;; Empty drawer + non-empty keyword → keyword.
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade
                    "/tmp/x.org" :drawer "" :keyword "2026-05-29")
                   "2026-05-29"))
    ;; Empty drawer + empty keyword → git.
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade
                    "/tmp/x.org" :drawer "" :keyword "")
                   "2024-01-01"))
    ;; Both nil → git (preserves Step 6 behavior).
    (should (equal (a3madkour-pub-frontmatter/last-modified-cascade "/tmp/x.org")
                   "2024-01-01"))))

(ert-deftest a3madkour-pub-frontmatter--hugo-description-keyword ()
  "#+HUGO_DESCRIPTION: keyword is read from source file and injected into alist as 'description.
When #+HUGO_DESCRIPTION: is present it wins over any pre-existing description in
the raw alist (e.g. from #+DESCRIPTION: via ox-hugo).  When absent, the raw
alist value (if any) passes through unchanged."
  (let ((src (make-temp-file "fm-desc-" nil ".org")))
    (unwind-protect
        (progn
          ;; Present: injected into alist.
          (with-temp-file src
            (insert "#+title: Theme One\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: research-themes\n"
                    "#+HUGO_DESCRIPTION: A short description of the theme.\n"))
          (should (equal (alist-get 'description
                                    (a3madkour-pub-frontmatter--inject-description
                                     '() src))
                         "A short description of the theme."))
          ;; Overrides existing description in raw alist.
          (should (equal (alist-get 'description
                                    (a3madkour-pub-frontmatter--inject-description
                                     '((description . "old value")) src))
                         "A short description of the theme."))
          ;; Absent: raw alist value passes through.
          (with-temp-file src
            (insert "#+title: Theme One\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: research-themes\n"))
          (should (equal (alist-get 'description
                                    (a3madkour-pub-frontmatter--inject-description
                                     '((description . "from-ox-hugo")) src))
                         "from-ox-hugo"))
          ;; Absent + nothing in raw alist: description key not added.
          (let ((out (a3madkour-pub-frontmatter--inject-description '() src)))
            (should (null (alist-get 'description out)))))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--research-normalize-common-shape ()
  "Common-field normalize covers title/draft/last_modified/tags/description/summary/source_stream."
  (let* ((raw '((title . "Theme One")
                (draft . nil)
                (lastmod . "2026-05-30")
                (tags . ("alpha" "TODO" "beta"))
                (description . "A short description.")
                (summary . "An umbrella thread.")
                (source_stream . "2026-04-10-example-stream")))
         (out (a3madkour-pub-frontmatter/research-normalize-common
               raw "/tmp/x.org")))
    (should (equal (alist-get 'title out) "Theme One"))
    (should (equal (alist-get 'last_modified out) "2026-05-30"))
    (should (equal (alist-get 'tags out) '("alpha" "beta")))   ; TODO filtered
    (should (equal (alist-get 'description out) "A short description."))
    (should (equal (alist-get 'summary out) "An umbrella thread."))
    (should (equal (alist-get 'source_stream out) "2026-04-10-example-stream"))))

(ert-deftest a3madkour-pub-frontmatter--research-normalize-common-defaults ()
  "Missing optional keys are not emitted; required keys derive from cascade."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-01-15"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-01-15")))
    (let* ((raw '((title . "Q1")))
           (out (a3madkour-pub-frontmatter/research-normalize-common
                 raw "/tmp/x.org")))
      (should (equal (alist-get 'title out) "Q1"))
      (should (equal (alist-get 'last_modified out) "2026-01-15"))
      (should-not (assq 'summary out))
      (should-not (assq 'source_stream out))
      (should-not (assq 'description out)))))

(ert-deftest a3madkour-pub-frontmatter--research-normalize-common-tags-all-editorial-dropped ()
  "When every tag is editorial, the filtered result is empty and the tags key is dropped."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "T") (tags . ("TODO" "NOEXPORT"))))
           (out (a3madkour-pub-frontmatter/research-normalize-common
                 raw "/tmp/x.org")))
      (should-not (assq 'tags out)))))

(ert-deftest a3madkour-pub-frontmatter--research-theme-required-fields ()
  "Theme required fields land in the output alist."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "Memory and play")
                  (description . "How readers assemble fragments.")
                  (status . "active")
                  (weight . "10")
                  (garden_topic_ref . "memory-in-play")
                  (tags . ("memory" "play"))))
           (out (a3madkour-pub-frontmatter/normalize 'research-themes raw "/tmp/x.org")))
      (should (equal (alist-get 'title out) "Memory and play"))
      (should (equal (alist-get 'status out) "active"))
      (should (equal (alist-get 'weight out) 10))     ; coerced int
      (should (equal (alist-get 'garden_topic_ref out) "memory-in-play")))))

(ert-deftest a3madkour-pub-frontmatter--research-theme-weight-octal-safe ()
  "weight string parsing is octal-safe (per [[hugo-int-octal-gotcha]])."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "Z") (description . "x") (status . "active")
                  (weight . "08")))
           (out (a3madkour-pub-frontmatter/normalize 'research-themes raw "/tmp/x.org")))
      ;; "08" must NOT octal-trap into a parse error; expect int 8.
      (should (equal (alist-get 'weight out) 8)))))

(ert-deftest a3madkour-pub-frontmatter--research-theme-forbidden-fields-dropped ()
  "parent_question + theme silently dropped on themes (linter is the gate)."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "T")
                  (description . "x")
                  (status . "active")
                  (parent_question . "qslug")
                  (theme . "other-theme")))
           (out (a3madkour-pub-frontmatter/normalize 'research-themes raw "/tmp/x.org")))
      (should-not (assq 'parent_question out))
      (should-not (assq 'theme out)))))

(ert-deftest a3madkour-pub-frontmatter--research-theme-status-enum-warn ()
  "Out-of-enum status WARNs but still emits."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "T") (description . "x") (status . "bogus")))
           (warnings '())
           (out (cl-letf (((symbol-function 'message)
                           (lambda (fmt &rest args)
                             (push (apply #'format fmt args) warnings))))
                  (a3madkour-pub-frontmatter/normalize 'research-themes raw "/tmp/x.org"))))
      (should (equal (alist-get 'status out) "bogus"))
      (should (seq-some (lambda (m) (string-match-p "status.*bogus.*not in" m)) warnings)))))

(ert-deftest a3madkour-pub-frontmatter--research-theme-weight-non-numeric-dropped ()
  "Non-numeric weight WARNs and the weight key is dropped (not emitted as nil)."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "T") (description . "x") (status . "active")
                  (weight . "not-a-number")))
           (warnings '())
           (out (cl-letf (((symbol-function 'message)
                           (lambda (fmt &rest args)
                             (push (apply #'format fmt args) warnings))))
                  (a3madkour-pub-frontmatter/normalize 'research-themes raw "/tmp/x.org"))))
      (should-not (assq 'weight out))
      (should (seq-some (lambda (m) (string-match-p "weight.*non-numeric" m)) warnings)))))

(ert-deftest a3madkour-pub-frontmatter--research-question-required-fields ()
  "Question required fields + slug-list parsing."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "What is a narrative atom?")
                  (description . "Active question.")
                  (theme . "procedural-narrative")
                  (status . "active")
                  (supporting_notes . "story-atoms recall-vs-replay")
                  (related_essays . "example-essay-two")
                  (tags . ("narrative"))))
           (out (a3madkour-pub-frontmatter/normalize 'research-questions raw "/tmp/x.org")))
      (should (equal (alist-get 'theme out) "procedural-narrative"))
      (should (equal (alist-get 'status out) "active"))
      (should (equal (alist-get 'supporting_notes out)
                     '("story-atoms" "recall-vs-replay")))
      (should (equal (alist-get 'related_essays out)
                     '("example-essay-two"))))))

(ert-deftest a3madkour-pub-frontmatter--research-question-optional-passthroughs ()
  "Optional question fields pass through; absent → omitted."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "Q") (description . "x") (theme . "t") (status . "active")
                  (parent_question . "qparent")
                  (started . "2025-09-01")
                  (weight . "20")))
           (out (a3madkour-pub-frontmatter/normalize 'research-questions raw "/tmp/x.org")))
      (should (equal (alist-get 'parent_question out) "qparent"))
      (should (equal (alist-get 'started out) "2025-09-01"))
      (should (equal (alist-get 'weight out) 20)))))

(ert-deftest a3madkour-pub-frontmatter--research-question-slug-list-empty ()
  "Empty supporting_notes / related_essays → key omitted, not emitted as [\"\"]."
  (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
             (lambda (_) "2026-05-30"))
            ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
             (lambda (_) "2026-05-30")))
    (let* ((raw '((title . "Q") (description . "x") (theme . "t") (status . "active")
                  (supporting_notes . "")))
           (out (a3madkour-pub-frontmatter/normalize 'research-questions raw "/tmp/x.org")))
      (should-not (assq 'supporting_notes out)))))

;; -- B.4 Task 3: essays normalizer skeleton --

(ert-deftest a3madkour-pub-frontmatter-test/essays-known-section ()
  "B.4 Task 3: dispatch accepts 'essays without erroring."
  (let ((tmp (make-temp-file "essays-norm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((result (a3madkour-pub-frontmatter/normalize
                         'essays
                         '((title . "x") (date . "2026-04-12"))
                         tmp)))
            (should (listp result))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-required-keys-present ()
  "B.4 Task 3: normalize emits all 14 required essay frontmatter keys."
  (let ((tmp (make-temp-file "essays-norm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let* ((raw '((title . "Test") (date . "2026-04-12") (summary . "S")
                        (tags . ("a"))))
                 (out (a3madkour-pub-frontmatter/normalize 'essays raw tmp))
                 (required '(title date lastmod draft summary tags series series_order
                             toc has_sidenotes has_citations has_footnotes has_math
                             has_widgets has_video_sync)))
            (dolist (k required)
              (should (assq k out)))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-draft-defaults-false ()
  "B.4 Task 3: absent draft → false."
  (let ((tmp (make-temp-file "essays-norm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays '((title . "x") (date . "2026-04-12")) tmp)))
            (should (eq (alist-get 'draft out) nil))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-draft-string-false-coerces-nil ()
  "P2.9: a string `draft: false' (e.g. via a #+HUGO_DRAFT: keyword path) must
coerce to nil, not silently flip to t under the naive `(and v ... t)' test."
  (let ((tmp (make-temp-file "essays-norm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays '((title . "x") (date . "2026-04-12") (draft . "false")) tmp)))
            (should (eq (alist-get 'draft out) nil))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-toc-string-false-coerces-nil ()
  "P2.9: a string `toc: false' must coerce to nil, not flip to t."
  (let ((tmp (make-temp-file "essays-norm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays '((title . "x") (date . "2026-04-12") (toc . "false")) tmp)))
            (should (eq (alist-get 'toc out) nil))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-series-order-keyword-negative-preserved ()
  "P2.11: an explicit #+HUGO_SERIES_ORDER of a non-positive value must be
preserved, not dropped by the old `(> coerced 0)' gate (which silently
reverted to the default 0)."
  (let ((tmp (make-temp-file "essays-norm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n#+HUGO_SERIES_ORDER: -1\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays '((title . "x") (date . "2026-04-12")) tmp)))
            (should (eq (alist-get 'series_order out) -1))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-toc-defaults-true ()
  "B.4 Task 3: absent toc → true."
  (let ((tmp (make-temp-file "essays-norm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays '((title . "x") (date . "2026-04-12")) tmp)))
            (should (eq (alist-get 'toc out) t))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-noise-keys-dropped ()
  "B.4 Task 3: ox-hugo noise keys NOT in the essay contract are dropped."
  (let ((tmp (make-temp-file "essays-norm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let* ((raw '((title . "x") (date . "2026-04-12") (author . "noise")
                        (slug . "noise")))
                 (out (a3madkour-pub-frontmatter/normalize 'essays raw tmp)))
            (should-not (assq 'author out))
            (should-not (assq 'slug out))))
      (delete-file tmp))))

;; -- B.4 Task 6: lastmod cascade in essays normalizer --

(ert-deftest a3madkour-pub-frontmatter-test/essays-lastmod-from-drawer ()
  "Tier 1: :LAST_MODIFIED: drawer wins."
  (let ((tmp (make-temp-file "essays-lm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays
                      '((title . "x") (date . "2026-04-12")
                        (last_modified . "2025-01-15"))
                      tmp)))
            (should (equal (alist-get 'lastmod out) "2025-01-15"))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-lastmod-from-keyword ()
  "Tier 2: HUGO_LASTMOD keyword (ISO datetime trimmed to date)."
  (let ((tmp (make-temp-file "essays-lm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays
                      '((title . "x") (date . "2026-04-12")
                        (lastmod . "2025-03-22T18:00:00+00:00"))
                      tmp)))
            (should (equal (alist-get 'lastmod out) "2025-03-22"))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-lastmod-from-fs-mtime ()
  "Tier 4: drawer + keyword absent + not a git repo → fs-mtime."
  (let ((tmp (make-temp-file "essays-lm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays
                      '((title . "x") (date . "2026-04-12"))
                      tmp)))
            ;; fs-mtime is today (we just created the temp file).
            (should (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
                                    (alist-get 'lastmod out)))))
      (delete-file tmp))))

;; -- B.4 Task 7: series defaults --

(ert-deftest a3madkour-pub-frontmatter-test/essays-series-defaults ()
  "Absent series → empty string; absent series_order → 0."
  (let ((tmp (make-temp-file "essays-ser-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays '((title . "x") (date . "2026-04-12")) tmp)))
            (should (equal (alist-get 'series out) ""))
            (should (equal (alist-get 'series_order out) 0))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-series-order-string-coerced ()
  "series_order from ox-hugo arrives as string '2' → coerce to int 2."
  (let ((tmp (make-temp-file "essays-ser-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays
                      '((title . "x") (date . "2026-04-12")
                        (series . "example-series") (series_order . "2"))
                      tmp)))
            (should (equal (alist-get 'series out) "example-series"))
            (should (eq (alist-get 'series_order out) 2))))
      (delete-file tmp))))

;; -- B.4 spot-check fix: Issue B + C --

(ert-deftest a3madkour-pub-frontmatter-test/essays-tags-empty-list-when-absent ()
  "Issue B: when raw-alist has no tags key, the normalizer should default tags
to an empty list marker so the YAML renders as `tags: []' — not `tags: false'.
The rendered frontmatter must contain `tags: []' (not `tags: false')."
  (let ((tmp (make-temp-file "essays-tags-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let* ((out (a3madkour-pub-frontmatter/normalize
                       'essays '((title . "x") (date . "2026-04-12")) tmp))
                 ;; The tags value must not be nil (which renders as false).
                 ;; It should be an empty list so the render path can emit [].
                 (tags-val (alist-get 'tags out)))
            ;; Key must be present.
            (should (assq 'tags out))
            ;; Value must NOT be nil (nil → "false" in YAML).
            ;; An empty list or vector sentinel both satisfy this.
            ;; We test the rendered output string to be definitive.
            (require 'a3madkour-publish-essays)
            (let ((rendered (a3madkour-pub-essays--render-frontmatter out)))
              (should (string-match-p "^tags: \\[\\]$" rendered))
              (should-not (string-match-p "^tags: false$" rendered)))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-series-list-coerced-to-string ()
  "Issue C-1: ox-hugo emits series as a single-element list (\"example-series\").
The normalizer must coerce it to the bare string \"example-series\"."
  (let ((tmp (make-temp-file "essays-ser-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: x\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays
                      '((title . "x") (date . "2026-04-12")
                        (series . ("example-series")))
                      tmp)))
            (should (stringp (alist-get 'series out)))
            (should (equal (alist-get 'series out) "example-series"))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter-test/essays-series-order-from-keyword ()
  "Issue C-2: #+HUGO_SERIES_ORDER: is not read by ox-hugo; the normalizer
must read it from the source file and coerce to int."
  (let ((tmp (make-temp-file "essays-ser-ord-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert ":PROPERTIES:\n:ID: e1\n:END:\n"
                    "#+title: x\n"
                    "#+HUGO_SERIES_ORDER: 3\n"))
          ;; raw-alist has no series_order (ox-hugo never emits it).
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'essays
                      '((title . "x") (date . "2026-04-12")
                        (series . "example-series"))
                      tmp)))
            (should (eq (alist-get 'series_order out) 3))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-frontmatter--normalize-recipes-standard-fields ()
  (let* ((f (make-temp-file "recipe-fm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f (insert "#+TITLE: X\n#+HUGO_SUMMARY: A tasty dish.\n#+DATE: 2026-07-09\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize
                      'recipes '((title . "X") (date . "2026-07-09") (draft . "true")) f)))
            (should (equal (alist-get 'summary out) "A tasty dish."))
            (should (eq (alist-get 'draft out) t))
            (should (assq 'tags out))
            (should (alist-get 'lastmod out))
            (should (equal (alist-get 'date out) "2026-07-09"))))
      (delete-file f))))

(ert-deftest a3madkour-pub-frontmatter--normalize-recipes-date-defaults-to-lastmod ()
  (let* ((f (make-temp-file "recipe-fm-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f (insert "#+TITLE: X\n#+HUGO_SUMMARY: y\n"))
          (let ((out (a3madkour-pub-frontmatter/normalize 'recipes '((title . "X")) f)))
            (should (equal (alist-get 'date out) (alist-get 'lastmod out)))))
      (delete-file f))))

;;; --- works/games + works/music -------------------------------------------
;;
;; Every normalize call below goes through the shared vocabulary, because the
;; emitted-field contract lives there (`data/works-vocab.json' in the site
;; repo) and no longer in an elisp defconst.  The macro supplies a site root
;; carrying the fixture, the way production supplies one.
;;
;; That is also why there is no longer a `-key-set-matches-contract' pair
;; here.  Those two tests compared an elisp defconst against an elisp test
;; constant — both copies of a Python set — so a key added on the Python side
;; left all three stale and green, and the normalizer then filtered the new
;; field out of every page silently.  What replaces them is
;; `--works-<type>-keeps-exactly-the-vocabulary-keys': the expectation is read
;; back out of the vocabulary FILE, so there is one thing to be right.

(defmacro a3madkour-pub-frontmatter-test--with-works-vocab (&rest body)
  "Run BODY with a temp site root carrying the shared vocabulary fixture."
  (declare (indent 0))
  `(a3madkour-works-vocab-test--with-root a3madkour-works-vocab-test--json
     ,@body))

(ert-deftest a3madkour-pub-frontmatter--works-games-comma-vs-whitespace ()
  "Review Focus: free-text lists split on comma, slug lists on whitespace."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-games
                '((title . "G") (year . "2026")
                  (collaborators . "Alice Example, Bob Example")
                  (tech_stack . "Godot, GDScript")
                  (research_questions . "example-question-one example-question-two"))
                "/tmp/g.org")))
      (should (equal (alist-get 'collaborators out) '("Alice Example" "Bob Example")))
      (should (equal (alist-get 'tech_stack out) '("Godot" "GDScript")))
      (should (equal (alist-get 'research_questions out)
                     '("/research/questions/example-question-one/"
                       "/research/questions/example-question-two/")))
      (should (equal (alist-get 'year out) 2026)))))

(ert-deftest a3madkour-pub-frontmatter--works-music-bool-coercion ()
  "hero and featured must emit real booleans, not strings."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-music
                '((title . "M") (year . "2026") (format . "album")
                  (hero . "t") (featured . "t"))
                "/tmp/m.org")))
      (should (eq (alist-get 'hero out) t))
      (should (eq (alist-get 'featured out) t)))))

;; Review Focus #1 — every optional absent must produce no keys at all.
(ert-deftest a3madkour-pub-frontmatter--works-games-minimal-emits-no-empty-keys ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-games
                '((title . "G") (year . "2026") (status . "playable")
                  (game_kind . "jam") (tagline . "T"))
                "/tmp/g.org")))
      (dolist (k '(screenshots collaborators tech_stack hero featured
                   research_questions related_essays related_notes summary))
        (should-not (assq k out))))))

;; Review Focus #1, present-but-false variant: `--coerce-bool' maps a false
;; VALUE to nil the same way it maps an absent key to nil, so a naive
;; `(setf (alist-get k out) (coerce-bool v))' would leave `(k . nil)' in the
;; alist when the author explicitly wrote "false" — a leaked empty key that
;; `works-games-minimal-emits-no-empty-keys' (whose input omits the keys
;; entirely) cannot catch.
(ert-deftest a3madkour-pub-frontmatter--works-music-false-bool-deletes-key ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-music
                '((title . "M") (year . "2026") (format . "album")
                  (hero . "false") (featured . "nil"))
                "/tmp/m.org")))
      (should-not (assq 'hero out))
      (should-not (assq 'featured out)))))

(ert-deftest a3madkour-pub-frontmatter--works-games-false-featured-deletes-key ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-games
                '((title . "G") (year . "2026") (featured . "false"))
                "/tmp/g.org")))
      (should-not (assq 'featured out)))))

(ert-deftest a3madkour-pub-frontmatter--works-screenshots-stay-filenames ()
  "screenshots split on whitespace but are NOT expanded to site paths."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-games
                '((title . "G") (year . "2026") (screenshots . "a.png b.png"))
                "/tmp/g.org")))
      (should (equal (alist-get 'screenshots out) '("a.png" "b.png"))))))


;;; Defect 3 (task-12 E2E) — the works normalizer never resolved `lastmod'.
;;
;; `check_works_fixtures.py' lists it in GAME_REQUIRED and MUSIC_REQUIRED, and
;; nothing in the works authoring surface sets `#+HUGO_LASTMOD:', so the key was
;; absent from every real publish and the site linter failed all of them.

(ert-deftest a3madkour-pub-frontmatter--works-games-emits-lastmod ()
  "A games publish with no date input anywhere still emits a YYYY-MM-DD lastmod."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-games
                '((title . "G") (year . "2026") (status . "playable")
                  (game_kind . "jam") (tagline . "T"))
                "/tmp/a3-works-no-such-file.org")))
      (should (assq 'lastmod out))
      (should (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'"
                              (alist-get 'lastmod out))))))

(ert-deftest a3madkour-pub-frontmatter--works-music-emits-lastmod ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-music
                '((title . "M") (year . "2026") (format . "album"))
                "/tmp/a3-works-no-such-file.org")))
      (should (assq 'lastmod out))
      (should (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'"
                              (alist-get 'lastmod out))))))

(ert-deftest a3madkour-pub-frontmatter--works-lastmod-prefers-drawer ()
  "The cascade's top slot wins, so an explicit :LAST_MODIFIED: is honoured
and is not re-emitted under its own name (`last_modified' is not a works key)."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-games
                '((title . "G") (year . "2026") (last_modified . "2024-01-02"))
                "/tmp/a3-works-no-such-file.org")))
      (should (equal (alist-get 'lastmod out) "2024-01-02"))
      (should-not (assq 'last_modified out)))))

(ert-deftest a3madkour-pub-frontmatter--works-lastmod-honours-p2-14-prior ()
  "P2.14: with no drawer, keyword or git history, the handler-bound
manifest-recorded value beats the filesystem mtime, so a republish of a
never-committed works note does not churn its date to today."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let* ((f (make-temp-file "a3-works-p214-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file f (insert "#+TITLE: G\n"))
            ;; The temp file is not in any git repo, so git-mtime is nil and the
            ;; next live slot would be the fs mtime (= today).
            (let* ((a3madkour-pub-frontmatter--prior-last-modified "2023-04-05")
                   (out (a3madkour-pub-frontmatter/normalize
                         'works-music
                         '((title . "M") (year . "2026") (format . "album")) f)))
              (should (equal (alist-get 'lastmod out) "2023-04-05"))))
        (delete-file f)))))


;;; Defect 4 (task-12 E2E) — the works normalizers never filtered to an
;;; allowed-key set, so ox-hugo's own auto-emitted `author' and `slug' reached
;;; the page and `check_works_fixtures.py' rejected both as unknown fields on
;;; every real publish.  Garden and essays already stripped exactly these two.

(ert-deftest a3madkour-pub-frontmatter--works-games-strips-ox-hugo-noise ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-games
                '((title . "G") (year . "2026") (status . "playable")
                  (game_kind . "jam") (tagline . "T")
                  (author . ("Abdelrahman Madkour")) (slug . "a-game")
                  (export_file_name . "x") (aliases . ("/y/")))
                "/tmp/a3-works-no-such-file.org")))
      (should-not (assq 'author out))
      (should-not (assq 'slug out))
      ;; Not a closed list of two: anything outside the contract goes.
      (should-not (assq 'export_file_name out))
      (should-not (assq 'aliases out))
      ;; ...and the filter did not eat the real fields on its way past.
      (should (equal (alist-get 'status out) "playable")))))

(ert-deftest a3madkour-pub-frontmatter--works-music-strips-ox-hugo-noise ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-music
                '((title . "M") (year . "2026") (format . "album")
                  (author . ("Abdelrahman Madkour")) (slug . "a-release"))
                "/tmp/a3-works-no-such-file.org")))
      (should-not (assq 'author out))
      (should-not (assq 'slug out))
      (should (equal (alist-get 'format out) "album")))))

;; The other half of an allowed-key filter: it must not be over-tight.  A set
;; missing one legal field would silently drop author data with no linter
;; complaint anywhere, which is the harder failure to notice.
;;
;; The expected set is read back out of the vocabulary FILE, not written out
;; here.  A literal list would be the third copy of the contract, which is
;; exactly how the deleted `-key-set-matches-contract' tests managed to pin
;; nothing.  This is not circular: the assertion is that a fully-populated
;; input survives `normalize' with every key the FILE declares legal and
;; nothing else, so a normalizer that ignored the file (or hardcoded its own
;; set) fails as soon as the two differ.

(defun a3madkour-pub-frontmatter-test--emitted-key-names (out)
  (sort (mapcar (lambda (c) (symbol-name (car c))) out) #'string<))

(ert-deftest a3madkour-pub-frontmatter--works-games-keeps-exactly-the-vocabulary-keys ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let* ((input '((title . "G") (date . "2026-01-01") (draft . nil)
                    (status . "playable") (game_kind . "jam") (tagline . "T")
                    (year . "2026") (tags . ("a")) (summary . "S")
                    (hero . "hero.png") (embed_url . "https://e")
                    (source_url . "https://s") (itch_url . "https://i")
                    (collaborators . "Alice Example") (tech_stack . "Godot")
                    (length . "3 hours") (screenshots . "a.png b.png")
                    (research_questions . "q-one") (related_essays . "e-one")
                    (related_notes . "n-one") (source_stream . "2026-01-01-s")
                    (tile_size . "large") (featured . "t")))
           (out (a3madkour-pub-frontmatter/normalize
                 'works-games input "/tmp/a3-works-no-such-file.org")))
      (should (equal (a3madkour-pub-frontmatter-test--emitted-key-names out)
                     (sort (mapcar #'symbol-name
                                   (a3madkour-works-vocab/emitted-keys 'works-games))
                           #'string<))))))

(ert-deftest a3madkour-pub-frontmatter--works-music-keeps-exactly-the-vocabulary-keys ()
  "Same, minus `platform_embed', which is assembled rather than passed through
\(it has its own tests below) and so cannot be supplied in the input alist."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let* ((input '((title . "M") (date . "2026-01-01") (draft . nil)
                    (format . "album") (year . "2026") (tags . ("a"))
                    (summary . "S") (tagline . "T") (cover . "cover.png")
                    (duration . "13:19")
                    (tracks . (((title . "One") (duration . "3:14"))))
                    (audio_url . "https://a") (lyrics_poem . "a-poem")
                    (related_works . "w-one") (related_essays . "e-one")
                    (made_with . "Ableton Live") (collaborators . "Alice Example")
                    (source_stream . "2026-01-01-s")
                    (tile_size . "large") (featured . "t") (hero . "t")))
           (out (a3madkour-pub-frontmatter/normalize
                 'works-music input "/tmp/a3-works-no-such-file.org")))
      (should (equal (a3madkour-pub-frontmatter-test--emitted-key-names out)
                     (sort (mapcar #'symbol-name
                                   (remq 'platform_embed
                                         (a3madkour-works-vocab/emitted-keys
                                          'works-music)))
                           #'string<))))))

;; A key the vocabulary does not declare is filtered out, and a key it DOES
;; declare survives — asserted against a vocabulary the test mutates, so the
;; filter provably consults the file rather than a compiled-in list.
(ert-deftest a3madkour-pub-frontmatter--works-filter-follows-the-vocabulary ()
  (a3madkour-works-vocab-test--with-root
      (replace-regexp-in-string
       "\"length\"" "\"playtime\"" a3madkour-works-vocab-test--json)
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-games
                '((title . "G") (year . "2026")
                  (length . "3 hours") (playtime . "3 hours"))
                "/tmp/a3-works-no-such-file.org")))
      (should-not (assq 'length out))
      (should (equal (alist-get 'playtime out) "3 hours")))))

(ert-deftest a3madkour-pub-frontmatter--works-fails-closed-without-a-vocabulary ()
  "No vocabulary means no publish: emitting unfiltered frontmatter would put
ox-hugo's `author'/`slug' on the page and fail the site linter."
  (a3madkour-works-vocab-test--with-root nil
    (should-error (a3madkour-pub-frontmatter/normalize
                   'works-games '((title . "G")) "/tmp/g.org"))
    (should-error (a3madkour-pub-frontmatter/normalize
                   'works-music '((title . "M")) "/tmp/m.org"))))


;;; `#+HUGO_SUMMARY:' (final-review finding 1) — silently dropped for both
;;; sections.  `summary' is in both allowed key sets, but ox-hugo does not
;;; emit it from that keyword and nothing injected it, so the documented
;;; authoring path lost the works tile's pull-quote with no error anywhere.
;;; The real-export proof lives in `a3madkour-publish-works-test.el'; these
;;; two pin the normalizer unit.

(ert-deftest a3madkour-pub-frontmatter--works-games-injects-hugo-summary ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((f (make-temp-file "a3-works-summary-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file f
              (insert "#+TITLE: G\n#+HUGO_SUMMARY: A memory-palace roguelike.\n"))
            (let ((out (a3madkour-pub-frontmatter/normalize
                        'works-games '((title . "G") (year . "2026")) f)))
              (should (equal (alist-get 'summary out)
                             "A memory-palace roguelike."))))
        (delete-file f)))))

(ert-deftest a3madkour-pub-frontmatter--works-music-injects-hugo-summary ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((f (make-temp-file "a3-works-summary-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file f
              (insert "#+TITLE: M\n#+HUGO_SUMMARY: Forty-two minutes of drone.\n"))
            (let ((out (a3madkour-pub-frontmatter/normalize
                        'works-music
                        '((title . "M") (year . "2026") (format . "album")) f)))
              (should (equal (alist-get 'summary out)
                             "Forty-two minutes of drone."))))
        (delete-file f)))))

(ert-deftest a3madkour-pub-frontmatter--works-summary-absent-emits-no-key ()
  "`summary' is optional for works, unlike essays/recipes where the linter
requires the key — so an absent keyword must emit nothing, not `summary: \"\"'."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((f (make-temp-file "a3-works-summary-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file f (insert "#+TITLE: G\n"))
            (should-not (assq 'summary
                              (a3madkour-pub-frontmatter/normalize
                               'works-games '((title . "G") (year . "2026")) f))))
        (delete-file f)))))


;;; Defect 6 (task-12 E2E) — `platform_embed' could not be authored at all.
;;
;; `#+HUGO_CUSTOM_FRONT_MATTER:' round-trips custom values as flat scalars, so
;; the nested map arrived as a string, failed the render key-hook's `listp'
;; test, and was silently omitted from every page.  Authored now as two flat
;; keys and assembled here.

(ert-deftest a3madkour-pub-frontmatter--works-music-assembles-platform-embed ()
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-music
                '((title . "M") (year . "2026") (format . "album")
                  (platform_kind . "bandcamp")
                  (platform_url . "https://example.bandcamp.com/album/x"))
                "/tmp/a3-works-no-such-file.org")))
      (should (equal (alist-get 'platform_embed out)
                     '((kind . "bandcamp")
                       (url . "https://example.bandcamp.com/album/x"))))
      ;; A LIST, which is what the render key-hook tests for -- the string the
      ;; old authoring path produced is exactly what it rejected.
      (should (listp (alist-get 'platform_embed out)))
      ;; The two authoring keys are inputs, not emitted fields.
      (should-not (assq 'platform_kind out))
      (should-not (assq 'platform_url out)))))

(ert-deftest a3madkour-pub-frontmatter--works-music-platform-embed-needs-both ()
  "One half alone emits nothing -- a half-map fails the site linter."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (dolist (half '(((platform_kind . "bandcamp"))
                    ((platform_url . "https://example.com/x"))))
      (let ((out (a3madkour-pub-frontmatter/normalize
                  'works-music
                  (append '((title . "M") (year . "2026") (format . "album")) half)
                  "/tmp/a3-works-no-such-file.org")))
        (should-not (assq 'platform_embed out))))))

(ert-deftest a3madkour-pub-frontmatter--works-music-drops-flat-platform-embed ()
  "A directly-authored `platform_embed' arrives as a string and must not ship.

`platform_embed' IS in the allowed key set, so the filter alone lets the
string through; emitting it would render a quoted scalar where the linter
demands a dict."
  (a3madkour-pub-frontmatter-test--with-works-vocab
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-music
                '((title . "M") (year . "2026") (format . "album")
                  (platform_embed . "{ kind: bandcamp, url: \"https://x\" }"))
                "/tmp/a3-works-no-such-file.org")))
      (should-not (assq 'platform_embed out)))))

(provide 'a3madkour-publish-frontmatter-test)
;;; a3madkour-publish-frontmatter-test.el ends here
