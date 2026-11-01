;;; a3madkour-publish-poetry-test.el --- ert tests for works/poetry handler  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-poetry)
(require 'a3madkour-sections-fixture)
(require 'a3madkour-publish-deliberate)

(ert-deftest a3madkour-pub-poetry-test/module-provides ()
  "The poetry module loads and provides its feature."
  (should (featurep 'a3madkour-publish-poetry)))

(ert-deftest a3madkour-pub-poetry-test/dispatch-registered ()
  "The deliberate dispatch alist contains a works/poetry entry."
  (should (eq (a3madkour-pub-registry/handler "works/poetry" 'deliberate)
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

(ert-deftest a3madkour-pub-poetry-test/copy-audio-asset-success ()
  "Relative `#+AUDIO:' filename → file copied from poetry-dir/assets/<id>/ to bundle."
  (let* ((src-id (format "33333333-3333-3333-3333-%012d" (random 1000000)))
         (poetry-root (make-temp-file "poetry-src-" t))
         (bundle-dir (make-temp-file "poetry-bundle-" t))
         (src-assets (expand-file-name (format "assets/%s/" src-id) poetry-root))
         (src-audio (expand-file-name "reading.mp3" src-assets)))
    (make-directory src-assets t)
    (with-temp-file src-audio (insert "ID3" (make-string 64 ?x)))   ; non-zero
    (let ((a3madkour-pub/poetry-dir poetry-root))
      (a3madkour-pub-poetry--copy-audio-asset src-id "reading.mp3" bundle-dir))
    (should (file-exists-p (expand-file-name "reading.mp3" bundle-dir)))
    (delete-directory poetry-root t)
    (delete-directory bundle-dir t)))

(ert-deftest a3madkour-pub-poetry-test/copy-audio-asset-missing-file ()
  "Missing source file → signals `user-error'."
  (let* ((src-id "44444444-4444-4444-4444-444444444444")
         (poetry-root (make-temp-file "poetry-src-" t))
         (bundle-dir (make-temp-file "poetry-bundle-" t)))
    (let ((a3madkour-pub/poetry-dir poetry-root))
      (should-error
       (a3madkour-pub-poetry--copy-audio-asset src-id "nope.mp3" bundle-dir)
       :type 'user-error))
    (delete-directory poetry-root t)
    (delete-directory bundle-dir t)))

(ert-deftest a3madkour-pub-poetry-test/copy-audio-asset-bad-extension ()
  "Disallowed extension → signals `user-error', no copy attempted."
  (let* ((src-id "55555555-5555-5555-5555-555555555555")
         (poetry-root (make-temp-file "poetry-src-" t))
         (bundle-dir (make-temp-file "poetry-bundle-" t))
         (src-assets (expand-file-name (format "assets/%s/" src-id) poetry-root)))
    (make-directory src-assets t)
    (with-temp-file (expand-file-name "notes.txt" src-assets) (insert "x"))
    (let ((a3madkour-pub/poetry-dir poetry-root))
      (should-error
       (a3madkour-pub-poetry--copy-audio-asset src-id "notes.txt" bundle-dir)
       :type 'user-error))
    (delete-directory poetry-root t)
    (delete-directory bundle-dir t)))

(ert-deftest a3madkour-pub-poetry-test/copy-audio-asset-zero-byte ()
  "Zero-byte file → signals `user-error'."
  (let* ((src-id "66666666-6666-6666-6666-666666666666")
         (poetry-root (make-temp-file "poetry-src-" t))
         (bundle-dir (make-temp-file "poetry-bundle-" t))
         (src-assets (expand-file-name (format "assets/%s/" src-id) poetry-root)))
    (make-directory src-assets t)
    (with-temp-file (expand-file-name "empty.mp3" src-assets))   ; zero bytes
    (let ((a3madkour-pub/poetry-dir poetry-root))
      (should-error
       (a3madkour-pub-poetry--copy-audio-asset src-id "empty.mp3" bundle-dir)
       :type 'user-error))
    (delete-directory poetry-root t)
    (delete-directory bundle-dir t)))

(defun a3madkour-pub-poetry-test--raw (content)
  "Write CONTENT to a temp org file and return its raw body."
  (let ((f (make-temp-file "a3-poem" nil ".org")))
    (unwind-protect
        (progn (with-temp-file f (set-buffer-multibyte t) (insert content))
               (a3madkour-pub-poetry--raw-body f))
      (delete-file f))))

(defconst a3madkour-pub-poetry-test--head
  ":PROPERTIES:\n:ID: x\n:END:\n#+TITLE: T\n#+DATE: 2026-01-01\n\n")

(ert-deftest a3madkour-pub-poetry-test/raw-body-keeps-every-line ()
  (let ((poem "A\n  B\n      C\nD  E\n- F\n1. G\n> H\n*I* /J/\n# K\n* L\n\nM"))
    (should (equal (a3madkour-pub-poetry-test--raw
                    (concat a3madkour-pub-poetry-test--head poem))
                   (concat poem "\n")))))

(ert-deftest a3madkour-pub-poetry-test/raw-body-drops-drawer-and-keywords ()
  (let ((out (a3madkour-pub-poetry-test--raw
              (concat a3madkour-pub-poetry-test--head "A\n"))))
    (should-not (string-match-p ":ID:" out))
    (should-not (string-match-p "#\\+TITLE" out))))

(ert-deftest a3madkour-pub-poetry-test/raw-body-drops-mid-poem-keyword ()
  (should (equal (a3madkour-pub-poetry-test--raw "a\n#+AUDIO: x.mp3\nb")
                 "a\nb\n"))
  (should (equal (a3madkour-pub-poetry-test--raw "a\n#+audio: x.mp3\nb")
                 "a\nb\n")))

(ert-deftest a3madkour-pub-poetry-test/raw-body-keeps-first-line-indent ()
  (should (equal (a3madkour-pub-poetry-test--raw
                  (concat a3madkour-pub-poetry-test--head "    A\nB"))
                 "    A\nB\n")))

(ert-deftest a3madkour-pub-poetry-test/raw-body-skips-drawer-after-keywords ()
  (should (equal (a3madkour-pub-poetry-test--raw
                  "#+TITLE: T\n:PROPERTIES:\n:ID: x\n:END:\nA")
                 "A\n")))

(ert-deftest a3madkour-pub-poetry-test/raw-body-crlf ()
  (should (equal (a3madkour-pub-poetry-test--raw "A\r\nB\r\n") "A\nB\n"))
  (should (equal (a3madkour-pub-poetry-test--raw "A\rB\r") "A\nB\n")))

(ert-deftest a3madkour-pub-poetry-test/raw-body-trims-line-ends ()
  (should (equal (a3madkour-pub-poetry-test--raw "A  \nB") "A\nB\n")))

(ert-deftest a3madkour-pub-poetry-test/raw-body-keeps-escaped-marker ()
  (should (equal (a3madkour-pub-poetry-test--raw "\\[00:99] A")
                 "\\[00:99] A\n")))

(defun a3madkour-pub-poetry-test--gap (content)
  (let ((f (make-temp-file "a3-poem" nil ".org")))
    (unwind-protect
        (progn (with-temp-file f (insert content))
               (a3madkour-pub-poetry/body-gap f))
      (delete-file f))))

(ert-deftest a3madkour-pub-poetry-test/body-gap-nil-for-verse ()
  (should-not (a3madkour-pub-poetry-test--gap
               (concat a3madkour-pub-poetry-test--head "A\nB\n"))))

(ert-deftest a3madkour-pub-poetry-test/body-gap-names-shortcode-line ()
  (should (string-match-p "line 2"
                          (a3madkour-pub-poetry-test--gap
                           (concat a3madkour-pub-poetry-test--head
                                   "A\n{{< x >}}\nB\n")))))

(ert-deftest a3madkour-pub-poetry-test/body-gap-percent-form ()
  (should (string-match-p "line 2"
                          (a3madkour-pub-poetry-test--gap
                           (concat a3madkour-pub-poetry-test--head
                                   "A\n{{% x %}}\nB\n")))))

(ert-deftest a3madkour-pub-poetry-test/body-gap-empty-poem ()
  (should (string-match-p "no poem text"
                          (a3madkour-pub-poetry-test--gap
                           a3madkour-pub-poetry-test--head))))

(ert-deftest a3madkour-pub-poetry-test/summary-marker-scrub ()
  "Summary containing `[mm:ss]' or `\\[mm:ss]' substrings has them stripped."
  (let* ((raw '((title . "T") (date . "2026-06-12") (lastmod . "2026-06-12")
                (draft . nil) (:body-line-count . 1)
                (summary . "Example [00:08]ipsum poem with \\[00:99] literal.")))
         (out (a3madkour-pub-frontmatter/normalize 'works-poetry raw nil)))
    (should (equal (alist-get 'summary out)
                   "Example ipsum poem with  literal."))))

(ert-deftest a3madkour-pub-poetry-test/summary-empty-preserved ()
  "Empty / missing summary stays empty."
  (let* ((raw '((title . "T") (date . "2026-06-12") (lastmod . "2026-06-12")
                (draft . nil) (:body-line-count . 1)))
         (out (a3madkour-pub-frontmatter/normalize 'works-poetry raw nil)))
    (should (equal (alist-get 'summary out) ""))))

(ert-deftest a3madkour-pub-poetry-test/soft-warn-audio-without-markers ()
  "#+AUDIO: set, body has zero markers → soft warning surfaced."
  (let ((warnings (a3madkour-pub-poetry--collect-warnings
                   "Plain poem with no timings"
                   "reading.mp3")))
    (should (cl-some (lambda (w) (string-match-p "isn't timed" w)) warnings))))

(ert-deftest a3madkour-pub-poetry-test/soft-warn-markers-without-audio ()
  "Body has markers, #+AUDIO: absent → soft warning surfaced."
  (let ((warnings (a3madkour-pub-poetry--collect-warnings
                   "[00:01]Lorem [00:02]ipsum"
                   nil)))
    (should (cl-some (lambda (w) (string-match-p "animation-driven sync" w))
                     warnings))))

(ert-deftest a3madkour-pub-poetry-test/soft-warn-both-present-quiet ()
  "Markers + audio → no soft warnings."
  (should (null (a3madkour-pub-poetry--collect-warnings
                 "[00:01]Lorem [00:02]ipsum"
                 "reading.mp3"))))

(ert-deftest a3madkour-pub-poetry-test/soft-warn-both-absent-quiet ()
  "No markers, no audio (plain poem) → no soft warnings."
  (should (null (a3madkour-pub-poetry--collect-warnings
                 "Plain poem"
                 nil))))

(ert-deftest a3madkour-pub-poetry-test/multi-export-warn-and-skip ()
  "`#+multi_export: t' on a poem → warning surfaced, D.2 dispatch not invoked."
  (let* ((dispatched nil)
         (file (make-temp-file "poetry-multi-" nil ".org"
                               ":PROPERTIES:\n:ID: 77777777-7777-7777-7777-777777777777\n:END:\n#+TITLE: T\n#+HUGO_SECTION: works/poetry\n#+multi_export: t\n\n[00:01]hi\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub-multi/dispatch-export)
                   (lambda (&rest _args) (setq dispatched t))))
          (let ((warnings (a3madkour-pub-poetry--maybe-warn-multi-export file)))
            (should (cl-some (lambda (w) (string-match-p "multi_export" w)) warnings))
            (should-not dispatched)))
      (delete-file file))))

(ert-deftest a3madkour-pub-poetry-test/handler-end-to-end-in-process ()
  "Round-trip: build a tmp corpus, publish a poem, assert emitted bytes + manifest.
Uses a fake mp3 (non-zero bytes) for the audio asset.  Does NOT call run-tests.sh
or hugo — pure in-process emacs."
  (let* ((id "88888888-8888-8888-8888-888888888888")
         (slug "test-poem")
         (poetry-root (make-temp-file "poetry-corpus-" t))
         (site-root   (make-temp-file "poetry-site-" t))
         (org-file (expand-file-name (format "%s.org" slug) poetry-root))
         (assets-dir (expand-file-name (format "assets/%s/" id) poetry-root))
         (audio-file (expand-file-name "reading.mp3" assets-dir)))
    (make-directory assets-dir t)
    (with-temp-file audio-file (insert "ID3" (make-string 256 ?x)))
    (with-temp-file org-file
      (insert ":PROPERTIES:\n:ID:       " id "\n:END:\n")
      (insert "#+TITLE: Test Poem\n")
      (insert "#+DATE: 2026-06-12\n")
      (insert "#+HUGO_SECTION: works/poetry\n")
      (insert "#+HUGO_PUBLISH: t\n")
      (insert "#+AUDIO: reading.mp3\n")
      (insert "\n")
      (insert "[00:01]Lorem [00:02]ipsum\n")
      (insert "[00:17]Duis aute\n")
      (insert "# K\n"))
    (unwind-protect
        (let* ((a3madkour-pub/poetry-dir poetry-root)
               (a3madkour-pub/site-data-dir (expand-file-name "data/" site-root))
               (a3madkour-pub-poetry/section-dir-name "works/poetry")
               (result (a3madkour-pub-poetry/publish-poetry-file
                        org-file nil :on-done #'ignore))
               (bundle-dir (expand-file-name
                            (format "content/works/poetry/%s/" slug) site-root))
               (index-md (expand-file-name "index.md" bundle-dir))
               (bundled-audio (expand-file-name "reading.mp3" bundle-dir)))
          (should (file-exists-p index-md))
          (should (file-exists-p bundled-audio))
          (let ((emitted (with-temp-buffer (insert-file-contents index-md) (buffer-string))))
            (should (string-match-p "audio_url: \"reading.mp3\"" emitted))
            (should (string-match-p "lines: 3" emitted))
            (should (string-match-p "^# K$" emitted))
            (should (string-match-p "\\[00:01\\]Lorem \\[00:02\\]ipsum" emitted))))
      (delete-directory poetry-root t)
      (delete-directory site-root t))))

(ert-deftest a3madkour-pub-poetry--render-yaml-value-escapes-quotes ()
  "P1.2: embedded double-quotes are escaped, not emitted raw."
  (should (equal (a3madkour-pub-poetry--render-yaml-value "The \"x\" y")
                 "\"The \\\"x\\\" y\""))
  (should (equal (a3madkour-pub-poetry--render-yaml-value '("a\"b"))
                 "[\"a\\\"b\"]")))

(ert-deftest a3madkour-pub-poetry-test/allowed-keys-follow-the-contract ()
  (a3madkour-sections-test--with-root
      (a3madkour-sections-test/mutate "\"collection\"" "\"cycle\"")
    (let ((out (a3madkour-pub-frontmatter/normalize
                'works-poetry
                '((title . "P") (date . "2026-06-12") (lastmod . "2026-06-12")
                  (collection . "old") (cycle . "new"))
                nil)))
      (should-not (assq 'collection out))
      (should (equal (alist-get 'cycle out) "new")))))


(provide 'a3madkour-publish-poetry-test)

;;; a3madkour-publish-poetry-test.el ends here
