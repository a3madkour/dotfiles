# Publish-pipeline audit remediation roadmap

**Date:** 2026-07-05
**Target:** `emacs-configs/custom/lisp/a3madkour-publish*.el` — 25 source modules (~7,650 LOC) + `a3-pub.sh`.
**Method:** Single-pass six-lens adversarial audit (correctness, edge-cases, duplication, robustness, test-quality, hygiene), mirroring the site repo's 2026-07-03 six-lens audit. Read-only; no code changed during the audit.

Row IDs are `P<tier>.<n>`. Tiers: **P1** blocking, **P2** correctness (non-blocking, will bite on real content), **P3** duplication, **P4** test coverage, **P5** hygiene.

## Status — 2026-07-06

**P1 (both) + P2 (all 14) implemented via TDD, incl. the two follow-ups. Suite: 735/735 green** (was 692 at audit; +43 tests). Committed on `main` (`7b8b7b3` for P1+P2 core; P2.14 full-wiring is a follow-up commit).

- **P2.3** — fully wired (multi-pdf `:svg-source-file` seam + `multi.el` caller passing the original source).
- **P2.14 — DONE (full wiring).** Manifest now persists `last_modified` (`record-publish :last-modified`, canonical key order extended, `recorded-last-modified` reader). The cascade gained a `prior-recorded` slot + an ambient `--prior-last-modified` dynamic var; all 4 handlers bind the note's recorded value around `normalize` and pass the resolved date back to `record-publish`. Proven idempotent by an end-to-end garden test (uncommitted note republished with a bumped fs-mtime keeps its first date). Byte-stability of the manifest preserved (key emitted only when present).
- **P2.2 residual — assessed, deliberately NOT changed.** The manifest collision is fixed. The run-accumulator still keys id-less notes on id, BUT id-less notes are essays-only, essays register into `deliberate--handlers`, and `deliberate` scope skips Step A (the only accumulator/diff consumer for removals). Living-swept sections (garden/library/research) are all org-roam-indexed (have ids). So the collision is **unreachable in practice**. A correct fix needs an invasive real-id-vs-surrogate distinction across `diff-published-set`/`walk`/`finish-publish` (`record-publish id nil 'removed` would misfire on a URL-surrogate key) — real data-loss risk for zero practical benefit. Left as a documented limitation.

## P3 status — 2026-07-06

Behavior-preserving dedup, guarded by the 744-test suite (all green). Done:
- **P3.1 DONE** (`be2e4d1`) — extracted `a3madkour-publish-yaml.el` (site-root, write-if-different, date-re, render-value, render-frontmatter); handlers are thin wrappers passing the drift as explicit params (strict flag + key-hook + value-fn). ~180 dup LOC → one module.
- **P3.3 DONE** (`0f6d012`) — extracted `a3madkour-publish-multi-backend.el` (probe-tools, convert-svgs-fan, log-line, run-scaffold); PDF + Word backends thin over it; dead `multi-word--log-line` dropped; self-test added.
- **P3.7 DONE** (`c0de36e`) — shared `a3madkour-pub/warn`; research + 3 frontmatter sites delegate (library's slug variant kept distinct).

Deliberately NOT done (assessed marginal / risky / behavior-changing):
- **P3.2 (handler skeleton)** — the 4 handlers diverge substantially (essays multi-export dispatch, poetry audio + list return-value, research outputs); a shared envelope would need many hooks. High risk for a maintainability-only gain → flagged, not attempted.
- **P3.4 (library slug → canonical)** — NOT a pure refactor. `library--title-to-slug` (NFD, punctuation→hyphen: `L'Étranger`→`l-etranger`) and `slug/slugify` (NFKD, punctuation dropped: →`letranger`) are different algorithms. Unifying changes library slugs/URLs — a behavior decision for the user (best done before real library content ships), not a silent refactor.
- **P3.5 (lastmod call-site prep)** — the prep varies per normalizer (source `raw-alist` vs `out`, which keys to delete, emitted key `lastmod` vs `last_modified`); extractable only via a 4–5 param helper for ~30 LOC, in the P2.14-delicate normalizers. Marginal value / real risk → flagged.
- **P3.6 (relocate works-poetry normalizer into frontmatter.el)** — restores the "frontmatter = complete registry" invariant but adds a frontmatter→poetry runtime coupling + byte-compile warnings. Marginal → flagged.
- **P3.8 (shared test scaffolds)** — genuine dup (`--with-manifest` defined twice; ~13 `with-tmp-*` macros) but test-only churn across many files. Available as a focused follow-up (mirrors the site repo's R5.4); not done this round.

P5 remains open.

## P4 status — 2026-07-06

**P4.1–P4.4 DONE via TDD (test-only, +9 tests, 744→753 green).** The four flagged
gaps were all in orchestration wiring (the destructive primitives were already
well-covered):
- **P4.1** — `a3madkour-pub-living-test/idempotent-through-orchestrator`: drives
  the real `a3-publish-living` (walk → dispatch → barrier → finish-publish) twice
  over an unchanged garden note and asserts a **byte-identical** emitted bundle.
  Genuinely guards the P2.14 last_modified reuse: run 2's fs-mtime advances to a
  new date, yet the output keeps the first-recorded date.
- **P4.2** — living: `error-aggregation-{one-on-done-err,handler-throw}-rolls-up`
  + `all-ok-rolls-up-ok`; deliberate: `handler-throw-reports-err-and-logs`
  + `handler-on-done-err-propagates-status`. A partial-failure publish now
  provably rolls up to `'err` (not a silent `'ok`), and the throw path logs
  `handler-error`.
- **P4.3** — `finish-publish-removed-{nil,malformed}-url-does-not-converge`:
  documents that a `:removed` entry whose `current_url` won't parse is never
  swept (delete-bundle uncalled, manifest not advanced) and re-surfaces every run.
- **P4.4** — `recheck-skips-self-source-being-removed`: the self-source skip in
  `recheck-live-note-links` is exercised — a note being removed this run does not
  emit false-positive orphan WARNs about its removed siblings.

**P4.5 — assessed, deliberately NOT changed.** The flagged log-step glyph/elapsed
assertions and modeline-format tests verify real user-facing renderer output (not
tautologies); the `skeleton-loaded`/`featurep` smokes catch module-load failures.
Churn cost is only paid on rare glyph changes. Deleting passing tests would shrink
coverage for no correctness gain — same call as P3.8. Left in place.

P5 remains open.

## Two systemic findings

1. **The destructive orphan sweep has no safety rails.** It deletes `content/<section>/<slug>/` bundles based on a run accumulator that is not guaranteed complete. A partial-failure run, a cancelled run, an empty source walk, or a nil-slug note can each cause deletion of still-valid published bundles — up to and including the whole live content tree. This is a real data-loss path.
2. **"Copy instead of abstract," again.** A 5-function YAML/frontmatter-render stack is copied across 4–5 handlers, has already drifted, and is the direct cause of the one other blocking bug (P1.2, missing YAML escaping). Extracting it (P3.1) fixes the bug and removes the drift class in one move.

---

## P1 — Blocking

### P1.1 — Orphan sweep deletes live bundles off an incomplete accumulator
`a3-pub-async/finish-publish` (`async.el:381`) runs `a3madkour-pub/finish-publish` inside `unwind-protect` with **no status gate**; Step A (`unpublish.el:234-267`) treats the run accumulator as the authoritative new-live-set. Failure modes:
- **Empty new-set → total wipe.** If `walk-published-source-set` yields empty (misconfigured `org-notes-dir`, walk failure) while the manifest holds N live entries, all N bundles are deleted in one run. No floor, no ratio circuit-breaker.
- **Partial failure → targeted loss.** A handler erroring after export but before `record-publish` is absent from the accumulator; if other notes succeeded, the failed note is classified `:removed` and its still-valid bundle deleted.
- **Cancel.** `cancel-current-run` docstring claims "accumulator discarded" but never `clrhash`es it — a mid-run cancel drives the sweep off a partial set.
- **Silent slug-drop.** A published note whose title slugifies empty is omitted from new-set → reaped (`walk-published-source-set` `unpublish.el:145`).
- **cwd fallback / no bundle check.** `--unpublish-delete-bundle` (`unpublish.el:170`) resolves to `./section/slug` relative to cwd if both roots are nil, and never verifies the target is a Hugo bundle before `delete-directory ... t`.

**Fix:** gate Step A on `status = 'ok`; refuse the sweep when new-set is empty but the manifest is non-empty; add a removals-exceed-X% circuit-breaker (configurable); WARN-and-skip nil-slug notes instead of omitting; error (don't cwd-fallback) on nil content-root; verify bundle shape (`index.md` present, resolves under content-root) before delete; `clrhash` the accumulator (or skip the sweep) on cancel and fix the docstring.

### P1.2 — YAML string scalars emitted unescaped
`--render-yaml-value` in `garden.el:70`, `essays.el:173`, `poetry.el:83`, `research.el:166` do `(format "\"%s\"" v)` with no escaping. A title like `The "Real" Problem` → `title: "The "Real" Problem"` → invalid YAML → Hugo build fails → deploy blocked. Latent today only because fixtures are lorem-ipsum. Correct implementations already exist in `citations.el` (`--yaml-escape`) and `library.el` (single-quote + `''` doubling). Also affects the list branch (tags) and `research--render-output-row`.

**Fix:** land as part of P3.1 — route all scalar rendering through one shared escaping helper.

---

## P2 — Correctness (non-blocking; bites on real content)

- **P2.1** — All 4 handlers call `record-publish` with hard-coded `'live`, ignoring parsed `:state`; drafts recorded as live, draft→live flip emits no history event. (`garden.el:134`, `research.el:352`, `essays.el:273`, `poetry.el:192`)
- **P2.2** — ID-less essays (not org-roam-indexed) collide on the single `id: null` manifest key; second overwrites first. (`history.el` `find-note-by-id`)
- **P2.3** — PDF backend lists SVG figures against the relocated temp copy, so `--asset-resolve-path` (requires source under `essays-dir`) filters them all out → figures silently dropped / xelatex breaks. Word backend does it correctly. (`multi-pdf.el:117`)
- **P2.4** — xelatex→biber→xelatex chain ignores exit codes; success judged by `file-exists-p` on a PDF in a reused work dir → stale PDF makes a failed compile report `:ok`. (`multi-pdf.el:78`)
- **P2.5** — `citations` `notes_ref` auto-detect builds the probe URL from `file-name-base`, not the title-derived slug → silently omitted whenever filename ≠ slug. (`citations.el:209`)
- **P2.6** — `--file-top-level-id` regex is hex-only + column-anchored, disagreeing with the permissive `--extract-id`; valid links to timestamp-ID/indented-drawer notes degrade to `:inert`. (`rewrite.el:242`)
- **P2.7** — no-display file links `[[file:foo.org]]` render literal `file:foo.org` as anchor text instead of the resolved URL. (`rewrite.el:245`)
- **P2.8** — `has_*` scans (except `has_math`) run against un-fence-stripped body → an essay documenting `{{< cite >}}`/`{{< widget >}}` in a code block gets false `has_*` metadata. (`essays.el:44`)
- **P2.9** — `toc`/`draft` coercion `(if (memq v '(nil :nil)) nil t)` silently flips a string `"false"` to `t`. (`frontmatter.el:243`)
- **P2.10** — library `year`/`status` coercion emits `year: 0` / `status: null` on malformed input → downstream CI hard-fail instead of publish-time skip. (`library.el:190`)
- **P2.11** — `series_order` `(> coerced 0)` gate drops explicit `0`/negative; redundant second coercion block is dead. (`frontmatter.el:260`)
- **P2.12** — B-coupled `new-set` includes `'removed` accumulator entries (nil url) → misclassification under `'living` scope. (`unpublish.el:234`)
- **P2.13** — `multi-filter` interpolates block `title` into pandoc `:data-title "%s"` / latex `:options [%s]` unescaped → `"`/`]` corrupts D.2 export. (`multi-filter.el:110`)
- **P2.14** — history fs-mtime fallback yields "today" for uncommitted edits → `last_modified` churns every run, defeating idempotence. (`history.el:349`)

---

## P3 — Duplication / abstraction (non-blocking; subsumes P1.2)

- **P3.1** — YAML/frontmatter render stack (`--site-root`, `--write-if-different`, `--date-re`, `--render-yaml-value`, `--render-frontmatter`) copied 4–5×, already drifted (`tags: []` special-case in essays/poetry but not garden/research; `cl-every #'stringp` guard only in research). `poetry.el:56` carries a never-paid "collapse these" IOU. Extract `a3madkour-publish-yaml.el` (~125 LOC). **P1.2's fix lands here.**
- **P3.2** — Handler pipeline skeleton (resolve→bundle→rewrite→export→normalize→assets→write→record in a `condition-case` envelope) copied 4× (~60–80 LOC).
- **P3.3** — `multi-pdf.el`/`multi-word.el` parallel copies (`--probe-tools`, `--convert-svgs-fan`, `--log-line`, `/run` scaffold differ only in literals) (~70 LOC).
- **P3.4** — `library--title-to-slug` reimplements `slug.el` and has drifted (NFD vs NFKD) → title can slug differently as data-row key vs note URL. Delete + call canonical.
- **P3.5** — `last_modified` call-site prep (extract/truncate-to-10/delete/setf) copied 4–5× though the cascade fn is shared (~30 LOC).
- **P3.6** — `--normalize-works-poetry` lives in `poetry.el`, outside the `frontmatter.el` normalizer registry it claims to own.
- **P3.7** — `--warn` logging reimplemented 5× with divergent arg orders. One core `a3madkour-pub/warn`.
- **P3.8** — Test scaffold duplication (13 near-identical `with-tmp-*` macros; `--with-manifest` defined twice). Mirror the site repo's R5.4 `test_helpers.py` move.

---

## P4 — Test coverage gaps (non-blocking)

- **P4.1** — Living-publish **idempotency contract** (spec §11) stated in commentary but never tested (run twice, compare bytes).
- **P4.2** — Async + deliberate **error-aggregation branches** (`condition-case` → `'err` roll-up) never exercised; a partial-failure publish reporting `'ok` would pass CI.
- **P4.3** — `:removed` entry with nil/malformed `current_url` never converges — untested. (`unpublish.el:262`)
- **P4.4** — self-source skip in `--recheck-live-note-links` unexercised → could regress into false-positive orphan warnings.
- **P4.5** — async log-step tests coupled to glyphs/column widths (churn, low signal); ~12 `fboundp`/`featurep` tautology smoke tests inflate the count.

Note: the destructive paths themselves (delete-bundle trichotomy, self-heal, dry-run, unpublish-deliberate guards) *are* well-covered — gaps are in orchestration wiring.

---

## P5 — Hygiene / dead code (non-blocking)

- **P5.1** — `defcustom` naming drift (slash vs plain-hyphen); `citations--ref-notes-dir` is a public defcustom wearing the private `--` prefix.
- **P5.2** — `async.el` uses `a3-pub-async-*`/`a3-pub-mode-*` vs the tree-wide `a3madkour-pub-*`; command surface mixes 5 prefixes.
- **P5.3** — Dead code: `frontmatter--infer-flavor` (0 callers), `multi-word--log-line` (0 callers), `multi-pdf--log-line` (only its own test).
- **P5.4** — `multi.el` calls `essays--site-root` with no `(require 'a3madkour-publish-essays)` (works only via `a3-pub.sh` load order); reaches into two `--` private helpers cross-module.
- **P5.5** — `a3-pub.sh` exits 0 on a failed/partial living publish (no `condition-case` like deliberate); splices `$target_path`/`$SITE_DATA_DIR` raw into `--eval` literals (breakage/injection on `"`/`\`). Pass via `getenv` like `A3_PUB_BIB_PATH`.

---

## Counts

2 blocking, 14 correctness, 8 dedup, 5 test, 5 hygiene.

## Recommended order

1. **P1.1** (data-safety) — highest priority; potential live-content loss.
2. **P1.2 via P3.1** — extract `a3madkour-publish-yaml.el`, land escaping there.
3. **P2.x** — cheap real bugs, each contained.
4. **P3.2–P3.8 / P4 / P5** — same tech-debt tiering as the site repo's post-audit roadmap; optional/opportunistic.
