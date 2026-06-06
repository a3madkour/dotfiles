# D.2 Figure-Ref Bundled Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two B.4 asset pipeline bugs blocking D.2 figure-ref round-trip verification.

**Architecture:** TDD-driven sequential implementation. 9 commits across 5 elisp modules in dotfiles + 1 org fixture in `~/org/essays/`. Each task lands red→green→commit. Test runner is `./run-tests.sh` in `emacs-configs/custom/lisp/`. Suite goes 525 → ~539 green.

**Tech Stack:** Emacs Lisp · ert · ox-hugo · org-roam.

**Spec:** `docs/superpowers/specs/2026-06-05-d2-figure-ref-bundled-fix-design.md` (commit `fc6ccbd`).

---

## File Structure

**Modify (in `emacs-configs/custom/lisp/`):**
- `a3madkour-publish-rewrite.el` — Tasks 1, 2
- `a3madkour-publish-rewrite-test.el` — Tasks 1, 2
- `a3madkour-publish-assets.el` — Tasks 3, 4, 5
- `a3madkour-publish-assets-test.el` — Tasks 3, 4, 5
- `a3madkour-publish-essays.el` — Task 6a
- `a3madkour-publish-essays-test.el` — Tasks 6a, 8
- `a3madkour-publish-garden.el` — Task 6b
- `a3madkour-publish-garden-test.el` — Task 6b
- `a3madkour-publish-research.el` — Task 6c
- `a3madkour-publish-research-test.el` — Task 6c

**External fixture (outside dotfiles repo, in `~/org/essays/`):**
- `example-multi.org` — Task 7 (add `:ID:` drawer)
- `diagram-1.svg` → `assets/<UUID>/diagram-1.svg` — Task 7 (file move)

**Test runner (one command for the whole suite):**
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh
```

Expected baseline before Task 1: 525 tests, all green.

---

## Task 1: `--strip-file-prefix-if-asset` helper

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-rewrite.el` (add helper near other `--link-*` helpers, ~line 125)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-rewrite-test.el` (append 5 tests)

- [ ] **Step 1: Write 5 failing tests**

Append to `a3madkour-publish-rewrite-test.el` (after the last test, before the `(provide …)` form):

```elisp
;;; --strip-file-prefix-if-asset --- normalize `file:' prefix on asset links.

(ert-deftest a3madkour-pub-rewrite-test/strip-file-prefix-on-asset-svg ()
  "`file:diagram.svg' strips the `file:' prefix (asset extension)."
  (should (equal (a3madkour-pub--strip-file-prefix-if-asset "file:diagram.svg")
                 "diagram.svg")))

(ert-deftest a3madkour-pub-rewrite-test/strip-file-prefix-on-asset-png ()
  "`file:hero.png' strips the `file:' prefix (asset extension)."
  (should (equal (a3madkour-pub--strip-file-prefix-if-asset "file:hero.png")
                 "hero.png")))

(ert-deftest a3madkour-pub-rewrite-test/preserve-file-prefix-on-org-target ()
  "`file:other-note.org' preserves prefix — org targets stay note-link dispatch."
  (should (equal (a3madkour-pub--strip-file-prefix-if-asset "file:other-note.org")
                 "file:other-note.org")))

(ert-deftest a3madkour-pub-rewrite-test/strip-preserves-bare-asset-path ()
  "Bare asset path (no `file:' prefix) returned unchanged."
  (should (equal (a3madkour-pub--strip-file-prefix-if-asset "diagram.svg")
                 "diagram.svg")))

(ert-deftest a3madkour-pub-rewrite-test/strip-preserves-id-link ()
  "`id:' prefix returned unchanged."
  (should (equal (a3madkour-pub--strip-file-prefix-if-asset "id:abc-def")
                 "id:abc-def")))
```

- [ ] **Step 2: Run tests, verify they fail**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "strip-file-prefix\|strip-preserves" | head -20
```

Expected: 5 `failed` lines (function `a3madkour-pub--strip-file-prefix-if-asset` not defined).

- [ ] **Step 3: Write the helper**

In `a3madkour-publish-rewrite.el`, insert before `a3madkour-pub--asset-shaped-link-p` (search for `(defun a3madkour-pub--asset-shaped-link-p`):

```elisp
(defun a3madkour-pub--strip-file-prefix-if-asset (path)
  "Return PATH with a `file:' prefix stripped if the remainder is asset-shaped.

Mirrors the normalization in `a3madkour-pub--extract-asset-refs' so both
walkers classify `[[file:asset.ext]]' and `[[asset.ext]]' identically.

Paths without `file:' prefix are returned unchanged.  `file:' paths whose
target has a `.org' extension are returned unchanged (kept as note links)."
  (cond
   ((not (string-prefix-p "file:" path)) path)
   ((let ((bare (substring path 5)))
      (and (file-name-extension bare)
           (not (member (file-name-extension bare) '("org")))))
    (substring path 5))
   (t path)))
```

- [ ] **Step 4: Run tests, verify they pass**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: final line shows `Ran 530 tests, 530 results as expected` (525 baseline + 5 new).

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-rewrite.el emacs-configs/custom/lisp/a3madkour-publish-rewrite-test.el && git commit -m "$(cat <<'EOF'
feat(d2-figref): --strip-file-prefix-if-asset helper

Mirror of cea5d2d's normalization for the buffer-rewriter scanner.
Returns PATH with `file:' prefix stripped iff the remainder has a
non-`.org' extension; otherwise returns PATH unchanged.

5 new ert tests. Suite 525 -> 530 green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Wire helper into `rewrite-link`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-rewrite.el` (function `rewrite-link`, ~line 285)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-rewrite-test.el` (append 2 end-to-end tests)

- [ ] **Step 1: Write 2 failing end-to-end tests**

Append to `a3madkour-publish-rewrite-test.el`:

```elisp
;;; rewrite-link: file: prefix on asset dispatches to asset-link path.

(ert-deftest a3madkour-pub-rewrite-test/rewrite-link-asset-via-file-prefix ()
  "[[file:diagram.svg]] dispatches to rewrite-asset-link, emits <img>."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-fileprefix-" t))))
    (unwind-protect
        (let ((svg (expand-file-name "diagram.svg" tmp)))
          (with-temp-file svg (insert "<svg/>"))
          (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                     (lambda (_id) nil))
                    ((symbol-function 'a3madkour-pub/note-slug)
                     (lambda (_id) nil))
                    ((symbol-function 'a3madkour-pub--asset-resolve-path)
                     (lambda (path _src)
                       (list :kind 'page
                             :abs-path (expand-file-name path tmp)
                             :rel-path (concat "page/x/" path)))))
            (let ((result (a3madkour-pub/rewrite-link
                           "[[file:diagram.svg]]" nil)))
              (should (plist-get result :html))
              (should (string-match-p "<img " (plist-get result :html)))
              (should (string-match-p "diagram.svg" (plist-get result :html))))))
      (delete-directory tmp t))))

(ert-deftest a3madkour-pub-rewrite-test/rewrite-link-file-prefix-org-target-unchanged ()
  "[[file:other.org]] still dispatches to --rewrite-file-link (note-link path)."
  (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
             (lambda (_id) nil))
            ((symbol-function 'a3madkour-pub--file-top-level-id)
             (lambda (_f) nil)))
    (let ((result (a3madkour-pub/rewrite-link
                   "[[file:other.org][Other]]" nil)))
      (should (plist-get result :inert))
      (should (cl-some (lambda (w) (string-match-p "lacks :ID:" w))
                       (plist-get result :warnings))))))
```

- [ ] **Step 2: Run tests, verify they fail**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "rewrite-link-asset-via-file-prefix\|rewrite-link-file-prefix-org-target" | head -10
```

Expected: `rewrite-link-asset-via-file-prefix` fails (`:inert` instead of `:html` — file: still routed to note-link path). `rewrite-link-file-prefix-org-target-unchanged` passes (existing behavior).

- [ ] **Step 3: Wire helper into `rewrite-link`**

In `a3madkour-publish-rewrite.el`, locate the `rewrite-link` function (search for `(defun a3madkour-pub/rewrite-link`). The let-binding currently looks like:

```elisp
(let* ((parsed (a3madkour-pub--parse-org-link org-link))
       (path (plist-get parsed :path))
       (text (plist-get parsed :text))
       (scheme (a3madkour-pub--link-scheme path)))
```

Replace it with:

```elisp
(let* ((parsed (a3madkour-pub--parse-org-link org-link))
       (raw-path (plist-get parsed :path))
       (path (a3madkour-pub--strip-file-prefix-if-asset raw-path))
       (text (plist-get parsed :text))
       (scheme (a3madkour-pub--link-scheme path)))
```

The cond body below is unchanged — `scheme` is now computed on the stripped path, so `file:asset.svg` flows to the `--asset-shaped-link-p` arm.

- [ ] **Step 4: Run tests, verify they pass**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: `Ran 532 tests, 532 results as expected` (530 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-rewrite.el emacs-configs/custom/lisp/a3madkour-publish-rewrite-test.el && git commit -m "$(cat <<'EOF'
fix(d2-figref): rewrite-link routes [[file:asset.ext]] to asset path

Bug 1 of the bundled D.2 figure-ref fix. The pre-export buffer rewriter
dispatched `file:' scheme to --rewrite-file-link, which expects a `:ID:'-
bearing org-note target. SVG/PNG/PDF assets via [[file:...]] hit the
note-link path and got :inert-flattened, erasing the link from the
exported markdown.

Symmetric fix to cea5d2d, which patched the same gap in
--extract-asset-refs. Both walkers now apply the same prefix
normalization.

2 new end-to-end ert tests. Suite 530 -> 532 green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `asset-validate-and-copy` signature change

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-assets.el` (function `asset-validate-and-copy`, ~line 423)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-assets-test.el` (existing tests may need to skip the new arg; add 2 new tests)

- [ ] **Step 1: Write 2 failing tests**

Append to `a3madkour-publish-assets-test.el`:

```elisp
;;; asset-validate-and-copy: source-note-id threading.

(ert-deftest a3madkour-pub-assets-test/validate-threads-source-note-id ()
  "Caller-supplied source-note-id is forwarded to rewrite-asset-link."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-validate-thread-" t)))
        (captured-source-note-id nil))
    (unwind-protect
        (let ((org-file (expand-file-name "x.org" tmp))
              (svg (expand-file-name "diagram.svg" tmp))
              (bundle (file-name-as-directory
                       (expand-file-name "bundle/" tmp))))
          (make-directory bundle t)
          (with-temp-file svg (insert "<svg/>"))
          (with-temp-file org-file
            (insert "* H\n[[file:diagram.svg]]\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/rewrite-asset-link)
                     (lambda (_path _text source-note-id &optional _dry-run)
                       (setq captured-source-note-id source-note-id)
                       (list :inert "(stub)" :warnings nil))))
            (a3madkour-pub/asset-validate-and-copy
             org-file bundle "real-note-id-42"))
          (should (equal captured-source-note-id "real-note-id-42")))
      (delete-directory tmp t))))

(ert-deftest a3madkour-pub-assets-test/validate-nil-source-note-id-tolerated ()
  "Omitting source-note-id passes nil through; no user-error fires."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-validate-nil-" t))))
    (unwind-protect
        (let ((org-file (expand-file-name "x.org" tmp))
              (svg (expand-file-name "diagram.svg" tmp))
              (bundle (file-name-as-directory
                       (expand-file-name "bundle/" tmp)))
              (captured-source-note-id 'unset))
          (make-directory bundle t)
          (with-temp-file svg (insert "<svg/>"))
          (with-temp-file org-file
            (insert "* H\n[[file:diagram.svg]]\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/rewrite-asset-link)
                     (lambda (_path _text source-note-id &optional _dry-run)
                       (setq captured-source-note-id source-note-id)
                       (list :inert "(stub)" :warnings nil))))
            ;; Should NOT signal — formerly threw user-error on "from-validate".
            (a3madkour-pub/asset-validate-and-copy org-file bundle))
          (should (null captured-source-note-id)))
      (delete-directory tmp t))))
```

- [ ] **Step 2: Run tests, verify they fail**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "validate-threads\|validate-nil-source" | head -10
```

Expected: both fail. `validate-threads` fails because the third arg isn't accepted — currently it's `dry-run`, so `"real-note-id-42"` is treated as truthy dry-run. `validate-nil-source` fails because the rewrite-asset-link receives `"from-validate"` (hardcoded sentinel) rather than nil.

- [ ] **Step 3: Change the signature + body**

In `a3madkour-publish-assets.el`, locate `(defun a3madkour-pub/asset-validate-and-copy` (~line 423).

Replace the signature line:
```elisp
(defun a3madkour-pub/asset-validate-and-copy (org-file bundle-dest-dir &optional dry-run)
```
with:
```elisp
(defun a3madkour-pub/asset-validate-and-copy
    (org-file bundle-dest-dir &optional source-note-id dry-run)
```

In the docstring, replace the paragraph that begins `Caller contract: this function passes "from-validate" …` (lines ~443–451) with:

```
SOURCE-NOTE-ID is the org-roam :ID: (UUID) of the source note containing
the asset references.  When provided, the per-asset cross-namespace check
runs against the source's slug.  When nil, the cross-namespace check is
suppressed — appropriate for tests or for sources without an :ID:.  Sub-
project B's per-section publishers thread their `:id' here; see
`a3madkour-pub-essays/publish-essay-file' for the canonical caller.

DRY-RUN, when non-nil, propagates to rewrite-asset-link's auto-remediation
and suppresses file I/O for copies + cleanup.
```

Then locate the call site (~line 465):
```elisp
(rewrite-result (a3madkour-pub/rewrite-asset-link
                 abs-path text "from-validate" dry-run))
```
Replace `"from-validate"` with `source-note-id`:
```elisp
(rewrite-result (a3madkour-pub/rewrite-asset-link
                 abs-path text source-note-id dry-run))
```

- [ ] **Step 4: Run tests, check status**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -10
```

Expected: `validate-threads-source-note-id` passes. `validate-nil-source-note-id-tolerated` still fails (the rewrite-asset-link still throws on nil — Task 4 fixes that).

(Verified ahead of plan-writing: all existing `asset-validate-and-copy` callers in `assets-test.el` use the 2-arg form, so the new optional `source-note-id` slot inserted before `dry-run` doesn't break existing tests.)

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-assets.el emacs-configs/custom/lisp/a3madkour-publish-assets-test.el && git commit -m "$(cat <<'EOF'
fix(d2-figref): asset-validate-and-copy accepts source-note-id

Bug 2 part a. Removes the hardcoded "from-validate" sentinel and adds
source-note-id as an explicit optional parameter, matching the contract
the function's docstring always declared. B publishers will thread their
note id through in a later commit.

Tests for nil source-note-id will pass once Task 4 lands nil-tolerance
in rewrite-asset-link.

2 new ert tests. Existing asset tests that passed dry-run positionally
updated to the new arg order.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `rewrite-asset-link` nil source-note-id tolerance

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-assets.el` (function `rewrite-asset-link`, ~line 284)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-assets-test.el` (append 1 test)

- [ ] **Step 1: Write 1 failing test**

Append to `a3madkour-publish-assets-test.el`:

```elisp
;;; rewrite-asset-link: nil source-note-id suppresses cross-namespace check.

(ert-deftest a3madkour-pub-assets-test/rewrite-asset-nil-source-skips-cross-namespace ()
  "Nil source-note-id: cross-namespace check is suppressed; :html still emitted."
  (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
             (lambda (_id) nil))
            ((symbol-function 'a3madkour-pub/note-slug)
             (lambda (_id)
               (error "note-slug should not run when source-note-id is nil")))
            ((symbol-function 'a3madkour-pub--asset-resolve-path)
             (lambda (_path _src)
               (list :kind 'page
                     :abs-path "/tmp/x/page/other-slug/foo.svg"
                     :rel-path "page/other-slug/foo.svg"))))
    (let ((result (a3madkour-pub/rewrite-asset-link
                   "/tmp/x/page/other-slug/foo.svg" "foo.svg" nil)))
      (should (plist-get result :html))
      (should (string-match-p "<img " (plist-get result :html))))))
```

This test asserts BOTH that note-slug is not called for nil source-note-id AND that the cross-namespace check is skipped.

The test also reverifies Bug 2: previously the unconditional call to note-slug crashed before any check could run.

- [ ] **Step 2: Run test, verify it fails**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "rewrite-asset-nil-source-skips-cross-namespace" | head -5
```

Expected: failure — `note-slug should not run when source-note-id is nil` (the test errors out from the stubbed note-slug).

- [ ] **Step 3: Add nil-tolerance**

In `a3madkour-publish-assets.el`, locate `(defun a3madkour-pub/rewrite-asset-link` (~line 284).

The let-binding currently starts:
```elisp
(let* ((source-file (a3madkour-pub--id-to-file source-note-id))
       (source-slug (a3madkour-pub/note-slug source-note-id))
       ...
```

Replace `source-slug` line to gate on source-note-id:
```elisp
(let* ((source-file (a3madkour-pub--id-to-file source-note-id))
       (source-slug (and source-note-id
                         (a3madkour-pub/note-slug source-note-id)))
       ...
```

Then locate the cross-namespace cond arm (~line 318):
```elisp
((and (eq kind 'page)
      (a3madkour-pub--asset-cross-namespace-p resolved source-slug))
 ...)
```

Add a `source-slug` guard so the check is skipped when nil:
```elisp
((and (eq kind 'page)
      source-slug
      (a3madkour-pub--asset-cross-namespace-p resolved source-slug))
 ...)
```

- [ ] **Step 4: Run tests, verify they pass**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: `Ran 535 tests, 535 results as expected`. Task 3's previously-failing `validate-nil-source-note-id-tolerated` also turns green because rewrite-asset-link no longer calls note-slug on nil.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-assets.el emacs-configs/custom/lisp/a3madkour-publish-assets-test.el && git commit -m "$(cat <<'EOF'
fix(d2-figref): rewrite-asset-link tolerates nil source-note-id

Bug 2 part b. note-slug is only called when source-note-id is non-nil;
the cross-namespace check is gated on source-slug. Closes the user-error
on the previously-hardcoded "from-validate" sentinel — tests and callers
that don't know a source id now pass nil cleanly.

1 new ert test. Suite 533 -> 535 green (Task 3's nil-tolerated test also
turns green now).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `--asset-resolve-path` essays-aware branch

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-assets.el` (function `--asset-resolve-path`, ~line 61; add helper `--essay-slug-from-source-file`)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-assets-test.el` (append 3 tests)

- [ ] **Step 1: Write 3 failing tests**

Append to `a3madkour-publish-assets-test.el`:

```elisp
;;; asset-resolve-path: essays-aware branch.

(ert-deftest a3madkour-pub-assets-test/resolve-path-essays-source-uses-assets-id-dir ()
  "Source under essays-dir with :ID: → resolves to essays-dir/assets/<id>/."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-resolve-essays-" t))))
    (unwind-protect
        (let* ((essays-dir (file-name-as-directory
                             (expand-file-name "essays/" tmp)))
               (id "11111111-2222-3333-4444-555555555555")
               (org-file (expand-file-name "essay.org" essays-dir))
               (asset-dir (file-name-as-directory
                            (expand-file-name (format "assets/%s/" id) essays-dir)))
               (asset (expand-file-name "diagram.svg" asset-dir)))
          (make-directory asset-dir t)
          (with-temp-file org-file
            (insert (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: e\n" id)))
          (with-temp-file asset (insert "<svg/>"))
          (let ((a3madkour-pub/essays-dir essays-dir)
                (a3madkour-pub-canonical-asset-root
                 (expand-file-name "notes/assets/" tmp)))
            (let ((result (a3madkour-pub--asset-resolve-path "diagram.svg" org-file)))
              (should (eq 'page (plist-get result :kind)))
              (should (equal asset (plist-get result :abs-path))))))
      (delete-directory tmp t))))

(ert-deftest a3madkour-pub-assets-test/resolve-path-essays-fallback-to-canonical-root ()
  "Source under essays-dir but no file in assets/<id>/ → falls through to existing logic."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-resolve-fallback-" t))))
    (unwind-protect
        (let* ((essays-dir (file-name-as-directory
                             (expand-file-name "essays/" tmp)))
               (id "11111111-2222-3333-4444-555555555555")
               (org-file (expand-file-name "essay.org" essays-dir)))
          (make-directory essays-dir t)
          (with-temp-file org-file
            (insert (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: e\n" id)))
          ;; assets/<id>/diagram.svg does NOT exist; fall through.
          (let ((a3madkour-pub/essays-dir essays-dir)
                (a3madkour-pub-canonical-asset-root
                 (expand-file-name "notes/assets/" tmp)))
            (let ((result (a3madkour-pub--asset-resolve-path "diagram.svg" org-file)))
              ;; Falls back: not found anywhere → :missing.
              (should (eq 'missing (plist-get result :kind))))))
      (delete-directory tmp t))))

(ert-deftest a3madkour-pub-assets-test/resolve-path-non-essays-source-unchanged ()
  "Source under garden (not essays) → existing canonical-root classification unchanged."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-resolve-nonessays-" t))))
    (unwind-protect
        (let* ((notes-dir (file-name-as-directory
                            (expand-file-name "notes/" tmp)))
               (assets-root (file-name-as-directory
                              (expand-file-name "assets/page/foo/" notes-dir)))
               (org-file (expand-file-name "note.org" notes-dir))
               (asset (expand-file-name "diagram.svg" assets-root)))
          (make-directory assets-root t)
          (with-temp-file org-file (insert "* H\n"))
          (with-temp-file asset (insert "<svg/>"))
          (let ((a3madkour-pub/essays-dir
                  (expand-file-name "essays/" tmp))   ; essays-dir set but source NOT under it
                (a3madkour-pub-canonical-asset-root
                 (expand-file-name "assets/" notes-dir)))
            (let ((result (a3madkour-pub--asset-resolve-path
                           "./assets/page/foo/diagram.svg" org-file)))
              (should (eq 'page (plist-get result :kind)))
              (should (equal asset (plist-get result :abs-path))))))
      (delete-directory tmp t))))
```

- [ ] **Step 2: Run tests, verify they fail**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "resolve-path-essays\|resolve-path-non-essays" | head -10
```

Expected: `resolve-path-essays-source-uses-assets-id-dir` fails (essays-aware branch doesn't exist; falls through to `:missing` because the sibling `essays-dir/diagram.svg` doesn't exist). The other two pass (no behavior change needed).

- [ ] **Step 3: Add helper + essays-aware branch**

In `a3madkour-publish-assets.el`, near the top of the file (after the require / defvar block, before `--asset-resolve-path`), add the helper:

```elisp
(defun a3madkour-pub--essay-slug-from-source-file (source-file)
  "Return the published slug for SOURCE-FILE, or nil.
Thin wrapper around `a3madkour-pub/note-metadata' that pulls `:slug'.
Used by `--asset-resolve-path' to synthesize the per-essay namespace
key on the essays-aware branch."
  (when source-file
    (plist-get (a3madkour-pub/note-metadata source-file) :slug)))
```

Then locate `(defun a3madkour-pub--asset-resolve-path` (~line 61). Replace the let-binding to add the essays-aware lookup and use it in the cond:

```elisp
(defun a3madkour-pub--asset-resolve-path (path source-file)
  "Normalize PATH + classify against the canonical asset root.

PATH may be relative (resolved against SOURCE-FILE's directory), absolute,
or tilde-expanded.  SOURCE-FILE may be nil — in which case relative paths
resolve against `default-directory'.

When SOURCE-FILE is under `a3madkour-pub/essays-dir' AND carries a top-
level :ID:, an essays-aware lookup runs first: PATH is looked up under
`essays-dir/assets/<source-id>/'.  If found, classification is `:page'
with the per-essay slug as the namespace key.  This matches the
convention enforced by `a3madkour-pub-essays--copy-asset-dir'.

Returns a plist:
  (:kind page|shared|out-of-root|missing
   :abs-path \"/canonical/absolute/path\"
   :rel-path \"page/<slug>/<filename>\" or \"shared/<filename>\" or nil)

`:kind missing' takes priority over location-based classification — a
non-existent file at a canonical-looking path still reports missing."
  (let* ((source-dir (or (and source-file (file-name-directory source-file))
                         default-directory))
         (essays-dir (and (boundp 'a3madkour-pub/essays-dir)
                          a3madkour-pub/essays-dir))
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
     (essays-page-path
      (let ((essay-slug (a3madkour-pub--essay-slug-from-source-file source-file)))
        (list :kind 'page :abs-path abs
              :rel-path (format "page/%s/%s"
                                (or essay-slug "")
                                (file-name-nondirectory abs)))))
     ((string-prefix-p root-page abs)
      (list :kind 'page :abs-path abs
            :rel-path (substring abs (length root))))
     ((string-prefix-p root-shared abs)
      (list :kind 'shared :abs-path abs
            :rel-path (substring abs (length root))))
     (t
      (list :kind 'out-of-root :abs-path abs :rel-path nil)))))
```

Note: the function references `a3madkour-pub--file-top-level-id` — this lives in `a3madkour-publish-rewrite.el`. assets.el needs to `(require 'a3madkour-publish-rewrite)` if it doesn't already. Verify:
```bash
grep -n "require 'a3madkour-publish" ~/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-assets.el
```
If `a3madkour-publish-rewrite` is missing from the requires, add it next to the other requires at the top.

- [ ] **Step 4: Run tests, verify they pass**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: `Ran 538 tests, 538 results as expected` (535 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-assets.el emacs-configs/custom/lisp/a3madkour-publish-assets-test.el && git commit -m "$(cat <<'EOF'
feat(d2-figref): asset-resolve-path essays-aware branch

When source-file is under a3madkour-pub/essays-dir AND has a top-level
:ID:, asset paths are looked up first under essays-dir/assets/<id>/
(the per-essay assets convention enforced by essays--copy-asset-dir).
Falls through to canonical-asset-root classification when the per-
essay lookup misses.

Adds --essay-slug-from-source-file helper (thin note-metadata wrapper)
to synthesize the rel-path's namespace key.

3 new ert tests. Suite 535 -> 538 green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6a: Essays publisher threads `id`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-essays.el` (line 255)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-essays-test.el` (append 1 test)

- [ ] **Step 1: Write 1 failing test**

Append to `a3madkour-publish-essays-test.el`:

```elisp
;;; B publisher threads id into asset-validate-and-copy.

(ert-deftest a3madkour-pub-essays-test/publisher-threads-id-to-asset-validate ()
  "publish-essay-file passes the note's :id as source-note-id to asset-validate-and-copy."
  (let ((captured-id 'unset))
    (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
               (lambda (_f)
                 (list :id "essay-id-99" :slug "test-essay" :section "essays"
                       :state 'live :title "T")))
              ((symbol-function 'a3madkour-pub/note-url)
               (lambda (_f) "/essays/test-essay/"))
              ((symbol-function 'a3madkour-pub-essays--site-root)
               (lambda () "/tmp/site-stub/"))
              ((symbol-function 'a3madkour-pub-rewrite/rewrite-to-tmp-file)
               (lambda (file _id _tag) file))
              ((symbol-function 'a3madkour-pub-export/export-file)
               (lambda (_f) (list :body "stub-body" :frontmatter nil)))
              ((symbol-function 'a3madkour-pub-essays--scan-has-flags)
               (lambda (_b) nil))
              ((symbol-function 'a3madkour-pub-frontmatter/normalize)
               (lambda (_section raw _f) raw))
              ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
               (lambda (_org _bundle &optional source-note-id &rest _)
                 (setq captured-id source-note-id)
                 (list :copied nil :removed nil :warnings nil :errors nil)))
              ((symbol-function 'a3madkour-pub-essays--copy-asset-dir)
               (lambda (_id _b) nil))
              ((symbol-function 'a3madkour-pub-essays--write-if-different)
               (lambda (_p _c) nil))
              ((symbol-function 'a3madkour-pub-essays--render-frontmatter)
               (lambda (_n) ""))
              ((symbol-function 'a3madkour-pub-history/record-publish)
               (lambda (_id _url _state) nil)))
      (a3madkour-pub-essays/publish-essay-file "/tmp/stub.org")
      (should (equal captured-id "essay-id-99")))))
```

- [ ] **Step 2: Run test, verify it fails**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "publisher-threads-id-to-asset-validate" | head -5
```

Expected: failure — `captured-id` is `'unset` because the current call site passes only 2 args.

- [ ] **Step 3: Update the call site**

In `a3madkour-publish-essays.el`, locate the `asset-validate-and-copy` call (~line 255):
```elisp
    (a3madkour-pub/asset-validate-and-copy file bundle-dir)
```
Replace with:
```elisp
    (a3madkour-pub/asset-validate-and-copy file bundle-dir id)
```

The `id` is already bound in scope (line 226: `(id (plist-get md :id))`).

- [ ] **Step 4: Run tests, verify they pass**

Run:
```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: `Ran 539 tests, 539 results as expected` (538 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-essays.el emacs-configs/custom/lisp/a3madkour-publish-essays-test.el && git commit -m "$(cat <<'EOF'
fix(d2-figref): essays publisher threads :id to asset-validate-and-copy

Bug 2 part c (essays). The note's :id (from note-metadata) now flows
into asset-validate-and-copy as source-note-id, enabling per-asset
cross-namespace checks and the essays-aware asset resolution branch.

1 new ert test. Suite 538 -> 539 green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6b: Garden publisher threads `id`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-garden.el` (line 123)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-garden-test.el` (append 1 test)

- [ ] **Step 1: Write 1 failing test**

Append to `a3madkour-publish-garden-test.el`. Garden's helper names: `garden--site-root`, `garden--write-if-different`, `garden--render-frontmatter`; entry point `garden/publish-garden-file`; `id` is bound at `garden.el:104`.

```elisp
(ert-deftest a3madkour-pub-garden-test/publisher-threads-id-to-asset-validate ()
  "publish-garden-file passes the note's :id as source-note-id to asset-validate-and-copy."
  (let ((captured-id 'unset))
    (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
               (lambda (_f)
                 (list :id "garden-id-77" :slug "test-note" :section "garden"
                       :state 'live :title "T")))
              ((symbol-function 'a3madkour-pub/note-url)
               (lambda (_f) "/garden/test-note/"))
              ((symbol-function 'a3madkour-pub-garden--site-root)
               (lambda () "/tmp/site-stub/"))
              ((symbol-function 'a3madkour-pub-rewrite/rewrite-to-tmp-file)
               (lambda (file _id _tag) file))
              ((symbol-function 'a3madkour-pub-export/export-file)
               (lambda (_f) (list :body "stub-body" :frontmatter nil)))
              ((symbol-function 'a3madkour-pub-frontmatter/normalize)
               (lambda (_section raw _f) raw))
              ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
               (lambda (_org _bundle &optional source-note-id &rest _)
                 (setq captured-id source-note-id)
                 (list :copied nil :removed nil :warnings nil :errors nil)))
              ((symbol-function 'a3madkour-pub-garden--write-if-different)
               (lambda (_p _c) nil))
              ((symbol-function 'a3madkour-pub-garden--render-frontmatter)
               (lambda (_n) ""))
              ((symbol-function 'a3madkour-pub-history/record-publish)
               (lambda (_id _url _state) nil)))
      (a3madkour-pub-garden/publish-garden-file "/tmp/stub.org")
      (should (equal captured-id "garden-id-77")))))
```

- [ ] **Step 2: Run test, verify it fails**

```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "garden-test/publisher-threads-id" | head -5
```

Expected: failure.

- [ ] **Step 3: Update the call site**

In `a3madkour-publish-garden.el` line 123, change:
```elisp
    (a3madkour-pub/asset-validate-and-copy file bundle-dir)
```
to:
```elisp
    (a3madkour-pub/asset-validate-and-copy file bundle-dir id)
```

`id` is already bound at line 104: `(id (plist-get (a3madkour-pub/note-metadata file) :id))`.

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: `Ran 540 tests, 540 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-garden.el emacs-configs/custom/lisp/a3madkour-publish-garden-test.el && git commit -m "$(cat <<'EOF'
fix(d2-figref): garden publisher threads :id to asset-validate-and-copy

Bug 2 part c (garden). Mirror of the essays change in the previous commit.

1 new ert test. Suite 539 -> 540 green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6c: Research publisher threads `id`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-research.el` (line 340)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-research-test.el` (append 1 test)

- [ ] **Step 1: Write 1 failing test**

Research helper names: `research--site-root`, `research--write-if-different`, `research--render-frontmatter`; entry point `research/publish-research-file`; `id` is bound at `research.el:295`.

Append to `a3madkour-publish-research-test.el`:

```elisp
(ert-deftest a3madkour-pub-research-test/publisher-threads-id-to-asset-validate ()
  "publish-research-file passes the note's :id as source-note-id to asset-validate-and-copy."
  (let ((captured-id 'unset))
    (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
               (lambda (_f)
                 (list :id "research-id-55" :slug "test-theme" :section "research"
                       :state 'live :title "T")))
              ((symbol-function 'a3madkour-pub/note-url)
               (lambda (_f) "/research/test-theme/"))
              ((symbol-function 'a3madkour-pub-research--site-root)
               (lambda () "/tmp/site-stub/"))
              ((symbol-function 'a3madkour-pub-rewrite/rewrite-to-tmp-file)
               (lambda (file _id _tag) file))
              ((symbol-function 'a3madkour-pub-export/export-file)
               (lambda (_f) (list :body "stub-body" :frontmatter nil)))
              ((symbol-function 'a3madkour-pub-frontmatter/normalize)
               (lambda (_section raw _f) raw))
              ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
               (lambda (_org _bundle &optional source-note-id &rest _)
                 (setq captured-id source-note-id)
                 (list :copied nil :removed nil :warnings nil :errors nil)))
              ((symbol-function 'a3madkour-pub-research--write-if-different)
               (lambda (_p _c) nil))
              ((symbol-function 'a3madkour-pub-research--render-frontmatter)
               (lambda (_n) ""))
              ((symbol-function 'a3madkour-pub-history/record-publish)
               (lambda (_id _url _state) nil)))
      (a3madkour-pub-research/publish-research-file "/tmp/stub.org")
      (should (equal captured-id "research-id-55")))))
```

- [ ] **Step 2: Run test, verify it fails**

```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "research-test/publisher-threads-id" | head -5
```

Expected: failure.

- [ ] **Step 3: Update the call site**

In `a3madkour-publish-research.el` line 340, change:
```elisp
    (a3madkour-pub/asset-validate-and-copy file bundle-dir)
```
to:
```elisp
    (a3madkour-pub/asset-validate-and-copy file bundle-dir id)
```

`id` is already bound at line 295.

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: `Ran 541 tests, 541 results as expected`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-research.el emacs-configs/custom/lisp/a3madkour-publish-research-test.el && git commit -m "$(cat <<'EOF'
fix(d2-figref): research publisher threads :id to asset-validate-and-copy

Bug 2 part c (research). Mirror of essays + garden.

1 new ert test. Suite 540 -> 541 green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Fixture — `example-multi.org` `:ID:` drawer + SVG move

**Files (outside dotfiles repo):**
- Modify: `~/org/essays/example-multi.org` (add `:PROPERTIES:` drawer at top)
- Move: `~/org/essays/diagram-1.svg` → `~/org/essays/assets/<UUID>/diagram-1.svg`

This task is a manual file-level operation since it touches the user's org notes, not the dotfiles repo. No tests; verified by Task 9 manual run.

- [ ] **Step 1: Generate a UUID**

```bash
uuidgen | tr 'A-Z' 'a-z'
```

Capture the output (e.g. `7f3a8c11-2d4e-4b6a-9f5c-1e2d3c4b5a6d`). Use this UUID consistently in the next steps.

- [ ] **Step 2: Add `:ID:` drawer to `example-multi.org`**

In `~/org/essays/example-multi.org`, the file currently starts with:
```org
#+title: Example essay — multi-target export
```

Insert these three lines BEFORE `#+title:`:
```org
:PROPERTIES:
:ID:       <PASTE-UUID-HERE>
:END:
```

The drawer must be the very first content in the buffer (org-element parser convention for file-level properties).

- [ ] **Step 3: Move the SVG into per-essay assets dir**

```bash
mkdir -p ~/org/essays/assets/<UUID>
mv ~/org/essays/diagram-1.svg ~/org/essays/assets/<UUID>/diagram-1.svg
```

Substitute the same UUID from Step 1.

Verify:
```bash
ls -la ~/org/essays/diagram-1.svg 2>&1   # should report "No such file"
ls -la ~/org/essays/assets/<UUID>/diagram-1.svg   # should exist
```

- [ ] **Step 4: Re-sync org-roam DB**

In Emacs:
```
M-x org-roam-db-sync RET
```

This picks up the new `:ID:` so `id-to-file` resolves correctly during publish.

- [ ] **Step 5: No commit**

The org notes live in `~/org/`, which is not the dotfiles git repo. If the user tracks `~/org/` separately, commit there per their convention. Otherwise, this step is a working-tree change to the user's notes — no version control action from this plan.

---

## Task 8: End-to-end `figure-ref-round-trip` ert test

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-essays-test.el` (append 1 test)

- [ ] **Step 1: Write the failing test**

Append to `a3madkour-publish-essays-test.el`:

```elisp
;;; End-to-end: [[file:asset.svg]] round-trip through publish-essay-file.

(ert-deftest a3madkour-pub-essays-test/figure-ref-round-trip ()
  "Real publish: [[file:fig.svg]] lands as <img> in index.md; svg copied to bundle."
  (let* ((tmp (file-name-as-directory
                (make-temp-file "a3-figure-roundtrip-" t)))
         (essays-dir (file-name-as-directory (expand-file-name "essays/" tmp)))
         (id "deadbeef-1234-5678-9abc-def012345678")
         (slug "test-figure-essay")
         (org-file (expand-file-name (concat slug ".org") essays-dir))
         (asset-dir (file-name-as-directory
                      (expand-file-name (format "assets/%s/" id) essays-dir)))
         (asset (expand-file-name "fig.svg" asset-dir))
         (site-root (file-name-as-directory (expand-file-name "site/" tmp)))
         (bundle-dir (file-name-as-directory
                       (expand-file-name (format "content/essays/%s/" slug)
                                          site-root))))
    (unwind-protect
        (progn
          (make-directory asset-dir t)
          (make-directory bundle-dir t)
          (with-temp-file asset (insert "<svg/>"))
          (with-temp-file org-file
            (insert (format ":PROPERTIES:
:ID:       %s
:END:
#+title: Test figure essay
#+date: 2026-06-05
#+hugo_publish: t
#+hugo_section: essays
#+hugo_slug: %s

Body text.

[[file:fig.svg]]
"
                            id slug)))
          (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                     (lambda (i) (if (equal i id) org-file nil)))
                    ((symbol-function 'a3madkour-pub-essays--site-root)
                     (lambda () site-root))
                    ((symbol-function 'a3madkour-pub-history/record-publish)
                     (lambda (_id _url _state) nil))
                    ((symbol-function 'a3madkour-pub-frontmatter/normalize)
                     (lambda (_section raw _f) raw))
                    ((symbol-function 'a3madkour-pub-essays--render-frontmatter)
                     (lambda (_n) "")))
            (let ((a3madkour-pub/essays-dir essays-dir))
              (a3madkour-pub-essays/publish-essay-file org-file)))
          (let* ((index-path (expand-file-name "index.md" bundle-dir))
                 (svg-path (expand-file-name "fig.svg" bundle-dir))
                 (index-body
                  (when (file-exists-p index-path)
                    (with-temp-buffer
                      (insert-file-contents index-path)
                      (buffer-string)))))
            (should (file-exists-p index-path))
            (should (file-exists-p svg-path))
            (should (string-match-p "<img " index-body))
            (should (string-match-p "fig.svg" index-body))))
      (delete-directory tmp t))))
```

- [ ] **Step 2: Run test, observe result**

```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | grep "figure-ref-round-trip" | head -5
```

Expected: PASS. Tasks 1–6 already implement all the moving parts; this test is the regression backstop, not a driver for new code.

If it fails, dig in: likely missing stub (e.g. ox-hugo export may need to actually run, or `a3madkour-pub-export/export-file` may need stubbing because the test environment lacks ox-hugo's full setup). Add stubs as needed until the assertions are reached.

- [ ] **Step 3: If the export step is too heavy to run in batch, stub it**

If `a3madkour-pub-export/export-file` errors out (ox-hugo dependency, etc.), stub it to return a body that contains the rewritten `@@html:<img …>@@` snippet (which the rewriter will have inserted into the tmp buffer):

```elisp
((symbol-function 'a3madkour-pub-export/export-file)
 (lambda (tmp-src)
   (let ((body (with-temp-buffer
                 (insert-file-contents tmp-src)
                 (buffer-string))))
     ;; Convert @@html:...@@ to raw — ox-hugo's actual behavior.
     (list :body
           (replace-regexp-in-string
            "@@html:\\(.*?\\)@@" "\\1" body)
           :frontmatter nil))))
```

Add this to the cl-letf bindings and re-run.

- [ ] **Step 4: Run tests, verify suite is green**

```bash
cd ~/dotfiles/emacs-configs/custom/lisp && ./run-tests.sh 2>&1 | tail -5
```

Expected: `Ran 542 tests, 542 results as expected` (541 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add emacs-configs/custom/lisp/a3madkour-publish-essays-test.el && git commit -m "$(cat <<'EOF'
test(d2-figref): end-to-end figure-ref round-trip regression test

Builds a temp essay with [[file:fig.svg]], runs publish-essay-file,
asserts bundle-dir/index.md contains <img> + fig.svg copied. Catches
either Bug 1 or Bug 2 regressing simultaneously.

1 new ert test. Suite 541 -> 542 green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Manual D.2 verification

**This is a human-in-the-loop task.** No code, no commit until all 5 checks pass.

- [ ] **Step 1: Verify org-roam DB is fresh**

In Emacs:
```
M-x org-roam-db-sync RET
```

- [ ] **Step 2: Run the publish**

In Emacs:
```
M-x a3-publish-deliberate RET ~/org/essays/example-multi.org RET
```

- [ ] **Step 3: Check `*Messages*` buffer**

`M-x switch-to-buffer RET *Messages* RET` and scan the bottom 50 lines.

Expected: NO occurrences of:
- `lacks :ID:`
- `cannot read file:`
- `from-validate`

If any appear, investigate which task regressed.

- [ ] **Step 4: Inspect the bundle**

```bash
ls -la ~/Sync/Workspace/a3madkour.github.io/content/essays/example-multi/
```

Expected files (with fresh mtime):
- `index.md`
- `diagram-1.svg`
- `example-multi.pdf`
- `example-multi.docx`

Then:
```bash
grep -c "<img" ~/Sync/Workspace/a3madkour.github.io/content/essays/example-multi/index.md
```

Expected: `1` (one `<img>` tag for diagram-1.svg).

- [ ] **Step 5: Open the PDF and DOCX, confirm figure embedded**

```bash
open ~/Sync/Workspace/a3madkour.github.io/content/essays/example-multi/example-multi.pdf
open ~/Sync/Workspace/a3madkour.github.io/content/essays/example-multi/example-multi.docx
```

Visual confirmation: the SVG (a small diagram) appears in both files.

- [ ] **Step 6: Run site Hugo build to confirm bundle resolution**

```bash
cd ~/Sync/Workspace/a3madkour.github.io && hugo server --buildDrafts
```

In a browser: `http://localhost:1313/essays/example-multi/`. The figure should render.

`C-c` to stop the dev server when done.

- [ ] **Step 7: No commit — manual verification is the success criterion itself**

If all 6 steps above pass, the implementation is complete. Update memory:

```bash
cd ~/Sync/Workspace/a3madkour.github.io
```

Edit `.claude/memory/project_d2_complete.md` to mark figure-ref follow-up #1 closed, citing the dotfiles commits from Tasks 1–8.

(This memory update isn't a hard requirement of the plan, but it closes the loop with the queued-work tracker referenced in the spec's success criteria.)

---

## Plan summary

| Task | What | Commit | Test count |
|---|---|---|---|
| 1 | `--strip-file-prefix-if-asset` helper | `feat(d2-figref): --strip-file-prefix-if-asset helper` | 525 → 530 |
| 2 | `rewrite-link` wires the helper | `fix(d2-figref): rewrite-link routes [[file:asset.ext]] to asset path` | 530 → 532 |
| 3 | `asset-validate-and-copy` signature | `fix(d2-figref): asset-validate-and-copy accepts source-note-id` | 532 → 533 |
| 4 | `rewrite-asset-link` nil-tolerance | `fix(d2-figref): rewrite-asset-link tolerates nil source-note-id` | 533 → 535 |
| 5 | `--asset-resolve-path` essays-aware | `feat(d2-figref): asset-resolve-path essays-aware branch` | 535 → 538 |
| 6a | Essays publisher threads id | `fix(d2-figref): essays publisher threads :id …` | 538 → 539 |
| 6b | Garden publisher threads id | `fix(d2-figref): garden publisher threads :id …` | 539 → 540 |
| 6c | Research publisher threads id | `fix(d2-figref): research publisher threads :id …` | 540 → 541 |
| 7 | `example-multi.org` `:ID:` + SVG move | (no dotfiles commit; user's `~/org/`) | unchanged |
| 8 | End-to-end ert test | `test(d2-figref): end-to-end figure-ref round-trip regression test` | 541 → 542 |
| 9 | Manual D.2 verification (5-step) | (no commit; memory update optional) | unchanged |

Final test count: **542 green** (525 baseline + 17 new tests across 8 commits). The spec's target of "525 → ~539" undercounted by 3; this plan delivers the full 17.
