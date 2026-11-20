# a3 cleanup — pass 2 (shared org-reading module)

Date: 2026-11-19
Status: awaiting approval
Roadmap: `2026-11-19-a3-cleanup-pass1-bugs-design.md` (pass 2 of 4)

## Why

The kitchen code (recipes, ingredients, groceries) and the publish code each
carry their own copies of the same org-reading helpers. The copies have
started to disagree (quantity parsing), and a fix has to be made in several
places. One shared module removes the copies so a fix lands once.

## Goals

- One new module, `lisp/a3madkour-org.el`, that depends only on org and
  holds the helpers both sides need.
- Every duplicate listed below is deleted and its callers use the shared one.
- Published recipes accept the same quantities the grocery list does.
- Two pass 1 leftovers are closed.

## Non-goals

- No renames of existing symbols (pass 4). No performance work (pass 3): a
  recipe's ingredient table is still read by a text parser for groceries and
  a parse-tree parser for publishing.
- Link patterns that serve one purpose (`[[file:…]]` only, `[[id:…]]` only,
  anchored forms) stay where they are.

## Anti-goals

- Any change in how an existing file is parsed or what a publish writes,
  other than the two decided behaviour changes below.
- The kitchen modules gaining a dependency on a publish module.

## Approaches considered

- **A. New module with both a text-level and a parse-tree reader set
  (chosen).** Each copy is replaced by the shared version of the same kind,
  so parsing does not change.
- **B. One text-level parser for everything.** Simpler end state, but table
  cells holding links or markup would be read differently, changing what
  research and recipe pages publish.
- **C. No new module; grow existing ones.** Smallest diff, but kitchen code
  would depend on a publish module.

## The shared module

`a3madkour-org.el`, feature `a3madkour-org`, prefix `a3madkour-org-`
(final naming convention). Requires only `org`, `org-element`, `subr-x`,
`cl-lib`.

| New | Replaces |
|---|---|
| `a3madkour-org-keyword (key)` — first `#+KEY:` value in the buffer, trimmed; `""` when present but empty; nil when absent | `a3madkour-pub-keywords/extract`, `a3madkour-recipes--keyword` |
| `a3madkour-org-keyword-in-string (text key)` | `a3madkour-recipes--text-keyword` |
| `a3madkour-org-ast-keyword (ast name)` | `a3madkour-recipe-lint--kw`, `a3madkour-works-lint--kw` |
| `a3madkour-org-ast-table-under (headline)` and `a3madkour-org-ast-table-rows (table)` | the `--find-table-under` / `--table-rows` pairs in `a3madkour-publish-research.el` and `a3madkour-publish-recipes.el` |
| `a3madkour-org-table-rows-under (heading-p &optional buffer)` — cell lists of the first table under the first heading line satisfying HEADING-P, rules dropped | the scanner inside `a3madkour-ingredients--recipe-rows` (which stays as a thin caller supplying its Ingredients-heading test) |
| `a3madkour-org-synced-buffer (file what)` — the buffer visiting FILE with the newest text; reverts an unmodified stale buffer; refuses with a `user-error` naming WHAT when there are unsaved edits and a newer file | the guard inside `a3madkour-ingredients--editing` and `a3madkour-groceries--buffer` |
| `a3madkour-org-bracket-link-re` — group 1 path, group 2 optional description | `a3madkour-pub-rewrite--bracket-link-re`, `a3madkour-library--link-re`, and the two inline patterns in `a3madkour-publish-assets.el` |

Rules for the move:

- A private duplicate is deleted and its call sites call the shared function.
- `a3madkour-pub-keywords/extract` is called from six modules, so it stays as
  a one-line alias of `a3madkour-org-keyword` until the rename pass. The two
  named link-pattern constants stay as aliases the same way.
- Tests that exercised a deleted helper directly are moved to
  `a3madkour-org-test.el` and pointed at the shared function with the same
  assertions. Tests of surviving callers are not edited.
- `a3-pub.sh` and `run-tests.sh` find modules through the load path, so
  `(require 'a3madkour-org)` in each caller is enough.

## Decided behaviour changes

1. **Quantities (owner's choice: the full kitchen grammar).**
   `a3madkour-pub-recipes--coerce-qty` is deleted; publishing and the recipe
   linter use `a3madkour-units/parse-qty`. A published recipe now accepts
   `1 1/2`, `½`, `1½` and ranges (`2-3`, `2 to 3`), a range publishing as its
   upper end. Everything the old parser accepted must give the same number
   as before (`2`, `1.5`, `.5`, `1/2`); a test pins that. The linter's
   "not numeric-or-empty" rule only fires for text that is no quantity.
2. **Bracket-link pattern (my call).** The shared pattern is the stricter one
   already used by the link rewriter (no `[` or `]` inside the path or the
   description). The two asset-scan patterns allowed a `[` there. A link
   whose description contains a bracket is not valid org anyway.

## Pass 1 leftovers closed here

- Delete the unused `a3madkour-pub--asset-rewrite-source-link` and the three
  tests that only exercise it.
- Slug-change link migration (`a3madkour-pub--unpublish-bulk-rewrite-source-links`)
  walks every living file, not only the notes tree, and matches links by the
  asset they resolve to, so a recipe's `./../notes/assets/page/<old>/…`
  link is migrated too. The same-slug no-op from pass 1 stays.
- `a3madkour-groceries--strip-note` is called once per pass in its two
  callers, and its docstring says "parenthesised".

## Constraints

- Same test rules as pass 1: ERT, temp directories, no real org-roam
  database, `~/org` or site checkout. The 17 `sections.json` failures are the
  baseline; no new ones.
- The migration change rewrites the author's source files; its tests run in
  temp directories only.
- One commit per helper family, work done in a worktree, a review after each.

## Done when

- No definition listed in the "Replaces" column remains, except the three
  aliases.
- `grep` finds one definition each of the keyword regexp, the parse-tree
  table walker, the sync guard and the any-bracket-link pattern.
- The suite passes at the baseline.

## Left to the builder

Internal helper names inside `a3madkour-org.el`, test fixture layout, and
the order callers are moved in.
