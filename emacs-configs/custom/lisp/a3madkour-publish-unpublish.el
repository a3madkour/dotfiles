;;; a3madkour-publish-unpublish.el --- Unpublish flow + orchestrator (A.1.d) -*- lexical-binding: t; -*-

;;; Commentary:
;; Phase 3 sub-project A.1.d.  Implements the three-step unpublish
;; orchestrator + --check-orphans dry-run preview, closing parent spec
;; §12 A.1 item #7.
;;
;;   Step A — unpublish sweep: diff new live-set vs manifest, delete
;;            stale page bundles, mutate manifest entries.
;;   Step B — slug-shift sync: rename ~/org/notes/assets/page/<old>/ →
;;            <new>/ and bulk-rewrite source .org link references.
;;   Step C — re-link-check: WARN for live-note outgoing links resolving
;;            into the removed-this-publish set.
;;
;; Public entry points:
;;   `a3madkour-pub/finish-publish'    — orchestrator (commits to FS + manifest)
;;   `a3madkour-pub/check-orphans'     — thin alias for dry-run preview
;;   `a3madkour-pub/diff-published-set'      — pure diff helper
;;   `a3madkour-pub/walk-published-source-set' — standalone-mode driver
;;
;; See `docs/superpowers/specs/2026-05-24-phase-3-a1-d-unpublish-design.md'.
;;
;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-async)

(defcustom a3madkour-pub-site-content-dir nil
  "Root of the Hugo `content/' tree for the site repo, or nil to derive.

When nil (the default), `a3madkour-pub--site-content-dir-effective' derives
the path from `a3madkour-pub/site-data-dir' (which is set at publish-start
via the a3-pub.sh wrapper or interactive config) by replacing `data/' with
`content/'. This is the right value 99% of the time and avoids hardcoding a
machine-specific path here.

Set explicitly only when the content tree lives somewhere other than the
sibling of the data dir. `a3madkour-pub--unpublish-delete-bundle' resolves
`<content-root>/<section>/<slug>/' against the effective value when an
orchestrator step needs to remove a bundle.

Override per-call by passing a third arg to the helper, or `let'-bind this
defcustom inside a fixture."
  :type '(choice (const :tag "Derive from site-data-dir" nil) directory)
  :group 'a3madkour-pub)

(defcustom a3madkour-pub-unpublish-removal-floor-count 5
  "Minimum live-set size before the P1.1c mass-removal circuit-breaker engages.

The breaker refuses a sweep only when at least this many notes are currently
live/draft in the manifest.  Below the floor, removals proceed unconditionally
so legitimately small sites (e.g. unpublishing the only note) are never
blocked.  Set to a very large number to effectively disable the floor gate."
  :type 'integer
  :group 'a3madkour-pub)

(defcustom a3madkour-pub-unpublish-max-removal-ratio 0.5
  "Fraction of the live set that may be removed in one publish run.

When the manifest holds at least `a3madkour-pub-unpublish-removal-floor-count'
live/draft notes AND a single run would classify more than this fraction of
them as `:removed', `a3madkour-pub/finish-publish' REFUSES the destructive
sweep — no bundles are deleted, no manifest entries advance to `removed' — and
surfaces a loud WARN.  This is the backstop against a misconfigured
`org-notes-dir' or an empty source walk wiping the whole site in one run.

Set to nil (or >= 1.0) to disable the ratio breaker."
  :type '(choice (const :tag "Disabled" nil) number)
  :group 'a3madkour-pub)

(defun a3madkour-pub--site-content-dir-effective ()
  "Return the effective Hugo `content/' root.
Honors `a3madkour-pub-site-content-dir' when set; otherwise derives from
`a3madkour-pub/site-data-dir' (sibling-of-data convention). Returns nil if
neither is set (caller's burden to error)."
  (or a3madkour-pub-site-content-dir
      (and a3madkour-pub/site-data-dir
           (file-name-as-directory
            (expand-file-name "content"
                              (file-name-directory
                               (directory-file-name
                                a3madkour-pub/site-data-dir)))))))

(defun a3madkour-pub/diff-published-set (new-set)
  "Diff NEW-SET against the manifest's currently-live+draft entries.

NEW-SET is a hash table id → (url . state) where state is `live' or `draft'.
The old set is computed by reading the manifest via
`a3madkour-pub-history/read-manifest-snapshot-or-disk' (which prefers
`a3madkour-pub--manifest-snapshot' when set, i.e. during a B.0+ publish
run) and filtering to entries with `state ∈ {live, draft}' (manifest
entries already in `removed' are excluded from the old set, so
re-removing them is a no-op).

Returns a plist:
  :added         (id ...)
  :removed       (id ...)
  :stayed        (id ...)
  :slug-shifted  ((id old-url new-url) ...)

`:slug-shifted' is a strict subset of `:stayed' — an id whose URL changed
appears in BOTH (in :stayed because it's still published; in :slug-shifted
because the URL also changed).  Step B (in `finish-publish') consumes
:slug-shifted to drive asset-dir + source-link migration."
  (let* ((manifest (a3madkour-pub-history/read-manifest-snapshot-or-disk))
         (notes (alist-get 'notes manifest))
         (old-set (make-hash-table :test 'equal))
         added removed stayed slug-shifted)
    ;; Build old-set from manifest live+draft entries.
    (cl-loop for i from 0 below (length notes)
             for entry = (aref notes i)
             for state-str = (alist-get 'state entry)
             when (member state-str '("live" "draft"))
             do (puthash (alist-get 'id entry)
                         (cons (alist-get 'current_url entry)
                               (intern state-str))
                         old-set))
    ;; Walk new-set: classify each id.
    (maphash
     (lambda (id new-entry)
       (let* ((new-url (car new-entry))
              (old-entry (gethash id old-set)))
         (cond
          ((null old-entry)
           (push id added))
          (t
           (push id stayed)
           (let ((old-url (car old-entry)))
             (unless (equal old-url new-url)
               (push (list id old-url new-url) slug-shifted)))))))
     new-set)
    ;; Walk old-set: anything not in new-set is :removed.
    (maphash
     (lambda (id _old-entry)
       (unless (gethash id new-set)
         (push id removed)))
     old-set)
    (list :added (nreverse added)
          :removed (nreverse removed)
          :stayed (nreverse stayed)
          :slug-shifted (nreverse slug-shifted))))

(defun a3madkour-pub/walk-published-source-set ()
  "Walk `a3madkour-pub/org-notes-dir' recursively, return hash table of the
new published set.

Returns id → (url . state) where state is `live' or `draft'.

Standalone-mode driver for `a3madkour-pub/finish-publish' — used when the
publish-run-accumulator is empty (no `record-publish' calls happened this
run, e.g. before B ships).  Each .org file is parsed via
`a3madkour-pub--parse-file' (which already implements the HUGO_PUBLISH gate
+ HUGO_DRAFT detection + slug derivation); files without `:state' (i.e.
unpublished or missing :ID:) are skipped.

This walk takes a fresh per-call snapshot of the source tree; it does NOT
hit the metadata cache populated by `note-metadata' (which is per-file
keyed, not per-walk).  Repeated calls are independent."
  (let ((set (make-hash-table :test 'equal)))
    (dolist (file (directory-files-recursively a3madkour-pub/org-notes-dir
                                                "\\.org\\'"))
      (let* ((parsed (a3madkour-pub--parse-file file))
             (state (plist-get parsed :state))
             (id (plist-get parsed :id))
             (section (plist-get parsed :section))
             (slug (plist-get parsed :slug)))
        (cond
         ((and state id section slug)
          (puthash id
                   (cons (format "/%s/%s/" section slug) state)
                   set))
         ;; P1.1e: a published note (state+id+section) with a nil/empty slug
         ;; can't form a URL, so it's skipped — but WARN rather than omit
         ;; silently.  Silent omission would classify a genuinely-published
         ;; note as `:removed' in the diff and risk deleting its bundle.
         ((and state id section)
          (message "[a3-pub] walk: note %s (%s) is published but has no slug (empty title / no #+HUGO_SLUG:) — skipped from the live set; check the source"
                   id file)))))
    set))

(cl-defun a3madkour-pub--unpublish-delete-bundle (section slug &optional content-root)
  "Recursively delete `<CONTENT-ROOT>/<SECTION>/<SLUG>/'.

CONTENT-ROOT defaults to `a3madkour-pub-site-content-dir'.

Return values:
  t        — bundle existed and was deleted.
  nil      — bundle was already absent (benign; logged via `message').
  'failed  — bundle existed but `delete-directory' signalled an error.
             The error is caught and reported via `message' with a `[a3-pub]
             delete-bundle FAILED' prefix so the publish log surfaces it.

`finish-publish' callers MUST inspect this return: on `'failed', do NOT
mark the manifest entry `removed' — leave it at its prior state (`live' /
`draft') so the diff on the next publish run re-detects the id under
`:removed' and retries the delete.  Without that gate, a single failed
delete (wrong content-root, permission error, transient FS issue) would
silently orphan the on-disk bundle forever.  (Bug 1.1 in
`docs/superpowers/specs/2026-06-07-polish-and-bugfix-roadmap.md'.)"
  (let ((root (or content-root (a3madkour-pub--site-content-dir-effective))))
    ;; P1.1d: never resolve the bundle path against `default-directory'.  A nil
    ;; root means neither the content-dir nor the site-data-dir is configured;
    ;; expanding "section/slug" against nil would target `./section/slug/'
    ;; relative to Emacs' cwd and recursively delete an unrelated directory.
    (unless root
      (error "a3-pub delete-bundle: no content root configured (set a3madkour-pub-site-content-dir or a3madkour-pub/site-data-dir); refusing to delete %s/%s"
             section slug))
    ;; P1.1d: guard against empty section/slug producing a path that resolves
    ;; to the content root itself.
    (when (or (null section) (equal section "") (null slug) (equal slug ""))
      (message "[a3-pub] delete-bundle: empty section/slug (%S / %S) — skipping" section slug)
      (cl-return-from a3madkour-pub--unpublish-delete-bundle 'failed))
    (let ((bundle (file-name-as-directory
                   (expand-file-name (format "%s/%s" section slug) root))))
      (cond
       ((not (file-directory-p bundle))
        (message "[a3-pub] delete-bundle: %s already absent (stale manifest?)" bundle)
        nil)
       ;; P1.1d: verify the target actually looks like a Hugo page bundle
       ;; before the recursive delete — an `index.md' or `_index.md' must be
       ;; present.  Refuse (return 'failed, like the caller's no-advance path)
       ;; rather than nuke an arbitrary directory sitting at the derived path.
       ((not (or (file-exists-p (expand-file-name "index.md" bundle))
                 (file-exists-p (expand-file-name "_index.md" bundle))))
        (message "[a3-pub] delete-bundle: %s is not a content bundle (no index.md/_index.md) — refusing to delete"
                 bundle)
        'failed)
       (t
        (condition-case err
            (progn (delete-directory bundle t) t)
          (error
           (message "[a3-pub] delete-bundle FAILED: %s (%s)"
                    bundle (error-message-string err))
           'failed)))))))

(defun a3madkour-pub--unpublish-url-to-section-slug (url)
  "Parse URL of shape `/<section>/<slug>/' (or nested) into a cons cell.

Returns (SECTION . SLUG) or nil if URL isn't well-formed.  Mirrors
`a3madkour-pub-history--section-of-url' for the section part; the slug
is the LAST path segment.  Nested sections like `/research/questions/q/'
yield (\"research/questions\" . \"q\")."
  (when (and (stringp url) (string-prefix-p "/" url))
    (let* ((trimmed (replace-regexp-in-string "\\`/+\\|/+\\'" "" url))
           (parts (split-string trimmed "/" t)))
      (when (>= (length parts) 2)
        (cons (mapconcat #'identity (butlast parts) "/")
              (car (last parts)))))))

(cl-defun a3madkour-pub/finish-publish (&key dry-run (scope 'living) (reap t))
  "Orchestrate the unpublish flow.  Returns a plist.

When DRY-RUN is non-nil: no FS writes, no manifest mutation.

When REAP is nil (P1.1a status gate): the destructive Step A sweep and the
Step B slug-shift FS mutations are skipped, exactly as under DRY-RUN, but the
diff is still computed and returned for logging.  Callers pass `:reap nil'
when the publish run did NOT complete cleanly (status err / cancelled) — a
partial or cancelled run leaves the accumulator incomplete, so trusting it as
the authoritative new-live-set would classify still-valid notes as `:removed'
and delete their bundles.  Gating the sweep on run success is the primary
safety rail against that data-loss path.

SCOPE is `'living' (default) or `'deliberate'.  `'living' runs the
full Step A unpublish-sweep + Step B slug-shift + Step C re-link-check
against the diff of new-set vs manifest.  `'deliberate' skips Step A
and Step C entirely (the accumulator carries only the touched files,
so `\"missing from accumulator\"' has no meaning) and narrows Step B
to the single accumulator entry's slug-shift if its URL differs from
the manifest.

Sub-steps (in fixed order):
  Step A — unpublish sweep: diff new live-set vs manifest live+draft;
           for each :removed, delete `content/<section>/<slug>/' bundle +
           call `record-publish' with state `removed' to mutate manifest.
           SKIPPED under `'deliberate'.
  Step B — slug-shift sync: rename `<asset-root>/page/<old-slug>/' →
           `<new-slug>/' and bulk-rewrite source .org link references.
           Under `'deliberate', narrowed to the single accumulator entry.
  Step C — re-link-check: scan live notes' outgoing [[id:...]] links;
           WARN for any link resolving into removed-this-publish-set.
           SKIPPED under `'deliberate'.

New-set is read from `a3madkour-pub--publish-run-accumulator' (B-coupled
mode); if empty, falls back to `walk-published-source-set' (standalone
mode — used today before B ships).

Returns:
  (:added          (id ...)
   :stayed         (id ...)
   :removed        (id ...)
   :slug-shifted   ((old-slug . new-slug) ...)
   :orphan-warnings (\"WARN: ...\" ...))"
  (let* ((new-set (if (zerop (hash-table-count a3madkour-pub--publish-run-accumulator))
                      (a3madkour-pub/walk-published-source-set)
                    ;; P2.12: the accumulator carries EVERY record-publish call
                    ;; this run, including `(record-publish id nil 'removed)'
                    ;; from a deliberate unpublish.  A `removed'/nil-url entry
                    ;; is NOT a live member of the new-set — including it would
                    ;; misclassify a just-removed id as `:stayed' (or a bogus
                    ;; `:slug-shifted' to nil).  Filter to live/draft, url-bearing.
                    (let ((filtered (make-hash-table :test 'equal)))
                      (maphash
                       (lambda (id entry)
                         (when (and (car entry)
                                    (memq (cdr entry) '(live draft)))
                           (puthash id entry filtered)))
                       a3madkour-pub--publish-run-accumulator)
                      filtered)))
         (diff (a3madkour-pub/diff-published-set new-set))
         (removed (plist-get diff :removed))
         (shifts (plist-get diff :slug-shifted))
         (manifest (a3madkour-pub-history/read-manifest-snapshot-or-disk))
         (notes (alist-get 'notes manifest))
         (removed-set (make-hash-table :test 'equal))
         ;; P1.1c mass-removal circuit-breaker.  Refuse a real (non-dry-run,
         ;; reaping) sweep that would delete more than the configured fraction
         ;; of a non-trivial live set — the signature of a misconfigured
         ;; `org-notes-dir' or an empty/partial source walk about to wipe the
         ;; site.  Below the floor count, small legitimate removals proceed.
         (old-live-count (cl-count-if
                          (lambda (n) (member (alist-get 'state n) '("live" "draft")))
                          notes))
         (sweep-refused
          (and (not (eq scope 'deliberate))
               reap (not dry-run)
               a3madkour-pub-unpublish-max-removal-ratio
               (>= old-live-count a3madkour-pub-unpublish-removal-floor-count)
               (> (/ (float (length removed)) (max 1 old-live-count))
                  a3madkour-pub-unpublish-max-removal-ratio)))
         slug-shifted-result orphan-warnings)
    (when sweep-refused
      (push (format (concat "WARN: refusing orphan sweep — %d of %d live notes "
                            "would be removed in one run (> %d%% threshold); NO "
                            "bundles deleted. Verify org-notes-dir / config, or "
                            "lower a3madkour-pub-unpublish-max-removal-ratio if "
                            "the mass removal is intentional.")
                    (length removed) old-live-count
                    (round (* 100 a3madkour-pub-unpublish-max-removal-ratio)))
            orphan-warnings))
    ;; Step A: sweep.  Skipped under 'deliberate, or when the breaker refused.
    ;;
    ;; Bug 1.1 (polish-and-bugfix-roadmap.md): only advance the manifest to
    ;; `removed' when `--unpublish-delete-bundle' actually succeeded (or the
    ;; bundle was already absent — also a no-op).  When the delete signalled
    ;; an error and returned `'failed', leave the manifest entry at its
    ;; previous state (`live' / `draft') so the NEXT publish run's diff
    ;; re-includes the id under `:removed' and retries the delete.  This is
    ;; the self-healing contract — without it, a single failed delete (wrong
    ;; content-root, permission error, transient FS issue) would silently
    ;; orphan the on-disk bundle forever, because the diff would never
    ;; surface the id again once its manifest entry said `removed'.
    (unless (or (eq scope 'deliberate) sweep-refused)
      (dolist (id removed)
        (puthash id t removed-set)
        (let* ((idx (a3madkour-pub-history--find-note-by-id notes id))
               (entry (when idx (aref notes idx)))
               (url (when entry (alist-get 'current_url entry)))
               (parts (when url (a3madkour-pub--unpublish-url-to-section-slug url))))
          (when (and parts (not dry-run) reap)
            (let ((delete-result
                   (a3madkour-pub--unpublish-delete-bundle (car parts) (cdr parts))))
              (unless (eq delete-result 'failed)
                (a3madkour-pub-history/record-publish id nil 'removed)))))))
    ;; Step B: slug-shift sync.  Under 'deliberate, narrow to touched ids.
    ;;
    ;; Bug 1.10 (polish-and-bugfix-roadmap.md): the orphan-bundle delete
    ;; below was previously fire-and-forget — `--unpublish-delete-bundle's'
    ;; documented `'failed' return was discarded.  Unlike Step A (bug 1.1),
    ;; we can't self-heal across runs here: by the time Step B runs, the
    ;; per-section handler has already written the new bundle and called
    ;; `record-publish' for the new URL, so the next run's diff sees
    ;; `:stayed' (no URL change relative to the just-written manifest) and
    ;; never re-attempts the old-slug delete.  Net result was a stray
    ;; `content/<section>/<old-slug>/' bundle Hugo would build as a
    ;; duplicate page, invisible to the manifest.  Minimum-viable fix:
    ;; capture the `'failed' return, append an author-visible WARN to
    ;; `:orphan-warnings' (consumed by the publish-UI buffer + the
    ;; check-orphans printer) so the orphan surfaces for manual cleanup.
    (let ((deliberate-ids
           (when (eq scope 'deliberate)
             (let ((ids nil))
               (maphash (lambda (k _v) (push k ids))
                        a3madkour-pub--publish-run-accumulator)
               ids))))
      (dolist (shift shifts)
        (when (or (not (eq scope 'deliberate))
                  (member (car shift) deliberate-ids))
          (let* ((old-url (nth 1 shift))
                 (new-url (nth 2 shift))
                 (old-parts (a3madkour-pub--unpublish-url-to-section-slug old-url))
                 (new-parts (a3madkour-pub--unpublish-url-to-section-slug new-url)))
            (when (and old-parts new-parts)
              (let ((old-slug (cdr old-parts))
                    (new-slug (cdr new-parts)))
                (unless (or dry-run (not reap))
                  (a3madkour-pub--unpublish-rename-asset-dir old-slug new-slug)
                  (a3madkour-pub--unpublish-bulk-rewrite-source-links old-slug new-slug)
                  ;; Delete the orphan Hugo content bundle at the old slug.
                  ;; The per-section handler already wrote a new bundle at the
                  ;; new slug; without this call the old bundle stays as dead
                  ;; content.  Runs regardless of asset-rename outcome — the
                  ;; bundle and the asset dir are independent artifacts.
                  (let ((delete-result
                         (a3madkour-pub--unpublish-delete-bundle
                          (car old-parts) (cdr old-parts))))
                    (when (eq delete-result 'failed)
                      (push (format
                             "WARN: slug-shift %s → %s left orphan bundle at %s; manual cleanup recommended"
                             old-slug new-slug old-url)
                            orphan-warnings))))
                (push (cons old-slug new-slug) slug-shifted-result)))))))
    ;; Step C: re-link-check (read-only; runs in dry-run too).  Skipped under 'deliberate.
    ;; Accumulate onto `orphan-warnings' via push (mirrors Step B's bug-1.10
    ;; contributions); the final return below nreverses once for insertion
    ;; order.
    (when (and (not (eq scope 'deliberate))
               (> (hash-table-count removed-set) 0))
      (dolist (w (a3madkour-pub--unpublish-recheck-live-note-links removed-set))
        (push w orphan-warnings)))
    ;; B.0: clear manifest snapshot now that the publish run is over.
    ;; Next publish run's begin-publish will populate it fresh.
    (setq a3madkour-pub--manifest-snapshot nil)
    (list :added (plist-get diff :added)
          :stayed (plist-get diff :stayed)
          :removed (if (or (eq scope 'deliberate) sweep-refused) nil removed)
          :slug-shifted (nreverse slug-shifted-result)
          :orphan-warnings (nreverse orphan-warnings))))

(defun a3madkour-pub--unpublish-rename-asset-dir (old-slug new-slug &optional canonical-root)
  "Rename `<CANONICAL-ROOT>/page/<OLD-SLUG>/' → `<NEW-SLUG>/'.

CANONICAL-ROOT defaults to `a3madkour-pub-canonical-asset-root'.

Returns a symbol indicating what happened:
  :renamed-git           — git-tracked; performed `git mv'.
  :renamed-mv            — untracked; performed `rename-file'.
  :skipped-no-source     — source dir doesn't exist (note had no assets).
  :skipped-target-exists — target dir already present (caller WARNs).

If `git mv' fails (git not installed, not a git repo), falls through to
`rename-file' and returns `:renamed-mv'."
  (let* ((root (or canonical-root a3madkour-pub-canonical-asset-root))
         (old-dir (file-name-as-directory
                   (expand-file-name (format "page/%s" old-slug) root)))
         (new-dir (file-name-as-directory
                   (expand-file-name (format "page/%s" new-slug) root))))
    (cond
     ((not (file-directory-p old-dir))
      :skipped-no-source)
     ((file-directory-p new-dir)
      (message "[a3-pub] rename-asset-dir: target exists: %s — skipping" new-dir)
      :skipped-target-exists)
     ((eq (vc-backend old-dir) 'Git)
      (let ((default-directory root)
            got-rc)
        (with-a3-pub-async-sync
         (a3-pub-async/run-process
          "git" (list "mv"
                      (directory-file-name old-dir)
                      (directory-file-name new-dir))
          :name "unpublish-git-mv"
          :on-done (lambda (rc _tail) (setq got-rc rc))))
        (if (zerop got-rc)
            :renamed-git
          ;; Fallback to mv on git failure.
          (rename-file (directory-file-name old-dir) (directory-file-name new-dir))
          :renamed-mv)))
     (t
      (rename-file (directory-file-name old-dir) (directory-file-name new-dir))
      :renamed-mv))))

(defun a3madkour-pub--unpublish-bulk-rewrite-source-links (old-slug new-slug &optional org-notes-dir)
  "Walk ORG-NOTES-DIR for .org files; substitute `page/<OLD-SLUG>/' →
`page/<NEW-SLUG>/' across three link forms:

  ./assets/page/<old>/...           → ./assets/page/<new>/...
  ~/org/notes/assets/page/<old>/... → ~/org/notes/assets/page/<new>/...
  <$HOME>/org/notes/assets/page/<old>/... → <$HOME>/org/notes/assets/page/<new>/...

ORG-NOTES-DIR defaults to `a3madkour-pub/org-notes-dir'.

Returns a plist:
  :modified  ((file . substitution-count) ...)
  :warnings  (\"WARN: failed to write back FILE: REASON\" ...)

Idempotent: re-runs after a successful pass produce zero modifications
(the substitution regex doesn't match the new slug)."
  (let* ((dir (or org-notes-dir a3madkour-pub/org-notes-dir))
         (home (expand-file-name "~/"))
         (patterns (list
                    (cons (format "\\./assets/page/%s/" (regexp-quote old-slug))
                          (format "./assets/page/%s/" new-slug))
                    (cons (format "~/org/notes/assets/page/%s/" (regexp-quote old-slug))
                          (format "~/org/notes/assets/page/%s/" new-slug))
                    (cons (format "%sorg/notes/assets/page/%s/"
                                  (regexp-quote home) (regexp-quote old-slug))
                          (format "%sorg/notes/assets/page/%s/" home new-slug))))
         modified warnings)
    (dolist (file (directory-files-recursively dir "\\.org\\'"))
      (let* ((orig (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string)))
             (new orig)
             (count 0))
        (dolist (p patterns)
          (while (string-match (car p) new)
            (setq new (replace-match (cdr p) t t new))
            (setq count (1+ count))))
        (when (> count 0)
          (condition-case err
              (progn
                (with-temp-buffer
                  (insert new)
                  (write-region (point-min) (point-max) file nil 'silent))
                (push (cons file count) modified))
            (error
             (push (format "WARN: failed to write back %s: %s"
                           file (error-message-string err))
                   warnings))))))
    (list :modified (nreverse modified)
          :warnings (nreverse warnings))))

(defun a3madkour-pub--unpublish-recheck-live-note-links (removed-this-publish-set)
  "For each live manifest entry, scan outgoing [[id:...]] links.
Emit WARN for each link whose target id is in REMOVED-THIS-PUBLISH-SET.

REMOVED-THIS-PUBLISH-SET is a hash table id → t (or any truthy value).

Returns a list of WARN strings.  Format:
  \"WARN: live note <id> (<url>) outgoing link to <removed-id> (was <old-url>) — republish recommended\"

Source files are located via `org-roam-id-find' — which returns `(file . pos)';
we unwrap via `car' (per memory `reference_org_roam_id_find_returns_cons').
Source files that don't exist or can't be read produce their own WARN."
  (let* ((manifest (a3madkour-pub-history/read-manifest))
         (notes (alist-get 'notes manifest))
         warnings)
    (cl-loop for i from 0 below (length notes)
             for entry = (aref notes i)
             when (and (equal (alist-get 'state entry) "live")
                       ;; Skip sources that are themselves being removed this
                       ;; publish — no value checking their outgoing links
                       ;; (relevant in dry-run, where manifest still shows
                       ;; them as live).
                       (not (gethash (alist-get 'id entry)
                                     removed-this-publish-set)))
             do
             (let* ((src-id (alist-get 'id entry))
                    (src-url (alist-get 'current_url entry))
                    (found (org-roam-id-find src-id))
                    (src-file (when (consp found) (car found))))
               (cond
                ((or (null src-file) (not (file-readable-p src-file)))
                 (push (format "WARN: live note %s (%s) source file unreadable"
                               src-id src-url)
                       warnings))
                (t
                 (let ((content (with-temp-buffer
                                  (insert-file-contents src-file)
                                  (buffer-string)))
                       (link-re "\\[\\[id:\\([^]]+\\)\\]"))
                   (with-temp-buffer
                     (insert content)
                     (goto-char (point-min))
                     (while (re-search-forward link-re nil t)
                       (let ((target-id (match-string 1)))
                         (when (gethash target-id removed-this-publish-set)
                           (let* ((tgt-idx (a3madkour-pub-history--find-note-by-id
                                            notes target-id))
                                  (tgt-entry (when tgt-idx (aref notes tgt-idx)))
                                  (tgt-hist (when tgt-entry
                                              (alist-get 'history tgt-entry)))
                                  (tgt-old-url
                                   (when (and tgt-hist (> (length tgt-hist) 0))
                                     (alist-get 'url (aref tgt-hist
                                                           (1- (length tgt-hist)))))))
                             (push (format
                                    "WARN: live note %s (%s) outgoing link to %s (was %s) — republish recommended"
                                    src-id src-url target-id (or tgt-old-url "?"))
                                   warnings)))))))))))
    (nreverse warnings)))

(defun a3madkour-pub/check-orphans ()
  "Dry-run preview of `a3madkour-pub/finish-publish'.

Thin alias for `(a3madkour-pub/finish-publish :dry-run t)'.  Exists
because parent spec §10 named it explicitly.

No FS or manifest mutation.  Returns the same plist shape as
`finish-publish' (with the same diagnostic content; only the side
effects differ between the two calls)."
  (a3madkour-pub/finish-publish :dry-run t))

(provide 'a3madkour-publish-unpublish)

;;; a3madkour-publish-unpublish.el ends here
