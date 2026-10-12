# agent-shell-only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire claude-code.el and use agent-shell alone, with its extension ecosystem and a single mnemonic `SPC a` leader map.

**Architecture:** config.org (`* "AI" "Agents"`) holds the `use-package` blocks, settings, hooks and the `SPC a` map. A new `lisp/a3madkour-agents.el` holds every named helper: advice, evil remaps, perspective jumping, optional-command wrappers, the prerequisite check, and the Phase 2 glue for meta, circus and Slack. Its tests live in `lisp/a3madkour-agents-test.el`. Phase 1 is Tasks 1–7; Phase 2 is Tasks 8–12.

**Tech Stack:** Emacs 31.1 (Homebrew, macOS), straight.el + use-package (`straight-use-package-by-default t`, `use-package-always-defer t`), evil + evil-collection, general.el, perspective.el, agent-shell 0.50.1 (`027e4cd`), ERT.

**Spec:** `emacs-configs/custom/docs/superpowers/specs/2026-10-11-agent-shell-only-design.md`

## Global Constraints

- Repo root is `~/dotfiles`; the config dir is `~/dotfiles/emacs-configs/custom`. `~/emacs-configs` is a symlink to `dotfiles/emacs-configs`. Paths below are relative to the config dir unless they start with `~`.
- The working tree has **unrelated uncommitted changes** (`.zshrc`, `init.el`, `early-init.el`, `bookmarks`, the root `.gitignore`, …). Always commit with explicit paths: `git commit -m … -- <paths>`. Never run `git add -A` or `git commit -a`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- `use-package-always-defer` is `t`. A block with no `:hook`, `:commands`, `:demand t` or `:defer nil` **never loads**. `:after` only delays a load; it never causes one.
- Extensions are not on MELPA. Use `:straight (<name> :type git :host github :repo "<owner/repo>")`.
- Use `when-let*` / `if-let*`, never `when-let` / `if-let`; the latter are obsolete in Emacs 31 and warn at load.
- Module symbols use the prefix `a3madkour-agents-`, with `a3madkour-agents--` for internals.
- **TEST command** (run from the config dir):
  `emacs --batch -L lisp -L straight/build/evil -L straight/build/goto-chg -l lisp/a3madkour-agents-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -15`
- **BOOT command** (run from `~/emacs-configs/custom`):
  `emacs --batch --init-directory ~/emacs-configs/custom -l early-init.el -l init.el --eval '(message "BOOT-OK")' 2>&1 | grep -E 'BOOT-OK|Error|error' `
  - **Baseline** (2026-10-11, before any change): prints `Error (use-package): Cannot load godot-signals` and `BOOT-OK`. The godot line is pre-existing and expected.
  - A pass means `BOOT-OK` is printed and no **new** `Error` lines appear. `a3madkour-agents` prerequisite warnings are expected in batch.
  - The first BOOT after adding a `:straight` recipe clones it, so it needs network access.
- Agent identifiers at this commit: `claude-code`, `codex`, `opencode`. agent-circus service names: `"claude-code"`, `"codex"`, `"opencode"`, `"mistral-vibe"`.

## Review Focus

1. **A missing ACP adapter.** Starting Claude with `claude-agent-acp` absent should give agent-shell's own "missing executable" error, and our startup warning should have named it exactly once, not once per shell. Pinned in Task 2.
2. **Edge paths in circus mode.** A path equal to `/workspace`, the project root without its trailing slash, `/workspace/../etc/passwd`, and paths outside both. The first two map to their counterparts, the traversal errors, and anything else passes through. Pinned in Task 9.
3. **A meta spawn whose name is already taken.** For example, a second `Dispatcher`. It should get a unique name, not error and orphan the new shell. Pinned in Task 8.
4. **Jumping when perspectives don't apply.** The target buffer is in no perspective, already in the current one, or persp-mode is off. Jumping should do nothing, with no error and no switch. Pinned in Task 3.
5. **Slack connect with only some Keychain items present.** It must refuse to connect, name the missing items, and must not call `agent-shell-to-go-setup`. Pinned in Task 10.

---

## Phase 1

### Task 1: Module skeleton + named OpenCode/symlink advice

**Files:**
- Create: `lisp/a3madkour-agents.el`
- Create: `lisp/a3madkour-agents-test.el`

**Interfaces:**
- Produces:
  - `a3madkour-agents--project-files-truename (orig-fn &rest args)`: `:around` advice for `agent-shell--project-files`.
  - `a3madkour-agents--opencode-diff-info (orig-fn &rest args)`: `:around` advice for `agent-shell--make-diff-info`. ARGS is the plist `(:acp-tool-call CALL)`. Returns ORIG's value, or an alist `((:old . S) (:new . S) [(:file . S)])`.
  - `a3madkour-agents--opencode-permission-title (orig-fn &rest args)`: `:around` advice for `agent-shell--permission-title`. ARGS is `(:acp-request REQ)`. Reads the buffer-local `agent-shell--state`.
  - `(provide 'a3madkour-agents)`.

- [ ] **Step 1: Write the failing tests**

Create `lisp/a3madkour-agents-test.el`:

```elisp
;;; a3madkour-agents-test.el --- Tests for agent-shell helpers -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-agents)

;; Special in the module; declare here too so `let' binds dynamically.
(defvar agent-shell--state)

;;;; OpenCode diff info

(ert-deftest a3madkour-agents-test/diff-info-passes-through ()
  (should (eq 'orig (a3madkour-agents--opencode-diff-info
                     (lambda (&rest _) 'orig) :acp-tool-call nil))))

(ert-deftest a3madkour-agents-test/diff-info-opencode-keys ()
  (let ((call '((rawInput . ((oldString . "a") (newString . "b") (filePath . "/p/x.el"))))))
    (should (equal '((:old . "a") (:new . "b") (:file . "/p/x.el"))
                   (a3madkour-agents--opencode-diff-info
                    (lambda (&rest _) nil) :acp-tool-call call)))))

(ert-deftest a3madkour-agents-test/diff-info-lowercase-filepath-missing-old ()
  (let ((call '((rawInput . ((newString . "b") (filepath . "/p/y.el"))))))
    (should (equal '((:old . "") (:new . "b") (:file . "/p/y.el"))
                   (a3madkour-agents--opencode-diff-info
                    (lambda (&rest _) nil) :acp-tool-call call)))))

(ert-deftest a3madkour-agents-test/diff-info-no-path ()
  (let ((call '((rawInput . ((oldString . "a") (newString . "b"))))))
    (should (equal '((:old . "a") (:new . "b"))
                   (a3madkour-agents--opencode-diff-info
                    (lambda (&rest _) nil) :acp-tool-call call)))))

(ert-deftest a3madkour-agents-test/diff-info-no-newstring-is-nil ()
  (let ((call '((rawInput . ((oldString . "a"))))))
    (should-not (a3madkour-agents--opencode-diff-info
                 (lambda (&rest _) nil) :acp-tool-call call))))

;;;; OpenCode permission title

(defun a3madkour-agents-test--request (id)
  `((params . ((toolCall . ((toolCallId . ,id)))))))

(ert-deftest a3madkour-agents-test/permission-title-specific-passes-through ()
  (should (equal "Edit foo.el"
                 (a3madkour-agents--opencode-permission-title
                  (lambda (&rest _) "Edit foo.el") :acp-request nil))))

(ert-deftest a3madkour-agents-test/permission-title-execute-from-state ()
  (let ((agent-shell--state
         '((:tool-calls . (("t1" . ((:command . "ls -la") (:kind . "execute"))))))))
    (should (equal "```console\nls -la\n```"
                   (a3madkour-agents--opencode-permission-title
                    (lambda (&rest _) "bash")
                    :acp-request (a3madkour-agents-test--request "t1"))))))

(ert-deftest a3madkour-agents-test/permission-title-other-kind-plain ()
  (let ((agent-shell--state
         '((:tool-calls . (("t2" . ((:command . "rm x") (:kind . "other"))))))))
    (should (equal "rm x"
                   (a3madkour-agents--opencode-permission-title
                    (lambda (&rest _) "execute")
                    :acp-request (a3madkour-agents-test--request "t2"))))))

(ert-deftest a3madkour-agents-test/permission-title-generic-unknown-id-is-nil ()
  "Pins the pre-existing behaviour: generic title + no saved call => nil."
  (let ((agent-shell--state '((:tool-calls . nil))))
    (should-not (a3madkour-agents--opencode-permission-title
                 (lambda (&rest _) "bash")
                 :acp-request (a3madkour-agents-test--request "nope")))))

;;;; Symlinked project dirs

(ert-deftest a3madkour-agents-test/project-files-truename ()
  (let* ((real (make-temp-file "a3ag-real" t))
         (link (expand-file-name (make-temp-name "a3ag-link") temporary-file-directory)))
    (unwind-protect
        (progn
          (make-symbolic-link real link)
          (let ((default-directory (file-name-as-directory link)))
            (should (equal (file-name-as-directory (file-truename real))
                           (file-name-as-directory
                            (a3madkour-agents--project-files-truename
                             (lambda () default-directory)))))))
      (delete-file link)
      (delete-directory real))))

(provide 'a3madkour-agents-test)
;;; a3madkour-agents-test.el ends here
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: TEST command.
Expected: an error loading `a3madkour-agents` (`Cannot open load file … a3madkour-agents`).

- [ ] **Step 3: Write the module**

Create `lisp/a3madkour-agents.el`:

```elisp
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

(provide 'a3madkour-agents)
;;; a3madkour-agents.el ends here
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: TEST command.
Expected: `Ran 10 tests, 10 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-agents.el emacs-configs/custom/lisp/a3madkour-agents-test.el && git commit -m "agents: named OpenCode/symlink advice in a3madkour-agents.el

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/lisp/a3madkour-agents.el emacs-configs/custom/lisp/a3madkour-agents-test.el
```

---

### Task 2: Prerequisite check + optional-command wrappers

**Files:**
- Modify: `lisp/a3madkour-agents.el` (insert before `(provide …)`)
- Modify: `lisp/a3madkour-agents-test.el` (insert before `(provide …)`)

**Interfaces:**
- Produces:
  - `a3madkour-agents-required-executables`: defcustom, a list of `(NAMES . HINT)`. NAMES is a string, or a list of strings where any one of them is enough.
  - `a3madkour-agents-missing-executables (&optional specs)` → the entries of SPECS (default: the defcustom) with no executable on `exec-path`.
  - `a3madkour-agents-check-prereqs ()`: warns once per session, through `display-warning` with type `a3madkour-agents`.
  - `a3madkour-agents--call-optional (target package)` and the macro `a3madkour-agents-define-optional (name target package)`.
  - Named commands used by the keymap (Task 6):
    - meta: `a3madkour-agents-meta-session`, `a3madkour-agents-meta-dispatcher`, `a3madkour-agents-meta-close-dispatcher`, `a3madkour-agents-meta-heartbeat-start`, `a3madkour-agents-meta-heartbeat-stop`, `a3madkour-agents-meta-heartbeat-now`, `a3madkour-agents-meta-big-red-button`;
    - slack: `a3madkour-agents-slack-connect-cmd`, `a3madkour-agents-slack-reconnect-buffer`, `a3madkour-agents-slack-reconnect-all`, `a3madkour-agents-slack-list-threads`, `a3madkour-agents-slack-send-image`, `a3madkour-agents-slack-cleanup`;
    - circus: `a3madkour-agents-circus-toggle-cmd`.

- [ ] **Step 1: Write the failing tests**

Append to the test file, before `(provide 'a3madkour-agents-test)`:

```elisp
;;;; Prerequisites

(ert-deftest a3madkour-agents-test/missing-executables ()
  (cl-letf (((symbol-function 'executable-find)
             (lambda (name &rest _) (member name '("present" "podman")))))
    (should (equal '(("absent" . "install absent"))
                   (a3madkour-agents-missing-executables
                    '(("present" . "x")
                      ("absent" . "install absent")
                      (("docker" "podman") . "any one is fine")))))))

(ert-deftest a3madkour-agents-test/check-prereqs-warns-once ()
  (let ((a3madkour-agents--prereqs-checked nil)
        (a3madkour-agents-required-executables '(("absent" . "install it")))
        (warnings nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil))
              ((symbol-function 'display-warning)
               (lambda (type msg &rest _) (push (cons type msg) warnings))))
      (a3madkour-agents-check-prereqs)
      (a3madkour-agents-check-prereqs)
      (should (= 1 (length warnings)))
      (should (eq 'a3madkour-agents (caar warnings)))
      (should (string-match-p "absent.*install it" (cdar warnings))))))

(ert-deftest a3madkour-agents-test/check-prereqs-silent-when-all-present ()
  (let ((a3madkour-agents--prereqs-checked nil)
        (a3madkour-agents-required-executables '(("here" . "x")))
        (warned nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/bin/here"))
              ((symbol-function 'display-warning) (lambda (&rest _) (setq warned t))))
      (a3madkour-agents-check-prereqs)
      (should-not warned))))

;;;; Optional commands

(ert-deftest a3madkour-agents-test/optional-missing-command-errors ()
  (let ((err (should-error (a3madkour-agents--call-optional
                            'a3madkour-agents-test--does-not-exist "fake-pkg")
                           :type 'user-error)))
    (should (string-match-p "fake-pkg" (cadr err)))))

(ert-deftest a3madkour-agents-test/optional-calls-through-with-prefix ()
  (let (seen)
    (cl-letf (((symbol-function 'a3madkour-agents-test--target)
               (lambda (arg) (interactive "P") (setq seen (list 'called arg)))))
      (let ((current-prefix-arg '(4)))
        (a3madkour-agents--call-optional 'a3madkour-agents-test--target "x"))
      (should (equal '(called (4)) seen)))))

(ert-deftest a3madkour-agents-test/define-optional-makes-command ()
  (should (commandp 'a3madkour-agents-meta-session))
  (should (commandp 'a3madkour-agents-circus-toggle-cmd))
  (should (commandp 'a3madkour-agents-slack-connect-cmd)))
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: TEST command.
Expected: the new tests FAIL with `void-function a3madkour-agents-missing-executables` and similar; the earlier 10 still pass.

- [ ] **Step 3: Implement**

Insert into `lisp/a3madkour-agents.el` before `(provide 'a3madkour-agents)`:

```elisp
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: TEST command.
Expected: `Ran 16 tests, 16 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git commit -m "agents: prerequisite check and optional-command wrappers

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/lisp/a3madkour-agents.el emacs-configs/custom/lisp/a3madkour-agents-test.el
```

---

### Task 3: Perspective-aware jumping + evil remap table

**Files:**
- Modify: `lisp/a3madkour-agents.el`
- Modify: `lisp/a3madkour-agents-test.el`

**Interfaces:**
- Consumes (perspective.el): `persp-current-name ()`, `persp-names ()`, `persp-get-buffers (&optional persp-or-name frame)` → list of buffers, `persp-switch (name &optional norecord)`, variable `persp-mode`.
- Produces:
  - `a3madkour-agents-persp-owner (buffer)` → the name of a perspective *other than the current one* holding BUFFER, or nil. Nil when persp-mode is off or the current perspective holds BUFFER.
  - `a3madkour-agents-switch-to-owner-persp (buffer)`: hook function for `agent-shell-attention-before-jump-hook`.
  - `a3madkour-agents--manager-goto-persp (&rest _)`: `:before` advice for `agent-shell-manager-goto`.
  - `a3madkour-agents-evil-bindings`: a list of `(MAP-SYMBOL MODE ((KEY . COMMAND) …))`.
  - `a3madkour-agents-evil-bind (map-symbol)`: sets MODE's initial state to normal and binds KEYs in normal state.

- [ ] **Step 1: Write the failing tests**

Append to the test file:

```elisp
;;;; Perspectives

(defvar persp-mode)

(defmacro a3madkour-agents-test--with-persps (current table &rest body)
  "Run BODY with perspective.el stubbed: CURRENT name, TABLE alist name->buffers.
Binds `switched' to the name passed to `persp-switch', if any."
  (declare (indent 2))
  `(let ((persp-mode t) (switched nil))
     (cl-letf (((symbol-function 'persp-current-name) (lambda () ,current))
               ((symbol-function 'persp-names) (lambda () (mapcar #'car ,table)))
               ((symbol-function 'persp-get-buffers)
                (lambda (&optional name _frame) (cdr (assoc (or name ,current) ,table))))
               ((symbol-function 'persp-switch)
                (lambda (name &rest _) (setq switched name))))
       ,@body)))

(ert-deftest a3madkour-agents-test/persp-switches-to-owner ()
  (let ((buf (generate-new-buffer " a3ag")))
    (unwind-protect
        (a3madkour-agents-test--with-persps "main" `(("main") ("work" ,buf))
          (a3madkour-agents-switch-to-owner-persp buf)
          (should (equal "work" switched)))
      (kill-buffer buf))))

(ert-deftest a3madkour-agents-test/persp-noop-when-in-current ()
  (let ((buf (generate-new-buffer " a3ag")))
    (unwind-protect
        (a3madkour-agents-test--with-persps "main" `(("main" ,buf) ("work" ,buf))
          (a3madkour-agents-switch-to-owner-persp buf)
          (should-not switched))
      (kill-buffer buf))))

(ert-deftest a3madkour-agents-test/persp-noop-when-unowned ()
  (let ((buf (generate-new-buffer " a3ag")))
    (unwind-protect
        (a3madkour-agents-test--with-persps "main" '(("main") ("work"))
          (a3madkour-agents-switch-to-owner-persp buf)
          (should-not switched))
      (kill-buffer buf))))

(ert-deftest a3madkour-agents-test/persp-noop-when-mode-off ()
  (let ((buf (generate-new-buffer " a3ag")))
    (unwind-protect
        (a3madkour-agents-test--with-persps "main" `(("main") ("work" ,buf))
          (let ((persp-mode nil))
            (a3madkour-agents-switch-to-owner-persp buf))
          (should-not switched))
      (kill-buffer buf))))

;;;; Evil remaps

(require 'evil)

(defvar a3madkour-agents-test--map (make-sparse-keymap))

(ert-deftest a3madkour-agents-test/evil-bind-from-table ()
  (let ((a3madkour-agents-evil-bindings
         '((a3madkour-agents-test--map nil (("x" . kill-buffer) ("gr" . revert-buffer))))))
    (a3madkour-agents-evil-bind 'a3madkour-agents-test--map)
    (let ((aux (evil-get-auxiliary-keymap a3madkour-agents-test--map 'normal)))
      (should (eq 'kill-buffer (lookup-key aux (kbd "x"))))
      (should (eq 'revert-buffer (lookup-key aux (kbd "gr")))))))

(ert-deftest a3madkour-agents-test/evil-table-pins-design ()
  "Keys from spec §1.4 that collide with evil or evil-collection."
  (cl-flet ((cmd (map key)
              (alist-get key (nth 2 (assq map a3madkour-agents-evil-bindings))
                         nil nil #'equal)))
    (should (eq 'agent-shell-manager-kill (cmd 'agent-shell-manager-mode-map "x")))
    (should (eq 'agent-shell-manager-goto (cmd 'agent-shell-manager-mode-map "RET")))
    (should (eq 'agent-shell-manager-refresh (cmd 'agent-shell-manager-mode-map "gr")))
    (should (eq 'agent-shell-attention-dashboard-open-ambient-directory
                (cmd 'agent-shell-attention-dashboard-mode-map "J")))
    (should (eq 'agent-review-send-to-agent-shell (cmd 'agent-review-mode-map "S")))
    (should (eq 'agent-review-refresh (cmd 'agent-review-mode-map "gr")))
    ;; every key must parse
    (dolist (entry a3madkour-agents-evil-bindings)
      (dolist (binding (nth 2 entry))
        (should (kbd (car binding)))))))
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: TEST command.
Expected: the new tests FAIL with `void-function a3madkour-agents-switch-to-owner-persp` and `void-variable a3madkour-agents-evil-bindings`.

- [ ] **Step 3: Implement**

Insert into the module before `(provide …)`:

```elisp
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: TEST command.
Expected: `Ran 22 tests, 22 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git commit -m "agents: perspective-aware jumping and evil remap table

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/lisp/a3madkour-agents.el emacs-configs/custom/lisp/a3madkour-agents-test.el
```

---

### Task 4: Remove claude-code; rewrite the core agent-shell block

**Files:**
- Modify: `config.org`. Replace everything from the `* "AI" "Agents"` line (≈4921) up to, but not including, `* Website publish` (≈5063).
- Create: `.gitignore` in the config dir. This is a new file; the dotfiles root `.gitignore` has unrelated edits, so don't touch it.

**Interfaces:**
- Consumes: from Task 1, `a3madkour-agents--project-files-truename`, `a3madkour-agents--opencode-diff-info`, `a3madkour-agents--opencode-permission-title`; from Task 2, `a3madkour-agents-check-prereqs`.
- Produces: the `** Agent shell` heading that Task 5 nests `***` sub-headings under. `(require 'a3madkour-agents)` runs early in the AI section.

- [ ] **Step 1: Record the baseline**

Run: BOOT command. Expected: `Error (use-package): Cannot load godot-signals`, then `BOOT-OK`.
Run: `grep -n 'claude-code\|monet\|inheritenv\|emacs-eat\|eat-' config.org | grep -v 'emms-toggle-repeat\|repeat-complex' | wc -l`. Expected: a non-zero count.

- [ ] **Step 2: Replace the section**

Use the Edit tool. Replace the whole region from `* "AI" "Agents"` through the `#+end_src` that closes the agent-shell block (the line right before `* Website publish`) with the following. The `*** …` sub-headings come in Task 5.

````org
* "AI" "Agents"
agent-shell is the only agent front-end here. claude-code.el, along with its eat, monet and inheritenv stack, was retired on 2026-10-11 (see [[file:docs/superpowers/specs/2026-10-11-agent-shell-only-design.md][the design spec]]). The helpers live in [[file:lisp/a3madkour-agents.el][a3madkour-agents.el]] so they can be tested; this heading only wires them up.

The Emacs server has to be running, because emacs-skills and meta-agent-shell drive this Emacs through =emacsclient=. It is skipped in batch so a boot check doesn't take the socket.
#+begin_src emacs-lisp
(require 'a3madkour-agents)
(require 'server)
(unless (or noninteractive (server-running-p))
  (server-start))
#+end_src
** Agent shell
Claude Code and Codex authenticate with their own CLI logins; OpenCode uses its CLI-stored credentials. The shell runs as the comint buffer, not the viewport (more reliable for diffs). The real setting is =agent-shell-prefer-viewport-interaction=; the =agent-shell-prefer-viewport= that used to be set here never existed.

The three advice functions patch OpenCode's non-standard ACP payloads and project.el's blindness to symlinked directories. They are named rather than inline lambdas so they can be tested and removed.

=a3madkour-agents-check-prereqs= warns once if an ACP adapter is missing from =exec-path=. Otherwise the first sign would be a failed shell.
#+begin_src emacs-lisp
(use-package shell-maker)
(use-package acp)
(use-package agent-shell
  :ensure t
  :defer nil
  :config

  (setq agent-shell-anthropic-authentication
		(agent-shell-anthropic-make-authentication :login t))
  (setq agent-shell-openai-authentication
		(agent-shell-openai-make-authentication :login t))
  ;; ── OpenCode auth (use CLI-stored credentials) ──
  (setq agent-shell-opencode-authentication '((:none . t)))

  (setq agent-shell-display-action
		'(display-buffer-pop-up-window))

  ;; ── Enable @ file completion ──
  (setq agent-shell-file-completion-enabled t)

  ;; ── Use comint mode (more reliable for diffs) ──
  (setq agent-shell-prefer-viewport-interaction nil)

  ;; ── Suppress interfering modes during edits ──
  (setopt agent-shell-write-inhibit-minor-modes
          '(aggressive-indent-mode electric-indent-mode))

  ;; ── Evil ──
  (with-eval-after-load 'evil
    (evil-define-key 'insert agent-shell-mode-map
      (kbd "S-<return>") #'newline
      (kbd "RET") #'comint-send-input)
    (evil-define-key 'normal agent-shell-mode-map
      (kbd "RET") #'comint-send-input))

  ;; Diff/permission buffers in emacs state so y/n/p/q just work
  (add-hook 'diff-mode-hook
            (lambda ()
              (when (string-match-p "\\*agent-shell-diff\\*" (buffer-name))
                (evil-emacs-state))))

  ;; ── Corfu: ensure @ completion triggers ──
  (add-hook 'agent-shell-mode-hook
            (lambda ()
              (setq-local corfu-auto t)
              (setq-local corfu-auto-prefix 1)
              (setq-local corfu-auto-delay 0.1)
			  (setq-local completion-at-point-functions
                          '(agent-shell--command-completion-at-point
							agent-shell--file-completion-at-point))
              (corfu-mode 1)))

  ;; ── Fixes (see lisp/a3madkour-agents.el) ──
  (advice-add 'agent-shell--project-files :around
              #'a3madkour-agents--project-files-truename)
  (advice-add 'agent-shell--make-diff-info :around
              #'a3madkour-agents--opencode-diff-info)
  (advice-add 'agent-shell--permission-title :around
              #'a3madkour-agents--opencode-permission-title)

  (a3madkour-agents-check-prereqs))
#+end_src
````

- [ ] **Step 3: Delete the `SPC k` group**

In `* Keybindings`, delete this block exactly (≈5237–5253). Leave the following `;; Git` line alone:

```elisp
 ;; claude
 "k"
 '(nil :which-key "claude code")
 "ko"
 '(claude-code :which-key "open claude code")
 "kr"
 '(claude-code-send-region :which-key "send claude code region")
 "kt"
 '(claude-code-toggle :which-key "claude code toggle")
 "km"
 '(claude-code-transient :which-key "claude code transient menu")
 "kd"
 '(claude-code-start-in-directory :which-key "open claude code in dir")
 "kk"
 '(claude-code-kill :which-key "kill claude code")
 "kc"
 '(claude-code-send-command-with-context :which-key "send a command to claude code with region context")
```

- [ ] **Step 4: Ignore agent-shell's working directory**

Create `.gitignore` in the config dir (it doesn't exist yet) containing:

```
# agent-shell transcripts, worktrees and macext copies
.agent-shell/
```

- [ ] **Step 5: Verify**

Run: `grep -n '(use-package claude-code\|claude-code-command-map\|claude-code-transient\|(use-package monet\|monet-mode\|(use-package inheritenv\|(use-package eat\|eat-self-input\|eat-semi\|"ko"' config.org`. Expected: no output. Plain mentions of claude-code.el in the new prose are fine.
Run: BOOT command. Expected: the same godot `Error` line, then `BOOT-OK`, with no new `Error` lines. `a3madkour-agents` warnings about `claude-agent-acp` / `codex-acp` / `terminal-notifier` are expected.
Run: TEST command. Expected: 22/22 pass.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/.gitignore && git commit -m "config: retire claude-code.el; agent-shell core uses named advice

Removes claude-code, monet, eat, inheritenv and the SPC k group.  Fixes
the nonexistent agent-shell-prefer-viewport setting, adds Codex auth,
server-start and a one-time prerequisite check.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/config.org emacs-configs/custom/.gitignore
```

---

### Task 5: Phase 1 extensions

**Files:**
- Modify: `config.org`. Insert six `***` sub-headings after the `** Agent shell` block's `#+end_src` and before `* Website publish`.

**Interfaces:**
- Consumes: `a3madkour-agents-evil-bind`, `a3madkour-agents-switch-to-owner-persp` and `a3madkour-agents--manager-goto-persp` (Task 3); the agent-shell block (Task 4).
- Produces: these commands become available for Task 6:
  - `agent-shell-manager-toggle`;
  - `agent-shell-attention-jump`, `-jump-idle`, `-dashboard`;
  - `agent-shell-sidebar-toggle`, `-toggle-focus`, `-change-provider`, `-reset`;
  - `agent-review`;
  - `agent-shell-macext-yank`.

- [ ] **Step 1: Insert the extension sub-headings**

Insert this text right after the `#+end_src` that ends the `** Agent shell` block:

````org
*** Session manager
[[https://github.com/jethrokuan/agent-shell-manager][agent-shell-manager]] is the main session list: status, mode, model, pending permissions and path for every shell, in a bottom side window (=SPC a l=). The keys are remapped for evil normal state (=x= kills, =gr= refreshes; see =a3madkour-agents-evil-bindings=). Going to a row switches to the perspective that owns that shell first.
#+begin_src emacs-lisp
(use-package agent-shell-manager
  :straight (agent-shell-manager :type git :host github :repo "jethrokuan/agent-shell-manager")
  :after agent-shell
  :commands agent-shell-manager-toggle
  :custom
  (agent-shell-manager-side 'bottom)
  (agent-shell-manager-transient nil)
  :config
  (a3madkour-agents-evil-bind 'agent-shell-manager-mode-map)
  (advice-add 'agent-shell-manager-goto :before #'a3madkour-agents--manager-goto-persp))
#+end_src
*** Attention
[[https://github.com/ultronozm/agent-shell-attention.el][agent-shell-attention]] is the "who needs me" tracker. It puts an =AS:n= count in the mode-line and provides =SPC a j= / =SPC a J= to jump to the waiting or idle shell, plus a secondary dashboard (=SPC a L=). Its own notifier is off: it relies on D-Bus, which this Emacs build lacks, and macext already notifies. =:demand t= is needed because a global mode only does anything once it is loaded and enabled.
#+begin_src emacs-lisp
(use-package agent-shell-attention
  :straight (agent-shell-attention :type git :host github :repo "ultronozm/agent-shell-attention.el")
  :after agent-shell
  :demand t
  :custom
  (agent-shell-attention-indicator-location 'global-mode-string)
  (agent-shell-attention-notify-function nil)
  :config
  (agent-shell-attention-mode 1)
  (add-hook 'agent-shell-attention-before-jump-hook
            #'a3madkour-agents-switch-to-owner-persp)
  (a3madkour-agents-evil-bind 'agent-shell-attention-dashboard-mode-map))
#+end_src
*** Sidebar
[[https://github.com/cmacrae/agent-shell-sidebar][agent-shell-sidebar]] gives one shell per project in a locked right side window (=SPC a s=, focus with =SPC a f=). It is locked, so =other-window= and evil's window motions skip it, and =SPC a f= is the way in. It defaults to Claude Code; =SPC a n P= switches provider.
#+begin_src emacs-lisp
(use-package agent-shell-sidebar
  :straight (agent-shell-sidebar :type git :host github :repo "cmacrae/agent-shell-sidebar")
  :after agent-shell
  :commands (agent-shell-sidebar-toggle agent-shell-sidebar-toggle-focus
             agent-shell-sidebar-change-provider agent-shell-sidebar-reset)
  :custom
  (agent-shell-sidebar-position 'right)
  (agent-shell-sidebar-width "35%")
  (agent-shell-sidebar-locked t)
  :config
  (setq agent-shell-sidebar-default-config
        (agent-shell-anthropic-make-claude-code-config)))
#+end_src
*** Bookmarks and org links
[[https://github.com/dcluna/agent-shell-bookmark][agent-shell-bookmark]] makes shells bookmarkable (=SPC a b=); jumping to one resumes the session by ID. =agent-shell-ol= from the same repo adds =[[agent-shell:…]]= org links, so =org-store-link= in a shell gives a link that resumes it.
#+begin_src emacs-lisp
(use-package agent-shell-bookmark
  :straight (agent-shell-bookmark :type git :host github :repo "dcluna/agent-shell-bookmark")
  :after agent-shell
  :demand t
  :config
  (with-eval-after-load 'org
    (require 'agent-shell-ol)))
#+end_src
*** Review
[[https://github.com/nineluj/agent-review][agent-review]] reviews the uncommitted diff with an agent of your choice and lists the issues; =m= marks and =S= sends to a shell. It runs its own ACP client, which skips agent-shell's authenticate step, so it may not work with Claude's =:login= auth. If it doesn't, review with OpenCode or Codex.
#+begin_src emacs-lisp
(use-package agent-review
  :straight (agent-review :type git :host github :repo "nineluj/agent-review")
  :commands agent-review
  :config
  (a3madkour-agents-evil-bind 'agent-review-mode-map))
#+end_src
*** macOS extensions
[[https://github.com/cxa/agent-shell-macext][agent-shell-macext]] is the only notifier. It sends native notifications for finished turns and permission requests: banners through =terminal-notifier= if it is installed, otherwise =osascript= into Notification Center. It also makes pasting a Finder file insert it as =@file= context, and supports drag and drop. Under evil, =p= / =P= are not =yank=, so they are rebound here in agent buffers.
#+begin_src emacs-lisp
(use-package agent-shell-macext
  :straight (agent-shell-macext :type git :host github :repo "cxa/agent-shell-macext")
  :if (eq system-type 'darwin)
  :after agent-shell
  :demand t
  :hook (agent-shell-mode . agent-shell-macext-setup)
  :custom
  (agent-shell-macext-notifications t)
  (agent-shell-macext-file-copy-policy 'auto)
  :config
  (with-eval-after-load 'evil
    (evil-define-key 'normal agent-shell-mode-map
      (kbd "p") #'agent-shell-macext-yank
      (kbd "P") #'agent-shell-macext-yank)))
#+end_src
````

- [ ] **Step 2: Verify that the packages install and load**

Run: BOOT command. Network is needed on this first run.
Expected: `BOOT-OK`, no new `Error` lines.

Then confirm that each package is installed and its command is defined:

```bash
cd ~/emacs-configs/custom && emacs --batch --init-directory ~/emacs-configs/custom -l early-init.el -l init.el --eval '(dolist (f (quote (agent-shell-manager-toggle agent-shell-attention-jump agent-shell-attention-jump-idle agent-shell-attention-dashboard agent-shell-sidebar-toggle agent-shell-sidebar-toggle-focus agent-review agent-shell-macext-yank))) (message "%s %s" f (if (fboundp f) "OK" "MISSING")))' 2>&1 | grep -E ' (OK|MISSING)$'
```
Expected: all 8 lines end in `OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git commit -m "config: agent-shell manager, attention, sidebar, bookmark, review, macext

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/config.org
```

---

### Task 6: The `SPC a` leader map

**Files:**
- Modify: `config.org`, in `* Keybindings`. Replace the `;; Agents` block (≈5101–5118, from ` ;; Agents` through the `"ab"` entry).

**Interfaces:**
- Consumes: the optional wrappers (Task 2); the extension commands (Task 5); built-in agent-shell commands (all verified to exist at `027e4cd`).

- [ ] **Step 1: Replace the Agents block**

Replace exactly this existing text:

```elisp
 ;; Agents
 "a" 
 '(nil  :which-key "agents")
 "ao"
 '(agent-shell-opencode-start-agent :which-key "opencode")
 "ak"
 '(agent-shell-anthropic-start-claude-code  :which-key "claude")
 "ar"
 '(agent-shell-send-region-to :which-key "send region")
 "ad"
 '(agent-shell-send-dwim :which-key "send dwim")
 "af"
 '(agent-shell-send-file :which-key "send file")
 "ac"
 '(agent-shell-prompt-compose :which-key "prompt compose")
 "ah"
 '(agent-shell-help-menu :which-key "help menu")
 "ab"
 '(agent-shell-other-buffer :which-key "switch to the between viewport and shell")
```

with:

```elisp
 ;; Agents (agent-shell + extensions; see * "AI" "Agents")
 "a"
 '(nil :which-key "agents")
 "aa" '(agent-shell :which-key "agent-shell dwim")
 "at" '(agent-shell-toggle :which-key "toggle shell")
 "aj" '(agent-shell-attention-jump :which-key "jump to waiting")
 "aJ" '(agent-shell-attention-jump-idle :which-key "jump to idle")
 "al" '(agent-shell-manager-toggle :which-key "session manager")
 "aL" '(agent-shell-attention-dashboard :which-key "attention dashboard")
 "as" '(agent-shell-sidebar-toggle :which-key "sidebar")
 "af" '(agent-shell-sidebar-toggle-focus :which-key "sidebar focus")
 "ac" '(agent-shell-prompt-compose :which-key "prompt compose")
 "ap" '(agent-shell-jump-to-latest-permission-button-row :which-key "latest permission")
 "ai" '(agent-shell-interrupt :which-key "interrupt")
 "aI" '(a3madkour-agents-meta-big-red-button :which-key "interrupt ALL (meta)")
 "ao" '(agent-shell-other-buffer :which-key "shell <-> viewport")
 "ab" '(bookmark-set :which-key "bookmark session")
 "ar" '(agent-review :which-key "review diff")
 "aC" '(a3madkour-agents-circus-toggle-cmd :which-key "toggle circus (project)")
 "a?" '(agent-shell-help-menu :which-key "help menu")

 "an" '(nil :which-key "new")
 "ank" '(agent-shell-anthropic-start-claude-code :which-key "claude")
 "ano" '(agent-shell-opencode-start-agent :which-key "opencode")
 "anc" '(agent-shell-openai-start-codex :which-key "codex")
 "ann" '(agent-shell-new-shell :which-key "new (pick agent)")
 "anw" '(agent-shell-new-worktree-shell :which-key "worktree")
 "ant" '(agent-shell-new-temp-shell :which-key "temp dir")
 "anD" '(agent-shell-new-downloads-shell :which-key "~/Downloads")
 "anf" '(agent-shell-fork :which-key "fork session")
 "anr" '(agent-shell-resume-session :which-key "resume session")
 "anR" '(agent-shell-restart :which-key "restart (clear)")
 "anl" '(agent-shell-reload :which-key "reload (same session)")
 "anP" '(agent-shell-sidebar-change-provider :which-key "sidebar provider")
 "anX" '(agent-shell-sidebar-reset :which-key "sidebar reset")

 "ax" '(nil :which-key "send")
 "axd" '(agent-shell-send-dwim :which-key "dwim")
 "axr" '(agent-shell-send-region-to :which-key "region to…")
 "axf" '(agent-shell-send-file :which-key "file")
 "axF" '(agent-shell-send-other-file :which-key "other file")
 "axs" '(agent-shell-send-screenshot :which-key "screenshot")
 "axi" '(agent-shell-send-clipboard-image :which-key "clipboard image")
 "ax!" '(agent-shell-insert-shell-command-output :which-key "shell cmd output")
 "axy" '(agent-shell-macext-yank :which-key "Finder-aware yank")

 "am" '(nil :which-key "mode/model")
 "amm" '(agent-shell-set-session-mode :which-key "set mode")
 "amv" '(agent-shell-set-session-model :which-key "set model")
 "am TAB" '(agent-shell-cycle-session-mode :which-key "cycle mode")

 "aq" '(nil :which-key "queue")
 "aqq" '(agent-shell-queue-request :which-key "queue request")
 "aqr" '(agent-shell-resume-pending-requests :which-key "resume pending")
 "aqd" '(agent-shell-remove-pending-request :which-key "remove pending")

 "aM" '(nil :which-key "meta")
 "aMm" '(a3madkour-agents-meta-session :which-key "meta session")
 "aMd" '(a3madkour-agents-meta-dispatcher :which-key "dispatcher")
 "aMk" '(a3madkour-agents-meta-close-dispatcher :which-key "close dispatcher")
 "aMh" '(a3madkour-agents-meta-heartbeat-start :which-key "heartbeat start")
 "aMH" '(a3madkour-agents-meta-heartbeat-stop :which-key "heartbeat stop")
 "aMs" '(a3madkour-agents-meta-heartbeat-now :which-key "heartbeat now")

 "aS" '(nil :which-key "slack")
 "aSc" '(a3madkour-agents-slack-connect-cmd :which-key "connect")
 "aSr" '(a3madkour-agents-slack-reconnect-buffer :which-key "reconnect buffer")
 "aSR" '(a3madkour-agents-slack-reconnect-all :which-key "reconnect all")
 "aSl" '(a3madkour-agents-slack-list-threads :which-key "list threads")
 "aSi" '(a3madkour-agents-slack-send-image :which-key "send image")
 "aSx" '(a3madkour-agents-slack-cleanup :which-key "cleanup old threads")

 "ad" '(nil :which-key "debug")
 "adt" '(agent-shell-view-traffic :which-key "traffic")
 "ada" '(agent-shell-view-acp-logs :which-key "acp logs")
 "adl" '(agent-shell-toggle-logging :which-key "toggle logging")
 "adu" '(agent-shell-show-usage :which-key "usage")
 "adT" '(agent-shell-open-transcript :which-key "transcript")
 "ady" '(agent-shell-copy-session-id :which-key "copy session id")
```

- [ ] **Step 2: Verify that every bound command resolves**

Run BOOT, then check the bindings directly:

```bash
cd ~/emacs-configs/custom && emacs --batch --init-directory ~/emacs-configs/custom -l early-init.el -l init.el --eval '(progn (require (quote evil)) (dolist (k (list "aa" "at" "aj" "aJ" "al" "aL" "as" "af" "ac" "ap" "ai" "aI" "ao" "ab" "ar" "aC" "a?" "ank" "ano" "anc" "ann" "anw" "ant" "anD" "anf" "anr" "anR" "anl" "anP" "anX" "axd" "axr" "axf" "axF" "axs" "axi" "ax!" "axy" "amm" "amv" "am TAB" "aqq" "aqr" "aqd" "aMm" "aMd" "aMk" "aMh" "aMH" "aMs" "aSc" "aSr" "aSR" "aSl" "aSi" "aSx" "adt" "ada" "adl" "adu" "adT" "ady")) (let ((cmd (lookup-key (evil-get-auxiliary-keymap general-override-mode-map (quote normal)) (kbd (concat "SPC " k))))) (message "KEY %-7s %s %s" k cmd (if (and (symbolp cmd) (commandp cmd)) "OK" "BAD")))))' 2>&1 | grep '^KEY' | grep -v ' OK$'
```

Expected: no output, meaning all 62 keys resolve to commands. If the lookup itself returns nil for every key, general stores override bindings somewhere else. In that case use `(general-lookup-key …)`, or check with `M-x describe-key SPC a …` in a live Emacs, and record which method worked in the commit message.

Run: `grep -n '"ak"\|"ah"\|"ab".*viewport' config.org`. Expected: no output (the old bindings are gone).

- [ ] **Step 3: Commit**

```bash
cd ~/dotfiles && git commit -m "config: SPC a agent leader map with sub-prefixes

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/config.org
```

---

### Task 7: Phase 1 prerequisites + manual acceptance (human in the loop)

The executing agent can't drive the GUI. Ask the user to run these steps and report back. Don't mark the task complete until they have.

- [ ] **Step 1: Ask the user to install the adapters** (outside Emacs)

```bash
npm i -g @zed-industries/claude-agent-acp
brew install terminal-notifier
# codex-acp: install per https://github.com/zed-industries/codex-acp (release binary or cargo)
```
Then restart Emacs (`emacs --with-profile custom`). Expected: no `a3madkour-agents` warning about any program that was just installed.

- [ ] **Step 2: Ask the user to run the spec §4.2 Phase 1 checklist**

1. `SPC a n k`, `SPC a n o` and `SPC a n c` each start a working session.
2. Two Claude sessions in one project both appear in `SPC a l`. `RET` switches between them; `x` kills one.
3. A permission prompt in a hidden session raises a macOS notification and bumps the `AS:` count. `SPC a j` lands on it, in its own perspective.
4. `SPC a s` and `SPC a f` toggle and focus the project sidebar.
5. `SPC a b` bookmarks a session; `bookmark-jump` resumes it after the buffer is killed. `org-store-link` plus opening the link does the same.
6. `SPC a r` gives an issues list; `m` then `S` sends to a shell. Record whether Claude `:login` works; if it doesn't, add a sentence to the `*** Review` prose.
7. `p` on a Finder-copied file in an agent buffer inserts `@file`.
8. `SPC a M m` and `SPC a S c` say "not installed/configured yet".

- [ ] **Step 3: Record results**

Append a `## Phase 1 acceptance — <date>` section to the spec listing pass or fail per item, then commit it with `-- emacs-configs/custom/docs/superpowers/specs/2026-10-11-agent-shell-only-design.md`. Any failure becomes a new task before Phase 2 starts.

---

## Phase 2

### Task 8: meta-agent-shell

**Files:**
- Modify: `lisp/a3madkour-agents.el`, `lisp/a3madkour-agents-test.el`
- Modify: `config.org` (new `*** Meta agent shell` sub-heading after `*** macOS extensions`)
- External: `~/.zshrc` (user's uncommitted file: append one line and don't commit it), `~/.claude/CLAUDE.md` (**confirm with the user first**), `~/.claude-meta/`, `~/.meta-agent-shell/`.

**Interfaces:**
- Consumes (agent-shell): `agent-shell--start (&key config no-focus new-session session-strategy session-id fork-session-id outgoing-request-decorator)` → shell buffer; variable `agent-shell-cwd-function`; `agent-shell-anthropic-make-claude-code-config`.
- Consumes (meta): variable `meta-agent-shell--pending-decorator`. Meta calls the start function as `(funcall fn 'use-current-dir NAME)` or `(funcall fn ARG "Dispatcher")`, then reads `(current-buffer)`. `meta-agent-shell--get-project-path ()`.
- Produces:
  - `a3madkour-agents-meta-config-function`: defcustom, default `#'agent-shell-anthropic-make-claude-code-config`.
  - `a3madkour-agents-meta-start (&optional arg buffer-name)` → the shell buffer, which is also left current.
  - `a3madkour-agents--meta-project-path (orig-fn &rest args)`: `:around` advice.

Calling `agent-shell--start` directly, rather than `agent-shell`, is deliberate. Stock `agent-shell` takes only one argument. The `:session-strategy 'new` keyword sets the strategy buffer-locally before the shell decides whether to prompt; a `let` around the call would have expired by then. Meta's decorator only reaches `agent-shell-start` through its advice, so it has to be passed explicitly.

- [ ] **Step 1: Write the failing tests**

Append to the test file:

```elisp
;;;; meta-agent-shell

(defvar agent-shell-cwd-function nil)
(defvar meta-agent-shell--pending-decorator nil)

(defmacro a3madkour-agents-test--with-fake-start (&rest body)
  "Run BODY with `agent-shell--start' stubbed.
Binds `start-args' (keyword plist received) and `start-cwd' (value of
`agent-shell-cwd-function' at call time, funcalled), and `made' (buffers)."
  (declare (indent 0))
  `(let (start-args start-cwd made)
     (cl-letf (((symbol-function 'agent-shell--start)
                (lambda (&rest args)
                  (setq start-args args
                        start-cwd (and agent-shell-cwd-function
                                       (funcall agent-shell-cwd-function)))
                  (car (push (generate-new-buffer "*fake-agent*") made)))))
       (unwind-protect (progn ,@body)
         (mapc #'kill-buffer (seq-filter #'buffer-live-p made))))))

(ert-deftest a3madkour-agents-test/meta-start-defaults ()
  (let ((a3madkour-agents-meta-config-function (lambda () '((:identifier . claude-code)))))
    (a3madkour-agents-test--with-fake-start
      (let ((buf (a3madkour-agents-meta-start)))
        (should (bufferp buf))
        (should (eq buf (current-buffer)))
        (should (equal '((:identifier . claude-code)) (plist-get start-args :config)))
        (should (eq t (plist-get start-args :new-session)))
        (should (eq 'new (plist-get start-args :session-strategy)))
        (should-not start-cwd)))))

(ert-deftest a3madkour-agents-test/meta-start-use-current-dir-and-name ()
  (let ((a3madkour-agents-meta-config-function #'ignore)
        (default-directory "/tmp/proj/sub/"))
    (a3madkour-agents-test--with-fake-start
      (let ((buf (a3madkour-agents-meta-start 'use-current-dir "Worker")))
        (should (equal "/tmp/proj/sub/" start-cwd))
        (should (equal "Worker" (buffer-name buf)))))))

(ert-deftest a3madkour-agents-test/meta-start-name-collision-is-unique ()
  (let ((a3madkour-agents-meta-config-function #'ignore)
        (taken (get-buffer-create "Dispatcher")))
    (unwind-protect
        (a3madkour-agents-test--with-fake-start
          (let ((buf (a3madkour-agents-meta-start nil "Dispatcher")))
            (should (buffer-live-p buf))
            (should-not (eq buf taken))
            (should (string-prefix-p "Dispatcher" (buffer-name buf)))))
      (kill-buffer taken))))

(ert-deftest a3madkour-agents-test/meta-start-passes-pending-decorator ()
  (let ((a3madkour-agents-meta-config-function #'ignore)
        (meta-agent-shell--pending-decorator #'identity))
    (a3madkour-agents-test--with-fake-start
      (a3madkour-agents-meta-start)
      (should (eq #'identity (plist-get start-args :outgoing-request-decorator))))))

(ert-deftest a3madkour-agents-test/meta-project-path-prefers-project-el ()
  (cl-letf (((symbol-function 'project-current) (lambda (&rest _) 'proj))
            ((symbol-function 'project-root) (lambda (_) "/tmp/root/")))
    (should (equal "/tmp/root/"
                   (a3madkour-agents--meta-project-path (lambda () "/fallback/"))))))

(ert-deftest a3madkour-agents-test/meta-project-path-falls-back ()
  (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil)))
    (should (equal "/fallback/"
                   (a3madkour-agents--meta-project-path (lambda () "/fallback/"))))))
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: TEST command. Expected: the 6 new tests FAIL (`void-function a3madkour-agents-meta-start`, …).

- [ ] **Step 3: Implement**

Insert into the module before `(provide …)`:

```elisp
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
```

Also add meta's CLI to the prerequisite list. In `a3madkour-agents-required-executables`, add this entry:

```elisp
    ("agent-shell-send" . "add straight/repos/meta-agent-shell/bin to PATH (meta-agent-shell)")
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: TEST command. Expected: `Ran 28 tests, 28 results as expected`.

- [ ] **Step 5: Add the config sub-heading**

Insert after the `*** macOS extensions` block:

````org
*** Meta agent shell
[[https://github.com/ElleNajt/meta-agent-shell][meta-agent-shell]] handles multi-agent orchestration. A meta session (=SPC a M m=) gets periodic heartbeats about every shell. Per-project dispatchers (=SPC a M d=) spawn and coordinate named agents, and agents talk to each other through the =bin/= scripts, which call =emacsclient=, hence =server-start= above. =SPC a I= interrupts every shell.

Meta calls its start function with two arguments, which stock =agent-shell= can't take, so =a3madkour-agents-meta-start= stands in. Spawns are always Claude Code with a new session, never the session prompt. Project detection goes through project.el instead of projectile. The heartbeat (every 15 minutes) stays off until =SPC a M h=.

Meta advises =agent-shell-start= globally to add a system prompt to each Claude session. Other agents ignore it.
#+begin_src emacs-lisp
(use-package meta-agent-shell
  :straight (meta-agent-shell :type git :host github :repo "ElleNajt/meta-agent-shell"
                              :files ("meta-agent-shell.el"))
  :after agent-shell
  :demand t
  :custom
  (meta-agent-shell-start-function #'a3madkour-agents-meta-start)
  :config
  (advice-add 'meta-agent-shell--get-project-path :around
              #'a3madkour-agents--meta-project-path)
  (add-to-list 'exec-path
               (expand-file-name "straight/repos/meta-agent-shell/bin" user-emacs-directory)))
#+end_src
````

`:demand t` is needed because meta installs its `agent-shell-start` advice at load time, and `meta-agent-shell-start` is not the only entry point: the CLI scripts call meta's functions through `emacsclient`.

- [ ] **Step 6: External setup** (the agent runs these, except the CLAUDE.md edit)

```bash
mkdir -p ~/.claude-meta ~/.meta-agent-shell/logs
test -f ~/.meta-agent-shell/config.org || printf '#+title: meta-agent-shell config\n' > ~/.meta-agent-shell/config.org
grep -q 'meta-agent-shell/bin' ~/.zshrc || echo 'export PATH="$HOME/emacs-configs/custom/straight/repos/meta-agent-shell/bin:$PATH"' >> ~/.zshrc
ls ~/emacs-configs/custom/straight/repos/meta-agent-shell/ | grep -i -E 'overview|setup'
```

Read the repo's `setup.sh` and find the exact `agent-overview.md` path. **Show the user the line to add to `~/.claude/CLAUDE.md`** (`@<absolute path>/agent-overview.md`) and wait for a yes before appending it. Don't commit `~/.zshrc`; it already has unrelated uncommitted edits.

- [ ] **Step 7: Verify**

Run: BOOT command. Expected: `BOOT-OK`, no new errors.
Run: `cd ~/emacs-configs/custom && emacs --batch --init-directory ~/emacs-configs/custom -l early-init.el -l init.el --eval '(message "META %s %s" meta-agent-shell-start-function (advice-member-p (quote a3madkour-agents--meta-project-path) (quote meta-agent-shell--get-project-path)))' 2>&1 | grep META`
Expected: `META a3madkour-agents-meta-start` followed by a non-nil value.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles && git commit -m "agents: meta-agent-shell with two-arg start wrapper and project.el root

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/lisp/a3madkour-agents.el emacs-configs/custom/lisp/a3madkour-agents-test.el emacs-configs/custom/config.org
```

---

### Task 9: agent-circus containers

**Files:**
- Modify: `lisp/a3madkour-agents.el`, `lisp/a3madkour-agents-test.el`
- Modify: `config.org` (new `*** Containers (agent-circus)` sub-heading)

**Interfaces:**
- Consumes (agent-shell): `agent-shell-cwd ()` → a directory; `agent-shell-get-config (buffer)` → an alist with `:identifier`; the defcustoms `agent-shell-command-prefix` (a function of a buffer → a list of strings, nil allowed) and `agent-shell-path-resolver-function` (a function of a path).
- Produces:
  - `a3madkour-agents-circus-services` (alist identifier → service);
  - `a3madkour-agents-circus-workspace` (`"/workspace/"`);
  - `a3madkour-agents-circus-projects` (a list of root directory names);
  - buffer-local `a3madkour-agents-circus-enabled`, a safe dir-local boolean;
  - `a3madkour-agents-circus-active-p (&optional buffer)`;
  - `a3madkour-agents-circus-command-prefix (buffer)`;
  - `a3madkour-agents-circus-resolve-path (path)`;
  - the command `a3madkour-agents-circus-toggle ()`.

- [ ] **Step 1: Write the failing tests**

Append to the test file:

```elisp
;;;; agent-circus

(defmacro a3madkour-agents-test--with-circus (root on &rest body)
  "Run BODY with agent-shell stubbed: cwd ROOT, circus ON for ROOT if non-nil."
  (declare (indent 2))
  `(let ((a3madkour-agents-circus-projects (and ,on (list ,root))))
     (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () ,root)))
       ,@body)))

(ert-deftest a3madkour-agents-test/circus-prefix-off-is-nil ()
  (a3madkour-agents-test--with-circus "/p/" nil
    (with-temp-buffer
      (should-not (a3madkour-agents-circus-command-prefix (current-buffer))))))

(ert-deftest a3madkour-agents-test/circus-prefix-maps-identifiers ()
  (a3madkour-agents-test--with-circus "/p/" t
    (with-temp-buffer
      (dolist (pair '((claude-code . "claude-code") (codex . "codex") (opencode . "opencode")))
        (cl-letf (((symbol-function 'agent-shell-get-config)
                   (lambda (_) `((:identifier . ,(car pair))))))
          (should (equal (list "agent-circus" "exec" (cdr pair) "--")
                         (a3madkour-agents-circus-command-prefix (current-buffer)))))))))

(ert-deftest a3madkour-agents-test/circus-prefix-unknown-agent-errors ()
  (a3madkour-agents-test--with-circus "/p/" t
    (with-temp-buffer
      (cl-letf (((symbol-function 'agent-shell-get-config)
                 (lambda (_) '((:identifier . gemini-cli)))))
        (should-error (a3madkour-agents-circus-command-prefix (current-buffer))
                      :type 'user-error)))))

(ert-deftest a3madkour-agents-test/circus-dir-local-enables ()
  (a3madkour-agents-test--with-circus "/p/" nil
    (with-temp-buffer
      (setq-local a3madkour-agents-circus-enabled t)
      (should (a3madkour-agents-circus-active-p (current-buffer))))))

(ert-deftest a3madkour-agents-test/circus-resolve-identity-when-off ()
  (a3madkour-agents-test--with-circus "/p/" nil
    (with-temp-buffer
      (should (equal "/p/a.el" (a3madkour-agents-circus-resolve-path "/p/a.el")))
      (should (equal "/workspace/a.el" (a3madkour-agents-circus-resolve-path "/workspace/a.el"))))))

(ert-deftest a3madkour-agents-test/circus-resolve-round-trip ()
  (a3madkour-agents-test--with-circus "/p/" t
    (with-temp-buffer
      (should (equal "/workspace/src/a.el" (a3madkour-agents-circus-resolve-path "/p/src/a.el")))
      (should (equal "/p/src/a.el" (a3madkour-agents-circus-resolve-path "/workspace/src/a.el"))))))

(ert-deftest a3madkour-agents-test/circus-resolve-edges ()
  (a3madkour-agents-test--with-circus "/p/" t
    (with-temp-buffer
      (should (equal "/p/" (a3madkour-agents-circus-resolve-path "/workspace")))
      (should (equal "/workspace/" (a3madkour-agents-circus-resolve-path "/p")))
      (should (equal "/etc/hosts" (a3madkour-agents-circus-resolve-path "/etc/hosts")))
      (should-error (a3madkour-agents-circus-resolve-path "/workspace/../etc/passwd")))))

(ert-deftest a3madkour-agents-test/circus-toggle-flips-project ()
  (a3madkour-agents-test--with-circus "/p/" nil
    (with-temp-buffer
      (a3madkour-agents-circus-toggle)
      (should (member "/p/" a3madkour-agents-circus-projects))
      (a3madkour-agents-circus-toggle)
      (should-not (member "/p/" a3madkour-agents-circus-projects)))))
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: TEST command. Expected: the 8 new tests FAIL with void-function errors.

- [ ] **Step 3: Implement**

Insert into the module before `(provide …)`:

```elisp
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

(defun a3madkour-agents-circus-active-p (&optional buffer)
  "Non-nil if agents for BUFFER (default current) run in agent-circus."
  (with-current-buffer (or buffer (current-buffer))
    (or a3madkour-agents-circus-enabled
        (and (member (a3madkour-agents--circus-root) a3madkour-agents-circus-projects) t))))

(defun a3madkour-agents-circus-command-prefix (buffer)
  "`agent-shell-command-prefix' function: agent-circus exec for BUFFER, or nil."
  (when (a3madkour-agents-circus-active-p buffer)
    (let* ((id (map-elt (agent-shell-get-config buffer) :identifier))
           (service (or (alist-get id a3madkour-agents-circus-services)
                        (user-error "agent-circus has no service for agent `%s'" id))))
      (list "agent-circus" "exec" service "--"))))

(defun a3madkour-agents-circus-resolve-path (path)
  "`agent-shell-path-resolver-function': map PATH between host and container.
Identity unless circus is active for the current buffer."
  (if (not (a3madkour-agents-circus-active-p))
      path
    (let* ((root (a3madkour-agents--circus-root))
           (workspace a3madkour-agents-circus-workspace))
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
       (t path)))))

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
             (if (member root a3madkour-agents-circus-projects) "ON" "OFF")
             root)))
```

In `a3madkour-agents-required-executables`, add:

```elisp
    ("agent-circus" . "uv tool install agent-circus (SPC a C)")
    (("docker" "podman") . "Docker Desktop or Podman (agent-circus)")
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: TEST command. Expected: `Ran 36 tests, 36 results as expected`.

- [ ] **Step 5: Add the config sub-heading**

Insert after `*** Meta agent shell`:

````org
*** Containers (agent-circus)
[[https://github.com/Embedded-Focus/agent-circus][agent-circus]] runs agents in firewalled Docker or Podman containers with the project mounted at =/workspace=. It is a Python CLI (=uv tool install agent-circus=, then =agent-circus build=), not an Emacs package. It is off everywhere until =SPC a C= turns it on for the current project, or a project's =.dir-locals.el= sets =a3madkour-agents-circus-enabled= to =t=. It only applies to shells started after the toggle. When it is off, both hooks below behave as stock, so the built-in devcontainer setup keeps working.
#+begin_src emacs-lisp
(with-eval-after-load 'agent-shell
  (setq agent-shell-command-prefix #'a3madkour-agents-circus-command-prefix)
  (setq agent-shell-path-resolver-function #'a3madkour-agents-circus-resolve-path))
#+end_src
````

- [ ] **Step 6: Verify**

Run: BOOT command. Expected: `BOOT-OK`, no new errors, and warnings for `agent-circus` and `docker/podman` (not installed yet).
Run: TEST command. Expected: 36/36.

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles && git commit -m "agents: per-project agent-circus container mode

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/lisp/a3madkour-agents.el emacs-configs/custom/lisp/a3madkour-agents-test.el emacs-configs/custom/config.org
```

---

### Task 10: agent-shell-to-go (Slack)

**Files:**
- Modify: `lisp/a3madkour-agents.el`, `lisp/a3madkour-agents-test.el`
- Modify: `config.org` (new `*** Slack (agent-shell-to-go)` sub-heading)

**Interfaces:**
- Consumes (to-go): the variables `agent-shell-to-go-bot-token`, `-app-token`, `-channel-id`, `-user-id` and `-authorized-users` (a list of strings), and the function `agent-shell-to-go-setup ()`.
- Produces:
  - `a3madkour-agents-slack-keychain-service` (defcustom, `"agent-shell-to-go"`);
  - `a3madkour-agents-keychain-secret (account)` → a string or nil;
  - `a3madkour-agents-slack-load-credentials ()` → the list of missing account names;
  - the command `a3madkour-agents-slack-connect ()`, the target of `a3madkour-agents-slack-connect-cmd` from Task 2.

- [ ] **Step 1: Write the failing tests**

Append to the test file:

```elisp
;;;; Slack (agent-shell-to-go)

(defvar agent-shell-to-go-bot-token nil)
(defvar agent-shell-to-go-app-token nil)
(defvar agent-shell-to-go-channel-id nil)
(defvar agent-shell-to-go-user-id nil)
(defvar agent-shell-to-go-authorized-users nil)

(defmacro a3madkour-agents-test--with-keychain (items &rest body)
  "Run BODY with Keychain stubbed to ITEMS (alist account -> secret)."
  (declare (indent 1))
  `(let ((agent-shell-to-go-bot-token nil) (agent-shell-to-go-app-token nil)
         (agent-shell-to-go-channel-id nil) (agent-shell-to-go-user-id nil)
         (agent-shell-to-go-authorized-users nil))
     (cl-letf (((symbol-function 'a3madkour-agents-keychain-secret)
                (lambda (account) (cdr (assoc account ,items)))))
       ,@body)))

(ert-deftest a3madkour-agents-test/slack-load-all ()
  (a3madkour-agents-test--with-keychain
      '(("bot-token" . "xoxb-1") ("app-token" . "xapp-1")
        ("channel-id" . "C1") ("user-id" . "U1"))
    (should-not (a3madkour-agents-slack-load-credentials))
    (should (equal "xoxb-1" agent-shell-to-go-bot-token))
    (should (equal "xapp-1" agent-shell-to-go-app-token))
    (should (equal "C1" agent-shell-to-go-channel-id))
    (should (equal '("U1") agent-shell-to-go-authorized-users))))

(ert-deftest a3madkour-agents-test/slack-partial-refuses-connect ()
  (a3madkour-agents-test--with-keychain '(("bot-token" . "xoxb-1"))
    (let (setup-called)
      (cl-letf (((symbol-function 'a3madkour-agents--slack-available-p) (lambda () t))
                ((symbol-function 'agent-shell-to-go-setup)
                 (lambda () (setq setup-called t))))
        (let ((err (should-error (a3madkour-agents-slack-connect) :type 'user-error)))
          (should (string-match-p "app-token" (cadr err)))
          (should (string-match-p "user-id" (cadr err))))
        (should-not setup-called)
        (should-not agent-shell-to-go-authorized-users)))))

(ert-deftest a3madkour-agents-test/slack-connect-calls-setup ()
  (a3madkour-agents-test--with-keychain
      '(("bot-token" . "b") ("app-token" . "a") ("channel-id" . "c") ("user-id" . "u"))
    (let (setup-called)
      (cl-letf (((symbol-function 'a3madkour-agents--slack-available-p) (lambda () t))
                ((symbol-function 'agent-shell-to-go-setup)
                 (lambda () (setq setup-called t))))
        (a3madkour-agents-slack-connect)
        (should setup-called)))))

(ert-deftest a3madkour-agents-test/keychain-secret-missing-is-nil ()
  (cl-letf (((symbol-function 'process-lines)
             (lambda (&rest _) (error "security: item not found"))))
    (should-not (a3madkour-agents-keychain-secret "bot-token"))))
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: TEST command. Expected: the 4 new tests FAIL.

- [ ] **Step 3: Implement**

Insert into the module before `(provide …)`:

```elisp
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
  (message "agent-shell-to-go connected; agent-shell buffers now mirror to Slack"))
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: TEST command. Expected: `Ran 40 tests, 40 results as expected`.

- [ ] **Step 5: Add the config sub-heading**

Insert after `*** Containers (agent-circus)`:

````org
*** Slack (agent-shell-to-go)
[[https://github.com/ElleNajt/agent-shell-to-go][agent-shell-to-go]] mirrors each shell to a Slack thread: you can prompt from your phone, approve permissions with reactions, and use =!yolo= / =!safe= / =!stop=. It **never connects at startup**, because anyone in that Slack thread could drive this Emacs. =SPC a S c= loads the tokens from the Keychain and connects. Only your own Slack user ID is authorized.

One-time setup:
1. Create a Slack app from the repo's =slack-app-manifest.yaml= and install it to the workspace.
2. Store four Keychain items under the service =agent-shell-to-go= with =security add-generic-password -s agent-shell-to-go -a <account> -w <value>=. The accounts are =bot-token= (xoxb), =app-token= (xapp), =channel-id= and =user-id=.
#+begin_src emacs-lisp
(use-package agent-shell-to-go
  :straight (agent-shell-to-go :type git :host github :repo "ElleNajt/agent-shell-to-go")
  :after agent-shell
  :commands (agent-shell-to-go-setup agent-shell-to-go-reconnect-buffer
             agent-shell-to-go-reconnect-all agent-shell-to-go-list-threads
             agent-shell-to-go-send-image agent-shell-to-go-cleanup-old-threads)
  :custom
  (agent-shell-to-go-env-file "/dev/null"))
#+end_src
````

`env-file` is `/dev/null` rather than nil because `agent-shell-to-go--load-env` calls `file-exists-p` on it unguarded. `file-exists-p` on nil signals a `wrong-type-argument` error, while on `/dev/null` it reads an empty file.

- [ ] **Step 6: Verify**

Run: BOOT command. Expected: `BOOT-OK`, no new errors.
Run: TEST command. Expected: 40/40.

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles && git commit -m "agents: agent-shell-to-go with Keychain credentials, connect on demand

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/lisp/a3madkour-agents.el emacs-configs/custom/lisp/a3madkour-agents-test.el emacs-configs/custom/config.org
```

---

### Task 11: emacs-skills

**Files:**
- Modify: `config.org` (new `*** emacs-skills` sub-heading)
- External: the Claude Code plugin install.

**Interfaces:**
- Consumes: the server (Task 4). The skill helper `agent-skill-highlight-mode` gets loaded into Emacs by `emacsclient` at runtime, so there's no feature to `with-eval-after-load` on. `evil-define-minor-mode-key` works before the mode exists.

- [ ] **Step 1: Add the config sub-heading**

Insert after `*** Slack (agent-shell-to-go)`:

````org
*** emacs-skills
[[https://github.com/xenodium/emacs-skills][emacs-skills]] is a Claude Code plugin, not an Emacs package. Skills such as =/open=, =/select=, =/highlight=, =/dired= and =/describe= let the agent act on this Emacs through =emacsclient=, which needs the server above. Install it with
=claude plugin marketplace add xenodium/emacs-skills && claude plugin install emacs-skills@xenodium-emacs-skills=.
Its highlight mode exits on =q=, which evil normal state shadows, so =q= is rebound here.
#+begin_src emacs-lisp
(with-eval-after-load 'evil
  (evil-define-minor-mode-key 'normal 'agent-skill-highlight-mode
    (kbd "q") #'agent-skill-highlight-exit))
#+end_src
````

- [ ] **Step 2: Install the plugin**

```bash
claude plugin marketplace add xenodium/emacs-skills && claude plugin install emacs-skills@xenodium-emacs-skills
claude plugin list 2>/dev/null | grep -i emacs-skills
```
Expected: `emacs-skills` is listed.

- [ ] **Step 3: Verify and commit**

Run: BOOT command. Expected: `BOOT-OK`.

```bash
cd ~/dotfiles && git commit -m "config: emacs-skills highlight q under evil

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- emacs-configs/custom/config.org
```

---

### Task 12: Phase 2 prerequisites + manual acceptance (human in the loop)

- [ ] **Step 1: Ask the user to install the remaining prerequisites**

```bash
uv tool install agent-circus
brew install --cask docker      # or: brew install podman && podman machine init && podman machine start
agent-circus build
exec zsh                        # picks up meta's bin/ on PATH
```
Then they create the Slack app and the Keychain items (Task 10 prose) and restart Emacs. Expected: no `a3madkour-agents` warnings remain.

- [ ] **Step 2: Ask the user to run the spec §4.2 Phase 2 checklist**

1. Ask Claude in a shell to `/open` a file; it opens in this Emacs.
2. `SPC a M d` starts a dispatcher. Ask it to spawn a named agent; the agent appears with no `wrong-number-of-arguments` error and no session prompt.
3. `SPC a S c` connects. A Slack message in the thread reaches the shell, and a reaction approves a permission.
4. `SPC a C` reports ON. `SPC a n k` runs inside the container (`agent-circus ps` shows it), and file links in the shell open the local files.

- [ ] **Step 3: Record results**

Append `## Phase 2 acceptance — <date>` to the spec with pass or fail per item, then commit with an explicit path. Failures become new tasks.
