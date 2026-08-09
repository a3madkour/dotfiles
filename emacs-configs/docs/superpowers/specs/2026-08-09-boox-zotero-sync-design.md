# Boox Note Max ↔ Zotero/Emacs reading round trip

**Date:** 2026-08-09
**Status:** Design approved, not yet implemented

## Goal

Close the loop between the Zotero library, the Boox Note Max, and the org-roam
ref notes:

1. Add papers or books to `queue.org` from citar (already works).
2. Push everything currently `:active:` in the queue to the tablet.
3. Read and annotate on the tablet in NeoReader.
4. Pull back both the annotated PDF and the extracted highlight text.
5. Open the annotated version in org-noter and keep taking notes into org-roam.

Steps 2 and 4 are what this design adds. Steps 1, 3 and 5 already exist or are
handled by the device.

## What already exists

| Piece | Location | Notes |
| --- | --- | --- |
| Reading queue with WIP limit | `config.org` — `a3madkour/citar-add-to-reading-queue` | `:active:` TODOs carrying `:CITEKEY:` |
| Ref-note creation | `config.org:1539` — `a3madkour/citar-org-format-note` | Writes `:NOTER_DOCUMENT:`, rewrites the path via `.*Sync/` → `~/Sync/` |
| Supernote staging | `config.org:1677` — `a3madkour/supernote-sync-active-queue` | Copies active-queue PDFs to `~/SupernoteOutbox/` for a manual MTP drag |
| Syncthing | `~/.config/syncthing/config.xml` | Folders `~/org` and `~/Sync`; devices Lab Machine, Windows PC, linuxmachine, Pixel, HP-laptop, MacBook Air |
| Library | `~/org/notes/ref-notes/library.bib` | 1026 entries; `~/Sync/Zotero/storage` 1801 items; `~/Sync/Books` 416 files |

### Known defect to fix as part of this work

Every `file = {...}` field in `library.bib` is a macOS path
(`/Users/a3madkour/Sync/Zotero/storage/...`). `a3madkour/citar-org-format-note`
compensates inline at `config.org:1569`, but
`a3madkour/supernote--pdf-for-key` (`config.org:1670`) does a raw
`file-readable-p` on the bib path, so on Linux every key is reported as
missing. The path rewrite gets factored into a shared function that both call.

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Reader app | Boox NeoReader (built-in) | Best pen and rendering; costs an explicit export step |
| What returns | Annotated PDF **and** highlight text | PDF for visual marks in pdf-tools, text for parsable org-noter notes |
| Scope | Papers and books, both through `queue.org` | One queue, one WIP limit, one push command |
| Annotated file location | Beside its source, `-annotated` suffix | Papers: item's Zotero storage dir. Books: `~/Sync/Books` |
| Document pointer | Three properties + toggle command | Keeps org-noter unpatched |
| Import trigger | Emacs command with a review buffer | Mirrors the existing `*Supernote Sync*` summary-buffer style |
| Identity across the trip | Filename prefix `<key>--<Short Title>.pdf` | No sidecar state to drift; survives firmware changes to the export dir |
| Transport | Syncthing-Fork (Catfriend1) on the Boox | Fits the existing six-device topology; official syncthing-android is discontinued |

### Approaches considered and rejected

**Manifest sidecar** — push pretty filenames plus a `manifest.json` mapping
filename to citekey. Rejected: a second source of truth that can drift, and
because NeoReader mangles export filenames the fuzzy-match code is still
needed, so the manifest is paid for and doesn't remove the fallback.

**Fuzzy title matching on import** — no naming discipline, match the export's
title header against the bib. Rejected: the bib contains many near-duplicate
proceedings titles (`2020_Book_InteractiveStorytelling` and siblings), and a
mis-match silently writes highlights into the wrong ref note — a failure that
surfaces months later.

**BooxDrop instead of Syncthing** — built-in, browser over LAN, zero install.
Rejected: manual drag in both directions, which is the Supernote workflow being
replaced.

**Mirroring the whole library to the tablet** — rejected: tens of GB, and no
clean signal for what is actually in progress.

## Architecture

### Directory layout

```
~/Boox/
  reading/     Syncthing folder root (send-receive both ends), shared only with the Boox
  archive/     not synced; consumed exports parked here for idempotency checks
```

`~/Boox/reading/` must live outside `~/Sync` and `~/org` because Syncthing
refuses nested folder roots, and because the tablet must not pull 1801 Zotero
attachments plus 416 books.

Invariants:

- **The sync folder is pure transit.** Import copies into the Zotero storage
  dir before removing anything from `reading/`, so a NeoReader cleanup or a bad
  Syncthing merge can never destroy the only copy.
- **Deletion is the "done" signal.** Dropping a file from `reading/` deletes it
  on the tablet, keeping tablet contents in lockstep with queue `:active:` state.
- **Simple File Versioning is enabled** on the folder, covering the window
  between "Boox wrote the export" and "import filed it".

### Export location: decision rule, resolved by verification step 2

- If NeoReader writes exports **beside the source document**, `reading/` is
  bidirectional and is the only folder needed.
- If NeoReader writes to a **fixed device directory** (e.g. `Storage/note/`), a
  second receive-only folder `~/Boox/exports/` is added pointing at it.

Both branches feed the same import command, which scans a list of inbox
directories. Only the length of that list differs.

### Data flow

```
queue.org (:active:)
   │  a3madkour/boox-push-queue
   ▼
~/Boox/reading/<key>--<Short Title>.pdf
   │  Syncthing
   ▼
Boox NeoReader  ──annotate──▶  export annotated PDF + highlight txt
   │  Syncthing
   ▼
~/Boox/reading/ (or ~/Boox/exports/)
   │  a3madkour/boox-import  (review buffer, then execute)
   ├──▶ <source-dir>/<source-basename>-annotated.pdf
   ├──▶ ref note: :NOTER_DOCUMENT: / :ORIGINAL_DOCUMENT: / :ANNOTATED_DOCUMENT:
   ├──▶ ref note: * Tablet Highlights  (subheadings with :NOTER_PAGE:)
   └──▶ ~/Boox/archive/  (consumed files)
```

## Components

### `a3madkour/normalize-library-path` (pure)

Takes a path from a bib `file` field, returns a path valid on this machine:
everything from `Sync/` onward, re-anchored to `$HOME`. Returns nil when the
input contains no `Sync/` segment.

Callers: `a3madkour/citar-org-format-note` (replacing the inline rewrite at
`config.org:1569`), `a3madkour/supernote--pdf-for-key` (fixing the Linux
defect), and the new push command.

### `a3madkour/boox--slug` (pure)

Sanitizes a title for Android/FAT filenames: strips `/ \ : * ? " < > |`,
collapses whitespace to single hyphens, truncates to 40 characters, trims
trailing hyphens.

### `a3madkour/boox--key-for-entry`

Given a `queue.org` entry, returns its key: the `:CITEKEY:` value for papers, or
a slug of the `:READING_FILE:` basename for books. Book slugs are
collision-checked against both existing book keys and the bib, so a book can
never shadow a citekey; collisions get a `-2`, `-3` suffix.

### `a3madkour/boox-push-queue` (command)

Generalizes `a3madkour/supernote-sync-active-queue` rather than sitting beside
it. For every `:active:` entry in `queue.org`:

1. Resolve the source path — via citar for `:CITEKEY:`, directly for
   `:READING_FILE:` — then through `a3madkour/normalize-library-path`.
2. Copy to `~/Boox/reading/<key>--<Short Title>.<ext>`, skipping files already
   present.
3. Remove files in `reading/` whose queue entry is no longer `:active:`, so
   finished reading falls off the tablet automatically.
4. Report copied / skipped / removed / missing / unsupported in a `*Boox Sync*`
   buffer.

Step 3 removes **only files the push command itself created** — those matching
`<key>--*` whose key resolves to a non-active queue entry, and which are not
export artifacts. Anything NeoReader wrote into `reading/` (annotated PDFs,
highlight exports) is never touched by push; only `a3madkour/boox-import`
consumes those. Without this restriction, marking an entry done before running
import would delete the very exports being waited on.

Unsupported extensions (`.djvu`, the ~6 extensionless files in `~/Sync/Books`)
are reported, not pushed.

### `a3madkour/boox-import` (command)

Scans the inbox directories, classifies each file as annotated-PDF or
annotation-text, and recovers the key from the filename prefix before `--`.
Presents a review buffer before writing anything:

```
Boox Import — 3 files

 [x] madkour2021pcg--Procedural-Content-Gener(annot).pdf
     → key: madkour2021pcg  ✓ in bib
     → ~/Sync/Zotero/storage/6M3WRGVC/Abela et al. - A Constr-annotated.pdf
 [x] madkour2021pcg--Procedural-Content-Gener.txt
     → 14 highlights parsed → ref-notes/madkour2021pcg.org
 [ ] Screenshot_20260809.png
     → no key  (left in place)

 RET toggle   x execute   q abort
```

On execute, per key:

1. Copy the annotated PDF beside its source as `<source-basename>-annotated.<ext>`.
2. Find or create the ref note (citar for papers,
   `a3madkour/boox--ensure-book-note` for books).
3. Write `:ORIGINAL_DOCUMENT:` and `:ANNOTATED_DOCUMENT:`, and point
   `:NOTER_DOCUMENT:` at the annotated copy.
4. Insert parsed highlights as subheadings under a single `* Tablet Highlights`
   heading, each carrying `:NOTER_PAGE:`.
5. Bump `:LAST_MODIFIED:`.
6. Move consumed files to `~/Boox/archive/`.

The single `* Tablet Highlights` heading keeps machine-written content visibly
separate from hand-written notes.

Files that cannot be matched are left in place and listed. No guessing.

### `a3madkour/boox--parse-highlights` (pure)

Parses a NeoReader annotation export into a list of `(page text note)`. Written
against a real captured export (verification step 2), which is committed as a
test fixture. Reports zero highlights loudly rather than writing an empty
section.

### `a3madkour/boox--ensure-book-note`

For `:READING_FILE:` entries with no citar entry: creates
`<org-ref-notes>/<slug>.org` shaped like a citar ref note — org-roam ID, `:Ref:`
filetag, document properties — without the bibliography preamble.

### `a3madkour/boox-toggle-noter-document` (command)

Swaps `:NOTER_DOCUMENT:` between the recorded `:ORIGINAL_DOCUMENT:` and
`:ANNOTATED_DOCUMENT:` values. org-noter needs no patching because it only ever
reads `:NOTER_DOCUMENT:`.

`a3madkour/citar-org-format-note` is amended to also emit
`:ORIGINAL_DOCUMENT:`, so freshly created notes are toggle-ready.

## EPUB limitations

`~/Sync/Books` holds 363 PDF, 43 EPUB, 2 DJVU, and ~6 extensionless files. No
EPUBs appear in the bib. EPUB is supported with three stated limits:

1. **No annotated EPUB returns.** NeoReader cannot burn annotations into an
   EPUB container. Highlight text only; `:ANNOTATED_DOCUMENT:` stays absent and
   `:NOTER_DOCUMENT:` keeps pointing at the original.
2. **Page numbers are meaningless.** EPUB is reflowable, so exported positions
   depend on the tablet's font size and do not map onto nov.el's
   `(chapter . pos)` locations. EPUB highlights are inserted as a plain list
   under `* Tablet Highlights` with no `:NOTER_PAGE:`.
3. **nov.el must be added.** `(use-package nov)` plus the `.epub` auto-mode
   entry, so org-noter can open EPUBs at all. This enables manual noting only;
   it does not make imported highlights positional.

## Error handling

| Condition | Behaviour |
| --- | --- |
| Source PDF missing after normalization | Reported in the push summary, entry skipped |
| Key not present in bib | File left in `reading/`, listed as unmatched |
| `*.sync-conflict-*` files | Skipped outright (one already exists in `~/org`) |
| Unsupported extension | Reported, not pushed |
| Parser finds zero highlights | Reported loudly; no empty section written |
| Re-delivered or double-imported file | Skipped via hash match against `~/Boox/archive/` |
| Re-reading and re-exporting a paper | Overwrites `-annotated` copy with confirmation; prior versions survive in Syncthing file versioning |
| Boox kills Syncthing in background | Mitigated by the power-management exemption in verification step 1 |

The review buffer *is* the dry run — nothing is written until `x` is pressed, so
there is no separate dry-run flag to maintain.

## Testing

Tests live in `~/emacs-configs/custom/tests/boox-tests.el`, tangled from
`config.org` via
`#+begin_src emacs-lisp :tangle "./tests/boox-tests.el"` — the same trick the
early-init block at `config.org:12` uses — so they stay out of `config.el` and
never load at startup.

ERT coverage targets the pure functions, which carry most of the risk:

- `a3madkour/normalize-library-path`: macOS path, Linux path, path with no
  `Sync/` segment, path with `Sync/` appearing twice.
- `a3madkour/boox--slug`: illegal characters, over-length titles, unicode,
  titles that slug to empty.
- `a3madkour/boox--key-for-entry`: citekey entries, book entries, slug
  collisions between two books, a book slug colliding with a citekey.
- Filename → key extraction: clean names, NeoReader-mangled names, names with
  `--` inside the title half.
- `a3madkour/boox--parse-highlights`: against the committed real-export fixture,
  plus an empty export and a malformed one.

## Implementation order

Steps 1 and 2 are manual and gate the code.

1. **Install Syncthing-Fork on the Boox.** Exempt it from Boox power
   management, share `~/Boox/reading/`, confirm files arrive and survive a
   sleep cycle.
2. **Annotate one throwaway PDF and export both artifacts.** Record exactly
   where they land and what they are named. This resolves the one-folder vs
   two-folder decision rule and produces the parser fixture.
3. `a3madkour/normalize-library-path`, `a3madkour/boox--slug`,
   `a3madkour/boox--key-for-entry`, and `a3madkour/boox-push-queue`. Fixes the
   Supernote command as a side effect.
4. `a3madkour/boox-import`: review buffer, PDF filing, property writing.
5. `a3madkour/boox--parse-highlights`, written against the step-2 fixture.
6. `a3madkour/boox-toggle-noter-document`, keybindings, the
   `a3madkour/citar-org-format-note` amendment, and `nov.el`.

## Code placement

All code lives in `config.org` as `emacs-lisp` src blocks — `config.el` is
generated output (`#+property: header-args:emacs-lisp :tangle yes` at
`config.org:4`, loaded by `org-babel-load-file` at `init.el:43`) and is never
edited directly.

A new `* Boox` section goes after `* Bibliography` (following the Citproc block
at `config.org:1735`, before `* Org`). Every load-time dependency —
`a3madkour/org-file` at `config.org:129`, `zot-bib`, `citar` at
`config.org:1590` — is defined by that point. The `org-noter` references sit
inside function bodies and resolve at call time, so the later `use-package` at
`config.org:3034` is not a constraint.

Keybindings go in the existing which-key section near `config.org:4403`.
