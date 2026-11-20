# a3 Cleanup Pass 3 (Manifest Cache and Publish Script) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A publish run parses `url-history.yaml` once, and `a3-pub.sh` builds its Emacs command in one place.

**Architecture:** A self-invalidating parse cache inside the existing `read-manifest` / `write-manifest` pair (no caller changes), then a behaviour-preserving refactor of the shell script verified by recording the arguments it passes to Emacs.

**Tech Stack:** Emacs Lisp, ERT, bash, `custom/lisp/run-tests.sh` (whole suite, about 10 seconds, no selector).

**Spec:** `custom/docs/superpowers/specs/2026-11-19-a3-cleanup-pass3-perf-script-design.md`

## Global Constraints

- Paths are relative to `emacs-configs/custom/` in the working tree; `git add` paths are relative to the git root.
- No renames of existing symbols. New Lisp symbols: `a3madkour-pub-history-…` public, `a3madkour-pub-history--…` private, no `/`. New tests: `<module-prefix>-test-<what>`, no `/`.
- `a3madkour-pub--manifest-snapshot` and `a3madkour-pub-history/read-manifest-snapshot-or-disk` are not modified.
- Manifest writes stay where they are: every change is written when it is made.
- Script: exit codes, messages, flags, environment variables and the order of each mode's own `--eval`s do not change.
- Tests run in temp directories; never the real org-roam database, `~/org` or the site checkout. No test may run a real publish.
- Baseline: `Ran 1292 tests, … 17 unexpected` (all `a3madkour-sections: contract not found …sections.json`). No new failures.
- Run: `cd lisp && ./run-tests.sh 2>&1 | grep -E "<regexp>|^Ran |unexpected"`.
- One commit per task, staging only the files the task names, ending with a `Co-Authored-By:` trailer naming the model that wrote it. Verify each commit with `git log --oneline -1`.

## Review Focus

1. The manifest file is replaced on disk by something else (git pull, sync) between two reads in one Emacs session: the second read sees the new content (Task 1).
2. A caller mutates the manifest it was given, without writing: the next read is unaffected (Task 1).
3. The manifest file is deleted, or emptied, after being cached: reads return the empty manifest (Task 1).
4. The custom directory or the lisp directory contains a space or a double quote: every mode still passes it intact (Task 3).
5. A mode's own arguments (`--publish-deliberate <path>`, pass-through `--eval`s) arrive after the common block, unchanged (Task 3).

---

### Task 1: Manifest parse cache

**Files:**
- Modify: `lisp/a3madkour-publish-history.el`
- Test: `lisp/a3madkour-publish-history-test.el`

**Interfaces — Produces (signatures unchanged):**
- `(a3madkour-pub-history/read-manifest)` → the manifest alist, as today. Parses the file only when no cached parse exists for the same absolute path, modification time and size; otherwise returns a deep copy (`copy-tree` with VECP non-nil) of the cached parse. A missing, unreadable or empty file returns a fresh copy of `a3madkour-pub-history--empty-manifest` and clears the cache.
- `(a3madkour-pub-history/write-manifest MANIFEST)` → as today, then stores a deep copy of the manifest it serialised (the canonicalised form it wrote must parse back `equal` to what a real read would return — see Step 3) with the written file's attributes.
- `(a3madkour-pub-history--cache-clear)` → drops the cache (for tests).

- [ ] **Step 1: Write the failing tests** (temp `a3madkour-pub/site-data-dir`; count parses with `cl-letf` or advice around `yaml-parse-string`; call `--cache-clear` at the start of each test)

```elisp
(ert-deftest a3madkour-pub-history-test-read-manifest-parses-once ()
  ;; write a 3-note manifest file by hand
  (a3madkour-pub-history/read-manifest)
  (a3madkour-pub-history/read-manifest)
  (a3madkour-pub-history/recorded-last-modified "id-1" "/garden/one/")
  (a3madkour-pub-history/aliases-for "id-2")
  (should (= parses 1)))

(ert-deftest a3madkour-pub-history-test-record-publish-does-not-reparse ()
  ;; same manifest; begin with one read (parses = 1), then:
  (a3madkour-pub-history/record-publish "id-1" "/garden/one-renamed/" 'live)
  (a3madkour-pub-history/record-publish "id-9" "/garden/nine/" 'live)
  (should (= parses 1))
  ;; and the file on disk has both changes:
  (a3madkour-pub-history--cache-clear)
  (let ((m (a3madkour-pub-history/read-manifest)))
    (should (= (length (alist-get 'notes m)) 4))))

(ert-deftest a3madkour-pub-history-test-read-manifest-sees-external-change ()
  (a3madkour-pub-history/read-manifest)
  ;; rewrite the file with different content AND a different size
  (should (equal (alist-get 'current_url (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
                 "/garden/changed-on-disk/"))
  (should (= parses 2)))

(ert-deftest a3madkour-pub-history-test-read-manifest-sees-same-size-change ()
  ;; rewrite with content of the SAME length, then set a different mtime with `set-file-times'
  (should (= parses 2)))

(ert-deftest a3madkour-pub-history-test-read-manifest-returns-a-copy ()
  (let ((m (a3madkour-pub-history/read-manifest)))
    (aset (alist-get 'notes m) 0 '((id . "mutated")))
    (setf (alist-get 'notes m) [])
    (should (equal (alist-get 'id (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
                   "id-1"))))

(ert-deftest a3madkour-pub-history-test-read-manifest-after-delete ()
  (a3madkour-pub-history/read-manifest)
  (delete-file manifest-path)
  (should (equal (a3madkour-pub-history/read-manifest) '((notes . [])))))

(ert-deftest a3madkour-pub-history-test-cache-matches-a-real-read-after-write ()
  ;; after each of several record-publish calls (new note, url change, state change, removal):
  (let ((cached (a3madkour-pub-history/read-manifest)))
    (a3madkour-pub-history--cache-clear)
    (should (equal cached (a3madkour-pub-history/read-manifest)))))
```

- [ ] **Step 2: Run** — expected: the parse-count tests FAIL (parses > 1), `--cache-clear` is void.
- [ ] **Step 3: Implement.** The cache is one private variable holding `(PATH MTIME SIZE MANIFEST)`. Compare modification times with `time-equal-p` on `file-attribute-modification-time`. In `write-manifest`, take the attributes after `rename-file`. What is cached after a write must be `equal` to what parsing the written file returns (the last test pins this); if canonicalisation or YAML round-tripping makes that not hold for some value (for example an empty history vector or a nil field), cache by re-reading the written file once instead, and say so in the report.
- [ ] **Step 4: Run the suite** — expected: 17 unexpected. Existing history, unpublish and publish tests stay unedited; if one fails because it writes the manifest file directly and reads it back within the same clock tick with the same size, report it rather than editing it.
- [ ] **Step 5: Commit** — `perf(publish): parse the URL-history manifest once per change, not per read`

---

### Task 2: Record what `a3-pub.sh` passes to Emacs

**Files:**
- Create: `lisp/a3-pub-argv-test.el`

**Interfaces — Produces:**
- `(a3-pub-argv-test--run &rest ARGS)` → `(EXIT-CODE . ARGV)`: runs `bash a3-pub.sh ARGS…` with a temp directory first on `PATH` holding a fake `emacs` (a shell script that writes each argument on its own NUL-terminated record to a file and exits 0), a temp paths file through `A3_PUB_PATHS_FILE`, `A3_PUB_SITE_DATA_DIR` set to a temp directory, and `A3_PUB_SKIP_MATH_CHECK=1`; ARGV is the list of recorded arguments. No real Emacs is started by the script.
- The five modes, as argument lists: `("--check-orphans")`, `("--publish-living")`, `("--publish-deliberate" "<temp>/x.org")`, `("--sync-citations")`, and the default `("--eval" "(message \"hi\")")`.

- [ ] **Step 1: Write the tests** (they describe the script as it is today, so they pass now; skip with `skip-unless` when the straight bootstrap file is absent, as `a3madkour-pub-paths-test--straight-p` does)

```elisp
(ert-deftest a3-pub-argv-test-every-mode-has-the-common-block ()
  (dolist (mode modes)
    (let ((argv (cdr (apply #'a3-pub-argv-test--run mode))))
      (should (equal (car argv) "--batch"))
      (should (member "(setq load-prefer-newer t)" argv))
      (should (member "(setq native-comp-enable-subr-trampolines nil)" argv))
      (should (member "(straight-use-package 'yaml)" argv))
      ;; -L <lisp dir> and -l <paths file> are present, -L before the first -l of a module
      (should (a3-pub-argv-test--before-p "-L" "a3madkour-publish" argv))
      (should (member paths-file argv)))))

(ert-deftest a3-pub-argv-test-deliberate-passes-its-path-through-the-environment ()
  ;; the source path must not appear inside any --eval string
  (let ((argv (cdr (a3-pub-argv-test--run "--publish-deliberate" "/tmp/has \"quote\".org"))))
    (should-not (cl-some (lambda (a) (string-match-p "has \\\\?\"quote" a)) argv))))

(ert-deftest a3-pub-argv-test-default-mode-passes-user-args-last ()
  (let ((argv (cdr (a3-pub-argv-test--run "--eval" "(message \"hi\")"))))
    (should (equal (last argv 2) '("--eval" "(message \"hi\")")))))
```

Adjust an assertion only where it misdescribes today's script, and say which in the report; the point of this task is a faithful harness.

- [ ] **Step 2:** Save today's full recorded argv for each of the five modes to five text files (one argument per line) in a directory OUTSIDE the repository, and put that directory's path in the report: Task 3 compares against them.
- [ ] **Step 3: Run the suite** — expected: 17 unexpected, the new tests pass.
- [ ] **Step 4: Commit** — `test(publish): record the arguments a3-pub.sh passes to emacs`

---

### Task 3: One bootstrap in `a3-pub.sh`

**Files:**
- Modify: `lisp/a3-pub.sh`, `lisp/a3-pub-argv-test.el`

**Interfaces — Consumes:** `a3-pub-argv-test--run` and the five "before" argv files from Task 2.

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest a3-pub-argv-test-every-mode-loads-the-same-modules ()
  ;; modules = the arguments following "-l" that start with "a3madkour-"
  (let ((lists (mapcar (lambda (mode) (a3-pub-argv-test--modules (cdr (apply #'a3-pub-argv-test--run mode))))
                       modes)))
    (should (cl-every (lambda (l) (equal l (car lists))) lists))
    (dolist (m '("a3madkour-publish" "a3madkour-publish-unpublish" "a3madkour-publish-living"
                 "a3madkour-publish-deliberate" "a3madkour-library-items"
                 "a3madkour-publish-library-notes" "a3madkour-publish-poetry"
                 "a3madkour-publish-bib" "a3madkour-publish-citations"
                 "a3madkour-publish-history" "a3madkour-publish-multi"))
      (should (member m (car lists))))))

(ert-deftest a3-pub-argv-test-custom-dir-is-not-spliced-into-lisp ()
  ;; run the script from a COPY of the lisp dir placed under a temp dir whose name contains a space
  ;; and a double quote; no recorded --eval argument contains that directory's name, and the
  ;; arguments that are paths (-L value, -l bootstrap) contain it intact.
  ...)

(ert-deftest a3-pub-argv-test-script-has-one-batch-invocation ()
  (should (= 1 (how-many-matches "emacs --batch" (file-contents a3-pub.sh)))))
```

- [ ] **Step 2: Run** — expected: all three FAIL.
- [ ] **Step 3: Refactor the script**
  - One function, `a3_pub_emacs`, holds the only `emacs --batch` and the common block; it takes the mode's own arguments as its parameters and appends them. Modes that used `exec emacs` use `exec`-equivalent behaviour (the script's exit status is Emacs's); `--publish-deliberate`, which runs Emacs without `exec` and then does more work, keeps doing so.
  - One array, `A3_PUB_MODULES`, the union of today's five lists in dependency-safe order, loaded by every mode.
  - `user-emacs-directory` is set from an exported `A3_PUB_CUSTOM_DIR` with `(getenv "A3_PUB_CUSTOM_DIR")`; no `--eval` string interpolates `$CUSTOM_DIR`.
  - The math check's roots come from the configured notes folder: resolve it once with a minimal `emacs --batch -Q -l "$PATHS_FILE"` that prints `a3madkour-pub/org-notes-dir` (this small probe is the one other Emacs invocation allowed; write it so the Step 1 "one batch invocation" test counts only the bootstrap — for example `emacs -Q --batch` — and say so in the report), and pass that folder and its parent where `$HOME/org/notes` and `$HOME/org` are passed today. If the probe prints nothing, fail with a message naming the paths file, exit status 2.
- [ ] **Step 4: Compare argv before and after.** For each mode, diff the new recorded argv against Task 2's file. Put the five diffs in the report. Every difference must be one of: the module list (now the union, same for all), the `user-emacs-directory` form now reading the environment, or a reordering inside the common block. Anything else is a bug to fix before committing.
- [ ] **Step 5: Run the suite** — expected: 17 unexpected (including the existing `a3madkour-pub-paths-test/a3-pub-…` tests, which run the real script).
- [ ] **Step 6: Run one real, harmless invocation** from the worktree: `./a3-pub.sh --eval '(princ (format "OK %s\n" a3madkour-pub/version))'` with `A3_PUB_SITE_DATA_DIR` pointing at a temp directory — expected: prints `OK <version>` and exits 0, with every module in `A3_PUB_MODULES` loading. Do not run any `--publish-*`, `--check-orphans` or `--sync-citations` mode for real.
- [ ] **Step 7: Commit** — `refactor(publish): one emacs bootstrap in a3-pub.sh`

---

### Task 4: Final check

- [ ] **Step 1:** Whole suite: 17 unexpected, all `contract not found`.
- [ ] **Step 2:** `grep -c "emacs --batch" lisp/a3-pub.sh` and `grep -n '\$HOME/org' lisp/a3-pub.sh` — one bootstrap, no hardcoded org folder.
- [ ] **Step 3:** Time the manifest: with the owner's real manifest copied into a temp directory, 100 `read-manifest` calls take well under a second (they took about 10 s before).
