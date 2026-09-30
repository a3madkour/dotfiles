;;; a3madkour-works-vocab-test.el --- tests for the shared works vocabulary reader  -*- lexical-binding: t; -*-

;;; Commentary:

;; The fixture these tests (and the works lint / frontmatter / handler tests)
;; run against lives in `a3madkour-works-vocab-fixture.el'.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-works-vocab)
(require 'a3madkour-works-vocab-fixture)

(ert-deftest a3madkour-works-vocab--reads-enum-lists ()
  (a3madkour-works-vocab-test--with-root a3madkour-works-vocab-test--json
    (should (member "playable" (a3madkour-works-vocab/list "game_statuses")))
    (should (member "bandcamp" (a3madkour-works-vocab/list "platform_kinds")))))

(ert-deftest a3madkour-works-vocab--fails-closed-when-missing ()
  (a3madkour-works-vocab-test--with-root nil
    (should-error (a3madkour-works-vocab/list "game_statuses"))))

(ert-deftest a3madkour-works-vocab--fails-closed-when-malformed ()
  (a3madkour-works-vocab-test--with-root "{ not json"
    (should-error (a3madkour-works-vocab/list "game_statuses"))))

(ert-deftest a3madkour-works-vocab--fails-closed-on-missing-field-key ()
  "A vocabulary carrying only the four enums is incomplete now, and must
signal rather than let the normalizer fall back to an unfiltered alist."
  (a3madkour-works-vocab-test--with-root
      "{\"game_statuses\":[\"playable\"],\"game_kinds\":[\"jam\"],\"music_formats\":[\"album\"],\"platform_kinds\":[\"bandcamp\"]}"
    (should-error (a3madkour-works-vocab/list "game_required"))
    (should-error (a3madkour-works-vocab/emitted-keys 'works-games))))

(ert-deftest a3madkour-works-vocab--rejects-unknown-key ()
  (a3madkour-works-vocab-test--with-root a3madkour-works-vocab-test--json
    (should-error (a3madkour-works-vocab/list "bogus_key"))))

(ert-deftest a3madkour-works-vocab--emitted-keys-compose-three-lists ()
  "The per-type union is required + optional + umbrella, all from the file."
  (a3madkour-works-vocab-test--with-root a3madkour-works-vocab-test--json
    (dolist (spec '((works-games . "game") (works-music . "music")))
      (let ((got (sort (mapcar #'symbol-name
                               (a3madkour-works-vocab/emitted-keys (car spec)))
                       #'string<))
            ;; `copy-sequence' on the last list: `append' SHARES its final
            ;; argument, and `sort' is destructive, so sorting here would
            ;; reorder the cached `umbrella_optional' list in place and break
            ;; the next loop iteration.
            (want (sort (append
                         (a3madkour-works-vocab/list
                          (format "%s_required" (cdr spec)))
                         (a3madkour-works-vocab/list
                          (format "%s_optional" (cdr spec)))
                         (copy-sequence
                          (a3madkour-works-vocab/list "umbrella_optional")))
                        #'string<)))
        (should (equal got want))
        ;; Not vacuous: the umbrella list really is folded in, and the two
        ;; types really do differ.
        (should (member "hero" got))
        (should (member "tile_size" got))))
    (should (member 'status (a3madkour-works-vocab/emitted-keys 'works-games)))
    (should-not (member 'status (a3madkour-works-vocab/emitted-keys 'works-music)))
    (should (member 'format (a3madkour-works-vocab/emitted-keys 'works-music)))
    (should-not (member 'format (a3madkour-works-vocab/emitted-keys 'works-games)))))

(ert-deftest a3madkour-works-vocab--emitted-keys-rejects-other-sections ()
  (a3madkour-works-vocab-test--with-root a3madkour-works-vocab-test--json
    (should-error (a3madkour-works-vocab/emitted-keys 'works-poetry))))

(ert-deftest a3madkour-works-vocab--cache-notices-an-edited-file ()
  "The cache is keyed on mtime, not path alone.

A path-only key served the first read for the rest of the session.  Async
publish keeps one Emacs alive across many runs on this project, so editing
`data/works-vocab.json' and publishing again silently used the stale copy."
  (a3madkour-works-vocab-test--with-root a3madkour-works-vocab-test--json
    (should (member "playable" (a3madkour-works-vocab/list "game_statuses")))
    (let ((root (file-name-directory
                 (directory-file-name a3madkour-pub/site-data-dir))))
      ;; Rewrite with a different enum, backdating nothing: bump the mtime so
      ;; the change is observable at 1-second filesystem granularity.
      (a3madkour-works-vocab-test/write
       root (replace-regexp-in-string "playable" "shippable"
                                      a3madkour-works-vocab-test--json))
      (set-file-times (expand-file-name "data/works-vocab.json" root)
                      (time-add (current-time) 10))
      (should (member "shippable" (a3madkour-works-vocab/list "game_statuses")))
      (should-not (member "playable" (a3madkour-works-vocab/list "game_statuses"))))))

(provide 'a3madkour-works-vocab-test)

;;; a3madkour-works-vocab-test.el ends here
