;;; a3madkour-publish-id.el --- org-roam ID → file lookup -*- lexical-binding: t; -*-

;;; Commentary:

;; Isolates the `org-roam' dep used to resolve `[[id:UUID]]` links to
;; concrete file paths.  All publish-side ID dispatching goes through
;; `a3madkour-pub--id-to-file` defined here.

;;; Code:

(require 'org-roam)

(defun a3madkour-pub--id-to-file (id)
  "Return the absolute file path containing org-roam node ID, or nil.

ID must be a string (a UUID).  Non-string input returns nil without error.

Wraps `org-roam-id-find', which performs a SQLite lookup against the
org-roam DB and returns either nil or a cons cell `(file . pos)' where
`file' is the absolute path and `pos' is the buffer position of the
heading carrying the id.  This wrapper extracts and returns the path.

Caught during Task 19 spot-check: the cl-letf test stubs returned plain
strings, masking the cons-cell shape of the real org-roam API.  Defensive
string-fallback retained for hypothetical alternate org-roam versions.

The DB is snapshotted at publish start (see `a3madkour-pub/begin-publish');
IDs created mid-run are NOT visible until the next snapshot."
  (when (stringp id)
    (let ((result (org-roam-id-find id)))
      (cond
       ((null result) nil)
       ((consp result) (car result))   ; real org-roam: (file . pos)
       ((stringp result) result)        ; defensive: string return
       (t (error "a3madkour-pub--id-to-file: unexpected org-roam-id-find return %S"
                 result))))))

(provide 'a3madkour-publish-id)

;;; a3madkour-publish-id.el ends here
