# Inbox and Season Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nothing disappears from the dashboard and nothing is lost from the inbox without the owner being told.

**Architecture:** Four shared fixes in `custom/config.org`, each replacing a class of silent failure: inbox handlers ask and validate before they change anything; the season is read through one accessor each time the dashboard is built; optional prompts stop relying on empty input; the org-roam hand-off keeps its state on its own capture buffer. Each review finding is reproduced by a failing test before it is fixed.

**Tech Stack:** Emacs Lisp, org-mode, org-super-agenda, org-roam, ERT.

**Spec:** `docs/superpowers/specs/2026-11-14-inbox-season-hardening-design.md`

## Global Constraints

- All code stays in `custom/config.org` src blocks. New helpers are top-level `(defun a3madkour…` / `(defvar a3madkour…` forms, or the test loader in `tests/test-helpers.el` will not see them.
- Tests run in batch with `./tests/run.sh [PATTERN]` from `custom/`, without org-super-agenda, Vertico or org-roam loaded. Stub them.
- Work on a branch `inbox-season-hardening` created in place in the existing checkout. Do **not** use a separate worktree: the tests need untracked tangled files (`custom/boox-core.el`) that a fresh worktree lacks.
- The working tree has many unrelated modified and untracked files. Stage only files this work touches, by explicit path.
- `custom/config.org` carries two unrelated uncommitted hunks by the owner (the `:LAST_MODIFIED:` bump and the `exec-path-from-shell` daemon change). They are never committed by this work. Every commit touching `config.org` uses the recipe in Task 0.
- Edit `config.org` with file tools, never by saving from Emacs (a `before-save-hook` bumps `LAST_MODIFIED`).
- Do not tangle `config.el` and do not launch the owner's full Emacs configuration. The owner reloads.
- Reproduce before fixing: each finding's test must be seen to fail first. A finding that does not reproduce is not fixed; record it in the commit message of the task that owned it and in Task 8's summary.
- No error at Emacs startup from missing or malformed org files. No new confirmation prompts on the normal inbox path.
- Commit messages follow the repo style (`fix(inbox): …`, `test(…): …`) and end with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.

## Review Focus

1. `projects.org` has `#+FILETAGS:` — the season's tags must be the heading's own tags only. (Task 2)
2. `projects.org` is empty, or has two `Current Season` headings — empty reads as "no heading"; with two, the first wins. (Task 2)
3. Season `END` property missing or malformed — no "ended" notice and no error. (Task 3)
4. Habit flexibility typed as `" 5 "`, `"5d"`, `"-1"` or `"0"` — surrounding spaces are accepted; the rest are rejected before the item changes. (Task 5)
5. Roam hand-off of an item with an empty body but child headings, or children at irregular depth — children still arrive, shallowest at level 1. (Task 6)

---

### Task 0: Branch, owner patch, baseline commit

**Files:**
- Modify (commit only): `custom/config.org`, `custom/tests/test-agenda-seasons.el`
- Commit: `docs/superpowers/specs/2026-11-14-inbox-season-hardening-design.md`, this plan

**Interfaces:**
- Produces: the commit recipe every later task uses for `config.org`.

- [ ] **Step 1: Create the branch**

Run from the repo root (`~/dotfiles`): `git switch -c inbox-season-hardening`

- [ ] **Step 2: Save the owner's hunks as a patch**

Run `git diff -- emacs-configs/custom/config.org` and write the two hunks that touch `:LAST_MODIFIED:` and `exec-path-from-shell` (with the file header) to `"$(git rev-parse --git-dir)/owner-hunks.patch"`.
Check: `git apply --check -R "$(git rev-parse --git-dir)/owner-hunks.patch"` exits 0.

- [ ] **Step 3: The commit recipe for `config.org`**

```bash
git add emacs-configs/custom/config.org
git apply --cached -R "$(git rev-parse --git-dir)/owner-hunks.patch"
git diff --cached --stat   # must not show LAST_MODIFIED or exec-path lines in `git diff --cached`
```

- [ ] **Step 4: Run the suite for a baseline**

Run: `cd emacs-configs/custom && ./tests/run.sh`
Expected: all pass. Record the count.

- [ ] **Step 5: Commit the existing `:tag` list fix, then the docs**

```bash
# recipe from Step 3, then:
git add emacs-configs/custom/tests/test-agenda-seasons.el
git commit -m "fix(agenda): pass season tags to super-agenda as a list"
git add emacs-configs/docs/superpowers/specs/2026-11-14-inbox-season-hardening-design.md \
        emacs-configs/docs/superpowers/plans/2026-11-14-inbox-season-hardening.md
git commit -m "docs(inbox): design and plan for inbox and season hardening"
```

---

### Task 1: Tests that fail loudly

**Files:**
- Modify: `custom/tests/test-helpers.el` (`a3madkour-test/queue`, add `a3madkour-test/in-org-file`)
- Modify: `custom/tests/test-inbox.el`, `custom/tests/test-agenda-seasons.el` (delete their copies of `in-org-file`)
- Test: `custom/tests/test-helpers-extracted.el`

**Interfaces:**
- Produces: `(a3madkour-test/queue VALUES)` — returned lambda signals `error` on the call after VALUES is used up; a `nil` element is still returned as `nil`. `a3madkour-test/in-org-file` defined once, in `test-helpers.el`.

- [ ] **Step 1: Write the failing test**

```elisp
(ert-deftest a3madkour-test/queue-signals-when-exhausted ()
  (let ((q (a3madkour-test/queue '("a" nil))))
    (should (equal "a" (funcall q)))
    (should (null (funcall q)))
    (should-error (funcall q))))
```

- [ ] **Step 2: Run it** — `./tests/run.sh queue-signals` — Expected: FAIL (third call returns nil).

- [ ] **Step 3: Make `a3madkour-test/queue` count its values and signal when exhausted; move `in-org-file` into `test-helpers.el`.**

- [ ] **Step 4: Run the full suite** — `./tests/run.sh`. Any test that now fails was under-supplying answers: give it the answers the code actually asks for. Do not weaken the queue. Expected after fixes: all pass.

- [ ] **Step 5: Commit** — `test(helpers): an exhausted prompt queue fails the test`, listing the tests that needed answers added.

---

### Task 2: One season accessor

**Files:**
- Modify: `custom/config.org` — `;; ---- Season queries ----` block; `a3madkour/-habit-tag-candidates`
- Test: `custom/tests/test-pure.el` (beside the existing `get-current-season*` tests)

**Interfaces:**
- Produces: `(a3madkour/current-season)` → plist. Never signals.
  - `(:status ok :name STRING :tags LIST :start STRING-OR-NIL :end STRING-OR-NIL)`
  - `(:status no-file)` — `projects.org` does not exist
  - `(:status no-heading)` — no `^\* Current Season:` heading
  - `:name` is the heading text after `Current Season: ` with trailing tags stripped; `:tags` are the heading's own tags only (no inheritance, no `#+FILETAGS`); `:start`/`:end` are the raw `START`/`END` property strings.
- Keeps: `(a3madkour/get-current-season)` → name, or `"No season set"`; `(a3madkour/get-current-season-tags)` → tag list or nil. Both become wrappers and neither signals.

- [ ] **Step 1: Write the failing tests** (fixtures via `a3madkour-test/with-org-env`, as the existing tests in this file do)

| Test name | `projects.org` content | Assertion |
|---|---|---|
| `current-season-ok` | `* Current Season: Rust (Nov — Dec)  :programming:rust:` + `START`/`END` drawer | `:status` `ok`, `:name` `"Rust (Nov — Dec)"`, `:tags` `("programming" "rust")`, `:end` `"[2026-12-26 Sat]"` |
| `current-season-tagless-is-a-season` | `* Current Season: Quiet` | `:status` `ok`, `:tags` nil |
| `current-season-no-file` | (no file seeded) | equals `(:status no-file)`; no error |
| `current-season-no-heading` | `* Some project :project:` | equals `(:status no-heading)` |
| `current-season-empty-file` | `""` | equals `(:status no-heading)` |
| `current-season-ignores-filetags` | `#+FILETAGS: :work:` then a season tagged `:rust:` | `:tags` `("rust")` |
| `current-season-first-heading-wins` | two `Current Season` headings, `A :a:` then `B :b:` | `:name` `"A"`, `:tags` `("a")` |
| `get-current-season-tags-no-file` | (no file seeded) | returns nil; no error |

All names prefixed `a3madkour-test/`.

- [ ] **Step 2: Run** — `./tests/run.sh current-season` — Expected: FAIL, `a3madkour/current-season` void; `…-no-file` fails with `file-missing`.

- [ ] **Step 3: Implement `a3madkour/current-season`; rewrite the two readers as wrappers; drop the `file-exists-p` guard in `-habit-tag-candidates`.** Read the file once per call.

- [ ] **Step 4: Run** — `./tests/run.sh season` — Expected: PASS, including the six pre-existing `get-current-season*` tests.

- [ ] **Step 5: Commit** — `fix(season): read the season through one accessor that cannot fail`.

---

### Task 3: Dashboard built when opened

**Files:**
- Modify: `custom/config.org` — `;; ---- Agenda + season rotation ----` block (`setup-agenda-commands`, `rotate-season`)
- Test: `custom/tests/test-agenda-seasons.el`

**Interfaces:**
- Consumes: `a3madkour/current-season` (Task 2).
- Produces:
  - `(a3madkour/-season-notices SEASON &optional NOW)` → list of strings; SEASON is the plist, NOW a time value defaulting to the current time.
  - `(a3madkour/-dashboard-header)` → string: `"Season: NAME"` (or the no-season notice in place of the name), each further notice on its own line prefixed `"⚠ "`, ending in a newline.
  - `(a3madkour/-dashboard-groups)` → value for `org-super-agenda-groups`.
  - `a3madkour/setup-agenda-commands` reads no file. In the `"d"` command the settings are the forms `(org-super-agenda-groups (a3madkour/-dashboard-groups))` and `(org-agenda-overriding-header (a3madkour/-dashboard-header))`.
  - `rotate-season` no longer calls `setup-agenda-commands`.

Group order from `-dashboard-groups`: `"⏰ Scheduled"`, `"🔁 Core Habits"`, `"🔁 Seasonal Habits"` (only when the season has tags; `:tag` is the tag list), `"🔁 Untagged Habits"`, `(:discard (:habit t))`, `"⚠️ Overdue"`. No other `:discard` group.

Notice text must contain these substrings (the rest of the wording is free):

| Condition | Substrings |
|---|---|
| `:status no-file` | `No current season`, `projects.org not found`, `rotate-season` |
| `:status no-heading` | `No current season`, `Current Season`, `rotate-season` |
| `ok`, `:tags` nil | `no tags` |
| `ok`, `:end` parses to a date before NOW's date | `ended` |

- [ ] **Step 1: Write the failing tests**

```elisp
(defun a3madkour-test/-group-names (groups)
  (mapcar (lambda (g) (or (plist-get g :name) (car g))) groups))

(ert-deftest a3madkour-test/dashboard-groups-order-with-season ()
  (cl-letf (((symbol-function 'a3madkour/current-season)
             (lambda () '(:status ok :name "S" :tags ("foo" "bar")))))
    (let ((groups (a3madkour/-dashboard-groups)))
      (should (equal '("⏰ Scheduled" "🔁 Core Habits" "🔁 Seasonal Habits"
                       "🔁 Untagged Habits" :discard "⚠️ Overdue")
                     (a3madkour-test/-group-names groups)))
      (should (equal '(:habit t) (plist-get (nth 4 groups) :discard)))
      (should (string-match-p (regexp-quote ":tag (\"foo\" \"bar\")")
                              (prin1-to-string (nth 2 groups)))))))
```

Plus, in the same style:
- `dashboard-groups-without-season-tags` — for `:tags nil`, `(:status no-file)` and `(:status no-heading)`: no `"🔁 Seasonal Habits"`; the other five in the same order.
- `dashboard-overdue-is-not-filtered-by-tag` — `(prin1-to-string (a3madkour/-dashboard-groups))` has exactly one occurrence of `:discard`.
- `setup-agenda-commands-reads-no-file` — stub `a3madkour/current-season` to `(error "read at setup")`; `(a3madkour/setup-agenda-commands)` does not signal; `(prin1-to-string (assoc "d" org-agenda-custom-commands))` contains `a3madkour/-dashboard-groups` and `a3madkour/-dashboard-header`.
- `season-notices-*` — one test per row of the table above, plus: `:end nil` and `:end "garbage"` give no `ended` notice and no error; a healthy season (`:tags ("x")`, `:end` after NOW) gives `nil`. Pass NOW explicitly, e.g. `(encode-time 0 0 12 1 1 2027)` against `:end "[2026-12-26 Sat]"`.
- `dashboard-header-shows-name-and-notices` — for `(:status ok :name "Rust" :tags nil)`, header matches `"Season: Rust"` and `"⚠ .*no tags"`.

Rewrite the two existing `setup-agenda-commands-with/without-season-tags` tests onto `-dashboard-groups` and delete them. Remove the `setup-agenda-commands` stub from both `rotate-season` tests.

- [ ] **Step 2: Run** — `./tests/run.sh 'dashboard\\|notices\\|agenda-commands'` — Expected: FAIL, functions void.

- [ ] **Step 3: Implement the three functions and slim `setup-agenda-commands`; delete the two tag-based `:discard` rules; drop the rebuild call from `rotate-season`.** "Untagged habit" needs a selector for "habit with no tags at all"; org-super-agenda's `:pred` is one way. Read `straight/repos/org-super-agenda/org-super-agenda.el` before choosing.

- [ ] **Step 4: Run** — `./tests/run.sh season` and the Step 2 pattern — Expected: PASS.

- [ ] **Step 5: Commit** — `fix(agenda): build the dashboard from the season as it is now`, noting findings 2, 7 and 9.

---

### Task 4: Valid tags, widened buffers, project-only targets

**Files:**
- Modify: `custom/config.org` — `a3madkour/select-season-tags`, `a3madkour/rotate-season`, `a3madkour/create-project`, `a3madkour/inbox-to-existing-project`
- Test: `custom/tests/test-agenda-seasons.el`, `custom/tests/test-project-lifecycle.el`, `custom/tests/test-inbox.el`

**Interfaces:**
- Produces:
  - `(a3madkour/-valid-tag-p STRING)` → non-nil when STRING is one or more of letters, digits, `_`, `@`, `#`, `%`.
  - `(a3madkour/-read-tags PROMPT CANDIDATES)` → list of tag strings in selection order. Each round calls `completing-read` with `"-- Done --"` first, `"-- Enter new tag --"` second, then the CANDIDATES not yet selected. An invalid tag (typed at "New tag:" or free-typed at the picker) is not added; `message` says why and the loop continues. No duplicates.
  - `(a3madkour/select-season-tags)` → `(a3madkour/-read-tags "Season tags" (a3madkour/get-habit-tags))`.

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest a3madkour-test/valid-tag-p ()
  (dolist (ok '("rust" "side_project" "a@b" "x1"))
    (should (a3madkour/-valid-tag-p ok)))
  (dolist (bad '("deep work" "side-project" "" "a:b"))
    (should-not (a3madkour/-valid-tag-p bad))))
```

- `read-tags-done-is-first-candidate` — stub `completing-read` to record its COLLECTION argument and return `"-- Done --"`; the recorded list starts `("-- Done --" "-- Enter new tag --" "tag1" …)`.
- `read-tags-rejects-invalid-new-tag` — `completing-read` queue `("-- Enter new tag --" "-- Done --")`, `read-string` queue `("deep work")` → result nil.
- `read-tags-rejects-invalid-free-typed` — `completing-read` queue `("side-project" "rust" "-- Done --")` → `("rust")`.
- `rotate-season-in-narrowed-buffer` — seed a season plus a project; narrow the `projects.org` buffer to the project subtree; rotate; after `widen`, exactly one `^\* Current Season:` and one `^\* ARCHIVE Season:`.
- `create-project-in-narrowed-buffer` — narrow to the first heading; create a project; after `widen`, the new project is the last heading in the file.
- `inbox-to-existing-project-offers-only-projects` — stub `org-refile` to capture `org-refile-targets`; it equals `` `((,(a3madkour/org-file "projects.org") :tag . "project")) ``.

- [ ] **Step 2: Run** — `./tests/run.sh 'valid-tag\\|read-tags\\|narrowed\\|offers-only'` — Expected: FAIL.

- [ ] **Step 3: Implement.** The four existing `select-season-tags-*` tests must pass unchanged.

- [ ] **Step 4: Run** — `./tests/run.sh` — Expected: all PASS.

- [ ] **Step 5: Commit** — `fix(season): only valid tags reach the season heading`, noting findings 8, 11, 12.

---

### Task 5: Inbox handlers ask first, change last

**Files:**
- Modify: `custom/config.org` — `a3madkour/inbox-to-someday`, `a3madkour/inbox-to-new-project`, `a3madkour/-build-habit-repeater`, and any other handler the audit shows breaking the rule
- Test: `custom/tests/test-inbox.el`, `custom/tests/test-helpers-extracted.el`

**Interfaces:**
- Produces: `(a3madkour/-build-habit-repeater FREQUENCY FLEXIBILITY)` — same signature. For daily / every 2 days / every 3 days (period 1 / 2 / 3 days), FLEXIBILITY after `string-trim` must be empty (no window) or all digits with a value greater than the period; otherwise it signals `user-error`. Other frequencies ignore it, as now.

"Intact" in every test below means: the item is still in `inbox.org`, its heading still starts `* TODO`, and its body and children are unchanged.

- [ ] **Step 1: Write the failing tests**

| Test name | Abort / bad input | Assertion |
|---|---|---|
| `inbox-to-someday-abort-keeps-keyword` | `completing-read` does `(signal 'quit nil)` (wrap the call in `condition-case` for `quit`) | intact |
| `inbox-to-someday-unknown-heading-errors` (extend) | heading `"Nope"` | `user-error`, and intact |
| `inbox-to-new-project-abort-leaves-no-project` | quit at the energy prompt | `projects.org` content unchanged; intact |
| `inbox-to-habit-bad-flexibility-touches-nothing` | every 3 days, flexibility `"3"` | `user-error`; item has no `STYLE` property and no `SCHEDULED:`; intact |
| `inbox-to-habit-abort-at-tags` | quit at the tags prompt | no `STYLE`, no `SCHEDULED:`; intact |
| `inbox-to-action-abort-at-schedule` | `yes-or-no-p` quits | `actions.org` does not contain the item; intact |
| `inbox-to-existing-project-abort-in-refile` | `org-refile` quits | intact |

```elisp
(ert-deftest a3madkour-test/build-habit-repeater-validates-flexibility ()
  (dolist (bad '("3" "2" "0" "-1" "x" "5d"))
    (should-error (a3madkour/-build-habit-repeater "every 3 days" bad)
                  :type 'user-error))
  (should (equal ".+3d/5d" (a3madkour/-build-habit-repeater "every 3 days" " 5 ")))
  (should (equal ".+3d" (a3madkour/-build-habit-repeater "every 3 days" "")))
  (should (equal ".+1d/2d" (a3madkour/-build-habit-repeater "daily" "2")))
  (should-error (a3madkour/-build-habit-repeater "daily" "1") :type 'user-error))
```

Replace `build-habit-repeater-bad-flexibility-foot-gun`, which pins the old behaviour.

- [ ] **Step 2: Run** — `./tests/run.sh 'abort\\|flexibility\\|unknown-heading'` — Expected: the someday, new-project and flexibility tests FAIL. The habit-tags, action and existing-project abort tests may already pass; keep them as regression tests.

- [ ] **Step 3: Implement.**
  - `inbox-to-someday`: resolve the target marker first; `(org-todo "")` immediately before `org-refile`.
  - `inbox-to-new-project`: `a3madkour/set-task-properties` before `a3madkour/create-project`. Do not restructure `create-project`.
  - `-build-habit-repeater`: validation above. `inbox-to-habit` already computes the repeater before it changes the item; keep it that way.

- [ ] **Step 4: Run** — `./tests/run.sh` — Expected: all PASS.

- [ ] **Step 5: Commit** — `fix(inbox): an aborted hand-off leaves the item as it was`, noting findings 1 and 3.

---

### Task 6: The org-roam hand-off owns its capture

**Files:**
- Modify: `custom/config.org` — `a3madkour--inbox-to-roam-marker`, `a3madkour--inbox-to-roam-finalize`, `a3madkour/inbox-to-org-roam`; add two top-level `add-hook` forms beside them
- Test: `custom/tests/test-inbox.el`

**Interfaces:**
- Produces:
  - `(a3madkour/-inbox-roam-content)` → string, called with point on the item's heading: the item's body (after its planning line and drawers), then every child subtree verbatim, re-levelled so the shallowest child is level 1 and relative depth is kept; trimmed; `""` when there is neither.
  - `a3madkour--inbox-roam-marker` — buffer-local in the capture buffer; marker to the inbox item.
  - `a3madkour--inbox-roam-finalizing` — global; the marker of the capture being finalised right now, else nil.
  - `(a3madkour--inbox-roam-prepare-finalize)` — on `org-capture-prepare-finalize-hook`; moves the current buffer's local marker (if any) into `a3madkour--inbox-roam-finalizing`.
  - `(a3madkour--inbox-to-roam-finalize)` — on `org-capture-after-finalize-hook`; if `a3madkour--inbox-roam-finalizing` is set, cuts that subtree unless `org-note-abort`, then always clears it. Otherwise does nothing.
  - `(a3madkour/inbox-to-org-roam)` — calls `org-roam-capture-` with a template whose body is always exactly `"%?"`. When it returns, if the current buffer is a capture buffer (`org-capture-mode` non-nil), inserts the content at point and sets the local marker. If not, signals `user-error` and leaves nothing set.
- The hooks are installed once at top level; nothing adds or removes them per hand-off. The old global marker variable is deleted.

Approach: content is inserted into the capture buffer after the capture starts, so neither org-capture's `%` expansion nor org-roam's `${…}` expansion ever sees it. Before writing code, confirm in `straight/repos/org/lisp/org-capture.el` that `org-capture-prepare-finalize-hook` runs in the capture buffer for both finalise and kill and that `org-note-abort` is set when the after-finalize hook runs, and in `straight/repos/org-roam/` that `org-roam-capture-` returns with the capture buffer current. If any of these does not hold, keep the requirements in the spec's Pattern 4 and the tests below, change the mechanism, and say so in the commit message.

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest a3madkour-test/inbox-roam-content-relevels-children ()
  (a3madkour-test/in-buffer "\
* TODO Parent                                                     :ptag:
:PROPERTIES:
:CAPTURED: [2026-11-01 Sun]
:END:
body line
*** NEXT Child                                                    :ctag:
:PROPERTIES:
:X: 1
:END:
**** Grandchild
* TODO Sibling
"
    (let ((content (a3madkour/-inbox-roam-content)))
      (should (string-prefix-p "body line" content))
      (should (string-match-p "^\\* NEXT Child +:ctag:$" content))
      (should (string-match-p "^:X: +1$" content))
      (should (string-match-p "^\\*\\* Grandchild$" content))
      (should-not (string-match-p "CAPTURED\\|ptag\\|Sibling" content)))))
```

A stub for the capture, used by the remaining tests:

```elisp
(defun a3madkour-test/-fake-roam-capture (name)
  "Return a stub for `org-roam-capture-' that makes buffer NAME current as a capture buffer."
  (lambda (&rest args)
    (set-buffer (get-buffer-create name))
    (setq-local org-capture-mode t)
    (setq-local a3madkour-test/-capture-args args)))
```

| Test name | Scenario | Assertion |
|---|---|---|
| `inbox-roam-content-empty-body-with-children` | item with no body, one `**` child | content starts `"* "` |
| `inbox-roam-content-no-children` / `-empty` | body only / nothing | body string / `""` |
| `inbox-to-org-roam-body-is-not-a-template` | body `100% %20 %^{x} %(error "x") ${foo}` | the template string passed to `org-roam-capture-` is `"%?"`; the capture buffer contains the body verbatim |
| `inbox-to-org-roam-own-finalize-cuts-whole-item` | hand-off; in the capture buffer run prepare then after hooks | parent and children gone from inbox; sibling remains |
| `inbox-to-org-roam-preserves-on-abort` (rewrite) | same, with `org-note-abort` bound to t | item still there; `a3madkour--inbox-roam-finalizing` nil |
| `inbox-to-org-roam-unrelated-capture-cuts-nothing` | hand-off; then in a different temp buffer run prepare then after hooks | item still there |
| `inbox-to-org-roam-two-in-flight` | hand-off A and B into two capture buffers; finalise B, then A | after B: only B's item gone; after A: both gone |
| `inbox-to-org-roam-capture-fails-to-start` | stub `org-roam-capture-` to do nothing | `user-error`; `a3madkour--inbox-roam-finalizing` nil; a later unrelated finalise cuts nothing |

Rewrite `inbox-to-org-roam-defers-cut-until-finalize` and `inbox-to-org-roam-empty-body-template` onto the new shape. Kill the fake capture buffers in each test's cleanup.

- [ ] **Step 2: Run** — `./tests/run.sh roam` — Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run** — `./tests/run.sh` — Expected: all PASS.

- [ ] **Step 5: Commit** — `fix(inbox): a roam hand-off removes only its own item, and all of it`, noting findings 4, 5, 10.

---

### Task 7: Blank prompts (owner checkpoint)

No other task waits on this one. Do Tasks 1–6 first if the owner is not available.

**Files:**
- Modify: `custom/config.org` — `a3madkour/inbox-to-someday`, `a3madkour/inbox-to-habit`
- Test: `custom/tests/test-inbox.el`

**Interfaces:**
- Consumes: `a3madkour/-read-tags` (Task 4), `a3madkour/-habit-tag-candidates`.

- [ ] **Step 1: Ask the owner.** "In your running Emacs, process an inbox item to *someday* and press RET on the empty heading prompt; then process one as a *habit* and press RET on the empty tags prompt. What was chosen each time?" Do not launch their Emacs to find out.
  - Blank already gives Parking Lot and no tags → finding 6 did not reproduce. Skip Steps 2–5, record it, done.
  - RET picked the first candidate → continue.

- [ ] **Step 2: Write the failing tests**
  - `inbox-to-someday-default-is-parking-lot` — stub `completing-read` to record all its arguments and return `"Parking Lot"`: the COLLECTION's first element is `"Parking Lot"`, the DEF argument is `"Parking Lot"`, and the item lands under Parking Lot. Keep `inbox-to-someday-default-parking-lot` (returning `""`) passing.
  - `inbox-to-habit-uses-tag-picker` — stub `a3madkour/-read-tags` to record its arguments and return `("core" "health")`: CANDIDATES contains `"core"` and `"health"`; the filed habit carries `:core:health:`. Stub `completing-read-multiple` to `(error "should not be called")`.
  - `inbox-to-habit-done-immediately-means-no-tags` — `-read-tags` returns nil → the filed habit heading has no tags.

  Rewrite `inbox-to-habit-sets-tags` onto the picker.

- [ ] **Step 3: Run** — `./tests/run.sh 'someday\\|habit'` — Expected: the new tests FAIL.

- [ ] **Step 4: Implement.** Someday prompt: `"Refile under heading (default Parking Lot): "`, `"Parking Lot"` first in the candidates and passed as the default. Habit: `(a3madkour/-read-tags "Tags" (a3madkour/-habit-tag-candidates))`, still before the item is changed.

- [ ] **Step 5: Run `./tests/run.sh`, then commit** — `fix(inbox): RET on an optional prompt means what the prompt says`, noting finding 6.

---

### Task 8: Close out

- [ ] **Step 1: Full suite** — `./tests/run.sh` — Expected: all PASS; count is the Task 0 baseline plus the new tests.

- [ ] **Step 2: Confirm the owner's hunks are still uncommitted** — `git log -p main..HEAD -- emacs-configs/custom/config.org | grep -c "exec-path-from-shell\|LAST_MODIFIED"` — Expected: `0`. `git diff -- emacs-configs/custom/config.org` still shows exactly those two hunks.

- [ ] **Step 3: Delete the patch file** — `rm "$(git rev-parse --git-dir)/owner-hunks.patch"`

- [ ] **Step 4: Write the summary for the owner.** For each of the 14 findings in the spec's table: reproduced and fixed, or did not reproduce and dropped. Plus any place the mechanism departed from this plan.

- [ ] **Step 5: Owner check** (the owner does this; ask them): tangle and reload, then
  - open the dashboard: "neetcode rust 1 problem a day" is under Seasonal Habits, overdue todos of any tag are under Overdue, and the header names the season;
  - rename the season heading in `projects.org`, reopen the dashboard: the header shows the no-season notice; rename it back;
  - process an inbox item to someday and press `C-g` at the heading prompt: the item is still a TODO in the inbox.
