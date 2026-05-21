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

(defcustom a3madkour-pub/site-data-dir
  nil
  "Path to the Hugo site repo's `data/' directory.

Required for URL-history manifest I/O.  Errors clearly when nil and
manifest reads/writes are attempted.  Set in your emacs config:

  (setq a3madkour-pub/site-data-dir
        \"~/Workspace/a3madkour.github.io/data/\")"
  :type '(choice (const :tag "Not set" nil) directory)
  :group 'a3madkour-pub)

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

(defun a3madkour-pub-history/write-manifest (manifest)
  "Serialize MANIFEST (an alist) to `url-history.yaml' as block-style YAML.
Creates the data dir if missing."
  (let ((path (a3madkour-pub-history--manifest-path)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (insert (yaml-encode manifest))
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

(defun a3madkour-pub-history--diff-reason (old-url new-url)
  "Classify the URL change between OLD-URL and NEW-URL.
Returns one of \"section_change\" or \"title_change\" (the latter is a
catch-all for either an actual title change or a `#+HUGO_SLUG:' override —
this stub doesn't distinguish them because it lacks source-file context).

A.1.b can add finer-grained reason detection if useful; the spec lists
`title_change' / `slug_override' / `section_change' / `removed' as the canonical
vocabulary.  This stub picks the safest classification."
  (let* ((old-section (a3madkour-pub-history--section-of-url old-url))
         (new-section (a3madkour-pub-history--section-of-url new-url)))
    (cond
     ((not (equal old-section new-section)) "section_change")
     ;; Same section, different slug → can't distinguish title-vs-override here.
     ;; A.1.b/F will pass an extra :had-slug-override-p hint to refine this.
     (t "title_change"))))

(defun a3madkour-pub-history--now-iso ()
  "Return current time as an ISO-8601 UTC string."
  (format-time-string "%FT%TZ" nil t))

(defun a3madkour-pub-history/record-publish (id new-url state)
  "Update the manifest entry for ID.

Cases:
  - ID not in manifest → insert a new entry with empty history.
  - ID present, current_url == NEW-URL and state == STATE → no-op.
  - ID present, current_url differs → append `{url, replaced_at, reason}'
    to history and update current_url.
  - state differs (e.g. live → removed) → update state; if current_url also
    differs, append history with reason=\"removed\" when new-url is nil,
    otherwise per `--diff-reason'.

STATE is `live', `draft', or `removed' (string or symbol accepted)."
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
                          (url-changed-p (a3madkour-pub-history--diff-reason
                                          old-url new-url))
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
            (a3madkour-pub-history/write-manifest manifest))))))))

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

(provide 'a3madkour-publish-history)

;;; a3madkour-publish-history.el ends here
