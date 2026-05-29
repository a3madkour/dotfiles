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

(require 'org-element)
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

(defun a3madkour-pub-library/publish-library-file (file)
  "Publish a single library FILE to data/<medium>.yaml.

Stub (Task 3): signature only; real implementation lands in Tasks 4-10."
  (ignore file)
  nil)

(provide 'a3madkour-publish-library)

;;; a3madkour-publish-library.el ends here
