;;; a3madkour-publish-author.el --- Interactive publish-author helpers (Tier 5.2) -*- lexical-binding: t; -*-

;;; Commentary:

;; Five interactive commands for author-side publish-state management:
;;   a3-publish-mark / unmark / status — toggle and query #+HUGO_PUBLISH:
;;   a3-library-insert-extras — scaffold a library heading's extras drawer
;;   a3-publish-jump-to-source — manifest-driven nav from content/ → org
;;
;; All five compose existing primitives (the section registry and the site's
;; data/sections.json contract, keywords API, publish manifest).  No new tables.
;;
;; See `docs/superpowers/specs/2026-06-08-emacs-publish-author-helpers-design.md'.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'a3madkour-publish)
(require 'a3madkour-publish-keywords)
(require 'a3madkour-publish-library)
(require 'a3madkour-publish-frontmatter)  ; editorial-tag filter
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
Text, ref, refs and enum values are double-quoted (the caller has rejected
embedded quotes and backslashes), so spaces, ` :' and digit-only strings
such as a slug `1984' survive ox-hugo's parser as strings.  A refs list is
one quoted, space-separated string, which the section normalizers split."
  (pcase type
    ((or "text" "ref" "enum") (format "\"%s\"" value))
    ("refs" (format "\"%s\"" (mapconcat #'identity value " ")))
    ("int" (number-to-string value))
    ("bool" (if value "true" "false"))
    ("list" (mapconcat #'identity value " "))
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

;; -- internal: file-level drawer properties (source `drawer') --
;;
;; A `drawer' field is a `LIBRARY_<NAME>' property of the file-level
;; `:PROPERTIES:' drawer.  Org reads that drawer as the file's properties
;; only while it is the buffer's first element, so reads honour that and
;; writes hoist or create it there.  Regex-only, no `org-element'.

(defun a3madkour-pub-author--drawer-property (name)
  "File-level property key for field NAME: `media_type' -> `LIBRARY_MEDIA_TYPE'."
  (concat "LIBRARY_" (upcase name)))

(defconst a3madkour-pub-author--file-drawer-re
  (concat "\\`[ \t]*:PROPERTIES:[ \t]*\n"
          "\\(\\(?:.*\n\\)*?\\)"
          "[ \t]*:END:[ \t]*\\(?:\n\\|\\'\\)")
  "The buffer-leading property drawer; group 1 is its property lines.")

(defun a3madkour-pub-author--drawer-get (name)
  "Value of field NAME's file-level property, or nil when absent or blank.
Only a drawer that is the first thing in the buffer counts."
  (save-excursion
    (save-match-data
      (goto-char (point-min))
      (when (looking-at a3madkour-pub-author--file-drawer-re)
        (let ((props (match-string-no-properties 1))
              (case-fold-search t))
          (when (string-match
                 (format "^[ \t]*:%s:[ \t]*\\(.*?\\)[ \t]*$"
                         (regexp-quote (a3madkour-pub-author--drawer-property name)))
                 props)
            (let ((v (match-string 1 props)))
              (and (not (string-empty-p v)) v))))))))

(defun a3madkour-pub-author--drawer-put (name value)
  "Set field NAME's file-level property to VALUE, first-element drawer.
Replaces an existing line in place, else appends before `:END:'; with no
leading drawer, creates one at the top (hoisting a mis-placed one first)."
  (a3madkour-pub-author--hoist-file-property-drawer)
  (let ((key (a3madkour-pub-author--drawer-property name))
        (case-fold-search t))
    (save-excursion
      (goto-char (point-min))
      (if (not (looking-at a3madkour-pub-author--file-drawer-re))
          (insert (format ":PROPERTIES:\n:%s: %s\n:END:\n" key value))
        (let ((beg (match-beginning 1)) (end (match-end 1)))
          (goto-char beg)
          (if (re-search-forward
               (format "^[ \t]*:%s:.*$" (regexp-quote key)) end t)
              (replace-match (format ":%s: %s" key value) t t)
            (goto-char end)
            (insert (format ":%s: %s\n" key value))))))))

(defun a3madkour-pub-author--write-field (name type value &optional source)
  "Write field NAME (of TYPE) with VALUE into the buffer preamble.
A field whose SOURCE is `filetags' is written as tags on `#+filetags:';
one whose SOURCE is `drawer' as a `LIBRARY_*' file-level property."
  (let ((kw (cdr (assoc name a3madkour-pub-author--keyword-fields))))
    (cond
     ((equal source "filetags") (a3madkour-pub-author--add-filetags value))
     ((equal source "drawer") (a3madkour-pub-author--drawer-put name value))
     (kw (a3madkour-pub-author--upsert-keyword kw value))
     (t (a3madkour-pub-author--upsert-cfm-key
         name (a3madkour-pub-author--cfm-value type value))))))

;; -- a3-publish-mark --

(defmacro a3madkour-pub-author--with-contract (&rest body)
  "Run BODY; turn a section-contract `error' into a `user-error'.
A `user-error' passes through unchanged."
  `(condition-case err (progn ,@body)
     (user-error (signal (car err) (cdr err)))
     (error (user-error "a3-publish-mark: %s" (error-message-string err)))))

(defun a3madkour-pub-author--stale-fields (section)
  "Fields in the buffer that SECTION's contract does not list.
Candidates are the custom front matter keys plus description/summary;
`#+TITLE:' is never offered for removal."
  (let ((legal (a3madkour-sections/emitted-keys section))
        (present (append
                  (cl-loop for (name . _kw) in a3madkour-pub-author--keyword-fields
                           when (and (not (equal name "title"))
                                     (a3madkour-pub-author--field-present-p name))
                           collect name)
                  (a3madkour-pub-author--cfm-keys))))
    (cl-remove-if (lambda (n) (member n legal))
                  (delete-dups present))))

(defun a3madkour-pub-author--gather (section)
  "Collect every value SECTION still needs; write nothing.
Returns (:values ((NAME TYPE VALUE) ...) :by-hand (NAME ...)).  BY-HAND
lists required `structured'/`object' fields, which are not prompted."
  (let (values by-hand)
    (dolist (cell (a3madkour-pub-author--fields-to-fill section))
      (let* ((name (car cell))
             (fs (cdr cell))
             (type (alist-get 'type fs)))
        (if (member type '("structured" "object"))
            (when (alist-get 'required fs) (push name by-hand))
          (let ((v (a3madkour-pub-author--ask section name fs)))
            (unless (eq v 'skip)
              (push (list name type v (alist-get 'source fs)) values))))))
    (list :values (nreverse values) :by-hand (nreverse by-hand))))

;;;###autoload
(cl-defun a3-publish-mark (section)
  "Mark the current org buffer for publish at SECTION and fill its fields.

Sets `#+HUGO_PUBLISH: t' + `#+HUGO_SECTION: SECTION', then supplies
every field SECTION's contract (data/sections.json) requires or marks
`ask' that the publisher cannot derive and the buffer lacks: prompting
for each (enum, bool, ref/refs over published pages, text) or filling it
(today, next weight).  title/description/summary are written as
`#+TITLE:'/`#+HUGO_DESCRIPTION:'/`#+HUGO_SUMMARY:', everything else as
`#+HUGO_CUSTOM_FRONT_MATTER: :key value'.  A field already present is
never prompted for or overwritten.

Every value is gathered BEFORE anything is written, so `C-g' (or a
`user-error' such as a required ref with no published targets) leaves
the buffer untouched.

Cross-section guard: if the buffer already has `#+HUGO_SECTION: <other>'
and SECTION differs, prompts `y-or-n-p' before changing; declining
aborts and returns nil.  On a change, offers (one `y-or-n-p') to remove
the fields the new section's contract does not list.

Refuses outside `org-mode', in a read-only buffer, or when the contract
is missing or malformed.  Returns SECTION, or nil if declined."
  (interactive
   (let ((current (a3madkour-pub-keywords/extract "HUGO_SECTION")))
     (list (completing-read "Section: " a3madkour-pub/sections
                            nil t nil nil current))))
  (unless (derived-mode-p 'org-mode)
    (user-error "a3-publish-mark: current buffer is not org-mode"))
  (when buffer-read-only
    (user-error "a3-publish-mark: buffer is read-only"))
  (a3madkour-pub-author--with-contract (a3madkour-sections/spec section))
  (let ((current (a3madkour-pub-keywords/extract "HUGO_SECTION")))
    (when (and current
               (not (string= current section))
               (not (y-or-n-p
                     (format "Move from `%s' to `%s'? (next publish-living will record slug-shift) "
                             current section))))
      (cl-return-from a3-publish-mark nil))
    (let* ((stale (and current
                       (not (string-empty-p current))
                       (not (string= current section))
                       (a3madkour-pub-author--stale-fields section)))
           (remove (and stale
                        (y-or-n-p (format "Remove fields not in %s (%s)? "
                                          section (string-join stale ", ")))))
           (plan (a3madkour-pub-author--gather section)))
      ;; Everything above only read and prompted; everything below writes.
      (a3madkour-pub-author--upsert-keyword "HUGO_PUBLISH" "t")
      (a3madkour-pub-author--upsert-keyword "HUGO_SECTION" section)
      (when remove
        (mapc #'a3madkour-pub-author--remove-field stale))
      (dolist (v (plist-get plan :values))
        (apply #'a3madkour-pub-author--write-field v))
      (when (plist-get plan :by-hand)
        (message "a3-publish-mark: %s also needs %s (structured; fill in by hand)"
                 section (string-join (plist-get plan :by-hand) ", ")))
      section)))

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

;; -- internal: what a3-publish-mark asks, and how --

(defun a3madkour-pub-author--site-root ()
  "The Hugo site root, or a `user-error' when it cannot be located."
  (unless (bound-and-true-p a3madkour-pub/site-data-dir)
    (user-error "a3-publish-mark: `a3madkour-pub/site-data-dir' is not set"))
  (a3madkour-pub-yaml/site-root))

(defun a3madkour-pub-author--fm-scalar (file key)
  "Top-level scalar KEY of FILE's YAML frontmatter, unquoted, or nil."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (when (looking-at "---[ \t]*\n\\(\\(?:.*\n\\)*?\\)---[ \t]*$")
      (let ((fm (match-string-no-properties 1)))
        (when (string-match (format "^%s:[ \t]*\\(.*?\\)[ \t]*$"
                                    (regexp-quote key))
                            fm)
          (let ((v (match-string 1 fm)))
            (if (string-match-p "\\`\".*\"\\'" v)
                (condition-case nil (read v) (error (substring v 1 -1)))
              v)))))))

(defun a3madkour-pub-author--bundles (section)
  "The index.md of every page bundle under content/SECTION/, or nil."
  (let ((dir (expand-file-name (concat "content/" section)
                               (a3madkour-pub-author--site-root))))
    (when (file-directory-p dir)
      (cl-loop for sub in (directory-files dir t "\\`[^._]")
               for md = (expand-file-name "index.md" sub)
               when (and (file-directory-p sub) (file-exists-p md))
               collect md))))

(defun a3madkour-pub-author--marked-notes (section)
  "Org notes under `a3madkour-pub/org-notes-dir' marked live for SECTION.
Returns `a3madkour-pub--parse-file' plists that carry a slug, skipping the
buffer being marked.  Read uncached: `note-metadata' snapshots per publish
run, and mark runs between runs.  A note whose keywords are invalid (a
`user-error' from the parser) is skipped; living publish reports it."
  (let ((dir (bound-and-true-p a3madkour-pub/org-notes-dir))
        (self (and buffer-file-name (expand-file-name buffer-file-name))))
    (when (and dir (file-directory-p dir))
      (cl-loop for f in (directory-files-recursively dir "\\.org\\'")
               for md = (and (not (equal (expand-file-name f) self))
                             (condition-case nil (a3madkour-pub--parse-file f)
                               (user-error nil)))
               when (and md
                         (eq (plist-get md :state) 'live)
                         (equal (plist-get md :section) section)
                         (plist-get md :slug))
               collect md))))

(defun a3madkour-pub-author--published-targets (to)
  "Pages of section TO a ref may name, as ((SLUG . TITLE) ...), by slug.
A published bundle (not `draft: true') counts, and so does an org note
marked live for TO that has not been published yet: marking a theme and
then its question in one session must offer that theme.  TITLE is the
bundle frontmatter's title (falling back to SLUG), or the note's title.
A slug present as both is listed once, with the bundle's title."
  (let ((targets
         (mapcar (lambda (md)
                   (let ((slug (file-name-nondirectory
                                (directory-file-name (file-name-directory md)))))
                     (cons slug (or (a3madkour-pub-author--fm-scalar md "title")
                                    slug))))
                 (cl-remove-if
                  (lambda (md)
                    (equal (a3madkour-pub-author--fm-scalar md "draft") "true"))
                  (a3madkour-pub-author--bundles to)))))
    (dolist (md (a3madkour-pub-author--marked-notes to))
      (unless (assoc (plist-get md :slug) targets)
        (push (cons (plist-get md :slug)
                    (or (plist-get md :title) (plist-get md :slug)))
              targets)))
    (sort targets (lambda (a b) (string< (car a) (car b))))))

(defun a3madkour-pub-author--next-weight (section)
  "Largest numeric weight in SECTION + 10, or 10.
Counts published bundles and notes marked for SECTION but not yet
published, so two themes marked before one publish get distinct weights."
  (let ((ws (append
             (cl-loop for md in (a3madkour-pub-author--bundles section)
                      for w = (a3madkour-pub-author--fm-scalar md "weight")
                      when (and w (string-match-p "\\`[0-9]+\\'" w))
                      collect (string-to-number w))
             (cl-loop for md in (a3madkour-pub-author--marked-notes section)
                      for w = (with-temp-buffer
                                (insert-file-contents (plist-get md :file))
                                (a3madkour-pub-author--cfm-get "weight"))
                      when (and w (string-match-p "\\`[0-9]+\\'" w))
                      collect (string-to-number w)))))
    (if ws (+ 10 (apply #'max ws)) 10)))

(defun a3madkour-pub-author--selector-value (on)
  "Buffer value of variant selector ON, or nil when absent or blank.
A blank value selects the same case as an absent field (matches the
site's check_fields).  A file-level `LIBRARY_<ON>' property wins over
the custom front matter key."
  (let ((v (and on (or (a3madkour-pub-author--drawer-get on)
                       (a3madkour-pub-author--cfm-get on)))))
    (and v (string-match-p "[^ \t]" v) v)))

(defun a3madkour-pub-author--filetags ()
  "The buffer's `#+filetags:' tags, in order, or nil."
  (let ((v (a3madkour-pub-keywords/extract "FILETAGS")))
    (and v (split-string v ":" t "[ \t]+"))))

(defun a3madkour-pub-author--source-satisfied-p (name source)
  "Non-nil when the buffer gives pipeline field NAME a value via SOURCE.
`title' is the `#+title:' keyword.  `drawer' is a non-blank file-level
`LIBRARY_*' property.  `filetags' needs a tag that survives
the pipeline's editorial filter: a note tagged only `:TODO:' exports no
tags key at all."
  (pcase source
    ("title" (a3madkour-pub-author--field-present-p name))
    ("filetags" (and (a3madkour-pub-frontmatter/filter-editorial-tags
                      (a3madkour-pub-author--filetags))
                     t))
    ("drawer" (and (a3madkour-pub-author--drawer-get name) t))
    (_ (error "a3-publish-mark: field %s has unknown source %S" name source))))

(defun a3madkour-pub-author--add-filetags (tags)
  "Append TAGS to the buffer's `#+filetags:', keeping the tags it has."
  (a3madkour-pub-author--upsert-keyword
   "filetags"
   (concat ":" (string-join (delete-dups (append (a3madkour-pub-author--filetags)
                                                 tags))
                            ":")
           ":")))

(defconst a3madkour-pub-author--org-tag-re "\\`[[:alnum:]_@#%]+\\'"
  "One org tag: org allows letters, digits, `_', `@', `#' and `%'.")

(defun a3madkour-pub-author--ask-filetags (name required prompt)
  "Read field NAME as whitespace-separated org tags; re-prompt until valid."
  (let (tags done)
    (while (not done)
      (setq tags (split-string (read-string prompt) "[ \t:]+" t))
      (cond
       ((and (null tags) required) (message "%s is required" name))
       ((cl-find-if-not (lambda (tg) (string-match-p a3madkour-pub-author--org-tag-re tg))
                        tags)
        (message "%s: org tags may use only letters, digits, _ @ # %%" name))
       (t (setq done t))))
    (or tags 'skip)))

(defun a3madkour-pub-author--fields-to-fill (section)
  "SECTION's fields `a3-publish-mark' must supply, as ((NAME . SPEC) ...).
A field qualifies when it is `required' or `ask' and absent from the
buffer.  A `from: pipeline' field qualifies only when it is required and
names a buffer `source' the pipeline would find empty (see
`--source-satisfied-p'); without a source the pipeline always derives it.  The variant case comes from the
buffer's value of the section's `variants.on' field.  A `store: data'
section (library) yields nil: its rows are collected from item notes."
  (let ((spec (a3madkour-sections/spec section)))
    (unless (equal (alist-get 'store spec) "data")
      (let* ((on (alist-get 'on (alist-get 'variants spec)))
             (vcase (a3madkour-pub-author--with-contract
                     (a3madkour-sections/variant-case
                      section (a3madkour-pub-author--selector-value on)))))
        (cl-remove-if-not
         (lambda (cell)
           (let ((fs (cdr cell)))
             (if (equal (alist-get 'from fs) "pipeline")
                 (and (alist-get 'required fs)
                      (alist-get 'source fs)
                      (not (a3madkour-pub-author--source-satisfied-p
                            (car cell) (alist-get 'source fs))))
               (and (or (alist-get 'required fs) (alist-get 'ask fs))
                    (not (a3madkour-pub-author--field-present-p (car cell)))))))
         (a3madkour-sections/fields section vcase))))))

(defun a3madkour-pub-author/missing-required (file section)
  "Required SECTION fields FILE lacks, by name: what mark would still ask.
These are the fields the pipeline cannot supply, so a bundle published
without them fails the site's fixture linter.  A contract error (say an
unknown variant case) signals a `user-error'."
  (with-temp-buffer
    (insert-file-contents file)
    (delay-mode-hooks (org-mode))
    (cl-loop for (name . spec) in (a3madkour-pub-author--fields-to-fill section)
             when (alist-get 'required spec)
             collect name)))

(defconst a3madkour-pub-author--string-shapes
  '(("int" "\\`[0-9]+\\'" "a whole number")
    ("date" "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" "a YYYY-MM-DD date"))
  "Per-type (REGEXP DESCRIPTION) a typed answer must match.")

(defun a3madkour-pub-author--ask-string (name type required keyword-p prompt)
  "Read field NAME of string-entered TYPE; re-prompt until acceptable.
An empty answer returns `skip' unless REQUIRED.  A double quote is
refused unless KEYWORD-P (custom front matter cannot carry one); so is a
backslash, which org's header-argument reader would consume."
  (let ((shape (cdr (assoc type a3madkour-pub-author--string-shapes)))
        v done)
    (while (not done)
      (setq v (string-trim (read-string prompt)))
      (cond
       ((string-empty-p v)
        (if required (message "%s is required" name) (setq done t)))
       ((and (not keyword-p) (string-match-p "\"" v))
        (message "%s: a double quote cannot be written to \
#+HUGO_CUSTOM_FRONT_MATTER" name))
       ((and (not keyword-p) (string-match-p "\\\\" v))
        (message "%s: a backslash cannot be written to \
#+HUGO_CUSTOM_FRONT_MATTER" name))
       ((and shape (not (string-match-p (car shape) v)))
        (message "%s must be %s" name (cadr shape)))
       (t (setq done t))))
    (cond ((string-empty-p v) 'skip)
          ((equal type "int") (string-to-number v))
          ((equal type "list") (split-string v "[ \t]+" t))
          (t v))))

(defvar vertico-preselect)

(defun a3madkour-pub-author--optional-pick (optional read)
  "Call READ, a pick-list read, with the empty input preselected if OPTIONAL.
An empty answer is how `completing-read' says \"no value\", even under
require-match, and the callers map it to `skip'.  Vertico preselects the
first candidate instead, so RET on an optional field filled it; `prompt'
makes RET on untouched input submit the empty answer.  Without Vertico
RET on empty input already returns \"\", so nothing is bound."
  (if (and optional (boundp 'vertico-preselect))
      (let ((vertico-preselect 'prompt)) (funcall read))
    (funcall read)))

(defun a3madkour-pub-author--ask-ref (name spec prompt)
  "Pick field NAME's ref/refs value (SPEC) from published targets."
  (let* ((to (alist-get 'to spec))
         (required (alist-get 'required spec))
         (choices (mapcar (lambda (c)
                            (cons (format "%s (%s)" (cdr c) (car c)) (car c)))
                          (a3madkour-pub-author--published-targets to)))
         (names (mapcar #'car choices)))
    (cond
     ((and (null choices) required)
      (user-error "a3-publish-mark: %s needs a published %s page; \
publish a %s page first" name to to))
     ((null choices) 'skip)
     ((equal (alist-get 'type spec) "ref")
      (let (pick)
        (while (progn (setq pick (a3madkour-pub-author--optional-pick
                                   (not required)
                                   (lambda () (completing-read prompt names nil t))))
                      (and required (string-empty-p pick))))
        (if (string-empty-p pick) 'skip (cdr (assoc pick choices)))))
     (t
      (let (picks)
        (while (progn (setq picks (a3madkour-pub-author--optional-pick
                                    (not required)
                                    (lambda () (completing-read-multiple prompt names nil t))))
                      (and required (null picks))))
        (if picks
            (mapcar (lambda (p) (cdr (assoc p choices))) picks)
          'skip))))))

(defun a3madkour-pub-author--ask (section name spec)
  "Obtain the value of SECTION's field NAME (SPEC), prompting as needed.
Returns the value, or `skip' for an optional field left empty.  Writes
nothing.  Signals `user-error' for a required ref with no targets."
  (let* ((type (alist-get 'type spec))
         (required (alist-get 'required spec))
         (fill (alist-get 'fill spec))
         (keyword-p (assoc name a3madkour-pub-author--keyword-fields))
         (prompt (format "%s %s%s: " section name (if required "" " (optional)"))))
    (cond
     ((equal (alist-get 'source spec) "filetags")
      (a3madkour-pub-author--ask-filetags name required prompt))
     ((equal fill "today") (format-time-string "%Y-%m-%d"))
     ((equal fill "next-weight") (a3madkour-pub-author--next-weight section))
     ((equal type "enum")
      (let ((default (alist-get 'default spec)) v)
        ;; With a default, RET submitting it is the intended answer.
        (while (progn (setq v (a3madkour-pub-author--optional-pick
                               (not (or required default))
                               (lambda ()
                                 (completing-read prompt (alist-get 'values spec)
                                                  nil t nil nil default))))
                      (and required (string-empty-p v))))
        (if (string-empty-p v) 'skip v)))
     ((equal type "bool")
      (y-or-n-p (format "%s %s? (default %s) " section name
                        (if (alist-get 'default spec) "yes" "no"))))
     ((member type '("ref" "refs"))
      (a3madkour-pub-author--ask-ref name spec prompt))
     ((member type '("text" "int" "date" "list"))
      (a3madkour-pub-author--ask-string name type required keyword-p prompt))
     (t (error "a3-publish-mark: no prompt for field %s of type %S" name type)))))

(provide 'a3madkour-publish-author)

;;; a3madkour-publish-author.el ends here
