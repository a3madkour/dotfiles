# Retire claude-code.el; agent-shell + extensions only

**Date:** 2026-10-11
**Target:** `emacs-configs/custom/config.org` (`* "AI" "Agents"` and `* Keybindings`), new `custom/lisp/a3madkour-agents.el` + `a3madkour-agents-test.el`.
**agent-shell baseline:** straight checkout `027e4cd` (2026-04-23), `Version: 0.50.1`. Every extension internal referenced below was verified to exist at this commit.

## Goal

Use **agent-shell** as the only agent front-end in Emacs. Remove claude-code.el and its terminal stack. Add as many agent-shell extensions as is practical: multi-session management, attention tracking, notifications, a sidebar, bookmarks, review, orchestration, Slack and containers. Put all of them under one mnemonic `SPC a` leader map.

**Success:**
- Emacs starts cleanly, and nothing in it references claude-code, monet, eat or inheritenv.
- From `SPC a` you can start, list, switch between, interrupt and kill several Claude, OpenCode and Codex sessions per project.
- Waiting sessions show up in the mode-line and trigger a native macOS notification.
- Phase 2 extensions work once their external prerequisites are installed. Until then they fail with a clear message, never at startup.

## Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Code structure | **Hybrid.** config.org holds the use-package blocks, settings, hooks and the `SPC a` map. `lisp/a3madkour-agents.el` holds the named helpers and advice, with ERT tests. |
| Notifications | **agent-shell-macext** only, since there's no D-Bus on this Emacs build. Every other notifier stays off. |
| Window managers | **agent-shell-manager** is the main list. **agent-shell-attention** provides the indicator, the jump commands and a secondary dashboard. **agent-shell-sidebar** is kept for per-project sessions. **agent-shell-workspace is skipped**: it advises `switch-to-buffer` globally and its tab-bar model clashes with perspective.el. |
| Heavy extensions | All included in **Phase 2**: emacs-skills, meta-agent-shell, agent-shell-to-go, agent-circus. |
| Phasing | One spec. **Phase 1** = removal, core cleanup, low-friction extensions and the full keymap, with Phase 2 keys stubbed. **Phase 2** = the four heavy extensions. |
| Key layout | Everything under `SPC a` with sub-prefixes. `SPC k` is retired. |
| Evil in list buffers | Normal state plus remaps. `j`/`k` stay as movement; colliding upstream keys move (see §2.3). |

Not included: agent-shell-workspace (perspective clash), agent-shell-notifications and agent-shell-knockknock (duplicate notifiers; knockknock also depends on an unmerged upstream PR).

---

## Phase 1

### 1.1 Removal

Delete the `** Claude code` subtree from config.org:
- the `inheritenv`, `monet`, `eat` and `claude-code` use-package blocks (with `C-c c`, the `M` repeat-map and the monet hook);
- `a3madkour/eat-send-escape` and the `eat-semi-char-mode-map` evil bindings;
- the attribution paragraph.

Nothing else in config.org uses eat, monet or inheritenv (checked with grep).

Delete the `;; claude` `SPC k` group in `* Keybindings` (`ko kr kt km kd kk kc`).

The straight repos (`claude-code.el`, `monet`, `emacs-eat`, `inheritenv`) are **not** deleted by this work; run `M-x straight-remove-unused-repos` later if you want them gone.

### 1.2 Core agent-shell block

Rewrite `** Agent shell`:
- **Fix:** `agent-shell-prefer-viewport` doesn't exist. Replace it with `agent-shell-prefer-viewport-interaction nil`.
- **Keep, unchanged:**
  - Anthropic `:login` auth, OpenCode `((:none . t))`;
  - `agent-shell-display-action '(display-buffer-pop-up-window)`;
  - `agent-shell-file-completion-enabled t`;
  - `agent-shell-write-inhibit-minor-modes`;
  - evil `RET` / `S-<return>` in `agent-shell-mode-map`;
  - `*agent-shell-diff*` buffers starting in emacs state;
  - the Corfu capf hook.
- **Move** the three inline advice lambdas into `a3madkour-agents.el` as named functions and attach them with `advice-add`:
  - `a3madkour-agents--project-files-truename` (`:around agent-shell--project-files`)
  - `a3madkour-agents--opencode-diff-info` (`:around agent-shell--make-diff-info`)
  - `a3madkour-agents--opencode-permission-title` (`:around agent-shell--permission-title`)

  Their behaviour stays byte-for-byte the same as the current lambdas.
- **Add Codex** as a third agent through the built-in `agent-shell-openai-start-codex`.
- **Server:** `(require 'server) (unless (server-running-p) (server-start))` at the top of the `* "AI" "Agents"` heading. emacs-skills and meta-agent-shell need it.
- **Prerequisite check:** `a3madkour-agents-check-prereqs` runs once after agent-shell loads.
  - It `display-warning`s, once per missing item: `claude-agent-acp`, `codex-acp`, `terminal-notifier`.
  - Phase 2 adds: `agent-circus`, `docker`|`podman`, and meta's `bin/` on PATH.
  - It never signals an error.
- **gitignore:** add `emacs-configs/custom/.agent-shell/` (transcripts, worktrees, macext copies) to the dotfiles root `.gitignore`.

**External prerequisites (Phase 1)**
- `npm i -g @zed-industries/claude-agent-acp`. Not installed today, so agent-shell Claude is currently broken.
- `codex-acp` (Codex ACP adapter). Not installed today.
- `brew install terminal-notifier`. Optional; without it macext falls back to osascript, which only lands in Notification Center.

### 1.3 Phase 1 extensions

Each one gets its own `*** <name>` org sub-heading under `** Agent shell`, installed with `:straight (:host github :repo …)`. None of them is on MELPA.

| Package | Repo | Config |
|---|---|---|
| agent-shell-manager | `jethrokuan/agent-shell-manager` | `agent-shell-manager-side 'bottom`, `agent-shell-manager-transient nil`. |
| agent-shell-attention | `ultronozm/agent-shell-attention.el` | `(agent-shell-attention-mode 1)`, `-indicator-location 'global-mode-string`, `-notify-function nil`. |
| agent-shell-sidebar | `cmacrae/agent-shell-sidebar` | `-position 'right`, `-width "35%"`, `-locked t`, `-default-config (agent-shell-anthropic-make-claude-code-config)`. |
| agent-shell-bookmark | `dcluna/agent-shell-bookmark` | `(require 'agent-shell-bookmark)`, and `(require 'agent-shell-ol)` with `with-eval-after-load 'org`. Requires agent-shell ≥ 0.50.1, which the baseline meets. |
| agent-review | `nineluj/agent-review` | No configuration. |
| agent-shell-macext | `cxa/agent-shell-macext` | `:hook (agent-shell-mode . agent-shell-macext-setup)`, `-notifications t`, `-file-copy-policy 'auto`. |

**Known risk:** agent-review starts its own ACP client and skips agent-shell's authenticate step. Whether it works with Claude `:login` auth has to be checked by hand (§4.2). If it doesn't, document using OpenCode or Codex for reviews.

### 1.4 Evil remaps for extension buffers

`a3madkour-agents-setup-evil` lives in the lisp module. It is called through `with-eval-after-load` for each package and binds in **normal** state.

**`agent-shell-manager-mode`:**

| Key | Command |
|---|---|
| `RET` | goto |
| `x` | kill (upstream `k`) |
| `c` | new |
| `r` | restart |
| `d` | delete-killed |
| `m` | set mode |
| `M` | set model |
| `t` | traffic |
| `l` | toggle logging |
| `gr` | refresh |
| `q` | quit |
| `C-c C-c` | interrupt |

**`agent-shell-attention-dashboard-mode`:**

| Key | Command |
|---|---|
| `RET` | visit |
| `o` | visit in other window |
| `J` | dired (upstream `j`) |
| `D` | kill |
| `gr` | refresh |
| `q` | quit |

**`agent-review-mode`:**

| Key | Command |
|---|---|
| `RET` | jump to issue |
| `m` / `u` | mark / unmark |
| `M` / `U` | mark all / unmark all |
| `S` | send to shell (overrides evil-collection's tabulated sort) |
| `W` | copy issues |
| `gr` | re-run |
| `q` | quit |

**`agent-shell-mode`:** `p` and `P` in normal state call `agent-shell-macext-yank`, so a Finder file pastes as `@file` context.

**`agent-skill-highlight-mode`** (Phase 2): `q` calls `agent-skill-highlight-exit`.

### 1.5 Perspective integration

Manager and attention list sessions from every perspective; that is intentional. Jumping should go to the session's own perspective rather than pulling its buffer into the current one:

- `a3madkour-agents--switch-to-buffer-perspective (buffer)` finds the first perspective whose buffer list contains BUFFER (`persp-all-names` / `persp-get-by-name` / `persp-buffers`) and calls `persp-switch` to it. If no perspective other than the current one owns the buffer, it does nothing.
- It is installed on `agent-shell-attention-before-jump-hook`, and as `:before` advice on `agent-shell-manager-goto` (the buffer comes from `tabulated-list-get-id`).

### 1.6 `SPC a` keymap

This replaces the current `SPC a` group, `ao ak ar ad af ac ah ab`, and the `SPC k` group. `SPC A` (org-archive) is not touched.

**Top level:**

| Key | Command |
|---|---|
| `SPC a a` | `agent-shell` (DWIM; `C-u` forces a new shell, `C-u C-u` picks one) |
| `SPC a t` | `agent-shell-toggle` |
| `SPC a j` | `agent-shell-attention-jump` |
| `SPC a J` | `agent-shell-attention-jump-idle` |
| `SPC a l` | `agent-shell-manager-toggle` |
| `SPC a L` | `agent-shell-attention-dashboard` |
| `SPC a s` | `agent-shell-sidebar-toggle` |
| `SPC a f` | `agent-shell-sidebar-toggle-focus` |
| `SPC a c` | `agent-shell-prompt-compose` |
| `SPC a p` | `agent-shell-jump-to-latest-permission-button-row` |
| `SPC a i` | `agent-shell-interrupt` |
| `SPC a I` | `meta-agent-shell-big-red-button` (Phase 2) |
| `SPC a o` | `agent-shell-other-buffer` |
| `SPC a b` | `bookmark-set` |
| `SPC a r` | `agent-review` |
| `SPC a C` | `a3madkour-agents-circus-toggle` (Phase 2) |
| `SPC a ?` | `agent-shell-help-menu` |

**`SPC a n` — new sessions:**

| Key | Command |
|---|---|
| `k` | `agent-shell-anthropic-start-claude-code` |
| `o` | `agent-shell-opencode-start-agent` |
| `c` | `agent-shell-openai-start-codex` |
| `n` | `agent-shell-new-shell` |
| `w` | `agent-shell-new-worktree-shell` |
| `t` | `agent-shell-new-temp-shell` |
| `D` | `agent-shell-new-downloads-shell` |
| `f` | `agent-shell-fork` |
| `r` | `agent-shell-resume-session` |
| `R` | `agent-shell-restart` |
| `l` | `agent-shell-reload` |
| `P` | `agent-shell-sidebar-change-provider` |
| `X` | `agent-shell-sidebar-reset` |

**`SPC a x` — send context:**

| Key | Command |
|---|---|
| `d` | `agent-shell-send-dwim` |
| `r` | `agent-shell-send-region-to` |
| `f` | `agent-shell-send-file` |
| `F` | `agent-shell-send-other-file` |
| `s` | `agent-shell-send-screenshot` |
| `i` | `agent-shell-send-clipboard-image` |
| `!` | `agent-shell-insert-shell-command-output` |
| `y` | `agent-shell-macext-yank` |

**`SPC a m` — mode and model:**

| Key | Command |
|---|---|
| `m` | `agent-shell-set-session-mode` |
| `v` | `agent-shell-set-session-model` |
| `TAB` | `agent-shell-cycle-session-mode` |

**`SPC a q` — queue:**

| Key | Command |
|---|---|
| `q` | `agent-shell-queue-request` |
| `r` | `agent-shell-resume-pending-requests` |
| `d` | `agent-shell-remove-pending-request` |

**`SPC a M` — meta (Phase 2):**

| Key | Command |
|---|---|
| `m` | `meta-agent-shell-start` |
| `d` | `meta-agent-shell-start-or-dispatcher` |
| `k` | `meta-agent-shell-close-dispatcher` |
| `h` | `meta-agent-shell-heartbeat-start` |
| `H` | `meta-agent-shell-heartbeat-stop` |
| `s` | `meta-agent-shell-heartbeat-send-now` |

**`SPC a S` — Slack (Phase 2):**

| Key | Command |
|---|---|
| `c` | `a3madkour-agents-slack-connect` |
| `r` | `agent-shell-to-go-reconnect-buffer` |
| `R` | `agent-shell-to-go-reconnect-all` |
| `l` | `agent-shell-to-go-list-threads` |
| `i` | `agent-shell-to-go-send-image` |
| `x` | `agent-shell-to-go-cleanup-old-threads` |

**`SPC a d` — debug:**

| Key | Command |
|---|---|
| `t` | `agent-shell-view-traffic` |
| `a` | `agent-shell-view-acp-logs` |
| `l` | `agent-shell-toggle-logging` |
| `u` | `agent-shell-show-usage` |
| `T` | `agent-shell-open-transcript` |
| `y` | `agent-shell-copy-session-id` |

**Phase 2 stubs:**
- In Phase 1 the `SPC a M` and `SPC a S` groups and `SPC a I` / `SPC a C` are bound to `a3madkour-agents--not-configured`-style wrappers.
- When the target command isn't `fboundp`, a wrapper signals `user-error "<pkg> not installed/configured (Phase 2)"`.
- Phase 2 needs no keymap edits: the same wrappers call through once the package loads.

---

## Phase 2

Each package is installed so that a missing prerequisite produces a warning from `a3madkour-agents-check-prereqs`, never a startup error.

### 2.1 emacs-skills

- Install outside Emacs: `claude plugin marketplace add xenodium/emacs-skills && claude plugin install emacs-skills@xenodium-emacs-skills`.
- In Emacs it needs the server (§1.2) and the `q` remap (§1.4).
- Some skills need optional external tools: gnuplot, plantuml, d2, mermaid-cli. Install them as you need them.

### 2.2 meta-agent-shell

- **Install:** `:straight (meta-agent-shell :host github :repo "ElleNajt/meta-agent-shell" :files ("meta-agent-shell.el"))`.
- **One-time setup:**
  - Create `~/.claude-meta/`, `~/.meta-agent-shell/logs/` and `~/.meta-agent-shell/config.org`.
  - Add `straight/repos/meta-agent-shell/bin` to PATH in `~/.zshrc` and to `exec-path`.
  - Add the `@…/agent-overview.md` line to `~/.claude/CLAUDE.md`. **This edit is shown to the user and confirmed before it is made**, because it affects every Claude session.
- **Wrapper:** `a3madkour-agents-meta-start (&optional arg buffer-name)` becomes `meta-agent-shell-start-function`. It:
  - accepts the two arguments meta passes, which stock `agent-shell` doesn't;
  - treats `arg = 'use-current-dir` as "start in `default-directory`";
  - binds `agent-shell-session-strategy` to `'new`, so spawns never stop at the session prompt;
  - starts through `agent-shell`, passing `'(4)` so a new shell is forced;
  - renames the resulting buffer to BUFFER-NAME when that is given;
  - returns the buffer.
- **Project root:** `:around` advice on `meta-agent-shell--get-project-path` (which tries projectile, then `default-directory`) resolves with `project-current` / `project-root` first.
- **Heartbeat:** off by default; start it with `SPC a M h`. Interval stays at 900 s.
- **Known side effect:** meta advises `agent-shell-start` globally to add `_meta.systemPrompt.append` to `session/new`. Claude uses it; other agents ignore it.

### 2.3 agent-shell-to-go (Slack)

- **Install:** `:straight (agent-shell-to-go :host github :repo "ElleNajt/agent-shell-to-go")`. `websocket` is already present.
- **Credentials:** read with `auth-source` from macOS Keychain (`auth-source-macos-keychain-*`): bot token (xoxb), app token (xapp), channel ID and user ID. Nothing secret goes in the repo.
  - `-authorized-users` is set to only the user's own Slack ID.
  - `-env-file nil`.
- **Never auto-connects.** `a3madkour-agents-slack-connect` loads the credentials, sets the variables and calls `agent-shell-to-go-setup`. Nothing in init calls setup, because Slack can drive Emacs remotely.
- **Manual steps** (go in the config.org prose): create the Slack app from `slack-app-manifest.yaml`, install it to the workspace, and store the tokens in Keychain.

### 2.4 agent-circus (Docker)

- **Install outside Emacs:** `uv tool install agent-circus`, plus Docker Desktop or Podman (neither is installed today), then `agent-circus build`.
- **Per-project toggle:** `a3madkour-agents-circus-mode` is a buffer-local variable that can also be set in `.dir-locals.el`. `a3madkour-agents-circus-toggle` (`SPC a C`) flips it for every buffer in the current project and reports the new state.
- `agent-shell-command-prefix` is set to `a3madkour-agents-circus-command-prefix (buffer)`:
  - It returns nil when circus is off for that buffer's project. Stock behaviour, so devcontainer still works.
  - Otherwise it returns `("agent-circus" "exec" SERVICE "--")`.
  - SERVICE comes from `(map-elt (agent-shell-get-config buffer) :identifier)`: `claude-code`→`claude`, `codex`→`codex`, `opencode`→`opencode`; anything else is `user-error`.
- `agent-shell-path-resolver-function` is set to `a3madkour-agents-circus-resolve-path (path)`. When circus is on it maps between `/workspace/…` and `<project-root>/…` in both directions; otherwise it returns PATH unchanged.

---

## 3. Error handling

- Every extension `use-package` uses deferred loading (`:commands` / `:hook` / `:after agent-shell`), so a failed clone or missing package never aborts init.
- `a3madkour-agents-check-prereqs` reports missing binaries with `display-warning` (type `a3madkour-agents`), once per session.
- Phase 2 keys go through the not-configured wrappers (§1.6) until their package loads.
- Slack connects only when asked.
- Circus is off unless enabled per project.

## 4. Testing

### 4.1 Automated (ERT)

`custom/lisp/a3madkour-agents-test.el` runs the same way as the existing publish tests (`emacs -batch -L lisp -l ert -l lisp/a3madkour-agents-test.el -f ert-run-tests-batch-and-exit`). It uses stubbed agent-shell functions and fixture ACP alists, so neither the agent nor the network is needed.

- `--opencode-diff-info`:
  - passes the original value through when it is non-nil;
  - maps `oldString`/`newString`/`filePath`/`filepath`;
  - handles a missing `oldString` as `""`.
- `--opencode-permission-title`:
  - passes a non-generic title through;
  - recovers the command from saved state;
  - wraps an `execute` kind in a console code fence.
- `--project-files-truename`: `default-directory` is bound to its truename while the original function runs.
- `meta-start`:
  - accepts 0, 1 and 2 arguments;
  - handles `use-current-dir`;
  - renames the buffer;
  - binds the session strategy to `new`.
- `circus-command-prefix`:
  - returns nil when off;
  - maps each identifier;
  - signals `user-error` for an unknown agent.
- `circus-resolve-path`:
  - round-trips both directions;
  - leaves paths outside the project alone;
  - is the identity when off.
- Not-configured wrappers: `user-error` when the target isn't `fboundp`; call through when it is.
- `--switch-to-buffer-perspective`: switches to the perspective that owns the buffer, and does nothing when no other perspective owns it (stubbed persp API).

### 4.2 Integration

- **Startup:** `emacs --batch -l init.el` (or the repo's usual boot check) finishes with no errors. `grep -n 'claude-code\|monet\|\beat\b\|inheritenv' config.org` returns nothing.
- **Manual checklist, Phase 1:**
  1. `SPC a n k`, `SPC a n o` and `SPC a n c` each start a working session.
  2. Two Claude sessions in one project both appear in `SPC a l`. `RET` switches between them; `x` kills one.
  3. A permission prompt in a hidden session raises a macOS notification and bumps the `AS:` mode-line count. `SPC a j` lands on it, in its own perspective.
  4. `SPC a s` / `SPC a f` toggle and focus the project sidebar.
  5. `SPC a b` bookmarks a session; `bookmark-jump` resumes it after the buffer is killed. `org-store-link` plus opening the link does the same.
  6. `SPC a r` produces an issues list. `m` and then `S` sends the marked issues to a shell. If Claude `:login` fails here, record that.
  7. Pasting a Finder file with `p` in an agent buffer inserts `@file`.
  8. `SPC a M m` and `SPC a S c` report "not installed/configured" until Phase 2 is done.
- **Manual checklist, Phase 2:**
  1. The agent opens a file in Emacs through emacs-skills `/open`.
  2. `SPC a M d` starts a dispatcher, and the dispatcher spawns a named agent with no `wrong-number-of-arguments` error.
  3. `SPC a S c` connects; a Slack message in the thread reaches the shell, and a reaction approves a permission.
  4. `SPC a C` turns circus on; `SPC a n k` runs inside the container, and file links resolve to local paths.

## 5. File map

| File | Change |
|---|---|
| `custom/config.org` | Delete `** Claude code`. Rewrite `** Agent shell`, adding the server, prerequisite check and Codex. Add one `***` per extension (Phase 1 and 2). Replace the `SPC a` group; delete the `SPC k` group. |
| `custom/lisp/a3madkour-agents.el` | New. Advice functions, evil setup, perspective jump, not-configured wrappers, prerequisite check, meta wrapper, circus prefix, resolver and toggle, Slack connect. |
| `custom/lisp/a3madkour-agents-test.el` | New. ERT tests per §4.1. |
| `dotfiles/.gitignore` | Add `emacs-configs/custom/.agent-shell/`. |
| `~/.zshrc`, `~/.claude/CLAUDE.md`, Keychain, `~/.claude-meta` | Phase 2 external setup. CLAUDE.md is confirmed with the user before it is edited. |
