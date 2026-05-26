;;; a3madkour-publish-garden.el --- garden per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; B.1: garden per-file publish handler.  Wires together ox-hugo export,
;; frontmatter normalization, A.1's link rewriter + asset copier, and
;; A.1's record-publish into one entry point: `publish-garden-file'.
;;
;; Registered into `a3madkour-pub-living--handlers' (see Task 11) as
;;   (garden . a3madkour-pub-garden/publish-garden-file)
;; per spec §10.

;;; Code:

(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)

(defun a3madkour-pub-garden/publish-garden-file (file)
  "Publish a single garden-section FILE to the site's content/garden/<slug>/.

Stub (Task 9): signature only; real implementation lands in Task 10."
  (ignore file)
  nil)

(provide 'a3madkour-publish-garden)

;;; a3madkour-publish-garden.el ends here
