# Boox Retire-on-Advance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a ref note's `PROGRESS` advances from `highlighting` to `ref-notes`, import any outstanding annotations, delete the paper from the Boox, and close its reading-queue entry — never leaving the tablet copy as the only copy.

**Architecture:** One thin interactive orchestrator (`boox-retire-document`) over five single-purpose helpers, plus a policy function that decides which pipeline transition fires it. The per-file import work is first extracted out of `boox-import-execute` so retirement reuses it rather than reimplementing it.

**Tech Stack:** Emacs Lisp, org-babel literate tangling, ERT, org-mode, pdf-tools, Syncthing.

---

## Context an implementer needs

`/Stuff/a3madkour/dotfiles/emacs-configs/custom/config.org` is the **single source of truth**. `#+property: header-args:emacs-lisp :tangle yes` (config.org:4) tangles `emacs-lisp` blocks into `config.el`; blocks with explicit `:tangle "./boox-core.el"` go there instead. `init.el:43` runs `org-babel-load-file`.

**`config.el`, `boox-core.el`, and `tests/boox-tests.el` are generated, untracked, and must never be edited or committed.** Only `config.org` (and occasionally `tests/run.sh`) is staged.

The repo carries unrelated uncommitted changes in `.doom.d/`, `default-persp`, `emacs-configs/custom/bookmarks`, `.config/xmonad/`. **Never stage those.**

`~/emacs-configs` is a symlink to `/Stuff/a3madkour/dotfiles/emacs-configs`.

**Two commands used throughout:**

```bash
# Tangle
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'

# Full suite (142 tests currently, all passing)
cd /Stuff/a3madkour/dotfiles/emacs-configs/custom && ./tests/run.sh
```

**Existing pieces this builds on**, all in the `* Boox` section of config.org:

| Function | Role |
| --- | --- |
| `a3madkour/boox--reading-file-for-key` | reading-dir file for a key, or nil |
| `a3madkour/boox--file-annotated-pdf` | copy to `<original>-annotated.pdf`, with loss guard |
| `a3madkour/boox--pdf-annotations` | highlights + ink via pdf-tools |
| `a3madkour/boox--insert-highlights` | write `* Tablet Highlights` |
| `a3madkour/boox--record-documents` | write the three document properties + hash |
| `a3madkour/boox--file-sha256` | content hash |
| `a3madkour/boox--source-for-key` | library original for a key |
| `a3madkour/boox--annotation-summary` | "1 highlight + handwriting on 2 pages" |

`a3madkour/org-roam-advance-pipeline` is at config.org:3811 and walks `PROGRESS` through `none → highlighting → ref-notes → main-notes → done`.

## File Structure

| File | Responsibility | Generated? |
| --- | --- | --- |
| `config.org` — `* Boox` / `** Import` | the five helpers + orchestrator | source |
| `config.org` — beside `advance-pipeline` (~:3811) | `boox--pipeline-advanced` + the one-line hook | source |
| `config.org` — `** Tests` | ERT cases | source |
| `boox-core.el` | **unchanged** — nothing here is pure enough to belong there | generated |

---

## Task 1: Extract the per-file import step

Pure refactor. Behaviour must not change.

**Files:**
- Modify: `config.org` — `a3madkour/boox-import-execute` (currently at config.org:2669)

- [ ] **Step 1: Add the extracted function immediately above `boox-import-execute`**

```elisp
(defun a3madkour/boox--import-pdf (key file)
  "Import annotated FILE for KEY into the library and the ref note.
Returns a summary string, or nil when the copy was declined — either
because the source could not be resolved or because the annotation-loss
guard was refused.  Shared by `a3madkour/boox-import-execute' and
`a3madkour/boox-retire-document' so there is one implementation of what
importing a PDF means."
  (when-let ((dest (a3madkour/boox--file-annotated-pdf key file)))
    (let ((marks (a3madkour/boox--pdf-annotations file)))
      ;; Highlights first: inserting them may create the ref note, and note
      ;; creation rewrites the file wholesale.  Properties go last so nothing
      ;; can clobber them.
      (when marks (a3madkour/boox--insert-highlights key marks))
      (a3madkour/boox--record-documents
       key (a3madkour/boox--source-for-key key) dest
       (a3madkour/boox--file-sha256 file))
      (format "%s → %s, %s" key (abbreviate-file-name dest)
              (a3madkour/boox--annotation-summary marks)))))
```

- [ ] **Step 2: Replace the `'pdf` branch of `boox-import-execute` to call it**

Replace exactly this:

```elisp
          ('pdf
           (if-let ((dest (a3madkour/boox--file-annotated-pdf key file)))
               (let ((marks (a3madkour/boox--pdf-annotations file)))
                 ;; Highlights first: inserting them may create the ref note,
                 ;; and note creation rewrites the file wholesale.  Properties
                 ;; go last so nothing can clobber them.
                 (when marks (a3madkour/boox--insert-highlights key marks))
                 (a3madkour/boox--record-documents
                  key (a3madkour/boox--source-for-key key) dest
                  (a3madkour/boox--file-sha256 file))
                 (push (format "%s → %s, %s" key (abbreviate-file-name dest)
                               (a3madkour/boox--annotation-summary marks))
                       results))
             (push (format "%s → SKIPPED, source unresolved" key) results)))
```

with:

```elisp
          ('pdf
           (push (or (a3madkour/boox--import-pdf key file)
                     (format "%s → SKIPPED, source unresolved" key))
                 results))
```

- [ ] **Step 3: Tangle and confirm the import path is unchanged**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
```

Then re-run the existing end-to-end import harness to prove identical behaviour. Build it fresh:

```bash
SP=/tmp/claude-1000/-Stuff-a3madkour-Sync-Workspace/10f323dd-8bca-497f-9d00-fa0d4f02dbbe/scratchpad/t1
rm -rf $SP && mkdir -p $SP/notes $SP/reading $SP/archive
D=/Stuff/a3madkour/dotfiles/emacs-configs/custom/straight/build/pdf-tools
cp "/home/a3madkour/Sync/Zotero/storage/43WBIBMB/Abramsky and Tzevelekos - 2010 - Introduction to Categories and Categorical Logic.pdf" $SP/original.pdf
cp ~/Boox/reading/.stversions/*20260813-105306.pdf "$SP/reading/abramskyIntroductionCategoriesCategorical2010--Intro.pdf"
cat > $SP/h.el <<EOF
(add-to-list 'load-path "$D")
(require 'boox-core)(require 'org)(require 'subr-x)(require 'seq)(require 'cl-lib)(require 'pdf-info)
(setq pdf-info-epdfinfo-program "$D/epdfinfo")
(provide 'citar)
(defun citar-get-entry (k) (list (cons "file" "$SP/original.pdf") (cons "title" "Intro")))
(defun citar-get-entries () (make-hash-table :test 'equal))
(defun citar-create-note (k &optional e) nil)
(defun a3madkour/org-file (p) (expand-file-name p "$SP"))
(setq org-ref-notes "$SP/notes")
(with-temp-buffer (insert-file-contents "~/emacs-configs/custom/config.el") (goto-char (point-min))
  (condition-case nil (while t (let ((f (read (current-buffer))))
    (when (and (consp f) (memq (car f) '(defun defvar defcustom defconst define-derived-mode))
               (string-match-p "boox" (format "%s" (cadr f)))) (eval f t)))) (end-of-file nil)))
(setq a3madkour/boox-reading-directory "$SP/reading/"
      a3madkour/boox-inbox-directories (list "$SP/reading/")
      a3madkour/boox-archive-directory "$SP/archive/")
(setq a3madkour/boox--candidates (a3madkour/boox--scan-inbox))
(cl-letf (((symbol-function 'a3madkour/boox-import) (lambda () nil))
          ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
          ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
  (a3madkour/boox-import-execute))
(message "NOTE: %s" (with-temp-buffer
  (insert-file-contents "$SP/notes/abramskyIntroductionCategoriesCategorical2010.org")
  (buffer-substring (point-min) (min (point-max) 400))))
EOF
emacs -Q --batch -L ~/emacs-configs/custom -l $SP/h.el 2>&1 | grep -E "Boox import|NOTER_DOCUMENT|ANNOTATED_DOCUMENT|BOOX_IMPORTED_SHA"
```

Expected: a `Boox import: … → …-annotated.pdf, 1 highlight + handwriting on 2 pages` line, and the note showing `NOTER_DOCUMENT`, `ANNOTATED_DOCUMENT` (both the annotated path) and `BOOX_IMPORTED_SHA`.

- [ ] **Step 4: Run the full suite**

```bash
cd /Stuff/a3madkour/dotfiles/emacs-configs/custom && ./tests/run.sh 2>&1 | tail -2
```
Expected: `Ran 142 tests, 142 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "refactor(boox): extract boox--import-pdf from import-execute"
```

---

## Task 2: `boox--note-key`, and refactor refresh onto it

**Files:**
- Modify: `config.org` — `** Import`, and `a3madkour/boox-refresh-document`
- Modify: `config.org` — `** Tests`

- [ ] **Step 1: Write the failing tests**

Append to the `** Tests` block:

```elisp
(ert-deftest boox-note-key-prefers-boox-key-property ()
  (let ((f (make-temp-file "boox-note-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert ":PROPERTIES:\n:BOOX_KEY: rules-of-play\n:END:\n#+title: X\n"))
          (with-current-buffer (find-file-noselect f)
            (should (equal (a3madkour/boox--note-key) "rules-of-play"))))
      (ignore-errors (delete-file f)))))

(ert-deftest boox-note-key-falls-back-to-filename ()
  (let* ((dir (make-temp-file "boox-notes-" t))
         (f (expand-file-name "smith2020.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file f (insert "#+title: X\n"))
          (with-current-buffer (find-file-noselect f)
            (should (equal (a3madkour/boox--note-key) "smith2020"))))
      (ignore-errors (delete-directory dir t)))))

(ert-deftest boox-note-key-nil-without-a-file ()
  (with-temp-buffer
    (org-mode)
    (should (null (a3madkour/boox--note-key)))))
```

- [ ] **Step 2: Run the suite and confirm the three new tests fail**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
cd /Stuff/a3madkour/dotfiles/emacs-configs/custom && ./tests/run.sh 2>&1 | tail -6
```
Expected: `Ran 145 tests`, 3 failing with `void-function a3madkour/boox--note-key`.

**Note:** `boox-tests.el` loads only `boox-core.el`, and `boox--note-key` tangles to `config.el`. Add this line to the **`** Tests` block preamble**, immediately after `(require 'boox-core)`, so the config-side functions are available to ERT:

```elisp
;; Config-side Boox functions live in the generated config.el, which cannot be
;; loaded wholesale in batch.  Evaluate just the boox forms out of it.
(let ((cfg (expand-file-name "~/emacs-configs/custom/config.el")))
  (when (file-readable-p cfg)
    (with-temp-buffer
      (insert-file-contents cfg)
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (and (consp form)
                         (memq (car form) '(defun defvar defcustom defconst))
                         (string-match-p "boox" (format "%s" (cadr form))))
                (ignore-errors (eval form t)))))
        (end-of-file nil)))))
```

- [ ] **Step 3: Implement, in the `** Import` subsection**

```elisp
(defun a3madkour/boox--note-key ()
  "Return the Boox key for the current ref note, or nil.
Books carry an explicit `:BOOX_KEY:'; papers are named after their citekey,
so the filename base is the key."
  (or (org-entry-get (point-min) "BOOX_KEY")
      (when (buffer-file-name)
        (file-name-base (buffer-file-name)))))
```

- [ ] **Step 4: Refactor `boox-refresh-document` onto it**

In `a3madkour/boox-refresh-document`, replace:

```elisp
  (let* ((key (or (org-entry-get (point-min) "BOOX_KEY")
                  (and (buffer-file-name) (file-name-base (buffer-file-name)))))
```

with:

```elisp
  (let* ((key (a3madkour/boox--note-key))
```

- [ ] **Step 5: Run the suite**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
cd /Stuff/a3madkour/dotfiles/emacs-configs/custom && ./tests/run.sh 2>&1 | tail -2
```
Expected: `Ran 145 tests, 145 results as expected`.

- [ ] **Step 6: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add boox--note-key and use it in refresh-document"
```

---

## Task 3: `boox--archive-path` and `boox--stale-p`

**Files:**
- Modify: `config.org` — `** Import` and `** Tests`

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest boox-archive-path-returns-readable-annotated-document ()
  (let* ((pdf (make-temp-file "boox-ann-" nil ".pdf"))
         (f (make-temp-file "boox-note-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file pdf (insert "pdf"))
          (with-temp-file f
            (insert (format ":PROPERTIES:\n:ANNOTATED_DOCUMENT: %s\n:END:\n" pdf)))
          (with-current-buffer (find-file-noselect f)
            (should (equal (a3madkour/boox--archive-path) pdf))))
      (ignore-errors (delete-file pdf))
      (ignore-errors (delete-file f)))))

(ert-deftest boox-archive-path-nil-when-file-missing ()
  (let ((f (make-temp-file "boox-note-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert ":PROPERTIES:\n:ANNOTATED_DOCUMENT: /nonexistent/x.pdf\n:END:\n"))
          (with-current-buffer (find-file-noselect f)
            (should (null (a3madkour/boox--archive-path)))))
      (ignore-errors (delete-file f)))))

(ert-deftest boox-archive-path-nil-when-property-absent ()
  (let ((f (make-temp-file "boox-note-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f (insert "#+title: X\n"))
          (with-current-buffer (find-file-noselect f)
            (should (null (a3madkour/boox--archive-path)))))
      (ignore-errors (delete-file f)))))

(ert-deftest boox-stale-p-compares-against-recorded-hash ()
  (let* ((dir (make-temp-file "boox-notes-" t))
         (note (expand-file-name "k1.org" dir))
         (pdf (make-temp-file "boox-pdf-" nil ".pdf"))
         (org-ref-notes dir))
    (unwind-protect
        (progn
          (with-temp-file pdf (insert "content"))
          (let ((sha (a3madkour/boox--file-sha256 pdf)))
            (with-temp-file note
              (insert (format ":PROPERTIES:\n:BOOX_IMPORTED_SHA: %s\n:END:\n" sha)))
            (should-not (a3madkour/boox--stale-p "k1" pdf))
            (with-temp-file pdf (insert "different content"))
            (should (a3madkour/boox--stale-p "k1" pdf))))
      (ignore-errors (delete-file pdf))
      (ignore-errors (delete-directory dir t)))))

(ert-deftest boox-stale-p-true-when-never-imported ()
  (let* ((dir (make-temp-file "boox-notes-" t))
         (note (expand-file-name "k2.org" dir))
         (pdf (make-temp-file "boox-pdf-" nil ".pdf"))
         (org-ref-notes dir))
    (unwind-protect
        (progn
          (with-temp-file pdf (insert "content"))
          (with-temp-file note (insert "#+title: X\n"))
          (should (a3madkour/boox--stale-p "k2" pdf)))
      (ignore-errors (delete-file pdf))
      (ignore-errors (delete-directory dir t)))))
```

- [ ] **Step 2: Run the suite and confirm 5 new failures**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
cd /Stuff/a3madkour/dotfiles/emacs-configs/custom && ./tests/run.sh 2>&1 | tail -8
```
Expected: `Ran 150 tests`, 5 failing on the two undefined functions.

- [ ] **Step 3: Implement**

```elisp
(defun a3madkour/boox--archive-path ()
  "Return the current note's `:ANNOTATED_DOCUMENT:' if it is readable.
Nil means no archive exists, which is the condition retirement refuses on:
deleting the tablet copy would then destroy the only annotated version."
  (when-let ((p (org-entry-get (point-min) "ANNOTATED_DOCUMENT")))
    (and (file-readable-p p) p)))

(defun a3madkour/boox--stale-p (key file)
  "Non-nil when FILE has not been imported into KEY's ref note.
Compares FILE's hash against the note's `:BOOX_IMPORTED_SHA:'.  A note with
no recorded hash counts as stale, since nothing has been imported from it."
  (let* ((note (expand-file-name (concat key ".org") org-ref-notes))
         (recorded (when (file-exists-p note)
                     (with-current-buffer (find-file-noselect note)
                       (org-entry-get (point-min) "BOOX_IMPORTED_SHA")))))
    (not (and recorded
              (equal recorded (a3madkour/boox--file-sha256 file))))))
```

- [ ] **Step 4: Run the suite**

Expected: `Ran 150 tests, 150 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add archive-path and stale-p helpers with tests"
```

---

## Task 4: `boox--delete-from-tablet` and `boox--close-queue-entry`

**Files:**
- Modify: `config.org` — `** Import` and `** Tests`

- [ ] **Step 1: Write the failing tests**

```elisp
(ert-deftest boox-delete-from-tablet-removes-the-file ()
  (let ((f (make-temp-file "boox-del-" nil ".pdf")))
    (with-temp-file f (insert "x"))
    (should (file-exists-p f))
    (a3madkour/boox--delete-from-tablet f)
    (should-not (file-exists-p f))))

(defmacro boox-test--with-queue (content &rest body)
  "Run BODY with a temp queue.org containing CONTENT, bound via `a3madkour/org-file'."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "boox-queue-" t))
          (qf (expand-file-name "queue.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file qf (insert ,content))
           (cl-letf (((symbol-function 'a3madkour/org-file)
                      (lambda (p) (expand-file-name p dir))))
             ,@body))
       (ignore-errors (delete-directory dir t)))))

(ert-deftest boox-close-queue-entry-matches-citekey ()
  (boox-test--with-queue
      "* TODO Read A :active:toread:\n:PROPERTIES:\n:CITEKEY: smith2020\n:END:\n"
    (should (= (a3madkour/boox--close-queue-entry "smith2020") 1))
    (with-temp-buffer
      (insert-file-contents (a3madkour/org-file "queue.org"))
      (should (string-match-p "^\\* DONE Read A" (buffer-string)))
      (should-not (string-match-p ":active:" (buffer-string))))))

(ert-deftest boox-close-queue-entry-matches-boox-key ()
  (boox-test--with-queue
      "* TODO Read B :active:toread:\n:PROPERTIES:\n:BOOX_KEY: rules-of-play\n:END:\n"
    (should (= (a3madkour/boox--close-queue-entry "rules-of-play") 1))))

(ert-deftest boox-close-queue-entry-closes-every-duplicate ()
  "A leftover :active: duplicate would keep a WIP slot and make push re-stage."
  (boox-test--with-queue
      (concat "* TODO Read A :active:toread:\n:PROPERTIES:\n:CITEKEY: smith2020\n:END:\n"
              "* TODO Read A again :active:toread:\n:PROPERTIES:\n:CITEKEY: smith2020\n:END:\n")
    (should (= (a3madkour/boox--close-queue-entry "smith2020") 2))))

(ert-deftest boox-close-queue-entry-is-idempotent ()
  (boox-test--with-queue
      "* DONE Read A :toread:\n:PROPERTIES:\n:CITEKEY: smith2020\n:END:\n"
    (should (= (a3madkour/boox--close-queue-entry "smith2020") 0))))

(ert-deftest boox-close-queue-entry-reports-no-match ()
  (boox-test--with-queue
      "* TODO Read A :active:toread:\n:PROPERTIES:\n:CITEKEY: other\n:END:\n"
    (should (= (a3madkour/boox--close-queue-entry "smith2020") 0))))
```

- [ ] **Step 2: Run the suite and confirm 6 new failures**

Expected: `Ran 156 tests`, 6 failing.

- [ ] **Step 3: Implement**

```elisp
(defun a3madkour/boox--delete-from-tablet (file)
  "Delete FILE from the reading directory, which removes it from the tablet.
Isolated so the destructive step has a name, happens in exactly one place,
and can be stubbed in tests.  Syncthing's file versioning on that folder
retains a local copy."
  (delete-file file)
  t)

(defun a3madkour/boox--close-queue-entry (key)
  "Mark every queue.org entry for KEY as DONE and drop its `:active:' tag.
Returns the number of entries closed.  Entries already DONE are left alone,
so this is idempotent.  Every match is closed rather than just the first: a
duplicate left `:active:' would keep consuming a WIP slot and cause
`a3madkour/boox-push-queue' to re-stage the file."
  (let ((closed 0))
    (with-current-buffer (find-file-noselect (a3madkour/org-file "queue.org"))
      (org-map-entries
       (lambda ()
         (when (and (member key (list (org-entry-get nil "CITEKEY")
                                      (org-entry-get nil "BOOX_KEY")))
                    (not (equal (org-get-todo-state) "DONE")))
           (org-todo "DONE")
           (org-set-tags (delete "active" (org-get-tags nil t)))
           (setq closed (1+ closed))))
       nil 'file)
      (when (> closed 0) (save-buffer)))
    closed))
```

- [ ] **Step 4: Run the suite**

Expected: `Ran 156 tests, 156 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add delete-from-tablet and close-queue-entry with tests"
```

---

## Task 5: `boox-retire-document`

**Files:**
- Modify: `config.org` — `** Import`

- [ ] **Step 1: Implement the orchestrator**

```elisp
(defun a3madkour/boox-retire-document ()
  "Finish with this note's paper on the tablet: import, delete, close queue.
Imports any annotations embedded since the last import, deletes the file
from the reading directory (which removes it from the Boox), and marks the
reading-queue entry DONE.

Refuses when no readable `:ANNOTATED_DOCUMENT:' exists, because the tablet
copy would then be the only annotated version.  Safe to run twice: with no
file in the reading directory it reports and returns."
  (interactive)
  (let* ((key (or (a3madkour/boox--note-key)
                  (user-error "Not in a ref note — cannot determine the key")))
         (file (a3madkour/boox--reading-file-for-key key)))
    (cond
     ((null file)
      (message "%s: nothing on the tablet (already retired)" key))
     ((null (a3madkour/boox--archive-path))
      (user-error "%s has no readable :ANNOTATED_DOCUMENT: — import before retiring" key))
     (t
      ;; Staleness is captured once: importing rewrites the recorded hash, so a
      ;; second call would answer a different question than the first.
      (let* ((stale (a3madkour/boox--stale-p key file))
             (imported (when stale (a3madkour/boox--import-pdf key file))))
        (if (and stale (null imported))
            (message "%s: import declined — file left on the tablet" key)
          (a3madkour/boox--delete-from-tablet file)
          (let ((closed (a3madkour/boox--close-queue-entry key)))
            (message "%s: %s removed from tablet%s"
                     key
                     (if imported "imported and " "")
                     (if (> closed 0)
                         (format ", %d queue entr%s closed" closed
                                 (if (= closed 1) "y" "ies"))
                       " (no queue entry found)")))))))))
```

- [ ] **Step 2: Verify end to end against a real annotated PDF**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
SP=/tmp/claude-1000/-Stuff-a3madkour-Sync-Workspace/10f323dd-8bca-497f-9d00-fa0d4f02dbbe/scratchpad/t5
rm -rf $SP && mkdir -p $SP/notes $SP/reading $SP/archive
D=/Stuff/a3madkour/dotfiles/emacs-configs/custom/straight/build/pdf-tools
cp "/home/a3madkour/Sync/Zotero/storage/43WBIBMB/Abramsky and Tzevelekos - 2010 - Introduction to Categories and Categorical Logic.pdf" $SP/original.pdf
cp ~/Boox/reading/.stversions/*20260813-105306.pdf $SP/original-annotated.pdf
cp ~/Boox/reading/.stversions/*20260813-105306.pdf "$SP/reading/smith2020--Intro.pdf"
cat > $SP/notes/smith2020.org <<EOF
:PROPERTIES:
:NOTER_DOCUMENT: $SP/original-annotated.pdf
:ORIGINAL_DOCUMENT: $SP/original.pdf
:ANNOTATED_DOCUMENT: $SP/original-annotated.pdf
:PROGRESS: highlighting
:END:
#+title: Intro
EOF
cat > $SP/queue.org <<'EOF'
* TODO Read Intro :active:toread:
:PROPERTIES:
:CITEKEY: smith2020
:END:
EOF
cat > $SP/h.el <<EOF
(add-to-list 'load-path "$D")
(require 'boox-core)(require 'org)(require 'subr-x)(require 'seq)(require 'cl-lib)(require 'pdf-info)
(setq pdf-info-epdfinfo-program "$D/epdfinfo")
(provide 'citar)
(defun citar-get-entry (k) (list (cons "file" "$SP/original.pdf") (cons "title" "Intro")))
(defun citar-get-entries () (make-hash-table :test 'equal))
(defun citar-create-note (k &optional e) nil)
(defun a3madkour/org-file (p) (expand-file-name p "$SP"))
(setq org-ref-notes "$SP/notes")
(with-temp-buffer (insert-file-contents "~/emacs-configs/custom/config.el") (goto-char (point-min))
  (condition-case nil (while t (let ((f (read (current-buffer))))
    (when (and (consp f) (memq (car f) '(defun defvar defcustom defconst define-derived-mode))
               (string-match-p "boox" (format "%s" (cadr f)))) (eval f t)))) (end-of-file nil)))
(setq a3madkour/boox-reading-directory "$SP/reading/")
(cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
          ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
  (with-current-buffer (find-file-noselect "$SP/notes/smith2020.org")
    (a3madkour/boox-retire-document)))
(message "reading dir now: %S" (directory-files "$SP/reading" nil "pdf"))
(message "archive still there: %s" (file-exists-p "$SP/original-annotated.pdf"))
(message "queue: %s" (with-temp-buffer (insert-file-contents "$SP/queue.org") (buffer-string)))
(message "note has highlights: %s"
  (with-temp-buffer (insert-file-contents "$SP/notes/smith2020.org")
    (if (string-match-p "Tablet Highlights" (buffer-string)) "yes" "no")))
(message "--- second run (idempotency) ---")
(with-current-buffer (find-file-noselect "$SP/notes/smith2020.org")
  (a3madkour/boox-retire-document))
EOF
emacs -Q --batch -L ~/emacs-configs/custom -l $SP/h.el 2>&1 | grep -E "removed from tablet|reading dir now|archive still|DONE|TODO|highlights:|already retired"
```

Expected, in order:
1. `smith2020: imported and removed from tablet, 1 queue entry closed`
2. `reading dir now: nil`
3. `archive still there: t`
4. queue shows `* DONE Read Intro :toread:` with no `:active:`
5. `note has highlights: yes`
6. second run prints `smith2020: nothing on the tablet (already retired)`

- [ ] **Step 3: Verify the already-current case — no re-import, still deleted**

The spec requires that a file already imported is *not* re-imported but *is*
still removed. Reuse the Task 5 Step 2 fixture, which after that run has a
recorded hash matching the file. Re-stage the same file and retire again:

```bash
SP=/tmp/claude-1000/-Stuff-a3madkour-Sync-Workspace/10f323dd-8bca-497f-9d00-fa0d4f02dbbe/scratchpad/t5
cp ~/Boox/reading/.stversions/*20260813-105306.pdf "$SP/reading/smith2020--Intro.pdf"
cat >> $SP/h.el <<'EOF'
(message "--- already-current run ---")
(with-current-buffer (find-file-noselect (expand-file-name "notes/smith2020.org" org-ref-notes))
  (a3madkour/boox-retire-document))
(message "reading dir after: %S" (directory-files a3madkour/boox-reading-directory nil "pdf"))
EOF
emacs -Q --batch -L ~/emacs-configs/custom -l $SP/h.el 2>&1 | grep -A2 "already-current run"
```

Expected: a message reading `smith2020: removed from tablet…` **without** the
word "imported", and `reading dir after: nil`.

- [ ] **Step 4: Verify the refusal case**

Self-contained — do not derive this script from the previous one:

```bash
SP=/tmp/claude-1000/-Stuff-a3madkour-Sync-Workspace/10f323dd-8bca-497f-9d00-fa0d4f02dbbe/scratchpad/t5b
rm -rf $SP && mkdir -p $SP/notes $SP/reading
D=/Stuff/a3madkour/dotfiles/emacs-configs/custom/straight/build/pdf-tools
cp ~/Boox/reading/.stversions/*20260813-105306.pdf "$SP/reading/smith2020--Intro.pdf"
cat > $SP/notes/smith2020.org <<'EOF'
:PROPERTIES:
:PROGRESS: highlighting
:END:
#+title: Intro
EOF
cat > $SP/h.el <<EOF
(add-to-list 'load-path "$D")
(require 'boox-core)(require 'org)(require 'subr-x)(require 'seq)(require 'cl-lib)(require 'pdf-info)
(setq pdf-info-epdfinfo-program "$D/epdfinfo")
(provide 'citar)
(defun citar-get-entry (k) nil)
(defun citar-get-entries () (make-hash-table :test 'equal))
(defun a3madkour/org-file (p) (expand-file-name p "$SP"))
(setq org-ref-notes "$SP/notes")
(with-temp-buffer (insert-file-contents "~/emacs-configs/custom/config.el") (goto-char (point-min))
  (condition-case nil (while t (let ((f (read (current-buffer))))
    (when (and (consp f) (memq (car f) '(defun defvar defcustom defconst define-derived-mode))
               (string-match-p "boox" (format "%s" (cadr f)))) (eval f t)))) (end-of-file nil)))
(setq a3madkour/boox-reading-directory "$SP/reading/")
(condition-case e
    (with-current-buffer (find-file-noselect "$SP/notes/smith2020.org")
      (a3madkour/boox-retire-document))
  (user-error (message "REFUSED: %s" (error-message-string e))))
(message "reading dir still has: %S" (directory-files "$SP/reading" nil "pdf"))
EOF
emacs -Q --batch -L ~/emacs-configs/custom -l $SP/h.el 2>&1 | grep -E "REFUSED|reading dir still"
```

Expected: `REFUSED: … has no readable :ANNOTATED_DOCUMENT: — import before retiring`, and the reading-directory file **still listed**.

- [ ] **Step 5: Run the full suite**

Expected: `Ran 156 tests, 156 results as expected`.

- [ ] **Step 6: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): add boox-retire-document orchestrator"
```

---

## Task 6: Pipeline hook and keybinding

**Files:**
- Modify: `config.org` — beside `a3madkour/org-roam-advance-pipeline` (~config.org:3811)
- Modify: `config.org` — the `zb` keybinding block

- [ ] **Step 1: Add the policy function immediately before `a3madkour/org-roam-advance-pipeline`**

```elisp
(defun a3madkour/boox--pipeline-advanced (from to)
  "Retire the tablet copy when leaving the highlighting stage.
Policy only: FROM and TO decide *whether* to retire, while
`a3madkour/boox-retire-document' decides *how*.  Failures are reported but
never re-signalled — the pipeline stage is a statement about your own
workflow, and a sleeping tablet or an unreachable file should not stop you
advancing a note."
  (when (and (equal from "highlighting") (equal to "ref-notes"))
    (condition-case err
        (a3madkour/boox-retire-document)
      (error (message "Boox retire failed (PROGRESS still advanced): %s"
                      (error-message-string err))))))
```

- [ ] **Step 2: Call it from `a3madkour/org-roam-advance-pipeline`**

Replace:

```elisp
    (save-excursion
      (goto-char (point-min))
      (org-set-property "PROGRESS" next))
    (message "Progress: %s → %s" current next)))
```

with:

```elisp
    (save-excursion
      (goto-char (point-min))
      (org-set-property "PROGRESS" next))
    (a3madkour/boox--pipeline-advanced current next)
    (message "Progress: %s → %s" current next)))
```

- [ ] **Step 3: Add the keybinding**

In the `general-define-key` block, after the `"zbr"` entry:

```elisp
 "zbd"
 '(a3madkour/boox-retire-document :which-key "done — remove from tablet")
```

- [ ] **Step 4: Verify the hook fires only on the right transition**

```bash
emacs -Q --batch --eval '(progn (require (quote org)) (org-babel-tangle-file "~/emacs-configs/custom/config.org"))'
emacs -Q --batch --eval '(progn
  (require (quote org))
  (with-temp-buffer
    (insert-file-contents "~/emacs-configs/custom/config.el")
    (goto-char (point-min))
    (condition-case nil
        (while t (let ((f (read (current-buffer))))
          (when (and (consp f) (memq (car f) (list (quote defun)))
                     (string-match-p "boox--pipeline-advanced" (format "%s" (cadr f))))
            (eval f t))))
      (end-of-file nil)))
  (let ((calls 0))
    (defun a3madkour/boox-retire-document () (setq calls (1+ calls)))
    (a3madkour/boox--pipeline-advanced "none" "highlighting")
    (a3madkour/boox--pipeline-advanced "ref-notes" "main-notes")
    (a3madkour/boox--pipeline-advanced "main-notes" "done")
    (message "calls after non-triggering transitions: %d" calls)
    (a3madkour/boox--pipeline-advanced "highlighting" "ref-notes")
    (message "calls after highlighting->ref-notes: %d" calls)))' 2>&1 | grep calls
```

Expected: `calls after non-triggering transitions: 0`, then `calls after highlighting->ref-notes: 1`.

- [ ] **Step 5: Verify an error does not block the advance**

```bash
emacs -Q --batch --eval '(progn
  (require (quote org))
  (with-temp-buffer
    (insert-file-contents "~/emacs-configs/custom/config.el")
    (goto-char (point-min))
    (condition-case nil
        (while t (let ((f (read (current-buffer))))
          (when (and (consp f) (memq (car f) (list (quote defun)))
                     (string-match-p "boox--pipeline-advanced" (format "%s" (cadr f))))
            (eval f t))))
      (end-of-file nil)))
  (defun a3madkour/boox-retire-document () (user-error "simulated failure"))
  (a3madkour/boox--pipeline-advanced "highlighting" "ref-notes")
  (message "survived the error"))' 2>&1 | grep -E "retire failed|survived"
```

Expected: both a `Boox retire failed (PROGRESS still advanced): …simulated failure` line and `survived the error`.

- [ ] **Step 6: Run the full suite**

Expected: `Ran 156 tests, 156 results as expected`.

- [ ] **Step 7: Commit**

```bash
cd /Stuff/a3madkour/dotfiles
git add emacs-configs/custom/config.org
git commit -m "feat(boox): retire tablet copy when advancing past highlighting"
```

---

## Acceptance

- [ ] Restart Emacs
- [ ] Open a ref note whose paper is on the tablet, with `:PROGRESS: highlighting`
- [ ] `M-x a3madkour/org-roam-advance-pipeline` — expect `Progress: highlighting → ref-notes` plus a retire message
- [ ] Confirm the file is gone from `~/Boox/reading/` and disappears from the Boox
- [ ] Confirm `<original>-annotated.pdf` still exists and `M-x org-noter` still opens it with highlights intact
- [ ] Confirm the `queue.org` entry is `DONE` and no longer `:active:`
- [ ] `M-x a3madkour/boox-push-queue` — confirm the paper is **not** re-staged
