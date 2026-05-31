;;; a3madkour-publish-living.el --- publish-living top-level command  -*- lexical-binding: t; -*-

;;; Commentary:

;; Top-level command for sub-project B's living-surfaces publish.
;; Wraps the begin/walk/finish lifecycle around the union of per-section
;; handlers for living sections (garden, library-*, research-themes,
;; research-questions).
;;
;; B.0 ships the lifecycle scaffold with an empty handler registry.
;; B.1 (garden) is the first slice to register a handler; B.2 (library)
;; and B.3 (research) fill in the rest.
;;
;; Idempotency contract (per design spec §11): running with no source
;; changes produces zero file diffs in content/ + data/.  The B.0 empty
;; handler set trivially satisfies this.

;;; Code:

(require 'a3madkour-publish)
(require 'a3madkour-publish-unpublish)

(defvar a3madkour-pub-living--handlers nil
  "Alist of (SECTION-STRING . HANDLER-FUNCTION) for living sections.

SECTION-STRING is the canonical `#+HUGO_SECTION:' value (e.g. `\"garden\"',
`\"library/reading\"').  Storing as a string lets the dispatcher compare
directly against `note-section''s return value with no symbol/string
bridge — critical for slash-form sections (`library/*', `research/*')
where `intern' would create awkward symbols.

HANDLER-FUNCTION takes one argument (a source file path) and emits the
corresponding Hugo content + calls `record-publish'.

B.0 ships this empty.  Each B.x slice that lands a living-section
handler will `setf' an entry here from its module's `provide' time
or init hook.  Example shape (filled in B.1+):

  ((\"garden\" . a3madkour-pub-garden/publish-garden-file)
   (\"library/reading\" . a3madkour-pub-library/publish-library-file)
   ...)")

;;;###autoload
(defun a3-publish-living ()
  "Publish all living-section source notes from `org-notes-dir'.

Runs the begin/walk/finish lifecycle.  For each registered living
handler in `a3madkour-pub-living--handlers', walks the section's source
set and invokes the handler per-file.

B.0: `a3madkour-pub-living--handlers' is empty, so the walk does nothing.
The lifecycle still runs (begin-publish populates snapshots;
finish-publish clears them) — this proves the wiring is correct without
emitting any Hugo content.

See parent design spec §4 (command surface) and §11 (idempotency)."
  (interactive)
  (a3madkour-pub/begin-publish)
  ;; Walk per-section handlers.  Empty in B.0.
  (dolist (entry a3madkour-pub-living--handlers)
    (let ((section (car entry))
          (handler (cdr entry)))
      (a3madkour-pub-living--walk-section section handler)))
  (a3madkour-pub/finish-publish))

(defun a3madkour-pub-living--walk-section (section handler)
  "Walk `org-notes-dir' for SECTION and invoke HANDLER per matching file.

SECTION is a string (the canonical `#+HUGO_SECTION:' value, e.g.
`\"garden\"', `\"library/reading\"').  A file matches SECTION when its
`note-section' equals SECTION.  Non-matching and unpublished files are
skipped.

B.0: never called (handlers list is empty).  Tests exercise this via
direct invocation with a mock handler if desired."
  (dolist (file (directory-files-recursively
                 a3madkour-pub/org-notes-dir "\\.org\\'"))
    (when (equal section (a3madkour-pub/note-section file))
      (funcall handler file))))

;; B.1: garden handler registration.  Uses `with-eval-after-load' so this
;; module stays unaware of garden's exact section string until garden is
;; loaded — each B.x slice that ships a living-section handler adds its
;; own after-load form via this pattern.
(with-eval-after-load 'a3madkour-publish-garden
  (add-to-list 'a3madkour-pub-living--handlers
               '("garden" . a3madkour-pub-garden/publish-garden-file)))

;; B.2: library handler registration (one entry per library-<medium>
;; section, all pointing at the same `publish-library-file' entry point).
(with-eval-after-load 'a3madkour-publish-library
  (dolist (section '("library/reading" "library/listening"
                     "library/playing" "library/watching"))
    (add-to-list 'a3madkour-pub-living--handlers
                 (cons section 'a3madkour-pub-library/publish-library-file))))

;; B.3: research handler registration (one entry per cascade type,
;; both pointing at the same `publish-research-file' entry point).
(with-eval-after-load 'a3madkour-publish-research
  (dolist (section '("research/themes" "research/questions"))
    (add-to-list 'a3madkour-pub-living--handlers
                 (cons section 'a3madkour-pub-research/publish-research-file))))

(provide 'a3madkour-publish-living)

;;; a3madkour-publish-living.el ends here
