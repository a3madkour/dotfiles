;;; a3madkour-publish-async.el --- async publish pipeline runtime -*- lexical-binding: t; -*-
;;; Commentary:
;;; Async runtime for the publish pipeline.  See
;;; ~/dotfiles/emacs-configs/custom/docs/superpowers/specs/2026-06-06-async-publish-pipeline-design.md.
;;;
;;; Public API:
;;;   - a3-pub-async/run-process   — make-process wrapper with sentinel
;;;   - a3-pub-async/barrier       — N-way join
;;;   - a3-pub-async/begin-publish — start a run; acquires the lifecycle lock
;;;   - a3-pub-async/finish-publish — end a run; releases the lock
;;;   - a3-pub-async/log-step      — append a step line to *a3-publish*
;;;   - a3-pub-async/cancel-current-run — C-c C-c entry point
;;;
;;; Tests opt into synchronous mode via the dynamic var
;;; `a3-pub-async--synchronous-p' so the existing 543-test suite keeps
;;; working without async-aware fixtures.
;;; Code:

(require 'cl-lib)

(defgroup a3-pub-async nil
  "Async publish pipeline runtime."
  :group 'a3madkour-pub)

(defvar a3-pub-async--synchronous-p nil
  "When non-nil, the async helpers run their subprocess calls via
`call-process' and invoke `on-done' inline.  Existing ert tests
bind this to t via `with-a3-pub-async-sync' so their `cl-letf'
stubs continue to fire.")

(cl-defun a3-pub-async/run-process (cmd args
                                    &key name on-done stderr-buf cwd)
  "Spawn CMD with ARGS; invoke ON-DONE with (rc stderr-tail) when done.

NAME defaults to CMD (used for process + stderr buffer names).
STDERR-BUF defaults to a buffer named `*a3-pub-stderr <name>*'.  When
the function auto-creates the buffer, it is killed after ON-DONE fires
so long sessions don't leak buffers.  When the caller passes STDERR-BUF
explicitly, the buffer is left alone (caller owns lifecycle).
CWD, when non-nil, sets `default-directory' for the spawn.

When `a3-pub-async--synchronous-p' is non-nil, runs `call-process'
inline and fires ON-DONE in the calling frame (test path)."
  (let* ((name (or name cmd))
         (buf-auto-created (not stderr-buf))
         (stderr-buf (or stderr-buf
                         (get-buffer-create (format "*a3-pub-stderr %s*" name))))
         (default-directory (or cwd default-directory)))
    ;; Start each call with a clean stderr buffer so caller-side
    ;; :name reuse can't leak stale content into on-done's tail arg.
    (with-current-buffer stderr-buf
      (let ((inhibit-read-only t)) (erase-buffer)))
    (if a3-pub-async--synchronous-p
        ;; Sync test path.
        (let ((rc (apply #'call-process cmd nil stderr-buf nil args))
              (tail (with-current-buffer stderr-buf (buffer-string))))
          (when on-done (funcall on-done rc tail))
          (when buf-auto-created (kill-buffer stderr-buf))
          nil)
      ;; Async path.
      (make-process
       :name (format "a3-pub-%s" name)
       :command (cons cmd args)
       :buffer nil
       :stderr stderr-buf
       :sentinel
       (lambda (proc _event)
         ;; Skip transient 'run'/'open' events; only exit/signal carry the rc.
         (when (memq (process-status proc) '(exit signal))
           (let* ((rc (process-exit-status proc))
                  (raw (with-current-buffer stderr-buf (buffer-string)))
                  (lines (split-string raw "\n" t))
                  (tail (mapconcat #'identity (last lines 10) "\n")))
             (when on-done (funcall on-done rc tail))
             (when buf-auto-created (kill-buffer stderr-buf)))))))))

(provide 'a3madkour-publish-async)
;;; a3madkour-publish-async.el ends here
