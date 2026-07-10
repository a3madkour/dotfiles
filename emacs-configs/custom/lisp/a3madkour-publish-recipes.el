;;; a3madkour-publish-recipes.el --- recipes per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; Slice 2: recipes per-file publish handler.  Parses drawer metadata plus
;; the ** Ingredients (org table) / ** Steps / ** Sources subtrees, routes the
;; standard frontmatter fields through the `recipes' normalize branch, injects
;; the recipe-specific keys, and writes content/recipes/<slug>/index.md.
;; Structural peer of a3madkour-publish-research.el.

;;; Code:

(require 'cl-lib)
(require 'org-element)
(require 'a3madkour-publish)
(require 'a3madkour-publish-yaml)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)
(require 'a3madkour-recipe-lint)

(defcustom a3madkour-pub-recipes/section-dir-name "recipes"
  "Hugo content section directory name for recipes (relative to site root)."
  :type 'string :group 'a3madkour-pub)

(cl-defun a3madkour-pub-recipes/publish-recipe-file (file run &key on-done)
  "Publish a single recipe FILE to content/recipes/<slug>/index.md.
Stub — real pipeline lands in Task 11."
  (ignore file run)
  (error "a3madkour-pub-recipes: not implemented yet")
  (when on-done (funcall on-done 'err)))

(defun a3madkour-pub-recipes/planned-steps (_file)
  "Return rough step count for the recipes handler."
  3)

(provide 'a3madkour-publish-recipes)

;;; a3madkour-publish-recipes.el ends here
