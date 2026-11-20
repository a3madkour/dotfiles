;;; a3madkour-publish-paths.el --- the author's folders come from config  -*- lexical-binding: t; -*-

;;; Commentary:

;; The publisher names none of the author's folders.  Every folder variable
;; defaults to nil and is set in the "Publishing paths" block of config.org,
;; which tangles to `publish-paths.el' beside config.el.  Interactive Emacs
;; loads that file from config.el; a3-pub.sh loads it before every batch
;; run, so both read the same values.

;;; Code:

(defconst a3madkour-pub/path-variables
  '(a3madkour-pub/site-data-dir
    a3madkour-pub/org-notes-dir
    a3madkour-pub/essays-dir
    a3madkour-pub/poetry-dir
    a3madkour-pub-canonical-asset-root
    a3madkour-pub-bib/library-path
    a3madkour-pub-citations/ref-notes-dir
    a3madkour-library/notes-dir
    ;; The ingredient registry (a3madkour-ingredients.el), read by the recipe
    ;; linter.  Unlike the rest it may stay nil: the linter then skips its
    ;; registry rule.
    a3madkour-ingredients/file
    ;; The folder recipe files live in, walked by living publish beside the
    ;; notes tree.  It too may stay nil: living publish then walks no
    ;; recipes folder.
    a3madkour-pub-recipes-dir)
  "Every folder or file the publisher reads from the author's config.
config.org's Publishing paths block must set each one.")

(defcustom a3madkour-pub-recipes-dir nil
  "Root directory of the author's recipe org files, or nil.
Living publish walks it beside `a3madkour-pub/org-notes-dir' (see
`a3madkour-pub-registry-living-folders'); with nil, or a folder that
does not exist, it walks no recipes folder.  Set in config.org's
Publishing paths block."
  :type '(choice (const :tag "Not set" nil) directory)
  :group 'a3madkour-pub)

(defun a3madkour-pub/path (var)
  "Return VAR's value expanded, or signal a `user-error' naming VAR.
VAR is one of `a3madkour-pub/path-variables'.  An unset folder is an
error rather than a silent fall-back to `default-directory'."
  (let ((v (and (boundp var) (symbol-value var))))
    (unless (and (stringp v) (not (string-empty-p v)))
      (user-error "a3madkour-pub: `%s' is not set; set it in the Publishing \
paths block of config.org (tangled to publish-paths.el)" var))
    (expand-file-name v)))

(provide 'a3madkour-publish-paths)

;;; a3madkour-publish-paths.el ends here
