;;; a3madkour-publish-export.el --- ox-hugo wrapper -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared ox-hugo export wrapper for sub-project B's per-section
;; publishers.  Exposes a single entry point `export-file' that invokes
;; ox-hugo on a single source `.org' file and returns a structured plist:
;;
;;   (:body MARKDOWN-STRING :frontmatter ALIST :warnings (STRING ...))
;;
;; B.0 ships the API surface only — the body is empty, frontmatter and
;; warnings are nil.  B.1 (garden handler) is the first slice that wires
;; the real ox-hugo invocation.
;;
;; ox-hugo loading: ox-hugo is loaded lazily.  When B.0 is in effect
;; (skeleton stub), ox-hugo is not required.  B.1+ will add `(require
;; 'ox-hugo)' here once the real export plumbing lands.

;;; Code:

(defun a3madkour-pub-export/export-file (file)
  "Export FILE (an absolute `.org' path) via ox-hugo.

Returns a plist:
  :body         MARKDOWN-STRING — the post-export markdown body (no frontmatter)
  :frontmatter  ALIST — keys are symbols (e.g. `title' `tags'), values are
                strings/lists/booleans as ox-hugo emits them
  :warnings     LIST OF STRINGS — non-fatal issues raised during export

B.0 skeleton: returns (:body \"\" :frontmatter nil :warnings nil) regardless
of input.  B.1 (this slice) wires the real ox-hugo invocation in a follow-up
task; this docstring's contract holds across both phases.

The bundle destination dir is the caller's responsibility (see spec §10);
this function does not write to disk."
  ;; B.0 skeleton: no-op stub.  B.1 replaces the body with real ox-hugo
  ;; invocation that captures the export buffer + extracts frontmatter.
  (ignore file)
  (list :body "" :frontmatter nil :warnings nil))

(provide 'a3madkour-publish-export)

;;; a3madkour-publish-export.el ends here
