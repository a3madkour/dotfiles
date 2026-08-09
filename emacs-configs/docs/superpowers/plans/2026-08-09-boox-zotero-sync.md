# Boox Note Max Reading Round Trip — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Push `:active:` reading-queue items from Emacs to the Boox Note Max, and pull annotated PDFs plus extracted highlights back into the org-roam ref notes.

**Architecture:** Pure helpers (path normalization, slugging, key extraction, highlight parsing) tangle from `config.org` into a standalone `boox-core.el` that batch ERT can load without pulling in the whole Emacs config. Interactive commands (`boox-push-queue`, `boox-import`) tangle into `config.el` as usual and `require` the core. Transport is a dedicated Syncthing folder at `~/Boox/reading/` shared only with the tablet.

**Tech Stack:** Emacs Lisp, org-babel literate tangling, ERT, citar, org-noter, org-roam, Syncthing.

---

## Prerequisites — device verification (manual, blocks Task 8 only)

These are done by hand on the tablet. Tasks 1-7 and 9-10 do not depend on them.

- [ ] **P1: Install Syncthing-Fork on the Boox**

Sideload Catfriend1's Syncthing-Fork (the official syncthing-android app is
discontinued). Pair it with this machine. Create the folder on this side first:

```bash
mkdir -p ~/Boox/reading ~/Boox/archive
```

Share `~/Boox/reading/` with the Boox only — not with Pixel, MacBook, or the
other four devices. Enable Simple File Versioning on the folder.

- [ ] **P2: Exempt Syncthing from Boox power management**

Boox aggressively kills background apps. Settings → Power → App optimization →
set Syncthing to "no optimization" / keep alive. Then verify: drop a test file
into `~/Boox/reading/`, let the tablet sleep 30 minutes, wake it, confirm the
file is there and that a file created on the tablet propagates back.

- [ ] **P3: Capture a real NeoReader export**

Open any PDF in `~/Boox/reading/` in NeoReader, add two or three highlights and
one typed annotation, then use the export function to produce **both** an
annotated PDF and an annotation text export. Record:

1. The exact directory the exports land in.
2. The exact filenames produced.
3. The full text of the annotation export.

Copy the annotation export to
`~/emacs-configs/custom/tests/fixtures/neoreader-export.txt`. Task 8 is written
against it.

**Decision rule from P3:** if exports land beside the source document,
`a3madkour/boox-inbox-directories` stays as the single `~/Boox/reading/`. If they
land in a fixed device directory, add a second receive-only Syncthing folder
`~/Boox/exports/` pointing at it and append that path to the list. This is one
line in Task 1's defcustom either way.

---

## File Structure

| File | Responsibility | Generated from |
| --- | --- | --- |
| `~/emacs-configs/custom/config.org` | Source of truth — new `* Boox` section after Citproc (`config.org:1735`) | hand-edited |
| `~/emacs-configs/custom/boox-core.el` | Pure functions: path normalization, slug, key extraction, highlight parser. `provide`s `boox-core`. No citar/org-noter dependency. | tangled |
| `~/emacs-configs/custom/config.el` | Interactive commands, defcustoms, keybindings | tangled |
| `~/emacs-configs/custom/tests/boox-tests.el` | ERT suite, loadable in `emacs -Q --batch` | tangled |
| `~/emacs-configs/custom/tests/fixtures/neoreader-export.txt` | Real export captured in P3 | hand-placed |

**Generated files are never committed.** `config.el` is untracked in this repo
and that convention holds for the two new tangle targets: only `config.org` and
the hand-placed fixture are ever `git add`ed. Every commit step below reflects
this — if a step seems to be missing a file, that is why.

**Why `boox-core.el` exists:** the design doc put tests in `tests/boox-tests.el`
but did not say how they would load the functions under test. Loading `config.el`
in batch would pull every `use-package` in the config. Splitting the pure
functions into a standalone feature makes the suite run in under a second with
`emacs -Q`.

**Two commands used constantly below.** Tangle, then test:

```bash
# Tangle config.org -> config.el, boox-core.el, tests/boox-tests.el
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'

# Run the ERT suite
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

---

## Task 1: Section scaffolding and configuration

**Files:**
- Modify: `~/emacs-configs/custom/config.org` (insert after the Citproc block ending at line 1735)

- [ ] **Step 1: Add the `* Boox` section header and configuration block**

Insert immediately after the `** Citproc` block and before `* Org`:

````org
* Boox
Round trip between the reading queue, the Boox Note Max, and the org-roam ref
notes.  Pure helpers tangle to =boox-core.el= so the ERT suite can load them
without the rest of the config; commands tangle to =config.el= as usual.
** Configuration
#+begin_src emacs-lisp
(defcustom a3madkour/boox-reading-directory (expand-file-name "~/Boox/reading/")
  "Syncthing folder shared with the Boox Note Max.
Files pushed here appear on the tablet; removing a file here removes it
from the tablet."
  :type 'directory
  :group 'a3madkour)

(defcustom a3madkour/boox-archive-directory (expand-file-name "~/Boox/archive/")
  "Local, unsynced directory where consumed exports are parked.
Used to make `a3madkour/boox-import' idempotent."
  :type 'directory
  :group 'a3madkour)

(defcustom a3madkour/boox-inbox-directories
  (list (expand-file-name "~/Boox/reading/"))
  "Directories scanned by `a3madkour/boox-import' for NeoReader exports.
If NeoReader writes exports beside the source document this stays as the
single reading directory.  If it writes to a fixed device directory, add a
second Syncthing folder for it and append that path here."
  :type '(repeat directory)
  :group 'a3madkour)

(defcustom a3madkour/boox-annotated-suffix "-annotated"
  "Suffix appended to the basename of an annotated copy."
  :type 'string
  :group 'a3madkour)

(defcustom a3madkour/boox-supported-extensions '("pdf" "epub")
  "Extensions NeoReader is known to open.  Others are reported, not pushed."
  :type '(repeat string)
  :group 'a3madkour)

(add-to-list 'load-path (expand-file-name "~/emacs-configs/custom"))
(require 'boox-core)
#+end_src
````

- [ ] **Step 2: Add the core file preamble block**

Directly after the configuration block:

````org
** Core helpers
These tangle to =boox-core.el= rather than =config.el= so the test suite can
load them standalone.
#+begin_src emacs-lisp :tangle "./boox-core.el" :mkdirp yes
;;; boox-core.el --- Pure helpers for the Boox reading round trip -*- lexical-binding: t; -*-
;;; Commentary:
;; Generated from config.org.  Do not edit directly.
;;; Code:

(require 'subr-x)
(require 'seq)
(require 'cl-lib)

(defconst a3madkour/boox-key-separator "--"
  "Separator between the key and the title half of a pushed filename.")
#+end_src
````

- [ ] **Step 3: Add the test file preamble block**

````org
** Tests
#+begin_src emacs-lisp :tangle "./tests/boox-tests.el" :mkdirp yes
;;; boox-tests.el --- ERT suite for boox-core -*- lexical-binding: t; -*-
;;; Commentary:
;; Generated from config.org.  Do not edit directly.
;; Run: emacs -Q --batch -L ~/emacs-configs/custom -l ert \
;;        -l ~/emacs-configs/custom/boox-core.el \
;;        -l ~/emacs-configs/custom/tests/boox-tests.el \
;;        -f ert-run-tests-batch-and-exit
;;; Code:

(require 'ert)
(require 'boox-core)
#+end_src
````

- [ ] **Step 4: Add the core file footer block**

This must be the **last** block that tangles to `boox-core.el`, so append it at
the very end of the `* Boox` section. Every later task inserts its core code
*above* this block.

````org
** Core footer
#+begin_src emacs-lisp :tangle "./boox-core.el"
(provide 'boox-core)
;;; boox-core.el ends here
#+end_src
````

- [ ] **Step 5: Tangle and confirm the files appear**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
ls -la ~/emacs-configs/custom/boox-core.el ~/emacs-configs/custom/tests/boox-tests.el
```

Expected: both files exist. `boox-core.el` contains the preamble, the
`defconst`, and the `provide` — in that order.

- [ ] **Step 6: Confirm the core file loads clean**

```bash
emacs -Q --batch -L ~/emacs-configs/custom -l boox-core --eval '(message "loaded: %s" a3madkour/boox-key-separator)'
```

Expected: `loaded: --` with no errors.

- [ ] **Step 7: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): scaffold Boox section, core file, and test suite"
```

---

## Task 2: `a3madkour/normalize-library-path`

Every `file = {...}` field in `library.bib` is a macOS path
(`/Users/a3madkour/Sync/...`). This re-anchors them onto whatever machine is
running.

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — core section (above the footer block) and tests section

- [ ] **Step 1: Write the failing tests**

Add to the `** Tests` block:

```elisp
(ert-deftest boox-normalize-macos-path ()
  (should (equal (a3madkour/normalize-library-path
                  "/Users/a3madkour/Sync/Zotero/storage/AB12/paper.pdf")
                 (expand-file-name "Sync/Zotero/storage/AB12/paper.pdf" "~"))))

(ert-deftest boox-normalize-linux-path-is-idempotent ()
  (let ((p (expand-file-name "Sync/Books/book.pdf" "~")))
    (should (equal (a3madkour/normalize-library-path p) p))))

(ert-deftest boox-normalize-returns-nil-without-sync-segment ()
  (should (null (a3madkour/normalize-library-path "/tmp/elsewhere/paper.pdf")))
  (should (null (a3madkour/normalize-library-path nil)))
  (should (null (a3madkour/normalize-library-path ""))))

(ert-deftest boox-normalize-uses-first-sync-segment ()
  (should (equal (a3madkour/normalize-library-path
                  "/Users/a3madkour/Sync/Books/Sync/nested.pdf")
                 (expand-file-name "Sync/Books/Sync/nested.pdf" "~"))))

(ert-deftest boox-normalize-trims-surrounding-whitespace ()
  (should (equal (a3madkour/normalize-library-path
                  "  /Users/a3madkour/Sync/Books/b.pdf  ")
                 (expand-file-name "Sync/Books/b.pdf" "~"))))

(ert-deftest boox-normalize-ignores-sync-without-trailing-slash ()
  (should (null (a3madkour/normalize-library-path "/tmp/Syncthing-notes.pdf"))))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: 6 failures, each `void-function a3madkour/normalize-library-path`.

- [ ] **Step 3: Write the implementation**

Add to the `** Core helpers` section, in a new block above the footer:

````org
#+begin_src emacs-lisp :tangle "./boox-core.el"
(defun a3madkour/normalize-library-path (path)
  "Re-anchor PATH from a bib `file' field onto this machine's home directory.
The bibliography was written on macOS, so entries carry
/Users/a3madkour/Sync/... prefixes that do not resolve elsewhere.  Take
everything from the first `Sync/' segment onward and expand it under `~'.
Return nil when PATH is empty or contains no `Sync/' segment."
  (when (and path (stringp path))
    (let ((trimmed (string-trim path)))
      (when (string-match "\\`.*?\\(Sync/.*\\)\\'" trimmed)
        (expand-file-name (match-string 1 trimmed) "~")))))
#+end_src
````

- [ ] **Step 4: Run the tests to verify they pass**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: `Ran 6 tests, 6 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add normalize-library-path with tests"
```

---

## Task 3: Retrofit the two existing callers

Fixes the live defect where `a3madkour/supernote-sync-active-queue` reports
every key as missing on Linux.

**Files:**
- Modify: `~/emacs-configs/custom/config.org:1569` (inside `a3madkour/citar-org-format-note`)
- Modify: `~/emacs-configs/custom/config.org:1670-1675` (`a3madkour/supernote--pdf-for-key`)

- [ ] **Step 1: Replace the inline rewrite in the note formatter**

At `config.org:1568-1569`, replace:

```elisp
		(when note-path-clean
		  (insert (concat "~/" (replace-regexp-in-string ".*Sync/" "Sync/" note-path-clean))))
```

with:

```elisp
		(when note-path-clean
		  (insert (or (a3madkour/normalize-library-path note-path-clean)
					  note-path-clean)))
```

Note the behaviour change: the old code emitted a literal `~/Sync/...` string,
the new one emits an absolute `/home/a3madkour/Sync/...` path. org-noter expands
both, and absolute paths are unambiguous across the Linux/macOS split.

- [ ] **Step 2: Normalize in the Supernote resolver**

At `config.org:1670`, replace the whole function with:

```elisp
(defun a3madkour/supernote--pdf-for-key (key)
  "Return the first .pdf path attached to KEY in Citar, normalized, or nil."
  (when-let* ((entry (citar-get-entry key))
              (file (alist-get "file" entry nil nil #'string=))
              (raw (car (seq-filter (lambda (p) (string-match-p "\\.pdf\\'" (string-trim p)))
                                    (split-string file ";")))))
    (or (a3madkour/normalize-library-path raw) (string-trim raw))))
```

- [ ] **Step 3: Move `boox-core` loading earlier**

`a3madkour/citar-org-format-note` at `config.org:1539` now calls a `boox-core`
function, but the `require` added in Task 1 sits later in the file. Cut these
two lines out of the Task 1 configuration block:

```elisp
(add-to-list 'load-path (expand-file-name "~/emacs-configs/custom"))
(require 'boox-core)
```

and paste them into the `* General configuration` block instead, immediately
after the `(require 'bibtex)` line at `config.org:122`.

- [ ] **Step 4: Verify the resolver works against the real bibliography**

Tangle, start Emacs normally (not `-Q`, the config must load), and evaluate:

```elisp
(a3madkour/supernote--pdf-for-key
 (car (a3madkour/supernote--queue-citekeys)))
```

Expected: an absolute path under `/home/a3madkour/Sync/Zotero/storage/...`.
Confirm it resolves:

```elisp
(file-readable-p (a3madkour/supernote--pdf-for-key
                  (car (a3madkour/supernote--queue-citekeys))))
```

Expected: `t`. Before this task it was `nil` for every key.

If `queue.org` currently has no `:active:` entries, run
`M-x a3madkour/citar-add-to-reading-queue` and pick any paper first.

- [ ] **Step 5: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "fix(bib): resolve macOS library paths on Linux via normalize-library-path"
```

---

## Task 4: `a3madkour/boox--slug`

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — core and tests sections

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest boox-slug-replaces-illegal-characters ()
  (should (equal (a3madkour/boox--slug "A/B:C*D?E\"F<G>H|I") "A-B-C-D-E-F-G-H-I")))

(ert-deftest boox-slug-collapses-whitespace ()
  (should (equal (a3madkour/boox--slug "  Procedural   Content  Generation ")
                 "Procedural-Content-Generation")))

(ert-deftest boox-slug-truncates-to-max-length ()
  (should (equal (length (a3madkour/boox--slug (make-string 100 ?a))) 40))
  (should (equal (length (a3madkour/boox--slug (make-string 100 ?a) 10)) 10)))

(ert-deftest boox-slug-never-emits-the-key-separator ()
  (should-not (string-match-p "--" (a3madkour/boox--slug "Games -- And Play")))
  (should-not (string-match-p "--" (a3madkour/boox--slug "A -  - B"))))

(ert-deftest boox-slug-trims-leading-and-trailing-hyphens ()
  (should (equal (a3madkour/boox--slug "--Hello--") "Hello"))
  (should (equal (a3madkour/boox--slug (concat (make-string 39 ?a) " bbb")) 
                 (make-string 39 ?a))))

(ert-deftest boox-slug-falls-back-for-empty-input ()
  (should (equal (a3madkour/boox--slug "") "untitled"))
  (should (equal (a3madkour/boox--slug nil) "untitled"))
  (should (equal (a3madkour/boox--slug "///") "untitled")))

(ert-deftest boox-slug-preserves-unicode ()
  (should (equal (a3madkour/boox--slug "Réflexions sur جيم") "Réflexions-sur-جيم")))
```

The separator test matters: `a3madkour/boox--key-from-filename` splits on the
first `--`, so a slug containing `--` would corrupt key extraction.

The truncation test's second assertion checks that truncating mid-string cannot
leave a trailing hyphen.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: 7 failures, `void-function a3madkour/boox--slug`.

- [ ] **Step 3: Write the implementation**

New block in the core section, above the footer:

````org
#+begin_src emacs-lisp :tangle "./boox-core.el"
(defun a3madkour/boox--slug (title &optional max-length)
  "Turn TITLE into a filename-safe slug of at most MAX-LENGTH characters.
MAX-LENGTH defaults to 40.  Characters illegal on Android/FAT are replaced
with hyphens, runs of hyphens are collapsed so the result can never contain
`a3madkour/boox-key-separator', and leading/trailing hyphens are trimmed.
Returns \"untitled\" when nothing usable remains."
  (let* ((max (or max-length 40))
         (s (or title ""))
         (s (replace-regexp-in-string "[/\\\\:*?\"<>|]" "-" s))
         (s (replace-regexp-in-string "[[:space:]]+" "-" (string-trim s)))
         (s (replace-regexp-in-string "-+" "-" s))
         (s (if (> (length s) max) (substring s 0 max) s))
         (s (replace-regexp-in-string "\\`-+\\|-+\\'" "" s)))
    (if (string-empty-p s) "untitled" s)))
#+end_src
````

- [ ] **Step 4: Run the tests to verify they pass**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: `Ran 13 tests, 13 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add filename slug helper with tests"
```

---

## Task 5: Key extraction and book keys

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — core and tests sections

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest boox-key-from-filename-extracts-prefix ()
  (should (equal (a3madkour/boox--key-from-filename
                  "madkour2021pcg--Procedural-Content-Gen.pdf")
                 "madkour2021pcg")))

(ert-deftest boox-key-from-filename-ignores-mangled-title-half ()
  (should (equal (a3madkour/boox--key-from-filename
                  "/some/dir/madkour2021pcg--Procedural-Content(annot).pdf")
                 "madkour2021pcg")))

(ert-deftest boox-key-from-filename-uses-first-separator ()
  (should (equal (a3madkour/boox--key-from-filename "key--a--b.pdf") "key")))

(ert-deftest boox-key-from-filename-allows-hyphens-in-key ()
  (should (equal (a3madkour/boox--key-from-filename "madkour-2021-pcg--Title.pdf")
                 "madkour-2021-pcg")))

(ert-deftest boox-key-from-filename-returns-nil-without-separator ()
  (should (null (a3madkour/boox--key-from-filename "Screenshot_20260809.png")))
  (should (null (a3madkour/boox--key-from-filename "--LeadingSeparator.pdf"))))

(ert-deftest boox-book-key-slugs-the-basename ()
  (should (equal (a3madkour/boox--book-key
                  "/home/a3madkour/Sync/Books/1-rules-of-play-game-design.pdf" nil)
                 "1-rules-of-play-game-design")))

(ert-deftest boox-book-key-avoids-collisions ()
  (should (equal (a3madkour/boox--book-key "/x/rules.pdf" '("rules")) "rules-2"))
  (should (equal (a3madkour/boox--book-key "/x/rules.pdf" '("rules" "rules-2"))
                 "rules-3")))

(ert-deftest boox-book-key-never-contains-the-separator ()
  (should-not (string-match-p "--" (a3madkour/boox--book-key "/x/a -- b.pdf" nil))))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: 8 failures for the two undefined functions.

- [ ] **Step 3: Write the implementation**

````org
#+begin_src emacs-lisp :tangle "./boox-core.el"
(defun a3madkour/boox--key-from-filename (filename)
  "Extract the pushed key from FILENAME, or nil if it carries none.
Files are pushed as KEY--TITLE.EXT.  NeoReader appends suffixes to the
title half on export, which is why only the half before the first
separator is trusted."
  (let ((base (file-name-nondirectory (or filename ""))))
    (when (string-match (concat "\\`\\([^/]+?\\)"
                                (regexp-quote a3madkour/boox-key-separator))
                        base)
      (match-string 1 base))))

(defun a3madkour/boox--book-key (file existing-keys)
  "Return a key for book FILE that does not collide with EXISTING-KEYS.
EXISTING-KEYS should include every key already in use, both book keys and
bibliography citekeys, so a book can never shadow a citekey.  Collisions
get a numeric suffix."
  (let* ((root (a3madkour/boox--slug (file-name-base file) 32))
         (key root)
         (n 1))
    (while (member key existing-keys)
      (setq n (1+ n)
            key (format "%s-%d" root n)))
    key))
#+end_src
````

- [ ] **Step 4: Run the tests to verify they pass**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: `Ran 21 tests, 21 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add key extraction and collision-safe book keys"
```

---

## Task 6: Queue entry resolution

Reads `queue.org` and turns each `:active:` entry into a resolved record. Book
keys get written back as `:BOOX_KEY:` on first resolution so they stay stable
even as other books are added — otherwise a collision suffix could shift between
runs and orphan an annotated file.

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — `* Boox` section (commands, tangling to `config.el`)

- [ ] **Step 1: Add the resolver**

New subsection `** Push` in the `* Boox` section:

````org
** Push
#+begin_src emacs-lisp
(defun a3madkour/boox--all-known-keys ()
  "Every key already in use: bibliography citekeys plus assigned book keys.
Uses the public `citar-get-entries' rather than citar internals, whose
signatures have shifted between releases."
  (append (hash-table-keys (citar-get-entries))
          (with-current-buffer (find-file-noselect (a3madkour/org-file "queue.org"))
            (delq nil (org-map-entries
                       (lambda () (org-entry-get nil "BOOX_KEY")) nil 'file)))))

(defun a3madkour/boox--queue-entries ()
  "Return a list of plists describing every :active: entry in queue.org.
Each plist has :key, :source, :title and :kind (either `paper' or `book').
Book entries without a :BOOX_KEY: get one assigned and written back, so the
key stays stable across future runs."
  (require 'citar)
  (with-current-buffer (find-file-noselect (a3madkour/org-file "queue.org"))
    (let ((known (a3madkour/boox--all-known-keys))
          (dirty nil)
          (entries nil))
      (org-map-entries
       (lambda ()
         (let ((citekey (org-entry-get nil "CITEKEY"))
               (reading-file (org-entry-get nil "READING_FILE")))
           (cond
            (citekey
             ;; Always push exactly one record.  A key with no bib entry, or a
             ;; bib entry with no PDF/EPUB attachment, yields :source nil and is
             ;; reported as missing rather than silently vanishing.
             (let* ((entry (ignore-errors (citar-get-entry citekey)))
                    (file (and entry (alist-get "file" entry nil nil #'string=)))
                    (raw (and file
                              (car (seq-filter
                                    (lambda (p) (string-match-p "\\.\\(pdf\\|epub\\)\\'"
                                                                (string-trim p)))
                                    (split-string file ";")))))
                    (source (and raw (or (a3madkour/normalize-library-path raw)
                                         (string-trim raw)))))
               (push (list :key citekey
                           :kind 'paper
                           :source source
                           :title (or (and entry (alist-get "title" entry nil nil #'string=))
                                      citekey))
                     entries)))
            (reading-file
             (let* ((source (expand-file-name reading-file))
                    (key (or (org-entry-get nil "BOOX_KEY")
                             (let ((k (a3madkour/boox--book-key source known)))
                               (org-entry-put nil "BOOX_KEY" k)
                               (setq known (cons k known) dirty t)
                               k))))
               (push (list :key key
                           :kind 'book
                           :source source
                           :title (file-name-base source))
                     entries))))))
       "+active" 'file)
      (when dirty (save-buffer))
      (nreverse entries))))
#+end_src
````

- [ ] **Step 2: Verify against the real queue**

Tangle, restart Emacs normally, add at least one paper and one book to
`queue.org`. For the book, add an entry by hand:

```org
* TODO Read Rules of Play :active:toread:
:PROPERTIES:
:ENERGY: high
:READING_FILE: ~/Sync/Books/1-rules-of-play-game-design-fundamentals.pdf
:END:
```

Then evaluate:

```elisp
(a3madkour/boox--queue-entries)
```

Expected: a list of plists. The paper entry has an absolute `:source` under
`/home/a3madkour/Sync/Zotero/storage/`. The book entry has `:kind book` and a
`:key` of `1-rules-of-play-game-design-fun`.

- [ ] **Step 3: Verify the key was written back**

Re-open `queue.org` and confirm the book entry now carries a `:BOOX_KEY:`
property. Evaluate `(a3madkour/boox--queue-entries)` a second time and confirm
the key is identical — it must not gain a `-2` suffix on the second run.

- [ ] **Step 4: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): resolve active queue entries to source files"
```

---

## Task 7: `a3madkour/boox-push-queue`

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — `** Push` subsection

- [ ] **Step 1: Add the push command**

Append to the `** Push` block:

````org
#+begin_src emacs-lisp
(defun a3madkour/boox--pushed-filename (entry)
  "Filename ENTRY should have inside `a3madkour/boox-reading-directory'."
  (format "%s%s%s.%s"
          (plist-get entry :key)
          a3madkour/boox-key-separator
          (a3madkour/boox--slug (plist-get entry :title))
          (file-name-extension (plist-get entry :source))))

(defun a3madkour/boox--pushed-files ()
  "Files in the reading directory that this command created.
Export artifacts written by NeoReader do not match this pattern and are
left alone; only `a3madkour/boox-import' consumes those."
  (let ((dir (file-name-as-directory a3madkour/boox-reading-directory)))
    (when (file-directory-p dir)
      (seq-filter
       (lambda (f)
         (and (a3madkour/boox--key-from-filename f)
              (member (downcase (or (file-name-extension f) ""))
                      a3madkour/boox-supported-extensions)
              (not (string-match-p "sync-conflict" f))))
       (directory-files dir nil "\\`[^.]" t)))))

(defun a3madkour/boox-push-queue ()
  "Stage every :active: queue entry into the Boox reading directory.
Files whose queue entry is no longer active are removed, which removes them
from the tablet too.  Only files this command created are ever removed."
  (interactive)
  (let* ((dir (file-name-as-directory a3madkour/boox-reading-directory))
         (entries (a3madkour/boox--queue-entries))
         copied skipped removed missing unsupported)
    (unless (file-directory-p dir) (make-directory dir t))
    (dolist (entry entries)
      (let ((src (plist-get entry :source)))
        (cond
         ((or (null src) (not (file-readable-p src)))
          (push (plist-get entry :key) missing))
         ((not (member (downcase (or (file-name-extension src) ""))
                       a3madkour/boox-supported-extensions))
          (push (cons (plist-get entry :key) (file-name-nondirectory src)) unsupported))
         (t
          (let* ((name (a3madkour/boox--pushed-filename entry))
                 (dest (expand-file-name name dir)))
            (if (file-exists-p dest)
                (push (cons (plist-get entry :key) name) skipped)
              (copy-file src dest)
              (push (cons (plist-get entry :key) name) copied)))))))
    (let ((wanted (mapcar #'a3madkour/boox--pushed-filename
                          (seq-filter (lambda (e) (plist-get e :source)) entries))))
      (dolist (f (a3madkour/boox--pushed-files))
        (unless (member f wanted)
          (delete-file (expand-file-name f dir))
          (push f removed))))
    (with-current-buffer (get-buffer-create "*Boox Sync*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Boox reading directory: %s\n\n" dir))
        (insert (format "Copied: %d   Skipped: %d   Removed: %d   Missing: %d   Unsupported: %d\n\n"
                        (length copied) (length skipped) (length removed)
                        (length missing) (length unsupported)))
        (dolist (pair (list (cons "Copied" copied)
                            (cons "Skipped (already present)" skipped)
                            (cons "Removed (no longer active)" removed)
                            (cons "Missing source" missing)
                            (cons "Unsupported format" unsupported)))
          (when (cdr pair)
            (insert (car pair) ":\n")
            (dolist (it (nreverse (cdr pair)))
              (insert (format "  %s\n" (if (consp it) (format "%s  (%s)" (cdr it) (car it)) it))))
            (insert "\n"))))
      (special-mode))
    (display-buffer "*Boox Sync*")
    (message "Boox: %d copied, %d skipped, %d removed, %d missing, %d unsupported"
             (length copied) (length skipped) (length removed)
             (length missing) (length unsupported))))
#+end_src
````

- [ ] **Step 2: Verify the push end to end**

Tangle, restart Emacs, run `M-x a3madkour/boox-push-queue`.

Expected: `*Boox Sync*` shows the paper and book copied. Confirm on disk:

```bash
ls -la ~/Boox/reading/
```

Expected: filenames shaped `citekey--Title.pdf` and
`1-rules-of-play-game-design-fun--1-rules-of-play-game-desig.pdf`.

- [ ] **Step 3: Verify the removal path**

Mark the book's queue entry `DONE` (dropping the `:active:` tag), re-run
`M-x a3madkour/boox-push-queue`.

Expected: the summary reports it under "Removed", and `ls ~/Boox/reading/` no
longer shows it.

- [ ] **Step 4: Verify export artifacts survive a push**

```bash
touch "~/Boox/reading/somekey--Title(annot).pdf"
touch ~/Boox/reading/notes-export.txt
```

Run `M-x a3madkour/boox-push-queue` again. Expected: `notes-export.txt` is
untouched (no key separator, so not a pushed file). The `(annot)` file **is**
matched by the key pattern and will be removed if `somekey` is not active —
which is correct, since a stale annotated file left in the reading directory has
already been imported or was never pushed. Confirm this matches your
expectation before proceeding; if not, tighten `a3madkour/boox--pushed-files` to
also exclude names containing the annotated marker found in P3.

```bash
rm -f ~/Boox/reading/notes-export.txt
```

- [ ] **Step 5: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add boox-push-queue command"
```

---

## Task 8: Highlight parser

**Blocked on P3.** The fixture must be a real NeoReader export.

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — core and tests sections
- Create: `~/emacs-configs/custom/tests/fixtures/neoreader-export.txt` (from P3)

- [ ] **Step 1: Confirm the fixture is in place**

```bash
cat ~/emacs-configs/custom/tests/fixtures/neoreader-export.txt
```

Expected: the real export text captured in P3. Do not proceed without it.

- [ ] **Step 2: Write the failing tests**

Adjust the three expected values in `boox-parse-fixture` to match your actual
fixture — the count of highlights, the first highlight's page, and a substring
of its text. Everything else is format-independent.

```elisp
(defconst boox-test-fixture-file
  (expand-file-name "~/emacs-configs/custom/tests/fixtures/neoreader-export.txt"))

(defun boox-test--fixture ()
  (with-temp-buffer
    (insert-file-contents boox-test-fixture-file)
    (buffer-string)))

(ert-deftest boox-parse-fixture ()
  (let ((result (a3madkour/boox--parse-highlights (boox-test--fixture))))
    ;; ADJUST these three to match tests/fixtures/neoreader-export.txt
    (should (= (length result) 3))
    (should (= (plist-get (car result) :page) 1))
    (should (string-match-p "." (plist-get (car result) :text)))))

(ert-deftest boox-parse-every-entry-has-page-and-text ()
  (dolist (h (a3madkour/boox--parse-highlights (boox-test--fixture)))
    (should (integerp (plist-get h :page)))
    (should (stringp (plist-get h :text)))
    (should-not (string-empty-p (plist-get h :text)))))

(ert-deftest boox-parse-empty-input-yields-nothing ()
  (should (null (a3madkour/boox--parse-highlights "")))
  (should (null (a3madkour/boox--parse-highlights "   \n\n  "))))

(ert-deftest boox-parse-malformed-input-yields-nothing ()
  (should (null (a3madkour/boox--parse-highlights
                 "no pages no separators just prose"))))

(ert-deftest boox-parse-drops-blocks-without-text ()
  (should (null (a3madkour/boox--parse-highlights
                 "Page 5\n\n--------------------\n\nPage 9\n\n"))))
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: 5 failures, `void-function a3madkour/boox--parse-highlights`.

- [ ] **Step 4: Write the implementation**

The three regexps are `defvar`s precisely so they can be retuned against the
fixture without touching the parsing logic.

````org
#+begin_src emacs-lisp :tangle "./boox-core.el"
(defvar a3madkour/boox-export-separator-regexp "^[-=_]\\{5,\\}[ \t]*$"
  "Regexp matching the line NeoReader writes between annotation blocks.")

(defvar a3madkour/boox-export-page-regexp "\\(?:[Pp]age\\|P\\.\\)[ \t]*\\([0-9]+\\)"
  "Regexp whose first group captures the page number within a block.")

(defvar a3madkour/boox-export-note-regexp
  "^[ \t]*\\(?:Annotations?\\|Notes?\\|Comment\\)[::][ \t]*"
  "Regexp matching the label that introduces a typed note within a block.")

(defvar a3madkour/boox-export-text-regexp
  "^[ \t]*\\(?:Original Text\\|Highlight\\|Text\\)[::][ \t]*"
  "Regexp matching the label that introduces highlighted text within a block.")

(defun a3madkour/boox--parse-block (block)
  "Parse one BLOCK of a NeoReader export into a plist, or nil.
The plist has :page, :text and :note.  A block without a page number or
without highlighted text is discarded."
  (let ((page (when (string-match a3madkour/boox-export-page-regexp block)
                (string-to-number (match-string 1 block))))
        text note)
    (when page
      (let* ((lines (split-string block "\n"))
             (state 'text)
             (text-lines nil)
             (note-lines nil))
        (dolist (line lines)
          (cond
           ((string-match-p a3madkour/boox-export-note-regexp line)
            (setq state 'note)
            (let ((rest (replace-regexp-in-string
                         a3madkour/boox-export-note-regexp "" line)))
              (unless (string-empty-p (string-trim rest))
                (push rest note-lines))))
           ((string-match-p a3madkour/boox-export-text-regexp line)
            (setq state 'text)
            (let ((rest (replace-regexp-in-string
                         a3madkour/boox-export-text-regexp "" line)))
              (unless (string-empty-p (string-trim rest))
                (push rest text-lines))))
           ((string-match-p a3madkour/boox-export-page-regexp line) nil)
           ((string-empty-p (string-trim line)) nil)
           ((eq state 'note) (push line note-lines))
           (t (push line text-lines))))
        (setq text (string-trim (mapconcat #'identity (nreverse text-lines) " "))
              note (string-trim (mapconcat #'identity (nreverse note-lines) " "))))
      (unless (string-empty-p text)
        (list :page page
              :text text
              :note (unless (string-empty-p note) note))))))

(defun a3madkour/boox--parse-highlights (content)
  "Parse NeoReader export CONTENT into a list of (:page :text :note) plists.
Returns nil when nothing parses, which callers must report rather than
writing an empty highlight section."
  (when (and content (stringp content))
    (delq nil (mapcar #'a3madkour/boox--parse-block
                      (split-string content
                                    a3madkour/boox-export-separator-regexp
                                    t)))))
#+end_src
````

- [ ] **Step 5: Run the tests, retuning the regexps until they pass**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: `Ran 26 tests, 26 results as expected`.

If `boox-parse-fixture` fails, inspect what the parser actually saw before
changing any logic:

```bash
emacs -Q --batch -L ~/emacs-configs/custom -l boox-core --eval \
  '(with-temp-buffer
     (insert-file-contents "~/emacs-configs/custom/tests/fixtures/neoreader-export.txt")
     (pp (split-string (buffer-string) a3madkour/boox-export-separator-regexp t)))'
```

If the blocks are wrong, fix `a3madkour/boox-export-separator-regexp`. If the
blocks are right but pages are nil, fix the page regexp. If pages are right but
text is polluted with labels, fix the two label regexps.

- [ ] **Step 6: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org \
        emacs-configs/custom/tests/fixtures/neoreader-export.txt
git commit -m "feat(boox): parse NeoReader annotation exports"
```

---

## Task 9: Import scan and review buffer

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — new `** Import` subsection

- [ ] **Step 1: Add the scanner**

````org
** Import
#+begin_src emacs-lisp
(defvar a3madkour/boox-annotated-marker-regexp "(annot\\|_annot\\|-annot"
  "Regexp identifying NeoReader's annotated-PDF exports by filename.
Set from the actual export filename recorded during device verification P3.")

(defun a3madkour/boox--annotated-p (file)
  "Non-nil when FILE looks like a NeoReader annotated-PDF export."
  (string-match-p a3madkour/boox-annotated-marker-regexp
                  (file-name-nondirectory file)))

(defun a3madkour/boox--scan-inbox ()
  "Return a list of candidate plists for every importable file found.
Each plist has :file, :key, :kind (`pdf' or `text'), :status and :selected."
  (let (candidates)
    (dolist (dir a3madkour/boox-inbox-directories)
      (when (file-directory-p dir)
        (dolist (f (directory-files dir t "\\`[^.]" t))
          (let* ((name (file-name-nondirectory f))
                 (ext (downcase (or (file-name-extension f) "")))
                 (key (a3madkour/boox--key-from-filename f)))
            (cond
             ((string-match-p "sync-conflict" name) nil)
             ((file-directory-p f) nil)
             ((and (string= ext "pdf") (not (a3madkour/boox--annotated-p f))) nil)
             ((not (member ext '("pdf" "txt" "html" "md"))) nil)
             ((a3madkour/boox--already-imported-p f)
              (push (list :file f :key key :kind (if (string= ext "pdf") 'pdf 'text)
                          :status 'already-imported :selected nil)
                    candidates))
             ((null key)
              (push (list :file f :key nil :kind (if (string= ext "pdf") 'pdf 'text)
                          :status 'no-key :selected nil)
                    candidates))
             (t
              (push (list :file f :key key
                          :kind (if (string= ext "pdf") 'pdf 'text)
                          :status 'ready :selected t)
                    candidates)))))))
    (nreverse candidates)))

(defun a3madkour/boox--already-imported-p (file)
  "Non-nil when FILE has already been consumed, matched by name and size."
  (let ((archived (expand-file-name (file-name-nondirectory file)
                                    a3madkour/boox-archive-directory)))
    (and (file-exists-p archived)
         (= (file-attribute-size (file-attributes archived))
            (file-attribute-size (file-attributes file))))))
#+end_src
````

- [ ] **Step 2: Add the review buffer**

````org
#+begin_src emacs-lisp
(defvar a3madkour/boox--candidates nil
  "Candidate list backing the current *Boox Import* buffer.")

(defvar a3madkour/boox-import-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'a3madkour/boox-import-toggle)
    (define-key map (kbd "x")   #'a3madkour/boox-import-execute)
    (define-key map (kbd "g")   #'a3madkour/boox-import)
    (define-key map (kbd "q")   #'quit-window)
    map)
  "Keymap for `a3madkour/boox-import-mode'.")

(define-derived-mode a3madkour/boox-import-mode special-mode "Boox-Import"
  "Review buffer for pending Boox imports.")

(defun a3madkour/boox--status-line (candidate)
  "One display line for CANDIDATE."
  (pcase (plist-get candidate :status)
    ('ready (format "→ key: %s  %s"
                    (plist-get candidate :key)
                    (if (eq (plist-get candidate :kind) 'pdf)
                        "annotated PDF"
                      (format "%d highlights parsed"
                              (length (a3madkour/boox--parse-highlights
                                       (a3madkour/boox--file-contents
                                        (plist-get candidate :file))))))))
    ('no-key "→ no key in filename  (left in place)")
    ('already-imported "→ already imported  (left in place)")))

(defun a3madkour/boox--file-contents (file)
  "Return the contents of FILE as a string."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun a3madkour/boox--render ()
  "Redraw the *Boox Import* buffer from `a3madkour/boox--candidates'."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (format "Boox Import — %d files\n\n"
                    (length a3madkour/boox--candidates)))
    (cl-loop for c in a3madkour/boox--candidates
             for i from 0
             do (insert (format " [%s] %s\n     %s\n"
                                (if (plist-get c :selected) "x" " ")
                                (file-name-nondirectory (plist-get c :file))
                                (a3madkour/boox--status-line c)))
             (put-text-property (line-beginning-position -1) (point) 'boox-index i))
    (insert "\n RET toggle   x execute   g refresh   q abort\n")
    (goto-char (point-min))))

(defun a3madkour/boox-import-toggle ()
  "Toggle selection of the candidate at point."
  (interactive)
  (when-let ((i (get-text-property (point) 'boox-index)))
    (let ((c (nth i a3madkour/boox--candidates)))
      (when (eq (plist-get c :status) 'ready)
        (setf (nth i a3madkour/boox--candidates)
              (plist-put c :selected (not (plist-get c :selected))))
        (let ((pos (point)))
          (a3madkour/boox--render)
          (goto-char (min pos (point-max))))))))

(defun a3madkour/boox-import ()
  "Scan the Boox inbox and present pending imports for review."
  (interactive)
  (setq a3madkour/boox--candidates (a3madkour/boox--scan-inbox))
  (with-current-buffer (get-buffer-create "*Boox Import*")
    (a3madkour/boox-import-mode)
    (a3madkour/boox--render))
  (pop-to-buffer "*Boox Import*"))
#+end_src
````

- [ ] **Step 3: Verify the review buffer renders**

Tangle, restart Emacs. Stage fake exports so the scanner has something to find —
substitute a real citekey from your queue for `CITEKEY` below:

```bash
mkdir -p ~/Boox/archive
cp ~/Boox/reading/CITEKEY--*.pdf "~/Boox/reading/CITEKEY--Title(annot).pdf"
cp ~/emacs-configs/custom/tests/fixtures/neoreader-export.txt ~/Boox/reading/CITEKEY--Title.txt
touch ~/Boox/reading/Screenshot_20260809.png
```

Run `M-x a3madkour/boox-import`.

Expected: three lines. The `(annot).pdf` and `.txt` show `[x]` with the citekey
resolved and a highlight count on the text line; the PNG is skipped entirely (it
is not in the allowed extension list). `RET` toggles the selected ones, `q`
quits without writing anything.

- [ ] **Step 4: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add import scanner and review buffer"
```

---

## Task 10: Import execution

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — `** Import` subsection

- [ ] **Step 1: Add note resolution and the book-note creator**

````org
#+begin_src emacs-lisp
(defun a3madkour/boox--source-for-key (key)
  "Return the original source file for KEY, paper or book."
  (or (when-let ((entry (ignore-errors (citar-get-entry key))))
        (when-let* ((file (alist-get "file" entry nil nil #'string=))
                    (raw (car (seq-filter
                               (lambda (p) (string-match-p "\\.\\(pdf\\|epub\\)\\'"
                                                           (string-trim p)))
                               (split-string file ";")))))
          (or (a3madkour/normalize-library-path raw) (string-trim raw))))
      (plist-get (seq-find (lambda (e) (equal (plist-get e :key) key))
                           (a3madkour/boox--queue-entries))
                 :source)))

(defun a3madkour/boox--ensure-book-note (key source)
  "Return the ref-note file for book KEY, creating it against SOURCE if absent."
  (let ((file (expand-file-name (concat key ".org") org-ref-notes)))
    (unless (file-exists-p file)
      (with-current-buffer (find-file-noselect file)
        (insert (format ":PROPERTIES:\n:ID: %s\n:NOTER_DOCUMENT: %s\n:ORIGINAL_DOCUMENT: %s\n:DATE_CREATED: %s\n:LAST_MODIFIED: %s\n:END:\n#+title: %s\n#+filetags: :Ref:Book:\n\n"
                        (org-id-new)
                        source source
                        (format-time-string "[%Y-%m-%d %a]")
                        (format-time-string "[%Y-%m-%d %a]")
                        (file-name-base source)))
        (save-buffer)))
    file))

(defun a3madkour/boox--note-for-key (key)
  "Return the ref-note file for KEY, creating it if necessary."
  (let ((citar-note (expand-file-name (concat key ".org") org-ref-notes)))
    (cond
     ((file-exists-p citar-note) citar-note)
     ((ignore-errors (citar-get-entry key))
      (citar-create-note key)
      citar-note)
     (t (a3madkour/boox--ensure-book-note key (a3madkour/boox--source-for-key key))))))

(defun a3madkour/boox--annotated-destination (source)
  "Path the annotated copy of SOURCE should occupy."
  (expand-file-name
   (format "%s%s.%s"
           (file-name-base source)
           a3madkour/boox-annotated-suffix
           (file-name-extension source))
   (file-name-directory source)))
#+end_src
````

- [ ] **Step 2: Add the execute command**

````org
#+begin_src emacs-lisp
(defun a3madkour/boox--file-annotated-pdf (key file)
  "Copy annotated export FILE beside KEY's source and record the properties.
Returns the destination path, or nil when the source cannot be resolved."
  (when-let* ((source (a3madkour/boox--source-for-key key))
              (dest (a3madkour/boox--annotated-destination source)))
    (when (or (not (file-exists-p dest))
              (y-or-n-p (format "Overwrite existing %s? "
                                (file-name-nondirectory dest))))
      (copy-file file dest t)
      (with-current-buffer (find-file-noselect (a3madkour/boox--note-for-key key))
        (goto-char (point-min))
        (org-entry-put nil "ORIGINAL_DOCUMENT" source)
        (org-entry-put nil "ANNOTATED_DOCUMENT" dest)
        (org-entry-put nil "NOTER_DOCUMENT" dest)
        (org-entry-put nil "LAST_MODIFIED" (format-time-string "[%Y-%m-%d %a]"))
        (save-buffer))
      dest)))

(defun a3madkour/boox--insert-highlights (key highlights)
  "Insert HIGHLIGHTS into KEY's ref note under a `Tablet Highlights' heading.
Existing content under that heading is replaced, so re-importing a longer
export supersedes the shorter one instead of duplicating it."
  (with-current-buffer (find-file-noselect (a3madkour/boox--note-for-key key))
    (org-with-wide-buffer
     (goto-char (point-min))
     (if (re-search-forward "^\\* Tablet Highlights[ \t]*$" nil t)
         (let ((start (line-beginning-position)))
           (org-end-of-subtree t t)
           (delete-region start (point))
           (goto-char start))
       (goto-char (point-max))
       (unless (bolp) (insert "\n")))
     (insert "* Tablet Highlights\n")
     (dolist (h highlights)
       (insert (format "** %s\n" (truncate-string-to-width
                                 (plist-get h :text) 70 nil nil "…")))
       (when (plist-get h :page)
         (insert (format ":PROPERTIES:\n:NOTER_PAGE: %d\n:END:\n" (plist-get h :page))))
       (insert (format "%s\n" (plist-get h :text)))
       (when (plist-get h :note)
         (insert (format "\n%s\n" (plist-get h :note))))
       (insert "\n"))
     (org-entry-put (point-min) "LAST_MODIFIED" (format-time-string "[%Y-%m-%d %a]"))
     (save-buffer))))

(defun a3madkour/boox-import-execute ()
  "File every selected candidate, then archive the consumed exports."
  (interactive)
  (unless (file-directory-p a3madkour/boox-archive-directory)
    (make-directory a3madkour/boox-archive-directory t))
  (let ((selected (seq-filter (lambda (c) (plist-get c :selected))
                              a3madkour/boox--candidates))
        (results nil))
    (dolist (c selected)
      (let ((key (plist-get c :key))
            (file (plist-get c :file)))
        (pcase (plist-get c :kind)
          ('pdf
           (if-let ((dest (a3madkour/boox--file-annotated-pdf key file)))
               (progn (push (format "%s → %s" key (abbreviate-file-name dest)) results)
                      (rename-file file (expand-file-name
                                         (file-name-nondirectory file)
                                         a3madkour/boox-archive-directory)
                                   t))
             (push (format "%s → SKIPPED, source unresolved" key) results)))
          ('text
           (let ((highlights (a3madkour/boox--parse-highlights
                              (a3madkour/boox--file-contents file))))
             (if (null highlights)
                 (push (format "%s → 0 highlights parsed, NOT imported" key) results)
               (a3madkour/boox--insert-highlights key highlights)
               (push (format "%s → %d highlights" key (length highlights)) results)
               (rename-file file (expand-file-name
                                  (file-name-nondirectory file)
                                  a3madkour/boox-archive-directory)
                            t)))))))
    (message "Boox import: %s" (string-join (nreverse results) "; "))
    (a3madkour/boox-import)))
#+end_src
````

Note the deliberate asymmetry: a text export that parses to zero highlights is
**not** archived, so it stays visible in the review buffer as a signal that the
parser regexps need retuning.

- [ ] **Step 3: Verify execution end to end**

Tangle, restart Emacs, re-stage the fake exports from Task 9 Step 3, run
`M-x a3madkour/boox-import`, then press `x`.

Expected, in order:

1. The annotated PDF appears beside the original:
   ```bash
   ls ~/Sync/Zotero/storage/*/*-annotated.pdf
   ```
2. The ref note for that citekey has `:NOTER_DOCUMENT:` pointing at the
   `-annotated.pdf`, plus `:ORIGINAL_DOCUMENT:` and `:ANNOTATED_DOCUMENT:`.
3. The ref note has a `* Tablet Highlights` heading with one subheading per
   highlight, each carrying `:NOTER_PAGE:`.
4. Both consumed files are now in `~/Boox/archive/` and gone from
   `~/Boox/reading/`.

- [ ] **Step 4: Verify idempotency**

Copy the same two files back into `~/Boox/reading/` and run
`M-x a3madkour/boox-import`.

Expected: both show `already imported (left in place)` with `[ ]` unchecked.

- [ ] **Step 5: Verify org-noter opens the annotated copy**

Open the ref note, `M-x org-noter`.

Expected: pdf-tools opens the `-annotated.pdf` and the highlights are visible on
the page. Click a `Tablet Highlights` subheading and confirm org-noter jumps to
its recorded page.

- [ ] **Step 6: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): execute imports into ref notes"
```

---

## Task 11: Toggle command, nov.el, and keybindings

**Files:**
- Modify: `~/emacs-configs/custom/config.org` — `** Import` subsection, org-noter section near line 3034, which-key section near line 4403
- Modify: `~/emacs-configs/custom/config.org:1563-1576` (`a3madkour/citar-org-format-note`)

- [ ] **Step 1: Add the toggle command**

````org
#+begin_src emacs-lisp
(defun a3madkour/boox-toggle-noter-document ()
  "Swap :NOTER_DOCUMENT: between the original and the annotated copy."
  (interactive)
  (let* ((current (org-entry-get (point-min) "NOTER_DOCUMENT"))
         (original (org-entry-get (point-min) "ORIGINAL_DOCUMENT"))
         (annotated (org-entry-get (point-min) "ANNOTATED_DOCUMENT")))
    (cond
     ((null annotated) (user-error "No annotated copy recorded for this note"))
     ((null original) (user-error "No original document recorded for this note"))
     (t (let ((next (if (equal current annotated) original annotated)))
          (org-entry-put (point-min) "NOTER_DOCUMENT" next)
          (save-buffer)
          (message "NOTER_DOCUMENT → %s"
                   (if (equal next annotated) "annotated" "original")))))))
#+end_src
````

- [ ] **Step 2: Emit `ORIGINAL_DOCUMENT` from the citar note formatter**

In `a3madkour/citar-org-format-note`, at `config.org:1567-1570`, replace:

```elisp
		(insert ":NOTER_DOCUMENT: ")
		(when note-path-clean
		  (insert (or (a3madkour/normalize-library-path note-path-clean)
					  note-path-clean)))
		(insert "\n")
```

with:

```elisp
		(let ((doc (and note-path-clean
						(or (a3madkour/normalize-library-path note-path-clean)
							note-path-clean))))
		  (insert ":NOTER_DOCUMENT: ")
		  (when doc (insert doc))
		  (insert "\n")
		  (insert ":ORIGINAL_DOCUMENT: ")
		  (when doc (insert doc))
		  (insert "\n"))
```

- [ ] **Step 3: Add nov.el for EPUB**

In the org-noter section near `config.org:3034`, after the `org-noter`
`use-package` block:

````org
#+begin_src emacs-lisp
(use-package nov
  :mode ("\\.epub\\'" . nov-mode))
#+end_src
````

This lets org-noter open EPUBs for manual noting. Imported EPUB highlights stay
non-positional because reflow makes exported page numbers meaningless.

- [ ] **Step 4: Add keybindings**

In the which-key section near `config.org:4403`, following the existing
`org-noter` entries:

```elisp
 '(a3madkour/boox-push-queue :which-key "boox push queue")
 '(a3madkour/boox-import :which-key "boox import")
 '(a3madkour/boox-toggle-noter-document :which-key "boox toggle document")
```

Match the surrounding `general-define-key` block's prefix and indentation
exactly — read the ten lines above the insertion point before writing.

- [ ] **Step 5: Verify the toggle**

Tangle, restart Emacs, open the ref note imported in Task 10, run
`M-x a3madkour/boox-toggle-noter-document` twice.

Expected: `:NOTER_DOCUMENT:` flips to `:ORIGINAL_DOCUMENT:`'s value, then back to
`:ANNOTATED_DOCUMENT:`'s. Message reports which one is active. Running it on a
note with no annotated copy reports a clean `user-error`, not a backtrace.

- [ ] **Step 6: Verify a fresh citar note is toggle-ready**

Run `M-x citar-open-notes` on a paper with no existing note and create one.

Expected: the new note has both `:NOTER_DOCUMENT:` and `:ORIGINAL_DOCUMENT:`
with the same absolute path.

- [ ] **Step 7: Run the full suite one last time**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch -L ~/emacs-configs/custom -l ert \
  -l ~/emacs-configs/custom/boox-core.el \
  -l ~/emacs-configs/custom/tests/boox-tests.el \
  -f ert-run-tests-batch-and-exit
```

Expected: `Ran 26 tests, 26 results as expected`.

- [ ] **Step 8: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add document toggle, nov.el, and keybindings"
```

---

## Full round-trip acceptance

- [ ] **Add a paper to the queue** — `M-x a3madkour/citar-add-to-reading-queue`
- [ ] **Push** — `M-x a3madkour/boox-push-queue`, confirm it lands on the tablet
- [ ] **Read and annotate** in NeoReader, export both artifacts
- [ ] **Wait for Syncthing**, confirm the exports appear in `~/Boox/reading/`
- [ ] **Import** — `M-x a3madkour/boox-import`, review, press `x`
- [ ] **Open in org-noter** from the ref note, confirm highlights are visible and the `Tablet Highlights` subheadings jump to the right pages
- [ ] **Mark the queue entry done**, run `M-x a3madkour/boox-push-queue`, confirm the file leaves the tablet
