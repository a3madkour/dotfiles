;;; a3madkour-publish-frontmatter.el --- per-section frontmatter normalizer dispatch  -*- lexical-binding: t; -*-

;;; Commentary:

;; Per-section frontmatter normalizer dispatch.  Each B.x content-type
;; slice registers its section's normalize logic by editing the dispatch
;; below.  B.0 ships dispatch infrastructure + pass-through behavior for
;; every known section.
;;
;; Contract (per design spec §7):
;;   (normalize SECTION RAW-ALIST SOURCE-FILE) -> NORMALIZED-ALIST
;;
;; SECTION is a symbol from the enum:
;;   garden | essays
;;   research-themes | research-questions
;;   works-games | works-music | works-poetry
;;   streams | about
;;   library-reading | library-listening | library-playing | library-watching
;;
;; RAW-ALIST is what ox-hugo produces (keys are symbols).  SOURCE-FILE is
;; the absolute path of the source `.org' file (needed for git-mtime
;; lookups, has_* body scans, slug derivation cross-checks).
;;
;; Returns an alist with the same key shape, normalized per the section's
;; contract.  B.0 returns RAW-ALIST unchanged for any known section;
;; B.1+ replaces each per-section branch with real logic.

;;; Code:

(require 'a3madkour-publish-keywords)

(defcustom a3madkour-pub-editorial-tags
  '("TODO" "DONE" "WAIT" "CANCELED" "HOLD" "NOEXPORT" "ATTACH")
  "Org tags treated as editorial (org-mode workflow keywords) and
stripped from round-tripped tag lists by `filter-editorial-tags'.
Used by both garden (file-level tags) and library (per-heading tags)
normalizers."
  :type '(repeat string) :group 'a3madkour-publish)

(defun a3madkour-pub-frontmatter/filter-editorial-tags (tags &optional extra-exclusions)
  "Strip editorial tags from TAGS (a list of strings).

EXTRA-EXCLUSIONS is an optional list of additional tag names to strip,
merged with the defcustom default `a3madkour-pub-editorial-tags'.
Preserves order of remaining tags."
  (let ((excl (append a3madkour-pub-editorial-tags extra-exclusions)))
    (seq-filter (lambda (tag) (not (member tag excl))) tags)))

(defconst a3madkour-pub-frontmatter--known-sections
  '(garden essays
    research-themes research-questions
    works-games works-music works-poetry
    streams about
    library-reading library-listening library-playing library-watching)
  "Closed set of section symbols `normalize' accepts.  Updated as new
sections are added (none planned beyond this set).")

(defun a3madkour-pub-frontmatter/normalize (section raw-alist source-file)
  "Normalize RAW-ALIST for SECTION's frontmatter contract.

SECTION must be a symbol from `a3madkour-pub-frontmatter--known-sections';
signals `error' otherwise.

SOURCE-FILE is the absolute path of the source `.org' file (kept for
per-section normalizers that need git-mtime, body scans, etc.).

Returns a normalized alist.  B.0 returns RAW-ALIST unchanged for any
known section; per-section logic lands in B.1+ (garden), B.2 (library),
… see design spec §12 slice ordering."
  (unless (memq section a3madkour-pub-frontmatter--known-sections)
    (error "a3madkour-pub-frontmatter: unknown section %S (must be one of %S)"
           section a3madkour-pub-frontmatter--known-sections))
  (cond
   ((eq section 'garden)
    (a3madkour-pub-frontmatter--normalize-garden raw-alist source-file))
   ((eq section 'essays)
    (a3madkour-pub-frontmatter--normalize-essays raw-alist source-file))
   ((eq section 'research-themes)
    (a3madkour-pub-frontmatter--normalize-research-theme raw-alist source-file))
   ((eq section 'research-questions)
    (a3madkour-pub-frontmatter--normalize-research-question raw-alist source-file))
   ;; B.2+ slices add real branches here:
   ;;   ((memq section '(library-reading library-listening library-playing library-watching))
   ;;    (a3madkour-pub-frontmatter--normalize-library section raw-alist source-file))
   ;;   ...
   (t
    ;; B.0 pass-through for sections not yet handled.
    (ignore source-file)
    raw-alist)))

(defconst a3madkour-pub-frontmatter--progress->stage
  '(("highlighting" . "seedling")
    ("ref-notes"    . "budding")
    ("main-notes"   . "evergreen")
    ("done"         . "evergreen"))
  "Mapping from org `:PROGRESS:' property to Hugo `growth_stage'.
Unset / unrecognized → \"seedling\" (per spec §7).")

(defconst a3madkour-pub-frontmatter--media-flavors
  '(("book" . "media") ("album" . "media") ("track" . "media")
    ("game" . "media") ("film"  . "media") ("series" . "media")
    ("paper" . "reference") ("video" . "reference")
    ("article" . "reference") ("talk" . "reference"))
  "Map garden `media_type' values to `flavor' per spec §7.")

(defun a3madkour-pub-frontmatter--infer-flavor (media-type)
  "Return flavor for MEDIA-TYPE per spec §7.
nil/unrecognized media_type → \"concept\"."
  (or (cdr (assoc media-type a3madkour-pub-frontmatter--media-flavors))
      "concept"))

(defun a3madkour-pub-frontmatter--coerce-slug-list (raw)
  "Coerce RAW (string or list-of-strings or nil) to a list of strings.
Strings split on whitespace.  nil stays nil."
  (cond
   ((null raw) nil)
   ((listp raw) raw)
   ((stringp raw) (split-string raw "[ \t]+" t))
   (t nil)))

(defun a3madkour-pub-frontmatter--read-org-property (file property)
  "Read PROPERTY (a string like \"PROGRESS\") from the first heading in FILE.
Returns nil if FILE does not exist or PROPERTY is not set.
Returns the first occurrence only."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^[ \t]*:%s:[ \t]+\\(.+\\)$" (regexp-quote property))
             nil t)
        (string-trim (match-string 1))))))

(defun a3madkour-pub-frontmatter--derive-growth-stage (raw-alist source-file)
  "Return growth_stage per spec §7: HUGO_GROWTH_STAGE wins; else map :PROGRESS:."
  (or (alist-get 'growth_stage raw-alist)
      (let ((progress (a3madkour-pub-frontmatter--read-org-property source-file "PROGRESS")))
        (or (and progress (cdr (assoc progress a3madkour-pub-frontmatter--progress->stage)))
            "seedling"))))

(defun a3madkour-pub-frontmatter--read-org-keyword (file keyword-name)
  "Read a single #+KEYWORD: line from FILE.
KEYWORD-NAME is the keyword (e.g. \"HUGO_DESCRIPTION\"); match is
case-insensitive.  Returns the trimmed value string or nil if the
keyword is absent or its value is empty.

Delegates the regex + buffer scan to `a3madkour-pub-keywords/extract'
to keep a single source of truth; we just wrap it with file I/O."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let ((v (a3madkour-pub-keywords/extract keyword-name)))
        (and v (not (string-empty-p v)) v)))))

(defun a3madkour-pub-frontmatter--inject-description (raw-alist source-file)
  "Inject `#+HUGO_DESCRIPTION:' from SOURCE-FILE into RAW-ALIST as `description'.

When `#+HUGO_DESCRIPTION:' is present in the source file, it is set as
the `description' key in the returned alist, overriding any pre-existing
value (e.g. from `#+DESCRIPTION:' via ox-hugo).

When absent, RAW-ALIST is returned unchanged — a pre-existing `description'
key (if any) passes through, and no key is added when neither source is set.

This parallels the HUGO_GROWTH_STAGE wiring used by the garden normalizer
and is the shared infrastructure required by both research-themes and
research-questions normalizers (B.3 Tasks 3-4).

This differs from `a3madkour-pub-frontmatter--derive-growth-stage':
that function preserves a pre-existing raw-alist value via `or'.
`--inject-description' always wins because ox-hugo does not natively
parse `#+HUGO_DESCRIPTION:' into the alist, so any pre-existing
`description' key came from `#+DESCRIPTION:' (a different ox-hugo
mechanism we intentionally override)."
  (let* ((out (copy-alist raw-alist))
         (kw-val (a3madkour-pub-frontmatter--read-org-keyword
                  source-file "HUGO_DESCRIPTION")))
    (when kw-val
      (setf (alist-get 'description out) kw-val))
    out))

(cl-defun a3madkour-pub-frontmatter/last-modified-cascade
    (file &key drawer keyword)
  "Resolve the last_modified value for FILE via the 5-step cascade.

Cascade order:
  1. DRAWER (the :LAST_MODIFIED: property if present in the source)
  2. KEYWORD (the #+HUGO_LASTMOD: keyword value if present)
  3. git-mtime via `a3madkour-pub-history/git-mtime-of-file'
  4. filesystem mtime via `a3madkour-pub-history/filesystem-mtime-of-file'
  5. today (`format-time-string \"%Y-%m-%d\"')

Returns a YYYY-MM-DD string; never nil.  DRAWER + KEYWORD are passed
in by per-section normalizers (each section reads them from different
places — file-level keyword for garden/essays/research, per-heading
drawer for library).

Empty-string values for DRAWER or KEYWORD are treated as absent: Elisp
`\"\"' is truthy so a bare `or' would short-circuit on it, returning an
empty string that the downstream linter rejects."
  (cl-flet ((nonempty (v) (and (stringp v) (not (string-empty-p v)) v)))
    (or (nonempty drawer)
        (nonempty keyword)
        (nonempty (a3madkour-pub-history/git-mtime-of-file file))
        (nonempty (a3madkour-pub-history/filesystem-mtime-of-file file))
        (format-time-string "%Y-%m-%d"))))

(defconst a3madkour-pub-frontmatter--essay-required-keys
  '(title date lastmod draft summary tags series series_order toc
          has_sidenotes has_citations has_footnotes has_math
          has_widgets has_video_sync)
  "14 required frontmatter keys per check_fixtures.py essay contract.")

(defconst a3madkour-pub-frontmatter--essay-optional-keys
  '(tile_size featured hero source_stream)
  "4 optional frontmatter keys per CLAUDE.md essay contract.")

(defun a3madkour-pub-frontmatter--normalize-essays (raw-alist source-file)
  "B.4: essays frontmatter normalizer.

Pipeline:
  1. Drop ox-hugo noise keys (anything not in required ∪ optional).
  2. Coerce draft to bool (default false), toc to bool (default true).
  3. Default series=\"\", series_order=0 (always emitted for linter parity).
  4. Resolve lastmod via last-modified-cascade (drawer → keyword → git → fs → today).
  5. Default all 6 has_* flags to nil; Tasks 4-5 add real scan + override merge.
Returns the normalized alist."
  (let* ((allowed (append a3madkour-pub-frontmatter--essay-required-keys
                          a3madkour-pub-frontmatter--essay-optional-keys))
         (out (cl-remove-if-not (lambda (cell) (memq (car cell) allowed))
                                (copy-alist raw-alist))))
    ;; draft default false
    (unless (assq 'draft out)
      (push (cons 'draft nil) out))
    (when (assq 'draft out)
      (let ((v (alist-get 'draft out)))
        (setf (alist-get 'draft out) (and v (not (eq v nil)) t))))
    ;; toc default true
    (unless (assq 'toc out)
      (push (cons 'toc t) out))
    (when (assq 'toc out)
      (let ((v (alist-get 'toc out)))
        (setf (alist-get 'toc out) (if (memq v '(nil :nil)) nil t))))
    ;; series defaults
    (unless (assq 'series out)
      (push (cons 'series "") out))
    (unless (assq 'series_order out)
      (push (cons 'series_order 0) out))
    (when-let ((so (alist-get 'series_order out)))
      (when (stringp so)
        (setf (alist-get 'series_order out) (string-to-number so))))
    ;; lastmod cascade
    (let* ((drawer-lm (alist-get 'last_modified raw-alist))
           (kw-lm     (alist-get 'lastmod raw-alist))
           (kw-trim   (when (and (stringp kw-lm) (>= (length kw-lm) 10))
                        (substring kw-lm 0 10))))
      (setq out (assq-delete-all 'lastmod out))
      (setq out (assq-delete-all 'last_modified out))
      (setf (alist-get 'lastmod out)
            (a3madkour-pub-frontmatter/last-modified-cascade
             source-file
             :drawer  drawer-lm
             :keyword kw-trim)))
    ;; Task 5: has_* flags.  Caller (publish-essay-file) injects a `:scan-plist'
    ;; key into raw-alist BEFORE calling normalize.  Merge with #+HUGO_HAS_<X>:
    ;; keyword overrides via the essays module helper.  When :scan-plist is
    ;; absent (e.g. unit tests of the normalizer alone), default all flags to nil.
    (require 'a3madkour-publish-essays)
    (let* ((scan-pl (alist-get :scan-plist raw-alist))
           (merged (if scan-pl
                       (a3madkour-pub-essays--merge-has-flags scan-pl source-file)
                     '(:has_sidenotes nil :has_citations nil :has_footnotes nil
                       :has_math nil :has_widgets nil :has_video_sync nil))))
      (setq out (assq-delete-all :scan-plist out))
      (dolist (cell a3madkour-pub-essays--has-flag-keywords)
        (let ((k (intern (substring (symbol-name (car cell)) 1))))  ; :has_x → has_x
          (setf (alist-get k out) (and (plist-get merged (car cell)) t)))))
    out))

(defun a3madkour-pub-frontmatter--normalize-garden (raw-alist source-file)
  "B.1: garden frontmatter normalizer.  Covers Tasks 5-8 + hygiene fixes.

Hygiene rules (check_garden_fixtures.py compliance):
  - `flavor' is NOT emitted to frontmatter.  The linter + Hugo template
    derive flavor internally from `media_type'; emitting it is forbidden
    on concept notes.  `--infer-flavor' stays as a pure helper for
    internal use.
  - `author' is stripped.  ox-hugo may emit it from #+author: or :AUTHOR:
    properties; `author' is not in any of the linter's allowed field sets.
    `creator' carries the equivalent semantic on media/reference notes per
    spec §7.  If the raw alist has both `author' and `creator', `creator'
    wins; if only `author', it is dropped without renaming.
  - `last_modified' is set when absent.  Derived from the source file's
    mtime in YYYY-MM-DD form (git-mtime is the design-spec target per
    §7 open-Q-5; that is a future follow-up)."
  (let ((out (copy-alist raw-alist)))
    ;; Task 5: growth_stage derivation.
    (setf (alist-get 'growth_stage out)
          (a3madkour-pub-frontmatter--derive-growth-stage raw-alist source-file))
    ;; Task 6 (revised): flavor is inferred but NOT emitted to frontmatter.
    ;; The linter derives flavor from media_type; emitting flavor: is forbidden
    ;; on concept notes and redundant on media/reference notes.
    (setq out (assq-delete-all 'flavor out))
    ;; Hygiene: strip `author' — not in any linter-allowed field set.
    ;; `creator' (already present if set in source) carries that semantic.
    (setq out (assq-delete-all 'author out))
    ;; Hygiene: ox-hugo emits #+HUGO_LASTMOD: as `lastmod:' (its own field
    ;; name), but the garden linter rejects `lastmod:' on concept notes and
    ;; requires `last_modified:'.  Resolve via the 5-step cascade:
    ;;   1. explicit last_modified in raw-alist (e.g. :LAST_MODIFIED: drawer)
    ;;   2. lastmod keyword (ox-hugo's ISO datetime truncated to YYYY-MM-DD)
    ;;   3. git-mtime of source-file
    ;;   4. filesystem mtime of source-file
    ;;   5. today
    (let* ((drawer-lm (alist-get 'last_modified out))
           (lastmod   (alist-get 'lastmod out))
           ;; ox-hugo formats HUGO_LASTMOD as ISO datetime ("2024-12-18T...");
           ;; take the YYYY-MM-DD prefix for the keyword slot.
           (keyword-lm (when (and (stringp lastmod) (>= (length lastmod) 10))
                         (substring lastmod 0 10))))
      (setq out (assq-delete-all 'lastmod out))
      (setf (alist-get 'last_modified out)
            (a3madkour-pub-frontmatter/last-modified-cascade
             source-file
             :drawer  drawer-lm
             :keyword keyword-lm)))
    ;; Task 7: topic_map coerce to slug list; only emit when non-nil.
    (let ((tm (a3madkour-pub-frontmatter--coerce-slug-list
               (alist-get 'topic_map raw-alist))))
      (if tm
          (setf (alist-get 'topic_map out) tm)
        ;; Ensure absent input produces no key in output.
        (setq out (assq-delete-all 'topic_map out))))
    ;; Task 8: coerce year and weight from string to int.
    (dolist (k '(year weight))
      (let ((v (alist-get k out)))
        (when (stringp v)
          (setf (alist-get k out) (string-to-number v)))))
    ;; B.2: retroactively close B.1.1 follow-up #6 — strip editorial tags
    ;; (TODO, NOEXPORT, etc.) from the round-tripped tag list.
    (when-let ((tags (alist-get 'tags out)))
      (setf (alist-get 'tags out)
            (a3madkour-pub-frontmatter/filter-editorial-tags tags)))
    out))

(defconst a3madkour-pub-frontmatter--research-statuses
  '("active" "dormant" "answered")
  "Allowed status values for research themes + questions
(per check_research_fixtures.py STATUSES).")

(defconst a3madkour-pub-frontmatter--theme-forbidden
  '(parent_question theme)
  "Frontmatter keys forbidden on themes (per check_research_fixtures.py
THEME_FORBIDDEN).  Dropped silently in the normalizer; site linter
is the hard gate.")

(defun a3madkour-pub-frontmatter--coerce-weight (raw file)
  "Coerce RAW weight value to int.  String '08' must not octal-trap
(per [[hugo-int-octal-gotcha]]).  Non-numeric raw → WARN + nil."
  (cond
   ((null raw) nil)
   ((integerp raw) raw)
   ((stringp raw)
    (let ((cleaned (string-trim raw)))
      (cond
       ((string-empty-p cleaned) nil)
       ;; Float-trip avoids the octal trap.
       ((string-match-p "^[+-]?[0-9]+\\(\\.[0-9]+\\)?$" cleaned)
        (truncate (string-to-number cleaned)))
       (t (message "a3madkour-pub-frontmatter WARN [%s]: weight=%S non-numeric"
                   (if file (file-name-nondirectory file) "unknown") raw)
          nil))))
   (t nil)))

(defun a3madkour-pub-frontmatter--parse-slug-list (raw)
  "Parse a space-delimited slug-list string RAW into a list of strings.

Contract:
  nil    → nil
  list   → returned as-is (defensive against pre-parsed input)
  string → trimmed; empty → nil; otherwise split on whitespace
  other  → nil"
  (cond
   ((null raw) nil)
   ((listp raw) raw)
   ((stringp raw)
    (let ((trimmed (string-trim raw)))
      (when (and trimmed (not (string-empty-p trimmed)))
        (split-string trimmed "[ \t]+" t))))
   (t nil)))

(defun a3madkour-pub-frontmatter--normalize-research-question (raw file)
  "Normalize a research-question RAW alist.  Returns the cleaned alist."
  (let ((out (a3madkour-pub-frontmatter/research-normalize-common raw file)))
    ;; Status enum check.
    (let ((status (alist-get 'status out)))
      (unless (member status a3madkour-pub-frontmatter--research-statuses)
        (message "a3madkour-pub-frontmatter WARN [%s]: status=%S not in %S"
                 (if file (file-name-nondirectory file) "unknown") status
                 a3madkour-pub-frontmatter--research-statuses)))
    ;; Weight coercion — drop key if coerce returns nil (matches theme post-T5 fix).
    (when-let ((raw-w (alist-get 'weight out)))
      (let ((coerced (a3madkour-pub-frontmatter--coerce-weight raw-w file)))
        (if coerced
            (setf (alist-get 'weight out) coerced)
          (setq out (assq-delete-all 'weight out)))))
    ;; Slug-list parses (supporting_notes, related_essays).
    (dolist (key '(supporting_notes related_essays))
      (let* ((raw-v (alist-get key out))
             (parsed (a3madkour-pub-frontmatter--parse-slug-list raw-v)))
        (if parsed
            (setf (alist-get key out) parsed)
          (setq out (assq-delete-all key out)))))
    ;; outputs: never arrives in raw via the custom keyword path (no
    ;; HUGO_OUTPUTS keyword exists).  Defensive cleanup only.  The real
    ;; outputs value is injected by publish-research-file (Task 9) after
    ;; this normalizer returns, parsed from the * Outputs org table.
    (setq out (assq-delete-all 'outputs out))
    out))

(defun a3madkour-pub-frontmatter--normalize-research-theme (raw file)
  "Normalize a research-theme RAW alist.  Returns the cleaned alist."
  (let ((out (a3madkour-pub-frontmatter/research-normalize-common raw file)))
    ;; Status enum check (WARN-don't-fail).
    (let ((status (alist-get 'status out)))
      (unless (member status a3madkour-pub-frontmatter--research-statuses)
        (message "a3madkour-pub-frontmatter WARN [%s]: status=%S not in %S"
                 (if file (file-name-nondirectory file) "unknown") status
                 a3madkour-pub-frontmatter--research-statuses)))
    ;; Weight coercion to int (octal-safe).  Drop the key when coercion
    ;; returns nil (non-numeric raw) rather than leaving (weight . nil)
    ;; in the alist, which would serialize as weight: null and fail the
    ;; research fixtures linter.
    (when-let ((raw-w (alist-get 'weight out)))
      (let ((coerced (a3madkour-pub-frontmatter--coerce-weight raw-w file)))
        (if coerced
            (setf (alist-get 'weight out) coerced)
          (setq out (assq-delete-all 'weight out)))))
    ;; Drop forbidden keys silently.
    (dolist (key a3madkour-pub-frontmatter--theme-forbidden)
      (setq out (assq-delete-all key out)))
    out))

(defun a3madkour-pub-frontmatter/research-normalize-common (raw source-file)
  "Apply common-across-both-research-types normalization to RAW alist.
Returns a NEW alist with the cleaned shared fields populated.  Caller
(theme or question per-type normalizer) layers on the type-specific
fields and emits the final alist.

Callers are responsible for injecting `description' and `source_stream'
into RAW before invocation if those fields should be emitted — ox-hugo
does not natively parse `#+HUGO_DESCRIPTION:' or `#+HUGO_SOURCE_STREAM:'
into the alist.  Use `a3madkour-pub-frontmatter--inject-description'
(B.3 Task 2) and the equivalent source-stream helper (when it exists)
in the per-section normalizer or the handler entry point."
  (let ((out (copy-alist raw)))
    ;; last_modified: cascade.
    (setf (alist-get 'last_modified out)
          (a3madkour-pub-frontmatter/last-modified-cascade
           source-file
           :drawer (alist-get 'last_modified raw)
           :keyword (alist-get 'lastmod raw)))
    ;; Drop ox-hugo's `lastmod' once cascade is resolved.
    (setq out (assq-delete-all 'lastmod out))
    ;; Tags: filter editorial.  If the result is empty (all tags were
    ;; editorial, e.g. only TODO), drop the key entirely rather than
    ;; emitting tags: [] — matches garden's pattern.
    (when-let ((tags (alist-get 'tags out)))
      (let ((filtered (a3madkour-pub-frontmatter/filter-editorial-tags tags)))
        (if filtered
            (setf (alist-get 'tags out) filtered)
          (setq out (assq-delete-all 'tags out)))))
    ;; description / summary / source_stream are pass-through from raw
    ;; (already present via custom HUGO_* keyword wiring).  Drop only if
    ;; raw value is nil/empty.
    (dolist (key '(description summary source_stream))
      (let ((v (alist-get key out)))
        (when (or (null v) (and (stringp v) (string-empty-p v)))
          (setq out (assq-delete-all key out)))))
    out))

(provide 'a3madkour-publish-frontmatter)

;;; a3madkour-publish-frontmatter.el ends here
