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
(require 'a3madkour-publish-registry)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-id)
(require 'ob-core)          ; the header-argument parser ox-hugo uses
(require 'a3madkour-publish-yaml)
(require 'a3madkour-sections)

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

;; -- internal: keyword upsert (used by mark / unmark) --

(defun a3madkour-pub-author--hoist-file-property-drawer ()
  "Move a file-level `:PROPERTIES:' drawer back to the top of the buffer.

Repairs notes an earlier `a3-publish-mark' left with `#+' keyword lines
above the drawer (S1 row 10): org then reads it as a plain drawer, ox-hugo
prints it into the page, and org-roam loses the note's `:ID:'.  Acts only
when the drawer is preceded by nothing but `#+' keyword and blank lines, so
a heading's own drawer is never touched.  Regex-only, no `org-element'."
  (save-excursion
    (goto-char (point-min))
    (when (and (not (looking-at "[ \t]*:PROPERTIES:"))
               (looking-at "\\(?:[ \t]*\\(?:#\\+.*\\)?\n\\)+")
               (progn (goto-char (match-end 0))
                      (looking-at (concat "[ \t]*:PROPERTIES:[ \t]*\n"
                                          "\\(?:.*\n\\)*?"
                                          "[ \t]*:END:[ \t]*\\(?:\n\\|\\'\\)"))))
      (let ((drawer (match-string 0)))
        (delete-region (match-beginning 0) (match-end 0))
        (goto-char (point-min))
        (insert drawer)
        (unless (string-suffix-p "\n" drawer) (insert "\n"))))))

(defun a3madkour-pub-author--upsert-keyword (key val)
  "Set `#+KEY: VAL' in the current buffer's preamble, idempotently.

If a `#+KEY:' line exists anywhere in the buffer, replace its value
in place.  Otherwise insert `#+KEY: VAL' at point-min — or, when the
buffer opens with a file-level `:PROPERTIES:' drawer, just after its
`:END:'.  Org reads that drawer as the file's properties (org-roam's
`:ID:' among them) only while it is the first element.

KEY matching is case-insensitive on the keyword name.  VAL is inserted
verbatim — caller is responsible for any escaping."
  (a3madkour-pub-author--hoist-file-property-drawer)
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t)
          (re (format "^#\\+%s:[[:space:]]*.*$" (regexp-quote key))))
      (if (re-search-forward re nil t)
          (replace-match (format "#+%s: %s" key val) t t)
        (goto-char (point-min))
        (when (and (looking-at "^[ \t]*:PROPERTIES:[ \t]*$")
                   (re-search-forward "^[ \t]*:END:[ \t]*$" nil t))
          (forward-line 1))
        (insert (format "#+%s: %s\n" key val))))))

;; -- internal: #+HUGO_CUSTOM_FRONT_MATTER: by (keyword, :key) --
;;
;; A note carries many `#+HUGO_CUSTOM_FRONT_MATTER:' lines and one line may
;; carry several keys, so `--upsert-keyword' (one value per keyword) cannot
;; address them.  Values are split exactly where ox-hugo splits them: its
;; `org-hugo--parse-property-arguments' is `org-babel-parse-header-arguments',
;; which cuts on a colon preceded by whitespace, outside quotes and parens.

(defconst a3madkour-pub-author--keyword-fields
  '(("title" . "TITLE")
    ("description" . "HUGO_DESCRIPTION")
    ("summary" . "HUGO_SUMMARY"))
  "Fields written as their own `#+KEYWORD:' line, not a custom key.
Identical across sections (spec §6 step 4).")

(defconst a3madkour-pub-author--cfm-re
  "^#\\+HUGO_CUSTOM_FRONT_MATTER:[ \t]*\\(.*\\)$"
  "A custom front matter line; group 1 is its value.")

(defun a3madkour-pub-author--cfm-segments (value)
  "Split custom front matter VALUE into ((KEY . SEGMENT) ...).
KEY is the key without its colon; SEGMENT the trimmed `:key value' text."
  (when (and value (string-match-p "[^ \t]" value))
    (let* ((raw (org-babel-balanced-split value '((32 9) . 58)))
           (segs (cons (car raw)
                       (mapcar (lambda (r) (concat ":" r)) (cdr raw)))))
      (delq nil
            (mapcar (lambda (s)
                      (let ((s (string-trim s)))
                        (when (string-match "\\`:\\([^ \t]+\\)" s)
                          (cons (match-string 1 s) s))))
                    segs)))))

(defun a3madkour-pub-author--cfm-lines ()
  "Every custom front matter line as (BEG END VALUE), in buffer order."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t) out)
      (while (re-search-forward a3madkour-pub-author--cfm-re nil t)
        (push (list (match-beginning 0) (match-end 0)
                    (match-string-no-properties 1))
              out))
      (nreverse out))))

(defun a3madkour-pub-author--cfm-keys ()
  "Every key named on any custom front matter line, in buffer order."
  (cl-loop for (_beg _end value) in (a3madkour-pub-author--cfm-lines)
           append (mapcar #'car (a3madkour-pub-author--cfm-segments value))))

(defun a3madkour-pub-author--cfm-get (key)
  "Value of custom front matter KEY as a string, or nil.
Parsed as ox-hugo parses it; the last line naming KEY wins."
  (let ((sym (intern (concat ":" key))) val)
    (dolist (l (a3madkour-pub-author--cfm-lines) val)
      (let ((cell (assq sym (org-babel-parse-header-arguments (nth 2 l) t))))
        (when cell
          (setq val (format "%s" (cdr cell))))))))

(defun a3madkour-pub-author--field-present-p (name)
  "Non-nil when field NAME already has a value in the buffer.
Reads the dedicated keyword for title/description/summary (a keyword with
an empty value counts as absent), else the custom front matter keys."
  (let ((kw (cdr (assoc name a3madkour-pub-author--keyword-fields))))
    (if kw
        (let ((v (a3madkour-pub-keywords/extract kw)))
          (and v (not (string-empty-p v))))
      (and (member name (a3madkour-pub-author--cfm-keys)) t))))

(defun a3madkour-pub-author--cfm-value (type value)
  "Render VALUE of field TYPE for a `:key VALUE' custom front matter segment.
Text is always double-quoted (the caller has rejected embedded quotes), so
spaces, ` :' and digit-only strings survive ox-hugo's parser verbatim."
  (pcase type
    ("text" (format "\"%s\"" value))
    ("int" (number-to-string value))
    ("bool" (if value "true" "false"))
    ("list" (mapconcat #'identity value " "))
    ;; Branch A (Task 1: the space list reaches the page as a YAML list).
    ;; Branch B replaces this line with:
    ;;   ("refs" (format "'(%s)" (mapconcat #'identity value " ")))
    ("refs" (mapconcat #'identity value " "))
    (_ value)))

(defun a3madkour-pub-author--cfm-insert-point ()
  "Where a new custom front matter line goes: after the last such line,
else after `#+HUGO_SECTION:', else after a leading file property drawer,
else at `point-min'."
  (save-excursion
    (let ((lines (a3madkour-pub-author--cfm-lines))
          (case-fold-search t))
      (cond
       (lines
        (goto-char (nth 1 (car (last lines))))
        (forward-line 1))
       ((progn (goto-char (point-min))
               (re-search-forward "^#\\+HUGO_SECTION:.*$" nil t))
        (forward-line 1))
       (t
        (goto-char (point-min))
        (when (and (looking-at "^[ \t]*:PROPERTIES:[ \t]*$")
                   (re-search-forward "^[ \t]*:END:[ \t]*$" nil t))
          (forward-line 1))))
      (point))))

(defun a3madkour-pub-author--upsert-cfm-key (key rendered)
  "Set custom front matter KEY to RENDERED (already a segment value).
A line naming KEY has that one segment replaced, its other keys kept;
otherwise a new `#+HUGO_CUSTOM_FRONT_MATTER: :KEY RENDERED' line is
inserted (see `--cfm-insert-point').  Hoists a displaced file property
drawer first, as `--upsert-keyword' does."
  (a3madkour-pub-author--hoist-file-property-drawer)
  (let ((seg (format ":%s %s" key rendered))
        (hit (cl-find-if (lambda (l)
                           (assoc key (a3madkour-pub-author--cfm-segments (nth 2 l))))
                         (a3madkour-pub-author--cfm-lines))))
    (save-excursion
      (if hit
          (let ((segs (a3madkour-pub-author--cfm-segments (nth 2 hit))))
            (setcdr (assoc key segs) seg)
            (delete-region (nth 0 hit) (nth 1 hit))
            (goto-char (nth 0 hit))
            (insert "#+HUGO_CUSTOM_FRONT_MATTER: " (mapconcat #'cdr segs " ")))
        (goto-char (a3madkour-pub-author--cfm-insert-point))
        (unless (bolp) (insert "\n"))
        (insert "#+HUGO_CUSTOM_FRONT_MATTER: " seg "\n")))))

(defun a3madkour-pub-author--remove-cfm-key (key)
  "Remove KEY's segment from every custom front matter line.
A line left with no keys is deleted with its newline."
  (save-excursion
    ;; Bottom-up, so earlier lines' positions stay valid.
    (dolist (l (reverse (a3madkour-pub-author--cfm-lines)))
      (let* ((segs (a3madkour-pub-author--cfm-segments (nth 2 l)))
             (kept (cl-remove-if (lambda (s) (equal (car s) key)) segs)))
        (unless (equal kept segs)
          (if kept
              (progn
                (delete-region (nth 0 l) (nth 1 l))
                (goto-char (nth 0 l))
                (insert "#+HUGO_CUSTOM_FRONT_MATTER: "
                        (mapconcat #'cdr kept " ")))
            (delete-region (nth 0 l) (min (point-max) (1+ (nth 1 l))))))))))

(defun a3madkour-pub-author--remove-field (name)
  "Remove field NAME: its keyword line, or its custom front matter key."
  (let ((kw (cdr (assoc name a3madkour-pub-author--keyword-fields))))
    (if (not kw)
        (a3madkour-pub-author--remove-cfm-key name)
      (save-excursion
        (goto-char (point-min))
        (let ((case-fold-search t))
          (while (re-search-forward
                  (format "^#\\+%s:.*\n?" (regexp-quote kw)) nil t)
            (replace-match "" t t)))))))

(defun a3madkour-pub-author--write-field (name type value)
  "Write field NAME (of TYPE) with VALUE into the buffer preamble."
  (let ((kw (cdr (assoc name a3madkour-pub-author--keyword-fields))))
    (if kw
        (a3madkour-pub-author--upsert-keyword kw value)
      (a3madkour-pub-author--upsert-cfm-key
       name (a3madkour-pub-author--cfm-value type value)))))

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
  (a3madkour-pub-registry/get section :default-medium))

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
    ;; Guard: point must be under a heading.  Use ignore-errors around
    ;; org-back-to-heading so that any internal signal (e.g. "Before first
    ;; headline") gets translated into our own user-error message.
    (unless (or (org-at-heading-p)
                (ignore-errors (save-excursion (org-back-to-heading t))))
      (user-error "a3-library-insert-extras: point not under any heading"))
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

(provide 'a3madkour-publish-author)

;;; a3madkour-publish-author.el ends here
