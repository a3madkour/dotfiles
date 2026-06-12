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
    (should-not (alist-get 'toc out))
    ;; defaults applied for missing required keys
    (should (eq    (alist-get 'draft   out) nil))
    (should (eq    (alist-get 'lines   out) 0))
    (should (equal (alist-get 'summary out) ""))))

(ert-deftest a3madkour-pub-poetry-test/lines-counter-basic ()
  "Counts non-blank lines; stanza breaks excluded."
  (let ((body "[00:01]Lorem [00:02]ipsum [00:03]dolor [00:04]sit
[00:05]amet [00:06]consectetur [00:07]adipiscing [00:08]elit

[00:09]sed [00:10]do [00:11]eiusmod [00:12]tempor
[00:13]incididunt [00:14]ut [00:15]labore [00:16]dolore

[00:17]Duis aute *irure* reprehenderit

[00:18]ut [00:19]enim \\[00:99] [00:20]minim [00:21]veniam"))
    (should (= (a3madkour-pub-poetry--count-poem-lines body) 6))))

(ert-deftest a3madkour-pub-poetry-test/lines-counter-marker-only-line-counts ()
  "A line containing only a `[mm:ss]' marker still counts."
  (let ((body "[00:01]Lorem
[00:17]
[00:18]veniam"))
    (should (= (a3madkour-pub-poetry--count-poem-lines body) 3))))

(ert-deftest a3madkour-pub-poetry-test/lines-counter-skips-leading-h2 ()
  "A leading H2 (e.g. `## Title') is excluded from the count."
  (let ((body "## Untitled Poem

[00:01]Lorem
[00:02]ipsum"))
    (should (= (a3madkour-pub-poetry--count-poem-lines body) 2))))

(ert-deftest a3madkour-pub-poetry-test/lines-counter-empty-body ()
  "Empty body → 0."
  (should (= (a3madkour-pub-poetry--count-poem-lines "") 0))
  (should (= (a3madkour-pub-poetry--count-poem-lines "   \n\n   \n") 0)))

(ert-deftest a3madkour-pub-poetry-test/normalize-uses-injected-line-count ()
  "Normalizer reads `:body-line-count' from raw-alist and emits `lines:'."
  (let* ((raw '((title . "T") (date . "2026-06-12") (lastmod . "2026-06-12")
                (draft . nil) (:body-line-count . 6)))
         (out (a3madkour-pub-frontmatter/normalize 'works-poetry raw nil)))
    (should (= (alist-get 'lines out) 6))
    (should-not (assq :body-line-count out))))

(ert-deftest a3madkour-pub-poetry-test/audio-classify-absolute-https ()
  "An absolute https:// URL classifies as :url."
  (let ((c (a3madkour-pub-poetry--classify-audio "https://example.com/r.mp3")))
    (should (equal (plist-get c :kind) :url))
    (should (equal (plist-get c :value) "https://example.com/r.mp3"))))

(ert-deftest a3madkour-pub-poetry-test/audio-classify-absolute-http ()
  "An absolute http:// URL classifies as :url."
  (let ((c (a3madkour-pub-poetry--classify-audio "http://example.com/r.mp3")))
    (should (equal (plist-get c :kind) :url))))

(ert-deftest a3madkour-pub-poetry-test/audio-classify-relative-filename ()
  "A bare filename classifies as :file."
  (let ((c (a3madkour-pub-poetry--classify-audio "reading.mp3")))
    (should (equal (plist-get c :kind) :file))
    (should (equal (plist-get c :value) "reading.mp3"))))

(ert-deftest a3madkour-pub-poetry-test/audio-classify-empty ()
  "Empty / nil input → nil."
  (should-not (a3madkour-pub-poetry--classify-audio nil))
  (should-not (a3madkour-pub-poetry--classify-audio ""))
  (should-not (a3madkour-pub-poetry--classify-audio "   ")))

(ert-deftest a3madkour-pub-poetry-test/audio-keyword-absolute-emission ()
  "`#+AUDIO: https://...' → frontmatter `audio_url:' set to the URL; no asset copy."
  (let* ((raw '((title . "T") (date . "2026-06-12") (lastmod . "2026-06-12")
                (draft . nil) (:body-line-count . 1)
                (audio_url . "https://example.com/reading.mp3")))
         (out (a3madkour-pub-frontmatter/normalize 'works-poetry raw nil)))
    (should (equal (alist-get 'audio_url out)
                   "https://example.com/reading.mp3"))))

(provide 'a3madkour-publish-poetry-test)

;;; a3madkour-publish-poetry-test.el ends here
