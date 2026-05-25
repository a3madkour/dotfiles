;;; a3madkour-publish.el --- Org → Hugo publish pipeline (sub-project A) -*- lexical-binding: t; -*-

;; Author: Abdelrahman Madkour <a3madkour@gmail.com>
;; Version: 0.1.0-bootstrap
;; Package-Requires: ((emacs "30.2"))
;; Keywords: org, hugo, publish

;;; Commentary:

;; Phase 3 sub-project A: access control + link semantics for the
;; org → Hugo publish pipeline driving https://a3madkour.github.io/.
;;
;; This is the bootstrap shell.  A.1.{a..d} implement keyword parsing,
;; slug derivation, URL-history, link rewriting, asset handling, and
;; the unpublish flow.  Consumed by sub-project B (the per-section
;; publisher) via the function surface documented in the design spec at
;; docs/superpowers/specs/2026-05-20-phase-3-access-control-link-semantics-design.md
;; (in the site repo).

;;; Code:

(require 'cl-lib)

(defgroup a3madkour-pub nil
  "Org → Hugo publish pipeline (sub-project A: access control + link semantics)."
  :group 'org
  :prefix "a3madkour-pub/")

(require 'a3madkour-publish-keywords)
(require 'a3madkour-publish-slug)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-id)

(defconst a3madkour-pub/version "0.1.0-bootstrap"
  "Current version of the publish library.")

(defconst a3madkour-pub/sections
  '("essays"
    "garden"
    "research/themes" "research/questions"
    "works/games" "works/music" "works/poetry"
    "library/reading" "library/listening" "library/playing" "library/watching"
    "streams"
    "about")
  "Permitted values for the org-side `#+HUGO_SECTION:' keyword.
See docs/superpowers/specs/2026-05-20-phase-3-access-control-link-semantics-design.md §4.")

(defun a3madkour-pub/valid-section-p (s)
  "Return non-nil iff S is a string matching one of `a3madkour-pub/sections'."
  (and (stringp s)
       (member s a3madkour-pub/sections)
       t))

(defun a3madkour-pub--extract-id ()
  "Return the value of a top-level org-roam `:ID:' property in the current buffer.
Searches for the file-level `:PROPERTIES:`...`:END:` drawer (before the first
heading) and extracts its `:ID:' value.  Returns nil if absent."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      ;; Constrain to pre-first-heading region (file-level drawer).
      (let ((limit (save-excursion
                     (if (re-search-forward "^\\*+ " nil t)
                         (match-beginning 0)
                       (point-max)))))
        (when (re-search-forward "^[ \t]*:ID:[ \t]+\\(\\S-+\\)[ \t]*$" limit t)
          (match-string-no-properties 1))))))

(defun a3madkour-pub--parse-file (file)
  "Open FILE and return a plist of parsed publish-relevant keywords.

Plist keys:
  :title     — `#+title:' value (string or nil).
  :publish-p — non-nil iff `#+HUGO_PUBLISH:' is `t'.
  :section   — `#+HUGO_SECTION:' value (string or nil; empty-string normalized).
  :draft-p   — non-nil iff `#+HUGO_DRAFT:' is `t'.
  :slug      — the derived slug: `#+HUGO_SLUG:' override if non-empty, else
               `a3madkour-pub-slug/slugify' of :title, else nil.
  :aliases   — parsed `#+HUGO_ALIASES:' list (or nil).
  :id        — file-level org-roam `:ID:' property (string or nil).
  :file      — absolute path to FILE.
  :state     — `'live | 'draft | nil` (the validated publish-state — see below).

The `:state' key encodes the result of validating the keyword combo:
  - `'live`  — `#+HUGO_PUBLISH: t' + valid `#+HUGO_SECTION:' + no `#+HUGO_DRAFT:'.
  - `'draft' — same as live but with `#+HUGO_DRAFT: t'.
  - `nil`    — `#+HUGO_PUBLISH:' is absent or not `t' (private).

Signals `user-error' for invalid combinations:
  - `#+HUGO_PUBLISH: t' without `#+HUGO_SECTION:'
  - `#+HUGO_SECTION:' with an unknown value (typo guard)

Errors with `user-error' if FILE is missing.

NOTE: each public accessor (`published-p', `note-section', `note-slug',
`note-url') currently re-invokes this function.  For a caller that needs
multiple values from the same file, this means redundant file I/O.  A.1.b
will introduce a memoizing cache around `note-metadata'; until then,
publish loops should hoist the parse manually if perf matters.

Uses pure regex extraction (no `(org-mode)' activation needed) to avoid
the ~1s org autoload on cold cache."
  (unless (file-readable-p file)
    (user-error "a3madkour-pub: cannot read file: %s" file))
  (with-temp-buffer
    (insert-file-contents file)
    (let* ((raw-section (a3madkour-pub-keywords/extract "HUGO_SECTION"))
           (raw-slug    (a3madkour-pub-keywords/extract "HUGO_SLUG"))
           (title       (a3madkour-pub-keywords/extract "title"))
           (publish-p   (a3madkour-pub-keywords/boolean-p
                         (a3madkour-pub-keywords/extract "HUGO_PUBLISH")))
           (section     (and raw-section (not (string-empty-p raw-section)) raw-section))
           (draft-p     (a3madkour-pub-keywords/boolean-p
                         (a3madkour-pub-keywords/extract "HUGO_DRAFT")))
           (override    (and raw-slug (not (string-empty-p raw-slug)) raw-slug))
           (slug        (or override
                            (and title
                                 (let ((s (a3madkour-pub-slug/slugify title)))
                                   (and s (not (string-empty-p s)) s)))))
           (aliases     (a3madkour-pub-keywords/parse-aliases
                         (a3madkour-pub-keywords/extract "HUGO_ALIASES")))
           (id          (a3madkour-pub--extract-id))
           (state
            (cond
             ;; Not opted-in → private (most common case).
             ((not publish-p) nil)
             ;; Opted-in but no section → likely typo / incomplete config.
             ((null section)
              (user-error "a3madkour-pub: %s has #+HUGO_PUBLISH but no #+HUGO_SECTION" file))
             ;; Unknown section value → likely typo.
             ((not (a3madkour-pub/valid-section-p section))
              (user-error "a3madkour-pub: %s has unknown #+HUGO_SECTION value %S"
                          file section))
             (draft-p 'draft)
             (t 'live))))
      (list :title     title
            :publish-p publish-p
            :section   section
            :draft-p   draft-p
            :slug      slug
            :aliases   aliases
            :id        id
            :file      (expand-file-name file)
            :state     state))))

(defvar a3madkour-pub--metadata-cache
  (make-hash-table :test 'equal)
  "Per-publish-run cache of file path → metadata plist (see `a3madkour-pub/note-metadata').
Reset explicitly via `a3madkour-pub--reset-metadata-cache' at the start of each
publish run (called from `a3madkour-pub/begin-publish').")

(defun a3madkour-pub--reset-metadata-cache ()
  "Clear the per-publish metadata cache.  Idempotent."
  (setq a3madkour-pub--metadata-cache (make-hash-table :test 'equal)))

(defvar a3madkour-pub--publish-run-accumulator
  (make-hash-table :test 'equal)
  "Per-publish-run accumulator of id → (current-url . state) for notes that
`a3madkour-pub-history/record-publish' processed during this publish.

Populated incrementally by B's per-content-type publisher (via record-publish);
consumed by `a3madkour-pub/finish-publish' to compute the new live+draft set
without re-walking the source tree.

When empty at the time `finish-publish' runs, the orchestrator falls back to
`a3madkour-pub/walk-published-source-set' (standalone mode — used today,
before B ships).

Reset explicitly via `a3madkour-pub/begin-publish' at the start of each run.")

(defvar a3madkour-pub--manifest-snapshot nil
  "Snapshot of the URL-history manifest taken at `begin-publish'.

`a3madkour-pub/diff-published-set' reads from this snapshot instead of
re-reading `data/url-history.yaml' off disk, so that `record-publish'
calls made mid-publish (by B's per-note publishers) do not poison the
slug-shift detection in `diff-published-set'.

nil means \"no snapshot active\" — `read-manifest-snapshot-or-disk' will
fall back to reading the manifest off disk.  Set at the top of
`begin-publish' (next to the metadata-cache reset); cleared at the bottom
of `finish-publish' (after Step C).

Lives in `a3madkour-publish.el' next to the publish-run-accumulator so the
two publish-run snapshots (accumulator, manifest) are colocated.

See parent design spec §6 (B-coupling fix); the design memo
`memory/project_a1d_complete.md' 'Architectural findings' section
documents why the snapshot approach was chosen over the alternatives.")

(defun a3madkour-pub--resolve-file-or-id (file-or-id)
  "If FILE-OR-ID is a UUID (looks like an org-roam ID), resolve via
`a3madkour-pub--id-to-file' and return the file path.  Otherwise return
FILE-OR-ID unchanged.  The heuristic is: input is a UUID if it matches
the RFC 4122 pattern; everything else is treated as a file path."
  (cond
   ((null file-or-id) nil)
   ((and (stringp file-or-id)
         (string-match-p
          "\\`[[:xdigit:]]\\{8\\}-[[:xdigit:]]\\{4\\}-[[:xdigit:]]\\{4\\}-[[:xdigit:]]\\{4\\}-[[:xdigit:]]\\{12\\}\\'"
          file-or-id))
    (a3madkour-pub--id-to-file file-or-id))
   (t file-or-id)))

(defun a3madkour-pub/note-metadata (file)
  "Return a plist of publish-relevant metadata for FILE, or nil if unpublished.

Thin wrapper over `a3madkour-pub--parse-file' (returns its full plist when
`:state' is non-nil; nil otherwise).  See `a3madkour-pub--parse-file' for
the plist-key contract.  Returned keys include at minimum:
  :id :section :slug :state :file :title
plus the rest of `--parse-file''s plist (:publish-p :draft-p :aliases).

Returns nil if `#+HUGO_PUBLISH:' is not `t' (i.e. `:state' is nil).

SNAPSHOT SEMANTICS: cached per publish run via `a3madkour-pub/begin-publish'
(added in Task 5).  Edits to FILE made after the cache warms are NOT picked
up until the next `begin-publish' call (acceptable for both shell and
interactive emacs publishes; author re-runs to see changes).  The cache is
keyed by absolute path and stores nil for known-unpublished files so they
don't re-parse on subsequent calls within the same run."
  (let* ((abs (expand-file-name file))
         (cached (gethash abs a3madkour-pub--metadata-cache 'a3-pub-miss)))
    (if (eq cached 'a3-pub-miss)
        (let* ((parsed (a3madkour-pub--parse-file abs))
               (md (when (plist-get parsed :state) parsed)))
          ;; Cache even nil results so unpublished files don't re-parse.
          (puthash abs md a3madkour-pub--metadata-cache)
          md)
      cached)))

(defun a3madkour-pub/published-p (file-or-id)
  "Return `'live`, `'draft`, or nil for FILE-OR-ID.
FILE-OR-ID may be either a file path (string) or an org-roam UUID string;
UUIDs are resolved via `a3madkour-pub--id-to-file' (RFC 4122 shape check
in `a3madkour-pub--resolve-file-or-id').
See `a3madkour-pub/note-metadata` for snapshot/caching behavior."
  (when-let* ((file (a3madkour-pub--resolve-file-or-id file-or-id))
              (md (a3madkour-pub/note-metadata file)))
    (plist-get md :state)))

(defun a3madkour-pub/note-section (file-or-id)
  "Return the `#+HUGO_SECTION:' value for FILE-OR-ID as a string, or nil.
FILE-OR-ID may be either a file path or an org-roam UUID string.
See `a3madkour-pub/note-metadata` for snapshot/caching behavior."
  (when-let ((file (a3madkour-pub--resolve-file-or-id file-or-id)))
    (plist-get (a3madkour-pub/note-metadata file) :section)))

(defun a3madkour-pub/note-slug (file-or-id)
  "Return the derived slug for FILE-OR-ID, or nil if unpublished / untitled.
FILE-OR-ID may be either a file path or an org-roam UUID string.
Slug is title-based, overridden by `#+HUGO_SLUG:`.
See `a3madkour-pub/note-metadata` for snapshot/caching behavior."
  (when-let ((file (a3madkour-pub--resolve-file-or-id file-or-id)))
    (plist-get (a3madkour-pub/note-metadata file) :slug)))

(defun a3madkour-pub/note-url (file-or-id)
  "Return `\"/<section>/<slug>/\"` for FILE-OR-ID, or nil if unpublished.
FILE-OR-ID may be either a file path or an org-roam UUID string.
See `a3madkour-pub/note-metadata` for snapshot/caching behavior."
  (when-let* ((file (a3madkour-pub--resolve-file-or-id file-or-id))
              (md (a3madkour-pub/note-metadata file))
              (section (plist-get md :section))
              (slug (plist-get md :slug)))
    (format "/%s/%s/" section slug)))

(defun a3madkour-pub/begin-publish ()
  "Take per-publish snapshots: reset metadata cache; clear accumulator;
read URL-history manifest into `a3madkour-pub--manifest-snapshot'; sync
org-roam DB.

Call this at the start of any publish run (shell or interactive).
Both A's accessors and the link rewriter rely on these snapshots being
fresh; edits made after this call are NOT picked up until the next
`begin-publish' call.

See parent spec §11 (snapshot-at-publish-start subsection).  A.1.d adds
the publish-run-accumulator clear (the accumulator backs `finish-publish'
in B-coupled mode).

NOTE: `org-roam' is required lazily via `autoload'/dynamic load on first
use of `org-roam-db-sync'.  Tests stub `org-roam-db-sync' via `cl-letf'
to avoid touching the author's real org-roam DB; for that stub to remain
in effect across the call, org-roam must already be loaded (so that
`require' here is a no-op).  The test file pre-requires `org-roam' for
that reason."
  (a3madkour-pub--reset-metadata-cache)
  (clrhash a3madkour-pub--publish-run-accumulator)
  ;; B.0: snapshot the URL-history manifest so diff-published-set reads
  ;; pre-publish state regardless of mid-publish record-publish calls.
  (setq a3madkour-pub--manifest-snapshot
        (a3madkour-pub-history/read-manifest))
  (require 'org-roam)
  ;; Gate `org-roam-db-sync' on the directory actually existing.  In batch
  ;; publish contexts (`emacs --batch'), the author's interactive config
  ;; that points `org-roam-directory' at the real notes tree may not be
  ;; loaded, leaving the package default (~/org-roam/) — which often does
  ;; not exist and causes `org-roam-db-sync' to crash the run.  A.1.d
  ;; known limitation.
  (when (and (boundp 'org-roam-directory)
             (file-directory-p org-roam-directory))
    (org-roam-db-sync)))

(provide 'a3madkour-publish)

;;; a3madkour-publish.el ends here
