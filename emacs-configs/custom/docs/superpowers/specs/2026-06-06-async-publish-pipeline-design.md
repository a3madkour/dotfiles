# Async Publish Pipeline — Design

**Date:** 2026-06-06
**Status:** Design. Brainstorm complete (2026-06-06). Ready for `superpowers:writing-plans`.
**Supersedes stub:** `2026-06-06-async-publish-pipeline-stub.md`

## 1. Context

`M-x a3-publish-deliberate` on `~/org/essays/example-multi.org` froze Emacs for ~30–60s during D.2 verification (see [[project-d2-figref-bundled-fix-complete]]). The publish pipeline runs entirely on synchronous primitives — `call-process`, `shell-command`, in-process `org-latex-export-to-latex`. The editor is unusable for the duration of the slowest backend (xelatex), the user has no progress feedback, and `C-g` is unreliable inside subprocess waits.

Stub inventory of sync call sites in `a3madkour-publish-*.el`:

| File | Line | Call | Cost |
|---|---|---|---|
| `multi-pdf.el` | 57 | `call-process rsvg-convert` (per SVG) | ~100ms × N figures |
| `multi-pdf.el` | 81 | `call-process xelatex / biber / xelatex / xelatex` | **10–60s** |
| `multi-pdf.el` | 116 | `org-latex-export-to-latex` (in-process Lisp) | 1–3s |
| `multi-word.el` | 39 | `call-process rsvg-convert` (per SVG) | ~100ms × N |
| `multi-word.el` | 56 | `call-process pandoc` | 1–3s |
| `history.el` | 312 | `call-process "git log"` (mtime probe) | 10–100ms × N notes |
| `assets.el` | 294 | `call-process "git" "mv"` (auto-remediate) | 10–100ms |
| `unpublish.el` | 323 | `shell-command "git mv …"` (slug rename) | variable |

xelatex is dominant. Everything else is small-N or fast-per-call, but cumulatively the pipeline is fully blocking.

## 2. Goals + non-goals

### Goals

1. `a3-publish-deliberate` and `a3-publish-living` return immediately; Emacs stays interactive during the run.
2. Every external subprocess invoked from `a3madkour-publish-*.el` runs through one helper that uses `make-process` + sentinel. No `call-process` / `shell-command` remains in publish modules.
3. The user can see per-step progress (`*a3-publish*` buffer + minibuffer + mode line) and cancel cleanly with `C-c C-c`.
4. `multi-pdf/run` and `multi-word/run` run concurrently from the D.2 orchestrator; finish-publish only fires after the barrier reports both done.
5. Manifest accumulator, citations accumulator, and URL-history accumulator stay correct under async — `finish-publish` runs from the sentinel of the *last* step, never under `unwind-protect` of a returning command.
6. All four B handlers (B.1 garden, B.2 library, B.3 research, B.4 essays) and both top-level commands (`a3-publish-deliberate`, `a3-publish-living`) participate.

### Non-goals

- ox-latex export stays in-process synchronous. Instrumented in the log buffer (`[✓] export  org → latex  (1.2s)`); follow-up if it becomes the new bottleneck.
- No new Emacs package dependencies. Built on `make-process` / `set-process-sentinel` / `run-with-timer`.
- No queue for a second invocation. `user-error` + pop-to-buffer is the UX.
- No change to subprocess command discovery (xelatex / pandoc / biber / rsvg-convert defcustoms — keep as-is).
- No change to the manifest YAML format, citations YAML, or any `data/*.yaml` emission shape.
- D.2 backend error-reporting format stays the existing `--log-line` shape (`[✓] pdf → path (1.2s)` / `[✗] pdf → exit 5.0s`).
- No change to `org-math-lint` integration (still runs pre-Emacs in `a3-pub.sh`).
- Network calls (BBT fetch, library cover fetch) — separate audit, not in this slice.

## 3. Architecture — `a3madkour-publish-async.el`

One new module owning: subprocess primitive, barrier helper, lifecycle lock, `*a3-publish*` status buffer, mode-line indicator, cancel command.

### 3.1 Public API (5 functions)

```elisp
;; 1. Subprocess primitive.
(a3-pub-async/run-process CMD ARGS &key NAME ON-DONE STDERR-BUF CWD)
  ;; Wraps make-process. Spawns CMD with ARGS, no stdout buffer;
  ;; stderr goes to STDERR-BUF (created if nil, named *a3-pub-stderr NAME*).
  ;; Sentinel fires ON-DONE with (rc stderr-tail-string) when process
  ;; exits. Returns the process object so callers stash it on the run
  ;; handle for cancel.

;; 2. Barrier helper.
(a3-pub-async/barrier N &key ON-ALL-DONE)
  ;; Returns a "report" function. Call it N times with one result each;
  ;; on the Nth call, ON-ALL-DONE is fired with the list of results
  ;; in registration order. N=0 fires ON-ALL-DONE immediately.

;; 3. Lifecycle: begin a run (replaces the open half of unwind-protect).
(a3-pub-async/begin-publish &key SCOPE SOURCE-LABEL)
  ;; Acquires the in-flight lock; user-error if already held.
  ;; Initializes accumulators (delegates to existing
  ;; a3-pub/begin-publish). Opens *a3-publish* buffer, writes a new
  ;; section header. Sets the mode-line indicator. Returns a run handle.

;; 4. Lifecycle: finalize (replaces the close half of unwind-protect).
(a3-pub-async/finish-publish RUN &key SCOPE STATUS)
  ;; STATUS is 'ok / 'err / 'cancelled. Calls existing
  ;; a3-pub/finish-publish, runs F's citations emit-yaml tail (when
  ;; scope=deliberate AND status=ok), clears mode-line, releases the
  ;; lock, writes summary to minibuffer + *a3-publish*.

;; 5. Step log.
(a3-pub-async/log-step RUN STEP-LABEL STATUS &key DETAIL ELAPSED ERR-SNIPPET)
  ;; Appends one line to *a3-publish*. STATUS is :running / :ok /
  ;; :err / :pending / :cancelled. Updates minibuffer current-step text.
  ;; Existing multi-pdf--log-line / multi-word--log-line become thin
  ;; wrappers around this.
```

### 3.2 Run handle

```elisp
(cl-defstruct a3-pub-async-run
  id              ; symbol or string, unique per run, used in process names
  scope           ; 'deliberate or 'living
  source-label    ; "essays/example-multi" — surfaced in buffer header
  buffer          ; *a3-publish* buffer (shared across runs)
  section-start   ; point in buffer where this run's section begins
  live-processes  ; list of live process objects, for cancel
  tmp-dirs        ; list of dirs to delete on cancel
  start-time      ; (current-time)
  planned-steps   ; integer from handler — drives mode-line "N/M"
  completed-steps ; integer, ticks up on each :ok / :err
  status)         ; :running / :ok / :err / :cancelled
```

### 3.3 Lifecycle flow (deliberate path)

```
a3-publish-deliberate(file-or-id)
  → RUN = (a3-pub-async/begin-publish :scope 'deliberate :source-label …)
  → resolve file + section + handler
  → (funcall handler file RUN
       :on-done (lambda (status)
                  (a3-pub-async/finish-publish RUN :scope 'deliberate :status status)))
  → return (Emacs idle again)

  ;; Handler sentinel chain runs in background; when finished, the LAST
  ;; sentinel calls on-done which calls finish-publish. NOT under
  ;; unwind-protect of a3-publish-deliberate.
```

### 3.4 Handler contract change

Every handler currently `(handler file)` becomes:

```elisp
(handler file run &key on-done)
  ;; FILE: absolute source file path
  ;; RUN:  a3-pub-async-run struct (threaded for log-step + cancel)
  ;; ON-DONE: 1-arg callback (status); status ∈ '(ok err cancelled)
  ;;         The handler MUST call on-done exactly once.
```

Handlers expose `(handler/planned-steps)` returning the integer step count they intend to log. The lifecycle calls this during `begin-publish` to seed `RUN.planned-steps`. Rough estimates (refined during implementation):

| Handler | Planned steps |
|---|---|
| B.1 garden (per-note) | ~3 |
| B.2 library (per-medium) | ~4 |
| B.3 research (per-page) | ~3 |
| B.4 essays (per-essay, no D.2) | ~5 |
| B.4 essays (per-essay, with D.2) | ~9 (see §4.1 buffer mockup; combines base + PDF + Word backend steps) |

The D.2 PDF backend contributes svgs-fan + ox-latex + xelatex-loop + place; the Word backend contributes svgs-fan + filter+pandoc + place. Both fold into the per-essay count when `#+multi_export: t`. Exact accounting is the plan's job, not the spec's.

### 3.5 Living-publish flow

`a3-publish-living` walks the source-set (per-section, current behavior preserved), dispatches per-section handlers, and uses a barrier over the set: each per-note handler reports done; when all have reported, `finish-publish` fires once.

### 3.6 Cancel command

`C-c C-c` in `*a3-publish*`:

1. Set `RUN.status = :cancelled` first, so sentinels firing in the next few ms can short-circuit.
2. `(dolist (p RUN.live-processes) (interrupt-process p))` — SIGINT.
3. After 2s, any still-live process gets `(kill-process p)` (SIGKILL fallback).
4. Each sentinel observing `RUN.status = :cancelled` reports up as `'cancelled` (not `'err`).
5. Final continuation calls `finish-publish` with `:status 'cancelled`.
6. Accumulator discarded (no manifest write, no citations emit-yaml).
7. Tmp dirs (`RUN.tmp-dirs`) recursively deleted.
8. Lock released. Mode line shows `[a3-pub ⨯ cancelled]` for 3s, then clears.

## 4. UI surface

### 4.1 `*a3-publish*` buffer

- Mode: `a3-pub-mode` (`special-mode` derivative; read-only; `q` buries; `n`/`p` jump to section headers).
- Persistent across runs; append-only audit log.
- Section header per run (blank line above):

  ```
  ───────────────────────────────────────────────
  2026-06-06 14:32:18  publish-deliberate  essays/example-multi
  ───────────────────────────────────────────────
  ```
- Step lines (`a3-pub-async/log-step` output):

  ```
    [✓] handler            essays                            (0.0s)
    [✓] export             org → hugo md                     (0.4s)
    [✓] export             org → latex                       (1.2s)
    [·] xelatex            pass 2/4                          [running]
    [ ] biber                                                [pending]
  ```
  `[·]` running, `[ ]` pending, `[✓]` ok, `[✗]` error, `[⨯]` cancelled.
- Running steps tick elapsed every 0.5s via `run-with-timer` on the run handle; timer cancelled on transition out of `:running`.
- Errors inline stderr tail (last 10 lines), prefixed `              ` (matches existing `--log-line` indent).
- Final summary line per run:

  ```
    ── publish ✓ ok        pdf+docx → ~/Sync/.../example-multi/   (47.2s)
    ── publish ✗ err       pdf failed; docx ok                    (12.0s)
    ── publish ⨯ cancelled at xelatex pass 2/4                    ( 8.0s)
  ```

### 4.2 Window placement

First publish in a session: `display-buffer-in-side-window` with `(side . bottom) (window-height . 0.25)`. Subsequent publishes reuse the existing window. Buffer is not auto-selected.

### 4.3 Minibuffer

`(message "a3-pub: xelatex pass 2/4 (5.0s)... [C-c C-c to cancel]")` updated on step transitions and every 1s while a step is running. Cleared on `finish-publish`.

### 4.4 Mode line

Global indicator added to `mode-line-misc-info`:

- Idle: not shown.
- Running: `[a3-pub ⧗ 5/9]` — fraction = `completed-steps / planned-steps`. Spinner glyph cycles `⧗◐◑◒◓` on a 0.25s timer.
- Cancelled: `[a3-pub ⨯ cancelled]` for 3s, then clears.
- Error: `[a3-pub ✗ err]` for 3s, then clears.

## 5. Per-call-site conversion

| File:line | Today | After |
|---|---|---|
| `multi-pdf.el:57` | sequential `call-process rsvg-convert` loop | **Parallel fan**: `run-process` per SVG; `barrier N` before xelatex begins. |
| `multi-pdf.el:81` | 4 sequential `call-process` (xelatex/biber/xelatex/xelatex) | **Sequential `run-process` chain**: each `on-done` fires the next. Step label `xelatex pass N/4` updates per pass. PDF backend reports done when 4th sentinel completes. |
| `multi-pdf.el:116` | in-process `org-latex-export-to-latex` | **Stays sync**, wrapped in `a3-pub-async/log-step` with `:elapsed` timing. |
| `multi-word.el:39` | sequential `call-process rsvg-convert` loop (PNG) | **Parallel fan**. |
| `multi-word.el:56` | `call-process pandoc` | **Single `run-process`**. |
| `history.el:312` | `call-process "git log"` to capture stdout | **Single `run-process`** with stdout-buf; sentinel parses date. Per-file during walk; barrier across the walk inside the handler. |
| `assets.el:294` | `call-process "git" "mv"` (auto-remediate, errors on rc≠0) | **Single `run-process`**; sentinel signals via `on-done`. Failure falls through to `rename-file` (existing semantics). |
| `unpublish.el:323` | `shell-command "git mv …"` | **Single `run-process` with "git" + "mv" argv** — drop the shell-command + `shell-quote-argument`. Same fallback to `rename-file`. |

### 5.1 D.2 orchestrator change

The D.2 multi-export orchestrator (currently sequential pdf→docx) becomes:

```elisp
(let ((report (a3-pub-async/barrier
               2 :on-all-done
               (lambda (results)
                 ;; results: (list pdf-result word-result), each is (:status … :path …)
                 ;; rolls up to a single multi-export :status passed back up
                 (funcall on-done (rollup results))))))
  (a3madkour-pub-multi-pdf/run source-file slug bundle-dir templates-dir
                               :run run :on-done (lambda (r) (funcall report r)))
  (a3madkour-pub-multi-word/run source-file slug bundle-dir templates-dir bib-path
                                :run run :on-done (lambda (r) (funcall report r))))
```

### 5.2 Test-mode shim

`a3-pub-async/run-process` honors a dynamic var `a3-pub-async--synchronous-p` (let-bound at the `ert-deftest` level via a `with-async-sync` helper macro): when t, runs `call-process` and invokes `on-done` immediately, in-line. The existing 543-test suite keeps working without rewriting fixtures for async; new async-specific behaviour (cancel, barrier semantics under genuine concurrency, lifecycle lock) gets dedicated tests that bind `synchronous-p` to nil.

The barrier helper honors the same shim: in sync mode it still counts to N and fires `on-all-done` after the Nth call — preserves the ordering guarantee in tests.

## 6. Error handling and edge cases

### 6.1 Per-step failure (subprocess rc ≠ 0)

- Preserved per-backend semantics: a backend failure doesn't fail the pipeline. Multi-pdf failing still lets multi-word run.
- Step line: `[✗] xelatex   pass 2/4    (8.3s)` plus stderr tail.
- Backend's `done-fn` invoked with `(:status 'err :elapsed N :err-snippet "...")`.
- Orchestrator `:on-all-done` rolls up: any `'err` in the results list → run status `'err`.

### 6.2 Handler exception (elisp error during the in-process portion)

- Caught by `condition-case` in `a3-pub-async/begin-publish`'s setup wrapper.
- `finish-publish` still called (matching today's `unwind-protect` guarantee).
- `:status 'err`; error message inlined in the summary: `── publish ✗  error: <message>  (1.4s)`.
- Lock released. Mode line clears.

### 6.3 Re-entry guard

- `a3madkour-pub-async--in-flight-run` — nil or the active run handle.
- `begin-publish` checks; on conflict: `(user-error "a3-pub: a publish is already running (see *a3-publish*)")` AND `(pop-to-buffer (a3-pub-async/buffer))`.
- Cleared by `finish-publish` even on error or cancel.

### 6.4 Sentinel hygiene

- Sentinel: `(lambda (proc event) … )`. Idempotent — guards on `(memq (process-status proc) '(exit signal))`; spurious `event` strings (`"open\n"`) ignored.
- Never recursive; chain advancement always via `(funcall on-done …)`.
- Never assume the buffer is current — `(with-current-buffer (process-buffer proc) …)` or use `(a3-pub-async/log-step RUN …)` which finds the buffer from the handle.

### 6.5 stderr buffer hygiene

- One stderr buffer per process, named `*a3-pub-stderr <name>*`.
- On `:ok` sentinel: buffer killed.
- On `:err` sentinel: last 10 lines extracted for the log line; buffer kept until `finish-publish`, then killed.
- On cancel: all stderr buffers killed unconditionally.

### 6.6 Frozen-Emacs failure mode

- If a subprocess hangs (e.g., xelatex waiting on missing font despite `-interaction=nonstopmode`), the mode-line shows `[a3-pub ⧗ N/M]` indefinitely. User `C-c C-c` cancels. The SIGINT-then-SIGKILL (2s) fallback ensures we never deadlock on the lock.

### 6.7 ox-latex sync coexistence

`multi-pdf.el:112` does `(with-current-buffer (find-file-noselect source-file) ...)` for `org-latex-export-to-latex`. We keep it. find-file-noselect is fast; the sentinel chain only takes over after the export returns.

## 7. Testing strategy

### 7.1 Existing tests stay green

Every existing ert test that drives a handler runs with `a3-pub-async--synchronous-p` bound to t via a `with-async-sync` helper macro (or `ert-deftest`-level advice). The shim runs `call-process` and invokes `on-done` inline. Existing assertions on file outputs, manifest, citations YAML, integration fixtures don't change.

### 7.2 New ert tests (~30)

| Area | Test |
|---|---|
| `run-process` | spawns process; sentinel fires with rc=0 + empty stderr-tail on success |
| `run-process` | non-zero rc; stderr tail captures last 10 lines |
| `run-process` | `interrupt-process` mid-run → sentinel fires with cancel status |
| `run-process` | nonexistent CMD → graceful error, no sentinel hang |
| `barrier` | N=3, fires `on-all-done` once, results in registration order |
| `barrier` | N=0 fires immediately |
| `barrier` | one reporter signals `:err` → roll-up status is `:err` |
| Lock | second `begin-publish` while in-flight → `user-error` |
| Lock | released on `:ok` finish |
| Lock | released on `:err` finish (condition-case path) |
| Lock | released on `:cancelled` finish |
| Lock | released on handler exception (unwind path) |
| Buffer | section header inserted on begin-publish |
| Buffer | step lines append in order, even when sentinels interleave |
| Buffer | stderr tail formatted under `[✗]` line |
| Buffer | summary line on finish (`:ok` / `:err` / `:cancelled` distinct) |
| Mode line | indicator appears on begin, clears on finish |
| Mode line | indicator clears on cancel-then-3s timeout |
| Cancel | `interrupt-process` called on every live process |
| Cancel | tmp dirs deleted |
| Cancel | accumulator discarded (manifest unchanged) |
| Handler contract | every handler accepts `(file run &key on-done)` and calls on-done exactly once |
| Handler contract | handler exception still calls on-done with `:status 'err` |
| Shim | `synchronous-p=t` runs sentinels inline; existing assertions pass |
| Shim | `synchronous-p=t` still honors barrier ordering |
| Shim | `synchronous-p=nil` (default) uses make-process; sentinels verify via timing |

### 7.3 Integration tests (Python, under `tests/integration/`)

- **`test_async_publish_deliberate_essay.py`** — `a3-pub.sh --publish-deliberate <fixture>` exercises the live async path. Asserts bundle dir, manifest YAML, citations YAML, exit code 0.
- **`test_async_publish_cancel.py`** — spawn publish in subprocess, send SIGTERM mid-xelatex. Asserts no manifest change, no orphan tmp dirs, nonzero exit, stderr mentions "cancelled". Requires `a3-pub.sh` to translate SIGTERM → `(a3-pub-async/cancel-current-run)`.

### 7.4 Real-corpus spot-check (manual, post-implementation)

`M-x a3-publish-deliberate` on `~/org/essays/example-multi.org`. Verify:

- Emacs stays interactive throughout (type in scratch, switch buffers).
- `*a3-publish*` opens; step lines tick; elapsed counter ticks.
- Mode-line spinner ticks.
- `C-c C-c` mid-xelatex cancels cleanly; no orphan tmp dirs in `/tmp/`.
- Second `M-x a3-publish-deliberate` while one runs → `user-error` + buffer pops.
- Re-run after cancel → fresh run, manifest unchanged from before cancel.

## 8. Out of scope

- ox-latex export running in a forked Emacs (deferred; instrument first, decide later).
- D.2 backend command discovery — keep existing defcustoms.
- Multi-export error reporting format — keep existing `--log-line` shape.
- Network calls (BBT fetch, library cover fetch) — separate audit.
- A publish queue (deferred per re-entrancy decision).
- Per-handler progress percentage beyond integer step fractions.

## 9. Open questions

- **Exact step labels for B.1/B.2/B.3 handlers** — refined during implementation; tracked in the plan, not the spec.
- **`a3-pub.sh` signal handling for SIGTERM-as-cancel** — design TBD during plan; non-interactive path needs a thin shim that maps signal → `(a3-pub-async/cancel-current-run)` before the elisp finishes. May fall out naturally from the cancel command — verify in plan.

## 10. References

- Stub: `2026-06-06-async-publish-pipeline-stub.md`
- D.2 figref bundled fix (last touched these files): `2026-06-05-d2-figure-ref-bundled-fix-design.md`
- B.0 publisher infra (lifecycle today): `2026-05-22-b0-publisher-infra-design.md`
- B.4 essays handler (deliberate scope): `2026-05-30-b4-essays-handler-design.md`
- Stub of D.2 multi-export (orchestrator): `2026-05-13-multi-target-export-design.md`
