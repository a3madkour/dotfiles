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
  (dolist (section '(garden essays research-theme research-question
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
  ;; Non-garden known sections still pass-through (B.1 only adds garden).
  (should (equal (a3madkour-pub-frontmatter/normalize 'essays
                                                       '((title . "Hi"))
                                                       "/tmp/x.org")
                 '((title . "Hi")))))

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

(provide 'a3madkour-publish-frontmatter-test)
;;; a3madkour-publish-frontmatter-test.el ends here
