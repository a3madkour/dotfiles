# Retiring a document from the Boox when note-taking advances

**Date:** 2026-08-13
**Status:** Design approved, not yet implemented
**Follows:** `2026-08-09-boox-zotero-sync-design.md`

## Goal

Close the last gap in the reading round trip. When a note advances past the
reading stage, the paper should leave the tablet automatically, without ever
risking the annotated copy that org-noter depends on.

Concretely: advancing `PROGRESS` from `highlighting` to `ref-notes` imports any
outstanding annotations, deletes the file from the Boox, and closes the reading
queue entry.

## Context

`a3madkour/org-roam-advance-pipeline` (config.org:3811) walks a `PROGRESS`
property through `none → highlighting → ref-notes → main-notes → done`.

The round trip already in place:

- `a3madkour/boox-push-queue` stages `:active:` queue entries into
  `~/Boox/reading/`, which Syncthing shares with the tablet.
- NeoReader's "Embed to PDF" writes annotations into that file in place.
- `a3madkour/boox-import` copies it into the Zotero storage directory as
  `<original>-annotated.pdf`, extracts highlights into the ref note, and records
  `:BOOX_IMPORTED_SHA:`.
- `:NOTER_DOCUMENT:` points at the annotated copy, so org-noter opens the
  highlighted version.

Nothing currently removes the file from the tablet except marking the queue
entry inactive and running push again.

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Trigger | `highlighting` → `ref-notes` only | That transition is the point where reading stops and org work starts; later advances do nothing |
| Un-imported annotations | Import automatically, then delete | One command, nothing lost, no decision to make mid-flow |
| Reading queue | Mark the entry `DONE`, drop `:active:` | Frees a WIP slot and stops push resurrecting the file |
| Archive location | The existing `<original>-annotated.pdf` in Zotero storage | Already outside the synced folder, already the `:NOTER_DOCUMENT:` target; a second copy would be another thing to keep in step |
| Command shape | Independently interactive, called by the pipeline | Retiring without advancing stays possible, and the command is testable in isolation |

### Rejected

**Refuse when annotations are un-imported.** Explicit, but costs a round trip
every time the obvious next action is "import it".

**Delete relying on Syncthing versioning alone.** `.stversions` does retain
deleted files, but recovery means digging through timestamped filenames. The
library archive is the primary net; versioning is the backstop.

**A dedicated `~/Boox/archive/` copy of the PDF.** Redundant with the Zotero
copy, and a third location to keep consistent.

## Architecture

### Extracted first

`a3madkour/boox-import-execute` currently inlines the per-file import work in
its `'pdf` branch. Retirement needs exactly that work, so it is lifted into a
shared function rather than reimplemented.

**`a3madkour/boox--import-pdf (key file)`** → summary string, or nil if the
copy was declined. Copies to the annotated destination (subject to the existing
annotation-loss guard), extracts annotations, inserts highlights, records the
document properties and content hash.

Callers: `boox-import-execute` and `boox-retire-document`.

### New functions

Each has one job and no knowledge of the others' concerns.

**`a3madkour/boox--note-key ()`** → key string, or nil
Resolves the current note buffer to its key: `:BOOX_KEY:` when present (books),
otherwise the filename base (papers, where the filename is the citekey).
`a3madkour/boox-refresh-document` inlines this logic today and is refactored
onto it.

**`a3madkour/boox--archive-path ()`** → path, or nil
Returns `:ANNOTATED_DOCUMENT:` from the current note, but only when that file is
readable. Nil means no archive exists, which is the condition retirement
refuses on.

**`a3madkour/boox--stale-p (key file)`** → boolean
Whether FILE's hash differs from the note's `:BOOX_IMPORTED_SHA:`. Kept separate
from `a3madkour/boox--already-imported-p`, which answers a related but different
question — it also consults the archive directory to cover text exports.

**`a3madkour/boox--delete-from-tablet (file)`** → t
Deletes the reading-directory file, which Syncthing propagates to the tablet.
One line of real work, isolated so the destructive act has a name, occurs in
exactly one place, and can be stubbed in tests.

**`a3madkour/boox--close-queue-entry (key)`** → count of entries closed
Finds every `queue.org` entry whose `:CITEKEY:` or `:BOOX_KEY:` matches, marks
each `DONE`, and removes the `:active:` tag. Knows nothing about PDFs or the
tablet.

All matches are closed rather than just the first: a duplicate entry left
`:active:` would keep consuming a WIP slot and cause push to re-stage the file,
which is the exact failure this feature exists to prevent. An entry already
`DONE` is left untouched and not counted, so the function is idempotent.

### Orchestration

**`a3madkour/boox-retire-document ()`** — interactive, called from a ref note.
Contains the sequence and nothing else:

1. Resolve the key. No key → `user-error`.
2. Find the reading-directory file. None → report "already retired", return.
   Advancing a note twice must not error.
3. Require an archive. `boox--archive-path` nil → `user-error`, delete nothing.
4. If stale, `boox--import-pdf`. A declined annotation-loss prompt cancels the
   retirement and leaves the file in place.
5. `boox--delete-from-tablet`.
6. `boox--close-queue-entry`. Not found → warn, continue.
7. Report: imported-then-deleted, deleted-only, or nothing-to-do.

**`a3madkour/boox--pipeline-advanced (from to)`**
The policy: call `boox-retire-document` only when FROM is `highlighting` and TO
is `ref-notes`. Separated from the mechanism so changing *when* retirement fires
never means touching *how* it works.

**`a3madkour/org-roam-advance-pipeline`** gains a single call to that hook,
passing the old and new stage. Its existing behaviour is unchanged.

### Dependency shape

```
advance-pipeline ──▶ pipeline-advanced ──▶ retire-document
                                             ├─▶ note-key
                                             ├─▶ archive-path
                                             ├─▶ reading-file-for-key   (exists)
                                             ├─▶ stale-p ──▶ import-pdf (extracted)
                                             ├─▶ delete-from-tablet
                                             └─▶ close-queue-entry
```

Nothing below the orchestrator calls anything above it.

## Safety property

The ordering — archive check, then import, then delete — guarantees the tablet
copy is never the only copy of anything at the moment it is removed. That is
what makes the command safe to fire automatically from a keybinding pressed
without thinking.

Two nets remain behind it: the annotated copy in Zotero storage, and Syncthing's
Simple File Versioning on the reading folder.

## Error handling

| Condition | Behaviour |
| --- | --- |
| Not in a note buffer / no key | `user-error`, nothing touched |
| No file in the reading directory | Report "already retired", advance proceeds |
| No readable `:ANNOTATED_DOCUMENT:` | `user-error`, nothing deleted |
| Import needed, annotation count dropped | Existing guard prompts; declining cancels the retirement |
| Queue entry not found | Warn, continue — the deletion still happened |
| Retirement fails during a pipeline advance | `PROGRESS` still advances; the error is reported |

The last row is deliberate: the pipeline stage is the user's statement of intent
about their own workflow, and a tablet-side failure should not block it.

## Testing

Batch-runnable, no tablet required.

**ERT, pure and near-pure:**
- `boox--note-key`: `:BOOX_KEY:` present, absent, non-file buffer.
- `boox--archive-path`: property present and readable, present but missing file,
  absent entirely.
- `boox--stale-p`: hash matches, differs, property absent.
- `boox--close-queue-entry`: match by `:CITEKEY:`, match by `:BOOX_KEY:`, no
  match, entry already `DONE` (idempotent no-op), two entries sharing one key
  (both closed).

**Harness, end to end**, following the pattern established for import — real
annotated PDF, temp reading directory, temp notes, temp `queue.org`, citar
stubbed, boox forms evaluated out of the real tangled `config.el`:
- Stale file: asserts highlights landed, archive updated, reading file gone,
  queue entry `DONE`.
- Current file: asserts no re-import, file still deleted, queue closed.
- Missing archive: asserts `user-error` and that the reading file survives.
- Already retired: asserts a clean no-op.

## Implementation order

1. Extract `boox--import-pdf` from `boox-import-execute`; confirm the existing
   import path still behaves identically.
2. `boox--note-key`, and refactor `boox-refresh-document` onto it.
3. `boox--archive-path`, `boox--stale-p`, `boox--delete-from-tablet`.
4. `boox--close-queue-entry`.
5. `boox-retire-document`.
6. `boox--pipeline-advanced` and the one-line change to
   `a3madkour/org-roam-advance-pipeline`.
7. Keybinding `zbd` ("done with this on the tablet"), joining `zbp` push,
   `zbi` import, `zbr` refresh, `zbt` toggle.

## Code placement

All code lives in `config.org`; `config.el` is generated output and is never
edited or committed. The new functions join the `** Import` subsection of the
`* Boox` section, except `boox--pipeline-advanced`, which sits beside
`a3madkour/org-roam-advance-pipeline` so the pipeline policy is visible where
the pipeline is defined.
