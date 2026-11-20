# a3 cleanup — roadmap, and pass 1 (the seven bugs)

Date: 2026-11-19
Status: awaiting approval

## Why

The `a3-*` / `a3madkour-*` code in `custom/lisp/` (about 33,700 lines, 45
modules plus tests and `a3-pub.sh`) feels sloppy: a code review found seven
real bugs, the same helpers written several times over, a publish run that
re-reads the same files many times, and names that follow three different
styles. The goal is code that is correct, has one copy of each helper, is
split along clear lines, and is named by one rule.

## Roadmap (decided)

Four passes, in this order. Each gets its own short design and plan. The
test suite (`lisp/run-tests.sh`) is green between passes.

1. **Bugs** — this document.
2. **Shared org-reading module** — one copy of the keyword reader, file
   drawer reader, table-under-heading parser, link regexp, quantity parser
   and the revert-if-changed-on-disk guard; kitchen and publish code both
   use it.
3. **Performance and script** — read the URL-history manifest once per
   publish run and write it once; read each source file once per handler;
   one `emacs --batch` bootstrap in `a3-pub.sh` instead of five.
4. **Rename** — one mechanical commit, no behaviour change, driven by a
   script and an old-name → new-name table. Hard cutover, no aliases.

### Approaches considered for the order

- **A. Four passes, rename last (chosen).** Behaviour changes land in small
  reviewable commits; the rename is a single diff that changes nothing but
  names. Cost: the bug-fix commits still show old names.
- **B. Rename first.** Later diffs read in final names, but the rename lands
  on code with a known hang, and a test that breaks afterwards could be the
  rename or an old bug.
- **C. Module by module.** Does not fit: names cross module boundaries, so
  the tree would stay half-converted for the whole project.

### Naming convention (decided: full convention)

- `a3-…` — commands run by hand (`M-x`, keybindings).
- `a3madkour-<module>-…` — public functions and variables.
- `a3madkour-<module>--…` — private ones.
- No `/` separator anywhere in these files.
- File name, `provide` feature and symbol prefix agree. The publish files
  become `a3madkour-pub-*.el` to match their symbols.
- One spelling per module (`recipes`, not `recipe` in some places).

New symbols added in passes 1–3 use this convention from the start.

Scope call (mine, not yet confirmed): the 156 `a3madkour/…` helpers that
`config.org` itself defines are left alone; `config.org` is only edited
where it refers to a renamed name.

Precondition for pass 4: the uncommitted edits in `config.org` and
`a3madkour-agents.el` are committed or stashed first.

## Pass 1: the seven bugs

### Goals

Each bug below is fixed, with a test that fails before the fix and passes
after. One commit per bug.

### Non-goals

- No renames of existing symbols, no deduplication, no performance work.
- The five smaller review items (orphan re-check noise, research date
  format, swallowed handler error message, macOS-only keychain lookup,
  import heuristics for "1-inch piece ginger") are not in this pass.

### Anti-goals

- A fix that changes what a correct publish writes to the site.
- A fix that moves or rewrites a source file in a case where it did not
  before.

### The fixes

1. **Publish hangs when a note changes section but keeps its slug**
   (`a3madkour-publish-unpublish.el`, the bulk source-link rewrite).
   - The caller skips the asset-directory rename and the link rewrite when
     old slug equals new slug.
   - The rewrite itself becomes a single left-to-right pass per pattern
     (literal replacement, counting matches), so it terminates for any
     input.

2. **A second publish in one Emacs session uses the previous run's
   metadata** (`a3-publish-living`, `a3-publish-deliberate`).
   - Both commands reset the metadata cache before they collect files or
     resolve a section.
   - The living dispatcher and the deliberate command refuse a file whose
     metadata is nil (reported as an error for that file), so no handler
     can write a `nil` slug. Guarded centrally, not in each handler (my
     call).

3. **Recipes marked for the website are never published.**
   - A new path variable, `a3madkour-pub-recipes-dir`, set in
     `publish-paths.el` to `~/org/recipes/`.
   - The `recipes` registry entry names it as its folder.
   - The living walk, and the "what is currently published" walk used by
     `finish-publish`, `--check-orphans` and `--sync-citations`, cover the
     notes directory plus every living section's folder.
   - Consequence to know about: `~/org/recipes/toast.org` already has
     `#+HUGO_PUBLISH: t`, so it goes to the site on the next living publish.

4. **Asset auto-remediation moves the file but leaves the source link
   pointing at the old place** (`a3madkour-publish-assets.el`).
   - The link text as the author wrote it is carried through to the source
     rewrite, alongside the normalised path.
   - The destination slug comes from the source file's own metadata, so it
     works for essays and poems that are not in org-roam.
   - The file is moved only when the slug is known and the source rewrite
     will match; otherwise the link is emitted inert with a warning, as for
     other unresolved assets.

5. **Recipe import yields no steps for a plain array of strings**
   (`a3madkour-recipe-import--steps`).
   - The "one object" test becomes: the first element is a cons whose car
     is a symbol.
   - Tests cover all four shapes: string, array of strings, one object,
     array of objects.

6. **`file:` links with a `::search` suffix publish as broken links**
   (`a3madkour-publish-rewrite.el`).
   - The `::…` part is split off before the link is classified.
   - An asset link (`file:paper.pdf::5`) resolves as the asset.
   - A note link (`file:other.org::*Setup`) links to that note's page; the
     heading part is dropped with a warning (my call: heading anchors are a
     feature, not part of this fix).

7. **Grocery list loses ticks and duplicates lines when a recipe title
   contains parentheses** (`a3madkour-groceries.el`).
   - One private helper strips the last top-level parenthesised note, by
     scanning for balanced parentheses from the right.
   - `--resolve` and `--recipe-item-p` both use it.
   - Test with "Instant Pot Curried Lentil Soup (Indian-Inspired)": two
     refreshes produce the same list, and a tick survives.

### Constraints

- Tests are ERT, one `*-test.el` per module, run with `lisp/run-tests.sh`.
  They must not touch the real org-roam database, `~/org`, or the site.
- Fix 4 involves `git mv` of real files; its tests run in a temporary git
  repository.

### Done when

- Seven commits, each with its test.
- `lisp/run-tests.sh` passes in full.
- A living publish dry run (`a3-pub.sh` in its check mode) completes and
  lists `toast.org` among the recipes.

### Left to the builder

Exact helper names (within the convention above), test fixture layout, and
the wording of warnings.
