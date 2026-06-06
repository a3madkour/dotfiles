# Async Publish Pipeline — Stub

**Date:** 2026-06-06
**Status:** Stub queued. No brainstorm or plan yet — open for prioritization.
**Trigger:** `M-x a3-publish-deliberate` on `~/org/essays/example-multi.org` froze Emacs for ~30–60s during D.2 verification. UI hung, no progress reporting. xelatex compilation alone accounts for most of the freeze.

## Problem

The publish pipeline runs entirely on synchronous primitives. The user can't see progress, can't interact with Emacs, and can't cancel without `C-g`. For a single-essay multi-export run this means the editor is unusable for the duration of the slowest backend (xelatex on cold-cache: tens of seconds typical, much longer on first-run with package fetch).

## Inventory of synchronous call sites (publish modules only)

Surfaced via `grep -n "call-process\|shell-command\|process-file\|org-latex-export\|org-export-to"` across `emacs-configs/custom/lisp/a3madkour-publish*.el` on 2026-06-06.

| File | Line | Call | Cost profile |
|---|---|---|---|
| `a3madkour-publish-multi-pdf.el` | 57 | `call-process rsvg-convert` | Fast (~100ms per SVG); fires once per figure |
| `a3madkour-publish-multi-pdf.el` | 81 | `call-process xelatex` (cmd is the latex binary, `-interaction=nonstopmode`) | **Slow**: 10–60s typical; longer on first run / package fetches |
| `a3madkour-publish-multi-pdf.el` | 116 | `org-latex-export-to-latex` | In-process ox-latex; can be seconds for large docs |
| `a3madkour-publish-multi-word.el` | 39 | `call-process rsvg-convert` | Fast |
| `a3madkour-publish-multi-word.el` | 56 | `call-process pandoc` | ~1–3s |
| `a3madkour-publish-history.el` | 312 | `call-process "git"` | ~10–100ms; fires per published note |
| `a3madkour-publish-assets.el` | 294 | `call-process "git" "mv" …` | ~10–100ms; auto-remediate path |
| `a3madkour-publish-unpublish.el` | 323 | `shell-command cmd` | Variable; needs inspection |

xelatex (line 81) is the dominant cost. Everything else is small-N or fast-per-call.

## Why this matters

- Editor unusable during publish — productivity hit on every multi-export
- No progress feedback — user can't tell whether it's working or hung
- No cancel — `C-g` is unreliable inside synchronous subprocess waits
- D.2 verification flow encourages `M-x a3-publish-deliberate` as the canonical author command; freezing on the canonical happy path is a daily-paper cut

## Possible directions (no decision yet)

- **`start-process` + sentinel for xelatex / pandoc.** Wrap multi-pdf/run and multi-word/run with a process-watcher state machine. Progress via `message`. Sentinel calls the next step on `exit 0`, surfaces stderr tail on non-zero.
- **`make-process` (newer API).** Same idea, cleaner stderr handling via `:stderr` buffer.
- **`async.el` / `emacs-async`.** Library-level abstraction. Already a straight-bootstrapped package candidate; would let backends run in a forked Emacs subprocess.
- **Status buffer pattern.** Dedicated `*a3-publish*` buffer that streams subprocess output, lets the user `C-c C-c` to abort cleanly. Mirrors how `compile.el` and `magit-process` work.
- **ox-latex export — harder.** It's pure Emacs lisp running in-process. Could run inside `async-start` (forked Emacs) but loses access to the current buffer's modifications. Probably worth measuring first — may not be the dominant cost vs xelatex.

## Out of scope (for the eventual async spec)

- D.2 backend command discovery (xelatex / pandoc / rsvg-convert binaries) — keep as-is
- Multi-export error reporting format — keep existing log buffer
- Network calls (BBT fetch, library cover fetch) — separate audit

## Next step (when prioritized)

`superpowers:brainstorming` on this stub to nail down the abstraction shape and the UI affordance (status buffer vs minibuffer vs notification). Then per-backend plan.
