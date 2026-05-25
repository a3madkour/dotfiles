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

(defcustom a3madkour-pub-site-content-dir
  (expand-file-name "Stuff/a3madkour/Sync/Workspace/a3madkour.github.io/content/"
                    "~/")
  "Root of the Hugo `content/' tree for the site repo.
`a3madkour-pub--unpublish-delete-bundle' resolves
`<content-root>/<section>/<slug>/' against this when an orchestrator
step needs to remove a bundle.

Override per-call by passing a third arg to the helper, or `let'-bind
this defcustom inside a fixture."
  :type 'directory
  :group 'a3madkour-publish)

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
        (when (and state id section slug)
          (puthash id
                   (cons (format "/%s/%s/" section slug) state)
                   set))))
    set))

(defun a3madkour-pub--unpublish-delete-bundle (section slug &optional content-root)
  "Recursively delete `<CONTENT-ROOT>/<SECTION>/<SLUG>/'.

CONTENT-ROOT defaults to `a3madkour-pub-site-content-dir'.  If the bundle
dir doesn't exist, logs via `message' and returns nil (not an error —
stale-manifest case is benign).  Other delete errors (permissions, file
lock) propagate to the caller.

Returns t on successful delete, nil if dir was absent."
  (let* ((root (or content-root a3madkour-pub-site-content-dir))
         (bundle (file-name-as-directory
                  (expand-file-name (format "%s/%s" section slug) root))))
    (cond
     ((file-directory-p bundle)
      (delete-directory bundle t)
      t)
     (t
      (message "[a3-pub] delete-bundle: %s already absent (stale manifest?)" bundle)
      nil))))

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

(cl-defun a3madkour-pub/finish-publish (&key dry-run)
  "Orchestrate the unpublish flow.  Returns a plist.

When DRY-RUN is non-nil: no FS writes, no manifest mutation.  Useful for
`--check-orphans' preview.  Step C still runs in dry-run (it's read-only).

Sub-steps (in fixed order):
  Step A — unpublish sweep: diff new live-set vs manifest live+draft;
           for each :removed, delete `content/<section>/<slug>/' bundle +
           call `record-publish' with state `removed' to mutate manifest.
  Step B — slug-shift sync: rename `<asset-root>/page/<old-slug>/' →
           `<new-slug>/' and bulk-rewrite source .org link references.
  Step C — re-link-check: scan live notes' outgoing [[id:...]] links;
           WARN for any link resolving into removed-this-publish-set.

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
                    (copy-hash-table a3madkour-pub--publish-run-accumulator)))
         (diff (a3madkour-pub/diff-published-set new-set))
         (removed (plist-get diff :removed))
         (shifts (plist-get diff :slug-shifted))
         (manifest (a3madkour-pub-history/read-manifest))
         (notes (alist-get 'notes manifest))
         (removed-set (make-hash-table :test 'equal))
         slug-shifted-result orphan-warnings)
    ;; Step A: sweep.
    (dolist (id removed)
      (puthash id t removed-set)
      (let* ((idx (a3madkour-pub-history--find-note-by-id notes id))
             (entry (when idx (aref notes idx)))
             (url (when entry (alist-get 'current_url entry)))
             (parts (when url (a3madkour-pub--unpublish-url-to-section-slug url))))
        (when (and parts (not dry-run))
          (a3madkour-pub--unpublish-delete-bundle (car parts) (cdr parts))
          (a3madkour-pub-history/record-publish id nil 'removed))))
    ;; Step B: slug-shift sync.
    (dolist (shift shifts)
      (let* ((old-url (nth 1 shift))
             (new-url (nth 2 shift))
             (old-parts (a3madkour-pub--unpublish-url-to-section-slug old-url))
             (new-parts (a3madkour-pub--unpublish-url-to-section-slug new-url)))
        (when (and old-parts new-parts)
          (let ((old-slug (cdr old-parts))
                (new-slug (cdr new-parts)))
            (unless dry-run
              (a3madkour-pub--unpublish-rename-asset-dir old-slug new-slug)
              (a3madkour-pub--unpublish-bulk-rewrite-source-links old-slug new-slug))
            (push (cons old-slug new-slug) slug-shifted-result)))))
    ;; Step C: re-link-check (read-only; runs in dry-run too).
    (when (> (hash-table-count removed-set) 0)
      (setq orphan-warnings
            (a3madkour-pub--unpublish-recheck-live-note-links removed-set)))
    ;; B.0: clear manifest snapshot now that the publish run is over.
    ;; Next publish run's begin-publish will populate it fresh.
    (setq a3madkour-pub--manifest-snapshot nil)
    (list :added (plist-get diff :added)
          :stayed (plist-get diff :stayed)
          :removed removed
          :slug-shifted (nreverse slug-shifted-result)
          :orphan-warnings orphan-warnings)))

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
      (let* ((cmd (format "git mv %s %s"
                          (shell-quote-argument (directory-file-name old-dir))
                          (shell-quote-argument (directory-file-name new-dir))))
             (rc (let ((default-directory root))
                   (shell-command cmd))))
        (if (zerop rc)
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
