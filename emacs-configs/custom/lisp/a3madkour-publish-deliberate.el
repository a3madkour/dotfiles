;;; a3madkour-publish-deliberate.el --- publish-deliberate top-level command  -*- lexical-binding: t; -*-

;;; Commentary:

;; Top-level command for sub-project B's deliberate-surfaces publish.
;; Async lifecycle: `a3-publish-deliberate' returns immediately after
;; dispatching the handler.  The handler is responsible for calling its
;; :on-done callback when its sentinel chain completes; finish-publish
;; then fires.

;;; Code:

(require 'a3madkour-publish)
(require 'a3madkour-publish-async)
(require 'a3madkour-publish-unpublish)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-essays)

(defvar a3madkour-pub-deliberate--handlers
  '((essays . a3madkour-pub-essays/publish-essay-file))
  "Alist of (SECTION-SYMBOL . HANDLER-FUNCTION).
Handler signature: (file run &key on-done).")

;;;###autoload
(defun a3-publish-deliberate (file-or-id)
  "Publish a single deliberate-section note identified by FILE-OR-ID.

Async lifecycle: returns immediately after dispatching the handler.
The handler is responsible for calling its :on-done callback when its
sentinel chain completes; finish-publish then fires."
  (interactive "fOrg file or ID: ")
  (let* ((file (a3madkour-pub--resolve-file-or-id file-or-id))
         (section (a3madkour-pub/note-section file))
         (handler (cdr (assq (intern (or section "")) a3madkour-pub-deliberate--handlers))))
    (unless handler
      (error "a3madkour-pub-deliberate: no handler registered for section %S (file: %s)"
             section file))
    (let* ((planned-steps-fn (intern (format "%s/planned-steps" handler)))
           (planned (if (fboundp planned-steps-fn)
                        (funcall planned-steps-fn file)
                      5))
           (run (a3-pub-async/begin-publish
                 :scope 'deliberate
                 :source-label (format "%s/%s" section (file-name-base file))
                 :planned-steps planned)))
      (condition-case err
          (funcall handler file run
                   :on-done
                   (lambda (status)
                     (a3-pub-async/finish-publish run
                                                  :scope 'deliberate
                                                  :status status)))
        (error
         (a3-pub-async/log-step run "handler-error" :err
                                :err-snippet (error-message-string err))
         (a3-pub-async/finish-publish run :scope 'deliberate :status 'err))))))

;;;###autoload
(defun a3-unpublish-deliberate (file-or-id)
  "Unpublish a single deliberate-section note identified by FILE-OR-ID.

Recovery command — composes the existing unpublish primitives:
  1. Resolve FILE-OR-ID to a manifest entry by id.
  2. Delete the Hugo content bundle at `<content-root>/<section>/<slug>/'.
  3. Record the manifest entry as `removed'.

Runs synchronously (no async-publish UI buffer / mode-line spinner) since
recovery wants immediate feedback. After it returns, the author should
run `a3-pub.sh --publish-living' if data files (citations.yaml, etc.)
need refreshing — this command does not touch any per-section data
aggregates.

Refuses to operate on living-section notes (garden / library / research)
— those should be unpublished by removing `#+HUGO_PUBLISH: t' from the
source and re-running publish-living, which lets the diff handle the
removal naturally.

Failure modes (all signal `user-error', manifest stays untouched):
  - id not in manifest                  → \"no manifest entry\"
  - manifest entry already `removed'    → \"already unpublished\"
  - section not in deliberate handlers  → \"section %s is not deliberate\"
  - bundle delete signalled error       → \"bundle delete failed\"

A bundle that is already absent (stale manifest) is NOT a failure — the
manifest is still advanced to `removed' so the state converges."
  (interactive "sOrg file or ID: ")
  (let* ((id (a3madkour-pub-deliberate--resolve-to-id file-or-id))
         (manifest (a3madkour-pub-history/read-manifest))
         (notes (alist-get 'notes manifest))
         (idx (and id (a3madkour-pub-history--find-note-by-id notes id)))
         (entry (and idx (aref notes idx)))
         (state (and entry (alist-get 'state entry)))
         (url (and entry (alist-get 'current_url entry)))
         (parts (and url (a3madkour-pub--unpublish-url-to-section-slug url))))
    (unless id
      (user-error "a3-unpublish-deliberate: could not resolve %S to an id"
                  file-or-id))
    (unless entry
      (user-error "a3-unpublish-deliberate: no manifest entry for id %s" id))
    (when (equal state "removed")
      (user-error "a3-unpublish-deliberate: %s is already unpublished (state=removed)"
                  id))
    (unless parts
      (user-error "a3-unpublish-deliberate: manifest URL %S is malformed" url))
    (let ((section (car parts)))
      (unless (assq (intern section) a3madkour-pub-deliberate--handlers)
        (user-error "a3-unpublish-deliberate: section %s is not deliberate \
(use publish-living + unmark `#+HUGO_PUBLISH:' instead)" section)))
    (let ((delete-result
           (a3madkour-pub--unpublish-delete-bundle (car parts) (cdr parts))))
      (when (eq delete-result 'failed)
        (user-error "a3-unpublish-deliberate: bundle delete failed at %s \
(see *Messages*; manifest left unchanged)" url)))
    (a3madkour-pub-history/record-publish id nil 'removed)
    (message "[a3-pub] unpublished %s (id %s)" url id)
    (list :id id :url url :section (car parts) :slug (cdr parts))))

(defun a3madkour-pub-deliberate--resolve-to-id (file-or-id)
  "Return the manifest id for FILE-OR-ID, or nil if unresolvable.

Resolution rules:
  - nil                                → nil
  - non-string                         → nil
  - empty string                       → nil
  - existing file path                 → `a3madkour-pub/note-metadata' id lookup
  - anything else (incl. UUIDs / opaque id strings) → returned verbatim

The file-existence check is the discriminator: recovery often runs
after the source file is gone, so a bare id string is the recovery
input.  Non-UUID ids are accepted because the manifest contract does
not require UUID format."
  (cond
   ((or (null file-or-id) (not (stringp file-or-id)) (string-empty-p file-or-id))
    nil)
   ((file-exists-p file-or-id)
    (plist-get (a3madkour-pub/note-metadata file-or-id) :id))
   (t file-or-id)))

(provide 'a3madkour-publish-deliberate)

;;; a3madkour-publish-deliberate.el ends here
