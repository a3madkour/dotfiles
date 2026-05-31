;;; a3madkour-publish-research.el --- research per-page bundle handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; B.3: research per-page bundle handler.  Two cascade types share one
;; handler function: themes (research-themes) and questions
;; (research-questions).  Both emit per-page Hugo bundles at
;; content/research/<themes|questions>/<slug>/index.md.
;;
;; Internal branch on #+HUGO_SECTION: selects per-type frontmatter
;; normalizer + the outputs-table parse (question-only).  Everything
;; else — ox-hugo export, link-rewrite, asset-copy, write-if-different,
;; record-publish — is shared with garden.
;;
;; Registered into `a3madkour-pub-living--handlers' as two entries
;; (one per cascade type, both pointing at the same `publish-research-file'
;; entry point) by `a3madkour-publish-living'.

;;; Code:

(require 'cl-lib)
(require 'org-element)
(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)

(defun a3madkour-pub-research/publish-research-file (file)
  "Publish a single research FILE to content/research/<type>/<slug>/index.md.

Stub (Task 3): signature only; real implementation lands in Tasks 4-10."
  (ignore file)
  nil)

(provide 'a3madkour-publish-research)

;;; a3madkour-publish-research.el ends here
