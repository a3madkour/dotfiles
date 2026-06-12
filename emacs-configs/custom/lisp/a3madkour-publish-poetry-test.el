;;; a3madkour-publish-poetry-test.el --- ert tests for works/poetry handler  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-poetry)
(require 'a3madkour-publish-deliberate)

(ert-deftest a3madkour-pub-poetry-test/module-provides ()
  "The poetry module loads and provides its feature."
  (should (featurep 'a3madkour-publish-poetry)))

(ert-deftest a3madkour-pub-poetry-test/dispatch-registered ()
  "The deliberate dispatch alist contains a works/poetry entry."
  (should (eq (cdr (assq 'works/poetry a3madkour-pub-deliberate--handlers))
              'a3madkour-pub-poetry/publish-poetry-file)))

(ert-deftest a3madkour-pub-poetry-test/section-dir-default ()
  "`section-dir-name' defaults to \"works/poetry\" (relative to site root)."
  (should (equal a3madkour-pub-poetry/section-dir-name "works/poetry")))

(ert-deftest a3madkour-pub-poetry-test/section-detection ()
  "A .org file with `#+HUGO_SECTION: works/poetry' resolves to that section.
`#+HUGO_PUBLISH: t' is required for `note-metadata' to return non-nil — without
it, `note-section' short-circuits via the publish gate (see `--parse-file')."
  (let ((tmp (make-temp-file "poetry-section-" nil ".org"
                             ":PROPERTIES:\n:ID: 22222222-2222-2222-2222-222222222222\n:END:\n#+TITLE: T\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: works/poetry\n#+DATE: 2026-06-12\n\nbody\n")))
    (unwind-protect
        (should (equal (a3madkour-pub/note-section tmp) "works/poetry"))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-poetry-test/normalize-passes-through-allowed-keys ()
  "Normalizer passes through allowed optional keys; drops essay-only keys."
  (let* ((raw '((title . "Untitled Poem")
                (date . "2026-06-12")
                (lastmod . "2026-06-12")
                (draft . nil)
                (tags . ("example" "synced"))
                (collection . "greenhouse-demos")
                (set_to_music . "music-slug")
                (source_stream . "stream-slug")
                (has_sidenotes . t)            ; essay-only — should be dropped
                (has_citations . t)            ; essay-only — should be dropped
                (toc . t)))                    ; essay-only — should be dropped
         (out (a3madkour-pub-frontmatter/normalize 'works-poetry raw nil)))
    (should (equal (alist-get 'title out) "Untitled Poem"))
    (should (equal (alist-get 'collection out) "greenhouse-demos"))
    (should (equal (alist-get 'set_to_music out) "music-slug"))
    (should (equal (alist-get 'source_stream out) "stream-slug"))
    (should (equal (alist-get 'tags out) '("example" "synced")))
    (should-not (alist-get 'has_sidenotes out))
    (should-not (alist-get 'has_citations out))
    (should-not (alist-get 'toc out))))

(provide 'a3madkour-publish-poetry-test)

;;; a3madkour-publish-poetry-test.el ends here
