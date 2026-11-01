;;; a3madkour-publish-living.el --- publish-living top-level command  -*- lexical-binding: t; -*-

;;; Commentary:

;; Top-level command for sub-project B's living-surfaces publish.
;; Wraps the begin/walk/finish lifecycle around every section that
;; `a3madkour-pub-registry' marks `:mode living'.
;;
;; Handlers are named by symbol in the registry and resolved at dispatch.
;; A registered handler that is not loaded is a loud per-file error: the
;; file reports `err' and the run buffer logs `handler-missing' naming the
;; function.  It used to be a silent skip, which made the section's pages
;; look removed to the orphan sweep (S1 row 9).
;;
;; Idempotency contract (per design spec §11): running with no source
;; changes produces zero file diffs in content/ + data/.

;;; Code:

(require 'a3madkour-publish)
(require 'a3madkour-publish-paths)
(require 'a3madkour-publish-registry)
(require 'a3madkour-publish-async)
(require 'a3madkour-publish-unpublish)
(require 'a3madkour-publish-author)    ; the contract gate
(require 'a3madkour-library-items)     ; the item-note `:site:' gate
(require 'a3madkour-publish-library-notes) ; the shelf collector

(defun a3madkour-pub-living--collect-triples ()
  "Return (section file handler) triples for every living-section file
under `a3madkour-pub/org-notes-dir'.

Walks the notes tree exactly once.  HANDLER is the registry's symbol; it
is not checked here (see `a3madkour-pub-living--dispatch')."
  (let ((triples nil))
    (dolist (file (directory-files-recursively
                   (a3madkour-pub/path 'a3madkour-pub/org-notes-dir) "\\.org\\'"))
      (let ((section (a3madkour-pub/note-section file)))
        (when section
          (let ((handler (a3madkour-pub-registry/handler section 'living)))
            (when handler
              (push (list section file handler) triples))))))
    (nreverse triples)))

(defun a3madkour-pub-living/contract-gap (file section)
  "Why FILE cannot publish under SECTION's contract, or nil when it can.
A library item note is refused first when SECTION is not garden (only
the garden handler narrows a note to its `:site:' section; any other
would publish the whole note), then when it has no usable `:site:'
section: there is nothing in it that may publish.  A missing file is
left to its handler to report.  A note not marked to publish (no
`#+HUGO_PUBLISH:' state) owes no contract: its handler withdraws it."
  (when (and (file-readable-p file)
             (a3madkour-pub/published-p file))
    (cond
     ((and (a3madkour-library/item-p file) (not (equal section "garden")))
      (format "%s: library item notes publish only to garden (section %s)"
              file section))
     ((and (a3madkour-library/item-p file)
           (not (a3madkour-library/site-body file)))
      (format "%s: library item has no :site: section; write one, then publish"
              file))
     (t
      (condition-case err
          (let ((missing (a3madkour-pub-author/missing-required file section)))
            (when missing
              (format "%s: missing required %s for %s; run M-x a3-publish-mark"
                      file (string-join missing ", ") section)))
        (user-error (format "%s: %s" file (error-message-string err))))))))

(defun a3madkour-pub-living--library-item-files (triples)
  "The live garden library item notes among TRIPLES' files.
These are what the shelf collector reads; drafts are left out."
  (cl-loop for (section file _handler) in triples
           when (and (equal section "garden")
                     (file-readable-p file)
                     (eq (a3madkour-pub/published-p file) 'live)
                     (a3madkour-library/item-p file))
           collect file))

(defun a3madkour-pub-living--build-shelves (triples run)
  "Rebuild the library shelves from TRIPLES' item notes; return \='ok or \='err.
An error is logged to RUN as a `library-shelves' step, never signalled,
so the run still finishes."
  (condition-case err
      (progn
        (a3madkour-pub-library-notes/build-shelves
         (a3madkour-pub-living--library-item-files triples))
        'ok)
    (error
     (let ((msg (format "library shelves: %s" (error-message-string err))))
       (message "a3-publish-living: %s" msg)
       (a3-pub-async/log-step run "library-shelves" :err :err-snippet msg)
       'err))))

(defun a3madkour-pub-living--dispatch (triple run report)
  "Run TRIPLE's handler on its file, reporting the outcome via REPORT.
A handler that is not `fboundp' reports `err' and logs a
`handler-missing' step naming the function.  A file lacking a field its
section requires reports `err' and logs a `contract' step instead of
publishing a bundle the site would reject (S1 row 24)."
  (let* ((section (nth 0 triple))
         (file (nth 1 triple))
         (handler (nth 2 triple))
         (gap (and (fboundp handler)
                   (a3madkour-pub-living/contract-gap file section))))
    (cond
     ((not (fboundp handler))
      (let ((msg (format "%s: handler `%s' for section %s is not loaded"
                         file handler section)))
        (message "a3-publish-living: %s" msg)
        (a3-pub-async/log-step run "handler-missing" :err :err-snippet msg)
        (funcall report 'err)))
     (gap
      (message "a3-publish-living: %s" gap)
      (a3-pub-async/log-step run "contract" :err :err-snippet gap)
      (funcall report 'err))
     (t
      (condition-case _err
          (funcall handler file run
                   :on-done (lambda (s) (funcall report s)))
        (error (funcall report 'err)))))))

;;;###autoload
(defun a3-publish-living ()
  "Publish all living-section source notes from `org-notes-dir'.

Async lifecycle: walks every living section's source set into a flat
\(section file handler) triple list, dispatches each in parallel, and
rebuilds the library shelves once after the barrier reports done, then
calls finish-publish."
  (interactive)
  (let* ((triples (a3madkour-pub-living--collect-triples))
         (n (length triples))
         (run (a3-pub-async/begin-publish
               :scope 'living
               :source-label (format "living (%d notes)" n)
               :planned-steps n)))
    (let ((on-all-done
           ;; The shelves are collected after every handler (their rows need
           ;; the garden bundles) and before finish-publish, even on an
           ;; empty run: a library with nothing shared must empty.
           (lambda (results)
             (let* ((shelves (a3madkour-pub-living--build-shelves triples run))
                    (status (if (or (eq shelves 'err) (memq 'err results))
                                'err 'ok)))
               (a3-pub-async/finish-publish
                run :scope 'living :status status)))))
      (if (zerop n)
          (funcall on-all-done nil)
        (let ((report (a3-pub-async/barrier n :on-all-done on-all-done)))
          (dolist (triple triples)
            (a3madkour-pub-living--dispatch triple run report)))))))

(provide 'a3madkour-publish-living)

;;; a3madkour-publish-living.el ends here
