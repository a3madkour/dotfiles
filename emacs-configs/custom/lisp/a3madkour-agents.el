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
    ("terminal-notifier" . "brew install terminal-notifier (optional: macext banners)")
    ("agent-shell-send" . "add straight/repos/meta-agent-shell/bin to PATH (meta-agent-shell)")
    ("agent-circus" . "uv tool install agent-circus (SPC a C)")
    (("docker" "podman") . "Docker Desktop or Podman (agent-circus)"))
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

(defun a3madkour-agents--manager-goto-persp (orig-fn &rest args)
  "`:around' advice for `agent-shell-manager-goto'.
Read the row's buffer first: `persp-switch' changes the current buffer,
so ORIG-FN would no longer find the manager's row.  When another
perspective owns the buffer, switch there and show it; else call
ORIG-FN with ARGS."
  (let* ((buffer (tabulated-list-get-id))
         (owner (and (bufferp buffer) (a3madkour-agents-persp-owner buffer))))
    (if owner
        (progn (persp-switch owner)
               (pop-to-buffer buffer))
      (apply orig-fn args))))

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

;;;; meta-agent-shell

(defvar agent-shell-cwd-function)
(defvar meta-agent-shell--pending-decorator)
(declare-function agent-shell--start "agent-shell")
(declare-function project-root "project")

(defcustom a3madkour-agents-meta-config-function
  #'agent-shell-anthropic-make-claude-code-config
  "Function returning the agent config meta-agent-shell spawns.
Spawns are unattended, so this must not prompt."
  :type 'function
  :group 'a3madkour-agents)

(defun a3madkour-agents-meta-start (&optional arg buffer-name)
  "Start a new agent shell for meta-agent-shell; return it, left current.
Meant for `meta-agent-shell-start-function', which calls it with
\(ARG BUFFER-NAME).  ARG `use-current-dir' starts in `default-directory'
instead of the project root.  BUFFER-NAME, when non-nil, names the
buffer (uniquified if taken).  Sessions are always new: an unattended
spawn must not stop at the session prompt."
  (let* ((dir default-directory)
         (agent-shell-cwd-function (if (eq arg 'use-current-dir)
                                       (lambda () dir)
                                     agent-shell-cwd-function))
         (buffer (agent-shell--start
                  :config (funcall a3madkour-agents-meta-config-function)
                  :new-session t
                  :session-strategy 'new
                  :outgoing-request-decorator
                  (bound-and-true-p meta-agent-shell--pending-decorator))))
    ;; The ACP session/new request runs after we return, so the let
    ;; above has expired; keep the directory in the buffer.
    (when (eq arg 'use-current-dir)
      (with-current-buffer buffer
        (setq-local agent-shell-cwd-function (lambda () dir))))
    (when buffer-name
      (with-current-buffer buffer
        (rename-buffer buffer-name t)))
    (set-buffer buffer)
    buffer))

(defun a3madkour-agents--meta-project-path (orig-fn &rest args)
  "Prefer project.el's root; else call ORIG-FN with ARGS.
meta-agent-shell only knows projectile."
  (or (when-let* ((project (project-current)))
        (expand-file-name (project-root project)))
      (apply orig-fn args)))

;;;; agent-circus
;;
;; Per project, run agents inside agent-circus containers.  Off by
;; default so the built-in devcontainer setup keeps working: both use
;; `agent-shell-command-prefix' and `agent-shell-path-resolver-function'.

(declare-function agent-shell-cwd "agent-shell-project")
(declare-function agent-shell-get-config "agent-shell")

(defcustom a3madkour-agents-circus-services
  '((claude-code . "claude-code")
    (codex . "codex")
    (opencode . "opencode")
    (mistral-vibe . "mistral-vibe"))
  "agent-shell identifier -> agent-circus service name."
  :type '(alist :key-type symbol :value-type string)
  :group 'a3madkour-agents)

(defconst a3madkour-agents-circus-workspace "/workspace/"
  "Project mount point inside agent-circus containers.")

(defvar a3madkour-agents-circus-projects nil
  "Project roots (directory names) whose agents run in agent-circus.")

(defvar-local a3madkour-agents-circus-enabled nil
  "Non-nil runs this buffer's agents in agent-circus (settable in .dir-locals.el).")
(put 'a3madkour-agents-circus-enabled 'safe-local-variable #'booleanp)

(defun a3madkour-agents--circus-root ()
  "The current agent-shell project root as a directory name."
  (file-name-as-directory (expand-file-name (agent-shell-cwd))))

(defvar-local a3madkour-agents--circus-session nil
  "Circus decision for this shell buffer: `on', `off', or nil if not yet made.
Recorded when the shell's command prefix is first built, so toggling
circus later cannot change how a running shell reads and writes paths.")

(defun a3madkour-agents--circus-configured-p ()
  "Non-nil if circus is enabled for the current buffer's project right now."
  (or a3madkour-agents-circus-enabled
      (and (member (a3madkour-agents--circus-root) a3madkour-agents-circus-projects) t)))

(defun a3madkour-agents-circus-active-p (&optional buffer)
  "Non-nil if agents for BUFFER (default current) run in agent-circus.
A shell that already decided (see `a3madkour-agents--circus-session')
keeps its decision."
  (with-current-buffer (or buffer (current-buffer))
    (if a3madkour-agents--circus-session
        (eq a3madkour-agents--circus-session 'on)
      (a3madkour-agents--circus-configured-p))))

(defvar a3madkour-agents--starting-config nil
  "Config of the agent-shell being started; see `a3madkour-agents--bind-starting-config'.")

(defun a3madkour-agents--bind-starting-config (orig-fn &rest args)
  "`:around' advice for `agent-shell--start': expose its :config to the prefix.
agent-shell builds the command before storing the config in its state,
so `agent-shell-get-config' is still nil at that point."
  (let ((a3madkour-agents--starting-config (plist-get args :config)))
    (apply orig-fn args)))

(defun a3madkour-agents-circus-command-prefix (buffer)
  "`agent-shell-command-prefix' function: agent-circus exec for BUFFER, or nil.
Runs on the host (nil) when circus is off, or when no agent identifier
is known (agent-review builds clients outside `agent-shell--start').
The decision is recorded in BUFFER on the first call."
  (let* ((active (a3madkour-agents-circus-active-p buffer))
         (id (and active
                  (map-elt (or (agent-shell-get-config buffer)
                               a3madkour-agents--starting-config)
                           :identifier))))
    (with-current-buffer buffer
      (unless a3madkour-agents--circus-session
        (setq-local a3madkour-agents--circus-session (if (and active id) 'on 'off))))
    (when id
      (let ((service (or (alist-get id a3madkour-agents-circus-services)
                         (user-error "agent-circus has no service for agent `%s'" id))))
        (list "agent-circus" "exec" service "--")))))

(defun a3madkour-agents-circus-resolve-path (path)
  "`agent-shell-path-resolver-function': map PATH between host and container.
Identity unless circus is active for the current buffer; then PATH must
lie in the project or the container workspace, else it is an error."
  (if (not (a3madkour-agents-circus-active-p))
      path
    (let* ((root (a3madkour-agents--circus-root))
           (workspace a3madkour-agents-circus-workspace)
           (path (expand-file-name path)))
      (cond
       ((equal path (directory-file-name root)) workspace)
       ((equal path (directory-file-name workspace)) root)
       ((string-prefix-p root path)
        (concat workspace (substring path (length root))))
       ((string-prefix-p workspace path)
        (let ((local (expand-file-name (substring path (length workspace)) root)))
          (if (string-prefix-p root local)
              local
            (error "Container path resolves outside the project: %s" path))))
       (t (error "agent-circus: path outside the project: %s" path))))))

(defun a3madkour-agents--circus-state-label (root)
  "Effective circus state for project ROOT in the current buffer, as a string.
The dir-local `a3madkour-agents-circus-enabled' wins over the project list."
  (let ((listed (and (member root a3madkour-agents-circus-projects) t)))
    (cond (listed "ON")
          (a3madkour-agents-circus-enabled
           "still ON (dir-local a3madkour-agents-circus-enabled)")
          (t "OFF"))))

(defun a3madkour-agents-circus-toggle ()
  "Toggle agent-circus for the current project.
Affects shells started afterwards; restart running ones (SPC a n R)."
  (interactive)
  (let ((root (a3madkour-agents--circus-root)))
    (if (member root a3madkour-agents-circus-projects)
        (setq a3madkour-agents-circus-projects
              (delete root a3madkour-agents-circus-projects))
      (push root a3madkour-agents-circus-projects))
    (message "agent-circus %s for %s (new shells only)"
             (a3madkour-agents--circus-state-label root) root)
    (unless (executable-find "agent-circus")
      (display-warning 'a3madkour-agents
                       "agent-circus not found on exec-path (uv tool install agent-circus)"
                       :warning))))

;;;; Slack (agent-shell-to-go)
;;
;; Slack can drive this Emacs remotely, so nothing connects at startup:
;; `a3madkour-agents-slack-connect' (SPC a S c) is the only way in.
;; Credentials live in the macOS Keychain, never in the repo:
;;   security add-generic-password -s agent-shell-to-go -a bot-token -w xoxb-…
;; (likewise app-token, channel-id, user-id).

(declare-function agent-shell-to-go-setup "agent-shell-to-go")

(defun a3madkour-agents--slack-available-p ()
  "Non-nil if agent-shell-to-go can be loaded."
  (require 'agent-shell-to-go nil t))

(defcustom a3madkour-agents-slack-keychain-service "agent-shell-to-go"
  "Keychain service name holding the agent-shell-to-go credentials."
  :type 'string
  :group 'a3madkour-agents)

(defconst a3madkour-agents-slack-accounts
  '((agent-shell-to-go-bot-token . "bot-token")
    (agent-shell-to-go-app-token . "app-token")
    (agent-shell-to-go-channel-id . "channel-id")
    (agent-shell-to-go-user-id . "user-id"))
  "agent-shell-to-go variable -> Keychain account name.")

(defun a3madkour-agents-keychain-secret (account)
  "Return the Keychain generic password for ACCOUNT, or nil if absent."
  (car (ignore-errors
         (process-lines "security" "find-generic-password"
                        "-s" a3madkour-agents-slack-keychain-service
                        "-a" account "-w"))))

(defun a3madkour-agents-slack-load-credentials ()
  "Set agent-shell-to-go's credentials from the Keychain.
Only the user's own Slack ID is authorized.  Return missing account names."
  (let (missing)
    (pcase-dolist (`(,var . ,account) a3madkour-agents-slack-accounts)
      (if-let* ((secret (a3madkour-agents-keychain-secret account)))
          (set var secret)
        (push account missing)))
    (unless missing
      (set 'agent-shell-to-go-authorized-users
           (list (symbol-value 'agent-shell-to-go-user-id))))
    (nreverse missing)))

(defvar a3madkour-agents--slack-connected nil
  "Non-nil once `a3madkour-agents-slack-connect' has loaded credentials and set up.")

(defmacro a3madkour-agents-define-slack (name target)
  "Define command NAME that runs agent-shell-to-go's TARGET once connected.
Autoloads make TARGET callable before the Keychain credentials are
loaded, so refuse until `a3madkour-agents-slack-connect' has run."
  `(defun ,name ()
     ,(format "Run `%s' after `a3madkour-agents-slack-connect'." target)
     (interactive)
     (unless a3madkour-agents--slack-connected
       (user-error "Run SPC a S c (a3madkour-agents-slack-connect) first"))
     (call-interactively ',target)))

(a3madkour-agents-define-slack a3madkour-agents-slack-reconnect-buffer
  agent-shell-to-go-reconnect-buffer)
(a3madkour-agents-define-slack a3madkour-agents-slack-reconnect-all
  agent-shell-to-go-reconnect-all)
(a3madkour-agents-define-slack a3madkour-agents-slack-list-threads
  agent-shell-to-go-list-threads)
(a3madkour-agents-define-slack a3madkour-agents-slack-send-image
  agent-shell-to-go-send-image)
(a3madkour-agents-define-slack a3madkour-agents-slack-cleanup
  agent-shell-to-go-cleanup-old-threads)

(defun a3madkour-agents-slack-connect ()
  "Load Slack credentials and start mirroring agent-shell sessions to Slack."
  (interactive)
  (unless (a3madkour-agents--slack-available-p)
    (user-error "agent-shell-to-go is not installed"))
  (when-let* ((missing (a3madkour-agents-slack-load-credentials)))
    (user-error "Missing Keychain items (service %s): %s"
                a3madkour-agents-slack-keychain-service
                (string-join missing ", ")))
  (agent-shell-to-go-setup)
  (setq a3madkour-agents--slack-connected t)
  (message "agent-shell-to-go connected; agent-shell buffers now mirror to Slack"))

(provide 'a3madkour-agents)
;;; a3madkour-agents.el ends here
