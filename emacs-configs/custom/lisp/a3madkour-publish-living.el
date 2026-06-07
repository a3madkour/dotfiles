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
(require 'a3madkour-publish-async)
(require 'a3madkour-publish-unpublish)

(defvar a3madkour-pub-living--handlers nil
  "Alist of (SECTION-STRING . HANDLER-FUNCTION) for living sections.

SECTION-STRING is the canonical `#+HUGO_SECTION:' value (e.g. `\"garden\"',
`\"library/reading\"').  Storing as a string lets the dispatcher compare
directly against `note-section''s return value with no symbol/string
bridge.

HANDLER-FUNCTION signature: (file run &key on-done).  Must call ON-DONE
exactly once with status 'ok / 'err / 'cancelled when its sentinel chain
completes.

B.0 ships this empty.  Each B.x slice that lands a living-section
handler will `add-to-list' an entry here via `with-eval-after-load'
\(see bottom of file).")

(defun a3madkour-pub-living--collect-triples ()
  "Return list of (section file handler) triples for every living-section
file under `a3madkour-pub/org-notes-dir'."
  (let (triples)
    (dolist (entry a3madkour-pub-living--handlers)
      (let ((section (car entry)) (handler (cdr entry)))
        (dolist (file (directory-files-recursively
                       a3madkour-pub/org-notes-dir "\\.org\\'"))
          (when (equal section (a3madkour-pub/note-section file))
            (push (list section file handler) triples)))))
    (nreverse triples)))

;;;###autoload
(defun a3-publish-living ()
  "Publish all living-section source notes from `org-notes-dir'.

Async lifecycle: walks every registered living-section's source set into
a flat (section file handler) triple list, dispatches each handler in
parallel, and calls finish-publish once after the barrier reports done."
  (interactive)
  (let* ((triples (a3madkour-pub-living--collect-triples))
         (n (length triples))
         (run (a3-pub-async/begin-publish
               :scope 'living
               :source-label (format "living (%d notes)" n)
               :planned-steps n)))
    (if (zerop n)
        (a3-pub-async/finish-publish run :scope 'living :status 'ok)
      (let* ((report (a3-pub-async/barrier
                      n :on-all-done
                      (lambda (results)
                        (let ((status (if (cl-some (lambda (r) (eq r 'err)) results)
                                          'err 'ok)))
                          (a3-pub-async/finish-publish
                           run :scope 'living :status status))))))
        (dolist (triple triples)
          (let ((file (nth 1 triple)) (handler (nth 2 triple)))
            (condition-case _err
                (funcall handler file run :on-done
                         (lambda (s) (funcall report s)))
              (error (funcall report 'err)))))))))

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
