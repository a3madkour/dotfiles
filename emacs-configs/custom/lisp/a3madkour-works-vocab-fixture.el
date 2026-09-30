;;; a3madkour-works-vocab-fixture.el --- shared works-vocabulary test fixture  -*- lexical-binding: t; -*-

;;; Commentary:

;; Test support, not a test: the vocabulary FIXTURE every works test file
;; needs, in one place rather than three.  It deliberately does NOT match
;; run-tests.sh's `*-test.el' glob — a file that is both `require'd by other
;; test files and loaded again by the runner makes ert refuse the redefinition
;; of every test it carries.
;;
;; This is a fixture, not a copy of the contract.  The contract's content lives
;; in the site repo's `data/works-vocab.json' and is asserted there
;; (`tools/test_check_works_fixtures.py'); both languages read that one file.
;; What the elisp tests assert is that the reader and the normalizer take their
;; key sets FROM a file, which is why their expectations are computed from this
;; fixture rather than written out beside it.

;;; Code:

(require 'a3madkour-works-vocab)
;; Defines `a3madkour-pub/site-data-dir'.  Required so the `let' in the macro
;; below is a DYNAMIC binding: under `lexical-binding: t' a `let' over a
;; symbol Emacs does not yet know to be special creates a lexical binding
;; instead, which the reader would never see.
(require 'a3madkour-publish-history)
;; Loaded eagerly so `a3madkour-pub-yaml/site-root' exists before any test
;; mocks it: `a3madkour-works-vocab' requires this module lazily, inside the
;; function, and a `cl-letf' mock installed over an UNDEFINED symbol would be
;; clobbered the moment that lazy `require' actually loaded the real defun.
(require 'a3madkour-publish-yaml)

(defconst a3madkour-works-vocab-test--json
  "{\"game_statuses\":[\"playable\",\"in-progress\",\"archived\"],
    \"game_kinds\":[\"full-release\",\"jam\",\"research-prototype\",\"experiment\"],
    \"music_formats\":[\"album\",\"track\",\"experiment\",\"live\"],
    \"platform_kinds\":[\"bandcamp\",\"soundcloud\",\"youtube\"],
    \"umbrella_optional\":[\"tile_size\",\"featured\",\"hero\"],
    \"game_required\":[\"title\",\"date\",\"lastmod\",\"draft\",
                      \"status\",\"game_kind\",\"tagline\",\"year\"],
    \"game_optional\":[\"tags\",\"summary\",\"embed_url\",\"source_url\",\"itch_url\",
                      \"collaborators\",\"tech_stack\",\"length\",\"screenshots\",
                      \"research_questions\",\"related_essays\",\"related_notes\",
                      \"source_stream\"],
    \"music_required\":[\"title\",\"date\",\"lastmod\",\"draft\",\"format\",\"year\"],
    \"music_optional\":[\"tags\",\"summary\",\"tagline\",\"cover\",\"duration\",
                       \"tracks\",\"platform_embed\",\"audio_url\",\"lyrics_poem\",
                       \"related_works\",\"related_essays\",\"made_with\",
                       \"collaborators\",\"source_stream\"]}"
  "Vocabulary fixture mirroring the site repo's `data/works-vocab.json' shape.")

(defun a3madkour-works-vocab-test/write (site-root &optional json)
  "Write the vocabulary fixture (or JSON) under SITE-ROOT's `data/'."
  (make-directory (expand-file-name "data" site-root) t)
  (with-temp-file (expand-file-name "data/works-vocab.json" site-root)
    (insert (or json a3madkour-works-vocab-test--json))))

(defmacro a3madkour-works-vocab-test--with-root (json &rest body)
  "Run BODY with a temp site root whose data/works-vocab.json holds JSON.
When JSON is nil, no vocabulary file is written.  The site root is supplied
the way production supplies it — through `a3madkour-pub/site-data-dir' — so
the test exercises the real path resolution, not a stubbed one."
  (declare (indent 1))
  `(let* ((a3madkour-works-vocab--cache nil)
          (root (file-name-as-directory (make-temp-file "a3-works-vocab" t))))
     (unwind-protect
         (progn
           (when ,json (a3madkour-works-vocab-test/write root ,json))
           (let ((a3madkour-pub/site-data-dir
                  (file-name-as-directory (expand-file-name "data" root))))
             ,@body))
       (delete-directory root t))))

(provide 'a3madkour-works-vocab-fixture)

;;; a3madkour-works-vocab-fixture.el ends here
