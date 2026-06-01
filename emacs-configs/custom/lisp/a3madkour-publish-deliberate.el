;;; a3madkour-publish-deliberate.el --- publish-deliberate top-level command  -*- lexical-binding: t; -*-

;;; Commentary:

;; Top-level command for sub-project B's deliberate-surfaces publish.
;; Wraps the begin/finish lifecycle around a SINGLE per-section handler
;; invocation, scoped to one source file (or org-roam ID resolved to a
;; file).  Intended for human-reviewed publishes (essays, works items,
;; streams items, about).
;;
;; B.0 ships the lifecycle scaffold with an empty handler registry.
;; B.4 (essays) is the first slice to register a handler.

;;; Code:

(require 'a3madkour-publish)
(require 'a3madkour-publish-unpublish)
(require 'a3madkour-publish-essays)

(defvar a3madkour-pub-deliberate--handlers
  '((essays . a3madkour-pub-essays/publish-essay-file))
  "Alist of (SECTION-SYMBOL . HANDLER-FUNCTION) for deliberate sections.

HANDLER-FUNCTION takes one argument (a source file path) and emits the
corresponding Hugo content + calls `record-publish'.

Same shape as `a3madkour-pub-living--handlers' but a separate registry
because some sections might exist in both (uncommon but possible).
B.4 registers `essays'; B.5 (works), B.6 (streams), B.7 (about) each
add their own entry.")

;;;###autoload
(defun a3-publish-deliberate (file-or-id)
  "Publish a single deliberate-section note identified by FILE-OR-ID.

FILE-OR-ID is either an absolute file path to a `.org' source file or an
org-roam UUID string.  Reads `#+HUGO_SECTION:' from the file; dispatches
to the handler registered in `a3madkour-pub-deliberate--handlers' for
that section.

B.0: every section's handler is unregistered, so this signals `error'
with a clear message naming the section that lacks a handler.  This is
expected; B.4+ adds handlers per section.

See parent design spec §4 (command surface)."
  (interactive "fOrg file or ID: ")
  (a3madkour-pub/begin-publish)
  (unwind-protect
      (let* ((file (a3madkour-pub--resolve-file-or-id file-or-id))
             (section (a3madkour-pub/note-section file))
             (handler (cdr (assq section a3madkour-pub-deliberate--handlers))))
        (unless handler
          (error "a3madkour-pub-deliberate: no handler registered for section %S (file: %s)"
                 section file))
        (funcall handler file))
    (a3madkour-pub/finish-publish :scope 'deliberate)))

(provide 'a3madkour-publish-deliberate)

;;; a3madkour-publish-deliberate.el ends here
