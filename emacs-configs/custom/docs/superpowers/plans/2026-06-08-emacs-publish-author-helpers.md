# Emacs publish-author helpers (Tier 5.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship six interactive Emacs commands (mark / unmark / status / library-insert-item / library-insert-extras / jump-to-source) in a new `a3madkour-publish-author.el` module so the author can manage publish state and library items without leaving Emacs.

**Architecture:** Single new module `a3madkour-publish-author.el` + sibling test file. All six commands compose existing primitives — sections registry (`a3madkour-pub/sections`), library config + extras tables (via two new thin public wrappers added to `a3madkour-publish-library.el`), publish history (`a3madkour-pub-history/read-manifest`), and the keywords API (`a3madkour-pub-keywords/extract` + `boolean-p`). No new tables; no new shell-script wrappers (commands are interactive only).

**Tech Stack:** Emacs Lisp · ert · Vertico (already configured; plain `completing-read` automatically gets the vertical UI).

**Spec:** [`docs/superpowers/specs/2026-06-08-emacs-publish-author-helpers-design.md`](../specs/2026-06-08-emacs-publish-author-helpers-design.md) (dotfiles commit `8767740`).

---

## File structure

| Path | Status | Responsibility |
|---|---|---|
| `emacs-configs/custom/lisp/a3madkour-publish-author.el` | NEW | Six interactive commands + a few `--double-dash` internal helpers (keyword upsert, manifest walk, etc) |
| `emacs-configs/custom/lisp/a3madkour-publish-author-test.el` | NEW | ert coverage (~33 tests) |
| `emacs-configs/custom/lisp/a3madkour-publish-library.el` | MODIFY | Add two thin public wrappers: `a3madkour-pub-library/sections`, `a3madkour-pub-library/extras-for` |
| `emacs-configs/custom/lisp/a3-pub.sh` | UNCHANGED | author.el is interactive-only; never invoked from the shell wrapper. Verified explicitly in Task 9 |

**Commit shape:** one logical dotfiles commit at the end (matches Tier 5.1 / Tier 4 batch pattern), then one site commit for the roadmap row + memory.

---

## Task 1: Bootstrap the module + test scaffolding

**Files:**
- Create: `emacs-configs/custom/lisp/a3madkour-publish-author.el`
- Create: `emacs-configs/custom/lisp/a3madkour-publish-author-test.el`

- [ ] **Step 1: Write the skeleton-loaded test (failing — module doesn't exist yet)**

Create `a3madkour-publish-author-test.el` with:

```elisp
;;; a3madkour-publish-author-test.el --- tests for -author.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the publish-author interactive helpers (Tier 5.2).
;;; Code:

(require 'ert)
(require 'a3madkour-publish-author)

(ert-deftest a3madkour-pub-author-test/skeleton-loaded ()
  "The author module loads and its provide marker is registered."
  (should (featurep 'a3madkour-publish-author)))

(provide 'a3madkour-publish-author-test)
;;; a3madkour-publish-author-test.el ends here
```

- [ ] **Step 2: Run test to verify it fails (module doesn't exist)**

```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: load error — `Cannot open load file: a3madkour-publish-author`. Suite count: 629 still passes; the new module load fails the test runner.

- [ ] **Step 3: Write the minimal module skeleton**

Create `a3madkour-publish-author.el` with:

```elisp
;;; a3madkour-publish-author.el --- Interactive publish-author helpers (Tier 5.2) -*- lexical-binding: t; -*-

;;; Commentary:

;; Six interactive commands for author-side publish-state management:
;;   a3-publish-mark / unmark / status — toggle and query #+HUGO_PUBLISH:
;;   a3-library-insert-item / insert-extras — scaffold library-*.org entries
;;   a3-publish-jump-to-source — manifest-driven nav from content/ → org
;;
;; All six compose existing primitives (sections registry, library config,
;; keywords API, publish manifest).  No new tables.
;;
;; See `docs/superpowers/specs/2026-06-08-emacs-publish-author-helpers-design.md'.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'a3madkour-publish)
(require 'a3madkour-publish-keywords)
(require 'a3madkour-publish-library)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-id)

(provide 'a3madkour-publish-author)

;;; a3madkour-publish-author.el ends here
```

- [ ] **Step 4: Run test to verify the skeleton-loaded test passes**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: suite count 629 → 630 (skeleton-loaded test).

---

## Task 2: Public wrappers in a3madkour-publish-library.el

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-library.el` — append two thin public functions after the existing `a3madkour-pub-library--config-for` helper (around line 51)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-library-test.el` — append three tests at the bottom

- [ ] **Step 1: Write the three failing tests**

Append to `a3madkour-publish-library-test.el` (before its final `(provide ...)` line):

```elisp
;; -- Tier 5.2: public wrappers for author.el --

(ert-deftest a3madkour-pub-library/sections-returns-config-section-keys ()
  "Tier 5.2: `/sections' enumerates the slash-form section strings from --config."
  (let ((result (a3madkour-pub-library/sections)))
    (should (member "library/reading" result))
    (should (member "library/listening" result))
    (should (member "library/playing" result))
    (should (member "library/watching" result))
    (should (= (length result) 4))))

(ert-deftest a3madkour-pub-library/extras-for-book-returns-book-extras ()
  "Tier 5.2: `/extras-for' looks up the per-medium extras spec."
  (let ((book (a3madkour-pub-library/extras-for "book")))
    (should book)
    ;; Book extras include ISBN as the first drawer key per --extras-by-media.
    (should (equal (caar book) "ISBN"))))

(ert-deftest a3madkour-pub-library/extras-for-unknown-medium-nil ()
  "Tier 5.2: `/extras-for' returns nil for an unknown medium (not an error)."
  (should (null (a3madkour-pub-library/extras-for "bogus"))))
```

- [ ] **Step 2: Run tests to verify they fail (functions don't exist)**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: 3 `Symbol's function definition is void` failures.

- [ ] **Step 3: Add the two public wrappers**

In `a3madkour-publish-library.el`, immediately after the `a3madkour-pub-library--config-for` defun (around line 51), insert:

```elisp
(defun a3madkour-pub-library/sections ()
  "Return the list of library section strings (e.g. \"library/reading\").

Public wrapper over `a3madkour-pub-library--config' for consumption from
sibling modules (Tier 5.2 author.el)."
  (mapcar #'car a3madkour-pub-library--config))

(defun a3madkour-pub-library/extras-for (medium)
  "Return the per-medium extras spec for MEDIUM, or nil if unknown.

Each element is (DRAWER-KEY YAML-KEY COERCION-OR-NIL).  Public wrapper
over `a3madkour-pub-library--extras-by-media' for sibling modules."
  (cdr (assoc medium a3madkour-pub-library--extras-by-media)))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: suite 630 → 633 (+3 wrapper tests).

---

## Task 3: a3-publish-status (read-only, simplest)

**Files:**
- Modify: `a3madkour-publish-author.el` — append after the `require` block
- Modify: `a3madkour-publish-author-test.el` — append before the final `(provide ...)`

- [ ] **Step 1: Write five failing tests**

Append to `a3madkour-publish-author-test.el`:

```elisp
;; -- a3-publish-status --

(ert-deftest a3madkour-pub-author-test/status-no-header ()
  "status: HUGO_PUBLISH absent → \"no HUGO_PUBLISH header\"."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n\n* Heading\n")
    (should (string= (a3-publish-status) "no HUGO_PUBLISH header"))))

(ert-deftest a3madkour-pub-author-test/status-nil ()
  "status: HUGO_PUBLISH: nil → private."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: nil\n#+title: Test\n")
    (should (string= (a3-publish-status) "private (HUGO_PUBLISH: nil)"))))

(ert-deftest a3madkour-pub-author-test/status-marked-valid-section ()
  "status: HUGO_PUBLISH: t + valid HUGO_SECTION → marked."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+title: Test\n")
    (should (string= (a3-publish-status) "marked for publish (garden)"))))

(ert-deftest a3madkour-pub-author-test/status-marked-invalid-section ()
  "status: HUGO_PUBLISH: t + invalid HUGO_SECTION → flagged."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: bogus-section\n#+title: Test\n")
    (should (string-match-p "invalid" (a3-publish-status)))
    (should (string-match-p "bogus-section" (a3-publish-status)))))

(ert-deftest a3madkour-pub-author-test/status-refuses-non-org-mode ()
  "status: non-org-mode buffer → user-error."
  (with-temp-buffer
    (text-mode)
    (insert "plain text")
    (should-error (a3-publish-status) :type 'user-error)))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh 2>&1 | tail -10
```

Expected: 5 `Symbol's function definition is void: a3-publish-status` failures.

- [ ] **Step 3: Implement `a3-publish-status`**

In `a3madkour-publish-author.el`, before the final `(provide ...)`, insert:

```elisp
;; -- a3-publish-status --

;;;###autoload
(defun a3-publish-status ()
  "Describe the current org buffer's publish state in the minibuffer.

Branches:
  - `#+HUGO_PUBLISH:' missing       → \"no HUGO_PUBLISH header\"
  - present but not \"t\"           → \"private (HUGO_PUBLISH: <raw>)\"
  - \"t\" + valid `#+HUGO_SECTION:' → \"marked for publish (<section>)\"
  - \"t\" + missing/invalid section → flagged variant

Returns the message string (also `message'd)."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "a3-publish-status: current buffer is not org-mode"))
  (let* ((publish-raw (a3madkour-pub-keywords/extract "HUGO_PUBLISH"))
         (section (a3madkour-pub-keywords/extract "HUGO_SECTION"))
         (msg
          (cond
           ((null publish-raw) "no HUGO_PUBLISH header")
           ((not (a3madkour-pub-keywords/boolean-p publish-raw))
            (format "private (HUGO_PUBLISH: %s)" publish-raw))
           ((or (null section) (string-empty-p section))
            "marked for publish but HUGO_SECTION is missing")
           ((not (a3madkour-pub/valid-section-p section))
            (format "marked for publish but HUGO_SECTION is invalid: %S" section))
           (t (format "marked for publish (%s)" section)))))
    (message "%s" msg)
    msg))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: suite 633 → 638 (+5 status tests).

---

## Task 4: a3-publish-mark (first writer; cross-section guard)

**Files:**
- Modify: `a3madkour-publish-author.el` — append helper + command
- Modify: `a3madkour-publish-author-test.el` — append six tests

- [ ] **Step 1: Write six failing tests**

```elisp
;; -- a3-publish-mark --

(ert-deftest a3madkour-pub-author-test/mark-inserts-both-keywords-when-absent ()
  "mark: empty preamble → inserts #+HUGO_PUBLISH: t + #+HUGO_SECTION: <pick>."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n\n* Heading\n")
    (a3-publish-mark "essays")
    (should (string-match-p "^#\\+HUGO_PUBLISH:[[:space:]]+t$"
                            (buffer-string)))
    (should (string-match-p "^#\\+HUGO_SECTION:[[:space:]]+essays$"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/mark-updates-section-in-place-when-present ()
  "mark: existing HUGO_SECTION → updated in place (cross-section guard skipped
when caller passes the same answer to y-or-n-p)."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+title: Test\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) t)))
      (a3-publish-mark "essays"))
    (should (string-match-p "^#\\+HUGO_SECTION:[[:space:]]+essays$"
                            (buffer-string)))
    (should-not (string-match-p "^#\\+HUGO_SECTION:[[:space:]]+garden$"
                                (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/mark-cross-section-confirm-accepted ()
  "mark: cross-section y-or-n-p → t edits proceed, returns picked section."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) t)))
      (should (equal (a3-publish-mark "essays") "essays")))))

(ert-deftest a3madkour-pub-author-test/mark-cross-section-confirm-declined-aborts ()
  "mark: cross-section y-or-n-p → nil aborts; neither keyword is changed."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n")
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) nil)))
        (should (null (a3-publish-mark "essays"))))
      (should (string= (buffer-string) before)))))

(ert-deftest a3madkour-pub-author-test/mark-refuses-non-org-mode ()
  "mark: non-org-mode buffer → user-error."
  (with-temp-buffer
    (text-mode)
    (should-error (a3-publish-mark "essays") :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/mark-refuses-read-only ()
  "mark: read-only buffer → user-error."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n")
    (read-only-mode 1)
    (should-error (a3-publish-mark "essays") :type 'user-error)))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh 2>&1 | tail -10
```

Expected: 6 failures (function undefined).

- [ ] **Step 3: Implement the keyword-upsert helper + `a3-publish-mark`**

In `a3madkour-publish-author.el`, insert before the `(provide ...)`:

```elisp
;; -- internal: keyword upsert (used by mark / unmark) --

(defun a3madkour-pub-author--upsert-keyword (key val)
  "Set `#+KEY: VAL' in the current buffer's preamble, idempotently.

If a `#+KEY:' line exists anywhere in the buffer, replace its value
in place.  Otherwise insert `#+KEY: VAL' at point-min.

KEY matching is case-insensitive on the keyword name.  VAL is inserted
verbatim — caller is responsible for any escaping."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t)
          (re (format "^#\\+%s:[[:space:]]*.*$" (regexp-quote key))))
      (if (re-search-forward re nil t)
          (replace-match (format "#+%s: %s" key val) t t)
        (goto-char (point-min))
        (insert (format "#+%s: %s\n" key val))))))

;; -- a3-publish-mark --

;;;###autoload
(cl-defun a3-publish-mark (section)
  "Mark the current org buffer for publish at SECTION.

Idempotently sets `#+HUGO_PUBLISH: t' + `#+HUGO_SECTION: SECTION' in the
buffer's preamble.  Reads SECTION via `completing-read' over
`a3madkour-pub/sections' (defaulting to the current `#+HUGO_SECTION:'
value if set).

Cross-section guard: if the buffer already has `#+HUGO_SECTION: <other>'
and SECTION differs, prompts `y-or-n-p' before changing.  Declining the
prompt aborts the entire command — neither keyword is touched and the
command returns nil.

Refuses outside `org-mode' or in a read-only buffer.

Returns the picked SECTION string, or nil if cross-section confirm was
declined."
  (interactive
   (let ((current (a3madkour-pub-keywords/extract "HUGO_SECTION")))
     (list (completing-read "Section: " a3madkour-pub/sections
                            nil t nil nil current))))
  (unless (derived-mode-p 'org-mode)
    (user-error "a3-publish-mark: current buffer is not org-mode"))
  (when buffer-read-only
    (user-error "a3-publish-mark: buffer is read-only"))
  (let ((current (a3madkour-pub-keywords/extract "HUGO_SECTION")))
    (when (and current
               (not (string= current section))
               (not (y-or-n-p
                     (format "Move from `%s' to `%s'? (next publish-living will record slug-shift) "
                             current section))))
      (cl-return-from a3-publish-mark nil)))
  (a3madkour-pub-author--upsert-keyword "HUGO_PUBLISH" "t")
  (a3madkour-pub-author--upsert-keyword "HUGO_SECTION" section)
  section)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: suite 638 → 644 (+6 mark tests).

---

## Task 5: a3-publish-unmark

**Files:**
- Modify: `a3madkour-publish-author.el` — append command (reuses `--upsert-keyword` from Task 4)
- Modify: `a3madkour-publish-author-test.el` — append four tests

- [ ] **Step 1: Write four failing tests**

```elisp
;; -- a3-publish-unmark --

(ert-deftest a3madkour-pub-author-test/unmark-flips-t-to-nil ()
  "unmark: HUGO_PUBLISH: t → nil; returns t."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n")
    (should (eq (a3-publish-unmark) t))
    (should (string-match-p "^#\\+HUGO_PUBLISH:[[:space:]]+nil$"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/unmark-inserts-nil-when-absent ()
  "unmark: HUGO_PUBLISH missing → inserts `#+HUGO_PUBLISH: nil`; returns t."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n")
    (should (eq (a3-publish-unmark) t))
    (should (string-match-p "^#\\+HUGO_PUBLISH:[[:space:]]+nil$"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/unmark-already-nil-no-op ()
  "unmark: HUGO_PUBLISH already nil → returns nil, buffer unchanged."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: nil\n#+title: Test\n")
    (let ((before (buffer-string)))
      (should (null (a3-publish-unmark)))
      (should (string= (buffer-string) before)))))

(ert-deftest a3madkour-pub-author-test/unmark-refuses-non-org-mode ()
  "unmark: non-org-mode buffer → user-error."
  (with-temp-buffer
    (text-mode)
    (should-error (a3-publish-unmark) :type 'user-error)))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh 2>&1 | tail -10
```

Expected: 4 failures (function undefined).

- [ ] **Step 3: Implement `a3-publish-unmark`**

Append to `a3madkour-publish-author.el` (before `(provide ...)`):

```elisp
;; -- a3-publish-unmark --

;;;###autoload
(defun a3-publish-unmark ()
  "Flip `#+HUGO_PUBLISH:' to `nil' in the current org buffer.

Preserves the keyword line (sets value to \"nil\") and leaves
`#+HUGO_SECTION:' untouched — so re-marking with `a3-publish-mark'
keeps the prior section choice as the default.

If `#+HUGO_PUBLISH:' is missing, inserts `#+HUGO_PUBLISH: nil' at the
top of the buffer.

Refuses outside `org-mode' or in a read-only buffer.

Returns t if the buffer changed, nil if `#+HUGO_PUBLISH:' was already nil."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "a3-publish-unmark: current buffer is not org-mode"))
  (when buffer-read-only
    (user-error "a3-publish-unmark: buffer is read-only"))
  (let ((current (a3madkour-pub-keywords/extract "HUGO_PUBLISH")))
    (cond
     ((equal current "nil") nil)
     (t (a3madkour-pub-author--upsert-keyword "HUGO_PUBLISH" "nil")
        t))))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: suite 644 → 648 (+4 unmark tests).

---

## Task 6: a3-library-insert-extras

**Files:**
- Modify: `a3madkour-publish-author.el` — append section-derivation helper + command
- Modify: `a3madkour-publish-author-test.el` — append four tests

Spec §4.5. Reads current heading's drawer properties via `org-entry-properties nil 'standard` (drawer only, skips `:CATEGORY:` etc); diffs against the medium's extras key set; inserts absent keys into the heading's `:PROPERTIES:` drawer (creates one if absent).

- [ ] **Step 1: Write four failing tests**

```elisp
;; -- a3-library-insert-extras --

(defmacro a3-pub-author-test--with-library-buffer (section &rest body)
  "Run BODY in a temp org buffer set up as a library file for SECTION."
  (declare (indent 1))
  `(with-temp-buffer
     (org-mode)
     (insert (format "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: %s\n#+title: Test\n\n"
                     ,section))
     ,@body))

(ert-deftest a3madkour-pub-author-test/insert-extras-bare-heading-inserts-all ()
  "insert-extras: bare heading (no drawer) → full extras for the section's medium."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (insert "* Pride and Prejudice\n")
    (goto-char (point-max))
    (search-backward "Pride")
    (a3-library-insert-extras)
    (let ((buf (buffer-string)))
      ;; Book extras include ISBN, PROGRESS_PCT, PROGRESS_LABEL, COVER_FILE, COVER_URL.
      (should (string-match-p ":ISBN:" buf))
      (should (string-match-p ":COVER_FILE:" buf)))))

(ert-deftest a3madkour-pub-author-test/insert-extras-partial-drawer-add-missing-only ()
  "insert-extras: drawer has some extras → y-or-n-p → t inserts only the missing keys."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (insert "* Pride and Prejudice\n:PROPERTIES:\n:ISBN: 1234567890\n:END:\n")
    (search-backward "Pride")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) t)))
      (a3-library-insert-extras))
    (let ((buf (buffer-string)))
      ;; ISBN was already there; new keys appended.
      (should (string-match-p ":COVER_FILE:" buf))
      ;; ISBN appears exactly once (no duplicate).
      (should (= 1 (cl-count-if (lambda (l) (string-match-p ":ISBN:" l))
                                (split-string buf "\n")))))))

(ert-deftest a3madkour-pub-author-test/insert-extras-refuses-outside-heading ()
  "insert-extras: point not under any heading → user-error."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (goto-char (point-max))
    (should-error (a3-library-insert-extras) :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/insert-extras-refuses-non-library-section ()
  "insert-extras: section not in library config → user-error."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_SECTION: garden\n* Heading\n")
    (search-backward "Heading")
    (should-error (a3-library-insert-extras) :type 'user-error)))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh 2>&1 | tail -10
```

Expected: 4 failures.

- [ ] **Step 3: Implement section-derivation + `a3-library-insert-extras`**

Append to `a3madkour-publish-author.el`:

```elisp
;; -- internal: library section + medium derivation --

(defun a3madkour-pub-author--require-library-section ()
  "Return the buffer's library `#+HUGO_SECTION:' value.
Signal `user-error' if missing or not in `(a3madkour-pub-library/sections)'."
  (let ((section (a3madkour-pub-keywords/extract "HUGO_SECTION")))
    (unless (and section (member section (a3madkour-pub-library/sections)))
      (user-error "a3madkour-pub-author: `#+HUGO_SECTION:' missing or not a library section (got %S)"
                  section))
    section))

(defun a3madkour-pub-author--default-medium-for (section)
  "Return the default medium string for SECTION (a library section)."
  (nth 1 (a3madkour-pub-library--config-for section)))

;; -- a3-library-insert-extras --

;;;###autoload
(defun a3-library-insert-extras ()
  "Insert the per-medium extras drawer keys on the current library heading.

Reads section from `#+HUGO_SECTION:' (must be a library section).  Derives
medium from the section's default (multi-medium sections like
`library/listening' default to `album'; the author edits the heading
afterward if they want `track').

If the heading already has some extras, prompts `y-or-n-p' and inserts
only the missing keys.

Refuses outside `org-mode', when section isn't a library section, or when
point is not under any heading."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "a3-library-insert-extras: current buffer is not org-mode"))
  (let ((section (a3madkour-pub-author--require-library-section)))
    (unless (org-at-heading-p)
      (let ((on-heading (save-excursion (org-back-to-heading t) t)))
        (unless on-heading
          (user-error "a3-library-insert-extras: point not under any heading"))))
    (let* ((medium (a3madkour-pub-author--default-medium-for section))
           (extras (a3madkour-pub-library/extras-for medium))
           (existing (mapcar #'car (org-entry-properties nil 'standard)))
           (missing (cl-remove-if
                     (lambda (spec) (member (upcase (car spec)) existing))
                     extras)))
      (when (and (< (length missing) (length extras))
                 (not (y-or-n-p
                       (format "Heading has %d/%d extras — append the missing %d? "
                               (- (length extras) (length missing))
                               (length extras)
                               (length missing)))))
        (user-error "a3-library-insert-extras: aborted"))
      (dolist (spec missing)
        (org-set-property (car spec) ""))
      (length missing))))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: suite 648 → 652 (+4 insert-extras tests).

Note: `org-set-property` handles drawer-creation automatically — no need to scaffold `:PROPERTIES: ... :END:` by hand.

---

## Task 7: a3-library-insert-item

**Files:**
- Modify: `a3madkour-publish-author.el` — append command
- Modify: `a3madkour-publish-author-test.el` — append five tests

Spec §4.4. Insert position: end of buffer. Inserted block: `* TITLE` heading + `:PROPERTIES:` drawer with required keys + per-medium extras.

- [ ] **Step 1: Write five failing tests**

```elisp
;; -- a3-library-insert-item --

(ert-deftest a3madkour-pub-author-test/insert-item-happy-reading ()
  "insert-item: library/reading defaults to book; status prompt; full drawer inserted."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_p coll &rest _) (car coll))))
      (a3-library-insert-item))
    (let ((buf (buffer-string)))
      (should (string-match-p "^\\* TITLE" buf))
      (should (string-match-p ":CREATOR:" buf))
      (should (string-match-p ":STATUS: finished" buf))
      (should (string-match-p ":LAST_MODIFIED:" buf))
      ;; Book extras keys
      (should (string-match-p ":ISBN:" buf))
      (should (string-match-p ":COVER_FILE:" buf)))))

(ert-deftest a3madkour-pub-author-test/insert-item-listening-prompts-medium ()
  "insert-item: library/listening allows album+track → prompts for medium."
  (a3-pub-author-test--with-library-buffer "library/listening"
    (let ((calls nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt coll &rest _)
                   (push prompt calls)
                   (car coll))))
        (a3-library-insert-item))
      ;; Two completing-read calls: medium first, then status.
      (should (= (length calls) 2)))))

(ert-deftest a3madkour-pub-author-test/insert-item-playing-skips-medium-prompt ()
  "insert-item: library/playing has single medium (game) → only status prompt."
  (a3-pub-author-test--with-library-buffer "library/playing"
    (let ((calls nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt coll &rest _)
                   (push prompt calls)
                   (car coll))))
        (a3-library-insert-item))
      ;; One call (status); medium prompt skipped.
      (should (= (length calls) 1)))))

(ert-deftest a3madkour-pub-author-test/insert-item-refuses-non-library-section ()
  "insert-item: non-library section → user-error."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_SECTION: garden\n")
    (should-error (a3-library-insert-item) :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/insert-item-appends-after-existing ()
  "insert-item: existing heading is preserved; new heading appended."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (insert "* Existing Book\n:PROPERTIES:\n:CREATOR: Old Author\n:END:\n")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_p coll &rest _) (car coll))))
      (a3-library-insert-item))
    (let ((buf (buffer-string)))
      (should (string-match-p "Existing Book" buf))
      (should (string-match-p "^\\* TITLE" buf))
      ;; Existing entry comes before the new one.
      (should (< (string-match "Existing Book" buf)
                 (string-match "^\\* TITLE" buf))))))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh 2>&1 | tail -10
```

Expected: 5 failures.

- [ ] **Step 3: Implement `a3-library-insert-item`**

Append to `a3madkour-publish-author.el`:

```elisp
;; -- a3-library-insert-item --

;;;###autoload
(defun a3-library-insert-item ()
  "Insert a new library item heading at the end of the current org buffer.

Reads:
  - medium: `completing-read' over the section's allowed-mt list (skipped
    if there's only one allowed)
  - status: `completing-read' over the section's allowed-status list
    (skipped if there's only one)

Inserts:
  * TITLE
  :PROPERTIES:
  :CREATOR:
  :YEAR:
  :STATUS: <picked-status>
  :LAST_MODIFIED: <today ISO>
  <per-medium extras keys with empty values>
  :END:

Refuses outside `org-mode' or when section isn't a library section."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "a3-library-insert-item: current buffer is not org-mode"))
  (let* ((section (a3madkour-pub-author--require-library-section))
         (cfg (a3madkour-pub-library--config-for section))
         (default-mt (nth 1 cfg))
         (allowed-mt (nth 2 cfg))
         (allowed-status (nth 3 cfg))
         (medium (if (> (length allowed-mt) 1)
                     (completing-read "Medium: " allowed-mt nil t nil nil default-mt)
                   default-mt))
         (status (if (> (length allowed-status) 1)
                     (completing-read "Status: " allowed-status nil t)
                   (car allowed-status)))
         (today (format-time-string "%Y-%m-%d"))
         (extras (a3madkour-pub-library/extras-for medium)))
    (goto-char (point-max))
    (unless (or (= (point) (point-min))
                (eq (char-before) ?\n))
      (insert "\n"))
    (insert "* TITLE\n")
    (insert ":PROPERTIES:\n")
    (insert ":CREATOR: \n")
    (insert ":YEAR: \n")
    (insert (format ":STATUS: %s\n" status))
    (insert (format ":LAST_MODIFIED: %s\n" today))
    (dolist (spec extras)
      (insert (format ":%s: \n" (car spec))))
    (insert ":END:\n")))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: suite 652 → 657 (+5 insert-item tests).

---

## Task 8: a3-publish-jump-to-source

**Files:**
- Modify: `a3madkour-publish-author.el` — append URL parser helper + command
- Modify: `a3madkour-publish-author-test.el` — append five tests

Spec §4.6 — auto-detect URL from `content/<section>/<slug>/index.md`, manifest walk, fallback to completing-read.

- [ ] **Step 1: Write five failing tests**

```elisp
;; -- a3-publish-jump-to-source --

(defun a3-pub-author-test--stub-manifest (entries)
  "Build a manifest with ENTRIES (each (id url state))."
  `((notes . ,(vconcat
               (mapcar (lambda (e)
                         `((id . ,(nth 0 e))
                           (current_url . ,(nth 1 e))
                           (history . [])
                           (state . ,(nth 2 e))))
                       entries)))))

(ert-deftest a3madkour-pub-author-test/jump-auto-detect-happy ()
  "jump-to-source: buffer in content/<section>/<slug>/index.md → manifest hit → find-file."
  (let ((find-file-target nil))
    (cl-letf (((symbol-function 'buffer-file-name)
               (lambda (&optional _) "/site/content/essays/foo/index.md"))
              ((symbol-function 'a3madkour-pub-history/read-manifest)
               (lambda () (a3-pub-author-test--stub-manifest
                           '(("id-foo" "/essays/foo/" "live")))))
              ((symbol-function 'a3madkour-pub--id-to-file)
               (lambda (id) (when (equal id "id-foo") "/notes/foo.org")))
              ((symbol-function 'find-file)
               (lambda (path) (setq find-file-target path))))
      (a3-publish-jump-to-source))
    (should (equal find-file-target "/notes/foo.org"))))

(ert-deftest a3madkour-pub-author-test/jump-auto-detect-url-miss-user-errors ()
  "jump-to-source: URL not in manifest → user-error."
  (cl-letf (((symbol-function 'buffer-file-name)
             (lambda (&optional _) "/site/content/essays/missing/index.md"))
            ((symbol-function 'a3madkour-pub-history/read-manifest)
             (lambda () (a3-pub-author-test--stub-manifest
                         '(("id-foo" "/essays/foo/" "live"))))))
    (should-error (a3-publish-jump-to-source) :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/jump-fallback-completing-read ()
  "jump-to-source: buffer not in content/ → completing-read over manifest."
  (let ((find-file-target nil))
    (cl-letf (((symbol-function 'buffer-file-name)
               (lambda (&optional _) "/notes/scratch.org"))
              ((symbol-function 'a3madkour-pub-history/read-manifest)
               (lambda () (a3-pub-author-test--stub-manifest
                           '(("id-foo" "/essays/foo/" "live")))))
              ((symbol-function 'a3madkour-pub/note-metadata)
               (lambda (_f) '(:title "Foo")))
              ((symbol-function 'completing-read)
               (lambda (_p coll &rest _) (car coll)))
              ((symbol-function 'a3madkour-pub--id-to-file)
               (lambda (_id) "/notes/foo.org"))
              ((symbol-function 'find-file)
               (lambda (path) (setq find-file-target path))))
      (a3-publish-jump-to-source))
    (should (equal find-file-target "/notes/foo.org"))))

(ert-deftest a3madkour-pub-author-test/jump-empty-manifest-user-errors ()
  "jump-to-source: empty manifest → user-error."
  (cl-letf (((symbol-function 'buffer-file-name)
             (lambda (&optional _) "/notes/scratch.org"))
            ((symbol-function 'a3madkour-pub-history/read-manifest)
             (lambda () '((notes . [])))))
    (should-error (a3-publish-jump-to-source) :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/jump-id-to-file-nil-user-errors ()
  "jump-to-source: --id-to-file returns nil → user-error."
  (cl-letf (((symbol-function 'buffer-file-name)
             (lambda (&optional _) "/site/content/essays/foo/index.md"))
            ((symbol-function 'a3madkour-pub-history/read-manifest)
             (lambda () (a3-pub-author-test--stub-manifest
                         '(("id-foo" "/essays/foo/" "live")))))
            ((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil)))
    (should-error (a3-publish-jump-to-source) :type 'user-error)))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./run-tests.sh 2>&1 | tail -10
```

Expected: 5 failures.

- [ ] **Step 3: Implement the URL parser + `a3-publish-jump-to-source`**

Append to `a3madkour-publish-author.el`:

```elisp
;; -- a3-publish-jump-to-source --

(defun a3madkour-pub-author--buffer-content-url ()
  "Return the URL `/<section>/<slug>/' if the buffer is a content/ index.md.

Recognizes paths matching `.../content/<section>/<slug>/index.md', where
SECTION may itself contain one slash (`research/themes', `works/games',
`library/reading', etc).  Returns nil if the path doesn't match."
  (let ((path (buffer-file-name)))
    (when (and path
               (string-match
                "/content/\\([^/]+\\(?:/[^/]+\\)?\\)/\\([^/]+\\)/index\\.md\\'"
                path))
      (format "/%s/%s/" (match-string 1 path) (match-string 2 path)))))

(defun a3madkour-pub-author--manifest-entry-by-url (manifest url)
  "Walk MANIFEST notes vector; return the entry whose `current_url' = URL.
Filters to state ∈ {live, draft}.  Returns nil on miss.  Signals
`user-error' on ambiguity (two entries matching same URL)."
  (let* ((notes (alist-get 'notes manifest))
         (hits (cl-loop for i from 0 below (length notes)
                        for e = (aref notes i)
                        for s = (alist-get 'state e)
                        when (and (member s '("live" "draft"))
                                  (equal (alist-get 'current_url e) url))
                        collect e)))
    (cond
     ((null hits) nil)
     ((= (length hits) 1) (car hits))
     (t (user-error "a3-publish-jump-to-source: ambiguous URL in manifest: %s" url)))))

;;;###autoload
(defun a3-publish-jump-to-source ()
  "Jump from a published bundle to its org source.

Auto-detect path: if the current buffer's file matches
`.../content/<section>/<slug>/index.md', parse the URL `/<section>/<slug>/',
look up the manifest entry by `current_url', resolve its id to a file via
`a3madkour-pub--id-to-file', and `find-file' it.

Completing-read fallback: otherwise, prompt over all live+draft manifest
entries (formatted `<state>  <title> — <url>') and jump to the pick.

Refuses with `user-error' on empty manifest, missed URL, or id that doesn't
resolve to a file."
  (interactive)
  (let* ((manifest (a3madkour-pub-history/read-manifest))
         (notes (alist-get 'notes manifest)))
    (when (zerop (length notes))
      (user-error "a3-publish-jump-to-source: manifest is empty (nothing published yet)"))
    (let* ((auto-url (a3madkour-pub-author--buffer-content-url))
           (entry
            (if auto-url
                (or (a3madkour-pub-author--manifest-entry-by-url manifest auto-url)
                    (user-error "a3-publish-jump-to-source: URL %s not in manifest" auto-url))
              (let* ((candidates
                      (cl-loop for i from 0 below (length notes)
                               for e = (aref notes i)
                               for s = (alist-get 'state e)
                               when (member s '("live" "draft"))
                               collect e))
                     (collection
                      (mapcar
                       (lambda (e)
                         (let* ((id (alist-get 'id e))
                                (file (a3madkour-pub--id-to-file id))
                                (title (or (and file
                                                (ignore-errors
                                                  (plist-get
                                                   (a3madkour-pub/note-metadata file)
                                                   :title)))
                                           "(source missing)")))
                           (cons (format "%s  %s — %s"
                                         (alist-get 'state e)
                                         title
                                         (alist-get 'current_url e))
                                 e)))
                       candidates))
                     (pick (completing-read "Jump to: " (mapcar #'car collection) nil t)))
                (cdr (assoc pick collection)))))
           (id (alist-get 'id entry))
           (file (a3madkour-pub--id-to-file id)))
      (unless file
        (user-error "a3-publish-jump-to-source: manifest id %s does not resolve to a file (org-roam-db may be stale; try `M-x org-roam-db-sync')"
                    id))
      (find-file file))))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
./run-tests.sh 2>&1 | tail -5
```

Expected: suite 657 → 662 (+5 jump-to-source tests).

---

## Task 9: Verify a3-pub.sh assumption + run full suite

- [ ] **Step 1: Verify author.el is not referenced by a3-pub.sh**

```bash
cd ~/dotfiles/emacs-configs/custom/lisp && grep -n "author" a3-pub.sh
```

Expected: NO output (confirms the spec's interactive-only assumption — no `-l a3madkour-publish-author` wrapper update needed; this honors `feedback_plan_wrapper_script_updates.md`).

- [ ] **Step 2: Run full ert suite**

```bash
./run-tests.sh 2>&1 | tail -3
```

Expected: `Ran 662 tests, 662 results as expected, 0 unexpected` (629 prior + 33 new = 662). If the count is off by ±1, recount the tests in tasks 1–8 (skeleton 1 + wrapper 3 + status 5 + mark 6 + unmark 4 + extras 4 + item 5 + jump 5 = 33).

- [ ] **Step 3: Stage by exact path (bystander rule) + commit**

```bash
git status --short -- emacs-configs/custom/lisp/a3madkour-publish-author.el emacs-configs/custom/lisp/a3madkour-publish-author-test.el emacs-configs/custom/lisp/a3madkour-publish-library.el
```

Expected output:
```
M emacs-configs/custom/lisp/a3madkour-publish-library.el
?? emacs-configs/custom/lisp/a3madkour-publish-author.el
?? emacs-configs/custom/lisp/a3madkour-publish-author-test.el
```

```bash
git add emacs-configs/custom/lisp/a3madkour-publish-author.el \
        emacs-configs/custom/lisp/a3madkour-publish-author-test.el \
        emacs-configs/custom/lisp/a3madkour-publish-library.el && \
git commit -m "$(cat <<'EOF'
feat(tier-5.2): emacs publish-author helpers (6 commands)

New a3madkour-publish-author.el module shipping six interactive
commands for author-side publish-state management:

  a3-publish-mark / unmark / status     — toggle and query
                                          #+HUGO_PUBLISH:
  a3-library-insert-item / insert-extras — scaffold library-*.org
                                          entries
  a3-publish-jump-to-source              — manifest-driven nav from
                                          content/<section>/<slug>/
                                          index.md → org source

Compose existing primitives (sections registry, library config,
keywords API, publish manifest). No new tables, no a3-pub.sh wrapper
updates (interactive-only).

Two thin public wrappers in a3madkour-publish-library.el expose the
existing --double-dash config + extras tables to author.el without
reach-through.

Test coverage (+33 ert): skeleton, wrapper x3, status x5, mark x6,
unmark x4, insert-extras x4, insert-item x5, jump-to-source x5.

Suite 629 → 662.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)" && git log --oneline -1
```

Expected: new dotfiles HEAD commit with `feat(tier-5.2): ...` title.

---

## Task 10: Site close-out — roadmap row + memory

**Files:**
- Modify: `~/Sync/Workspace/a3madkour.github.io/docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md`
- Create: `~/Sync/Workspace/a3madkour.github.io/.claude/memory/project_tier_5_2_complete.md`
- Modify: `~/Sync/Workspace/a3madkour.github.io/.claude/memory/MEMORY.md`

- [ ] **Step 1: Mark roadmap row 5.2 ✓**

In `docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md`:

Replace the line:
```markdown
| 5.2 | ☐ **Emacs publish-author helpers** — `--mark-publish`, `--insert-library-item`, `--preview-section`, `--jump-to-source`, `--current-status`. Standalone module in `a3madkour-publish-author.el`. | [project-emacs-publish-helpers-followup](../../../.claude/memory/project_emacs_publish_helpers_followup.md) |
```

with:
```markdown
| 5.2 | ✓ **Emacs publish-author helpers** — 6 interactive commands in `a3madkour-publish-author.el`. → [project-tier-5-2-complete](../../../.claude/memory/project_tier_5_2_complete.md) (shipped 2026-06-08; mark / unmark / status / library-insert-item / library-insert-extras / jump-to-source; +33 ert; preview-section deferred to its own slice — Tier 5.3 once filed). | [project-emacs-publish-helpers-followup](../../../.claude/memory/project_emacs_publish_helpers_followup.md) |
```

Also update the status line and the §5 session-shape blurb:

Replace:
```markdown
**Status:** Active. Each tier maps to one or more future sessions. **Tier 5.2 + Tier 6 are the next sessions.** ...; Tier 5.1 closed 2026-06-08 (5.2 remains — own brainstorm cycle).
```

with:
```markdown
**Status:** Active. Each tier maps to one or more future sessions. **Tier 6 is the next session.** ...; Tier 5 closed 2026-06-08 (5.1 + 5.2 shipped; preview-section deferred as 5.3 stub).
```

Replace:
```markdown
**Session shape:** 5.1 is small (one session). 5.2 is its own brainstorm → spec → plan → ship cycle.
```

with:
```markdown
**Session shape:** 5.1 was small (one session, shipped 2026-06-08). 5.2 shipped 2026-06-08 in its own brainstorm → spec → plan → ship cycle.

**TIER 5.2 CLOSED 2026-06-08.** Six interactive commands shipped in one dotfiles commit; +33 ert (suite 629 → 662). preview-section deferred — open a Tier 5.3 row when authoring friction surfaces.
```

- [ ] **Step 2: Write the memory file**

Create `~/Sync/Workspace/a3madkour.github.io/.claude/memory/project_tier_5_2_complete.md`:

```markdown
---
name: project-tier-5-2-complete
description: Tier 5.2 closed 2026-06-08 — six interactive emacs publish-author helpers shipped in a3madkour-publish-author.el
metadata:
  type: project
---

# Tier 5.2 — emacs publish-author helpers — shipped 2026-06-08

Spec: dotfiles `docs/superpowers/specs/2026-06-08-emacs-publish-author-helpers-design.md` (commit `8767740`).
Plan: dotfiles `docs/superpowers/plans/2026-06-08-emacs-publish-author-helpers.md`.
Roadmap: site `docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md` Tier 5.2.
Source memo: [[emacs-publish-helpers-followup]] (site).

## What shipped

Single new dotfiles module `a3madkour-publish-author.el` + sibling test + two thin public wrappers in `a3madkour-publish-library.el`. Six interactive commands:

| Command | Purpose |
|---|---|
| `a3-publish-mark` | Idempotent insert/update of `#+HUGO_PUBLISH: t` + `#+HUGO_SECTION:` |
| `a3-publish-unmark` | Flip `#+HUGO_PUBLISH:` to `nil` (preserves `HUGO_SECTION`) |
| `a3-publish-status` | Minibuffer message describing current publish state |
| `a3-library-insert-item` | Scaffold new heading + drawer in `library-*.org` |
| `a3-library-insert-extras` | Add medium-specific extras to existing heading |
| `a3-publish-jump-to-source` | Auto-detect `content/<section>/<slug>/index.md` → org via manifest; completing-read fallback |

Two new public accessors in library.el: `a3madkour-pub-library/sections` and `a3madkour-pub-library/extras-for`. The existing `--double-dash` internals are unchanged.

Test coverage: 33 new ert tests (skeleton 1 + wrappers 3 + status 5 + mark 6 + unmark 4 + insert-extras 4 + insert-item 5 + jump-to-source 5). Suite 629 → 662.

## Why this design

- **Compose, don't duplicate**: sections registry, library config, extras table, keywords API, manifest walk — all already exist. No new tables = no drift.
- **Interactive only, no `a3-pub.sh` wrapper update**: verified via grep before commit. Honors [[feedback-plan-wrapper-script-updates]].
- **Synchronous + read-modify-write on the current buffer**: no async lifecycle (author wants immediate result). All edits confined to the buffer.
- **No init.el keybindings this slice**: author binds manually after merge per their preference.

## Deferred to follow-ups

- `a3-publish-preview-section` — needs new `--dry-run` plumbing on `a3-pub.sh` + `publish-living`. Own session. File as roadmap Tier 5.3 when triggered.
- Mode-line `mode-line-misc-info` segment showing publish state.
- Marginalia annotator for `jump-to-source`'s completing-read.
- `a3-library-bulk-import` — CSV → N headings.

## Files touched (dotfiles)

- `emacs-configs/custom/lisp/a3madkour-publish-author.el` — NEW (~250 lines)
- `emacs-configs/custom/lisp/a3madkour-publish-author-test.el` — NEW (~350 lines)
- `emacs-configs/custom/lisp/a3madkour-publish-library.el` — MODIFY (+2 public wrapper defuns)

Single dotfiles commit. Bystander rule honored (stage by exact path).

## Next slice

Per roadmap, **Tier 6 (About Now widget)** is the next session's queue head. 2.2/2.3/2.4 still trigger-gated; Tier 3 human-driven.
```

- [ ] **Step 3: Add MEMORY.md index entry**

Add after the existing `project_tier_5_1_complete.md` line:

```markdown
- [Tier 5.2 emacs publish-author helpers — shipped](project_tier_5_2_complete.md) — 2026-06-08 dotfiles; `a3madkour-publish-author.el` with 6 interactive commands (mark / unmark / status / library-insert-item / library-insert-extras / jump-to-source) + 2 public wrappers in library.el; +33 ert (suite 629 → 662); preview-section deferred to Tier 5.3 stub
```

- [ ] **Step 4: Commit site repo**

```bash
cd ~/Sync/Workspace/a3madkour.github.io && \
git add docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md \
        .claude/memory/MEMORY.md \
        .claude/memory/project_tier_5_2_complete.md && \
git commit -m "$(cat <<'EOF'
docs(roadmap): Tier 5.2 closed — emacs publish-author helpers

Marks 5.2 ✓ on the polish-and-bugfix roadmap and updates the
next-session pointer to Tier 6. Records the shipped batch in memory
(project_tier_5_2_complete.md) for future-session pickup.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)" && git log --oneline -1
```

Expected: new site HEAD commit with `docs(roadmap): Tier 5.2 closed ...` title.

- [ ] **Step 5: Surface push offer to the user (don't push automatically)**

Report to user:

> Tier 5.2 closed. Dotfiles commit `<hash>` + site commit `<hash>`. Nothing pushed — say `push both` when ready.

---

## Self-review notes

**Spec coverage check** (against `2026-06-08-emacs-publish-author-helpers-design.md`):

- §2 v1 scope (6 commands, preview-section deferred) — Tasks 3–8 + deferred-list in memory file (Task 10 Step 2). ✓
- §3.1 module layout — Task 1 + Task 9. ✓
- §3.4 two thin public wrappers — Task 2. ✓
- §4.1 mark contract — Task 4 (incl. cross-section guard with abort semantics). ✓
- §4.2 unmark contract — Task 5. ✓
- §4.3 status branches — Task 3 (4 branches + refuse). ✓
- §4.4 insert-item contract — Task 7 (incl. single-medium / single-status skip). ✓
- §4.5 insert-extras contract — Task 6 (incl. add-missing-only). ✓
- §4.6 jump-to-source contract — Task 8 (auto-detect + fallback + 3 user-error paths). ✓
- §5 error handling — covered by per-task refuse tests. ✓
- §6 testing — count matches (33 new tests). ✓
- §7 commit + file layout — Tasks 9 + 10. ✓
- §8 v2 follow-ups — listed in memory file (Task 10 Step 2). ✓

**Type / signature consistency**:
- `a3madkour-pub-author--upsert-keyword KEY VAL` (Task 4) reused by `a3-publish-unmark` (Task 5). ✓
- `a3madkour-pub-author--require-library-section` (Task 6) reused by `a3-library-insert-item` (Task 7). ✓
- `a3madkour-pub-author--default-medium-for SECTION` (Task 6) used in Task 6 only — Task 7 derives medium directly from `--config-for` since it also needs the allowed-mt list. Intentional. ✓

**Placeholder scan**: none.
