# Config Citations Pilot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add source-attribution citations to the three blocks under `* Bootstrap` in `config.org` (Early Init, Compile-angel, GCMH), validating a citation convention that can later scale to the rest of the 4,300-line file.

**Architecture:** Three parallel web-research agents identify likely canonical sources for each block. Their findings get synthesized into draft citation lines, batch-reviewed by the user, then applied to `config.org` as inline org-mode links between each heading and its `#+begin_src`. Results are recorded in the spec doc appendix for the future scale-up pass.

**Tech Stack:** org-mode, Emacs Lisp (target file is read-only as far as the citations are concerned — we don't execute or test elisp), markdown for the spec/plan docs.

**Reference spec:** `emacs-configs/custom/docs/superpowers/specs/2026-05-24-config-citations-pilot-design.md`

**Important note on TDD:** This plan edits prose/content, not executable code. There are no unit tests to write. The "test" for each citation is the user-review gate in Task 4 — that is the single non-skippable verification step.

---

## File Structure

**Modified files:**
- `emacs-configs/custom/config.org` — three inline citation lines inserted between headings and `#+begin_src` blocks at lines 11, 54, and 81 (line numbers will shift after each edit; use heading anchors `** Early Init`, `** Compile-angel`, `** GCMH` to locate).
- `emacs-configs/custom/docs/superpowers/specs/2026-05-24-config-citations-pilot-design.md` — Appendix section updated with research results.

**No new files.**

---

## Task 1: Research Early Init sources (parallel)

**Files:**
- Read only: `emacs-configs/custom/config.org` lines 11–53

**Parallel:** Tasks 1, 2, and 3 are independent. Dispatch them in a single message with three `Agent` tool calls. Wait for all three to return before proceeding to Task 4.

- [ ] **Step 1: Dispatch research subagent**

Tool: `Agent` with `subagent_type: "general-purpose"`, `description: "Research Early Init citation"`, prompt:

```
I'm citing sources for a public org-mode Emacs config. Help identify the likely
origin of this `Early Init` block. Web-search GitHub, blog posts, Reddit, and
Doom Emacs source for matches.

The block (lines 11–53 of `emacs-configs/custom/config.org`):

#+begin_src emacs-lisp :tangle "./early-init.el"
;;Phone config
(when (eq system-type 'android)
  (setenv "PATH" (format "%s:%s" "/data/data/com.termux/files/usr/bin" (getenv "PATH")))
  (push "/data/data/com.termux/files/usr/bin" exec-path)
  (setq touch-screen-display-keyboard t)
  (set-fontset-font t 'emoji '("Noto Emoji" . "iso10646-1") nil 'prepend)
  (setq overriding-text-conversion-style nil))
(setq load-prefer-newer t)
(setq native-comp-jit-compilation t)
(setq gc-cons-percentage 0.6)
(setq gc-cons-threshold most-positive-fixnum)
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq native-comp-async-report-warnings-errors 'silent)
(setq idle-update-delay 1.0)
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)
(setq-default cursor-in-non-selected-windows nil)
(setq highlight-nonselected-windows nil)
(setq fast-but-imprecise-scrolling t)
(setq inhibit-compacting-font-caches t)
(setq frame-inhibit-implied-resize t)
(setq default-file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist default-file-name-handler-alist)))
#+end_src

Distinctive patterns to search for (these are likely copy-pasted from a specific
source):
- The `idle-update-delay`, `bidi-display-reordering`, `cursor-in-non-selected-windows`,
  `highlight-nonselected-windows`, `fast-but-imprecise-scrolling`, `inhibit-compacting-font-caches`,
  `frame-inhibit-implied-resize` cluster — this exact set appears in known Emacs
  performance posts and configs.
- The `file-name-handler-alist` nil-then-restore-on-startup pattern is a famous
  Doom Emacs optimization.
- The Android/termux branch is likely original (personal).
- `compile-angel` author jamescherti also has an early-init template — check it.

Return a markdown report with:
1. **Ranked candidate sources** (top 3), each with:
   - URL
   - Confidence: high / medium / low
   - Evidence: which exact lines or patterns matched, with quotes from the source
2. **Suggested citation line** in org markup (one or two sentences max) that
   covers the multi-source nature honestly.
3. **Any portions you believe are original/personal** (e.g. Android branch).

Be honest about uncertainty. Do not invent URLs. If a candidate has only weak
pattern matches (no exact text), say so.
```

- [ ] **Step 2: Save the agent's report**

Save the full markdown report to a working file:
`emacs-configs/custom/docs/superpowers/specs/.pilot-research-early-init.md`
(Dot-prefixed so it's clearly a temp file; will be folded into the appendix and deleted in Task 8.)

---

## Task 2: Research Compile-angel sources (parallel)

**Files:**
- Read only: `emacs-configs/custom/config.org` lines 54–80

- [ ] **Step 1: Dispatch research subagent**

Tool: `Agent` with `subagent_type: "general-purpose"`, `description: "Research Compile-angel citation"`, prompt:

```
I'm citing sources for a public org-mode Emacs config. Help identify the likely
origin of this `Compile-angel` block. The package is by jamescherti; the
expected primary source is its README on GitHub. Web-search to confirm and
also to see if there's a known blog post that introduced this exact snippet.

The block (lines 54–80 of `emacs-configs/custom/config.org`):

#+begin_src emacs-lisp
(use-package compile-angel
  :ensure t
  :demand t
  :config
  (setq compile-angel-verbose t)
  (push "/init.el" compile-angel-excluded-files)
  (push "/early-init.el" compile-angel-excluded-files)
  (compile-angel-on-load-mode 1))
#+end_src

(Note: the user's file also contains the commented-out documentation block
verbatim from somewhere — likely the README. Confirm.)

Return a markdown report with:
1. **Primary source** with URL, confidence, evidence (quote the matching README
   section if found).
2. **Any secondary sources** (blog posts about compile-angel) if relevant.
3. **Suggested citation line** in org markup (one sentence).

Be honest about uncertainty.
```

- [ ] **Step 2: Save the agent's report**

Save to `emacs-configs/custom/docs/superpowers/specs/.pilot-research-compile-angel.md`.

---

## Task 3: Research GCMH sources (parallel)

**Files:**
- Read only: `emacs-configs/custom/config.org` lines 81–104

- [ ] **Step 1: Dispatch research subagent**

Tool: `Agent` with `subagent_type: "general-purpose"`, `description: "Research GCMH citation"`, prompt:

```
I'm citing sources for a public org-mode Emacs config. Help identify the likely
origin of this `GCMH` block (Garbage Collector Magic Hack). The package gcmh
is by Andrea Corallo and is widely used; the gc-cons-threshold tweaks in
emacs-startup-hook and the startup-time message are common Emacs idioms.

The block (lines 81–104 of `emacs-configs/custom/config.org`):

#+begin_src emacs-lisp
(use-package gcmh
  :diminish gcmh-mode
  :config
  (setq gcmh-idle-delay 5
        gcmh-high-cons-threshold (* 16 1024 1024))  ; 16mb
  (gcmh-mode 1))

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-percentage 0.2)
            (setq gc-cons-threshold 8000000)))

(add-hook 'emacs-startup-hook
          (lambda ()
            (message "Emacs ready in %s with %d garbage collections."
                     (format "%.2f seconds"
                             (float-time
                              (time-subtract after-init-time before-init-time)))
                     gcs-done)))
#+end_src

Things to search for:
- The exact `(* 16 1024 1024)` value with `gcmh-idle-delay 5` — is this from
  the gcmh README, or from a downstream config (e.g. Doom)?
- The "Emacs ready in X seconds with Y garbage collections" message is famously
  from the Emacs init.el example or from someone like Patrick McMillan / Sacha
  Chua / the Emacs FAQ.

Return a markdown report with:
1. **Ranked sources** (top 2–3), URL, confidence, evidence.
2. **Suggested citation line** in org markup. May span multiple sources.

Be honest about uncertainty.
```

- [ ] **Step 2: Save the agent's report**

Save to `emacs-configs/custom/docs/superpowers/specs/.pilot-research-gcmh.md`.

---

## Task 4: Synthesize drafts + user review gate

**Files:**
- Read: the three `.pilot-research-*.md` files from Tasks 1–3
- No edits yet

- [ ] **Step 1: Read all three research reports**

- [ ] **Step 2: Draft citation lines**

For each of the three blocks, draft a single org-formatted citation line in this format:

```
Sourced from [[URL][Source name]].
```

or for multi-source:

```
GC tuning adapted from [[url1][Doom Emacs]]; performance settings from [[url2][post]]. Android branch is original.
```

If a research report flagged "no confident source," do NOT invent one — propose leaving that block un-cited and record the search in the appendix.

- [ ] **Step 3: Present batch to user**

In a single message to the user, show all three draft citation lines together along with the confidence level and one-line evidence summary per block. Format:

```
Bootstrap citations — please review:

** Early Init  (confidence: <high/medium/low>)
Draft: <citation line>
Evidence: <one sentence>

** Compile-angel  (confidence: <...>)
Draft: <...>
Evidence: <...>

** GCMH  (confidence: <...>)
Draft: <...>
Evidence: <...>

Approve all, or tell me which ones to revise/drop.
```

- [ ] **Step 4: Wait for user approval**

Do NOT proceed to Task 5 until the user approves the batch (or provides revisions). If they revise, update the drafts and re-present.

---

## Task 5: Apply citation to Early Init block

**Files:**
- Modify: `emacs-configs/custom/config.org` at heading `** Early Init` (currently line 11)

- [ ] **Step 1: Apply edit**

Use `Edit` tool with:
- `old_string`: `** Early Init\n#+begin_src emacs-lisp :tangle "./early-init.el"`
- `new_string`: `** Early Init\n<approved citation line from Task 4>\n#+begin_src emacs-lisp :tangle "./early-init.el"`

(Exact citation text comes from Task 4's approved draft — substitute it in.)

- [ ] **Step 2: Visual verify**

Read lines 10–15 of `config.org` and confirm the citation line is present, the `#+begin_src` is unchanged, and the `:tangle` directive is intact. The `:tangle` directive is load-bearing — if it's accidentally dropped, the file won't tangle to `early-init.el` anymore.

---

## Task 6: Apply citation to Compile-angel block

**Files:**
- Modify: `emacs-configs/custom/config.org` at heading `** Compile-angel`

- [ ] **Step 1: Apply edit**

Use `Edit` tool with:
- `old_string`: `** Compile-angel\n#+begin_src emacs-lisp`
- `new_string`: `** Compile-angel\n<approved citation line from Task 4>\n#+begin_src emacs-lisp`

Note: `** Compile-angel\n#+begin_src emacs-lisp` appears more than once in the file (every heading has a `#+begin_src emacs-lisp` after it). Edit's uniqueness rule means we need the heading text in the match — `** Compile-angel\n#+begin_src emacs-lisp` is unique because it pairs that exact heading with the immediately-following src marker.

- [ ] **Step 2: Visual verify**

Read the Compile-angel section (use `Grep` to find the heading line, then `Read` with `offset` near that line) and confirm citation is present.

---

## Task 7: Apply citation to GCMH block

**Files:**
- Modify: `emacs-configs/custom/config.org` at heading `** GCMH`

- [ ] **Step 1: Apply edit**

Use `Edit` tool with:
- `old_string`: `** GCMH\n#+begin_src emacs-lisp`
- `new_string`: `** GCMH\n<approved citation line from Task 4>\n#+begin_src emacs-lisp`

- [ ] **Step 2: Visual verify**

Read the GCMH section and confirm citation is present.

---

## Task 8: Update spec doc appendix

**Files:**
- Modify: `emacs-configs/custom/docs/superpowers/specs/2026-05-24-config-citations-pilot-design.md`
- Delete: the three `.pilot-research-*.md` temp files

- [ ] **Step 1: Replace the placeholder appendix table**

Use `Edit` to replace the existing appendix section. The existing content is:

```
## Appendix: Pilot results

_(To be filled in after the research phase, before edits.)_

| Block | Confidence | Source(s) | Citation line | Notes |
|-------|-----------|-----------|---------------|-------|
| Early Init | TBD | TBD | TBD | |
| Compile-angel | TBD | TBD | TBD | |
| GCMH | TBD | TBD | TBD | |
```

Replace with a completed table using the data from the research reports and the final approved citations from Task 4. Include any blocks that were left un-cited (mark them clearly).

- [ ] **Step 2: Delete the three temp research files**

```bash
rm emacs-configs/custom/docs/superpowers/specs/.pilot-research-early-init.md
rm emacs-configs/custom/docs/superpowers/specs/.pilot-research-compile-angel.md
rm emacs-configs/custom/docs/superpowers/specs/.pilot-research-gcmh.md
```

The detail from those files is now folded into the appendix; the temp files have served their purpose.

- [ ] **Step 3: Flip spec status from Draft to Pilot-complete**

Edit the spec doc's `**Status:**` header line from `Draft — awaiting user review` to `Pilot complete — YYYY-MM-DD` (use today's date).

---

## Task 9: Verify and commit

**Files:**
- All changes from Tasks 5–8

- [ ] **Step 1: Sanity-check the config.org changes**

Run:
```bash
git -C /Stuff/a3madkour/dotfiles diff -- emacs-configs/custom/config.org
```
Expected: exactly three additions, each a single citation line under `** Early Init`, `** Compile-angel`, `** GCMH`. No other lines changed. No `:tangle` directives touched. No `#+begin_src`/`#+end_src` markers altered.

If the diff shows anything else, STOP and investigate. Common failure: an `Edit` accidentally matched the wrong heading and inserted in the wrong place.

- [ ] **Step 2: Check that the file still loads as org**

Run:
```bash
emacs --batch --eval "(progn (find-file \"/Stuff/a3madkour/dotfiles/emacs-configs/custom/config.org\") (org-mode) (message \"loaded\"))" 2>&1 | tail -5
```
Expected: output contains `loaded` and no error backtrace. If org-mode reports parse errors, fix before committing.

- [ ] **Step 3: Commit**

```bash
git -C /Stuff/a3madkour/dotfiles add emacs-configs/custom/config.org emacs-configs/custom/docs/superpowers/specs/2026-05-24-config-citations-pilot-design.md
git -C /Stuff/a3madkour/dotfiles status
```

Verify `git status` shows only the two intended files staged, plus the three deleted temp files (`.pilot-research-*.md`). No straggling temp files.

```bash
git -C /Stuff/a3madkour/dotfiles commit -m "$(cat <<'EOF'
Add source citations to Bootstrap section of config.org (pilot)

Cites Early Init, Compile-angel, and GCMH blocks as part of the citation
pass tracked in config.org's first TODO. Pilot validates the convention
(inline org link between heading and #+begin_src) before scaling to the
rest of the file.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Confirm commit**

```bash
git -C /Stuff/a3madkour/dotfiles log -1 --stat
```

Expected: the commit shows changes to `config.org` and the spec doc.

---

## Out of scope (explicitly NOT in this plan)

- Citing any block outside `* Bootstrap`. After this pilot ships, a follow-up plan can extend the convention to the rest of the file.
- Modifying the `a3madkour-publish*.el` infrastructure to render citations specially. Inline org links render natively when exported — no publish-side changes needed.
- Removing the original `* TODO Go through the config and cite all the sources of information` line on line 9. The TODO covers the whole file, not just Bootstrap; it stays until the full pass is done.
