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
                                    &key name on-done stderr-buf stdout-buf cwd)
  "Spawn CMD with ARGS; invoke ON-DONE with (rc captured-tail) when done.

NAME defaults to CMD (used for process + stderr buffer names).
STDERR-BUF defaults to a buffer named `*a3-pub-stderr <name>*'.  When
the function auto-creates the buffer, it is killed after ON-DONE fires
so long sessions don't leak buffers.  When the caller passes STDERR-BUF
explicitly, the buffer is left alone (caller owns lifecycle).

STDOUT-BUF, when non-nil, is used as the stdout sink and (for callers
that pass it) becomes the source for the tail string passed to ON-DONE.
When STDOUT-BUF is nil, the tail is the stderr tail (last 10 lines) —
existing behavior.  Caller-owned STDOUT-BUF is left alone on exit.

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
    (when stdout-buf
      (with-current-buffer stdout-buf
        (let ((inhibit-read-only t)) (erase-buffer))))
    (if a3-pub-async--synchronous-p
        ;; Sync test path.
        (let* ((rc (apply #'call-process cmd nil
                          (or stdout-buf stderr-buf) nil args))
               (tail (if stdout-buf
                         (with-current-buffer stdout-buf (buffer-string))
                       (with-current-buffer stderr-buf (buffer-string)))))
          (when on-done (funcall on-done rc tail))
          (when buf-auto-created (kill-buffer stderr-buf))
          nil)
      ;; Async path.
      (make-process
       :name (format "a3-pub-%s" name)
       :command (cons cmd args)
       :buffer stdout-buf
       :stderr stderr-buf
       :sentinel
       (lambda (proc _event)
         ;; Skip transient 'run'/'open' events; only exit/signal carry the rc.
         (when (memq (process-status proc) '(exit signal))
           (let* ((rc (process-exit-status proc))
                  (raw (if stdout-buf
                           (with-current-buffer stdout-buf (buffer-string))
                         (with-current-buffer stderr-buf (buffer-string))))
                  (lines (split-string raw "\n" t))
                  (tail (if stdout-buf
                            ;; stdout: full content (typically short, no truncation).
                            raw
                          ;; stderr: last 10 lines.
                          (mapconcat #'identity (last lines 10) "\n"))))
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

(defvar a3-pub-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-c") #'a3-pub-async/cancel-current-run)
    (define-key m (kbd "n") (lambda () (interactive)
                              (re-search-forward "^─\\{20,\\}$" nil t)))
    (define-key m (kbd "p") (lambda () (interactive)
                              (re-search-backward "^─\\{20,\\}$" nil t)))
    m)
  "Keymap for `a3-pub-mode'.")

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

(defvar a3-pub-async--spinner-glyphs '("⧗" "◐" "◑" "◒" "◓"))
(defvar a3-pub-async--spinner-idx 0)
(defvar a3-pub-async--spinner-timer nil)

(defun a3-pub-async--modeline-string (run)
  (cond
   ((null run) "")
   ((eq (a3-pub-async-run-status run) :cancelled)
    "[a3-pub ⨯ cancelled]")
   ((eq (a3-pub-async-run-status run) :err)
    "[a3-pub ✗ err]")
   ((eq (a3-pub-async-run-status run) :running)
    (format "[a3-pub %s %d/%d]"
            (nth a3-pub-async--spinner-idx a3-pub-async--spinner-glyphs)
            (a3-pub-async-run-completed-steps run)
            (a3-pub-async-run-planned-steps run)))
   (t "")))

(defun a3-pub-async--modeline-tick ()
  (setq a3-pub-async--spinner-idx
        (mod (1+ a3-pub-async--spinner-idx)
             (length a3-pub-async--spinner-glyphs)))
  (force-mode-line-update t))

(defun a3-pub-async--modeline-start ()
  (add-to-list 'mode-line-misc-info
               '(:eval (a3-pub-async--modeline-string a3-pub-async--in-flight-run))
               t)
  (setq a3-pub-async--spinner-timer
        (run-with-timer 0 0.25 #'a3-pub-async--modeline-tick)))

(defun a3-pub-async--modeline-stop ()
  (when a3-pub-async--spinner-timer
    (cancel-timer a3-pub-async--spinner-timer)
    (setq a3-pub-async--spinner-timer nil))
  (force-mode-line-update t))

(cl-defun a3-pub-async/begin-publish (&key scope source-label planned-steps)
  "Acquire the single-in-flight lock and start a run.

Signals user-error if a run is already in flight.  Delegates to the
existing `a3madkour-pub/begin-publish' for accumulator setup.  Returns
the new run handle."
  (when a3-pub-async--in-flight-run
    (when (fboundp 'pop-to-buffer)
      (pop-to-buffer (a3-pub-async/buffer)))
    (user-error "a3-pub: a publish is already running (see *a3-publish*)"))
  (a3madkour-pub/begin-publish)
  (let* ((buf (a3-pub-async/buffer))
         (run (make-a3-pub-async-run
               :id (gensym "a3-pub-run-")
               :scope scope
               :source-label (or source-label "")
               :buffer buf
               :section-start nil
               :live-processes nil
               :tmp-dirs nil
               :start-time (current-time)
               :planned-steps (or planned-steps 0)
               :completed-steps 0
               :status :running)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert "\n───────────────────────────────────────────────\n")
        (insert (format-time-string "%Y-%m-%d %H:%M:%S  ")
                (format "publish-%s  %s\n" scope (or source-label "")))
        (insert "───────────────────────────────────────────────\n")
        (setf (a3-pub-async-run-section-start run) (point))))
    (setq a3-pub-async--in-flight-run run)
    (a3-pub-async--modeline-start)
    (display-buffer buf '((display-buffer-in-side-window)
                          (side . bottom) (window-height . 0.25)))
    run))

(cl-defun a3-pub-async/finish-publish (run &key scope status)
  "End the publish run.

Calls the existing `a3madkour-pub/finish-publish'.  When STATUS=ok and
SCOPE=deliberate, flushes citations YAML.  Always releases the lock and
clears the mode-line indicator."
  (let* ((elapsed (float-time
                   (time-subtract (current-time)
                                  (a3-pub-async-run-start-time run))))
         ;; Normalize STATUS arg ('ok, 'err, 'cancelled) into the run
         ;; struct's keyword form (:ok, :err, :cancelled), matching the
         ;; struct's :running / :pending vocabulary.
         (status-kw (pcase status
                      ('ok :ok)
                      ('err :err)
                      ('cancelled :cancelled)
                      (_ status))))
    (setf (a3-pub-async-run-status run) status-kw)
    (unwind-protect
        (progn
          (a3madkour-pub/finish-publish :scope scope)
          ;; Citations flush fires on both deliberate and living per the
          ;; original F slice behavior (a3-publish-deliberate AND
          ;; a3-publish-living both tail-called emit-yaml).  Gated on
          ;; status=ok only — cancelled / err skip the flush.
          (when (eq status 'ok)
            (when (require 'a3madkour-publish-citations nil 'noerror)
              (a3madkour-pub-citations/emit-yaml :mode 'merge))))
      (setq a3-pub-async--in-flight-run nil)
      (a3-pub-async--modeline-stop))
    ;; Append summary.
    (let ((buf (a3-pub-async-run-buffer run)))
      (when (and buf (buffer-live-p buf))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (insert (format "  ── publish %s  (%.1fs)\n"
                            (pcase status
                              ('ok "✓ ok")
                              ('err "✗ err")
                              ('cancelled "⨯ cancelled")
                              (_ "?"))
                            elapsed))))))
    (message "a3-pub: %s (%.1fs)" status elapsed)))

(defun a3-pub-async/cancel-current-run ()
  "Cancel the in-flight run, if any.
Sends SIGINT to every live process; status flag set first so sentinels
firing in the next ms short-circuit.  Tmp dirs cleaned, accumulator
discarded by finish-publish."
  (interactive)
  (let ((run a3-pub-async--in-flight-run))
    (when run
      (setf (a3-pub-async-run-status run) :cancelled)
      (dolist (p (a3-pub-async-run-live-processes run))
        (when (and (processp p) (process-live-p p))
          (ignore-errors (interrupt-process p))))
      ;; SIGKILL fallback after 2s.
      (run-with-timer
       2 nil
       (lambda ()
         (dolist (p (a3-pub-async-run-live-processes run))
           (when (and (processp p) (process-live-p p))
             (ignore-errors (kill-process p))))))
      (dolist (d (a3-pub-async-run-tmp-dirs run))
        (when (and d (file-directory-p d))
          (ignore-errors (delete-directory d t))))
      (message "a3-pub: cancel requested")
      t)))

(defmacro with-a3-pub-async-sync (&rest body)
  "Run BODY with the async helpers in sync mode."
  (declare (indent 0))
  `(let ((a3-pub-async--synchronous-p t)) ,@body))

(provide 'a3madkour-publish-async)
;;; a3madkour-publish-async.el ends here
