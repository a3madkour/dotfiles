# a3 Cleanup Pass 2 (Shared Org-Reading Module) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the duplicated org-reading helpers in the kitchen and publish code with one shared module, `a3madkour-org.el`, and close three pass 1 leftovers.

**Architecture:** A new leaf module that requires only org. Each task moves one helper family: add the shared function with tests, switch the callers, delete the copies. Parsing behaviour does not change except for the two changes the spec decides (quantities, bracket-link pattern).

**Tech Stack:** Emacs Lisp, ERT, `custom/lisp/run-tests.sh` (whole suite, about 10 seconds, no selector).

**Spec:** `custom/docs/superpowers/specs/2026-11-19-a3-cleanup-pass2-shared-org-design.md`

## Global Constraints

- Paths are relative to `emacs-configs/custom/` in the working tree; `git add` paths are relative to the git root.
- `a3madkour-org.el` requires only `org`, `org-element`, `subr-x`, `cl-lib`. It must never require another `a3madkour-*` module.
- No kitchen module (`a3madkour-recipes`, `-ingredients`, `-groceries`, `-units`, `-recipe-import`) may gain a `require` of an `a3madkour-publish-*` module.
- New symbols: `a3madkour-org-…` public, `a3madkour-org--…` private, no `/`. New tests: `a3madkour-org-test-<what>`, no `/`.
- No renames of existing symbols that survive. No performance work.
- A deleted helper's own tests move to `lisp/a3madkour-org-test.el`, pointed at the shared function with the same assertions. Tests of surviving callers are not edited.
- Tests run in temp directories; never the real org-roam database, `~/org` or the site checkout.
- Baseline: `Ran 1274 tests, … 17 unexpected` (all `a3madkour-sections: contract not found …sections.json`). No new failures. The test count changes only by tests this plan adds, moves or (Task 7) deletes.
- Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "<regexp>|^Ran |unexpected"`.
- One commit per task, staging only the files the task names. End each message with a `Co-Authored-By:` trailer naming the model that wrote it.

## Review Focus

1. A `#+KEY:` line with no value: `""`, not nil, from the buffer reader (Task 1).
2. A table cell holding a link or bold text read through the parse tree: the same string the old walker gave (Task 2).
3. An Ingredients heading with tags, or with no table before the next heading: same rows / nil as before (Task 3).
4. A registry or grocery buffer with unsaved edits and a newer file on disk: refused, both left intact, message names the right thing (Task 4).
5. A slug-change migration when a living file links the old asset folder by a relative path from outside the notes tree (Task 8).

---

### Task 1: Module and keyword readers

**Files:**
- Create: `lisp/a3madkour-org.el`, `lisp/a3madkour-org-test.el`
- Modify: `lisp/a3madkour-publish-keywords.el`, `lisp/a3madkour-recipes.el`, `lisp/a3madkour-recipe-lint.el`, `lisp/a3madkour-works-lint.el`

**Interfaces — Produces:**
- `(a3madkour-org-keyword KEY)` → value of the first `#+KEY:` line in the current buffer (whole buffer, narrowing ignored, key case-insensitive), trimmed; `""` when present with no value; nil when absent.
- `(a3madkour-org-keyword-in-string TEXT KEY)` → same, reading TEXT.
- `(a3madkour-org-ast-keyword AST NAME)` → value of the first keyword element in AST whose key, upcased, equals NAME; nil when absent.

- [ ] **Step 1: Write the failing tests** in `a3madkour-org-test.el`

```elisp
(ert-deftest a3madkour-org-test-keyword ()
  (with-temp-buffer
    (insert "#+TITLE:  Toast \n#+hugo_section: recipes\n#+EMPTY:\n* H\n")
    (narrow-to-region (point-max) (point-max))
    (should (equal (a3madkour-org-keyword "TITLE") "Toast"))
    (should (equal (a3madkour-org-keyword "HUGO_SECTION") "recipes"))
    (should (equal (a3madkour-org-keyword "EMPTY") ""))
    (should (null (a3madkour-org-keyword "MISSING")))))

(ert-deftest a3madkour-org-test-keyword-in-string ()
  (should (equal (a3madkour-org-keyword-in-string "x\n#+title: A b \n" "TITLE") "A b"))
  (should (equal (a3madkour-org-keyword-in-string "#+EMPTY:\n" "EMPTY") ""))
  (should (null (a3madkour-org-keyword-in-string "no keywords" "TITLE"))))

(ert-deftest a3madkour-org-test-ast-keyword ()
  (let ((ast (with-temp-buffer
               (insert "#+hugo_section: works/games\n#+TITLE: T\n")
               (org-mode) (org-element-parse-buffer))))
    (should (equal (a3madkour-org-ast-keyword ast "HUGO_SECTION") "works/games"))
    (should (null (a3madkour-org-ast-keyword ast "MISSING")))))
```

Before deleting them, check what `a3madkour-recipes--keyword` and `--text-keyword` return for a present-but-empty keyword; if either returns nil where the shared one returns `""`, keep that caller's behaviour by wrapping at the call site, and say so in the report.

- [ ] **Step 2: Run** — expected: the three tests FAIL (void function).
- [ ] **Step 3: Implement the three functions** in `a3madkour-org.el` (with header, `;;; Commentary:` stating the leaf-module rule, and `(provide 'a3madkour-org)`).
- [ ] **Step 4: Switch the callers**
  - `a3madkour-publish-keywords.el`: `(require 'a3madkour-org)`; replace the body of `a3madkour-pub-keywords/extract` with `(defalias 'a3madkour-pub-keywords/extract #'a3madkour-org-keyword "…until the rename pass.")`. Its existing tests in `a3madkour-publish-keywords-test.el` stay unedited and must pass.
  - `a3madkour-recipes.el`: delete `a3madkour-recipes--keyword` and `a3madkour-recipes--text-keyword`; their call sites call the shared functions.
  - `a3madkour-recipe-lint.el`, `a3madkour-works-lint.el`: delete `--kw`; call sites call `a3madkour-org-ast-keyword`.
- [ ] **Step 5: Run the suite** — expected: 17 unexpected.
- [ ] **Step 6: Commit** — `refactor(org): one shared keyword reader`

---

### Task 2: Parse-tree table readers

**Files:**
- Modify: `lisp/a3madkour-org.el`, `lisp/a3madkour-org-test.el`, `lisp/a3madkour-publish-research.el`, `lisp/a3madkour-publish-recipes.el`, `lisp/a3madkour-recipe-lint.el`, `lisp/a3madkour-publish-recipes-test.el` (only the two references to the deleted helpers)

**Interfaces — Produces:**
- `(a3madkour-org-ast-table-under HEADLINE)` → first table element in HEADLINE's own section, or nil.
- `(a3madkour-org-ast-table-rows TABLE)` → list of rows, each a list of trimmed cell strings; rule rows skipped; an empty cell is `""`; a cell whose content is not a plain string is its interpreted org text, trimmed, without text properties.

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest a3madkour-org-test-ast-table ()
  (let* ((ast (with-temp-buffer
                (insert "* R\n** Ingredients\ntext\n| qty | item |\n|-----+------|\n| 2 | [[id:x][egg]] |\n|   | *salt* |\n*** Sub\n| a |\n** Empty\n")
                (org-mode) (org-element-parse-buffer)))
         (hl (lambda (title)
               (org-element-map ast 'headline
                 (lambda (h) (and (equal (org-element-property :raw-value h) title) h))
                 nil t))))
    (should (equal (a3madkour-org-ast-table-rows
                    (a3madkour-org-ast-table-under (funcall hl "Ingredients")))
                   '(("qty" "item") ("2" "[[id:x][egg]]") ("" "*salt*"))))
    (should (null (a3madkour-org-ast-table-under (funcall hl "Empty"))))
    (should (null (a3madkour-org-ast-table-under (funcall hl "R"))))))
```

If the old walker gives different strings for the link or bold cell than this test expects, the old walker's output is the correct expectation: adjust the two expected strings to it and say so in the report.

- [ ] **Step 2: Run** — expected: FAIL (void function).
- [ ] **Step 3: Implement** by moving one of the existing pairs verbatim.
- [ ] **Step 4: Switch the callers** — delete `a3madkour-pub-research--find-table-under`, `--table-rows`, `a3madkour-pub-recipes--find-table-under`, `--table-rows`; every call site (including the `declare-function` lines and calls in `a3madkour-recipe-lint.el`, and the two references in `a3madkour-publish-recipes-test.el`) uses the shared names. `(require 'a3madkour-org)` in each module that calls them.
- [ ] **Step 5: Run the suite** — expected: 17 unexpected.
- [ ] **Step 6: Commit** — `refactor(org): one shared parse-tree table reader`

---

### Task 3: Text-level table rows under a heading

**Files:**
- Modify: `lisp/a3madkour-org.el`, `lisp/a3madkour-org-test.el`, `lisp/a3madkour-ingredients.el`

**Interfaces — Produces:**
- `(a3madkour-org-table-rows-under HEADING-P &optional BUFFER)` → cell lists of the first table that follows, before the next heading, the first heading line for which `(funcall HEADING-P LINE)` is non-nil; rule lines dropped; header row first; nil when there is no such heading or no table before the next heading. Reads the whole buffer regardless of narrowing; leaves point and restriction as they were.

- [ ] **Step 1: Write the failing test**

```elisp
(ert-deftest a3madkour-org-test-table-rows-under ()
  (let ((p (lambda (line) (string-match-p "\\`\\*+ +Ingredients" line))))
    (with-temp-buffer
      (insert "* R\n** Ingredients :tag:\nnote\n  | qty | item |\n  |-----+------|\n  | 2 | egg |\n** Steps\n| x |\n")
      (should (equal (a3madkour-org-table-rows-under p) '(("qty" "item") ("2" "egg")))))
    (with-temp-buffer
      (insert "** Ingredients\nnone here\n** Steps\n| x |\n")
      (should (null (a3madkour-org-table-rows-under p))))
    (with-temp-buffer
      (insert "* Other\n| x |\n")
      (should (null (a3madkour-org-table-rows-under p))))))
```

- [ ] **Step 2: Run** — expected: FAIL (void function).
- [ ] **Step 3: Implement** by moving the scanning loop out of `a3madkour-ingredients--recipe-rows`, together with the row-splitting and rule-line helpers it uses if nothing else in `a3madkour-ingredients.el` needs them (if something else does, the shared module gets its own private copies named `a3madkour-org--…` and the ingredients ones stay; say which in the report).
- [ ] **Step 4:** `a3madkour-ingredients--recipe-rows` becomes a one-expression caller passing `#'a3madkour-ingredients--ingredients-heading-p`. Its existing tests stay unedited.
- [ ] **Step 5: Run the suite** — expected: 17 unexpected.
- [ ] **Step 6: Commit** — `refactor(org): one shared table-under-heading scanner`

---

### Task 4: Buffer sync guard

**Files:**
- Modify: `lisp/a3madkour-org.el`, `lisp/a3madkour-org-test.el`, `lisp/a3madkour-ingredients.el`, `lisp/a3madkour-groceries.el`

**Interfaces — Produces:**
- `(a3madkour-org-synced-buffer FILE WHAT)` → the buffer visiting FILE (an existing one, else a new one; FILE's directory is created if missing), holding the newest text there is. When the file changed on disk under an unmodified buffer, the buffer is reverted without asking. When the buffer also has unsaved edits, signals `(user-error "%s has unsaved changes and the file changed on disk; save or revert it first" WHAT)` and changes nothing.

- [ ] **Step 1: Write the failing tests** (temp dir; change the file on disk with `write-region` and set a later mtime with `set-file-times` so `verify-visited-file-modtime` sees it)

```elisp
(ert-deftest a3madkour-org-test-synced-buffer-reverts-stale ()
  ;; visit f ("old"), rewrite f on disk to "new" with a newer mtime
  (should (equal (with-current-buffer (a3madkour-org-synced-buffer f "The list") (buffer-string))
                 "new")))

(ert-deftest a3madkour-org-test-synced-buffer-refuses-unsaved ()
  ;; visit f, insert "edit" (unsaved), rewrite f on disk with a newer mtime
  (let ((err (should-error (a3madkour-org-synced-buffer f "The list") :type 'user-error)))
    (should (equal (cadr err)
                   "The list has unsaved changes and the file changed on disk; save or revert it first")))
  (should (string-match-p "edit" (with-current-buffer buf (buffer-string))))
  (should (equal (file-contents f) "new")))

(ert-deftest a3madkour-org-test-synced-buffer-creates-directory ()
  (should (bufferp (a3madkour-org-synced-buffer (expand-file-name "sub/new.org" dir) "X")))
  (should (file-directory-p (expand-file-name "sub" dir))))
```

- [ ] **Step 2: Run** — expected: FAIL (void function).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Switch the callers** — `a3madkour-ingredients--editing` uses `(a3madkour-org-synced-buffer file "The registry buffer")`; `a3madkour-groceries--buffer` uses `(a3madkour-org-synced-buffer file "The grocery list")`. Both keep their exact current error text and everything else they do (the unset-file check, `save-buffer`, widening). Existing tests stay unedited.
- [ ] **Step 5: Run the suite** — expected: 17 unexpected.
- [ ] **Step 6: Commit** — `refactor(org): one shared buffer sync guard`

---

### Task 5: Bracket-link pattern

**Files:**
- Modify: `lisp/a3madkour-org.el`, `lisp/a3madkour-org-test.el`, `lisp/a3madkour-publish-rewrite.el`, `lisp/a3madkour-publish-assets.el`, `lisp/a3madkour-library-items.el`

**Interfaces — Produces:**
- `a3madkour-org-bracket-link-re` — the string currently bound to `a3madkour-pub-rewrite--bracket-link-re`: `"\\[\\[\\([^][]+\\)\\(?:\\]\\[\\([^][]+\\)\\)?\\]\\]"`. Group 1 = path, group 2 = description or unmatched.

- [ ] **Step 1: Write the failing test**

```elisp
(ert-deftest a3madkour-org-test-bracket-link-re ()
  (let ((re a3madkour-org-bracket-link-re))
    (should (string-match re "a [[file:x.png]] b"))
    (should (equal (match-string 1 "a [[file:x.png]] b") "file:x.png"))
    (should (null (match-string 2 "a [[file:x.png]] b")))
    (should (string-match re "[[id:u][the text]]"))
    (should (equal (match-string 2 "[[id:u][the text]]") "the text"))
    (should-not (string-match re "[[a][b [c]]]"))))
```

- [ ] **Step 2: Run** — expected: FAIL (void variable).
- [ ] **Step 3: Define the constant; switch the users**
  - `a3madkour-publish-rewrite.el`: delete `a3madkour-pub-rewrite--bracket-link-re`; its one use takes the shared constant.
  - `a3madkour-publish-assets.el`: the two inline patterns (in `--extract-asset-refs` and `--asset-rewrite-source-links-to`) take the shared constant.
  - `a3madkour-library-items.el`: delete `a3madkour-library--link-re`; its one use takes the shared constant. Its old group 2 was the `][desc` part including the brackets; the shared group 2 is the description alone — adapt the replacement code so the rewritten link text is byte-identical to before.
- [ ] **Step 4: Run the suite** — expected: 17 unexpected, with every existing library-items, assets and rewrite test unedited.
- [ ] **Step 5: Commit** — `refactor(org): one shared bracket-link pattern`

---

### Task 6: Quantities

**Files:**
- Modify: `lisp/a3madkour-publish-recipes.el`, `lisp/a3madkour-recipe-lint.el`, `lisp/a3madkour-publish-recipes-test.el`, `lisp/a3madkour-recipe-lint-test.el`

**Interfaces — Consumes:** `(a3madkour-units/parse-qty STRING)` → number or nil (`a3madkour-units.el`, no dependencies).

- [ ] **Step 1: Write the failing tests**

In `a3madkour-publish-recipes-test.el`, replace `a3madkour-pub-recipes--coerce-qty-forms` (a test of the helper being deleted) with a test through the surviving ingredient parser, same fixture style as `a3madkour-pub-recipes--parse-ingredients-happy`:

```elisp
(ert-deftest a3madkour-pub-recipes-test-ingredient-quantities ()
  ;; one ingredient row per qty cell below; collect the :qty of each parsed row
  (should (equal qtys '(2 800 0.5 0.5 0.5 1.5 0.5 1.5 3 3 nil))))
;; cells, in order: "2" "800" "0.5" ".5" "1/2" "1 1/2" "½" "1½" "2-3" "2 to 3" ""
```

In `a3madkour-recipe-lint-test.el`:

```elisp
(ert-deftest a3madkour-recipe-lint-test-accepts-kitchen-quantities ()
  ;; a recipe whose qty cells are "1 1/2", "½", "2-3" lints with no qty finding
  (should-not (cl-some (lambda (f) (string-match-p "qty" f)) findings)))

(ert-deftest a3madkour-recipe-lint-test-rejects-non-quantity ()
  ;; qty cell "a pinch"
  (should (cl-some (lambda (f) (string-match-p "ingredient qty \"a pinch\" is not numeric-or-empty" f))
                   findings)))
```

- [ ] **Step 2: Run** — expected: the first two FAIL (`1 1/2`, `½`, ranges rejected or nil); the third passes before and after.
- [ ] **Step 3: Implement** — delete `a3madkour-pub-recipes--coerce-qty`; `a3madkour-publish-recipes.el` and `a3madkour-recipe-lint.el` `(require 'a3madkour-units)` and call `a3madkour-units/parse-qty` (drop the `declare-function` for the deleted helper). An empty or whitespace cell must still give nil and no lint finding.
- [ ] **Step 4: Run the suite** — expected: 17 unexpected. If an existing recipe test fails because a whole-number decimal such as `2.0` now publishes as `2`, that is the one accepted difference: report it, do not edit the test, and stop.
- [ ] **Step 5: Commit** — `feat(recipes): published recipes accept the kitchen quantity grammar`

---

### Task 7: Small leftovers

**Files:**
- Modify: `lisp/a3madkour-publish-assets.el`, `lisp/a3madkour-publish-assets-test.el`, `lisp/a3madkour-groceries.el`

- [ ] **Step 1:** Delete `a3madkour-pub--asset-rewrite-source-link` (no production caller) and the three tests that only call it: `a3madkour-pub-assets-test/rewrite-source-link-basic`, `…-with-display-text`, `…-multiple-occurrences`. Confirm with `grep` that nothing else names the function.
- [ ] **Step 2:** In `a3madkour-groceries--resolve` and `a3madkour-groceries--recipe-item-p`, call `a3madkour-groceries--strip-note` once per loop pass (bind the result, then test it). Change "bracketed" to "parenthesised" in its docstring.
- [ ] **Step 3: Run the suite** — expected: 17 unexpected; the test count drops by exactly 3.
- [ ] **Step 4: Commit** — `chore: remove the unused link-rewrite helper and tidy strip-note`

---

### Task 8: Slug-change link migration covers every living file

**Files:**
- Modify: `lisp/a3madkour-publish-unpublish.el` (`a3madkour-pub--unpublish-bulk-rewrite-source-links`), `lisp/a3madkour-publish-unpublish-test.el`

**Interfaces:**
- Consumes: `(a3madkour-pub-registry-living-files)`; `a3madkour-org-bracket-link-re`; `(a3madkour-pub--asset-normalize-link-path PATH ORG-FILE)` → absolute path (`a3madkour-publish-assets.el`; if requiring that module from unpublish would create a load cycle, use `declare-function` and note it); `(a3madkour-pub-rewrite--split-search PATH)`.
- Produces: `(a3madkour-pub--unpublish-bulk-rewrite-source-links OLD-SLUG NEW-SLUG &optional ORG-NOTES-DIR)` keeps its signature and `(:modified ((FILE . COUNT) …) :warnings (…))` return. New behaviour: it visits every bracket link in every file of `(a3madkour-pub-registry-living-files)` (or, when ORG-NOTES-DIR is given, every `.org` file under it — the existing tests pass a directory); a link whose path (after `file:` and `::search` are set aside) resolves to a file under `<asset-root>/page/<OLD-SLUG>/` has that one path segment replaced by NEW-SLUG, the rest of the link text (spelling, `file:` prefix, `::search`, description) left exactly as written. OLD-SLUG equal to NEW-SLUG still returns at once with nothing modified.

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest a3madkour-pub-unpublish-test-bulk-rewrite-covers-recipes-folder ()
  ;; notes/ and recipes/ are siblings; asset root is notes/assets.
  ;; recipes/toast.org: "[[file:../notes/assets/page/old/x.png][pic]]"
  ;; a3madkour-pub/org-notes-dir -> notes, a3madkour-pub-recipes-dir -> recipes
  (let ((r (a3madkour-pub--unpublish-bulk-rewrite-source-links "old" "new")))
    (should (equal (plist-get r :modified) (list (cons toast 1))))
    (should (equal (file-contents toast)
                   "[[file:../notes/assets/page/new/x.png][pic]]"))))

(ert-deftest a3madkour-pub-unpublish-test-bulk-rewrite-keeps-spelling-and-search ()
  ;; notes/a.org: "[[./assets/page/old/p.pdf::5]] [[~/…abbreviated root…/page/old/y.png]] [[./assets/page/older/z.png]]"
  ;; after migrating "old" -> "new": first two rewritten in place, third untouched
  (should (equal (cdar (plist-get r :modified)) 2))
  (should (string-match-p (regexp-quote "[[./assets/page/new/p.pdf::5]]") (file-contents a)))
  (should (string-match-p (regexp-quote "/page/new/y.png]]") (file-contents a)))
  (should (string-match-p (regexp-quote "[[./assets/page/older/z.png]]") (file-contents a))))
```

The pass 1 tests (`…-bulk-rewrite-same-slug-terminates`, `…-counts-each-match-once`, and every older bulk-rewrite test) stay unedited and must pass.

- [ ] **Step 2: Run** — expected: the recipes-folder test FAILS (file not visited / pattern does not match); the second may pass or fail on the `older` assertion — record which.
- [ ] **Step 3: Implement.** A file is written only when at least one link changed. A write failure adds `"WARN: failed to write back FILE: REASON"` to `:warnings`, as today.
- [ ] **Step 4: Run the suite** — expected: 17 unexpected.
- [ ] **Step 5: Commit** — `fix(publish): migrate asset links in every living file on a slug change`

---

### Task 9: Final check

- [ ] **Step 1:** Whole suite: 17 unexpected, all `contract not found`.
- [ ] **Step 2:** `grep -n "defun a3madkour-recipes--keyword\|defun a3madkour-recipes--text-keyword\|--kw \|--find-table-under\|defun a3madkour-pub-.*--table-rows\|--coerce-qty\|a3madkour-library--link-re\|a3madkour-pub-rewrite--bracket-link-re\|--asset-rewrite-source-link " lisp/a3madkour-*.el` prints nothing.
- [ ] **Step 3:** `grep -n "^(require 'a3madkour" lisp/a3madkour-org.el` prints nothing, and no kitchen module requires an `a3madkour-publish-*` module.
