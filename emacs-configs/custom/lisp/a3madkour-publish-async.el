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

(provide 'a3madkour-publish-async)
;;; a3madkour-publish-async.el ends here
