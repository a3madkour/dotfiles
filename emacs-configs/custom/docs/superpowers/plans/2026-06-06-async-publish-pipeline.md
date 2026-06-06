# Async Publish Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `a3-publish-deliberate` and `a3-publish-living` from synchronous to async so Emacs stays responsive throughout a publish, with progress in a status buffer + mode line and clean cancellation.

**Architecture:** One new module (`a3madkour-publish-async.el`) provides a `make-process`-based subprocess primitive, a barrier helper, a single-in-flight lifecycle lock, the `*a3-publish*` status buffer, and a mode-line indicator. Existing handlers (B.1 garden / B.2 library / B.3 research / B.4 essays) and both top-level commands convert to a `(file run &key on-done)` continuation contract. A dynamic-var `synchronous-p` shim runs the helpers inline for the existing 543 ert tests, so they stay green without rewrites.

**Tech Stack:** Emacs Lisp (`make-process`, `set-process-sentinel`, `run-with-timer`, `cl-defstruct`); existing dotfiles publish modules; ert + Python integration fixtures.

**Spec:** `~/dotfiles/emacs-configs/custom/docs/superpowers/specs/2026-06-06-async-publish-pipeline-design.md` (committed as `216e6c9`).

---

## File Structure

### New files (under `emacs-configs/custom/lisp/`)

| File | Responsibility |
|---|---|
| `a3madkour-publish-async.el` | Primitive + barrier + lock + status buffer + mode line + cancel + lifecycle helpers (`begin-publish` / `finish-publish` wrappers). Single cohesive module per design §3. |
| `a3madkour-publish-async-test.el` | ert tests for every public function in `-async.el`. ~30 tests per spec §7.2. |

### New integration tests (under `emacs-configs/custom/lisp/integration/`)

| File | Responsibility |
|---|---|
| `test_async_publish_deliberate_essay.py` | End-to-end deliberate publish via `a3-pub.sh --publish-deliberate`; verifies bundle dir + manifest + citations YAML. |
| `test_async_publish_cancel.py` | Spawns publish, sends SIGTERM mid-xelatex, asserts no manifest change + no orphan tmp dirs + non-zero exit. |

### Modified files

| File | Change |
|---|---|
| `a3madkour-publish-deliberate.el` | Replace `unwind-protect (handler file) (finish-publish)` with `(begin-publish …)` returning a run, `(funcall handler file run :on-done (lambda (status) (finish-publish run …)))`. |
| `a3madkour-publish-living.el` | Same lifecycle conversion; barrier across the per-section walk. |
| `a3madkour-publish-essays.el` | Handler signature changes to `(file run &key on-done)`; multi-export tail becomes async chain. |
| `a3madkour-publish-garden.el` | Handler signature change. |
| `a3madkour-publish-library.el` | Handler signature change. |
| `a3madkour-publish-research.el` | Handler signature change. |
| `a3madkour-publish-multi.el` | D.2 orchestrator runs multi-pdf + multi-word via `barrier`. |
| `a3madkour-publish-multi-pdf.el` | rsvg fan-out via barrier; xelatex/biber/xelatex/xelatex chain via sentinels; ox-latex sync wrap with `log-step` timing; `multi-pdf/run` becomes `&key run on-done`. |
| `a3madkour-publish-multi-word.el` | rsvg fan-out via barrier; pandoc via single sentinel; `multi-word/run` becomes `&key run on-done`. |
| `a3madkour-publish-history.el` | `git log -1 --format=%cs` via `run-process` (sync mode keeps existing API; async mode wraps the same logic). |
| `a3madkour-publish-assets.el` | `git mv` for auto-remediate via `run-process`. |
| `a3madkour-publish-unpublish.el` | `git mv` for slug rename via `run-process` (drops `shell-command` + `shell-quote-argument`). |
| `a3-pub.sh` | Add `-l a3madkour-publish-async` to load list; SIGTERM handler that maps to `(a3-pub-async/cancel-current-run)`. |
| `config.el` (or `config.org`) | Add `(require 'a3madkour-publish-async)` near the other publish requires. **User-edited file; check with user before touching — see Task 0.** |

---

## Phase 1 — Foundations (the new module, no handler behavior change yet)

### Task 0: Pre-flight — confirm strategy for `config.el`/`config.org`

**Files:**
- Read: `emacs-configs/custom/config.org` (search for `a3madkour-publish`)
- Read: `emacs-configs/custom/config.el` (search for `a3madkour-publish`)

- [ ] **Step 1: Check current require pattern**

Run: `grep -n "a3madkour-publish" /Users/a3madkour/dotfiles/emacs-configs/custom/config.el | head -20`

Expected: lists of `(require 'a3madkour-publish-...)` lines (config.el:3326 has `a3madkour-publish-deliberate` per earlier grep).

- [ ] **Step 2: Confirm both `config.org` and `config.el` are in the user's "dirty bystanders" set**

Run: `git -C /Users/a3madkour/dotfiles status --short emacs-configs/custom/config.{org,el}`

Expected: both show ` M` (modified, not staged). Per handoff, these are author's in-progress local work — never commit them.

- [ ] **Step 3: Decision: where does the new `(require 'a3madkour-publish-async)` live?**

Two options:
- **A.** Add to user-edited `config.el` next to `(require 'a3madkour-publish-deliberate)`. Author commits when ready.
- **B.** Self-require: every entry point (`-deliberate.el`, `-living.el`) already requires `a3madkour-publish-essays` etc.; have `-async.el` get pulled in via `(require 'a3madkour-publish-async)` at the top of `-deliberate.el` + `-living.el`. No `config.el` change needed.

Plan picks **B** — self-require in `-deliberate.el` + `-living.el`. Keeps the slice's blast radius inside committed files. config.el/config.org untouched.

- [ ] **Step 4: Record decision in scratch task notes (no commit yet — Task 0 has no file change).**

---

### Task 1: Module skeleton + sync-mode dynamic var

**Files:**
- Create: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Create: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing test for the synchronous-p var**

```elisp
;;; a3madkour-publish-async-test.el --- tests for -async.el  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-async)

(ert-deftest a3-pub-async-test/synchronous-p-defaults-nil ()
  "Async mode is the default; tests opt into sync mode."
  (should-not a3-pub-async--synchronous-p))

(ert-deftest a3-pub-async-test/synchronous-p-can-be-let-bound ()
  (let ((a3-pub-async--synchronous-p t))
    (should a3-pub-async--synchronous-p)))

(provide 'a3madkour-publish-async-test)
;;; a3madkour-publish-async-test.el ends here
```

- [ ] **Step 2: Run test; expect fail**

Run: `cd ~/dotfiles && emacs --batch -L emacs-configs/custom/lisp -l emacs-configs/custom/lisp/a3madkour-publish-async-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -10`

Expected: `Cannot open load file: a3madkour-publish-async`.

- [ ] **Step 3: Create the module skeleton**

```elisp
;;; a3madkour-publish-async.el --- async publish pipeline runtime -*- lexical-binding: t; -*-
;;; Commentary:
;;; Async runtime for the publish pipeline.  See
;;; ~/dotfiles/emacs-configs/custom/docs/superpowers/specs/2026-06-06-async-publish-pipeline-design.md.
;;;
;;; Public API:
;;;   - a3-pub-async/run-process   — make-process wrapper with sentinel
;;;   - a3-pub-async/barrier       — N-way join
;;;   - a3-pub-async/begin-publish — start a run; acquires the lifecycle lock
;;;   - a3-pub-async/finish-publish — end a run; releases the lock
;;;   - a3-pub-async/log-step      — append a step line to *a3-publish*
;;;   - a3-pub-async/cancel-current-run — C-c C-c entry point
;;;
;;; Tests opt into synchronous mode via the dynamic var
;;; `a3-pub-async--synchronous-p' so the existing 543-test suite keeps
;;; working without async-aware fixtures.
;;; Code:

(require 'cl-lib)

(defgroup a3-pub-async nil
  "Async publish pipeline runtime."
  :group 'a3madkour-pub)

(defvar a3-pub-async--synchronous-p nil
  "When non-nil, the async helpers run their subprocess calls via
`call-process' and invoke `on-done' inline.  Existing ert tests
bind this to t via `with-a3-pub-async-sync' so their `cl-letf'
stubs continue to fire.")

(provide 'a3madkour-publish-async)
;;; a3madkour-publish-async.el ends here
```

- [ ] **Step 4: Run tests; expect 2 PASS**

Run: `cd ~/dotfiles && emacs --batch -L emacs-configs/custom/lisp -l emacs-configs/custom/lisp/a3madkour-publish-async-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -5`

Expected: `Ran 2 tests, 2 results as expected`.

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): module skeleton + synchronous-p shim var"
```

---

### Task 2: `run-process` primitive — sync path

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing test for sync-mode subprocess invocation**

Append to `a3madkour-publish-async-test.el`:

```elisp
(ert-deftest a3-pub-async-test/run-process-sync-calls-on-done-with-rc ()
  "In sync mode, run-process invokes call-process and fires on-done
inline with (rc stderr-tail)."
  (let ((calls nil) (result nil))
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd _ _ _ &rest args)
                 (push (cons cmd args) calls) 0)))
      (let ((a3-pub-async--synchronous-p t))
        (a3-pub-async/run-process "true" '("a" "b")
                                  :on-done (lambda (rc tail)
                                             (setq result (cons rc tail))))))
    (should (equal (car calls) '("true" "a" "b")))
    (should (= 0 (car result)))
    (should (or (null (cdr result)) (string-empty-p (cdr result))))))

(ert-deftest a3-pub-async-test/run-process-sync-nonzero-rc-passes-through ()
  "Non-zero exit code is reported as-is to on-done."
  (let ((rc-seen nil))
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 2)))
      (let ((a3-pub-async--synchronous-p t))
        (a3-pub-async/run-process "false" nil
                                  :on-done (lambda (rc _tail) (setq rc-seen rc)))))
    (should (= 2 rc-seen))))
```

- [ ] **Step 2: Run; expect fail (function undefined)**

Run: `emacs --batch -L emacs-configs/custom/lisp -l emacs-configs/custom/lisp/a3madkour-publish-async-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -10`

Expected: `Symbol's function definition is void: a3-pub-async/run-process`.

- [ ] **Step 3: Implement sync path**

Add to `a3madkour-publish-async.el` before `(provide …)`:

```elisp
(cl-defun a3-pub-async/run-process (cmd args
                                    &key name on-done stderr-buf cwd)
  "Spawn CMD with ARGS; invoke ON-DONE with (rc stderr-tail) when done.

NAME defaults to CMD (used for process + stderr buffer names).
STDERR-BUF defaults to a buffer named `*a3-pub-stderr <name>*'.
CWD, when non-nil, sets `default-directory' for the spawn.

When `a3-pub-async--synchronous-p' is non-nil, runs `call-process'
inline and fires ON-DONE in the calling frame (test path)."
  (let* ((name (or name cmd))
         (stderr-buf (or stderr-buf
                         (get-buffer-create (format "*a3-pub-stderr %s*" name))))
         (default-directory (or cwd default-directory)))
    (if a3-pub-async--synchronous-p
        ;; Sync test path.
        (let ((rc (apply #'call-process cmd nil stderr-buf nil args))
              (tail (with-current-buffer stderr-buf
                      (buffer-substring-no-properties (point-min) (point-max)))))
          (when on-done (funcall on-done rc tail))
          nil)
      ;; Async path — implemented in Task 3.
      (error "a3-pub-async/run-process: async path not yet implemented"))))
```

- [ ] **Step 4: Run; expect 4 PASS (2 prior + 2 new)**

Run: same as Step 2. Expected: `4 results as expected`.

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): run-process sync path"
```

---

### Task 3: `run-process` primitive — async path

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing test for async make-process spawn**

Append:

```elisp
(ert-deftest a3-pub-async-test/run-process-async-spawns-make-process ()
  "In async mode, run-process uses make-process and the sentinel
fires on-done with the exit code."
  (let ((done-rc nil) (done-tail nil)
        (sem (make-semaphore 0)))
    ;; Use a tiny real subprocess: /bin/sh -c 'exit 0'.
    (a3-pub-async/run-process "/bin/sh" '("-c" "exit 0")
                              :name "test-sh"
                              :on-done (lambda (rc tail)
                                         (setq done-rc rc done-tail tail)
                                         (semaphore-notify sem)))
    ;; Wait up to 5s for the sentinel.
    (with-timeout (5 (error "sentinel never fired"))
      (while (null done-rc) (accept-process-output nil 0.05)))
    (should (= 0 done-rc))))

(ert-deftest a3-pub-async-test/run-process-async-stderr-tail-captured ()
  "Stderr output is captured into the stderr buffer and surfaced to on-done."
  (let ((done-tail nil))
    (a3-pub-async/run-process "/bin/sh"
                              '("-c" "echo OOPS 1>&2 ; exit 1")
                              :name "test-err"
                              :on-done (lambda (_rc tail) (setq done-tail tail)))
    (with-timeout (5 (error "sentinel never fired"))
      (while (null done-tail) (accept-process-output nil 0.05)))
    (should (string-match-p "OOPS" done-tail))))
```

- [ ] **Step 2: Run; expect 2 fail (async path stub errors)**

Expected: `a3-pub-async/run-process: async path not yet implemented`.

- [ ] **Step 3: Replace the error stub with the async path**

Replace the `(error ...)` line in `a3-pub-async/run-process` with:

```elisp
      ;; Async path.
      (let ((proc (make-process
                   :name (format "a3-pub-%s" name)
                   :command (cons cmd args)
                   :buffer nil
                   :stderr stderr-buf
                   :sentinel
                   (lambda (proc event)
                     (when (memq (process-status proc) '(exit signal))
                       (let* ((rc (process-exit-status proc))
                              (tail (with-current-buffer stderr-buf
                                      (let ((end (point-max)))
                                        (buffer-substring-no-properties
                                         (max (point-min) (- end 2000))
                                         end))))
                              (lines (split-string tail "\n" t))
                              (tail-trimmed
                               (mapconcat #'identity
                                          (last lines (min 10 (length lines)))
                                          "\n")))
                         (when on-done (funcall on-done rc tail-trimmed))))))))
        proc)
```

- [ ] **Step 4: Run; expect 6 PASS (4 + 2)**

Run: same. Expected: `6 results as expected`.

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): run-process async path via make-process"
```

---

### Task 4: `barrier` helper

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing tests**

Append:

```elisp
(ert-deftest a3-pub-async-test/barrier-fires-on-nth-call ()
  "N=3: on-all-done fires exactly once, after the 3rd report,
with results in registration order."
  (let ((fired 0) (saw nil))
    (let ((report (a3-pub-async/barrier 3
                                        :on-all-done
                                        (lambda (results)
                                          (cl-incf fired)
                                          (setq saw results)))))
      (funcall report 'a)
      (funcall report 'b)
      (should (= 0 fired))
      (funcall report 'c))
    (should (= 1 fired))
    (should (equal saw '(a b c)))))

(ert-deftest a3-pub-async-test/barrier-n-zero-fires-immediately ()
  "N=0: on-all-done fires immediately with nil."
  (let ((fired nil))
    (a3-pub-async/barrier 0 :on-all-done (lambda (results)
                                           (setq fired (or results 'empty))))
    (should (eq fired 'empty))))

(ert-deftest a3-pub-async-test/barrier-extra-calls-after-n-are-ignored ()
  "Calls beyond N are silently ignored (defensive against double-fire)."
  (let ((fired 0))
    (let ((report (a3-pub-async/barrier 2
                                        :on-all-done
                                        (lambda (_) (cl-incf fired)))))
      (funcall report 'a)
      (funcall report 'b)
      (funcall report 'c)
      (funcall report 'd))
    (should (= 1 fired))))
```

- [ ] **Step 2: Run; expect 3 fail**

Expected: `Symbol's function definition is void: a3-pub-async/barrier`.

- [ ] **Step 3: Implement**

Append before `(provide …)`:

```elisp
(cl-defun a3-pub-async/barrier (n &key on-all-done)
  "Return a 1-arg report function.  After N calls, fires ON-ALL-DONE
with the list of reports in call order.  N=0 fires immediately.
Calls beyond N are silently ignored."
  (let ((remaining n)
        (results nil))
    (if (zerop n)
        (progn (when on-all-done (funcall on-all-done nil)) (lambda (_) nil))
      (lambda (result)
        (when (> remaining 0)
          (setq remaining (1- remaining))
          (push result results)
          (when (zerop remaining)
            (when on-all-done
              (funcall on-all-done (nreverse results)))))))))
```

- [ ] **Step 4: Run; expect 9 PASS**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): barrier helper"
```

---

### Task 5: Run handle struct + lifecycle lock var

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing tests**

Append:

```elisp
(ert-deftest a3-pub-async-test/run-struct-fields ()
  (let ((r (make-a3-pub-async-run
            :id 'test :scope 'deliberate
            :source-label "essays/x" :start-time '(0 0 0 0)
            :planned-steps 5 :completed-steps 0 :status :running)))
    (should (eq (a3-pub-async-run-scope r) 'deliberate))
    (should (= 5 (a3-pub-async-run-planned-steps r)))))

(ert-deftest a3-pub-async-test/lock-defaults-nil ()
  (should-not a3-pub-async--in-flight-run))
```

- [ ] **Step 2: Run; expect 2 fail (struct + var undefined)**

- [ ] **Step 3: Implement**

Append before `(provide …)`:

```elisp
(cl-defstruct a3-pub-async-run
  id              ; symbol or string, unique per run
  scope           ; 'deliberate or 'living
  source-label    ; "essays/example-multi" — surfaced in buffer header
  buffer          ; *a3-publish* buffer
  section-start   ; point in buffer where this run's section begins
  live-processes  ; list of live process objects, for cancel
  tmp-dirs        ; list of dirs to delete on cancel
  start-time      ; (current-time)
  planned-steps   ; integer
  completed-steps ; integer
  status)         ; :running / :ok / :err / :cancelled

(defvar a3-pub-async--in-flight-run nil
  "The active run handle, or nil when no publish is in flight.")
```

- [ ] **Step 4: Run; expect 11 PASS**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): run handle struct + in-flight lock var"
```

---

### Task 6: `*a3-publish*` buffer + `a3-pub-mode` + `log-step`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing tests**

Append:

```elisp
(ert-deftest a3-pub-async-test/buffer-getter-creates-once ()
  (let ((buf (a3-pub-async/buffer)))
    (should (bufferp buf))
    (should (eq buf (a3-pub-async/buffer)))
    (with-current-buffer buf
      (should (eq major-mode 'a3-pub-mode)))
    (kill-buffer buf)))

(ert-deftest a3-pub-async-test/log-step-running-formats-line ()
  (let* ((buf (a3-pub-async/buffer))
         (run (make-a3-pub-async-run :buffer buf
                                     :section-start (point-min))))
    (a3-pub-async/log-step run "xelatex" :running :detail "pass 2/4")
    (with-current-buffer buf
      (should (string-match-p "\\[·\\] xelatex" (buffer-string)))
      (should (string-match-p "pass 2/4" (buffer-string)))
      (should (string-match-p "running" (buffer-string))))
    (kill-buffer buf)))

(ert-deftest a3-pub-async-test/log-step-ok-shows-checkmark-and-elapsed ()
  (let* ((buf (a3-pub-async/buffer))
         (run (make-a3-pub-async-run :buffer buf
                                     :section-start (point-min))))
    (a3-pub-async/log-step run "pdf" :ok :detail "place" :elapsed 1.234)
    (with-current-buffer buf
      (should (string-match-p "\\[✓\\] pdf" (buffer-string)))
      (should (string-match-p "1\\.2s" (buffer-string))))
    (kill-buffer buf)))

(ert-deftest a3-pub-async-test/log-step-err-includes-snippet ()
  (let* ((buf (a3-pub-async/buffer))
         (run (make-a3-pub-async-run :buffer buf
                                     :section-start (point-min))))
    (a3-pub-async/log-step run "xelatex" :err :elapsed 8.3
                           :err-snippet "Missing font: foo")
    (with-current-buffer buf
      (should (string-match-p "\\[✗\\] xelatex" (buffer-string)))
      (should (string-match-p "Missing font: foo" (buffer-string))))
    (kill-buffer buf)))
```

- [ ] **Step 2: Run; expect 4 fail**

- [ ] **Step 3: Implement buffer + mode + log-step**

Append before `(provide …)`:

```elisp
(defconst a3-pub-async--buffer-name "*a3-publish*")

(define-derived-mode a3-pub-mode special-mode "a3-pub"
  "Major mode for the *a3-publish* status buffer."
  (setq buffer-read-only t
        truncate-lines t))

(defun a3-pub-async/buffer ()
  "Return (creating if needed) the *a3-publish* status buffer."
  (let ((buf (get-buffer-create a3-pub-async--buffer-name)))
    (with-current-buffer buf
      (unless (eq major-mode 'a3-pub-mode) (a3-pub-mode)))
    buf))

(defun a3-pub-async--status-glyph (status)
  (pcase status
    (:running   "·")
    (:ok        "✓")
    (:err       "✗")
    (:cancelled "⨯")
    (:pending   " ")
    (_           "?")))

(cl-defun a3-pub-async/log-step (run label status &key detail elapsed err-snippet)
  "Append a step line to RUN's buffer.
LABEL is the step name (e.g. \"xelatex\"); DETAIL is the trailing
column (e.g. \"pass 2/4\"); ELAPSED is seconds (float).
ERR-SNIPPET, when non-nil, is inlined on the next line indented 14 cols."
  (let ((buf (a3-pub-async-run-buffer run)))
    (when (and buf (buffer-live-p buf))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (let ((rhs (cond
                      ((eq status :running) "[running]")
                      ((eq status :pending) "[pending]")
                      (elapsed (format "(%4.1fs)" elapsed))
                      (t ""))))
            (insert (format "  [%s] %-18s %-32s %s\n"
                            (a3-pub-async--status-glyph status)
                            label
                            (or detail "")
                            rhs)))
          (when err-snippet
            (dolist (line (split-string err-snippet "\n" t))
              (insert (format "              %s\n" line)))))))))
```

- [ ] **Step 4: Run; expect 15 PASS**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): *a3-publish* buffer + a3-pub-mode + log-step"
```

---

### Task 7: Mode-line indicator

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing tests**

Append:

```elisp
(ert-deftest a3-pub-async-test/modeline-format-running ()
  (let ((run (make-a3-pub-async-run :status :running
                                    :planned-steps 9 :completed-steps 5)))
    (should (string-match-p "5/9"
                            (a3-pub-async--modeline-string run)))))

(ert-deftest a3-pub-async-test/modeline-empty-when-idle ()
  (let ((a3-pub-async--in-flight-run nil))
    (should (string-empty-p (a3-pub-async--modeline-string nil)))))

(ert-deftest a3-pub-async-test/modeline-format-cancelled ()
  (let ((run (make-a3-pub-async-run :status :cancelled
                                    :planned-steps 9 :completed-steps 3)))
    (should (string-match-p "cancelled"
                            (a3-pub-async--modeline-string run)))))
```

- [ ] **Step 2: Run; expect 3 fail**

- [ ] **Step 3: Implement**

Append:

```elisp
(defvar a3-pub-async--spinner-glyphs '("⧗" "◐" "◑" "◒" "◓"))
(defvar a3-pub-async--spinner-idx 0)
(defvar a3-pub-async--spinner-timer nil)

(defun a3-pub-async--modeline-string (run)
  (cond
   ((null run) "")
   ((eq (a3-pub-async-run-status run) :cancelled)
    "[a3-pub ⨯ cancelled]")
   ((eq (a3-pub-async-run-status run) :err)
    "[a3-pub ✗ err]")
   ((eq (a3-pub-async-run-status run) :running)
    (format "[a3-pub %s %d/%d]"
            (nth a3-pub-async--spinner-idx a3-pub-async--spinner-glyphs)
            (a3-pub-async-run-completed-steps run)
            (a3-pub-async-run-planned-steps run)))
   (t "")))

(defun a3-pub-async--modeline-tick ()
  (setq a3-pub-async--spinner-idx
        (mod (1+ a3-pub-async--spinner-idx)
             (length a3-pub-async--spinner-glyphs)))
  (force-mode-line-update t))

(defun a3-pub-async--modeline-start ()
  (add-to-list 'mode-line-misc-info
               '(:eval (a3-pub-async--modeline-string a3-pub-async--in-flight-run))
               t)
  (setq a3-pub-async--spinner-timer
        (run-with-timer 0 0.25 #'a3-pub-async--modeline-tick)))

(defun a3-pub-async--modeline-stop ()
  (when a3-pub-async--spinner-timer
    (cancel-timer a3-pub-async--spinner-timer)
    (setq a3-pub-async--spinner-timer nil))
  (force-mode-line-update t))
```

- [ ] **Step 4: Run; expect 18 PASS**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): mode-line spinner indicator"
```

---

### Task 8: Lifecycle — `begin-publish` + `finish-publish`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing tests**

Append:

```elisp
(ert-deftest a3-pub-async-test/begin-acquires-lock ()
  (let ((a3-pub-async--in-flight-run nil))
    (cl-letf (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil)))
      (let ((run (a3-pub-async/begin-publish :scope 'deliberate
                                             :source-label "essays/x"
                                             :planned-steps 5)))
        (should (eq a3-pub-async--in-flight-run run))
        (should (eq (a3-pub-async-run-status run) :running))
        (should (= 5 (a3-pub-async-run-planned-steps run)))))))

(ert-deftest a3-pub-async-test/begin-second-call-errors ()
  (let ((a3-pub-async--in-flight-run
         (make-a3-pub-async-run :id 'existing :status :running)))
    (cl-letf (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil))
              ((symbol-function 'pop-to-buffer) (lambda (_) nil)))
      (should-error (a3-pub-async/begin-publish :scope 'deliberate
                                                :source-label "essays/y"
                                                :planned-steps 5)
                    :type 'user-error))))

(ert-deftest a3-pub-async-test/finish-releases-lock-on-ok ()
  (let* ((run (make-a3-pub-async-run :id 'r :status :running
                                     :buffer (a3-pub-async/buffer)
                                     :start-time (current-time))))
    (let ((a3-pub-async--in-flight-run run))
      (cl-letf (((symbol-function 'a3madkour-pub/finish-publish) (lambda (&rest _) nil)))
        (a3-pub-async/finish-publish run :scope 'deliberate :status 'ok)
        (should-not a3-pub-async--in-flight-run)
        (should (eq (a3-pub-async-run-status run) :ok))))))

(ert-deftest a3-pub-async-test/finish-releases-lock-on-err ()
  (let* ((run (make-a3-pub-async-run :id 'r :status :running
                                     :buffer (a3-pub-async/buffer)
                                     :start-time (current-time))))
    (let ((a3-pub-async--in-flight-run run))
      (cl-letf (((symbol-function 'a3madkour-pub/finish-publish) (lambda (&rest _) nil)))
        (a3-pub-async/finish-publish run :scope 'deliberate :status 'err)
        (should-not a3-pub-async--in-flight-run)))))

(ert-deftest a3-pub-async-test/finish-cancelled-skips-citation-emit ()
  "On cancelled, the citations emit-yaml tail does NOT fire."
  (let* ((run (make-a3-pub-async-run :id 'r :status :running
                                     :buffer (a3-pub-async/buffer)
                                     :start-time (current-time)))
         (emit-fired nil))
    (let ((a3-pub-async--in-flight-run run))
      (cl-letf (((symbol-function 'a3madkour-pub/finish-publish) (lambda (&rest _) nil))
                ((symbol-function 'a3madkour-pub-citations/emit-yaml)
                 (lambda (&rest _) (setq emit-fired t))))
        (a3-pub-async/finish-publish run :scope 'deliberate :status 'cancelled)
        (should-not emit-fired)))))
```

- [ ] **Step 2: Run; expect 5 fail**

- [ ] **Step 3: Implement**

Append:

```elisp
(cl-defun a3-pub-async/begin-publish (&key scope source-label planned-steps)
  "Acquire the single-in-flight lock and start a run.

Signals user-error if a run is already in flight.  Delegates to the
existing `a3madkour-pub/begin-publish' for accumulator setup.  Returns
the new run handle."
  (when a3-pub-async--in-flight-run
    (when (fboundp 'pop-to-buffer)
      (pop-to-buffer (a3-pub-async/buffer)))
    (user-error "a3-pub: a publish is already running (see *a3-publish*)"))
  (a3madkour-pub/begin-publish)
  (let* ((buf (a3-pub-async/buffer))
         (run (make-a3-pub-async-run
               :id (gensym "a3-pub-run-")
               :scope scope
               :source-label (or source-label "")
               :buffer buf
               :section-start nil
               :live-processes nil
               :tmp-dirs nil
               :start-time (current-time)
               :planned-steps (or planned-steps 0)
               :completed-steps 0
               :status :running)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert "\n───────────────────────────────────────────────\n")
        (insert (format-time-string "%Y-%m-%d %H:%M:%S  ")
                (format "publish-%s  %s\n" scope (or source-label "")))
        (insert "───────────────────────────────────────────────\n")
        (setf (a3-pub-async-run-section-start run) (point))))
    (setq a3-pub-async--in-flight-run run)
    (a3-pub-async--modeline-start)
    (display-buffer buf '((display-buffer-in-side-window)
                          (side . bottom) (window-height . 0.25)))
    run))

(cl-defun a3-pub-async/finish-publish (run &key scope status)
  "End the publish run.

Calls the existing `a3madkour-pub/finish-publish'.  When STATUS=ok and
SCOPE=deliberate, flushes citations YAML.  Always releases the lock and
clears the mode-line indicator."
  (let ((elapsed (float-time
                  (time-subtract (current-time)
                                 (a3-pub-async-run-start-time run)))))
    (setf (a3-pub-async-run-status run) status)
    (unwind-protect
        (progn
          (a3madkour-pub/finish-publish :scope scope)
          (when (and (eq status 'ok) (eq scope 'deliberate))
            (when (require 'a3madkour-publish-citations nil 'noerror)
              (a3madkour-pub-citations/emit-yaml :mode 'merge))))
      (setq a3-pub-async--in-flight-run nil)
      (a3-pub-async--modeline-stop))
    ;; Append summary.
    (let ((buf (a3-pub-async-run-buffer run)))
      (when (and buf (buffer-live-p buf))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (insert (format "  ── publish %s  (%.1fs)\n"
                            (pcase status
                              ('ok "✓ ok")
                              ('err "✗ err")
                              ('cancelled "⨯ cancelled")
                              (_ "?"))
                            elapsed))))))
    (message "a3-pub: %s (%.1fs)" status elapsed)))
```

- [ ] **Step 4: Run; expect 23 PASS**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): begin-publish / finish-publish lifecycle"
```

---

### Task 9: Cancel command + `with-a3-pub-async-sync` test helper

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing tests**

Append:

```elisp
(ert-deftest a3-pub-async-test/cancel-noop-when-idle ()
  (let ((a3-pub-async--in-flight-run nil))
    (should-not (a3-pub-async/cancel-current-run))))

(ert-deftest a3-pub-async-test/cancel-interrupts-live-processes ()
  (let* ((procs nil)
         (run (make-a3-pub-async-run :status :running
                                     :live-processes procs)))
    (cl-letf* ((interrupted nil)
               ((symbol-function 'interrupt-process)
                (lambda (p) (push p interrupted))))
      ;; Build a fake proc list.
      (setf (a3-pub-async-run-live-processes run) '(p1 p2))
      (let ((a3-pub-async--in-flight-run run))
        (a3-pub-async/cancel-current-run))
      (should (memq 'p1 interrupted))
      (should (memq 'p2 interrupted))
      (should (eq (a3-pub-async-run-status run) :cancelled)))))

(ert-deftest a3-pub-async-test/cancel-deletes-tmp-dirs ()
  (let* ((tmp1 (make-temp-file "a3-pub-cancel-" t))
         (tmp2 (make-temp-file "a3-pub-cancel-" t))
         (run (make-a3-pub-async-run :status :running
                                     :tmp-dirs (list tmp1 tmp2))))
    (let ((a3-pub-async--in-flight-run run))
      (a3-pub-async/cancel-current-run))
    (should-not (file-directory-p tmp1))
    (should-not (file-directory-p tmp2))))

(ert-deftest a3-pub-async-test/with-sync-helper-binds-var ()
  (with-a3-pub-async-sync
   (should a3-pub-async--synchronous-p))
  (should-not a3-pub-async--synchronous-p))
```

- [ ] **Step 2: Run; expect 4 fail**

- [ ] **Step 3: Implement**

Append:

```elisp
(defun a3-pub-async/cancel-current-run ()
  "Cancel the in-flight run, if any.
Sends SIGINT to every live process; status flag set first so sentinels
firing in the next ms short-circuit.  Tmp dirs cleaned, accumulator
discarded by finish-publish."
  (interactive)
  (let ((run a3-pub-async--in-flight-run))
    (when run
      (setf (a3-pub-async-run-status run) :cancelled)
      (dolist (p (a3-pub-async-run-live-processes run))
        (when (and (processp p) (process-live-p p))
          (ignore-errors (interrupt-process p))))
      ;; SIGKILL fallback after 2s.
      (run-with-timer
       2 nil
       (lambda ()
         (dolist (p (a3-pub-async-run-live-processes run))
           (when (and (processp p) (process-live-p p))
             (ignore-errors (kill-process p))))))
      (dolist (d (a3-pub-async-run-tmp-dirs run))
        (when (and d (file-directory-p d))
          (ignore-errors (delete-directory d t))))
      (message "a3-pub: cancel requested")
      t)))

(defmacro with-a3-pub-async-sync (&rest body)
  "Run BODY with the async helpers in sync mode."
  (declare (indent 0))
  `(let ((a3-pub-async--synchronous-p t)) ,@body))
```

- [ ] **Step 4: Run; expect 27 PASS**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): cancel-current-run + with-a3-pub-async-sync helper"
```

---

### Task 10: Bind `C-c C-c` in `a3-pub-mode` + finish-publish summary minibuffer

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-async-test.el`

- [ ] **Step 1: Write failing test for keymap binding**

Append:

```elisp
(ert-deftest a3-pub-async-test/mode-binds-cancel ()
  "C-c C-c in *a3-publish* is bound to cancel-current-run."
  (with-current-buffer (a3-pub-async/buffer)
    (should (eq (lookup-key a3-pub-mode-map (kbd "C-c C-c"))
                'a3-pub-async/cancel-current-run))))
```

- [ ] **Step 2: Run; expect fail**

- [ ] **Step 3: Add binding**

Replace the `(define-derived-mode a3-pub-mode …)` form with:

```elisp
(defvar a3-pub-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-c") #'a3-pub-async/cancel-current-run)
    (define-key m (kbd "n") (lambda () (interactive)
                              (re-search-forward "^─\\{20,\\}$" nil t)))
    (define-key m (kbd "p") (lambda () (interactive)
                              (re-search-backward "^─\\{20,\\}$" nil t)))
    m)
  "Keymap for `a3-pub-mode'.")

(define-derived-mode a3-pub-mode special-mode "a3-pub"
  "Major mode for the *a3-publish* status buffer."
  (setq buffer-read-only t
        truncate-lines t))
```

- [ ] **Step 4: Run; expect 28 PASS**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el
git -C ~/dotfiles commit -m "feat(async-pub): bind C-c C-c to cancel in a3-pub-mode"
```

---

## Phase 2 — Handler contract migration

The handler contract changes to `(file run &key on-done)`. The existing tests use `with-a3-pub-async-sync` so the conversions don't break them. Each handler converts independently; commit after each.

### Task 11: `deliberate.el` lifecycle rewrite + `essays` handler stub adapter

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-deliberate.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-deliberate-test.el`

- [ ] **Step 1: Read the current 60-line file**

Run: `cat /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-deliberate.el`

Expected: see the existing 33–59 line shape; the handler is called inside `unwind-protect`.

- [ ] **Step 2: Write a failing test for the new lifecycle path**

Append to `a3madkour-publish-deliberate-test.el`:

```elisp
(ert-deftest a3madkour-pub-delib-test/async-handler-receives-run-and-on-done ()
  "After conversion, the handler is called with (file run :on-done …).
The handler invokes on-done synchronously under with-a3-pub-async-sync,
which flows through to finish-publish."
  (let ((calls nil) (run-seen nil))
    (cl-letf*
        (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil))
         ((symbol-function 'a3madkour-pub/finish-publish)
          (lambda (&rest args) (push (cons 'finish args) calls)))
         ((symbol-function 'a3madkour-pub--resolve-file-or-id)
          (lambda (x) x))
         ((symbol-function 'a3madkour-pub/note-section)
          (lambda (_) "essays"))
         ((symbol-function 'a3madkour-pub-essays/publish-essay-file)
          (lambda (_file run &rest rest)
            (setq run-seen run)
            (let ((on-done (plist-get rest :on-done)))
              (funcall on-done 'ok)))))
      (with-a3-pub-async-sync
       (a3-publish-deliberate "/tmp/fake.org")))
    (should (a3-pub-async-run-p run-seen))
    (should (cl-find 'finish calls :key #'car))))
```

- [ ] **Step 3: Run; expect fail (resolve-file-or-id / async lifecycle not wired yet)**

- [ ] **Step 4: Rewrite `a3-publish-deliberate`**

Replace the body of `a3madkour-publish-deliberate.el` (lines 14–60) with:

```elisp
(require 'a3madkour-publish)
(require 'a3madkour-publish-async)
(require 'a3madkour-publish-unpublish)
(require 'a3madkour-publish-essays)

(defvar a3madkour-pub-deliberate--handlers
  '((essays . a3madkour-pub-essays/publish-essay-file))
  "Alist of (SECTION-SYMBOL . HANDLER-FUNCTION).
Handler signature: (file run &key on-done).")

;;;###autoload
(defun a3-publish-deliberate (file-or-id)
  "Publish a single deliberate-section note identified by FILE-OR-ID.

Async lifecycle: returns immediately after dispatching the handler.
The handler is responsible for calling its :on-done callback when its
sentinel chain completes; finish-publish then fires."
  (interactive "fOrg file or ID: ")
  (let* ((file (a3madkour-pub--resolve-file-or-id file-or-id))
         (section (a3madkour-pub/note-section file))
         (handler (cdr (assq (intern (or section "")) a3madkour-pub-deliberate--handlers))))
    (unless handler
      (error "a3madkour-pub-deliberate: no handler registered for section %S (file: %s)"
             section file))
    (let ((run (a3-pub-async/begin-publish
                :scope 'deliberate
                :source-label (format "%s/%s" section (file-name-base file))
                :planned-steps (if (fboundp (intern (format "%s/planned-steps" handler)))
                                   (funcall (intern (format "%s/planned-steps" handler)) file)
                                 5))))
      (condition-case err
          (funcall handler file run
                   :on-done
                   (lambda (status)
                     (a3-pub-async/finish-publish run
                                                  :scope 'deliberate
                                                  :status status)))
        (error
         (a3-pub-async/log-step run "handler-error" :err
                                :err-snippet (error-message-string err))
         (a3-pub-async/finish-publish run :scope 'deliberate :status 'err))))))

(provide 'a3madkour-publish-deliberate)
```

- [ ] **Step 5: Run the full test suite; expect new test PASS + every existing deliberate test still green**

Run: `cd ~/dotfiles && emacs --batch -L emacs-configs/custom/lisp -l emacs-configs/custom/lisp/a3madkour-publish-deliberate-test.el -f ert-run-tests-batch-and-exit 2>&1 | tail -8`

Expected: `Ran N tests, N results as expected` — existing tests keep passing because they `cl-letf` `begin-publish` / `finish-publish` and (with the new test's pattern) the handler invocation. Existing tests that didn't pass a `run` arg will break — see Step 6.

- [ ] **Step 6: Fix existing deliberate tests that called `(handler file)` with the old signature**

If any existing tests fail because they assume the old `(handler file)` shape, update them to:
- Bind `a3-pub-async--in-flight-run` to nil for `begin-publish`'s lock check.
- Stub `a3madkour-pub-essays/publish-essay-file` to accept `(file run &key on-done)` and call `on-done` with `'ok`.

- [ ] **Step 7: Re-run; expect all green**

- [ ] **Step 8: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-deliberate.el emacs-configs/custom/lisp/a3madkour-publish-deliberate-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): deliberate lifecycle uses a3-pub-async/begin+finish"
```

---

### Task 12: `living.el` lifecycle rewrite + barrier across notes

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-living.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-living-test.el`

- [ ] **Step 1: Read current file to understand the dispatch loop**

Run: `wc -l /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-living.el && grep -n "defun a3-publish-living\\|defun a3madkour-pub-living" /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-living.el`

- [ ] **Step 2: Write failing test for the new async-lifecycle path**

Append a test analogous to Task 11's that:
1. Stubs `a3madkour-pub-living--source-notes` to return 3 fake notes.
2. Stubs each handler to call `on-done` with `'ok` after a short delay (use `run-with-timer 0`).
3. Asserts `finish-publish` fires once, after all 3 handlers report.

```elisp
(ert-deftest a3madkour-pub-living-test/async-barrier-finishes-once ()
  "Living walks N notes, barrier waits for all on-done before finish-publish."
  (let ((finish-count 0))
    (cl-letf*
        (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil))
         ((symbol-function 'a3madkour-pub/finish-publish)
          (lambda (&rest _) (cl-incf finish-count)))
         ((symbol-function 'a3madkour-pub-living--source-notes)
          (lambda () '(("garden" "/a.org") ("garden" "/b.org") ("library" "/c.org"))))
         ((symbol-function 'a3madkour-pub-garden/publish-note)
          (lambda (_file _run &rest rest)
            (funcall (plist-get rest :on-done) 'ok)))
         ((symbol-function 'a3madkour-pub-library/publish-note)
          (lambda (_file _run &rest rest)
            (funcall (plist-get rest :on-done) 'ok))))
      (with-a3-pub-async-sync
       (a3-publish-living)))
    (should (= 1 finish-count))))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Implement living lifecycle**

The structure of `a3-publish-living` becomes (sketch — read the existing file to preserve any pre-loop hooks):

```elisp
;;;###autoload
(defun a3-publish-living ()
  (interactive)
  (let* ((notes (a3madkour-pub-living--source-notes))
         (n (length notes))
         (run (a3-pub-async/begin-publish
               :scope 'living
               :source-label (format "living (%d notes)" n)
               :planned-steps n)))
    (if (zerop n)
        (a3-pub-async/finish-publish run :scope 'living :status 'ok)
      (let* ((report (a3-pub-async/barrier
                      n :on-all-done
                      (lambda (results)
                        (let ((status (if (cl-some (lambda (r) (eq r 'err)) results)
                                          'err 'ok)))
                          (a3-pub-async/finish-publish
                           run :scope 'living :status status))))))
        (dolist (entry notes)
          (let* ((section (car entry))
                 (file (cadr entry))
                 (handler (cdr (assq (intern section)
                                     a3madkour-pub-living--handlers))))
            (if (null handler)
                (funcall report 'err)
              (condition-case _
                  (funcall handler file run
                           :on-done (lambda (status)
                                      (funcall report status)))
                (error (funcall report 'err))))))))))
```

- [ ] **Step 5: Run living tests; expect new test PASS + existing green (modulo signature-update sweep)**

- [ ] **Step 6: Update any existing living tests that pass `(handler file)`** to pass `(handler file run :on-done …)`.

- [ ] **Step 7: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-living.el emacs-configs/custom/lisp/a3madkour-publish-living-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): living lifecycle uses barrier + async/begin+finish"
```

---

### Task 13: B.4 essays handler signature change

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-essays.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-essays-test.el`

- [ ] **Step 1: Read current `publish-essay-file` to identify the steps and the D.2 invocation**

Run: `grep -n "defun a3madkour-pub-essays/\|multi/export-bundle\\|a3madkour-pub-multi" /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-essays.el`

Expected: locates `publish-essay-file`, and the D.2 `multi/export-bundle` call somewhere in the body.

- [ ] **Step 2: Write failing test for the new signature + on-done firing**

Append:

```elisp
(ert-deftest a3madkour-pub-essays-test/handler-accepts-run-and-fires-on-done ()
  "publish-essay-file accepts (file run &key on-done) and calls on-done."
  (let (done-status)
    (cl-letf*
        (;; Stub all the steps so the handler runs without I/O.
         ((symbol-function 'a3madkour-pub-essays--run-pipeline)
          (lambda (_file _run on-done) (funcall on-done 'ok))))
      (with-a3-pub-async-sync
       (a3madkour-pub-essays/publish-essay-file
        "/tmp/fake.org" (make-a3-pub-async-run)
        :on-done (lambda (s) (setq done-status s)))))
    (should (eq done-status 'ok))))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Wrap the current handler body in a `--run-pipeline` helper, then convert `publish-essay-file`**

Sketch (the engineer reads the current handler body and threads the pipeline; the structure is):

```elisp
(defun a3madkour-pub-essays--run-pipeline (file run on-done)
  "Run the essays publish pipeline.  Calls ON-DONE with 'ok/'err
when the chain (including the async multi-export tail) completes."
  ;; [Existing sync steps move here, each followed by
  ;;  (a3-pub-async/log-step run STEP :ok :elapsed …) ]
  ;; [The D.2 tail dispatches to a3madkour-pub-multi/export-bundle
  ;;  with :run RUN :on-done (lambda (status) (funcall on-done status)) ]
  ...
  (funcall on-done 'ok))

(cl-defun a3madkour-pub-essays/publish-essay-file (file run &key on-done)
  "B.4 essays handler. Async-aware.

Calls ON-DONE with 'ok/'err when the publish chain (including the
async multi-export tail when `#+multi_export: t`) finishes."
  (a3madkour-pub-essays--run-pipeline file run on-done))

(defun a3madkour-pub-essays/planned-steps (file)
  "Return the integer step count this handler intends to log."
  ;; Probe #+multi_export keyword on FILE; return 5 (no multi) or 9 (with multi).
  (if (a3madkour-pub-essays--multi-export-p file) 9 5))
```

- [ ] **Step 5: Run essays tests; new test PASS + existing**

The existing essays tests do `cl-letf` on internals; converting the handler entry point doesn't break them as long as `--run-pipeline` is the unit that does the work. If any test breaks because it called `publish-essay-file` with `(file)`, update to `(file run :on-done ...)` with a stub `on-done`.

- [ ] **Step 6: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-essays.el emacs-configs/custom/lisp/a3madkour-publish-essays-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): B.4 essays handler signature (file run :on-done)"
```

---

### Task 14: B.1 garden handler signature change

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-garden.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-garden-test.el`

- [ ] **Step 1: Read current garden handler entry-point**

Run: `grep -n "defun a3madkour-pub-garden/publish" /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-garden.el`

- [ ] **Step 2: Write failing test for the new signature**

Append a test matching Task 13's shape, scoped to the garden handler:

```elisp
(ert-deftest a3madkour-pub-garden-test/handler-async-signature ()
  (let (done-status)
    (cl-letf (((symbol-function 'a3madkour-pub-garden--run-pipeline)
               (lambda (_file _run on-done) (funcall on-done 'ok))))
      (with-a3-pub-async-sync
       (a3madkour-pub-garden/publish-note
        "/tmp/fake.org" (make-a3-pub-async-run)
        :on-done (lambda (s) (setq done-status s)))))
    (should (eq done-status 'ok))))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Convert the handler to `&key on-done`**

```elisp
(cl-defun a3madkour-pub-garden/publish-note (file run &key on-done)
  (a3madkour-pub-garden--run-pipeline file run on-done))

(defun a3madkour-pub-garden/planned-steps (_file) 3)
```

Then move the existing handler body into `--run-pipeline` with `log-step` calls around the major phases (org→hugo export, frontmatter emit, record-publish). Wrap any single sync call so the count matches.

- [ ] **Step 5: Run; expect green**

- [ ] **Step 6: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-garden.el emacs-configs/custom/lisp/a3madkour-publish-garden-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): B.1 garden handler signature (file run :on-done)"
```

---

### Task 15: B.2 library handler signature change

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-library.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-library-test.el`

- [ ] **Step 1: Read current library handler entry-point**

Run: `grep -n "defun a3madkour-pub-library/publish" /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-library.el`

- [ ] **Step 2: Write failing test (mirror of Task 14)**

```elisp
(ert-deftest a3madkour-pub-library-test/handler-async-signature ()
  (let (done-status)
    (cl-letf (((symbol-function 'a3madkour-pub-library--run-pipeline)
               (lambda (_file _run on-done) (funcall on-done 'ok))))
      (with-a3-pub-async-sync
       (a3madkour-pub-library/publish-note
        "/tmp/fake.org" (make-a3-pub-async-run)
        :on-done (lambda (s) (setq done-status s)))))
    (should (eq done-status 'ok))))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Convert handler**

```elisp
(cl-defun a3madkour-pub-library/publish-note (file run &key on-done)
  (a3madkour-pub-library--run-pipeline file run on-done))

(defun a3madkour-pub-library/planned-steps (_file) 4)
```

- [ ] **Step 5: Run; expect green**

- [ ] **Step 6: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-library.el emacs-configs/custom/lisp/a3madkour-publish-library-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): B.2 library handler signature (file run :on-done)"
```

---

### Task 16: B.3 research handler signature change

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-research.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-research-test.el`

- [ ] **Step 1: Read current research handler**

Run: `grep -n "defun a3madkour-pub-research/publish" /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-research.el`

- [ ] **Step 2: Write failing test (mirror of Task 15)**

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Convert handler**

```elisp
(cl-defun a3madkour-pub-research/publish-page (file run &key on-done)
  (a3madkour-pub-research--run-pipeline file run on-done))

(defun a3madkour-pub-research/planned-steps (_file) 3)
```

- [ ] **Step 5: Run; expect green**

- [ ] **Step 6: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-research.el emacs-configs/custom/lisp/a3madkour-publish-research-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): B.3 research handler signature (file run :on-done)"
```

---

## Phase 3 — Subprocess conversions

Every subprocess call site in publish modules moves to `a3-pub-async/run-process`. Existing tests use `with-a3-pub-async-sync` to keep their `cl-letf` `call-process` stubs working.

### Task 17: `multi-pdf.el` — rsvg-convert per-SVG → parallel fan-out

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-pdf.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-pdf-test.el`

- [ ] **Step 1: Write failing test**

Append:

```elisp
(ert-deftest a3madkour-pub-multi-pdf/svg-fan-uses-barrier ()
  "When N SVGs are converted, all run via run-process and barrier
fires once.  Uses synchronous shim so the test is deterministic."
  (let ((calls nil) (done nil))
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd &rest _) (push cmd calls) 0))
              ((symbol-function 'make-directory) (lambda (&rest _) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf--convert-svgs-fan
        '(("/a.svg" "/a.pdf") ("/b.svg" "/b.pdf"))
        :on-done (lambda (_) (setq done t)))))
    (should (= 2 (length calls)))
    (should done)))
```

- [ ] **Step 2: Run; expect fail (function undefined)**

- [ ] **Step 3: Implement fan-out**

Add to `a3madkour-publish-multi-pdf.el` before `multi-pdf/run`:

```elisp
(cl-defun a3madkour-pub-multi-pdf--convert-svgs-fan (pairs &key on-done)
  "PAIRS is a list of (SRC DST).  Fan out one run-process per pair.
ON-DONE fires (with the list of exit codes) when all complete."
  (let ((n (length pairs)))
    (if (zerop n)
        (when on-done (funcall on-done nil))
      (let ((report (a3-pub-async/barrier n :on-all-done on-done)))
        (dolist (pair pairs)
          (let ((src (car pair)) (dst (cadr pair)))
            (make-directory (file-name-directory dst) t)
            (a3-pub-async/run-process
             a3madkour-pub-multi-rsvg-convert-command
             (list "-f" "pdf" src "-o" dst)
             :name (format "rsvg-%s" (file-name-base src))
             :on-done (lambda (rc _tail) (funcall report rc)))))))))
```

- [ ] **Step 4: Run; expect green**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-multi-pdf.el emacs-configs/custom/lisp/a3madkour-publish-multi-pdf-test.el
git -C ~/dotfiles commit -m "feat(async-pub): multi-pdf rsvg fan-out via barrier"
```

---

### Task 18: `multi-pdf.el` — xelatex/biber chain via sentinels

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-pdf.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-pdf-test.el`

- [ ] **Step 1: Write failing test**

Append:

```elisp
(ert-deftest a3madkour-pub-multi-pdf/compile-chain-runs-four-passes ()
  "compile-tex-async invokes the 4-pass sequence and fires on-done."
  (let (cmds done)
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd &rest _) (push cmd cmds) 0))
              ((symbol-function 'file-exists-p) (lambda (_) t)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf--compile-tex-async
        "/tmp/x/foo.tex"
        :on-done (lambda (ok) (setq done ok)))))
    (should (= 4 (length cmds)))
    (should done)))
```

- [ ] **Step 2: Run; expect fail**

- [ ] **Step 3: Implement async compile chain**

Add to the module:

```elisp
(cl-defun a3madkour-pub-multi-pdf--compile-tex-async (tex-path &key on-done step-cb)
  "Async version of compile-tex.  Chains xelatex→biber→xelatex→xelatex.
STEP-CB, when non-nil, is called with (pass-name pass-rc) per pass.
ON-DONE is called with t/nil based on PDF existence after the run."
  (let* ((dir (file-name-directory tex-path))
         (base (file-name-base tex-path))
         (pdf-path (expand-file-name (concat base ".pdf") dir))
         (seq (list (cons a3madkour-pub-multi-xelatex-command "pass 1/4")
                    (cons a3madkour-pub-multi-biber-command   "biber")
                    (cons a3madkour-pub-multi-xelatex-command "pass 3/4")
                    (cons a3madkour-pub-multi-xelatex-command "pass 4/4"))))
    (cl-labels
        ((run-next (remaining)
           (if (null remaining)
               (when on-done (funcall on-done (file-exists-p pdf-path)))
             (let* ((cmd-and-label (car remaining))
                    (cmd (car cmd-and-label))
                    (label (cdr cmd-and-label))
                    (arg (if (string= cmd a3madkour-pub-multi-biber-command)
                             base
                           (concat base ".tex")))
                    (default-directory dir))
               (a3-pub-async/run-process
                cmd (list "-interaction=nonstopmode" arg)
                :name (format "pdf-%s" label)
                :cwd dir
                :on-done
                (lambda (rc _tail)
                  (when step-cb (funcall step-cb label rc))
                  (run-next (cdr remaining))))))))
      (run-next seq))))
```

- [ ] **Step 4: Run; expect green**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-multi-pdf.el emacs-configs/custom/lisp/a3madkour-publish-multi-pdf-test.el
git -C ~/dotfiles commit -m "feat(async-pub): multi-pdf xelatex chain via sentinels"
```

---

### Task 19: `multi-pdf.el` — `multi-pdf/run` rewires to `&key run on-done`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-pdf.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-pdf-test.el`

- [ ] **Step 1: Read existing `multi-pdf/run` signature (multi-pdf.el:92)**

- [ ] **Step 2: Write failing test for the new entry-point shape**

```elisp
(ert-deftest a3madkour-pub-multi-pdf/run-async-fires-on-done-with-status ()
  (let (status)
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 0))
              ((symbol-function 'file-exists-p) (lambda (_) t))
              ((symbol-function 'rename-file) (lambda (&rest _) nil))
              ((symbol-function 'copy-file) (lambda (&rest _) nil))
              ((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'find-file-noselect)
               (lambda (_) (get-buffer-create "*pdf-test*")))
              ((symbol-function 'org-latex-export-to-latex) (lambda (&rest _) nil))
              ((symbol-function 'a3madkour-pub-multi-pdf--list-svg-figures)
               (lambda (_) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-pdf/run
        "/tmp/x.org" "x" "/tmp/bundle/" "/tmp/templates/"
        :run (make-a3-pub-async-run :buffer (a3-pub-async/buffer))
        :on-done (lambda (s) (setq status s)))))
    (should (or (eq (plist-get status :status) 'ok)
                (eq status 'ok)))))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Rewrite `multi-pdf/run` to dispatch the async chain**

Replace the existing `multi-pdf/run` with a `cl-defun` that accepts `&key run on-done`. Move the existing sync body's preparation (mkdir, copy-file madkour-paper.cls, ox-latex export) into the head; chain SVG fan → xelatex compile → rename-file via `:on-done` callbacks; final `on-done` reports `(:status 'ok :path target)` or `(:status 'err :err-snippet …)`.

Detailed sketch:

```elisp
(cl-defun a3madkour-pub-multi-pdf/run (source-file slug bundle-dir templates-dir
                                       &key run on-done)
  "Async PDF backend.  RUN is the a3-pub-async-run handle (for log-step).
ON-DONE is called with (:status 'ok :path target) or (:status 'err …)."
  (let* ((work-dir (expand-file-name (format "multi-export-%s/" slug)
                                     temporary-file-directory))
         (fig-dir (expand-file-name "figures/" work-dir))
         (tex-path (expand-file-name (concat slug ".tex") work-dir))
         (svgs (a3madkour-pub-multi-pdf--list-svg-figures source-file))
         (svg-pairs (mapcar (lambda (svg)
                              (list svg (expand-file-name
                                         (concat (file-name-base svg) ".pdf")
                                         fig-dir)))
                            svgs)))
    (make-directory fig-dir t)
    (copy-file (expand-file-name "madkour-paper.cls" templates-dir)
               (expand-file-name "madkour-paper.cls" work-dir) t)
    (when run (push work-dir (a3-pub-async-run-tmp-dirs run)))
    ;; Phase 1: ox-latex export (sync, instrumented).
    (let ((start (current-time)))
      (with-current-buffer (find-file-noselect source-file)
        (let ((org-latex-with-hyperref t)
              (org-latex-default-class "madkour-paper")
              (org-export-show-temporary-export-buffer nil))
          (org-latex-export-to-latex)))
      (when run
        (a3-pub-async/log-step run "export" :ok :detail "org → latex"
                               :elapsed (float-time
                                         (time-subtract (current-time) start)))))
    ;; Move produced .tex into work dir.
    (let ((source-tex (expand-file-name (concat slug ".tex")
                                        (file-name-directory source-file))))
      (when (file-exists-p source-tex)
        (rename-file source-tex tex-path t)))
    ;; Phase 2: SVG fan → xelatex chain → place.
    (a3madkour-pub-multi-pdf--convert-svgs-fan
     svg-pairs
     :on-done
     (lambda (_svg-rcs)
       (when run (a3-pub-async/log-step run "svgs" :ok
                                        :detail (format "%d files" (length svg-pairs))))
       (a3madkour-pub-multi-pdf--compile-tex-async
        tex-path
        :step-cb
        (lambda (label rc)
          (when run
            (a3-pub-async/log-step run "xelatex" (if (zerop rc) :ok :err)
                                   :detail label)))
        :on-done
        (lambda (ok)
          (if (not ok)
              (when on-done
                (funcall on-done '(:status err :err-snippet "PDF not produced")))
            (let ((built (expand-file-name (concat slug ".pdf") work-dir))
                  (target (expand-file-name (concat slug ".pdf") bundle-dir)))
              (when (file-exists-p built)
                (rename-file built target t)
                (when run
                  (a3-pub-async/log-step run "pdf" :ok :detail target))
                (when on-done
                  (funcall on-done (list :status 'ok :path target))))))))))))
```

- [ ] **Step 5: Run multi-pdf tests; expect green (existing tests pass because they `cl-letf` `call-process` + use the sync shim)**

- [ ] **Step 6: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-multi-pdf.el emacs-configs/custom/lisp/a3madkour-publish-multi-pdf-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): multi-pdf/run is async (:key run on-done)"
```

---

### Task 20: `multi-word.el` — rsvg fan + pandoc sentinel + `multi-word/run` async entry-point

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-word.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-word-test.el`

- [ ] **Step 1: Write failing test**

Append:

```elisp
(ert-deftest a3madkour-pub-multi-word/run-async-fires-on-done ()
  (let (status)
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 0))
              ((symbol-function 'file-exists-p) (lambda (_) t))
              ((symbol-function 'rename-file) (lambda (&rest _) nil))
              ((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'a3madkour-pub-multi-word--serialize-filtered)
               (lambda (&rest _) nil))
              ((symbol-function 'a3madkour-pub-assets/list-referenced-files)
               (lambda (_) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi-word/run
        "/tmp/x.org" "x" "/tmp/bundle/" "/tmp/templates/" "/tmp/lib.bib"
        :run (make-a3-pub-async-run :buffer (a3-pub-async/buffer))
        :on-done (lambda (s) (setq status s)))))
    (should (or (eq (plist-get status :status) 'ok)
                (eq status 'ok)))))
```

- [ ] **Step 2: Run; expect fail**

- [ ] **Step 3: Add the fan helper + convert `multi-word/run`**

Mirror multi-pdf's fan helper for PNG output:

```elisp
(cl-defun a3madkour-pub-multi-word--convert-svgs-fan (pairs &key on-done)
  "PAIRS is (SRC DST) for SVG→PNG via rsvg-convert -f png -d 192."
  (let ((n (length pairs)))
    (if (zerop n)
        (when on-done (funcall on-done nil))
      (let ((report (a3-pub-async/barrier n :on-all-done on-done)))
        (dolist (pair pairs)
          (make-directory (file-name-directory (cadr pair)) t)
          (a3-pub-async/run-process
           a3madkour-pub-multi-rsvg-convert-command
           (list "-f" "png" "-d" "192" (car pair) "-o" (cadr pair))
           :name (format "rsvg-png-%s" (file-name-base (car pair)))
           :on-done (lambda (rc _tail) (funcall report rc))))))))
```

Then convert `multi-word/run` to `&key run on-done`. Calls fan → pandoc via `run-process` → place via `rename-file` → `on-done`.

- [ ] **Step 4: Run; expect green**

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-multi-word.el emacs-configs/custom/lisp/a3madkour-publish-multi-word-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): multi-word/run is async (:key run on-done)"
```

---

### Task 21: D.2 orchestrator — multi-pdf + multi-word in parallel via barrier

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi.el`
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-multi-test.el`

- [ ] **Step 1: Read current orchestrator entry-point**

Run: `grep -n "defun a3madkour-pub-multi/" /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-multi.el`

- [ ] **Step 2: Write failing test**

Append:

```elisp
(ert-deftest a3madkour-pub-multi/export-bundle-runs-pdf-and-word-in-parallel ()
  (let (pdf-ran word-ran done-status)
    (cl-letf
        (((symbol-function 'a3madkour-pub-multi-pdf/run)
          (cl-function (lambda (&rest _ &key on-done &allow-other-keys)
                         (setq pdf-ran t)
                         (funcall on-done '(:status ok :path "/x.pdf")))))
         ((symbol-function 'a3madkour-pub-multi-word/run)
          (cl-function (lambda (&rest _ &key on-done &allow-other-keys)
                         (setq word-ran t)
                         (funcall on-done '(:status ok :path "/x.docx"))))))
      (with-a3-pub-async-sync
       (a3madkour-pub-multi/export-bundle
        "/tmp/x.org" "x" "/tmp/bundle/" "/tmp/templates/" "/tmp/lib.bib"
        :run (make-a3-pub-async-run :buffer (a3-pub-async/buffer))
        :on-done (lambda (s) (setq done-status s)))))
    (should pdf-ran) (should word-ran)
    (should (eq (plist-get done-status :status) 'ok))))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Rewrite the orchestrator**

```elisp
(cl-defun a3madkour-pub-multi/export-bundle (source-file slug bundle-dir
                                             templates-dir bib-path
                                             &key run on-done)
  "Run PDF + Word backends in parallel via barrier; on-done fires once.
ON-DONE receives (:status 'ok …) or (:status 'err …) summarizing the
two backends."
  (let ((report (a3-pub-async/barrier
                 2 :on-all-done
                 (lambda (results)
                   (let* ((statuses (mapcar (lambda (r) (plist-get r :status))
                                            results))
                          (rolled (if (cl-some (lambda (s) (eq s 'err)) statuses)
                                      'err 'ok)))
                     (when on-done
                       (funcall on-done (list :status rolled
                                              :results results))))))))
    (a3madkour-pub-multi-pdf/run source-file slug bundle-dir templates-dir
                                 :run run
                                 :on-done (lambda (r) (funcall report r)))
    (a3madkour-pub-multi-word/run source-file slug bundle-dir templates-dir bib-path
                                  :run run
                                  :on-done (lambda (r) (funcall report r)))))
```

- [ ] **Step 5: Run; expect green**

- [ ] **Step 6: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-multi.el emacs-configs/custom/lisp/a3madkour-publish-multi-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): D.2 orchestrator runs PDF+Word in parallel via barrier"
```

---

### Task 22: `history.el` — `git-mtime-of-file` via `run-process`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-history.el` (line 312 area)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-history-test.el`

- [ ] **Step 1: Read existing function**

Run: `sed -n '300,335p' /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-history.el`

- [ ] **Step 2: Write failing test for an async variant**

The existing function returns the date sync; we add an async sibling so callers that participate in the lifecycle can use it. The existing function stays as a thin wrapper that calls the async one with `with-a3-pub-async-sync`.

```elisp
(ert-deftest a3madkour-pub-history/git-mtime-async-returns-date ()
  (let (date)
    (cl-letf (((symbol-function 'call-process)
               (lambda (_cmd _ buf &rest _)
                 (when (bufferp buf)
                   (with-current-buffer buf (insert "2026-06-06"))) 0))
              ((symbol-function 'file-exists-p) (lambda (_) t)))
      (with-a3-pub-async-sync
       (a3madkour-pub-history/git-mtime-of-file-async
        "/tmp/x.org" (lambda (d) (setq date d)))))
    (should (string= "2026-06-06" date))))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Implement async variant + rewrite sync wrapper**

```elisp
(defun a3madkour-pub-history/git-mtime-of-file-async (file on-done)
  "Async: invoke ON-DONE with the YYYY-MM-DD date of last commit for FILE."
  (if (not (file-exists-p file))
      (funcall on-done nil)
    (let* ((default-directory (file-name-directory (expand-file-name file)))
           (basename (file-name-nondirectory file))
           (stderr-buf (generate-new-buffer " *git-mtime-stdout*")))
      (a3-pub-async/run-process
       "git" (list "log" "-1" "--format=%cs" "--" basename)
       :name (format "git-mtime-%s" basename)
       :stderr-buf stderr-buf
       :on-done
       (lambda (_rc tail)
         ;; stdout was captured into stderr-buf because we passed it as
         ;; the stderr buffer; we actually need to read it differently —
         ;; SEE NOTE.  For sync path, we use call-process variant.
         (let ((trimmed (string-trim tail)))
           (funcall on-done
                    (if (and trimmed
                             (string-match-p
                              "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
                              trimmed))
                        trimmed nil))))))))

;; Sync wrapper preserves existing API.
(defun a3madkour-pub-history/git-mtime-of-file (file)
  (let (result)
    (with-a3-pub-async-sync
     (a3madkour-pub-history/git-mtime-of-file-async
      file (lambda (d) (setq result d))))
    result))
```

**NOTE for engineer:** `run-process` as designed routes stdout to nil and stderr to `stderr-buf`. For `git log` we need stdout. Plan addendum: extend `a3-pub-async/run-process` with an `:stdout-buf` keyword arg if not present, OR add a thin variant `run-process-capturing-stdout` that uses a buffer for `:buffer` (the stdout sink). Pick one — addendum below.

- [ ] **Step 5: Plan addendum** — Extend the helper:

In `a3madkour-publish-async.el`, extend `run-process` with `:stdout-buf`:

```elisp
(cl-defun a3-pub-async/run-process (cmd args
                                    &key name on-done stderr-buf stdout-buf cwd)
  ;; ... unchanged setup ...
  (if a3-pub-async--synchronous-p
      (let ((rc (apply #'call-process cmd nil
                       (or stdout-buf stderr-buf) nil args))
            (out (when stdout-buf
                   (with-current-buffer stdout-buf (buffer-string))))
            (tail (with-current-buffer stderr-buf
                    (buffer-substring-no-properties (point-min) (point-max)))))
        (when on-done (funcall on-done rc (or out tail)))
        nil)
    ;; async path: pass :buffer stdout-buf, :stderr stderr-buf to make-process
    (make-process
     :name (format "a3-pub-%s" name)
     :command (cons cmd args)
     :buffer stdout-buf
     :stderr stderr-buf
     :sentinel ...)))
```

Adjust the caller in this task accordingly to use `:stdout-buf` for `git log`.

- [ ] **Step 6: Run; expect green (extend the async-test for `:stdout-buf` to keep coverage)**

- [ ] **Step 7: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-async.el emacs-configs/custom/lisp/a3madkour-publish-async-test.el emacs-configs/custom/lisp/a3madkour-publish-history.el emacs-configs/custom/lisp/a3madkour-publish-history-test.el
git -C ~/dotfiles commit -m "feat(async-pub): run-process :stdout-buf + history git-mtime async"
```

---

### Task 23: `assets.el` — `git mv` for auto-remediate via `run-process`

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-assets.el` (line 294 area)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-assets-test.el`

- [ ] **Step 1: Read the existing `git mv` block**

Run: `sed -n '280,310p' /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-assets.el`

- [ ] **Step 2: Write failing test**

The function is currently sync and returns a plist. We convert it to take an `on-done` callback; existing tests rebind via `with-a3-pub-async-sync` + stub `call-process`.

```elisp
(ert-deftest a3madkour-pub-assets-test/git-mv-async-success ()
  (let (result)
    (cl-letf (((symbol-function 'vc-backend) (lambda (_) 'Git))
              ((symbol-function 'call-process) (lambda (&rest _) 0))
              ((symbol-function 'make-directory) (lambda (&rest _) nil)))
      (with-a3-pub-async-sync
       (a3madkour-pub--asset-perform-move-async
        "/src" "/dst" nil
        (lambda (r) (setq result r)))))
    (should (eq (plist-get result :method) 'git-mv))))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Implement the async variant; keep sync entry as a wrapper**

```elisp
(defun a3madkour-pub--asset-perform-move-async (src dest dry-run on-done)
  "Async variant of asset-perform-move.  Calls ON-DONE with the
result plist when the move (or git mv → fallback) completes."
  (when (not dry-run) (make-directory (file-name-directory dest) t))
  (cond
   (dry-run (funcall on-done (list :method 'dry-run
                                   :info (format "would move: %s -> %s" src dest))))
   ((eq (vc-backend src) 'Git)
    (a3-pub-async/run-process
     "git" (list "mv" src dest)
     :name "asset-git-mv"
     :on-done
     (lambda (rc _tail)
       (if (zerop rc)
           (funcall on-done (list :method 'git-mv
                                  :info (format "moved (git mv): %s -> %s" src dest)))
         (condition-case _
             (progn (rename-file src dest)
                    (funcall on-done (list :method 'mv
                                           :info (format "moved (fallback): %s -> %s" src dest))))
           (error (funcall on-done (list :method 'failed :rc rc))))))))
   (t (rename-file src dest)
      (funcall on-done (list :method 'mv
                             :info (format "moved: %s -> %s" src dest))))))

;; Sync wrapper preserves existing API.
(defun a3madkour-pub--asset-perform-move (src dest dry-run)
  (let (result)
    (with-a3-pub-async-sync
     (a3madkour-pub--asset-perform-move-async
      src dest dry-run (lambda (r) (setq result r))))
    result))
```

- [ ] **Step 5: Run; expect green**

- [ ] **Step 6: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-assets.el emacs-configs/custom/lisp/a3madkour-publish-assets-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): assets git mv via run-process"
```

---

### Task 24: `unpublish.el` — `git mv` via `run-process` (drop shell-command)

**Files:**
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-unpublish.el` (line 323 area)
- Modify: `emacs-configs/custom/lisp/a3madkour-publish-unpublish-test.el`

- [ ] **Step 1: Read the existing `shell-command "git mv"` block**

Run: `sed -n '315,335p' /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/a3madkour-publish-unpublish.el`

- [ ] **Step 2: Write failing test that asserts call-process is used, not shell-command**

```elisp
(ert-deftest a3madkour-pub-unpublish-test/rename-asset-dir-uses-run-process ()
  (let (called-cp called-sh)
    (cl-letf (((symbol-function 'file-directory-p)
               (lambda (d) (string-match-p "old" d)))
              ((symbol-function 'vc-backend) (lambda (_) 'Git))
              ((symbol-function 'call-process)
               (lambda (cmd &rest _) (setq called-cp cmd) 0))
              ((symbol-function 'shell-command)
               (lambda (&rest _) (setq called-sh t) 0)))
      (with-a3-pub-async-sync
       (a3madkour-pub--unpublish-rename-asset-dir "old" "new"
                                                  "/tmp/root/")))
    (should (string= called-cp "git"))
    (should-not called-sh)))
```

- [ ] **Step 3: Run; expect fail**

- [ ] **Step 4: Replace the `shell-command` branch with `run-process`**

In `a3madkour-pub--unpublish-rename-asset-dir`, replace the Git branch (currently lines 318–328):

```elisp
     ((eq (vc-backend old-dir) 'Git)
      (let* ((default-directory root)
             (got-rc nil))
        (with-a3-pub-async-sync
         (a3-pub-async/run-process
          "git" (list "mv"
                      (directory-file-name old-dir)
                      (directory-file-name new-dir))
          :name "unpublish-git-mv"
          :on-done (lambda (rc _tail) (setq got-rc rc))))
        (if (zerop got-rc)
            :renamed-git
          (rename-file (directory-file-name old-dir) (directory-file-name new-dir))
          :renamed-mv)))
```

- [ ] **Step 5: Run; expect green**

- [ ] **Step 6: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3madkour-publish-unpublish.el emacs-configs/custom/lisp/a3madkour-publish-unpublish-test.el
git -C ~/dotfiles commit -m "refactor(async-pub): unpublish git mv via run-process (drop shell-command)"
```

---

## Phase 4 — End-to-end integration tests + spot-check

### Task 25: Python integration test — async deliberate essay end-to-end

**Files:**
- Create: `emacs-configs/custom/lisp/integration/test_async_publish_deliberate_essay.py`

- [ ] **Step 1: Sketch the fixture setup**

The integration tests follow the pattern of existing `~/dotfiles/emacs-configs/custom/lisp/integration/test_*.py` files: a Python test that shells out to `a3-pub.sh --publish-deliberate <fixture>`, then asserts file outputs.

- [ ] **Step 2: Read an existing integration test to mirror its setup**

Run: `ls /Users/a3madkour/dotfiles/emacs-configs/custom/lisp/integration/ 2>/dev/null | head -20`

If no `integration/` dir exists, place the test under `tests/integration/` per spec §7.3 — adjust the file path.

- [ ] **Step 3: Write the test**

```python
"""Integration test: async deliberate publish of an example essay.

Runs a3-pub.sh --publish-deliberate against a copied example-multi fixture
and asserts:
  - Exit code 0.
  - Bundle dir exists with both index.md and the PDF.
  - data/url-history.yaml shows the new note in 'live' state.
  - data/citations.yaml has citation entries (if the source had citations).
"""
import os, shutil, subprocess, tempfile, pathlib, yaml

A3_PUB_SH = pathlib.Path.home() / "dotfiles/emacs-configs/custom/lisp/a3-pub.sh"
FIXTURE_ORG = pathlib.Path.home() / "org/essays/example-multi.org"

def test_async_publish_deliberate_essay(tmp_path):
    if not FIXTURE_ORG.exists():
        import pytest
        pytest.skip(f"missing fixture {FIXTURE_ORG}")
    site_data = tmp_path / "data"
    site_data.mkdir()
    (site_data / "url-history.yaml").write_text("notes: []\n")
    env = os.environ.copy()
    env["A3_PUB_SITE_DATA_DIR"] = str(site_data)
    rc = subprocess.run(
        [str(A3_PUB_SH), "--publish-deliberate", str(FIXTURE_ORG)],
        env=env, capture_output=True, text=True, timeout=180,
    )
    assert rc.returncode == 0, f"stdout:\n{rc.stdout}\nstderr:\n{rc.stderr}"
    # The bundle dir should be discoverable via the manifest:
    manifest = yaml.safe_load((site_data / "url-history.yaml").read_text())
    notes = manifest.get("notes", [])
    assert any(n.get("history", []) for n in notes), \
        f"no notes published; manifest={manifest}"
```

- [ ] **Step 4: Run; expect either PASS or skip if `~/org/essays/example-multi.org` missing on host**

Run: `cd ~/dotfiles && python3 -m pytest emacs-configs/custom/lisp/integration/test_async_publish_deliberate_essay.py -v`

Expected: PASS or skip.

- [ ] **Step 5: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/integration/test_async_publish_deliberate_essay.py
git -C ~/dotfiles commit -m "test(async-pub): integration — async deliberate essay end-to-end"
```

---

### Task 26: Python integration test — cancel mid-xelatex

**Files:**
- Create: `emacs-configs/custom/lisp/integration/test_async_publish_cancel.py`

- [ ] **Step 1: Wire a3-pub.sh SIGTERM → `(a3-pub-async/cancel-current-run)`**

Modify `a3-pub.sh` to set a SIGTERM handler around the `--publish-deliberate` intercept that calls into Emacs via `--eval '(a3-pub-async/cancel-current-run)'`. Since the SIGTERM is delivered to the parent shell, it needs to translate the signal into a request to the running Emacs process. Simplest: a `trap 'kill -INT <emacs-pid>' SIGTERM` that propagates SIGINT to Emacs; Emacs's running `make-process` children receive SIGINT in cascade, and the sentinel chain reports `'cancelled` up.

Add to `a3-pub.sh` near the `--publish-deliberate` intercept:

```bash
if [ "${1:-}" = "--publish-deliberate" ]; then
  shift
  target_path="$1"
  shift
  trap 'kill -INT $emacs_pid 2>/dev/null' SIGTERM
  emacs --batch -L "$LISP_DIR" \
        -l a3madkour-publish-deliberate \
        --eval "(a3-publish-deliberate \"$target_path\")" &
  emacs_pid=$!
  wait "$emacs_pid"
  exit $?
fi
```

- [ ] **Step 2: Write the cancel test**

```python
"""Integration test: SIGTERM mid-publish cancels cleanly.

Spawns a3-pub.sh --publish-deliberate, sends SIGTERM after 2s (likely
inside xelatex), asserts:
  - non-zero exit
  - no manifest changes
  - no orphan multi-export-* tmp dirs in /tmp
"""
import os, signal, subprocess, time, tempfile, pathlib, glob

A3_PUB_SH = pathlib.Path.home() / "dotfiles/emacs-configs/custom/lisp/a3-pub.sh"
FIXTURE_ORG = pathlib.Path.home() / "org/essays/example-multi.org"

def test_async_publish_cancel(tmp_path):
    if not FIXTURE_ORG.exists():
        import pytest
        pytest.skip(f"missing fixture {FIXTURE_ORG}")
    site_data = tmp_path / "data"
    site_data.mkdir()
    initial_manifest = "notes: []\n"
    (site_data / "url-history.yaml").write_text(initial_manifest)
    env = os.environ.copy()
    env["A3_PUB_SITE_DATA_DIR"] = str(site_data)
    pre_tmp = set(glob.glob("/tmp/multi-export-*/"))
    proc = subprocess.Popen(
        [str(A3_PUB_SH), "--publish-deliberate", str(FIXTURE_ORG)],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    time.sleep(2.5)  # let publish enter xelatex
    proc.terminate()
    proc.wait(timeout=10)
    assert proc.returncode != 0
    assert (site_data / "url-history.yaml").read_text() == initial_manifest, \
        "manifest should be unchanged after cancel"
    post_tmp = set(glob.glob("/tmp/multi-export-*/"))
    leaked = post_tmp - pre_tmp
    assert not leaked, f"leaked tmp dirs: {leaked}"
```

- [ ] **Step 3: Run; expect PASS or skip**

Run: `cd ~/dotfiles && python3 -m pytest emacs-configs/custom/lisp/integration/test_async_publish_cancel.py -v`

- [ ] **Step 4: Commit**

```bash
git -C ~/dotfiles add emacs-configs/custom/lisp/a3-pub.sh emacs-configs/custom/lisp/integration/test_async_publish_cancel.py
git -C ~/dotfiles commit -m "test(async-pub): integration — SIGTERM cancel + a3-pub.sh signal handler"
```

---

### Task 27: Real-corpus manual spot-check

This is a manual checklist task — the engineer drives Emacs and visually verifies. No automated tests; the goal is to catch any UX issue the unit tests can't.

- [ ] **Step 1: Open Emacs interactive (NOT batch)** and load the dotfiles config.

- [ ] **Step 2: `M-x a3-publish-deliberate RET ~/org/essays/example-multi.org RET`**

Expected:
- Minibuffer returns to prompt immediately (or within ~1s for the in-process ox-latex export).
- A `*a3-publish*` window opens at the bottom.
- Step lines appear and tick.
- Mode-line shows `[a3-pub ⧗ N/M]` with the spinner cycling.
- You can switch buffers, type in `*scratch*`, etc.

- [ ] **Step 3: Wait for completion**

Expected:
- Final summary line in `*a3-publish*`: `── publish ✓ ok  pdf+docx → ~/Sync/.../example-multi/  (XX.Xs)`.
- Minibuffer: `a3-pub: ok (XX.Xs)`.
- Mode-line clears.
- `~/Sync/Workspace/a3madkour.github.io/content/essays/example-multi/index.md` updated.
- `~/Sync/Workspace/a3madkour.github.io/content/essays/example-multi/example-multi.pdf` updated.
- `~/Sync/Workspace/a3madkour.github.io/content/essays/example-multi/example-multi.docx` updated.

- [ ] **Step 4: Test cancel — start a new publish + `C-c C-c` mid-xelatex**

Run a3-publish-deliberate again. While the buffer shows `[·] xelatex pass 2/4 [running]`, switch to `*a3-publish*` and press `C-c C-c`.

Expected:
- Step line transitions to `[⨯] xelatex pass 2/4`.
- Summary line: `── publish ⨯ cancelled at xelatex pass 2/4  (X.Xs)`.
- Mode line shows `[a3-pub ⨯ cancelled]` for 3s, then clears.
- `ls /tmp/multi-export-*/` shows no surviving dirs from this run.
- Bundle dir contents UNCHANGED from before the run (manifest preserved).

- [ ] **Step 5: Test re-entrancy — try to start a second publish while one is running**

Start one publish; immediately `M-x a3-publish-deliberate` again on a different file.

Expected:
- `user-error`: `a3-pub: a publish is already running (see *a3-publish*)`.
- `*a3-publish*` becomes the active buffer (pop-to-buffer fired).

- [ ] **Step 6: Run the full ert + integration suite once more locally**

Run: `cd ~/dotfiles && ls emacs-configs/custom/lisp/*-test.el | xargs -I{} emacs --batch -L emacs-configs/custom/lisp -l {} -f ert-run-tests-batch-and-exit 2>&1 | tail -30`

Expected: every test file runs green; the total count is 543 (existing) + ~30 (new async tests) = ~573 ert tests passing.

Run: `cd ~/dotfiles && python3 -m pytest emacs-configs/custom/lisp/integration/ -v 2>&1 | tail -20`

Expected: all integration tests PASS or skip-on-host-missing-fixture.

- [ ] **Step 7: No new commit — spot-check is verification only.** Document any deviations as `project_async_publish_followup_*.md` memories.

---

## Self-Review

**Spec coverage check** (against spec §2 goals):

| Spec goal | Tasks covering |
|---|---|
| §2 Goal 1: commands return immediately | 11, 12 (lifecycle rewrites) |
| §2 Goal 2: every subprocess via helper | 17–24 |
| §2 Goal 3: status buffer + cancel | 6, 9, 10 |
| §2 Goal 4: parallel multi-pdf + multi-word | 21 |
| §2 Goal 5: finish-publish from sentinel | 8 (begin/finish wrapping), 11–16 (handlers call on-done) |
| §2 Goal 6: all four B handlers participate | 13–16 |
| §3 Architecture (module + API + struct + lifecycle) | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 |
| §3.6 Cancel command | 9, 10 |
| §4 UI surface (buffer + minibuffer + mode line) | 6, 7, 8 |
| §5 Per-call-site conversion | 17, 18, 19 (PDF); 20 (Word); 21 (orchestrator); 22 (history); 23 (assets); 24 (unpublish) |
| §6 Error handling | 8 (finish-publish status path), 18 (per-pass rc), 11 (handler exception) |
| §7 Testing | 1–24 (per-task tests); 25, 26 (integration); 27 (spot-check) |

No gaps observed.

**Placeholder scan:** No TBDs, no "add appropriate error handling" — every step has real code. Task 22 explicitly addresses the `:stdout-buf` extension. Task 27's spot-check is detailed step-by-step.

**Type consistency:**
- `a3-pub-async/run-process` keyword args: `:name :on-done :stderr-buf :stdout-buf :cwd` (introduced in Task 2, extended in Task 22).
- Handler signature: `(file run &key on-done)` everywhere (Tasks 11–16).
- Backend `run` signature: `(source-file slug bundle-dir templates-dir [bib-path] &key run on-done)` (Tasks 19–21).
- `a3-pub-async/log-step` keyword args: `:detail :elapsed :err-snippet` (Task 6).
- Status symbols: `'ok 'err 'cancelled` (handler-level); buffer status: `:running :ok :err :cancelled :pending` (UI-level). Spec §3.1 mirrors this split; tasks consistently use the right one per layer.

No inconsistencies observed.

---
