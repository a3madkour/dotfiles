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
    a3madkour-library/notes-dir)
  "Every folder or file the publisher reads from the author's config.
config.org's Publishing paths block must set each one.")

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
