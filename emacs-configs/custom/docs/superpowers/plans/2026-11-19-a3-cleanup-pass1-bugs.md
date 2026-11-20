# a3 Cleanup Pass 1 (Seven Bugs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the seven bugs the code review found in `custom/lisp/`, one commit each, each with a test that fails first.

**Architecture:** Seven independent fixes in existing modules. No existing symbol is renamed and nothing is deduplicated; that is passes 2–4. Each task touches one module and its `*-test.el`, except Task 3, which also touches the registry, the paths module and `config.org`.

**Tech Stack:** Emacs Lisp, ERT, `custom/lisp/run-tests.sh` (whole suite, about 10 seconds).

**Spec:** `custom/docs/superpowers/specs/2026-11-19-a3-cleanup-pass1-bugs-design.md`

## Global Constraints

- All paths below are relative to `/home/a3madkour/dotfiles/emacs-configs/custom/`. The git root is `/home/a3madkour/dotfiles/`.
- No renames of existing symbols, no deduplication, no performance work.
- New symbols follow the final convention: `a3madkour-<module>-…` public, `a3madkour-<module>--…` private, no `/`. New tests are named `<module-prefix>-test-<what>` with no `/`.
- A fix must not change what a correct publish writes to the site, and must not move or rewrite a source file in a case where it did not before.
- Tests must not touch the real org-roam database, `~/org`, or the site checkout. Use temp directories and `cl-letf` stubs as the neighbouring tests do.
- One commit per task. Stage only the files the task names. End each message with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.
- **Baseline:** before any change the suite reports `Ran 1240 tests, 1223 results as expected, 17 unexpected`. All 17 fail with `a3madkour-sections: contract not found at …/a3madkour.github.io/data/sections.json` (the site checkout on this machine lacks that file). "Suite passes" in this plan means: the unexpected count is still 17 and every one is that error (or 0 if the file has been restored).
- Run the suite with: `cd lisp && ./run-tests.sh 2>&1 | grep -E "<test-name-regexp>|^Ran |unexpected"`. The runner takes no selector; always run it whole.

## Review Focus

Each line is pinned by a test in the task named.

1. A note changes section and slug at once: the asset directory and source links must still migrate (Task 1).
2. A source link text contains the old path twice on one line: both are rewritten, once each (Task 1).
3. A recipe file sits in the recipes folder with no `#+HUGO_PUBLISH:`: it is not collected and nothing is written (Task 3).
4. Two links in one note point at the same stray asset in different spellings (`file:../img/x.png` and `../img/x.png`): both are rewritten by one move (Task 4).
5. A URL that contains `::` (`https://example.com/a::b`): it passes through untouched (Task 6).

---

### Task 0: Preconditions

**Files:** none.

- [ ] **Step 1: Check `config.org` has no pending edits**

Run: `git -C /home/a3madkour/dotfiles diff --quiet -- emacs-configs/custom/config.org; echo $?`
Expected: `0`. If `1`, stop: Task 3 commits `config.org`, and the owner's own pending edits must be committed or stashed by them first.

- [ ] **Step 2: Confirm the baseline**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |contract not found" | sort | uniq -c`
Expected: one `Ran 1240 tests, 1223 results as expected, 17 unexpected` line, and every failure message is `contract not found`. If the numbers differ, record the new baseline and use it for the rest of the plan.

---

### Task 1: Publish hangs when a note keeps its slug but changes section

**Files:**
- Modify: `lisp/a3madkour-publish-unpublish.el` (`a3madkour-pub--unpublish-bulk-rewrite-source-links`, about line 497; its call site in `a3madkour-pub/finish-publish`, about line 416)
- Test: `lisp/a3madkour-publish-unpublish-test.el`

**Interfaces:**
- Produces: nothing new. `(a3madkour-pub--unpublish-bulk-rewrite-source-links OLD-SLUG NEW-SLUG &optional ORG-NOTES-DIR)` keeps its signature and its `(:modified ((FILE . COUNT) …) :warnings (…))` return.

- [ ] **Step 1: Write the failing tests**

Follow the fixture style of the existing bulk-rewrite tests in the test file (temp notes dir, `a3madkour-pub-canonical-asset-root` bound to a temp dir).

```elisp
(ert-deftest a3madkour-pub-unpublish-test-bulk-rewrite-same-slug-terminates ()
  ;; note.org contains "[[./assets/page/foo/x.png]]"
  (with-timeout (5 (ert-fail "bulk rewrite did not terminate"))
    (let ((r (a3madkour-pub--unpublish-bulk-rewrite-source-links "foo" "foo" dir)))
      (should (null (plist-get r :modified)))
      (should (equal before (file-contents note))))))

(ert-deftest a3madkour-pub-unpublish-test-bulk-rewrite-counts-each-match-once ()
  ;; note.org: "[[./assets/page/foo/a.png]] [[./assets/page/foo/b.png]]"
  (let ((r (a3madkour-pub--unpublish-bulk-rewrite-source-links "foo" "foo-bar" dir)))
    (should (equal (cdar (plist-get r :modified)) 2))
    (should (equal (file-contents note)
                   "[[./assets/page/foo-bar/a.png]] [[./assets/page/foo-bar/b.png]]"))))

(ert-deftest a3madkour-pub-unpublish-test-finish-publish-same-slug-skips-migration ()
  ;; Manifest has id X at /garden/foo/; new set has X at /research/themes/foo/.
  ;; Stub rename-asset-dir and bulk-rewrite to record calls.
  (should (null rename-calls))
  (should (null rewrite-calls))
  ;; the old bundle content/garden/foo/ is still deleted
  (should-not (file-exists-p old-bundle)))

(ert-deftest a3madkour-pub-unpublish-test-finish-publish-section-and-slug-change-migrates ()
  ;; X moves /garden/foo/ -> /research/themes/foo-bar/
  (should (equal rename-calls '(("foo" "foo-bar"))))
  (should (equal rewrite-calls '(("foo" "foo-bar")))))
```

The `counts-each-match-once` and `section-and-slug-change-migrates` tests pin behaviour that already works; they pass before the fix and must still pass after it.

- [ ] **Step 2: Run to verify they fail**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "unpublish-test-(bulk|finish-publish-s)|^Ran "`
Expected: the two same-slug tests FAIL (timeout, and recorded migration calls); `Ran` line shows 19 unexpected.

- [ ] **Step 3: Fix the rewrite**

In `a3madkour-pub--unpublish-bulk-rewrite-source-links`: return `(:modified nil :warnings nil)` at once when `(equal old-slug new-slug)`. Replace the `while string-match` loop with one left-to-right pass per pattern that never rescans replaced text: `replace-regexp-in-string` with a function replacement that increments `count` and returns the literal new text, `FIXEDCASE` and `LITERAL` both `t`.

- [ ] **Step 4: Fix the call site**

In `a3madkour-pub/finish-publish`, wrap only the `--unpublish-rename-asset-dir` and `--unpublish-bulk-rewrite-source-links` calls in `(unless (equal old-slug new-slug) …)`. The orphan-bundle deletion and the `slug-shifted-result` push below them stay unconditional.

- [ ] **Step 5: Run the suite**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |unexpected"`
Expected: 17 unexpected.

- [ ] **Step 6: Commit**

```bash
git add emacs-configs/custom/lisp/a3madkour-publish-unpublish.el emacs-configs/custom/lisp/a3madkour-publish-unpublish-test.el
git commit -m "fix(publish): stop the hang when a note changes section but keeps its slug"
```

---

### Task 2: A second publish in one session uses stale metadata

**Files:**
- Modify: `lisp/a3madkour-publish-living.el` (`a3-publish-living`, `a3madkour-pub-living--dispatch`)
- Modify: `lisp/a3madkour-publish-deliberate.el` (`a3-publish-deliberate`)
- Test: `lisp/a3madkour-publish-living-test.el`, `lisp/a3madkour-publish-deliberate-test.el`

**Interfaces:**
- Consumes: `(a3madkour-pub--reset-metadata-cache)` and `(a3madkour-pub/note-metadata FILE)` from `a3madkour-publish.el`. `note-metadata` returns nil for a file not marked `#+HUGO_PUBLISH: t`.
- Produces: `a3madkour-pub-living--dispatch` reports `err` and logs a step named `"unpublished"` for a readable file whose metadata is nil.

- [ ] **Step 1: Write the failing tests**

Use the helpers already in the living test file (`a3-pub-living-test--capture-finish-status`, the `--theme` writer) and stub handlers with `cl-letf`.

```elisp
(ert-deftest a3madkour-pub-living-test-unmarked-note-is-not-collected-on-second-run ()
  ;; garden note marked HUGO_PUBLISH t; warm the cache:
  (should (a3madkour-pub/note-metadata note))
  ;; rewrite the file without #+HUGO_PUBLISH, then:
  (should-not (member note (mapcar #'cadr (progn (a3-publish-living) dispatched)))))

(ert-deftest a3madkour-pub-living-test-dispatch-refuses-nil-metadata ()
  ;; triple ("garden" FILE stub-handler), FILE readable and unmarked
  (a3madkour-pub-living--dispatch triple run (lambda (s) (setq status s)))
  (should (eq status 'err))
  (should-not handler-called)
  (should (member "unpublished" logged-step-names)))

(ert-deftest a3madkour-pub-deliberate-test-second-run-sees-fixed-keywords ()
  ;; essay with no HUGO_SECTION; first call signals "no handler registered":
  (should-error (a3-publish-deliberate essay))
  ;; add "#+HUGO_SECTION: essays" and "#+HUGO_PUBLISH: t" to the file, then:
  (a3-publish-deliberate essay)
  (should handler-called))
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "second-run|refuses-nil-metadata|^Ran "`
Expected: the three new tests FAIL.

- [ ] **Step 3: Reset the cache first in both commands**

`a3-publish-living`: call `(a3madkour-pub--reset-metadata-cache)` before `--collect-triples`. `a3-publish-deliberate`: call it before `a3madkour-pub/note-section`.

- [ ] **Step 4: Guard the dispatcher**

In `a3madkour-pub-living--dispatch`, add a `cond` branch after the handler-missing branch and before the contract-gap branch: when `(and (file-readable-p file) (not (a3madkour-pub/note-metadata file)))`, message, log step `"unpublished"` with `:err` and a snippet `"<file>: no longer marked to publish"`, and report `err`. An unreadable file still falls through to its handler, as the `contract-gap` docstring promises.

- [ ] **Step 5: Run the suite**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |unexpected"`
Expected: 17 unexpected. If an existing test fails because it dispatched an unmarked file and expected the handler to run, stop and report it rather than editing that test.

- [ ] **Step 6: Commit**

```bash
git add emacs-configs/custom/lisp/a3madkour-publish-living.el emacs-configs/custom/lisp/a3madkour-publish-deliberate.el emacs-configs/custom/lisp/a3madkour-publish-living-test.el emacs-configs/custom/lisp/a3madkour-publish-deliberate-test.el
git commit -m "fix(publish): reset the metadata cache before collecting, refuse unmarked notes"
```

---

### Task 3: Recipes marked for the website are never published

**Files:**
- Modify: `lisp/a3madkour-publish-paths.el` (new variable, added to `a3madkour-pub/path-variables`)
- Modify: `lisp/a3madkour-publish-registry.el` (`recipes` entry, new function)
- Modify: `lisp/a3madkour-publish-living.el` (`a3madkour-pub-living--collect-triples`)
- Modify: `lisp/a3madkour-publish-unpublish.el` (`a3madkour-pub/walk-published-source-set`)
- Modify: `config.org` ("Publishing paths" block, about line 5583; the interactive override beside `a3madkour-ingredients/file`, about line 5556), then regenerate `publish-paths.el`
- Test: `lisp/a3madkour-publish-registry-test.el`, `lisp/a3madkour-publish-living-test.el`, `lisp/a3madkour-publish-unpublish-test.el`, `lisp/a3madkour-publish-paths-test.el`

**Interfaces:**
- Produces:
  - `a3madkour-pub-recipes-dir` — variable, default nil, the folder recipe files live in. Like `a3madkour-ingredients/file` it may stay nil: living publish then walks no recipes folder.
  - `(a3madkour-pub-registry-living-folders)` → list of absolute directory names, no duplicates, registry order. `a3madkour-pub/org-notes-dir` is resolved with `a3madkour-pub/path` (signals when unset). Any other living section's `:folder` variable is included when it is a non-empty string and skipped when nil.
  - `(a3madkour-pub-registry-living-files)` → every `.org` file under those folders, recursive, no duplicates.

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest a3madkour-pub-registry-test-living-folders-include-recipes ()
  (let ((a3madkour-pub/org-notes-dir notes) (a3madkour-pub-recipes-dir recipes))
    (should (equal (a3madkour-pub-registry-living-folders)
                   (list (file-name-as-directory notes) (file-name-as-directory recipes))))))

(ert-deftest a3madkour-pub-registry-test-living-folders-skip-unset-recipes ()
  (let ((a3madkour-pub/org-notes-dir notes) (a3madkour-pub-recipes-dir nil))
    (should (equal (a3madkour-pub-registry-living-folders)
                   (list (file-name-as-directory notes))))))

(ert-deftest a3madkour-pub-registry-test-recipes-folder-is-registered ()
  (should (eq (a3madkour-pub-registry/get "recipes" :folder) 'a3madkour-pub-recipes-dir)))

(ert-deftest a3madkour-pub-living-test-collects-a-marked-recipe ()
  ;; recipes/toast.org: #+HUGO_SECTION: recipes, #+HUGO_PUBLISH: t
  ;; recipes/plain.org: #+HUGO_SECTION: recipes, no HUGO_PUBLISH
  ;; recipes/ingredients.org: no keywords
  (should (equal (a3madkour-pub-living--collect-triples)
                 `(("recipes" ,toast a3madkour-pub-recipes/publish-recipe-file)))))

(ert-deftest a3madkour-pub-unpublish-test-walk-includes-recipes-folder ()
  ;; same toast.org, :ID: R1, title "Toast"
  (should (equal (gethash "R1" (a3madkour-pub/walk-published-source-set))
                 '("/recipes/toast/" . live))))
```

In `a3madkour-publish-paths-test.el`, add `a3madkour-pub-recipes-dir` wherever the existing tests enumerate the expected members of `a3madkour-pub/path-variables`.

- [ ] **Step 2: Run to verify they fail**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "recipes|living-folders|^Ran "`
Expected: the new tests FAIL (void function / void variable).

- [ ] **Step 3: Add the variable and the registry folder**

Declare `a3madkour-pub-recipes-dir` (nil) where the other folder variables are declared, add it to `a3madkour-pub/path-variables` with a comment that it may stay nil, and add `:folder a3madkour-pub-recipes-dir` to the `"recipes"` registry entry.

- [ ] **Step 4: Implement `a3madkour-pub-registry-living-folders` and `a3madkour-pub-registry-living-files` in `a3madkour-publish-registry.el`**

Add `(require 'a3madkour-publish-paths)`.

- [ ] **Step 5: Use them in both walks**

`a3madkour-pub-living--collect-triples` and `a3madkour-pub/walk-published-source-set` iterate `(a3madkour-pub-registry-living-files)` instead of walking `a3madkour-pub/org-notes-dir`. Update both docstrings.

- [ ] **Step 6: Set the folder in `config.org`**

In the "Publishing paths" block add `a3madkour-pub-recipes-dir (expand-file-name "~/org/recipes/")`. Beside the interactive `(setq a3madkour-ingredients/file (a3madkour/org-file "recipes/ingredients.org"))` add `(setq a3madkour-pub-recipes-dir (a3madkour/org-file "recipes/"))`. Regenerate `publish-paths.el` by tangling that block; it is untracked, so it is not staged.

- [ ] **Step 7: Run the suite**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |unexpected"`
Expected: 17 unexpected.

- [ ] **Step 8: Commit**

```bash
git add emacs-configs/custom/config.org emacs-configs/custom/lisp/a3madkour-publish-paths.el emacs-configs/custom/lisp/a3madkour-publish-registry.el emacs-configs/custom/lisp/a3madkour-publish-living.el emacs-configs/custom/lisp/a3madkour-publish-unpublish.el emacs-configs/custom/lisp/a3madkour-publish-paths-test.el emacs-configs/custom/lisp/a3madkour-publish-registry-test.el emacs-configs/custom/lisp/a3madkour-publish-living-test.el emacs-configs/custom/lisp/a3madkour-publish-unpublish-test.el
git commit -m "fix(publish): walk the recipes folder so marked recipes publish"
```

---

### Task 4: Asset auto-remediation leaves the source link behind

**Files:**
- Modify: `lisp/a3madkour-publish-assets.el` (`a3madkour-pub/rewrite-asset-link`, about line 355; `a3madkour-pub--asset-rewrite-source-link`, about line 338)
- Test: `lisp/a3madkour-publish-assets-test.el`

**Interfaces:**
- Consumes: `(a3madkour-pub--asset-normalize-link-path PATH ORG-FILE)` → absolute path; `(a3madkour-pub/note-slug FILE-OR-ID)`.
- Produces: `(a3madkour-pub--asset-rewrite-source-links-to ORG-FILE ABS-TARGET NEW-PATH &optional COUNT-ONLY)` → integer. It visits every bracket link in ORG-FILE, strips a leading `file:` from the link path, normalises it with `--asset-normalize-link-path`, and where the result equals ABS-TARGET replaces the link's path part with NEW-PATH (description left as written). Returns how many links matched. With COUNT-ONLY non-nil it writes nothing.

This replaces the spec's "carry the author's link text through" with matching by resolved target. The outcome is the same and it also covers one asset linked in two spellings. `a3madkour-pub--asset-rewrite-source-link` is deleted if nothing else calls it.

- [ ] **Step 1: Write the failing tests**

Model them on `a3madkour-pub-assets-test/remediate-moves-and-rewrites-link` (line 459), which runs in a temp git repo.

```elisp
(ert-deftest a3madkour-pub-assets-test-remediate-rewrites-relative-file-link ()
  ;; note.org (slug "note") contains "[[file:../img/x.png]]"; called as
  ;; asset-validate-and-copy does: PATH is the absolute form.
  (should (file-exists-p (expand-file-name "page/note/x.png" asset-root)))
  (should (string-match-p (regexp-quote "[[./assets/page/note/x.png]]") (file-contents note)))
  (should-not (string-match-p "\\.\\./img/x\\.png" (file-contents note))))

(ert-deftest a3madkour-pub-assets-test-remediate-rewrites-both-spellings ()
  ;; "[[file:../img/x.png]] and [[../img/x.png][the figure]]"
  (should (equal (file-contents note)
                 "[[./assets/page/note/x.png]] and [[./assets/page/note/x.png][the figure]]")))

(ert-deftest a3madkour-pub-assets-test-remediate-uses-source-file-slug ()
  ;; essay outside org-roam: --id-to-file stubbed to return nil,
  ;; SOURCE-FILE passed, essay slug "my-essay"
  (should (file-exists-p (expand-file-name "page/my-essay/x.png" asset-root)))
  (should-not (file-exists-p (expand-file-name "page/nil" asset-root))))

(ert-deftest a3madkour-pub-assets-test-remediate-refuses-without-slug ()
  ;; note-slug stubbed to return nil
  (should (plist-get result :inert))
  (should (file-exists-p stray))                       ; not moved
  (should (string-match-p "no slug" (car (plist-get result :warnings)))))

(ert-deftest a3madkour-pub-assets-test-remediate-refuses-when-no-link-matches ()
  ;; SOURCE-FILE does not link the asset at all
  (should (plist-get result :inert))
  (should (file-exists-p stray))
  (should (equal before (file-contents note))))
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "assets-test-remediate|^Ran "`
Expected: the five new tests FAIL.

- [ ] **Step 3: Implement `a3madkour-pub--asset-rewrite-source-links-to`**

- [ ] **Step 4: Rework the out-of-root branch of `a3madkour-pub/rewrite-asset-link`**

- `source-slug` becomes `(a3madkour-pub/note-slug (or source-file source-note-id))`.
- In the auto-remediate branch, when not `dry-run`: if `source-slug` is nil, return `:inert` with warning `"cannot place asset %s: no slug for %s"`; if `source-file` is given and `(a3madkour-pub--asset-rewrite-source-links-to source-file abs dest-rel t)` is 0, return `:inert` with warning `"cannot move asset %s: no link to it found in %s"`. Neither case moves the file.
- Otherwise move, then call `--asset-rewrite-source-links-to` for real. The two literal `--asset-rewrite-source-link` calls go away.
- The `dry-run` branch is unchanged.

- [ ] **Step 5: Run the suite**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |unexpected"`
Expected: 17 unexpected. The existing `remediate-moves-and-rewrites-link` test must still pass unedited.

- [ ] **Step 6: Commit**

```bash
git add emacs-configs/custom/lisp/a3madkour-publish-assets.el emacs-configs/custom/lisp/a3madkour-publish-assets-test.el
git commit -m "fix(publish): rewrite the source link when an asset is auto-moved"
```

---

### Task 5: Recipe import drops steps given as plain strings

**Files:**
- Modify: `lisp/a3madkour-recipe-import.el` (`a3madkour-recipe-import--steps`, about line 189)
- Test: `lisp/a3madkour-recipe-import-test.el`

- [ ] **Step 1: Write the failing test**

```elisp
(ert-deftest a3madkour-recipe-import-test-steps-all-shapes ()
  (should (equal (a3madkour-recipe-import--steps "Chop.\nFry.") '("Chop." "Fry.")))
  (should (equal (a3madkour-recipe-import--steps '("Chop." "Fry.")) '("Chop." "Fry.")))
  (should (equal (a3madkour-recipe-import--steps '((@type . "HowToStep") (text . "Chop.")))
                 '("Chop.")))
  (should (equal (a3madkour-recipe-import--steps
                  '(((@type . "HowToStep") (text . "Chop."))
                    ((@type . "HowToSection")
                     (itemListElement . (((text . "Fry.")) ((text . "Serve.")))))))
                 '("Chop." "Fry." "Serve."))))
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "steps-all-shapes|^Ran "`
Expected: FAIL on the second `should` (got nil).

- [ ] **Step 3: Fix the object test**

The "one object" branch's condition becomes `(and (consp (car-safe instructions)) (symbolp (caar instructions)))`.

- [ ] **Step 4: Run the suite**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |unexpected"`
Expected: 17 unexpected.

- [ ] **Step 5: Commit**

```bash
git add emacs-configs/custom/lisp/a3madkour-recipe-import.el emacs-configs/custom/lisp/a3madkour-recipe-import-test.el
git commit -m "fix(kitchen): import recipe steps given as a plain list of strings"
```

---

### Task 6: `file:` links with a `::search` suffix publish as broken links

**Files:**
- Modify: `lisp/a3madkour-publish-rewrite.el` (`a3madkour-pub/rewrite-link`, about line 316; new helper)
- Modify: `lisp/a3madkour-publish-assets.el` (`a3madkour-pub--extract-asset-refs`, about line 200)
- Test: `lisp/a3madkour-publish-rewrite-test.el`, `lisp/a3madkour-publish-assets-test.el`

**Interfaces:**
- Produces: `(a3madkour-pub-rewrite--split-search PATH)` → `(PATH . SEARCH)`. When PATH starts with `file:`, `./`, `../`, `/` or `~` and contains `::`, PATH is the part before the first `::` and SEARCH the part after; otherwise `(PATH . nil)`.

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest a3madkour-pub-rewrite-test-split-search ()
  (should (equal (a3madkour-pub-rewrite--split-search "file:other.org::*Setup")
                 '("file:other.org" . "*Setup")))
  (should (equal (a3madkour-pub-rewrite--split-search "./paper.pdf::5") '("./paper.pdf" . "5")))
  (should (equal (a3madkour-pub-rewrite--split-search "file:other.org") '("file:other.org" . nil)))
  (should (equal (a3madkour-pub-rewrite--split-search "https://example.com/a::b")
                 '("https://example.com/a::b" . nil)))
  (should (equal (a3madkour-pub-rewrite--split-search "id:abc::x") '("id:abc::x" . nil))))

(ert-deftest a3madkour-pub-rewrite-test-file-link-with-heading-links-the-note ()
  ;; other.org is published at /garden/other/; fixture as the existing file-link tests
  (let ((r (a3madkour-pub/rewrite-link "[[file:other.org::*Setup][see setup]]" src-id src-file)))
    (should (string-match-p "href=\"/garden/other/\"" (plist-get r :html)))
    (should-not (string-match-p "::" (plist-get r :html)))
    (should (cl-some (lambda (w) (string-match-p "heading target dropped.*\\*Setup" w))
                     (plist-get r :warnings)))))

(ert-deftest a3madkour-pub-rewrite-test-asset-link-with-search-resolves-the-asset ()
  ;; ./assets/page/src/paper.pdf exists
  (let ((r (a3madkour-pub/rewrite-link "[[file:./assets/page/src/paper.pdf::5]]" src-id src-file)))
    (should (plist-get r :html))
    (should-not (string-match-p "::" (plist-get r :html)))))

(ert-deftest a3madkour-pub-rewrite-test-url-with-double-colon-passes-through ()
  (let ((r (a3madkour-pub/rewrite-link "[[https://example.com/a::b][x]]" src-id src-file)))
    (should (string-match-p (regexp-quote "https://example.com/a::b") (plist-get r :html)))))

;; in a3madkour-publish-assets-test.el
(ert-deftest a3madkour-pub-assets-test-extract-refs-drops-search-suffix ()
  ;; note contains "[[file:./assets/page/n/paper.pdf::5]]"
  (should (equal (mapcar #'car (a3madkour-pub--extract-asset-refs note))
                 '("./assets/page/n/paper.pdf"))))
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "split-search|with-heading|with-search|double-colon|drops-search|^Ran "`
Expected: all but the URL pass-through test FAIL.

- [ ] **Step 3: Implement `a3madkour-pub-rewrite--split-search`**

- [ ] **Step 4: Use it in `a3madkour-pub/rewrite-link`**

Split `raw-path` first; classify and dispatch on the path part exactly as today. The existing "text equals raw path" check compares against the unsplit raw path, so `[[file:x.png::1]]` still gets its filename as display text. When SEARCH is non-nil and the link went down the `file` (note) branch, append the warning `"heading target dropped: ::<SEARCH> (<path>)"` to the result's `:warnings`. Asset links drop SEARCH with no warning.

- [ ] **Step 5: Use it in `a3madkour-pub--extract-asset-refs`**

Split each raw path before the `file:` strip and the asset-shape check. `a3madkour-publish-assets.el` already loads after or alongside the rewrite module; if it does not `require` it, add `(declare-function a3madkour-pub-rewrite--split-search "a3madkour-publish-rewrite")` and the `require` that the load order allows without a cycle (if a cycle results, define the helper in `a3madkour-publish-assets.el` instead and have the rewrite module call it from there).

- [ ] **Step 6: Run the suite**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |unexpected"`
Expected: 17 unexpected.

- [ ] **Step 7: Commit**

```bash
git add emacs-configs/custom/lisp/a3madkour-publish-rewrite.el emacs-configs/custom/lisp/a3madkour-publish-assets.el emacs-configs/custom/lisp/a3madkour-publish-rewrite-test.el emacs-configs/custom/lisp/a3madkour-publish-assets-test.el
git commit -m "fix(publish): resolve file links that carry a ::search suffix"
```

---

### Task 7: Grocery list breaks on recipe titles with parentheses

**Files:**
- Modify: `lisp/a3madkour-groceries.el` (`a3madkour-groceries--resolve`, about line 135; `a3madkour-groceries--recipe-item-p`, about line 192; new helper)
- Test: `lisp/a3madkour-groceries-test.el`

**Interfaces:**
- Produces: `(a3madkour-groceries--strip-note TEXT)` → TEXT without its last top-level parenthesised group and the whitespace before it, or nil when TEXT (trimmed) does not end in a balanced `(…)` group.

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest a3madkour-groceries-test-strip-note ()
  (should (equal (a3madkour-groceries--strip-note "lentils (1 cup: Soup (Indian-Inspired))")
                 "lentils"))
  (should (equal (a3madkour-groceries--strip-note "lentils (low) (2 tbsp: Toast)") "lentils (low)"))
  (should (equal (a3madkour-groceries--strip-note "lentils (low)") "lentils"))
  (should (null (a3madkour-groceries--strip-note "lentils")))
  (should (null (a3madkour-groceries--strip-note "lentils (low")))
  (should (null (a3madkour-groceries--strip-note "lentils low)"))))

(ert-deftest a3madkour-groceries-test-refresh-is-stable-for-a-title-with-parentheses ()
  ;; Fixture as `a3madkour-groceries--refresh-keeps-ticks-and-extras':
  ;; one planned recipe titled "Instant Pot Curried Lentil Soup (Indian-Inspired)"
  ;; needing "1 cup" of lentils.
  (let* ((first (refresh))
         (ticked (replace-regexp-in-string "- \\[ \\] lentils" "- [X] lentils" first))
         (second (refresh-from ticked))
         (third (refresh-from second)))
    (should (string-match-p "- \\[X\\] lentils (1 cup: Instant Pot Curried Lentil Soup (Indian-Inspired))"
                            second))
    (should (equal second third))
    (should (= 1 (how-many-lines-matching "lentils" second)))))
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "groceries-test-|^Ran "`
Expected: both FAIL.

- [ ] **Step 3: Implement `a3madkour-groceries--strip-note`**

Scan from the last character leftwards, counting `)` up and `(` down; the group opens where the count returns to zero.

- [ ] **Step 4: Use it in both callers**

In `--resolve` and `--recipe-item-p`, the `string-match "…([^()]*)\\'"` branch becomes: `(let ((stripped (a3madkour-groceries--strip-note candidate))) …)` — continue with `stripped` when non-nil, stop when nil.

- [ ] **Step 5: Run the suite**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |unexpected"`
Expected: 17 unexpected.

- [ ] **Step 6: Commit**

```bash
git add emacs-configs/custom/lisp/a3madkour-groceries.el emacs-configs/custom/lisp/a3madkour-groceries-test.el
git commit -m "fix(kitchen): keep grocery ticks when a recipe title has parentheses"
```

---

### Task 8: Final check

**Files:** none.

- [ ] **Step 1: Whole suite**

Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "^Ran |contract not found" | sort | uniq -c`
Expected: 17 unexpected, all `contract not found`; the test count has grown by the tests added above.

- [ ] **Step 2: Report what could not be checked here**

The spec's last "done when" item (a living publish dry run that lists `toast.org`) needs the site's `data/sections.json`, which this machine's checkout of `a3madkour.github.io` does not have. Say so in the hand-back; do not run a real publish.
