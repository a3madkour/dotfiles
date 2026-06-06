# Figure-Ref `:inert + missing` Bug — Stub

**Date:** 2026-06-06
**Status:** Stub. Bug surfaced during Task 9 manual verification of the D.2 figure-ref bundled fix (plan `2026-06-05-d2-figure-ref-bundled-fix.md`, all 8 dotfiles commits landed).
**Tasks 1–8 commits:** `59869fc..cb9fe63` in dotfiles.

## Symptom

After running `M-x a3-publish-deliberate ~/org/essays/example-multi.org`, the publish completes (all bundle files re-written with fresh mtime), but `content/essays/example-multi/index.md` contains:

```
(missing asset: diagram-1.svg)
```

instead of the expected `<img src="diagram-1.svg" alt="diagram-1.svg" />`.

The `:inert + missing` marker is `--asset-emit-inert`'s output, triggered by `rewrite-asset-link`'s missing-file cond arm — which fires when `asset-resolve-path` returns `:kind 'missing` (i.e. `(file-exists-p abs)` was false).

## Fixture state at time of failure

Confirmed correct via shell inspection:

- `~/org/essays/example-multi.org` has `:PROPERTIES: :ID: 394db383-e408-44a2-a347-20ad7a54c5e7 :END:` drawer
- `~/org/essays/assets/394db383-e408-44a2-a347-20ad7a54c5e7/diagram-1.svg` exists (502 bytes)
- User ran `M-x org-roam-db-sync` after the fixture move

So the essays-aware branch in `--asset-resolve-path` SHOULD have:
1. Seen `string-prefix-p essays-dir source-file` → t (source is under `~/org/essays/`)
2. Resolved `id` via `--file-top-level-id` → `394db383-...`
3. Resolved `slug` via `--essay-slug-from-source-file` → `example-multi`
4. Computed `candidate = ~/org/essays/assets/394db383.../diagram-1.svg`
5. Checked `file-exists-p candidate` → t
6. Returned `essays-page-path = candidate`

Resulting in `abs = essays-page-path` → exists → `:kind page` → `:html` emitted.

But the bundle shows `:inert + missing`, which means one of these steps failed in production. Task 8's end-to-end ert test exercises the same code path and passes — so the gap is between the test environment and the production publish.

## Suspect: `a3madkour-pub/essays-dir` boundp / load order

- The defcustom for `a3madkour-pub/essays-dir` lives in `a3madkour-publish-history.el:29` (`default: (expand-file-name "~/org/essays/")`).
- `a3madkour-publish-assets.el` does NOT require `a3madkour-publish-history`.
- `--asset-resolve-path` guards on `(boundp 'a3madkour-pub/essays-dir)` (assets.el:93).

If history.el isn't loaded by the time `--asset-resolve-path` runs in production (publish-deliberate's load chain is `publish → publish-unpublish → publish-essays`, which DOES require history at essays.el:20 — but assets.el is required FIRST at essays.el:19), there's at least a theoretical ordering hazard. By the time the publisher actually invokes `--asset-resolve-path`, history.el should be loaded transitively via essays.el. But this is the most likely culprit to investigate first.

Other possibilities to rule out:
- `--file-top-level-id` returning nil (the regex may not match the `:PROPERTIES:` drawer format the fixture uses)
- `note-metadata` returning nil for some reason (no #+HUGO_PUBLISH? It IS present in the fixture)
- `expand-file-name` mismatch between `essays-dir` (`~/org/essays/` → home expansion) and `source-file` (id-to-file returns absolute path)

## Why Task 8's end-to-end test passes

Task 8 uses `let ((a3madkour-pub/essays-dir essays-dir) …)` to dynamically bind the var, sidestepping any boundp / load-order issue. It also stubs `id-to-file`, `note-metadata`, and `note-slug` directly. None of those stubs run in production.

## Suggested investigation

1. **Add a `message` or `debug-on-error` instrumentation** inside `--asset-resolve-path`'s essays-aware branch, then re-run the publish. Log `essays-dir`, `source-file`, `string-prefix-p` result, `id`, `slug`, `candidate`, `(file-exists-p candidate)` at each step.
2. **Verify load order** — load `a3madkour-publish-deliberate` in a fresh Emacs and check `(boundp 'a3madkour-pub/essays-dir)`.
3. **Verify `--file-top-level-id` regex** against the actual fixture format (line ends, whitespace).
4. **Add a production-mirroring ert test** that DOES NOT stub id-to-file / note-metadata / note-slug, but instead uses the real on-disk fixture pattern.

## Fix candidates

- **assets.el requires history.el.** Trivially closes the load-order hazard.
- **Move `essays-dir` defcustom to `a3madkour-publish.el`** (base module everyone requires). Architecturally cleaner — assets/essays/history all need it.
- **Drop the `boundp` guard.** Use the same `defcustom` mechanism but require history. Test then re-verifies the production path.

## Blocking status

Task 9 of the bundled-fix plan is **partially failed**:
- Pipeline doesn't crash ✓
- PDF + Word backends ran ✓
- index.md has `:inert + missing` instead of `<img>` ✗
- The actual figure-ref round-trip is NOT working end-to-end ✗

The bundled-fix dotfiles commits (`59869fc..cb9fe63`) are still correct — Tasks 1–8's tests all pass. But the spec's success criterion #2 ("`content/essays/example-multi/index.md` body contains `<img src="diagram-1.svg" />`") is unmet.

## Next step (when prioritized)

`superpowers:systematic-debugging` to root-cause via step 1 of the investigation above (instrumentation). Then either land a small fix (likely a 1-line `(require 'a3madkour-publish-history)` in assets.el) or surface a deeper resolution path bug.
