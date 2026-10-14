# lsp-mode Plist Fix and eglot Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make lsp-mode actually connect (fix the plist/hash-table compile mismatch), guard against the mismatch recurring, and add the Corfu/consult/signature extras so the setup matches or exceeds what eglot gave.

**Architecture:** All config lives in literate `config.org`, tangled to `config.el` by `org-babel-load-file` at startup (`init.el`). New top-level `a3madkour/` defuns are picked up automatically by the ERT loader in `tests/test-helpers.el`, which is how the guard predicate gets unit-tested without lsp-mode installed in batch. Package changes go through straight.el (`straight-use-package-by-default` is t).

**Tech Stack:** Emacs 31, straight.el, lsp-mode (with `LSP_USE_PLISTS` + emacs-lsp-booster), corfu, cape, orderless, nerd-icons-corfu, consult-lsp, general.el leader keys, ERT.

**Spec:** `docs/superpowers/specs/2026-10-13-lsp-mode-parity-design.md`

---

## Ground rules for this repo

- **The working tree has user edits that are not ours.** `config.org` and `tests/run.sh` both carry uncommitted user changes (e.g. the deleted `** Lexical binding` block). Never `git add config.org` or `git add tests/run.sh` whole. Stage only our hunks with the snapshot-diff method below.
- **Snapshot-diff staging.** Before the first edit to a user-modified file in a task:
  ```bash
  S=/tmp/claude-1000/-Stuff-a3madkour-dotfiles-emacs-configs-custom/3842745a-4534-4e33-b353-0cf3049e7762/scratchpad
  cp config.org "$S/config.org.before"
  ```
  At commit time:
  ```bash
  diff -u --label a/emacs-configs/custom/config.org --label b/emacs-configs/custom/config.org \
    "$S/config.org.before" config.org > "$S/ours.patch"
  (cd "$(git rev-parse --show-toplevel)" && git apply --cached --recount "$S/ours.patch")
  git diff --cached --stat   # must list only our files/hunks
  ```
  `git apply --cached` applies against the index (HEAD), so the user's unrelated hunks near the top of the file stay unstaged; our hunks are far away and apply with an offset. If it reports a conflict, stop and ask the user.
- **Live Emacs checks** use `emacsclient -e`. For any form containing regex backslashes or nested quotes, write it to `$S/q.el` and evaluate with:
  ```bash
  emacsclient -e "(with-temp-buffer (insert-file-contents \"$S/q.el\") (eval (read (current-buffer)) t))"
  ```
- The ERT suite: `./tests/run.sh` (currently 156/156 passing).

## File map

| File | Change |
|------|--------|
| `config.org` `** Lsp` (~line 1279) | signature-help settings; consult-lsp block |
| `config.org` new `** lsp-mode plist guard` (after `** Lsp`) | predicate, rebuild command, startup warning |
| `config.org` `** Corfu` (~line 863) | corfu-popupinfo; new `** Nerd-icons-corfu` subsection |
| `config.org` global leader `;;code/lsp` (~line 5516) | `cs` `cd` `ce` `ci` + two named defuns near the guard |
| `tests/test-lsp-plists.el` (new) | ERT tests for the guard predicate |
| `tests/run.sh` | load the new test file |

---

### Task 1: Guard predicate (TDD)

**Files:**
- Create: `tests/test-lsp-plists.el`
- Modify: `tests/run.sh` (the `for f in ...` list)
- Modify: `config.org` (new `** lsp-mode plist guard` heading after the `** Lsp` src block, i.e. right after the `(use-package eldoc ...)` block's `#+end_src`, before `** Format all`)

- [ ] **Step 1: Snapshot both user-modified files**

```bash
cd /Stuff/a3madkour/dotfiles/emacs-configs/custom
S=/tmp/claude-1000/-Stuff-a3madkour-dotfiles-emacs-configs-custom/3842745a-4534-4e33-b353-0cf3049e7762/scratchpad
cp config.org "$S/config.org.before"
cp tests/run.sh "$S/run.sh.before"
```

- [ ] **Step 2: Write the failing test**

Create `tests/test-lsp-plists.el`:

```elisp
;;; test-lsp-plists.el --- lsp-mode plist guard tests  -*- lexical-binding: t; -*-

;; `a3madkour/lsp-plists-consistent-p' is loaded from config.org by
;; test-helpers.el.  lsp-mode is not available in batch, so the compiled
;; accessor is stubbed with a plist-reading or a hash-reading version.

(require 'ert)
(require 'cl-lib)

(defvar lsp-use-plists)

(defun a3madkour-test/plist-accessor (x)
  (plist-get x :capabilities))

(defun a3madkour-test/hash-accessor (x)
  (gethash "capabilities" x))

(defmacro a3madkour-test/with-lsp-build (plists accessor &rest body)
  "Run BODY with `lsp-use-plists' bound to PLISTS and the accessor stubbed."
  (declare (indent 2))
  `(let ((lsp-use-plists ,plists))
     (cl-letf (((symbol-function 'lsp:initialize-result-capabilities)
                ,accessor))
       ,@body)))

(ert-deftest lsp-plists-consistent-plist-build-plist-env ()
  (a3madkour-test/with-lsp-build "true" #'a3madkour-test/plist-accessor
    (should (a3madkour/lsp-plists-consistent-p))))

(ert-deftest lsp-plists-inconsistent-hash-build-plist-env ()
  "The bug: hash-table byte-code with LSP_USE_PLISTS set."
  (a3madkour-test/with-lsp-build "true" #'a3madkour-test/hash-accessor
    (should-not (a3madkour/lsp-plists-consistent-p))))

(ert-deftest lsp-plists-inconsistent-nil-returning-build-plist-env ()
  "The live stale build returned nil on a plist instead of signalling."
  (a3madkour-test/with-lsp-build "true" #'ignore
    (should-not (a3madkour/lsp-plists-consistent-p))))

(ert-deftest lsp-plists-consistent-hash-build-hash-env ()
  (a3madkour-test/with-lsp-build nil #'a3madkour-test/hash-accessor
    (should (a3madkour/lsp-plists-consistent-p))))

(ert-deftest lsp-plists-inconsistent-plist-build-hash-env ()
  (a3madkour-test/with-lsp-build nil #'a3madkour-test/plist-accessor
    (should-not (a3madkour/lsp-plists-consistent-p))))

;;; test-lsp-plists.el ends here
```

In `tests/run.sh`, add the file to the loop list after `tests/boox-tests.el`:

```bash
         tests/boox-tests.el \
         tests/test-lsp-plists.el; do
```

(and remove the `; do` from the `tests/boox-tests.el` line).

- [ ] **Step 3: Run test to verify it fails**

Run: `./tests/run.sh lsp-plists`
Expected: 5 tests FAIL with `(void-function a3madkour/lsp-plists-consistent-p)`.

- [ ] **Step 4: Write the predicate in config.org**

Insert after the `** Lsp` section's closing `#+end_src` (the block ending with the `use-package eldoc` form), before `** Format all`:

````org
** lsp-mode plist guard
=lsp-protocol.el='s accessor macros read =lsp-use-plists= at /compile/ time.
Byte- or native-code built where =LSP_USE_PLISTS= was unset (e.g. a straight
rebuild inside a session that predates the =setenv= in early-init) reads the
booster's plists as hash tables, and every server stalls at its initialize
response with =wrong-type-argument hash-table-p=. Rebuilding the =.elc= alone
is not enough: =.eln= names hash the source, not the environment, so the stale
native code keeps loading. This checks a compiled accessor at load time and
points at the fix.
#+begin_src emacs-lisp
(defun a3madkour/lsp-plists-consistent-p ()
  "Non-nil when lsp-mode's compiled accessors match `lsp-use-plists'."
  (defvar lsp-use-plists)
  (let ((plist-build (eq t (ignore-errors
                             (lsp:initialize-result-capabilities
                              '(:capabilities t))))))
    (eq plist-build (and lsp-use-plists t))))
#+end_src
````

The defun must start at column 0 so `tests/test-helpers.el` picks it up.

- [ ] **Step 5: Run tests to verify they pass**

Run: `./tests/run.sh lsp-plists`
Expected: `Ran 5 tests, 5 results as expected, 0 unexpected`

Run: `./tests/run.sh`
Expected: `Ran 161 tests, 161 results as expected, 0 unexpected`

- [ ] **Step 6: Commit (our hunks only)**

```bash
diff -u --label a/emacs-configs/custom/config.org --label b/emacs-configs/custom/config.org \
  "$S/config.org.before" config.org > "$S/ours.patch"
diff -u --label a/emacs-configs/custom/tests/run.sh --label b/emacs-configs/custom/tests/run.sh \
  "$S/run.sh.before" tests/run.sh >> "$S/ours.patch"
(cd "$(git rev-parse --show-toplevel)" && git apply --cached --recount "$S/ours.patch")
git add tests/test-lsp-plists.el
git diff --cached --stat
git commit -m "feat(lsp): predicate detecting plist/hash-table compile mismatch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected `--stat`: `config.org`, `tests/run.sh`, `tests/test-lsp-plists.el` only, with small line counts (no 40-line deletion from the user's edits).

---

### Task 2: Rebuild command and startup warning

**Files:**
- Modify: `config.org` (the `** lsp-mode plist guard` src block from Task 1)

- [ ] **Step 1: Snapshot**

```bash
cp config.org "$S/config.org.before"
```

- [ ] **Step 2: Add the command and the warning**

Append to the `** lsp-mode plist guard` src block, after `a3madkour/lsp-plists-consistent-p`:

```elisp
(defun a3madkour/lsp-rebuild-for-plists ()
  "Rebuild lsp-mode and its dependents for the current `lsp-use-plists'.
Also deletes their native-compiled files, which would otherwise survive the
rebuild.  Emacs must be restarted afterwards to load the new code."
  (interactive)
  (dolist (pkg (cons "lsp-mode" (straight-dependents "lsp-mode")))
    (straight-rebuild-package pkg)
    (dolist (el (directory-files (straight--build-dir pkg) t "\\.el\\'"))
      (let ((eln (comp-el-to-eln-filename el)))
        (when (file-exists-p eln)
          (delete-file eln)))))
  (message "Rebuilt lsp-mode and its dependents; restart Emacs to load them."))

(with-eval-after-load 'lsp-protocol
  (unless (a3madkour/lsp-plists-consistent-p)
    (display-warning
     'lsp-mode
     (format "lsp-mode was compiled for %s but lsp-use-plists is %S; servers will not initialize.  Run M-x a3madkour/lsp-rebuild-for-plists and restart."
             (if lsp-use-plists "hash tables" "plists")
             lsp-use-plists)
     :error)))
```

- [ ] **Step 3: Verify the live session detects the current bad build**

The running Emacs still has the stale code loaded. Write `$S/q.el`:

```elisp
(progn
  (defun a3madkour/lsp-plists-consistent-p ()
    (defvar lsp-use-plists)
    (let ((plist-build (eq t (ignore-errors
                               (lsp:initialize-result-capabilities
                                '(:capabilities t))))))
      (eq plist-build (and lsp-use-plists t))))
  (a3madkour/lsp-plists-consistent-p))
```

Run the `emacsclient` eval wrapper from the ground rules.
Expected: `nil`

- [ ] **Step 4: Confirm the suite still passes**

Run: `./tests/run.sh`
Expected: `Ran 161 tests, 161 results as expected, 0 unexpected`

- [ ] **Step 5: Commit (our hunks only)**

```bash
diff -u --label a/emacs-configs/custom/config.org --label b/emacs-configs/custom/config.org \
  "$S/config.org.before" config.org > "$S/ours.patch"
(cd "$(git rev-parse --show-toplevel)" && git apply --cached --recount "$S/ours.patch")
git diff --cached --stat
git commit -m "feat(lsp): warn on plist mismatch and add rebuild command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Corfu extras (popupinfo + nerd-icons-corfu)

**Files:**
- Modify: `config.org` `** Corfu` block (~line 866)

- [ ] **Step 1: Snapshot**

```bash
cp config.org "$S/config.org.before"
```

- [ ] **Step 2: Edit the Corfu block**

Replace:

```elisp
(use-package corfu
  :custom
  (corfu-auto t)
  :init
  (global-corfu-mode))
```

with:

```elisp
(use-package corfu
  :custom
  (corfu-auto t)
  (corfu-popupinfo-delay '(0.5 . 0.2))
  :init
  (global-corfu-mode)
  (corfu-popupinfo-mode))
```

Directly after that block's `#+end_src`, before `** Cape`, add:

````org
** Nerd-icons-corfu
Kind icons in the Corfu popup, from the [[https://github.com/LuigiPiucco/nerd-icons-corfu][nerd-icons-corfu README]].
#+begin_src emacs-lisp
(use-package nerd-icons-corfu
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))
#+end_src
````

- [ ] **Step 3: Install and check in the live session**

Write `$S/q.el`:

```elisp
(progn
  (straight-use-package 'nerd-icons-corfu)
  (require 'nerd-icons-corfu)
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter)
  (setq corfu-popupinfo-delay '(0.5 . 0.2))
  (corfu-popupinfo-mode 1)
  (list (memq #'nerd-icons-corfu-formatter corfu-margin-formatters)
        corfu-popupinfo-mode))
```

Run via the eval wrapper.
Expected: a non-nil list followed by `t`, e.g. `((nerd-icons-corfu-formatter) t)`.

- [ ] **Step 4: Commit (our hunks only)**

```bash
diff -u --label a/emacs-configs/custom/config.org --label b/emacs-configs/custom/config.org \
  "$S/config.org.before" config.org > "$S/ours.patch"
(cd "$(git rev-parse --show-toplevel)" && git apply --cached --recount "$S/ours.patch")
git diff --cached --stat
git commit -m "feat(corfu): popupinfo docs and nerd-icons kind icons

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Signature help, consult-lsp, leader keys

**Files:**
- Modify: `config.org` `** Lsp` block (~line 1304), `** lsp-mode plist guard` section, global leader `;;code/lsp` (~line 5516)

- [ ] **Step 1: Snapshot**

```bash
cp config.org "$S/config.org.before"
```

- [ ] **Step 2: Signature help in the lsp-mode `:config`**

Replace:

```elisp
  ;; Trim the UI down to roughly what eglot showed.
  (setq lsp-headerline-breadcrumb-enable nil
        lsp-lens-enable nil
        lsp-modeline-code-actions-enable nil
        lsp-signature-auto-activate nil
        lsp-eldoc-render-all nil
        lsp-enable-symbol-highlighting nil
        lsp-enable-on-type-formatting nil))
```

with:

```elisp
  ;; Trim the UI down to roughly what eglot showed.
  (setq lsp-headerline-breadcrumb-enable nil
        lsp-lens-enable nil
        lsp-modeline-code-actions-enable nil
        lsp-eldoc-render-all nil
        lsp-enable-symbol-highlighting nil
        lsp-enable-on-type-formatting nil)
  ;; One-line signatures while typing a call, like eglot's eldoc output.
  (setq lsp-signature-auto-activate '(:on-trigger-char :on-server-request)
        lsp-signature-render-documentation nil))

(use-package consult-lsp
  :after (consult lsp-mode)
  :commands (consult-lsp-symbols consult-lsp-diagnostics))
```

- [ ] **Step 3: Named code-action commands**

These are unrelated to the guard, so add a new heading directly after the `** lsp-mode plist guard` section:

````org
** lsp code actions
eglot shipped =eglot-code-action-extract= / =-inline=; lsp-mode only has the
generic by-kind command, so these give the leader keys readable names.
#+begin_src emacs-lisp
(defun a3madkour/lsp-code-action-extract ()
  "Run an extract refactoring code action at point."
  (interactive)
  (lsp-execute-code-action-by-kind "refactor.extract"))

(defun a3madkour/lsp-code-action-inline ()
  "Run an inline refactoring code action at point."
  (interactive)
  (lsp-execute-code-action-by-kind "refactor.inline"))
#+end_src
````

- [ ] **Step 4: Leader keys**

In the global leader block, replace:

```elisp
 "cr" 'lsp-rename
 "ca" 'lsp-execute-code-action
 "co" 'lsp-organize-imports
 "cR" 'lsp-workspace-restart
```

with:

```elisp
 "cr" 'lsp-rename
 "ca" 'lsp-execute-code-action
 "ce" '(a3madkour/lsp-code-action-extract :which-key "extract")
 "ci" '(a3madkour/lsp-code-action-inline :which-key "inline")
 "co" 'lsp-organize-imports
 "cR" 'lsp-workspace-restart
 "cs" '(consult-lsp-symbols :which-key "workspace symbols")
 "cd" '(consult-lsp-diagnostics :which-key "workspace diagnostics")
```

Confirm uniqueness first: `grep -n '"cr" .lsp-rename' config.org` must print exactly one line.

- [ ] **Step 5: Suite still passes (the new a3madkour defuns load in batch)**

Run: `./tests/run.sh`
Expected: `Ran 161 tests, 161 results as expected, 0 unexpected` (the loader evaluates `defun` forms without calling them, so `lsp-execute-code-action-by-kind` being unbound in batch is fine).

- [ ] **Step 6: Commit (our hunks only)**

```bash
diff -u --label a/emacs-configs/custom/config.org --label b/emacs-configs/custom/config.org \
  "$S/config.org.before" config.org > "$S/ours.patch"
(cd "$(git rev-parse --show-toplevel)" && git apply --cached --recount "$S/ours.patch")
git diff --cached --stat
git commit -m "feat(lsp): signature help, consult-lsp, extract/inline/symbol keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Repair the installed build and verify end to end

No file changes. This touches `straight/build/` and `eln-cache/` (both untracked build output).

- [ ] **Step 1: Install consult-lsp first so it is rebuilt as a dependent**

Write `$S/q.el`:

```elisp
(progn (straight-use-package 'consult-lsp)
       (straight-dependents "lsp-mode"))
```

Run via the eval wrapper.
Expected: a list containing `"lean4-mode"` and `"consult-lsp"`.

- [ ] **Step 2: Run the rebuild in the live session**

The live session has `LSP_USE_PLISTS=true`, so the rebuild compiles correctly. Write `$S/q.el` with the full body of `a3madkour/lsp-rebuild-for-plists` from Task 2 wrapped in `(progn (defun ...) (a3madkour/lsp-rebuild-for-plists))`, then run via the eval wrapper (allow up to 5 minutes: `timeout 300 emacsclient ...`).
Expected: `"Rebuilt lsp-mode and its dependents; restart Emacs to load them."`

Then check the stale eln is gone:

```bash
ls ~/emacs-configs/custom/eln-cache/31.1-*/lsp-protocol-* 2>&1
```

Expected: `No such file or directory`.

- [ ] **Step 3: Check the rebuilt .elc in a clean Emacs**

```bash
cd ~/emacs-configs/custom/straight/build
LSP_USE_PLISTS=true emacs -Q --batch -L lsp-mode -L dash -L f -L ht -L s -L spinner -L lv -L markdown-mode \
  --eval '(progn (setq load-no-native t) (load (expand-file-name "lsp-mode/lsp-protocol.elc") nil t) (princ (format "result=%S\n" (lsp:initialize-result-capabilities (list :capabilities 1)))))' 2>&1 | grep result=
```

Expected: `result=1` (before the fix this printed `result=nil`).

- [ ] **Step 4: Ask the user to restart Emacs**

Do not kill their Emacs yourself. Ask them to restart it and to open a Rust file and an org file. Wait for confirmation.

- [ ] **Step 5: Verify the restarted session**

Write `$S/q.el`:

```elisp
(list
 :consistent (a3madkour/lsp-plists-consistent-p)
 :buffers
 (delq nil
       (mapcar
        (lambda (b)
          (with-current-buffer b
            (when (bound-and-true-p lsp-mode)
              (list (buffer-name)
                    (mapcar (lambda (w) (list (lsp--workspace-server-id w)
                                              (lsp--workspace-status w)))
                            (lsp-workspaces))
                    :completion (bound-and-true-p lsp-completion-mode)
                    :capf (and (memq #'lsp-completion-at-point completion-at-point-functions) t)
                    :flymake (bound-and-true-p flymake-mode)))))
        (buffer-list)))
 :hash-errors
 (with-current-buffer "*Messages*"
   (save-excursion (goto-char (point-min))
                   (and (search-forward "hash-table-p" nil t) t))))
```

Run via the eval wrapper.
Expected: `:consistent t`; every listed buffer shows its servers in `initialized`, `:completion t :capf t :flymake t` for the Rust buffer; `:hash-errors nil`.

Note: native-comp will re-create the lsp-mode `.eln` files asynchronously after restart; that is expected, and they are now built with the env set.

- [ ] **Step 6: Interactive smoke check (ask the user)**

Ask the user to confirm in the Rust buffer:
- Typing an identifier prefix shows Corfu with kind icons and, after a pause, a doc popup.
- Typing `foo(` inside a call shows a one-line signature in the echo area.
- `SPC c s` opens consult-lsp symbols; `SPC c d` lists diagnostics.

---

### Task 6: Guard negative test against a real hash-table build

No file changes.

- [ ] **Step 1: Compile lsp-protocol without the env into scratch, then probe with the env set**

```bash
S=/tmp/claude-1000/-Stuff-a3madkour-dotfiles-emacs-configs-custom/3842745a-4534-4e33-b353-0cf3049e7762/scratchpad
mkdir -p "$S/hashbuild"
cp ~/emacs-configs/custom/straight/build/lsp-mode/lsp-protocol.el "$S/hashbuild/"
B=~/emacs-configs/custom/straight/build
env -u LSP_USE_PLISTS emacs -Q --batch -L $B/dash -L $B/f -L $B/ht -L $B/s -L $B/lsp-mode \
  -f batch-byte-compile "$S/hashbuild/lsp-protocol.el" 2>&1 | tail -2
LSP_USE_PLISTS=true emacs -Q --batch -L $B/dash -L $B/f -L $B/ht -L $B/s \
  --eval "(progn (setq load-no-native t) (load \"$S/hashbuild/lsp-protocol.elc\" nil t)
           (defun a3madkour/lsp-plists-consistent-p ()
             (defvar lsp-use-plists)
             (let ((plist-build (eq t (ignore-errors (lsp:initialize-result-capabilities '(:capabilities t))))))
               (eq plist-build (and lsp-use-plists t))))
           (princ (format \"plists=%S consistent=%S\n\" lsp-use-plists (a3madkour/lsp-plists-consistent-p))))" 2>&1 | grep plists=
```

Expected: `plists="true" consistent=nil`

---

## Self-review notes

- Spec §1 (one-time repair) → Task 5. §2 (guard) → Tasks 1–2. §3 (Corfu extras) → Task 3. §4 (signature, consult-lsp) → Task 4. §5 (leader keys) → Task 4. Verification 1–4 → Task 5; verification 5 → Task 6.
- Names used consistently: `a3madkour/lsp-plists-consistent-p`, `a3madkour/lsp-rebuild-for-plists`, `a3madkour/lsp-code-action-extract`, `a3madkour/lsp-code-action-inline`.
