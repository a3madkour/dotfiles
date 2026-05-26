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

(defun a3madkour-pub-frontmatter--normalize-garden (raw-alist source-file)
  "B.1: garden frontmatter normalizer.  Filled in by Tasks 5-8."
  (ignore source-file)
  raw-alist)

(provide 'a3madkour-publish-frontmatter)

;;; a3madkour-publish-frontmatter.el ends here
