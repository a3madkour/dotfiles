# Emacs publish-author helpers (Tier 5.2)

**Date:** 2026-06-08
**Status:** designed; plan + impl next
**Scope:** dotfiles — one new module `a3madkour-publish-author.el` + sibling test + two thin public wrappers in `a3madkour-publish-library.el`
**Roadmap row:** Tier 5.2 in [`a3madkour.github.io/docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md`](https://github.com/a3madkour/a3madkour.github.io/blob/master/docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md)
**Source memo:** `.claude/memory/project_emacs_publish_helpers_followup.md` (site repo)

## §1. Why

Phase 3 sub-projects A + B shipped the publish-side pipeline (annotate org files, run `a3-pub.sh --publish-living`, B handlers emit to `content/` / `data/`). The author-side ergonomics are still bare:

- Marking a single note for publish requires manually editing `#+HUGO_PUBLISH: t` + `#+HUGO_SECTION: <section>` into the file's preamble — and remembering which `<section>` strings are valid.
- Adding a library item requires remembering the per-medium drawer-property names (`:CREATOR:` / `:YEAR:` / `:STATUS:` / per-medium extras like `:ISBN:` / `:MBID:` / `:IGDB_ID:` / `:RUNTIME_MIN:` etc.) and the valid status enum (different per medium).
- No fast way to query a note's current publish status or jump from an emitted bundle back to its org source.

The helpers are pure ergonomics — they compose existing primitives and don't change any publish-side behavior. They unblock the "I want to publish a new note / library item / look up what's published right now" loop without leaving Emacs.

## §2. Scope

**v1 ships six commands** (all interactive, all in one module):

| Command | Purpose |
|---|---|
| `a3-publish-mark` | Set / update `#+HUGO_PUBLISH: t` + `#+HUGO_SECTION:` in the current org buffer |
| `a3-publish-unmark` | Flip `#+HUGO_PUBLISH:` to `nil` (preserves keyword line + `HUGO_SECTION`) |
| `a3-publish-status` | Minibuffer message describing the current file's publish state |
| `a3-library-insert-item` | Insert a new top-level heading + scaffolded drawer in a `library-*.org` |
| `a3-library-insert-extras` | On an existing library heading, insert the per-medium extras drawer keys |
| `a3-publish-jump-to-source` | From `content/<section>/<slug>/index.md`, jump to the org source; or completing-read over the manifest |

**Deferred to v2 (out of this slice):**
- `a3-publish-preview-section` — a dry-run preview of what `publish-living` would emit. Needs new `--dry-run` plumbing on `a3-pub.sh` + `a3madkour-publish-living.el` + a buffer-formatter. Own session; filed as roadmap Tier 5.3 (or fold into 5.2 follow-up — author's call at impl time).
- Mode-line indicator ("◉ published as essays").
- Marginalia annotator entries for `jump-to-source`'s completing-read.
- `a3-library-bulk-import` (CSV → headings).

**No init.el wiring this slice.** Author binds the new commands manually after v1 ships.

## §3. Architecture

### 3.1 Module layout

- New file: `emacs-configs/custom/lisp/a3madkour-publish-author.el`
  - `(require 'a3madkour-publish)` — `a3madkour-pub/sections`, `a3madkour-pub--id-to-file`, `a3madkour-pub/note-metadata`
  - `(require 'a3madkour-publish-keywords)` — `a3madkour-pub-keywords/extract` / `boolean-p`
  - `(require 'a3madkour-publish-library)` — public wrappers (see §3.4)
  - `(require 'a3madkour-publish-history)` — `a3madkour-pub-history/read-manifest`
- Sibling: `emacs-configs/custom/lisp/a3madkour-publish-author-test.el`
- All six commands carry `;;;###autoload`. Author may add `(require 'a3madkour-publish-author)` to their init.el or rely on autoloads.

### 3.2 Naming convention

- **Interactive commands**: short `a3-publish-…` / `a3-library-…` prefix, matching `a3-publish-deliberate` / `a3-publish-living` / `a3-unpublish-deliberate`.
- **Internal helpers**: `a3madkour-pub-author--<fn>` (double-dash private convention used elsewhere in the publish tree).

### 3.3 Re-used registries (no new tables)

All six commands compose existing data structures. No duplicated section / medium / extras tables — those would drift.

| Source | Where | Consumers |
|---|---|---|
| `a3madkour-pub/sections` (defconst, 14 slash-form strings) | `a3madkour-publish.el` | `a3-publish-mark` (completing-read), `a3-publish-status` (validation) |
| `a3madkour-pub-library--config` (per-section: yaml-file + default-mt + allowed-mt + allowed-status) | `a3madkour-publish-library.el` | `a3-library-insert-item` (status enum + medium options), `a3-library-insert-extras` (section→medium) |
| `a3madkour-pub-library--extras-by-media` (per-medium: drawer-key + yaml-key + coercion) | `a3madkour-publish-library.el` | both `a3-library-insert-*` |
| `a3madkour-pub-history/read-manifest` (id → current_url + state) | `a3madkour-publish-history.el` | `a3-publish-jump-to-source` |
| `a3madkour-pub--id-to-file` (id → file path via org-roam) | `a3madkour-publish.el` | `a3-publish-jump-to-source` |
| `a3madkour-pub-keywords/extract` (canonical `#+keyword:` parser) | `a3madkour-publish-keywords.el` | `a3-publish-mark/unmark/status` |

### 3.4 Two thin public wrappers (added in this slice)

The library config + extras are currently `--double-dash` private. author.el needs both. Rather than reach through the double-dash names from a sibling module, add two thin public accessors in `a3madkour-publish-library.el`:

```elisp
(defun a3madkour-pub-library/sections ()
  "Return the list of library section strings (e.g. (\"library/reading\" ...))."
  (mapcar #'car a3madkour-pub-library--config))

(defun a3madkour-pub-library/extras-for (medium)
  "Return the extras-spec list for MEDIUM, or nil if MEDIUM is unknown."
  (cdr (assoc medium a3madkour-pub-library--extras-by-media)))
```

The existing double-dash internals are unchanged.

## §4. Per-command contracts

### 4.1 `a3-publish-mark`

- **Refuses**: not in `org-mode`; buffer read-only.
- **Reads**: completing-read over `a3madkour-pub/sections`. Default = current `#+HUGO_SECTION:` value if already set; else no default.
- **Behavior**: idempotent insert/update of `#+HUGO_PUBLISH: t` + `#+HUGO_SECTION: <pick>` in the preamble (above the first heading; after existing `#+TITLE:` / `#+DATE:` / etc).
- **Cross-section guard**: if file already has `#+HUGO_SECTION: <other>` AND the picked section differs, prompt `y-or-n-p` `"Move from <other> to <pick>? (next publish-living will record slug-shift)"`. **Declining the prompt aborts the entire command** — neither `#+HUGO_PUBLISH:` nor `#+HUGO_SECTION:` is touched, and the command returns nil. The author re-runs with the same section if they want a pure `HUGO_PUBLISH: t` toggle.
- **Returns**: the chosen section string, or nil if the cross-section confirm was declined.

### 4.2 `a3-publish-unmark`

- **Refuses**: not in `org-mode`; buffer read-only.
- **Behavior**: sets `#+HUGO_PUBLISH: nil`. Does NOT delete the line or remove `#+HUGO_SECTION:` (preserves history for re-marking). If the keyword is absent, inserts `#+HUGO_PUBLISH: nil` at the top.
- **Returns**: t on change, nil if already nil.

### 4.3 `a3-publish-status`

- **Refuses**: not in `org-mode`.
- **Reads**: `#+HUGO_PUBLISH:` + `#+HUGO_SECTION:` via `a3madkour-pub-keywords/extract`.
- **Branches**:
  - keyword missing → `"no HUGO_PUBLISH header"`
  - present, nil → `"private (HUGO_PUBLISH: nil)"`
  - present, t, valid section → `"marked for publish (<section>)"`
  - present, t, missing/invalid section → `"marked for publish but HUGO_SECTION is missing/invalid: %S"`
- **Returns**: the message string (also `message`'d).

### 4.4 `a3-library-insert-item`

- **Refuses**: not in `org-mode`; `#+HUGO_SECTION:` missing OR not in `(a3madkour-pub-library/sections)`.
- **Reads**:
  - **medium**: if section's allowed-mt list has >1 element, completing-read over it; else the single value is used silently
  - **status**: if section's allowed-status list has >1 element, completing-read over it; else single value used
- **Insert position**: end of buffer (don't disturb existing headings).
- **Inserted block**:
  - `* TITLE` heading (with `TITLE` text region selected so author can immediately type)
  - `:PROPERTIES:` drawer containing:
    - `:CREATOR:` (empty)
    - `:YEAR:` (empty)
    - `:STATUS: <picked-status>`
    - `:LAST_MODIFIED: <today ISO>`
    - all per-medium extras keys from `(a3madkour-pub-library/extras-for medium)` with empty values
  - `:END:`
- **Returns**: marker at the heading title.

### 4.5 `a3-library-insert-extras`

- **Refuses**: not in `org-mode`; `#+HUGO_SECTION:` missing OR not in `(a3madkour-pub-library/sections)`; point not under any heading.
- **Behavior**:
  - Read current heading's drawer properties via `org-entry-properties nil 'standard`
  - If any of the medium's extras keys are present → prompt `y-or-n-p` `"heading has %d/%d extras — append missing only?"`; on `n`, abort
  - Insert absent keys into the heading's `:PROPERTIES:` drawer (create one if absent)
  - Preserve existing key ordering — new keys go at the end of the drawer
- **Returns**: number of keys inserted.

### 4.6 `a3-publish-jump-to-source`

- **Auto-detect path**:
  - Regex `buffer-file-name` for `.*/content/<section>/<slug>/index\.md$` (slug-form `<section>` may contain a single `/` for `research/...` / `works/...` / `library/...`).
  - Build URL `/<section>/<slug>/`
  - Walk `(alist-get 'notes (a3madkour-pub-history/read-manifest))`, filter state ∈ {live, draft}, match on `current_url`
  - On hit: resolve id via `a3madkour-pub--id-to-file` → `find-file`
  - On miss: `user-error "URL /<section>/<slug>/ not in manifest"`
- **Completing-read fallback**: when buffer isn't in `content/`, OR auto-detect missed but user accepts the fallback prompt:
  - Build collection from manifest entries: `"<state>  <title> — <url>"` where `<title>` comes from `a3madkour-pub/note-metadata` on the id's file. If the file errors (deleted/moved), use `"(source missing)"`.
  - Pick → resolve id → `find-file`
- **Refuses**: manifest empty; `--id-to-file` returns nil after a successful pick.

## §5. Error handling + edge cases

### 5.1 Error severity

All refuse modes use `user-error`, not `error` — the helpers are author-facing and a stack trace would be noise.

### 5.2 Keyword editing invariants

`a3-publish-mark/unmark` are confined to the **preamble** (before the first heading). Edits use `re-search-forward` for existing lines + literal-line insert for absent ones; never touch content past the first heading.

State is read via `a3madkour-pub-keywords/extract` ([[reference-dotfiles-keywords-api]]). Never re-implement with `org-collect-keywords` + `cadar`.

### 5.3 Library item insertion edge cases

- File with no headings → insert at end-of-buffer with a leading blank line if buffer doesn't already end with one
- File with headings → insert at end-of-buffer (author reorders via `M-↑/M-↓`)
- Status / medium dim with single allowed value → skip the completing-read prompt
- `:LAST_MODIFIED:` filled with `(format-time-string "%Y-%m-%d")` — author edits before saving if needed

### 5.4 Extras add-missing-only path

- Reads `(org-entry-properties nil 'standard)` (drawer properties only — excludes `:CATEGORY:`, `:ID:`, etc.)
- Diffs against the medium's extras key set (case-insensitive on drawer keys)
- Preserves existing key ordering; new keys appended

### 5.5 Jump-to-source manifest invariants

- `current_url` is unique per state per the manifest contract. Defensive: if multiple entries match → `user-error "ambiguous URL in manifest: <url>"`.
- `--id-to-file` returns nil when the id isn't in `org-roam-db-sync`'s index. `user-error` "manifest id `<id>` not resolvable — note may have been deleted or org-roam-db is stale (try `M-x org-roam-db-sync`)".

### 5.6 Idempotency contract

Every command is idempotent on re-run:
- `mark` re-applies the same keyword lines (no append loop)
- `unmark` sees `nil` and returns nil on second run
- `status` is read-only
- `insert-item` creates a new heading per call (intentional; that's the explicit action)
- `insert-extras` on a fully-filled drawer is a no-op (skips the prompt; nothing to insert)
- `jump-to-source` is read-only side-effect (besides `find-file`)

## §6. Testing

### 6.1 Sibling test file

`a3madkour-publish-author-test.el` — same patterns as the rest of the test tree (ert + cl-letf stubs + `with-temp-buffer` + `org-mode`).

### 6.2 Coverage target — one test per branch

| Command | Tests (~count) |
|---|---|
| `a3-publish-mark` | (a) insert both keywords absent · (b) update `HUGO_SECTION` in place · (c) cross-section confirm `y-or-n-p` → t · (d) cross-section confirm → nil abort · (e) refuses non-org-mode · (f) refuses read-only buffer |
| `a3-publish-unmark` | (a) `t` → `nil` · (b) insert `nil` when absent · (c) already-nil no-op returns nil · (d) refuses non-org-mode |
| `a3-publish-status` | (a) no header · (b) `nil` · (c) marked + valid section · (d) marked + invalid section · (e) refuses non-org-mode |
| `a3-library-insert-item` | (a) happy path `library/reading` (book; status=queued) · (b) multi-medium section prompts for medium · (c) single-medium skips prompt · (d) refuses non-library section · (e) appends after existing headings — doesn't disturb |
| `a3-library-insert-extras` | (a) full extras on bare heading · (b) add-missing-only `y-or-n-p` → t · (c) refuses outside a heading · (d) refuses non-library section |
| `a3-publish-jump-to-source` | (a) auto-detect happy (stub `buffer-file-name`, manifest, `--id-to-file`, `find-file`) · (b) auto-detect URL miss → user-error · (c) completing-read fallback (stub) · (d) empty manifest → user-error · (e) `--id-to-file` nil → user-error |
| Public wrappers (§3.4) | (a) `/sections` returns `--config`'s section keys · (b) `/extras-for "book"` returns the book extras list · (c) `/extras-for "bogus"` returns nil |

**Expected suite delta**: ~30 new ert tests. Suite 629 → ~659.

### 6.3 No interactive smoke required this slice

All six commands are deterministic given stubbed `completing-read` / `y-or-n-p` / `read-string`. The ert suite is the contract. Optional manual spot-check after merge — author runs `M-x a3-publish-mark` on a scratch org buffer.

## §7. Commit + file layout

### 7.1 Dotfiles slice — one commit

| Path | Status |
|---|---|
| `emacs-configs/custom/lisp/a3madkour-publish-author.el` | NEW |
| `emacs-configs/custom/lisp/a3madkour-publish-author-test.el` | NEW |
| `emacs-configs/custom/lisp/a3madkour-publish-library.el` | MODIFY (add 2 public wrappers in §3.4) |

Single commit closing 5.2 v1.

### 7.2 Site slice — one commit

| Path | Status |
|---|---|
| `docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md` | MODIFY (5.2 row ✓) |
| `.claude/memory/project_tier_5_2_complete.md` | NEW |
| `.claude/memory/MEMORY.md` | MODIFY (index entry) |

### 7.3 No init.el wiring

Per author preference, keybindings are bound by the author manually after merge.

## §8. v2 follow-ups (filed, not in this slice)

1. **`a3-publish-preview-section`** — `--dry-run` plumbing on `a3-pub.sh` + `publish-living` + a `*a3-publish-preview*` buffer-formatter. Own session.
2. **Mode-line `mode-line-misc-info` segment** — "◉ published as essays" / "○ private" / blank. Tiny but its own UX call.
3. **Marginalia annotator** for `jump-to-source`'s completing-read — annotate each candidate with state + last-modified.
4. **`a3-library-bulk-import`** — CSV / TSV → N headings. Not in source memo; mentioned only as possible.

## §9. References

All cross-repo memory references live in `.claude/memory/` in the site repo (`~/Sync/Workspace/a3madkour.github.io/.claude/memory/`).

- Source memo: `project_emacs_publish_helpers_followup.md` (site memory)
- Roadmap row: site `docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md` Tier 5.2
- Related shipped-slice memory: `project_b0_complete.md` (section registry); `project_b1_complete.md` (garden drawer surface); `project_b2_complete.md` (library config table); `project_tier_5_1_complete.md` (the just-shipped unpublish command — sister-slice in spirit)
- Keywords API contract: `reference_dotfiles_keywords_api.md` (use `a3madkour-pub-keywords/extract` + `boolean-p`)
