# Inbox and season hardening — design

Date: 2026-11-14
Status: draft, awaiting approval

## Intent

The inbox-processing and season/agenda code in `custom/config.org` fails
quietly. The one failure the owner noticed was a seasonal habit ("neetcode
rust 1 problem a day") missing from the dashboard; a code review then found
ten more failures of the same character, none of which had been noticed.

The goal is one sentence: **nothing disappears from the dashboard and nothing
is lost from the inbox without the owner being told.**

## Background: how it works today

All code is in `custom/config.org`, tangled to `custom/config.el`.

- **Season.** `~/org/projects.org` starts with a level-1 heading
  `* Current Season: <name> (<month> — <month>)  :tag1:tag2:` with `START`
  and `END` properties. `a3madkour/get-current-season` and
  `a3madkour/get-current-season-tags` read it. `a3madkour/rotate-season`
  archives it and inserts a new one, using `a3madkour/select-season-tags`.
- **Dashboard.** `a3madkour/setup-agenda-commands` builds the `"d"` agenda
  command. It runs once inside `(use-package org :config ...)` and again from
  `rotate-season`. It reads the season tags and bakes them into
  `org-super-agenda-groups` as a quoted constant: Scheduled, Core Habits
  (habit + `core`), Seasonal Habits (habit + any season tag), two discard
  rules for overdue items lacking a core/season tag, Overdue, then discard all
  remaining habits.
- **Inbox.** `a3madkour/process-inbox-item` asks for a destination and calls
  one of `inbox-delete`, `inbox-to-org-roam`, `inbox-to-someday`,
  `inbox-to-habit`, `inbox-to-action`, `inbox-to-new-project`,
  `inbox-to-existing-project`.
- **Tests.** `custom/tests/run.sh` runs ERT in batch. `test-helpers.el`
  extracts every top-level `(defun|defvar|defcustom|defalias|defmacro
  a3madkour…` form from `config.org` and evaluates it; third-party packages
  (org-super-agenda, Vertico, org-roam) are not loaded, so tests stub them.
  Prompts are stubbed with `a3madkour-test/queue`.

Already fixed in the working tree (uncommitted) and assumed by this design:
season tags are passed to org-super-agenda's `:tag` as a list instead of a
`"a|b"` string, which it compared literally.

## Goals

1. Aborting or mistyping at any prompt during inbox processing leaves the
   item intact and processable again.
2. Sending an item to org-roam can never remove any inbox item other than
   the one sent, and never drops or alters its content.
3. The dashboard reflects the season as it is in `projects.org` when the
   dashboard is opened, not as it was at startup.
4. When the season cannot be determined or is unusable, the dashboard says so
   visibly.
5. Every overdue todo appears under Overdue, whatever its tags.
6. Optional prompts behave as their text says under the owner's completion
   setup (Vertico), and reject values that would break the agenda.
7. The test suite fails when a test under-supplies prompt answers, and covers
   the abort paths.

## Non-goals

- Moving this code out of `config.org` into `custom/lisp/` (considered as
  approach C; a possible follow-up as a pure move).
- Changing what a season is, how it is stored, or the `Current Season`
  heading format.
- The file-level `:PROPERTIES:` drawer case in `-insert-new-season`
  (`projects.org` has no such drawer).
- Exercising the top-level `before-save-hook` in tests.
- Startup-time optimisation for its own sake.

## Anti-goals

- Replacing a silent failure with a silent fallback. A recovered-from problem
  must still be visible.
- Making inbox processing slower to use: no extra confirmation prompts on the
  normal path.
- Any error at Emacs startup caused by missing or malformed org files.

## Constraints

- Code stays in `config.org` src blocks. New helpers must be top-level
  `a3madkour`-prefixed `defun`/`defvar` forms or the test loader will not see
  them.
- Tests must run under `custom/tests/run.sh` in batch without third-party
  packages.
- The repo working tree has many unrelated modified and untracked files.
  Commits must stage only files this work touches.
- `config.org` itself carries unrelated uncommitted edits by the owner (an
  `exec-path-from-shell` daemon change and a `LAST_MODIFIED` bump) alongside
  the `:tag` list fix. Those unrelated hunks are never staged by this work:
  every commit touching `config.org` stages by hunk. The `:tag` fix and its
  test change in `test-agenda-seasons.el` form the first commit.
- `config.el` is produced by tangling; the owner reloads it themselves.

## Approaches considered

- **A. Fix each finding where it is.** Smallest change, but leaves the next
  handler free to repeat the same mistake.
- **B. Fix by pattern (chosen by the owner).** The findings share four root
  causes; fix each once and move the findings onto the shared fix. Medium
  size, closes classes of failure rather than instances.
- **C. Extract into its own module, rebuilt around B's patterns.** Cleanest
  end state, but moves code while changing behaviour, which hides
  regressions.

## Decisions made by the owner

- Approach B.
- **Overdue todos that are not in season are always shown.** The season
  filters habits only.

## Design

The review findings were produced by reading code, not by running it. **Each
finding must first be reproduced by a failing test.** A finding that does not
reproduce is dropped and recorded as such in the plan's results, not fixed
speculatively.

### Pattern 1 — ask first, change last (inbox handlers)

Rule: a handler gathers and validates every answer it needs before it
modifies the inbox item. After an abort (`C-g`) or a `user-error` at any
prompt, the item must still be in `inbox.org`, still carry its TODO keyword,
and have its body and children unchanged, so `process-inbox-item` can be run
on it again.

- `inbox-to-someday` currently calls `(org-todo "")` first. The keyword is
  removed only after the target heading has been resolved.
- `inbox-to-habit` validates flexibility and tags before setting `STYLE`,
  scheduling or tagging.
- The remaining handlers are audited against the rule.

Each handler gets an "abort leaves the item intact" test.

The rule also covers what a handler writes outside the inbox.
`inbox-to-new-project` currently calls `create-project` (which inserts and
saves the project heading) before the energy/effort prompts, so an abort
there leaves an empty project behind and a retry creates a duplicate. The
energy/effort prompts move before `create-project`. `create-project` itself
already asks all its questions before writing and is not restructured.

*Design calls:*
- `ENERGY`/`EFFORT` properties left on the item by an aborted action/project
  hand-off are acceptable; they do not stop reprocessing.
- Reordering the prompts is preferred over splitting `create-project` into
  "gather" and "write" halves.

### Pattern 2 — the season is read when needed

One accessor replaces the two readers. It returns either the current season
(name, tags, start, end) or an explicit "no season" result carrying the
reason. There are exactly two reasons: `projects.org` is missing, or it has
no `Current Season` heading. It never signals.

A `Current Season` heading with no tags **is a season**, with an empty tag
list. Rotation legitimately allows zero tags and the existing tests for a
tagless heading keep passing. A heading whose tags org cannot parse (for
example `:rust lang:`) is not a separate state: it reads as a season with no
tags, and the validation at entry (below) is what prevents it being written.

`get-current-season` and `get-current-season-tags` either become thin
wrappers or are removed, with their other callers (`-habit-tag-candidates`
and `a3madkour/show-project-status`) moved to the accessor.

The dashboard command is defined once at startup **without reading any
file**. Its `org-super-agenda-groups` and header are computed by a function
called each time the agenda is built (custom-command settings are evaluated
at build time; the existing header already relies on this).
`rotate-season` no longer needs to rebuild the command.

Group order becomes:

1. Scheduled (unchanged)
2. Core Habits (unchanged)
3. Seasonal Habits — only when the season has tags
4. Untagged Habits — habits with no tags at all (see below)
5. discard remaining habits
6. Overdue — every past-scheduled or past-deadline item

The two tag-based discard rules are deleted. Habits are discarded *before*
Overdue so that out-of-season habits do not reappear there.

Visible notices, shown in the dashboard header:

- no season: the reason and a pointer to `a3madkour/rotate-season`, in place
  of the season name;
- season has no tags: the season name plus a "no tags" notice;
- season `END` date has passed: the season name plus an "ended" notice.

*Design calls:*
- With no usable season, non-core tagged habits stay hidden; the header
  notice is what tells the owner.
- A habit with no tags can never be in season, so it is shown in its own
  group rather than hidden forever.
- The season-ended notice is advisory only; nothing rotates automatically.

Also in this pattern:

- `select-season-tags` rejects anything that is not a valid org tag and asks
  again, so a heading with unparsable tags cannot be written.
- `rotate-season` and `create-project` operate on the widened buffer.
- `inbox-to-existing-project` offers only project headings as targets, not
  the season headings.

### Pattern 3 — prompts that mean what they say

The review reports that with Vertico's default preselection, pressing RET on
an empty prompt submits the first candidate, so "blank for none" tags a new
habit with the first candidate and "blank for Parking Lot" files under
whichever heading sorts first. This needs a live Emacs with the owner's
completion setup; batch tests cannot show it.

**Owner checkpoint.** Before the picker and Parking Lot changes are made, the
owner presses RET on an empty prompt at the someday heading prompt and at the
habit tags prompt and reports what was chosen. The builder does not launch
the owner's full Emacs configuration to check this. If the owner reports that
blank already works, the picker and Parking Lot changes are dropped; tag
validation and flexibility validation go ahead regardless, as they do not
depend on it. The plan places this checkpoint so that no other work waits on
it.

Fix: stop relying on empty input.

- Someday: "Parking Lot" is the default and the first candidate, so RET gives
  Parking Lot under any completion UI.
- Tags: one shared picker used by both habit capture and season rotation.
  It is the existing one-at-a-time picker, with "Done" as the first candidate
  so RET on an empty prompt finishes. It applies the tag validation above.
- Habit flexibility: must be a whole number of days greater than the period;
  blank means no window. An invalid value is rejected before the item is
  touched.

Tests assert what is passed to the completion function (candidate order and
default), since the UI itself is not available in batch.

*Design call:* the shared picker replaces `completing-read-multiple` in habit
capture, changing how tags are entered there (one at a time rather than
comma-separated).

### Pattern 4 — the org-roam hand-off owns its own capture

Requirements:

- Finalising any capture other than the one started by the hand-off never
  touches the inbox.
- Two hand-offs in progress at once each remove only their own item.
- If the roam capture fails to start, nothing is left armed.
- On abort, the item stays. On success, it is removed.
- The whole item reaches the note: body **and** child headings.
- The body reaches the note verbatim. Text such as `%20`, `100%`,
  `%^{x}`, `%(error "x")` and `${foo}` causes no prompt, no evaluation and
  no alteration.

Shape of the note for an item with child headings:

- the parent's body comes first, as today;
- child headings follow it, verbatim, with their TODO keywords, tags and
  property drawers, re-levelled so the shallowest child is level 1 and
  relative depth is kept;
- the parent's own metadata (its `CAPTURED` drawer, planning line and tags)
  is still not carried over, as today. The parent's heading text is already
  the note title.

*Design call:* the note shape above.

The mechanism (carrying the marker on the capture itself rather than in a
global variable; how the body bypasses template expansion) is left to the
builder.

### Tests

- `a3madkour-test/queue` signals when called after its values are exhausted.
  Existing tests that relied on the silent nil are corrected.
- `a3madkour-test/in-org-file` moves to `test-helpers.el`; the two copies go.
- New tests: one reproducing test per finding, the abort-intact tests, the
  roam requirements above, the dashboard group order and notices, and the
  accessor's "no season" reasons.

## Findings covered

| # | Finding | Pattern |
|---|---------|---------|
| 1 | someday strips keyword before validating | 1 |
| 2 | overdue todos discarded by tag | 2 |
| 3 | habit flexibility unvalidated | 3 |
| 4 | roam body expanded as template | 4 |
| 5 | roam global marker/hook cuts on unrelated capture | 4 |
| 6 | "blank for none" under Vertico | 3 |
| 7 | missing `projects.org` breaks startup | 2 |
| 8 | invalid season tags | 2/3 |
| 9 | season tags baked in at startup | 2 |
| 10 | roam drops child headings | 4 |
| 11 | narrowed buffer in rotate/create | 2 |
| 12 | season headings offered as project targets | 2 |
| 13 | test queue returns nil when exhausted | tests |
| 14 | duplicated test macro | tests |

## Left to the builder

- Names and signatures of new helpers.
- The roam mechanism, within the requirements above.
- How "untagged habit" is expressed to org-super-agenda.
- Exact wording of notices and error messages.
- Order of work, provided each finding is reproduced before it is fixed and
  the suite is green at each commit.
