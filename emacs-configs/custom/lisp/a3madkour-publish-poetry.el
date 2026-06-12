;;; a3madkour-publish-poetry.el --- Tier 8.2 works-poetry per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; Publishes a single org-mode poem into a synced-poetry page bundle
;; under `content/works/poetry/<slug>/'.
;;
;; Peer of `a3madkour-publish-essays.el'.  Both call into shared B.0
;; infra (rewrite-to-tmp-file, export-file, asset-validate-and-copy,
;; record-publish).  The essays handler is not modified by this slice.
;;
;; Authoring contract: see
;; `docs/superpowers/specs/2026-05-19-org-synced-poetry-export.md'.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-keywords)

(defgroup a3madkour-pub-poetry nil
  "Tier 8.2 works-poetry publish handler."
  :group 'a3madkour-pub)

(defcustom a3madkour-pub-poetry/section-dir-name "works/poetry"
  "Relative content directory under `content/' for poetry bundles.
The on-disk path becomes `content/<section-dir-name>/<slug>/index.md'.
Independent of the `#+HUGO_SECTION:' dispatch symbol (`works-poetry')."
  :type 'string
  :group 'a3madkour-pub-poetry)

(defcustom a3madkour-pub/poetry-dir
  (expand-file-name "notes/works/poetry/" (getenv "HOME"))
  "Root directory of the author's poem org files.
Each poem lives at `<poetry-dir>/<slug>.org' with assets under
`<poetry-dir>/assets/<id>/'."
  :type 'directory
  :group 'a3madkour-pub-poetry)

(defconst a3madkour-pub-poetry--audio-extensions
  '("mp3" "m4a" "ogg" "wav")
  "Allowed audio extensions for `#+AUDIO:' relative filenames.")

(cl-defun a3madkour-pub-poetry/publish-poetry-file (file run &key on-done)
  "Publish a single poem FILE to `content/works/poetry/<slug>/index.md'.

Stub for Task 10.  Tasks 2-9 build out the supporting helpers
(section detection, normalizer, audio keyword resolver, asset copy,
summary scrub, soft warnings, multi-export warn-and-skip).  Task 10
wires them into this entry point."
  (ignore file run on-done)
  (error "a3madkour-pub-poetry/publish-poetry-file: not yet implemented (Task 10)"))

(provide 'a3madkour-publish-poetry)

;;; a3madkour-publish-poetry.el ends here
