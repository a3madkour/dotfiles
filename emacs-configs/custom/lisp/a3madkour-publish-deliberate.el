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

(provide 'a3madkour-publish-deliberate)

;;; a3madkour-publish-deliberate.el ends here
