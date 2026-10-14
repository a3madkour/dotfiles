# lsp-mode: fix the plist mismatch and reach eglot parity

Date: 2026-10-13
Scope: `config.org` (sections `* LSP & Languages`, `** Corfu`, global leader `c` map)

## Problem

Commit `72d477b` moved the config from eglot to lsp-mode, with Corfu/Cape/orderless
already wired to `lsp-completion-at-point`. In practice lsp-mode never finishes
connecting: every workspace stays in `starting`, so no completion capf, no flymake
diagnostics, no eldoc, no code actions.

Evidence from the running Emacs:

- `lib.rs` (rustic, rust-analyzer): `lsp-mode` t, `lsp-completion-mode` nil,
  `flymake-mode` nil; capfs are only `cape-*`.
- `*Messages*`, for every server:
  `Error processing message (wrong-type-argument hash-table-p (:capabilities ...))`
- `LSP_USE_PLISTS` is `"true"` and emacs-lsp-booster emits plists, but
  `(lsp:initialize-result-capabilities '(:capabilities 1))` returns nil while a hash
  table returns the value. This holds for both
  `straight/build/lsp-mode/lsp-protocol.elc` (checked in `emacs -Q` with the env set)
  and `eln-cache/31.1-*/lsp-protocol-*.eln`.

### Root cause

`lsp-protocol.el`'s accessor macros read `lsp-use-plists` at compile time. The
installed byte-code and native code were compiled without `LSP_USE_PLISTS`, most
likely by a straight rebuild inside an Emacs session that predated the
`setenv` in `early-init.el` (early-init tangled 17:39, `.elc` built 17:40 on
2026-10-10).

Native-comp `.eln` filenames hash the source path and content, not the environment,
so rebuilding the `.elc` alone does not replace a stale `.eln`.

## Design

### 1. One-time repair

Rebuild lsp-mode and every straight package that depends on it, purge their
native-compiled files, restart.

- Packages: `"lsp-mode"` plus `(straight-dependents "lsp-mode")` (expected:
  `lean4-mode`, `consult-lsp`, and any others straight reports).
- For each package: `straight-rebuild-package`, then for each `.el` in its
  `straight/build/<pkg>/` directory delete `(comp-el-to-eln-filename file)` if it
  exists.
- Restart Emacs.

This is performed by the command in section 2, run once.

### 2. Plist guard (new `** lsp-mode plist guard` under `* LSP & Languages`)

Placed directly after the `** Lsp` block.

- `a3madkour/lsp-plists-consistent-p`: returns non-nil when
  `(lsp:initialize-result-capabilities '(:capabilities t))` is `t` exactly when
  `lsp-use-plists` is non-nil. Wrapped in `ignore-errors`, because a
  hash-table build may signal on a plist argument; an error counts as inconsistent
  when `lsp-use-plists` is set.
- `(with-eval-after-load 'lsp-protocol ...)`: if the check fails, show
  `display-warning 'lsp-mode` (level `:error`). The warning says that lsp-mode was
  compiled for the other JSON representation and names
  `M-x a3madkour/lsp-rebuild-for-plists`.
- `a3madkour/lsp-rebuild-for-plists` (interactive): runs the section 1 repair for
  lsp-mode and its dependents, then shows a message asking the user to restart
  Emacs.

Warning plus command, not automatic rebuild: the wrong code is already loaded when
the check runs, so a restart is required anyway, and a silent rebuild during boot is
slow and surprising.

### 3. Completion UI extras

In `** Corfu`:

- Enable `corfu-popupinfo-mode` (ships with corfu), with
  `corfu-popupinfo-delay '(0.5 . 0.2)`.

New `** Nerd-icons-corfu` subsection after `** Corfu`:

- `(use-package nerd-icons-corfu :after corfu :config (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))`

### 4. lsp-mode additions

In the `** Lsp` `use-package lsp-mode` `:config`:

- Replace `lsp-signature-auto-activate nil` with
  `lsp-signature-auto-activate '(:on-trigger-char :on-server-request)` and set
  `lsp-signature-render-documentation nil`, so signatures are a single line, like
  eglot's eldoc output.
- All other existing settings stay as they are.

New `use-package consult-lsp` after the lsp-mode block (`:after (consult lsp-mode)`,
`:commands (consult-lsp-symbols consult-lsp-diagnostics)`).

### 5. Leader keys (global `c` "code" map)

Existing: `cr` rename, `ca` code action, `co` organize imports, `cR` workspace
restart. Add:

| Key  | Command | Note |
|------|---------|------|
| `cs` | `consult-lsp-symbols` | new |
| `cd` | `consult-lsp-diagnostics` | new |
| `ce` | `(lsp-execute-code-action-by-kind "refactor.extract")` | restores eglot's `eglot-code-action-extract` |
| `ci` | `(lsp-execute-code-action-by-kind "refactor.inline")` | restores eglot's `eglot-code-action-inline` |

`ce` and `ci` are wrapped in named interactive defuns
(`a3madkour/lsp-code-action-extract`, `a3madkour/lsp-code-action-inline`) so
which-key shows readable labels. `cs`, `cd`, `ce` and `ci` appear only in the
mode-local ein/org-agenda leader maps, not in the global `c` map, so there is no
conflict.

## Verification

This is config, not library code, so it is checked manually against a restarted
Emacs (via `emacsclient -e`):

1. After running `a3madkour/lsp-rebuild-for-plists` and restarting,
   `(a3madkour/lsp-plists-consistent-p)` is t and there is no guard warning.
2. In `lib.rs`: `(lsp-workspaces)` status is `initialized`, `lsp-completion-mode`
   is t, `lsp-completion-at-point` is in `completion-at-point-functions`, and
   `flymake-mode` is t with lsp diagnostics.
3. In an org buffer, harper-ls connects and `*Messages*` has no `hash-table-p`
   error.
4. Corfu popup shows kind icons and the popupinfo doc window; signature appears
   after typing `(` in a Rust call.
5. Guard negative test: byte-compile `lsp-protocol.el` into a scratch directory
   without `LSP_USE_PLISTS`, then in a batch `emacs -Q` with `LSP_USE_PLISTS=true`
   load that `.elc` and the guard predicate. The predicate returns nil.

## Out of scope

- The uncommitted working-tree edits to `config.org` (including the removed
  `** Lexical binding` block). Those belong to the user and are left untouched; only
  the hunks from this change are staged when committing.
- Switching back to eglot, or dropping `LSP_USE_PLISTS`.

## Found during verification

- **Big-repo watch prompt.** harper-ls roots org buffers at the enclosing git
  repo; for `config.org` that is the whole dotfiles repo (4392 directories,
  mostly `straight/` and doom's `.local/`). lsp-mode's blocking
  `lsp--ask-about-watching-big-repo` prompt runs inside the message handler's
  `lsp--cur-workspace` binding, so until it is answered every buffer reports
  harper as its server (rust buffers lose completion). Fix: add `straight`,
  `eln-cache`, `.local`, `.stack-work` to `lsp-file-watch-ignored-directories`
  (4392 → 464, under the 1000 threshold).
- **nerd-icons-corfu never loaded.** `use-package-always-defer` is on, so
  `:after corfu` alone defers it forever; it needs `:demand t`.
