;;; a3madkour-agents.el --- Helpers for agent-shell and its extensions -*- lexical-binding: t; -*-

;;; Commentary:

;; Named, testable pieces of the agent-shell setup wired up in config.org
;; (* "AI" "Agents").  See docs/superpowers/specs/2026-10-11-agent-shell-only-design.md.

;;; Code:

(require 'cl-lib)
(require 'map)
(require 'seq)
(require 'subr-x)

(defgroup a3madkour-agents nil
  "Personal glue for agent-shell."
  :group 'tools)

(defvar agent-shell--state)

;;;; Advice

(defun a3madkour-agents--project-files-truename (orig-fn &rest args)
  "Call ORIG-FN with ARGS, `default-directory' resolved through symlinks.
project.el does not find projects reached through a symlinked directory."
  (let ((default-directory (file-truename default-directory)))
    (apply orig-fn args)))

(defun a3madkour-agents--opencode-diff-info (orig-fn &rest args)
  "Call ORIG-FN with ARGS; fall back to OpenCode's diff keys.
OpenCode sends oldString/newString/filePath where agent-shell expects
old_str/new_str/path."
  (or (apply orig-fn args)
      (when-let* ((acp-tool-call (plist-get args :acp-tool-call))
                  (raw-input (map-elt acp-tool-call 'rawInput))
                  (new-text (map-elt raw-input 'newString))
                  (old-text (or (map-elt raw-input 'oldString) "")))
        (append (list (cons :old old-text)
                      (cons :new new-text))
                (when-let* ((path (or (map-elt raw-input 'filePath)
                                      (map-elt raw-input 'filepath))))
                  (list (cons :file path)))))))

(defun a3madkour-agents--opencode-permission-title (orig-fn &rest args)
  "Call ORIG-FN with ARGS; recover OpenCode's bash command when generic.
OpenCode sends an empty rawInput in bash permission requests, so the
title degrades to \"bash\"/\"execute\".  Use the command saved when the
tool call was announced instead."
  (let ((result (apply orig-fn args)))
    (if (and result
             (not (string= result "bash"))
             (not (string= result "execute")))
        result
      (when-let* ((acp-request (plist-get args :acp-request))
                  (tool-call-id (map-nested-elt acp-request
                                                '(params toolCall toolCallId)))
                  (saved (map-nested-elt agent-shell--state
                                         (list :tool-calls tool-call-id)))
                  (command (map-elt saved :command)))
        (if (equal (map-elt saved :kind) "execute")
            (concat "```console\n" command "\n```")
          command)))))

;;;; Prerequisites

(defcustom a3madkour-agents-required-executables
  '(("claude-agent-acp" . "npm i -g @zed-industries/claude-agent-acp")
    ("codex-acp" . "install the Codex ACP adapter (codex-acp) for SPC a n c")
    ("terminal-notifier" . "brew install terminal-notifier (optional: macext banners)"))
  "External programs the agent setup expects, as (NAMES . HINT).
NAMES is a program name, or a list of names any one of which suffices."
  :type '(repeat (cons (choice string (repeat string)) string))
  :group 'a3madkour-agents)

(defvar a3madkour-agents--prereqs-checked nil
  "Non-nil once `a3madkour-agents-check-prereqs' has run this session.")

(defun a3madkour-agents-missing-executables (&optional specs)
  "Return the entries of SPECS whose programs are all missing from `exec-path'.
SPECS defaults to `a3madkour-agents-required-executables'."
  (seq-remove (lambda (spec)
                (seq-some #'executable-find (ensure-list (car spec))))
              (or specs a3madkour-agents-required-executables)))

(defun a3madkour-agents-check-prereqs ()
  "Warn once per session about each missing external program."
  (unless a3madkour-agents--prereqs-checked
    (setq a3madkour-agents--prereqs-checked t)
    (dolist (spec (a3madkour-agents-missing-executables))
      (display-warning 'a3madkour-agents
                       (format "%s not found: %s"
                               (string-join (ensure-list (car spec)) "/")
                               (cdr spec))
                       :warning))))

;;;; Optional commands
;;
;; Phase 2 packages are bound in the leader map from Phase 1 on.  Until
;; they load, these say so instead of signalling `void-function'.

(defun a3madkour-agents--call-optional (target package)
  "Call TARGET interactively if defined, else explain PACKAGE is missing."
  (if (fboundp target)
      (call-interactively target)
    (user-error "%s is not installed/configured yet (Phase 2 of the agent-shell spec)"
                package)))

(defmacro a3madkour-agents-define-optional (name target package)
  "Define command NAME that runs TARGET from PACKAGE when it is available."
  `(defun ,name ()
     ,(format "Run `%s' (%s), or say it is not set up yet." target package)
     (interactive)
     (a3madkour-agents--call-optional ',target ,package)))

(a3madkour-agents-define-optional a3madkour-agents-meta-session
  meta-agent-shell-start "meta-agent-shell")
(a3madkour-agents-define-optional a3madkour-agents-meta-dispatcher
  meta-agent-shell-start-or-dispatcher "meta-agent-shell")
(a3madkour-agents-define-optional a3madkour-agents-meta-close-dispatcher
  meta-agent-shell-close-dispatcher "meta-agent-shell")
(a3madkour-agents-define-optional a3madkour-agents-meta-heartbeat-start
  meta-agent-shell-heartbeat-start "meta-agent-shell")
(a3madkour-agents-define-optional a3madkour-agents-meta-heartbeat-stop
  meta-agent-shell-heartbeat-stop "meta-agent-shell")
(a3madkour-agents-define-optional a3madkour-agents-meta-heartbeat-now
  meta-agent-shell-heartbeat-send-now "meta-agent-shell")
(a3madkour-agents-define-optional a3madkour-agents-meta-big-red-button
  meta-agent-shell-big-red-button "meta-agent-shell")
(a3madkour-agents-define-optional a3madkour-agents-slack-connect-cmd
  a3madkour-agents-slack-connect "agent-shell-to-go")
(a3madkour-agents-define-optional a3madkour-agents-slack-reconnect-buffer
  agent-shell-to-go-reconnect-buffer "agent-shell-to-go")
(a3madkour-agents-define-optional a3madkour-agents-slack-reconnect-all
  agent-shell-to-go-reconnect-all "agent-shell-to-go")
(a3madkour-agents-define-optional a3madkour-agents-slack-list-threads
  agent-shell-to-go-list-threads "agent-shell-to-go")
(a3madkour-agents-define-optional a3madkour-agents-slack-send-image
  agent-shell-to-go-send-image "agent-shell-to-go")
(a3madkour-agents-define-optional a3madkour-agents-slack-cleanup
  agent-shell-to-go-cleanup-old-threads "agent-shell-to-go")
(a3madkour-agents-define-optional a3madkour-agents-circus-toggle-cmd
  a3madkour-agents-circus-toggle "agent-circus")

;;;; Perspectives
;;
;; Manager and attention list sessions from every perspective.  Jumping
;; should land in the session's own perspective rather than pull its
;; buffer into the current one.

(defvar persp-mode)
(declare-function persp-current-name "perspective")
(declare-function persp-names "perspective")
(declare-function persp-get-buffers "perspective")
(declare-function persp-switch "perspective")
(declare-function tabulated-list-get-id "tabulated-list")

(defun a3madkour-agents-persp-owner (buffer)
  "Name of a perspective other than the current one holding BUFFER, or nil.
Nil when `persp-mode' is off or the current perspective holds BUFFER."
  (when (and (bound-and-true-p persp-mode) (buffer-live-p buffer))
    (let ((current (persp-current-name)))
      (unless (memq buffer (persp-get-buffers current))
        (seq-find (lambda (name)
                    (and (not (equal name current))
                         (memq buffer (persp-get-buffers name))))
                  (persp-names))))))

(defun a3madkour-agents-switch-to-owner-persp (buffer)
  "Switch to the perspective owning BUFFER, if it is not the current one."
  (when-let* ((name (a3madkour-agents-persp-owner buffer)))
    (persp-switch name)))

(defun a3madkour-agents--manager-goto-persp (&rest _)
  "Before `agent-shell-manager-goto': switch to the row buffer's perspective."
  (let ((buffer (tabulated-list-get-id)))
    (when (bufferp buffer)
      (a3madkour-agents-switch-to-owner-persp buffer))))

;;;; Evil remaps for extension list buffers
;;
;; evil-collection starts tabulated-list buffers in normal state, which
;; shadows the packages' single-letter keys.  Rebind them in normal
;; state; keys that collide with evil movement move (k -> x, j -> J).

(declare-function evil-define-key* "evil-core")
(declare-function evil-set-initial-state "evil-core")

(defconst a3madkour-agents-evil-bindings
  '((agent-shell-manager-mode-map
     agent-shell-manager-mode
     (("RET" . agent-shell-manager-goto)
      ("x" . agent-shell-manager-kill)
      ("c" . agent-shell-manager-new)
      ("r" . agent-shell-manager-restart)
      ("d" . agent-shell-manager-delete-killed)
      ("m" . agent-shell-manager-set-mode)
      ("M" . agent-shell-manager-set-model)
      ("t" . agent-shell-manager-view-traffic)
      ("l" . agent-shell-manager-toggle-logging)
      ("gr" . agent-shell-manager-refresh)
      ("q" . quit-window)
      ("C-c C-c" . agent-shell-manager-interrupt)))
    (agent-shell-attention-dashboard-mode-map
     agent-shell-attention-dashboard-mode
     (("RET" . agent-shell-attention-dashboard-visit)
      ("o" . agent-shell-attention-dashboard-visit-other-window)
      ("J" . agent-shell-attention-dashboard-open-ambient-directory)
      ("D" . agent-shell-attention-dashboard-kill-session)
      ("gr" . agent-shell-attention-dashboard-refresh)
      ("q" . quit-window)))
    (agent-review-mode-map
     agent-review-mode
     (("RET" . agent-review-jump-to-issue)
      ("m" . agent-review-mark)
      ("u" . agent-review-unmark)
      ("M" . agent-review-mark-all)
      ("U" . agent-review-unmark-all)
      ("S" . agent-review-send-to-agent-shell)
      ("W" . agent-review-copy-issues)
      ("gr" . agent-review-refresh)
      ("q" . quit-window))))
  "Normal-state bindings per keymap, as (MAP-SYMBOL MODE ((KEY . COMMAND) ...)).")

(defun a3madkour-agents-evil-bind (map-symbol)
  "Apply the normal-state bindings listed for MAP-SYMBOL.
See `a3madkour-agents-evil-bindings'."
  (pcase-let ((`(,_ ,mode ,bindings) (assq map-symbol a3madkour-agents-evil-bindings)))
    (when mode
      (evil-set-initial-state mode 'normal))
    (let ((map (symbol-value map-symbol)))
      (pcase-dolist (`(,key . ,command) bindings)
        (evil-define-key* 'normal map (kbd key) command)))))

(provide 'a3madkour-agents)
;;; a3madkour-agents.el ends here
