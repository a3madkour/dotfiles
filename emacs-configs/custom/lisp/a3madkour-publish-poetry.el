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

(defcustom a3madkour-pub-poetry/section-dir-name "works/poetry"
  "Relative content directory under `content/' for poetry bundles.
The on-disk path becomes `content/<section-dir-name>/<slug>/index.md'.
Independent of the `#+HUGO_SECTION:' dispatch symbol (`works-poetry')."
  :type 'string
  :group 'a3madkour-pub)

(defcustom a3madkour-pub/poetry-dir
  (expand-file-name "notes/works/poetry/" (getenv "HOME"))
  "Root directory of the author's poem org files.  Source corpus for the
`works-poetry' dispatch.  Each poem lives at `<poetry-dir>/<slug>.org'
with assets under `<poetry-dir>/assets/<id>/'."
  :type 'directory
  :group 'a3madkour-pub)

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

(defconst a3madkour-pub-poetry--required-keys
  '(title date lastmod draft lines)
  "5 required frontmatter keys per check_works_fixtures.py poetry contract.")

(defconst a3madkour-pub-poetry--optional-keys
  '(tags collection set_to_music summary audio_url source_stream
         tile_size featured hero)
  "9 optional frontmatter keys per spec §Authoring + check_works_fixtures.py.")

(defun a3madkour-pub-poetry--allowed-keys ()
  "All keys allowed in the emitted poetry frontmatter."
  (append a3madkour-pub-poetry--required-keys
          a3madkour-pub-poetry--optional-keys))

(defun a3madkour-pub-frontmatter--normalize-works-poetry (raw-alist source-file)
  "Tier 8.2: works-poetry frontmatter normalizer.

Pipeline:
  1. Filter RAW-ALIST to only allowed keys (drops ox-hugo noise + essay-only keys).
  2. Coerce draft to bool (default nil).
  3. Default lines=0 (Task 4 wires real auto-counting via :body-line-count
     injected into raw-alist by the handler).
  4. Default summary=\"\" (linter requires the key; marker scrub lands in Task 7).
  5. audio_url passed through if present (Tasks 5-6 wire the #+AUDIO: keyword
     reader into raw-alist injection).

SOURCE-FILE is the original .org path (passed through for parity with
peer normalizers; this normalizer does not yet read it, but Tasks 4-7
may extend it to do so via `a3madkour-pub-frontmatter--read-org-keyword')."
  (ignore source-file)
  (let* ((allowed (a3madkour-pub-poetry--allowed-keys))
         (out (cl-remove-if-not
               (lambda (cell) (memq (car cell) allowed))
               (copy-tree raw-alist))))
    ;; Default draft → nil (false)
    (setf (alist-get 'draft out) (and (alist-get 'draft out) t))
    ;; Default lines → 0 (Task 4 will inject :body-line-count and use it)
    (unless (alist-get 'lines out)
      (setf (alist-get 'lines out) 0))
    ;; Default summary → "" (linter requires key)
    (unless (alist-get 'summary out)
      (setf (alist-get 'summary out) ""))
    out))

(provide 'a3madkour-publish-poetry)

;;; a3madkour-publish-poetry.el ends here
