;;; a3madkour-publish-library.el --- library per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; B.2: library per-file publish handler.  Walks top-level org headings
;; inside one of four source files (library-{reading,listening,playing,
;; watching}.org), normalizes each heading to a YAML row plist, renders
;; the corresponding data/<medium>.yaml deterministically.
;;
;; Registered into `a3madkour-pub-living--handlers' as four entries
;; (one per library-<medium> section symbol, all pointing at the same
;; `publish-library-file' entry point) by `a3madkour-publish-living'.

;;; Code:

(require 'cl-lib)
(require 'org-element)
(require 'ucs-normalize)
(require 'a3madkour-publish)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-history)

(defconst a3madkour-pub-library--config
  '((library-reading
     "reading.yaml"  "book"  ("book")
     ("finished" "reading" "queued" "abandoned"))
    (library-listening
     "listening.yaml" "album" ("album" "track")
     ("finished" "listening" "queued" "dropped"))
    (library-playing
     "playing.yaml"   "game"  ("game")
     ("finished" "100pct" "playing" "queued" "dropped"))
    (library-watching
     "watching.yaml"  "film"  ("film" "series")
     ("finished" "watching" "queued" "dropped")))
  "Per-section config: (SYMBOL YAML-FILE DEFAULT-MT (ALLOWED-MT...) (ALLOWED-STATUS...)).
Status enums copied verbatim from check_library_fixtures.py — the linter is
authoritative for B-emitted YAML.")

(defun a3madkour-pub-library--config-for (section)
  "Return (yaml-file default-mt allowed-mt allowed-status) for SECTION.
Errors when SECTION is not a known library section."
  (let ((entry (assq section a3madkour-pub-library--config)))
    (unless entry
      (error "a3madkour-pub-library: unknown library section %S" section))
    (cdr entry)))

(defun a3madkour-pub-library--title-to-slug (title)
  "Derive a kebab-case slug from TITLE per spec §5.

Pipeline: NFD-decompose → drop combining marks → lowercase →
collapse non-alphanumeric runs to single `-' → trim leading/trailing
`-'. Returns empty string when no alphanumeric content survives —
callers WARN and skip the item in that case.

Combining marks are matched via the U+0300–U+036F Combining
Diacritical Marks block — same precedent as
`a3madkour-pub-slug--ascii-fold' in `a3madkour-publish-slug.el'.
Emacs's `\\cM' category does NOT correspond to Unicode general
category Mn, so a literal char-range is the portable choice."
  (let* ((decomposed (ucs-normalize-NFD-string title))
         ;; Drop combining marks (Unicode block U+0300–U+036F).
         (stripped (replace-regexp-in-string "[̀-ͯ]" "" decomposed))
         (lower (downcase stripped))
         ;; Collapse runs of non-alphanumeric to a single `-'.
         (dashed (replace-regexp-in-string "[^a-z0-9]+" "-" lower))
         ;; Trim leading/trailing `-'.
         (trimmed (replace-regexp-in-string "\\`-+\\|-+\\'" "" dashed)))
    trimmed))

(defun a3madkour-pub-library--headline-property (headline prop)
  "Read a single drawer property PROP (a string like \"CREATOR\") off HEADLINE.
Returns nil if not set or empty."
  (let ((val (org-element-property
              (intern (concat ":" prop)) headline)))
    (and (stringp val) (not (string-empty-p val)) (string-trim val))))

(defun a3madkour-pub-library--warn (file slug fmt &rest args)
  "Emit a WARN message with FILE + SLUG context."
  (apply #'message (concat "a3madkour-pub-library WARN [%s slug=%s]: " fmt)
         (file-name-nondirectory file) (or slug "?") args))

(defun a3madkour-pub-library--resolve-slug (headline title file)
  "Resolve slug: :SLUG: drawer → fallback `--title-to-slug'.
Empty result → WARN + return nil (caller skips the item)."
  (let* ((drawer-slug (a3madkour-pub-library--headline-property headline "SLUG"))
         (derived (and (not drawer-slug) (a3madkour-pub-library--title-to-slug title)))
         (slug (or drawer-slug derived)))
    (cond
     ((and slug (not (string-empty-p slug))) slug)
     (t (a3madkour-pub-library--warn file nil
                                     "empty slug for title %S; skipping" title)
        nil))))

(cl-defun a3madkour-pub-library--normalize-item (headline section cfg file)
  "Build a YAML-row plist from HEADLINE for SECTION using CFG.
FILE is the source path (used for WARN context + git-mtime fallback for
the `last_modified' field).

Returns nil when the item should be skipped (e.g. empty slug)."
  (ignore section)
  (let* ((title (org-element-property :raw-value headline))
         (slug (a3madkour-pub-library--resolve-slug headline title file)))
    (unless slug
      (cl-return-from a3madkour-pub-library--normalize-item nil))
    (let* ((default-mt    (nth 1 cfg))
           (allowed-mt    (nth 2 cfg))
           (allowed-stat  (nth 3 cfg))
           (drawer-mt     (a3madkour-pub-library--headline-property headline "MEDIA_TYPE"))
           (media-type    (or drawer-mt default-mt))
           (status        (a3madkour-pub-library--headline-property headline "STATUS"))
           (creator       (a3madkour-pub-library--headline-property headline "CREATOR"))
           (year-raw      (a3madkour-pub-library--headline-property headline "YEAR"))
           (year          (and year-raw (string-to-number year-raw)))
           (row-plist     (list :slug slug
                                :title title
                                :creator creator
                                :year year
                                :media_type media-type
                                :status status)))
      (unless (member media-type allowed-mt)
        (a3madkour-pub-library--warn file slug
                                     "media_type=%s not in %S" media-type allowed-mt))
      (unless (and status (member status allowed-stat))
        (a3madkour-pub-library--warn file slug
                                     "status=%s not in %S" status allowed-stat))
      ;; Optional drawer pass-throughs.
      (dolist (prop '(("STARTED" . :started)
                      ("FINISHED" . :finished)
                      ("SPOILER_LEVEL" . :spoiler_level)
                      ("CITE_KEY" . :cite_key)
                      ("CANONICAL_URL" . :canonical_url)
                      ("NOTE_SLUG" . :note_slug)
                      ("PREVIEW" . :preview)))
        (let ((val (a3madkour-pub-library--headline-property headline (car prop))))
          (when val
            (setq row-plist (plist-put row-plist (cdr prop) val)))))
      ;; last_modified: :LAST_MODIFIED: drawer → git-mtime fallback.
      (let* ((drawer-lm (a3madkour-pub-library--headline-property headline "LAST_MODIFIED"))
             (lm (or drawer-lm
                     (a3madkour-pub-history/git-mtime-of-file file))))
        (when lm
          (setq row-plist (plist-put row-plist :last_modified lm))))
      row-plist)))

(defun a3madkour-pub-library/publish-library-file (file)
  "Publish a single library FILE to data/<medium>.yaml.

Stub (Task 3): signature only; real implementation lands in Tasks 4-10."
  (ignore file)
  nil)

(provide 'a3madkour-publish-library)

;;; a3madkour-publish-library.el ends here
