# D.2 Figure-Ref Bundled Fix — Design

**Date:** 2026-06-05
**Status:** Spec drafted; implementation pending
**Target files:**
- `emacs-configs/custom/lisp/a3madkour-publish-rewrite.el`
- `emacs-configs/custom/lisp/a3madkour-publish-assets.el`
- `emacs-configs/custom/lisp/a3madkour-publish-essays.el`
- `emacs-configs/custom/lisp/a3madkour-publish-garden.el`
- `emacs-configs/custom/lisp/a3madkour-publish-research.el`
- `~/org/essays/example-multi.org` (fixture hardening)
**Related slice:** D.2 multi-target export (shipped 2026-06-04, commits `a6336f3..5be2d7a`); this fix closes D.2 follow-up #1 (figure-ref round-trip verification).

## Motivation

D.2's figure-ref verification — running `M-x a3-publish-deliberate RET ~/org/essays/example-multi.org RET` to confirm `[[file:diagram-1.svg]]` round-trips through Hugo + PDF + Word backends — surfaced two distinct bugs in B.4's asset pipeline. Both fire on the same publish invocation:

```
[a3-pub-essays] rewrite WARN (~/org/essays/example-multi.org):
  file-link target /Users/a3madkour/diagram-1.svg lacks :ID:; cannot resolve
user-error: a3madkour-pub: cannot read file: /Users/a3madkour/from-validate
```

The first warning is silent data loss; the second aborts the publish before any asset gets copied or the D.2 after-publish hook fires. Either bug alone makes the figure-ref round-trip non-functional, so both fixes must ship in the same patch.

The bugs were not caught by D.2's existing test coverage because:
- D.2's integration tests use bare-path forms (`[[diagram-1.svg]]`) that bypass Bug 1's `file:` dispatch
- B publishers' integration tests stub `note-slug` via `cl-letf`, so they never exercise the `"from-validate"` propagation that surfaces in production

Commit `cea5d2d` (2026-06-04) fixed the symmetric bug in `--extract-asset-refs`, but the analogous bug in `rewrite-buffer-links` was not surfaced by that commit's test repro.

## Scope

In scope:
1. Bug 1 — `rewrite-link` normalizes `file:` prefix on asset-shaped paths
2. Bug 2 — `asset-validate-and-copy` accepts a `source-note-id` parameter; `rewrite-asset-link` tolerates nil
3. Essays-aware branch in `asset-resolve-path` — resolves `[[file:<basename>]]` against `essays-dir/assets/<source-id>/` when source is an essay
4. `example-multi.org` fixture hardening — `:ID:` drawer added; SVG moved from sibling to `essays-dir/assets/<UUID>/`
5. Test coverage — ert unit tests + one end-to-end ert test

Out of scope:
- Garden / research / library asset conventions (unchanged)
- The "from-validate" sentinel in test fixtures and docstrings (incidental cleanup as encountered, but not a scope item)
- Auto-remediation behavior changes
- D.2 PDF / Word backend changes — they already call `list-referenced-files` correctly post-`cea5d2d`

## Bug 1: Pre-export rewriter erases `[[file:asset.ext]]`

### Trace

`a3madkour-publish-rewrite.el:273` — `rewrite-link` dispatches on URL scheme:

```elisp
(cond
 ((equal scheme "id")   (--rewrite-id-link path text source-note-id))
 ((equal scheme "file") (--rewrite-file-link path text source-note-id))
 ((member scheme a3madkour-pub-typed-link-types) ...)
 ((--external-scheme-p scheme) ...)
 ((--asset-shaped-link-p path) (rewrite-asset-link path text source-note-id))
```

The `file:` arm fires before the asset-shaped arm. `--asset-shaped-link-p` (line 126) returns nil for any path with a scheme — including `file:` — so even paths to obvious assets (`file:diagram.svg`) fall through to `--rewrite-file-link`.

`--rewrite-file-link` (line 229) assumes the target is another org note carrying an `:ID:` drawer. For an SVG/PNG/PDF target there is no `:ID:`, so it returns `(:inert <text> :warnings ("file-link target ... lacks :ID:; cannot resolve"))`. `rewrite-buffer-links` then deletes the `[[…]]` brackets from the buffer and leaves only the bare text. The figure reference is erased from the source before ox-hugo ever sees it.

Author intent (`[[file:diagram-1.svg]]` is the most natural org syntax for "link the sibling SVG") is incompatible with the current dispatcher.

### Why cea5d2d didn't catch this

`cea5d2d` patched `--extract-asset-refs` (the walker `asset-validate-and-copy` uses to find asset references) but the buffer rewriter is a separate scanner. Two scanners walk the same `[[…]]` forms with two different code paths; the bug fix landed on one only.

### Fix

Add a one-line normalization at the top of `rewrite-link`, before the cond:

```elisp
(let* ((parsed   (--parse-org-link org-link))
       (raw-path (plist-get parsed :path))
       (path     (--strip-file-prefix-if-asset raw-path))   ; NEW
       (text     (plist-get parsed :text))
       (scheme   (--link-scheme path))                       ; computed AFTER strip
       ...))
```

New helper:

```elisp
(defun a3madkour-pub--strip-file-prefix-if-asset (path)
  "Return PATH with a `file:' prefix stripped if the remainder is asset-shaped.
Mirrors cea5d2d's normalization in --extract-asset-refs so both walkers
(--extract-asset-refs + rewrite-buffer-links) classify asset links the same
way. Paths without `file:' prefix and `file:' paths whose target has a `.org'
extension are returned unchanged."
  (cond
   ((not (string-prefix-p "file:" path)) path)
   ((let ((bare (substring path 5)))
      (and (file-name-extension bare)
           (not (member (file-name-extension bare) '("org")))))
    (substring path 5))
   (t path)))
```

After normalization, `scheme` is computed on the stripped path. For `file:diagram-1.svg` → `scheme` is nil → `--asset-shaped-link-p` matches → `rewrite-asset-link` fires. For `file:other-note.org` → unchanged → `--rewrite-file-link` still fires (existing note-link behavior preserved).

This is the **symmetric mirror** of cea5d2d in `--extract-asset-refs:179-181`. The two scanners now apply the same normalization.

## Bug 2: `asset-validate-and-copy` hardcodes `"from-validate"`

### Trace

`a3madkour-publish-assets.el:423` — `asset-validate-and-copy`'s docstring (lines 443–451) declares the contract that B's per-section publishers will pass a real source-note-id. The signature never accepted one — `(org-file bundle-dest-dir &optional dry-run)`. Internally (line 465) the function passes the literal string `"from-validate"` to `rewrite-asset-link`.

`rewrite-asset-link` (line 304):
```elisp
(let* ((source-file (--id-to-file source-note-id))   ; nil for "from-validate"
       (source-slug (note-slug source-note-id))      ; ← this crashes
       ...)
```

`note-slug "from-validate"`:
- `--resolve-file-or-id "from-validate"` → not a UUID → returns `"from-validate"` unchanged
- `note-metadata "from-validate"` → `--parse-file "from-validate"`
- `(expand-file-name "from-validate")` → `/Users/a3madkour/from-validate` (default-directory at publish time)
- `(file-readable-p ...)` → nil
- `(user-error "a3madkour-pub: cannot read file: %s" "/Users/a3madkour/from-validate")`

The user-error propagates up the call stack. The essays/garden/research publishers don't catch it. The publish aborts before any asset copy, before `record-publish`, and before the D.2 after-publish hook fires.

### Why this never fired in B production

Real B publishes (B.1 garden, B.2 library, B.3 research, B.4 essays) have shipped without triggering this bug because:
1. Most real source notes use `./assets/page/<slug>/foo.png` (the canonical-asset-root convention) or bare-path `[[diagram.svg]]` forms — neither hits the `file:` prefix path
2. The bare `[[diagram.svg]]` form does go through `asset-validate-and-copy` and would crash on `"from-validate"`, but it's rarely used in real B-published notes; canonical-root paths dominate
3. Integration tests stub `note-slug` via `cl-letf` so the crash never surfaces in CI

example-multi.org is the first production fixture authoring an asset via `[[file:…]]` form against a non-canonical-root location — surfacing both bugs at once.

### Fix

Three coordinated changes.

**a. `asset-validate-and-copy` signature.** New optional positional parameter `source-note-id`, inserted before the existing `dry-run` optional:

```elisp
(defun a3madkour-pub/asset-validate-and-copy
    (org-file bundle-dest-dir &optional source-note-id dry-run)
  ...)
```

Internal hardcoded `"from-validate"` is replaced by `source-note-id` (or nil when caller omits). The `from-validate` sentinel string is removed from the function body. The docstring contract paragraph (lines 443–451) is replaced with a description of the new parameter; references to "stub `note-slug` via `cl-letf`" are removed since tests can now pass nil cleanly.

**b. `rewrite-asset-link` nil-tolerance.** Update lines 304–305 to skip the cross-namespace check when `source-slug` is nil:

```elisp
(let* ((source-file (--id-to-file source-note-id))
       (source-slug (and source-note-id (note-slug source-note-id)))
       (resolved (--asset-resolve-path path source-file))
       ...)
  ...
  ;; Cross-namespace use → inert + WARN (only checked when source-slug known).
  ((and (eq kind 'page)
        source-slug
        (--asset-cross-namespace-p resolved source-slug))
   ...)
```

No `condition-case` swallowing — nil-tolerance is structural, not defensive. The semantics: when caller doesn't supply a source-note-id, the cross-namespace check is suppressed (there's no source slug to compare against). This is correct behavior for test paths that don't need namespace validation.

**c. B publisher callers thread `id` through.** Each handler (essays / garden / research) already computes `id` from `note-metadata` at the top of its publish function. Each pass-through point updates from two args to three:

```elisp
;; Before:
(a3madkour-pub/asset-validate-and-copy file bundle-dir)
;; After:
(a3madkour-pub/asset-validate-and-copy file bundle-dir id)
```

Three call sites: `essays.el:255`, `garden.el:123`, `research.el:340`.

## Essays-aware asset resolution

### The path-resolution mismatch

After Bugs 1 + 2 fixes, `rewrite-asset-link` runs for `[[file:diagram-1.svg]]` in `example-multi.org`. It calls `--asset-resolve-path("diagram-1.svg", source-file)` where `source-file = ~/org/essays/example-multi.org`. The current resolution (`assets.el:75-92`) expands the path against `source-dir` (`~/org/essays/`) → `~/org/essays/diagram-1.svg`, then classifies against the canonical asset root `~/org/notes/assets/`. The result is `:kind out-of-root` — the file is not under canonical-root.

For essays specifically this classification is wrong. Essays use a per-essay assets-dir convention enforced by `essays--copy-asset-dir` (`essays.el:126`): assets live at `essays-dir/assets/<source-id>/`, not at canonical-root. The author's natural `[[file:diagram-1.svg]]` against an essay should find the file at `~/org/essays/assets/<UUID>/diagram-1.svg`.

### Fix

Add an essays-aware branch in `--asset-resolve-path`:

```elisp
(defun a3madkour-pub--asset-resolve-path (path source-file)
  "..."
  (let* ((source-dir (or (and source-file (file-name-directory source-file))
                         default-directory))
         (essays-dir (and (boundp 'a3madkour-pub/essays-dir)
                          a3madkour-pub/essays-dir))
         ;; NEW: essays-aware lookup. If source-file is under essays-dir,
         ;; try essays-dir/assets/<source-id>/<basename> before falling
         ;; through to canonical-asset-root classification.
         (essays-page-path
          (and source-file essays-dir
               (string-prefix-p (expand-file-name essays-dir) source-file)
               (let* ((id (a3madkour-pub--file-top-level-id source-file))
                      (page-dir (and id
                                     (expand-file-name
                                      (format "assets/%s/" id) essays-dir)))
                      (candidate (and page-dir
                                      (expand-file-name
                                       (file-name-nondirectory path) page-dir))))
                 (and candidate (file-exists-p candidate) candidate))))
         (abs (or essays-page-path
                  (expand-file-name path source-dir)))
         (root (expand-file-name a3madkour-pub-canonical-asset-root))
         (root-page (file-name-as-directory (expand-file-name "page" root)))
         (root-shared (file-name-as-directory (expand-file-name "shared" root)))
         (exists (file-exists-p abs)))
    (cond
     ((not exists)
      (list :kind 'missing :abs-path abs :rel-path nil))
     ;; NEW: essays-page-path resolved → classify as :page with essay slug
     ;; as the namespace key (slug derived by caller from source-note-id).
     ;; Cross-namespace check is suppressed because source-slug equals the
     ;; resolved page-slug by construction.
     (essays-page-path
      (list :kind 'page :abs-path abs
            :rel-path (concat "page/" (a3madkour-pub--essay-slug-from-source-file
                                       source-file) "/" (file-name-nondirectory abs))))
     ((string-prefix-p root-page abs) ...)   ; unchanged
     ((string-prefix-p root-shared abs) ...)
     (t (list :kind 'out-of-root :abs-path abs :rel-path nil)))))
```

The essays-aware branch:
1. Fires only when `source-file` is under `essays-dir` AND has a top-level `:ID:`
2. Falls back to existing resolution if file not found at `essays-dir/assets/<id>/<basename>`
3. Classifies as `:kind page` with `:rel-path` synthesized so cross-namespace check is a no-op
4. Does NOT touch garden / research / library code paths

The `essays-dir/assets/<id>/` convention is already established by `essays--copy-asset-dir`; the rewriter now resolves against the same dir.

## Fixture: `:ID:` drawer for `example-multi.org`

Two changes to `~/org/essays/example-multi.org`:

1. Add `:PROPERTIES: :ID: <UUID> :END:` drawer at the very top (before `#+title:`)
2. Move `~/org/essays/diagram-1.svg` to `~/org/essays/assets/<UUID>/diagram-1.svg`

The UUID is generated once and committed as part of this fix. After this change the fixture exercises:
- `note-metadata` → `:id` populated
- `id-to-file` → resolves correctly via org-roam DB after sync
- essays-aware asset resolution → finds the SVG via per-essay assets dir
- `essays--copy-asset-dir` → dumps the assets dir into the bundle (idempotent with `asset-validate-and-copy`)
- D.2 after-publish hook → fires with real id, slug, bundle-dir

## Implementation outline

Six change targets:

1. **`a3madkour-publish-rewrite.el`** — add `--strip-file-prefix-if-asset`; call at top of `rewrite-link`
2. **`a3madkour-publish-assets.el`** — `asset-validate-and-copy` signature; `rewrite-asset-link` nil-tolerance; `--asset-resolve-path` essays-aware branch + `--essay-slug-from-source-file` helper
3. **`a3madkour-publish-essays.el`** — thread `id` into `asset-validate-and-copy` call (line 255)
4. **`a3madkour-publish-garden.el`** — thread `id` into `asset-validate-and-copy` call (line 123)
5. **`a3madkour-publish-research.el`** — thread `id` into `asset-validate-and-copy` call (line 340)
6. **`~/org/essays/example-multi.org`** + sibling SVG move — `:ID:` drawer + `~/org/essays/assets/<UUID>/diagram-1.svg`

Order of implementation (TDD-driven, each step lands its own commit):

1. ert: `--strip-file-prefix-if-asset` unit tests → helper impl
2. ert: `rewrite-link` end-to-end via `file:` prefix → call-site change
3. ert: `asset-validate-and-copy` new signature → signature change + caller-stubs update in existing tests
4. ert: `rewrite-asset-link` nil source-note-id tolerance → cross-namespace skip when nil
5. ert: `--asset-resolve-path` essays-aware branch → impl
6. B publishers: thread `id` into call sites (one commit per handler with its handler test update)
7. Fixture: `example-multi.org` `:ID:` drawer + SVG move
8. End-to-end ert test in `essays-test.el` (figure-ref-round-trip)
9. Manual D.2 verification (5-step) — committed only after the rest is green

## Test plan

### Unit tests (ert)

`a3madkour-publish-rewrite-test.el` — `file:` prefix normalization:

| Test | Input | Expected |
|---|---|---|
| `strip-file-prefix-on-asset/svg` | `"file:diagram.svg"` | `"diagram.svg"` |
| `strip-file-prefix-on-asset/png` | `"file:hero.png"` | `"hero.png"` |
| `preserve-file-prefix-on-org-target` | `"file:other-note.org"` | `"file:other-note.org"` |
| `preserve-bare-asset-path` | `"diagram.svg"` | `"diagram.svg"` |
| `preserve-id-link` | `"id:abc-…"` | `"id:abc-…"` |
| `rewrite-link-asset-via-file-prefix` | `[[file:diagram.svg]]` | `:html` with `<img>` |
| `rewrite-link-file-prefix-org-target` | `[[file:other.org]]` | existing file-link path |

`a3madkour-publish-assets-test.el` — signature + nil-tolerance + essays-aware resolution:

| Test | What it asserts |
|---|---|
| `asset-validate-and-copy/threads-source-note-id` | Stubs `rewrite-asset-link`; asserts called with id passed by caller |
| `asset-validate-and-copy/nil-source-note-id-tolerated` | Pass nil; no user-error; rewrite called with nil |
| `rewrite-asset-link/nil-source-skips-cross-namespace` | Cross-namespace-eligible path; source nil; still `:html` |
| `asset-resolve-path/essays-source-resolves-against-assets-id-dir` | Source under essays-dir + has `:ID:`; finds file in `assets/<id>/` |
| `asset-resolve-path/essays-fallback-to-canonical-root` | Source under essays-dir but no file in `assets/<id>/`; falls through |
| `asset-resolve-path/non-essays-source-unchanged` | Source under garden; existing classification wins |

`a3madkour-publish-essays-test.el`, `-garden-test.el`, `-research-test.el` — each gets one test asserting the publisher threads `id` into `asset-validate-and-copy` (stub captures the third arg).

Net new ert tests: ~14 (13 unit + 1 end-to-end). Suite from 525 → ~539 green.

### End-to-end ert test (replaces what the prior B-slice memory notes called "integration tests")

Dotfiles has no separate fixture / Python integration runner — all "integration tests" in the publisher modules are ert tests that build a fixture in a temp dir via `with-temp-file` / `make-temp-file`, run the full pipeline, and assert on output. Same pattern here.

Add **one** end-to-end test to `a3madkour-publish-essays-test.el`:

```
ert-deftest a3madkour-pub-essays-test/figure-ref-round-trip
  Stages a temp essays-dir with:
    source/example-figure-ref.org   ← :ID: + [[file:fig.svg]]
    source/assets/<uuid>/fig.svg
  Stubs org-roam-id-find so the :ID: resolves to the temp source file.
  Calls a3madkour-pub-essays/publish-essay-file on the source.
  Asserts:
    - bundle-dir/index.md exists
    - bundle-dir/index.md body contains "<img src=\"fig.svg\""
    - bundle-dir/fig.svg exists
    - No warnings logged about "lacks :ID:" or "from-validate"
```

This is the regression backstop: index.md missing `<img>` ⇒ Bug 1 regressed; `fig.svg` not in bundle ⇒ Bug 2 regressed. Counted in the unit-test total below (so the suite goes 525 → ~539, not ~538).

### Manual verification (post-implementation)

`M-x a3-publish-deliberate RET ~/org/essays/example-multi.org RET` produces:

1. No errors in `*Messages*` (no "file-link target … lacks :ID:" or "cannot read file: … from-validate")
2. `content/essays/example-multi/index.md` body contains `<img src="diagram-1.svg" alt="diagram-1.svg" />` (or equivalent ox-hugo output)
3. `content/essays/example-multi/diagram-1.svg` exists with fresh mtime
4. `content/essays/example-multi/example-multi.pdf` re-rendered with figure embedded
5. `content/essays/example-multi/example-multi.docx` re-rendered with figure embedded

This is the original D.2 figure-ref verification that triggered the spec.

## Risks

- **Essays-aware resolution mis-classifies an edge case.** Mitigation: explicit `string-prefix-p essays-dir source-file` check; falls through to existing canonical-root logic if no per-essay asset is found. Unit test `asset-resolve-path/essays-fallback-to-canonical-root` covers the fall-through path explicitly.
- **`example-multi.org` `:ID:` change disturbs the fixture.** The site repo references `content/essays/example-multi/` paths but not the source `.org` directly; org-roam DB needs to re-index after the fixture change. Mitigation: add `org-roam-db-sync` to the pre-verification step; flag in CLAUDE.md memory if any site-side references break.
- **SVG move leaves a stale sibling.** `~/org/essays/diagram-1.svg` should be deleted after the move. Cosmetic, not a publish blocker — but worth doing as part of the fixture commit so future authors don't see the stale path and copy the convention.
- **The "from-validate" sentinel may still appear elsewhere.** Search for remaining references after the fix; remove from docstrings and test comments. Not blocking but loose-end cleanup.

## Success criteria

- All ~539 ert tests green (suite up by 14)
- Integration fixture `essays-figure-ref/` passes clean
- Manual D.2 figure-ref verification (5-step list above) succeeds
- No `from-validate` references remain in `assets.el` source (test fixtures may retain for now)
- D.2 follow-up #1 closed in `memory/project_d2_complete.md`

## Open questions / follow-ups

- Should garden / research / library also accept the essays-style `assets/<id>/` convention? Authors may want sibling-asset support across all B handlers. Out of scope here — spec separately if appetite shows up.
- Should `asset-resolve-path` learn a generic "per-source-page-dir" abstraction so each handler can declare its own asset namespace, rather than the essays-aware branch being a special case? Probably yes when a second handler needs it; YAGNI for now.
- The "from-validate" sentinel string survives in test scaffolds and unit-test comments; sweep separately once production callers are migrated.
