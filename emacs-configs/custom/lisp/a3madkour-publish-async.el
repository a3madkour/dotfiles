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

(cl-defun a3-pub-async/barrier (n &key on-all-done)
  "Return a 1-arg report function.  After N calls, fires ON-ALL-DONE
with the list of reports in call order.  N=0 fires immediately.
Calls beyond N are silently ignored (defensive against double-fire)."
  (let ((remaining n)
        (results nil))
    (if (zerop n)
        (progn (when on-all-done (funcall on-all-done nil)) (lambda (_) nil))
      (lambda (result)
        (when (> remaining 0)
          (setq remaining (1- remaining))
          (push result results)
          (when (zerop remaining)
            (when on-all-done
              (funcall on-all-done (nreverse results)))))))))

(cl-defstruct a3-pub-async-run
  id              ; symbol or string, unique per run
  scope           ; 'deliberate or 'living
  source-label    ; "essays/example-multi" — surfaced in buffer header
  buffer          ; *a3-publish* buffer
  section-start   ; point in buffer where this run's section begins
  live-processes  ; list of live process objects, for cancel
  tmp-dirs        ; list of dirs to delete on cancel
  start-time      ; (current-time)
  planned-steps   ; integer
  completed-steps ; integer
  status)         ; :running / :ok / :err / :cancelled

(defvar a3-pub-async--in-flight-run nil
  "The active run handle, or nil when no publish is in flight.")

(defconst a3-pub-async--buffer-name "*a3-publish*")

(define-derived-mode a3-pub-mode special-mode "a3-pub"
  "Major mode for the *a3-publish* status buffer."
  (setq buffer-read-only t
        truncate-lines t))

(defun a3-pub-async/buffer ()
  "Return (creating if needed) the *a3-publish* status buffer."
  (let ((buf (get-buffer-create a3-pub-async--buffer-name)))
    (with-current-buffer buf
      (unless (eq major-mode 'a3-pub-mode) (a3-pub-mode)))
    buf))

(defun a3-pub-async--status-glyph (status)
  (pcase status
    (:running   "·")
    (:ok        "✓")
    (:err       "✗")
    (:cancelled "⨯")
    (:pending   " ")
    (_           "?")))

(cl-defun a3-pub-async/log-step (run label status &key detail elapsed err-snippet)
  "Append a step line to RUN's buffer.
LABEL is the step name (e.g. \"xelatex\"); DETAIL is the trailing
column (e.g. \"pass 2/4\"); ELAPSED is seconds (float).
ERR-SNIPPET, when non-nil, is inlined on the next line indented 14 cols."
  (let ((buf (a3-pub-async-run-buffer run)))
    (when (and buf (buffer-live-p buf))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (let ((rhs (cond
                      ((eq status :running) "[running]")
                      ((eq status :pending) "[pending]")
                      (elapsed (format "(%4.1fs)" elapsed))
                      (t ""))))
            (insert (format "  [%s] %-18s %-32s %s\n"
                            (a3-pub-async--status-glyph status)
                            label
                            (or detail "")
                            rhs)))
          (when err-snippet
            (dolist (line (split-string err-snippet "\n" t))
              (insert (format "              %s\n" line)))))))))

(provide 'a3madkour-publish-async)
;;; a3madkour-publish-async.el ends here
