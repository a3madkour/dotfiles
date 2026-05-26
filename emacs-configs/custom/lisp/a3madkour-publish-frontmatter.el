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
;;   research-theme | research-question
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

(defconst a3madkour-pub-frontmatter--known-sections
  '(garden essays
    research-theme research-question
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
   ;; B.2+ slices add real branches here:
   ;;   ((memq section '(library-reading library-listening library-playing library-watching))
   ;;    (a3madkour-pub-frontmatter--normalize-library section raw-alist source-file))
   ;;   ((memq section '(research-theme research-question))
   ;;    (a3madkour-pub-frontmatter--normalize-research section raw-alist source-file))
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
    ;; requires `last_modified:'. Rename when present; otherwise derive from
    ;; the source file's mtime in YYYY-MM-DD form (git-mtime is the §7
    ;; open-Q-5 follow-up).
    (let ((lastmod (alist-get 'lastmod out)))
      (when (and lastmod (not (alist-get 'last_modified out)))
        ;; ox-hugo formats HUGO_LASTMOD as ISO datetime ("2024-12-18T..."); take
        ;; the YYYY-MM-DD prefix.
        (setf (alist-get 'last_modified out)
              (if (and (stringp lastmod) (>= (length lastmod) 10))
                  (substring lastmod 0 10)
                lastmod)))
      (setq out (assq-delete-all 'lastmod out)))
    (unless (alist-get 'last_modified out)
      (setf (alist-get 'last_modified out)
            (format-time-string "%Y-%m-%d"
                                (file-attribute-modification-time
                                 (file-attributes source-file)))))
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
    out))

(provide 'a3madkour-publish-frontmatter)

;;; a3madkour-publish-frontmatter.el ends here
