;;; a3madkour-publish-history.el --- URL-history manifest -*- lexical-binding: t; -*-

;;; Commentary:

;; Reads, writes, and updates `data/url-history.yaml' (path computed from
;; `a3madkour-pub/site-data-dir').  Tracks every published note's current
;; URL plus the URLs it has had in the past, so that `aliases:' frontmatter
;; can be emitted on the next publish.
;;
;; Single-process assumption: `record-publish' is read-modify-write without
;; locking.  Concurrent publishers would race; the second writer's update
;; clobbers the first.  Acceptable because the publish CLI is single-process.

;;; Code:

(require 'cl-lib)
(require 'yaml)

;; The user-facing defcustoms below live under the parent `a3madkour-pub'
;; group (defined in a3madkour-publish.el) so `M-x customize-group RET
;; a3madkour-pub' surfaces every site-config knob in one place.

(defcustom a3madkour-pub/org-notes-dir
  (expand-file-name "~/org/notes/")
  "Root directory of the org-roam notes corpus."
  :type 'directory
  :group 'a3madkour-pub)

(defcustom a3madkour-pub/essays-dir (expand-file-name "~/org/essays/")
  "Directory holding essay source `.org' files for B.4 essays handler.

Essays are NOT roam-indexed and do NOT live under
`a3madkour-pub/org-notes-dir'.  The handler walks this directory only
under `publish-deliberate'; `publish-living' does not touch essays."
  :type 'directory
  :group 'a3madkour-pub)

(defcustom a3madkour-pub/site-data-dir
  nil
  "Path to the Hugo site repo's `data/' directory.

Required for URL-history manifest I/O.  Errors clearly when nil and
manifest reads/writes are attempted.  Set in your emacs config:

  (setq a3madkour-pub/site-data-dir
        \"~/Workspace/a3madkour.github.io/data/\")"
  :type '(choice (const :tag "Not set" nil) directory)
  :group 'a3madkour-pub)

;; Forward declaration: the real defvar lives in `a3madkour-publish.el',
;; which already `require's this file (so we can't `require' it back without
;; a circular dependency).  No initform here so we don't override the real
;; defvar's value when both files load.  Used by
;; `read-manifest-snapshot-or-disk' below; see parent design spec §6.
(defvar a3madkour-pub--manifest-snapshot)

(defun a3madkour-pub-history--manifest-path ()
  "Return the absolute path to `url-history.yaml', or signal user-error."
  (unless a3madkour-pub/site-data-dir
    (user-error "a3madkour-pub: set `a3madkour-pub/site-data-dir' first"))
  (expand-file-name "url-history.yaml" a3madkour-pub/site-data-dir))

(defconst a3madkour-pub-history--empty-manifest
  '((notes . []))
  "Initial manifest shape: an empty vector under `notes'.")

(defun a3madkour-pub-history/read-manifest ()
  "Return the manifest as an alist parsed from `url-history.yaml'.
If the file is missing or empty, returns the empty shape `((notes . []))'.

Uses `yaml-parse-string' keyword API (yaml.el's public surface; the dynamic
vars `yaml--parsing-*' are internal and may not be honoured by callers)."
  (let ((path (a3madkour-pub-history--manifest-path)))
    (if (and (file-readable-p path)
             (> (file-attribute-size (file-attributes path)) 0))
        (with-temp-buffer
          (insert-file-contents path)
          (yaml-parse-string (buffer-string)
                             :object-type 'alist
                             :object-key-type 'symbol
                             :sequence-type 'array
                             :null-object nil
                             :false-object nil))
      (copy-tree a3madkour-pub-history--empty-manifest))))

(defun a3madkour-pub-history/read-manifest-snapshot-or-disk ()
  "Return `a3madkour-pub--manifest-snapshot' when non-nil; otherwise read disk.

Use this from any function that needs the URL-history manifest as it
existed AT THE START of the current publish run (as opposed to whatever
state `record-publish' has eagerly written to disk mid-run).  Currently
the sole caller is `a3madkour-pub/diff-published-set' (the slug-shift
detector); other A.1 readers continue to call `read-manifest' directly
because they don't care about run boundaries.

The snapshot defvar lives in `a3madkour-publish.el' (colocated with the
publish-run-accumulator); it is populated by `a3madkour-pub/begin-publish'
and cleared by `a3madkour-pub/finish-publish'.

See parent design spec §6 (B-coupling fix)."
  (if a3madkour-pub--manifest-snapshot
      a3madkour-pub--manifest-snapshot
    (a3madkour-pub-history/read-manifest)))

(defconst a3madkour-pub-history--canonical-key-order
  '(id current_url history state)
  "Canonical key order for each entry in `url-history.yaml'.
Applied at write time so the emitted file is byte-stable across publish runs
regardless of construction order in upstream code (yaml.el serializes alists
in list order — entries get re-shuffled keys depending on how they were
updated).")

(defun a3madkour-pub-history--canonicalize-entry (entry)
  "Return ENTRY (an alist) with keys re-ordered per
`a3madkour-pub-history--canonical-key-order'.  Unknown keys are appended
after the canonical ones in their existing order, so adding a new key
elsewhere in the codebase doesn't silently drop it from the emitted YAML."
  (let* ((known (cl-remove-if-not
                 (lambda (k) (assq k entry))
                 a3madkour-pub-history--canonical-key-order))
         (extras (cl-remove-if
                  (lambda (cell)
                    (memq (car cell)
                          a3madkour-pub-history--canonical-key-order))
                  entry)))
    (append (mapcar (lambda (k) (assq k entry)) known) extras)))

(defun a3madkour-pub-history--canonicalize-manifest (manifest)
  "Return MANIFEST with each `notes' entry's keys re-ordered canonically."
  (let ((notes (alist-get 'notes manifest)))
    (if (vectorp notes)
        (cons (cons 'notes
                    (vconcat
                     (mapcar #'a3madkour-pub-history--canonicalize-entry notes)))
              (assq-delete-all 'notes (copy-alist manifest)))
      manifest)))

(defun a3madkour-pub-history/write-manifest (manifest)
  "Serialize MANIFEST (an alist) to `url-history.yaml' as block-style YAML.
Creates the data dir if missing.  Each note entry's keys are pre-ordered
canonically (id / current_url / history / state) so the emitted file is
byte-stable across publish runs."
  (let ((path (a3madkour-pub-history--manifest-path))
        (canonical (a3madkour-pub-history--canonicalize-manifest manifest)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (insert (yaml-encode canonical))
      (unless (eq ?\n (char-before)) (insert "\n")))))

(defun a3madkour-pub-history--find-note-by-id (notes-vec id)
  "Return the index of the note with given ID in NOTES-VEC, or nil if absent."
  (cl-loop for i from 0 below (length notes-vec)
           when (equal id (alist-get 'id (aref notes-vec i)))
           return i))

(defun a3madkour-pub-history--state-to-string (state)
  "Coerce STATE (symbol or string) to its canonical string form."
  (cond
   ((stringp state) state)
   ((symbolp state) (symbol-name state))
   (t (error "a3madkour-pub: invalid state %S" state))))

(defun a3madkour-pub-history--section-of-url (url)
  "Extract the section component from URL of shape `/<section>/<slug>/'.
For nested sections like `/research/questions/q/' returns `research/questions'."
  (when (and (stringp url) (string-prefix-p "/" url))
    (let* ((trimmed (replace-regexp-in-string "\\`/+\\|/+\\'" "" url))
           (parts (split-string trimmed "/")))
      ;; All but the last segment is the section.
      (when (>= (length parts) 2)
        (mapconcat #'identity (butlast parts) "/")))))

(defun a3madkour-pub-history--diff-reason (old-url new-url &optional had-slug-override-p)
  "Classify the URL change between OLD-URL and NEW-URL.
Returns one of \"section_change\", \"slug_override\", or \"title_change\".

Precedence:
  - Section differs → \"section_change\" (wins over the slug-override flag).
  - Same section + HAD-SLUG-OVERRIDE-P non-nil → \"slug_override\"
    (the source `.org' had `#+HUGO_SLUG:' set, so the URL change is driven
    by an explicit author choice rather than a title edit).
  - Same section + flag nil → \"title_change\".

Callers guard the `\"removed\"' case (NEW-URL is nil) and the no-change
case (OLD-URL equals NEW-URL) before invoking this helper, so it only
sees genuine same-id URL transitions where both URLs are non-nil."
  (let* ((old-section (a3madkour-pub-history--section-of-url old-url))
         (new-section (a3madkour-pub-history--section-of-url new-url)))
    (cond
     ((not (equal old-section new-section)) "section_change")
     (had-slug-override-p "slug_override")
     (t "title_change"))))

(defun a3madkour-pub-history--now-iso ()
  "Return current time as an ISO-8601 UTC string."
  (format-time-string "%FT%TZ" nil t))

(cl-defun a3madkour-pub-history/record-publish (id new-url state &key had-slug-override-p)
  "Update the manifest entry for ID.

Cases:
  - ID not in manifest → insert a new entry with empty history.
  - ID present, current_url == NEW-URL and state == STATE → no-op.
  - ID present, current_url differs → append `{url, replaced_at, reason}'
    to history and update current_url.
  - state differs (e.g. live → removed) → update state; if current_url also
    differs, append history with reason=\"removed\" when new-url is nil,
    otherwise per `--diff-reason'.

STATE is `live', `draft', or `removed' (string or symbol accepted).

Keyword args:
  :HAD-SLUG-OVERRIDE-P — when non-nil, signals that the source `.org' file
    had `#+HUGO_SLUG:' set on this publish.  Used to disambiguate same-section
    URL changes between author-driven slug overrides (\"slug_override\") and
    title-derived ones (\"title_change\").  Section changes always win regardless.
    Defaults to nil, preserving the prior behavior of classifying same-section
    changes as \"title_change\".

A.1.d additions:
  - `republished' reason: emitted on a removed → live transition.
  - Every call appends (id . (new-url . state)) to
    `a3madkour-pub--publish-run-accumulator' for `finish-publish' consumption.
    Caller must ensure `begin-publish' was invoked at the start of the publish
    run; the accumulator is not cleared on each call."
  (let* ((manifest (a3madkour-pub-history/read-manifest))
         (notes (alist-get 'notes manifest))
         (idx (a3madkour-pub-history--find-note-by-id notes id))
         (state-str (a3madkour-pub-history--state-to-string state)))
    (cond
     ;; New note.
     ((null idx)
      (let* ((new-note `((id . ,id)
                         (current_url . ,new-url)
                         (history . [])
                         (state . ,state-str)))
             (new-notes (vconcat notes (vector new-note))))
        (setf (alist-get 'notes manifest) new-notes)
        (a3madkour-pub-history/write-manifest manifest)))
     ;; Existing — compute diff.
     (t
      (let* ((current (aref notes idx))
             (old-url (alist-get 'current_url current))
             (old-state (alist-get 'state current))
             (url-changed-p (not (equal old-url new-url)))
             (state-changed-p (not (equal old-state state-str))))
        (when (or url-changed-p state-changed-p)
          (let* ((reason (cond
                          ((and url-changed-p (null new-url)) "removed")
                          ;; A.1.d: republish — removed → live transition.
                          ;; Takes precedence over the bare url-changed-p
                          ;; branch so republishing at a NEW URL still gets
                          ;; the `republished' label (not `title_change').
                          ((and state-changed-p
                                (equal old-state "removed")
                                (equal state-str "live"))
                           "republished")
                          ;; A.1.d: removed → draft (or any other non-live
                          ;; state) is state-only — no event appended.  The
                          ;; current_url update still happens (state change
                          ;; is real), but history stays quiet until the
                          ;; note actually republishes as live.
                          ((equal old-state "removed") nil)
                          (url-changed-p (a3madkour-pub-history--diff-reason
                                          old-url new-url had-slug-override-p))
                          (t nil)))  ; state-only change
                 (new-history
                  (if reason
                      (vconcat (alist-get 'history current)
                               (vector `((url . ,old-url)
                                         (replaced_at . ,(a3madkour-pub-history--now-iso))
                                         (reason . ,reason))))
                    (alist-get 'history current)))
                 (updated `((id . ,id)
                            (current_url . ,new-url)
                            (history . ,new-history)
                            (state . ,state-str))))
            (aset notes idx updated)
            (a3madkour-pub-history/write-manifest manifest))))))
    ;; A.1.d: accumulator append (always, regardless of which branch above
    ;; mutated the manifest).  Stores the SYMBOL form of state so that
    ;; `a3madkour-pub/diff-published-set' can compare cdr against `live' /
    ;; `draft' symbols (Task 5 contract).
    (puthash id (cons new-url state) a3madkour-pub--publish-run-accumulator)))

(defun a3madkour-pub-history/aliases-for (id)
  "Return all prior URLs recorded for ID, oldest-first.  Nil if ID unknown.
Drops `nil' entries (notes that have only ever had a single URL or are removed)."
  (let* ((manifest (a3madkour-pub-history/read-manifest))
         (notes (alist-get 'notes manifest))
         (idx (a3madkour-pub-history--find-note-by-id notes id)))
    (when idx
      (let ((hist (alist-get 'history (aref notes idx))))
        (when (and hist (> (length hist) 0))
          (cl-loop for i from 0 below (length hist)
                   for entry = (aref hist i)
                   for url = (alist-get 'url entry)
                   when url collect url))))))

(defun a3madkour-pub-history/git-mtime-of-file (file)
  "Return the YYYY-MM-DD date of the most recent commit touching FILE.
Returns nil when FILE is not under git or has never been committed.

Used as the per-file fallback for `last_modified' when no explicit
property is set on the source (garden + library per spec §8 + §5
respectively)."
  (when (file-exists-p file)
    (let* ((default-directory (file-name-directory (expand-file-name file)))
           (basename (file-name-nondirectory file))
           (raw (with-output-to-string
                  (with-current-buffer standard-output
                    (call-process "git" nil t nil
                                  "log" "-1" "--format=%cs" "--" basename))))
           (trimmed (string-trim raw)))
      (when (and trimmed
                 (not (string-empty-p trimmed))
                 (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$" trimmed))
        trimmed))))

(defun a3madkour-pub-history/filesystem-mtime-of-file (file)
  "Return the YYYY-MM-DD filesystem mtime of FILE.
Returns nil when FILE does not exist.

Used as the ultimate fallback for `last_modified' when neither
:LAST_MODIFIED: drawer, #+HUGO_LASTMOD: keyword, nor git-mtime
\(`--git-mtime-of-file') yields a value.  Best-effort idempotence —
editor saves with no content change bump mtime and will produce a
publish diff."
  (when (file-exists-p file)
    (format-time-string "%Y-%m-%d"
                        (file-attribute-modification-time
                         (file-attributes file)))))

(provide 'a3madkour-publish-history)

;;; a3madkour-publish-history.el ends here
