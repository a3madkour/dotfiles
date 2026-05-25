# Config Citation Pass — Pilot Design

**Date:** 2026-05-24
**Status:** Pilot complete — 2026-05-24
**Target file:** `emacs-configs/custom/config.org` (4,323 lines)
**Related TODO:** Line 9 — `* TODO Go through the config and cite all the sources of information`

## Motivation

The org-mode config will be published (see the in-progress `a3madkour-publish*.el` infra in the same directory). For a public artifact, snippets borrowed from other configs, blog posts, package READMEs, and Reddit threads need attribution — both to credit authors and to let readers follow links to original context.

A few existing partial citations live in the file (e.g. line 556 `** Insert file path (from Doom)`, line 1255 `;;uv I LOVE YOU DUDE: https://mclare.blog/posts/using-uv-in-emacs/`), but the bulk of the file is unannotated.

## Scope: Pilot on Bootstrap section only

Pilot covers three blocks under `* Bootstrap` (lines 11–104):

1. `** Early Init` — performance/UI tuning (GC, native-comp, bidi, font cache, frame setup)
2. `** Compile-angel` — wraps `jamescherti/compile-angel.el`
3. `** GCMH` — GC magic hack with idle-delay tuning

These were chosen over alternatives (Completion, Editor) because they:
- Form a small, contained pilot (~90 lines)
- Have distinctive code that should be traceable to specific sources
- Mix the messy real-world cases (multi-source patchwork in Early Init, single-source in the other two) so the convention gets stress-tested early

Out of scope for this pilot: every other section. If the convention works here, the same workflow scales to the rest.

## Citation Convention

Inline org link in prose, placed between the heading and the `#+begin_src` block. Three patterns:

### Single clear source
```org
** Compile-angel
Sourced from [[https://github.com/jamescherti/compile-angel.el][compile-angel by jamescherti]].
#+begin_src emacs-lisp
...
```

### Adapted / multi-source
```org
** Early Init
GC and native-comp tuning adapted from [[url][source A]]; bidi/scroll tweaks from [[url][source B]];
Android branch is original.
#+begin_src emacs-lisp
...
```

### No confident source found
Leave un-cited in the file. Record the block in this spec's appendix so it can be revisited later. Do not write "origin unknown" in the published artifact — it draws attention without adding value.

## Research Workflow

Batch mode (per user preference):

1. For each of the 3 blocks, dispatch a research agent (`general-purpose`) with the block's distinctive snippets. Agent web-searches GitHub, blogs, Reddit, package READMEs for matches.
2. Agent returns: ranked candidate sources, confidence level, and evidence (exact-text matches, near-matches, or pattern matches).
3. After all 3 finish, draft citation lines for each block.
4. Present all 3 drafts to user in one review pass.
5. After approval, edit `config.org` to insert citations and commit.

## Deliverables

1. **`config.org`** — Bootstrap section (lines 11–104) edited to include the 3 citation lines.
2. **This spec file** — appended with a "Pilot results" section recording per-block candidates, confidence, and final citation decisions. Doubles as design doc and pilot retrospective.

## Success Criteria

- Each of the 3 Bootstrap blocks either has a confident citation, or is documented in the appendix as "no source found" with what was searched.
- The citation format renders cleanly when the org file is exported by the publish infra (visual check after edit).
- User reviews and approves the batch before any edits to `config.org`.

## Risks / Open Questions

- **Wrong attribution.** Web-searched candidates may match by coincidence (common Emacs idioms appear in many configs). Mitigation: agent must show evidence (e.g. exact 3+-line text match), and user reviews each before commit.
- **No findable source.** Some snippets are personal accumulation. Acceptable outcome — record in appendix.
- **Scope creep.** Tempting to expand mid-pilot. Don't. Validate the convention on 3 blocks first.

## Appendix: Pilot results

Research conducted via WebFetch against the canonical upstream sources. Subagents in the dispatched research workflow lacked network access (sandboxed); the controlling session's WebFetch tool succeeded. Workflow note for scale-up: do the web fetches from the parent session rather than dispatching research subagents, until that sandbox limitation is resolved.

### Early Init

- **Confidence:** high
- **Sources:**
  - [Doom Emacs `lisp/doom-start.el`](https://github.com/doomemacs/doomemacs/blob/master/lisp/doom-start.el) — exact-comment matches for `fast-but-imprecise-scrolling`, `cursor-in-non-selected-windows`, `highlight-nonselected-windows`, `inhibit-compacting-font-caches`, `bidi-display-reordering` (all carry Doom's distinctive prose comments verbatim or near-verbatim in the user's pre-citation file).
  - [jamescherti/minimal-emacs.d `early-init.el`](https://github.com/jamescherti/minimal-emacs.d) — exact matches for `frame-inhibit-implied-resize`, `gc-cons-threshold most-positive-fixnum`, `load-prefer-newer`, `default-frame-alist` UI-bar pushes, and the `file-name-handler-alist` save-and-restore on `emacs-startup-hook`.
- **Original:** the `(when (eq system-type 'android) ...)` Termux branch — `system-type 'android` is an Emacs 30+ feature.
- **Citation applied:** `Adapted from [[...][Doom Emacs's startup optimizations]] and [[...][jamescherti/minimal-emacs.d]]; the Android/Termux branch is original.`

### Compile-angel

- **Confidence:** very high
- **Source:** [compile-angel README by jamescherti](https://github.com/jamescherti/compile-angel.el) — verbatim, including the distinctive multi-line comment ("The following directive prevents compile-angel from compiling your init files..."). User's only addition is `:ensure t`.
- **Citation applied:** `Sourced from the [[...][compile-angel README]] by jamescherti.`

### GCMH

- **Confidence:** medium-high
- **Sources:**
  - [gcmh by Andrea Corallo](https://gitlab.com/koral/gcmh) — the package itself; README's only example is `(gcmh-mode 1)`, so specific tuning values are NOT from the README.
  - [Doom Emacs `lisp/doom-start.el`](https://github.com/doomemacs/doomemacs/blob/master/lisp/doom-start.el) — pattern for `gcmh-idle-delay` + `gcmh-high-cons-threshold` config wrapping. Doom uses `'auto` + 64mb; the user's `5` + 16mb are personal tuning.
  - The "Emacs ready in X seconds with Y garbage collections" message is a widely-circulating Emacs idiom (System Crafters, many dotfiles configs); often attributed to Doom but appears in many sources.
- **Citation applied:** `Sourced from [[...][gcmh by Andrea Corallo]]; tuning values and startup-time message pattern adapted from [[...][Doom Emacs]].`

### Methodology lessons for scale-up

1. **Subagent network access is unreliable in this environment.** The next pass should fetch URLs from the parent session, or batch-extract candidate snippets and use `WebFetch` directly. Saves a round trip per block.
2. **The "exact distinctive comment" heuristic worked extremely well.** Phrases like "The following directive prevents compile-angel from compiling your init files..." and Doom's "More performant rapid scrolling over unfontified regions..." are unique enough to Google for an immediate match. Lean on this for future sections.
3. **Some blocks will have personal tuning on top of borrowed structure.** Citation should distinguish "structure adapted from X" vs "values chosen by me." The GCMH citation models this.
4. **A block can legitimately have 2+ sources.** Don't force single-source attribution.
