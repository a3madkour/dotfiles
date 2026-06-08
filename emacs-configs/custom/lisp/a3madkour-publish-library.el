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
  '(("library/reading"
     "reading.yaml"  "book"  ("book")
     ("finished" "reading" "queued" "abandoned"))
    ("library/listening"
     "listening.yaml" "album" ("album" "track")
     ("finished" "listening" "queued" "dropped"))
    ("library/playing"
     "playing.yaml"   "game"  ("game")
     ("finished" "100pct" "playing" "queued" "dropped"))
    ("library/watching"
     "watching.yaml"  "film"  ("film" "series")
     ("finished" "watching" "queued" "dropped")))
  "Per-section config: (SECTION-STRING YAML-FILE DEFAULT-MT (ALLOWED-MT...) (ALLOWED-STATUS...)).
SECTION-STRING is the canonical `#+HUGO_SECTION:' slash-form value (e.g.
`\"library/reading\"') so it compares directly against `note-section''s
string return — no symbol/string bridge needed.

Status enums copied verbatim from check_library_fixtures.py — the linter is
authoritative for B-emitted YAML.")

(defun a3madkour-pub-library--config-for (section)
  "Return (yaml-file default-mt allowed-mt allowed-status) for SECTION.
SECTION is a string (the canonical `#+HUGO_SECTION:' slash-form).
Errors when SECTION is not a known library section."
  (let ((entry (assoc section a3madkour-pub-library--config)))
    (unless entry
      (error "a3madkour-pub-library: unknown library section %S" section))
    (cdr entry)))

(defconst a3madkour-pub-library--extras-by-media
  '(("book"
     ("ISBN" :isbn nil) ("PROGRESS_PCT" :progress_pct int)
     ("PROGRESS_LABEL" :progress_label nil)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("album"
     ("MBID" :musicbrainz_release_group nil)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("track"
     ("MBID" :musicbrainz_release_group nil)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("game"
     ("IGDB_ID" :igdb_id int) ("HOURS_PLAYED" :hours_played int)
     ("PLATFORM" :platform nil)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("film"
     ("RUNTIME_MIN" :runtime_min int) ("TMDB_ID" :tmdb_id int)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("series"
     ("EPISODE_COUNT" :episode_count int) ("CURRENT_EPISODE" :current_episode int)
     ("CURRENT_SEASON" :current_season int) ("TMDB_ID" :tmdb_id int)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil)))
  "Per-medium extras drawer prop → yaml key + coercion.
Matches `tools/check_library_fixtures.py:ALLOWED_EXTRAS' exactly.")

(defun a3madkour-pub-library--site-static-dir-of (source-file)
  "Derive the site static/ dir given SOURCE-FILE (a library .org).
Cascade: A3_PUB_SITE_STATIC_DIR env var → sibling of `a3madkour-pub/site-data-dir'.
Returns absolute path with trailing slash, or nil if unresolvable."
  (ignore source-file)
  (or (getenv "A3_PUB_SITE_STATIC_DIR")
      (when (and (boundp 'a3madkour-pub/site-data-dir)
                 a3madkour-pub/site-data-dir)
        (expand-file-name "../static/"
                          (directory-file-name a3madkour-pub/site-data-dir)))))

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

(defun a3madkour-pub-library--collect-extras (headline media-type file slug)
  "Collect extras drawer properties from HEADLINE per MEDIA-TYPE.
WARNs on missing cover-file (emits key anyway).  Returns a plist or nil."
  (let* ((spec (cdr (assoc media-type a3madkour-pub-library--extras-by-media)))
         (result '()))
    (dolist (entry spec)
      (let* ((prop (nth 0 entry))
             (key (nth 1 entry))
             (coerce (nth 2 entry))
             (raw (a3madkour-pub-library--headline-property headline prop)))
        (when raw
          (let ((val (if (eq coerce 'int) (string-to-number raw) raw)))
            (setq result (plist-put result key val))
            ;; Cover-file existence check (WARN only; key still emitted above).
            (when (eq key :cover_file)
              (let* ((static-dir (a3madkour-pub-library--site-static-dir-of file))
                     (cover-path (and static-dir
                                      (expand-file-name (concat "library/covers/" raw)
                                                        static-dir))))
                (when (and cover-path (not (file-exists-p cover-path)))
                  (a3madkour-pub-library--warn file slug
                                               "cover file missing at %s" cover-path))))))))
    result))

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
      ;; Tags: per-heading org tags through editorial filter.
      (let* ((raw-tags (org-element-property :tags headline))
             (filtered (a3madkour-pub-frontmatter/filter-editorial-tags raw-tags)))
        ;; Always emit :tags (linter requires the field even when empty).
        (setq row-plist (plist-put row-plist :tags filtered)))
      ;; last_modified: full 5-step cascade per B.3's shared helper
      ;; (drawer → keyword → git-mtime → fs-mtime → today).  Library rows
      ;; have no per-heading keyword equivalent of `#+HUGO_LASTMOD:', so
      ;; :keyword is left unset.  Bug 1.5 (polish-and-bugfix-roadmap.md):
      ;; before this change the library handler used a 2-step `or' that
      ;; could return nil → the per-row :last_modified key was omitted →
      ;; site linter rejected the row (last_modified is required).  The
      ;; cascade always returns a YYYY-MM-DD string, so `:last_modified'
      ;; is now unconditionally emitted.
      (let ((lm (a3madkour-pub-frontmatter/last-modified-cascade
                 file
                 :drawer (a3madkour-pub-library--headline-property
                          headline "LAST_MODIFIED"))))
        (setq row-plist (plist-put row-plist :last_modified lm)))
      ;; Extras: per-medium drawer mapping + cover-file existence check.
      (let ((extras (a3madkour-pub-library--collect-extras headline media-type file slug)))
        (when extras
          (setq row-plist (plist-put row-plist :extras extras))))
      row-plist)))

(defconst a3madkour-pub-library--yaml-key-order
  '(:slug :title :creator :year :media_type :status
    :started :finished :last_modified :note_slug :canonical_url
    :spoiler_level :cite_key :preview :tags :extras)
  "Deterministic key order within each yaml row.
Matches the shape of existing fixtures under data/*.yaml.")

(defun a3madkour-pub-library--yaml-single-quote (val)
  "Wrap VAL in YAML single-quoted style, doubling embedded `''.
Single-quoted YAML: the only escape is `'' → `'''."
  (concat "'" (replace-regexp-in-string "'" "''" val) "'"))

(defun a3madkour-pub-library--render-scalar (val)
  "Render a scalar VAL for inclusion in YAML.

Strings that contain YAML-sensitive characters (`:' `#'), look like URLs,
or begin with any YAML indicator character (`[' `]' `{' `}' `>' `|' `*'
`&' `!' `%' `@' `` ` `` `\"' `'' `?' `,' `-') are emitted in YAML
single-quoted style (`'...''), with embedded `'' doubled. Dates
(YYYY-MM-DD) and plain strings emit unquoted; nil/t/numbers handle their
natural types."
  (cond
   ((null val) "null")
   ((eq val t) "true")
   ((numberp val) (number-to-string val))
   ((stringp val)
    (cond
     ;; YYYY-MM-DD: emit unquoted so PyYAML loads as datetime.date.
     ((string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$" val) val)
     ;; URLs: single-quote (escape embedded `'').
     ((string-prefix-p "http" val)
      (a3madkour-pub-library--yaml-single-quote val))
     ;; YAML-sensitive chars: single-quote (escape embedded `'').
     ((string-match-p "[:#]" val)
      (a3madkour-pub-library--yaml-single-quote val))
     ;; Leading YAML indicator would confuse the parser into reading a
     ;; flow collection, anchor/alias, block scalar, tag, directive, or
     ;; quoted scalar; force single-quoted output. `]' is placed first
     ;; inside the class so it is taken as a literal.
     ((string-match-p "\\`[][{}>|*&!%@`\"'?,-]" val)
      (a3madkour-pub-library--yaml-single-quote val))
     (t val)))
   (t (a3madkour-pub-library--yaml-single-quote (format "%S" val)))))

(defun a3madkour-pub-library--render-tags (tags)
  "Render a list of tag strings as a YAML flow-sequence."
  (concat "[" (mapconcat #'identity tags ", ") "]"))

(defun a3madkour-pub-library--render-extras (extras indent)
  "Render an EXTRAS plist as a nested YAML block at INDENT (a string)."
  (let ((lines '()))
    ;; Render in plist-iteration order (matches insertion order from
    ;; the per-medium extras table — already deterministic).
    (cl-loop for (k v) on extras by #'cddr
             for name = (substring (symbol-name k) 1)
             do (push (format "%s%s: %s" indent name
                              (a3madkour-pub-library--render-scalar v))
                      lines))
    (mapconcat #'identity (nreverse lines) "\n")))

(defun a3madkour-pub-library--render-row (row)
  "Render one ROW plist as a YAML list item (`  - key: value' style)."
  (let ((lines '())
        (first t))
    (dolist (key a3madkour-pub-library--yaml-key-order)
      (when (plist-member row key)
        (let* ((val (plist-get row key))
               (name (substring (symbol-name key) 1))
               (prefix (if first "  - " "    "))
               (line
                (cond
                 ((eq key :tags)
                  (format "%s%s: %s" prefix name
                          (a3madkour-pub-library--render-tags val)))
                 ((eq key :extras)
                  (format "%s%s:\n%s" prefix name
                          (a3madkour-pub-library--render-extras val "      ")))
                 (t
                  (format "%s%s: %s" prefix name
                          (a3madkour-pub-library--render-scalar val))))))
          (push line lines)
          (setq first nil))))
    (mapconcat #'identity (nreverse lines) "\n")))

(defun a3madkour-pub-library--render-library-yaml (rows source-file)
  "Render ROWS (a list of plists) into a complete YAML document.
SOURCE-FILE is recorded in the comment header for provenance."
  (concat
   (format
    "# Generated by a3madkour-publish-library from %s.\n# Manual edits will be overwritten on next publish-living run.\nitems:\n"
    (file-name-nondirectory source-file))
   (mapconcat #'a3madkour-pub-library--render-row rows "\n")
   "\n"))

(defun a3madkour-pub-library--write-if-different (path content)
  "Write CONTENT to PATH only if it differs from existing on-disk content.
Returns t if a write occurred, nil if the existing content was identical."
  (let ((existing (when (file-exists-p path)
                    (with-temp-buffer
                      (insert-file-contents path)
                      (buffer-string)))))
    (unless (string= existing content)
      (make-directory (file-name-directory path) t)
      (with-temp-file path (insert content))
      t)))

(defun a3madkour-pub-library--yaml-path (file cfg)
  "Compute the absolute output yaml path for FILE given CFG.
Resolves under `a3madkour-pub/site-data-dir'; errors if unset."
  (ignore file)
  (let ((data-dir (and (boundp 'a3madkour-pub/site-data-dir)
                       a3madkour-pub/site-data-dir)))
    (unless data-dir
      (error "a3madkour-pub-library: a3madkour-pub/site-data-dir is nil"))
    (expand-file-name (nth 0 cfg) data-dir)))

(cl-defun a3madkour-pub-library/publish-library-file (file run &key on-done)
  "Publish a single library FILE to data/<medium>.yaml.

Walks top-level headings via `org-element-parse-buffer', normalizes each
via `--normalize-item', deduplicates slugs (WARN on collision; skip
second), renders the YAML, writes if different.  Library items do NOT
call `record-publish' (URL-less; per spec §6 step 8).

RUN is the a3-pub-async-run handle (used for log-step in later tasks).
ON-DONE is invoked with \\='ok on completion or \\='err if any step throws."
  (condition-case _err
      (progn
        (ignore run)
        (let* ((section (a3madkour-pub/note-section file))
               (cfg (a3madkour-pub-library--config-for section))
               (out-path (a3madkour-pub-library--yaml-path file cfg))
               (ast (with-temp-buffer
                      (insert-file-contents file)
                      (org-mode)
                      (org-element-parse-buffer)))
               (seen-slugs (make-hash-table :test 'equal))
               (rows '()))
          (org-element-map ast 'headline
            (lambda (hl)
              (when (= 1 (org-element-property :level hl))
                (let ((row (a3madkour-pub-library--normalize-item hl section cfg file)))
                  (when row
                    (let ((slug (plist-get row :slug)))
                      (cond
                       ((gethash slug seen-slugs)
                        (a3madkour-pub-library--warn
                         file slug "slug collision; skipping second occurrence"))
                       (t
                        (puthash slug t seen-slugs)
                        (push row rows)))))))))
          (let ((yaml (a3madkour-pub-library--render-library-yaml
                       (nreverse rows) file)))
            (a3madkour-pub-library--write-if-different out-path yaml)))
        (when on-done (funcall on-done 'ok)))
    (error
     (when on-done (funcall on-done 'err)))))

(defun a3madkour-pub-library/planned-steps (_file)
  "Return rough step count for B.2 library handler."
  4)

(provide 'a3madkour-publish-library)

;;; a3madkour-publish-library.el ends here
