;;; a3madkour-publish-frontmatter-test.el --- tests for -frontmatter.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the per-section frontmatter normalizer dispatch.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-frontmatter)

(ert-deftest a3madkour-pub-fm-test/normalize-returns-alist-with-section ()
  "B.0 — `normalize' returns the input alist annotated with section symbol.
Per-section transforms land in B.1+; B.0 ships pass-through behavior."
  (let* ((raw '((title . "Hello") (tags . ("a" "b"))))
         (result (a3madkour-pub-frontmatter/normalize 'garden raw "/tmp/foo.org")))
    (should (listp result))
    (should (equal "Hello" (alist-get 'title result)))
    (should (equal '("a" "b") (alist-get 'tags result)))))

(ert-deftest a3madkour-pub-fm-test/normalize-accepts-all-known-sections ()
  "B.0 — `normalize' dispatches without error for every section enum value."
  (dolist (section '(garden essays research-themes research-questions
                     works-games works-music works-poetry
                     streams about
                     library-reading library-listening
                     library-playing library-watching))
    (should (a3madkour-pub-frontmatter/normalize section '((title . "X")) "/tmp/x.org"))))

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

(provide 'a3madkour-publish-frontmatter-test)
;;; a3madkour-publish-frontmatter-test.el ends here
