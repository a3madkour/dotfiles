;;; a3madkour-library-items.el --- library item notes  -*- lexical-binding: t; -*-
;;; Commentary:
;;; A library item is an org note whose file-level property drawer carries
;;; `:LIBRARY_MEDIA_TYPE:'.  This module reads its `LIBRARY_*' fields, stamps
;;; status and dates, cleans its tags, and extracts the `:site:' subtree --
;;; the only part of the note that may ever be published.
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'ox)                          ; `org-export-exclude-tags'
(require 'a3madkour-sections)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-library)
(require 'a3madkour-publish-author)
(require 'a3madkour-publish-rewrite)   ; link-scheme / asset-shape tests
(require 'a3madkour-publish-slug)
(require 'org-id)

(defcustom a3madkour-library/structural-tags '("Ref" "Book")
  "Org tags that structure the note rather than describe the item."
  :type '(repeat string) :group 'a3madkour-pub)

(defconst a3madkour-library--shelf-by-media
  '(("book" . "library/reading")
    ("album" . "library/listening") ("track" . "library/listening")
    ("game" . "library/playing")
    ("film" . "library/watching") ("series" . "library/watching"))
  "Media type -> library shelf section.")

(defconst a3madkour-library--core-fields
  '("media_type" "status" "creator" "year" "started" "finished" "preview")
  "Item fields read from `LIBRARY_<UPCASE>' file-level properties.")

(defmacro a3madkour-library--with-file (file &rest body)
  "Run BODY in a temp org buffer holding FILE's text."
  (declare (indent 1))
  `(with-temp-buffer
     (insert-file-contents ,file)
     (delay-mode-hooks (org-mode))
     ,@body))

(defun a3madkour-library/shelf-for (media-type)
  "Library shelf section for MEDIA-TYPE, or nil when unknown."
  (cdr (assoc media-type a3madkour-library--shelf-by-media)))

(defun a3madkour-library/statuses (media-type)
  "Allowed status words for MEDIA-TYPE's shelf."
  (a3madkour-sections/enum (a3madkour-library/shelf-for media-type) "status"))

(defun a3madkour-library/in-progress-status (media-type)
  "The in-progress status word for MEDIA-TYPE (reading, listening, ...)."
  (file-name-nondirectory (a3madkour-library/shelf-for media-type)))

(defun a3madkour-library/item-p (file)
  "Non-nil when FILE's drawer has a non-blank `LIBRARY_MEDIA_TYPE'."
  (a3madkour-library--with-file file
    (and (a3madkour-pub-author--drawer-get "media_type") t)))

(defun a3madkour-library/properties (file)
  "Alist of FILE's non-blank `LIBRARY_*' core fields, plus `(extras . PLIST)'.
Only the `LIBRARY_'-prefixed drawer keys are read; extras are the
per-medium keys of `a3madkour-pub-library/extras-for' (int-coerced)."
  (a3madkour-library--with-file file
    (let (alist extras
          (media (a3madkour-pub-author--drawer-get "media_type")))
      (dolist (f a3madkour-library--core-fields)
        (let ((v (a3madkour-pub-author--drawer-get f)))
          (when v (push (cons f v) alist))))
      (dolist (entry (a3madkour-pub-library/extras-for media))
        (let ((raw (a3madkour-pub-author--drawer-get (nth 0 entry))))
          (when raw
            (setq extras (plist-put extras (nth 1 entry)
                                    (if (eq (nth 2 entry) 'int)
                                        (string-to-number raw)
                                      raw))))))
      (nreverse (if extras (cons (cons 'extras extras) alist) alist)))))

(defun a3madkour-library/set-status (status &optional today)
  "Set the current buffer's item STATUS, stamping started/finished once.
Signals `user-error' unless STATUS is valid for the note's shelf.  TODAY
is a YYYY-MM-DD string, default today.  Returns STATUS."
  (let* ((mt (a3madkour-pub-author--drawer-get "media_type"))
         (valid (and mt (a3madkour-library/shelf-for mt)
                     (a3madkour-library/statuses mt)))
         (today (or today (format-time-string "%Y-%m-%d"))))
    (unless (member status valid)
      (user-error "Status %S is not valid for %S (use one of %S)" status mt valid))
    (a3madkour-pub-author--drawer-put "status" status)
    (when (and (equal status (a3madkour-library/in-progress-status mt))
               (not (a3madkour-pub-author--drawer-get "started")))
      (a3madkour-pub-author--drawer-put "started" today))
    (when (and (member status '("finished" "100pct"))
               (not (a3madkour-pub-author--drawer-get "finished")))
      (a3madkour-pub-author--drawer-put "finished" today))
    status))

(defun a3madkour-library--kebab (tag)
  "TAG as lowercase kebab-case, or nil when it cannot be made a clean slug."
  (let* ((case-fold-search nil)
         (s (replace-regexp-in-string
             "\\([a-z0-9]\\)\\([A-Z]\\)" "\\1-\\2" tag t))
         (s (replace-regexp-in-string
             "\\([A-Z]+\\)\\([A-Z][a-z]\\)" "\\1-\\2" s t))
         (s (replace-regexp-in-string "[_ ]" "-" s t))
         (s (replace-regexp-in-string "-+" "-" (downcase s) t)))
    (and (string-match-p "\\`[a-z0-9][a-z0-9-]*\\'" s) s)))

(defun a3madkour-library/clean-tags (tags)
  "TAGS minus editorial and structural tags, kebab-cased, de-duplicated.
A tag that is not a clean slug after kebab-casing is dropped."
  (let ((kept (cl-remove-if
               (lambda (tag) (member tag a3madkour-library/structural-tags))
               (a3madkour-pub-frontmatter/filter-editorial-tags tags))))
    (delete-dups (delq nil (mapcar #'a3madkour-library--kebab kept)))))

(defconst a3madkour-library--drawer-re
  "^[ \t]*:[A-Za-z0-9_-]+:[ \t]*\n\\(?:.*\n\\)*?[ \t]*:END:[ \t]*\\(?:\n\\|\\'\\)"
  "A whole org drawer, from its `:NAME:' line through `:END:'.")

(defconst a3madkour-library--planning-re
  "[ \t]*\\(?:SCHEDULED\\|DEADLINE\\|CLOSED\\):.*\n"
  "A planning line.")

(defun a3madkour-library--excluded-heading-p ()
  "Non-nil when the heading at point never exports.
That is a COMMENT heading, or one whose own tags include `ARCHIVE'
\(`org-archive-tag') or any of `org-export-exclude-tags'."
  (save-excursion
    (save-match-data
      (beginning-of-line)
      (or (let ((case-fold-search nil))
            (looking-at "\\*+ COMMENT\\(?: \\|$\\)"))
          (cl-intersection (org-get-tags nil t)
                           (cons org-archive-tag org-export-exclude-tags)
                           :test #'equal)))))

(defun a3madkour-library/site-heading-region ()
  "Body region (BEG . END) of the first level-1 `:site:' heading, or nil.
An excluded heading (`--excluded-heading-p': COMMENT, ARCHIVE or an
export-exclude tag such as `noexport') never counts.  The body follows the
heading line, its planning line and any drawers, and ends at the next
level-1 heading or the end of the buffer."
  (save-excursion
    (save-match-data
      (goto-char (point-min))
      (let ((case-fold-search nil) found)
        (while (and (not found)
                    (re-search-forward "^\\* .*$" nil t))
          (when (and (not (a3madkour-library--excluded-heading-p))
                     (member "site" (org-get-tags nil t)))
            (setq found t)))
        (when found
          (forward-line 1)
          (when (looking-at a3madkour-library--planning-re)
            (goto-char (match-end 0)))
          (while (looking-at a3madkour-library--drawer-re)
            (goto-char (match-end 0)))
          (let ((beg (point)))
            (cons beg (if (re-search-forward "^\\* " nil t)
                          (match-beginning 0)
                        (point-max)))))))))

(defconst a3madkour-library--comment-block-re
  "^[ \t]*#\\+begin_comment\\b.*\n\\(?:.*\n\\)*?[ \t]*#\\+end_comment\\b.*\\(?:\n\\|\\'\\)"
  "A whole `#+begin_comment' ... `#+end_comment' block (match ignoring case).")

(defconst a3madkour-library--comment-line-re
  "^[ \t]*#\\(?:[ \t].*\\)?\\(?:\n\\|\\'\\)"
  "An org comment line: `#' alone or followed by whitespace.")

(defun a3madkour-library--publishable (text)
  "TEXT minus every drawer, comment and excluded subtree.
Comments are `# ...' lines and `#+begin_comment' blocks; excluded
subtrees are those `--excluded-heading-p' names."
  (with-temp-buffer
    (insert text)
    (delay-mode-hooks (org-mode))
    (let ((case-fold-search nil))
      (goto-char (point-min))
      (while (re-search-forward a3madkour-library--drawer-re nil t)
        (replace-match ""))
      (let ((case-fold-search t))
        (goto-char (point-min))
        (while (re-search-forward a3madkour-library--comment-block-re nil t)
          (replace-match "")))
      (goto-char (point-min))
      (while (re-search-forward a3madkour-library--comment-line-re nil t)
        ;; In a src/example/export block a `# ' line is content, not a comment.
        (unless (save-match-data
                  (save-excursion
                    (goto-char (match-beginning 0))
                    (org-in-block-p '("src" "example" "export"))))
          (replace-match "")))
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*+\\) .*$" nil t)
        (let ((level (length (match-string 1)))
              (beg (match-beginning 0)))
          (if (a3madkour-library--excluded-heading-p)
              (progn
                (goto-char beg)
                (forward-line 1)
                (if (re-search-forward
                     (format "^\\*\\{1,%d\\} " level) nil t)
                    (delete-region beg (match-beginning 0))
                  (delete-region beg (point-max)))
                (goto-char beg))
            (forward-line 1)))))
    (buffer-string)))

(defun a3madkour-library/site-body (file)
  "Text of FILE's `:site:' section, or nil when absent or blank.
Drawers and noexport or COMMENT sub-trees are removed, so the result is
safe to treat as publishable."
  (a3madkour-library--with-file file
    (let ((r (a3madkour-library/site-heading-region)))
      (when r
        (let ((s (string-trim (a3madkour-library--publishable
                               (buffer-substring-no-properties (car r) (cdr r))))))
          (and (not (string-empty-p s)) s))))))

(defconst a3madkour-library--link-re
  "\\[\\[\\([^][]+\\)\\(\\]\\[[^][]+\\)?\\]\\]"
  "An org bracket link: group 1 the path, group 2 the `][desc' part.")

(defun a3madkour-library--absolute-link-path (path dir)
  "PATH made absolute against DIR when it is a relative file path, else PATH.
A `file:' path and a scheme-less path that is `./'/`../'-relative or
asset-shaped are relative file paths.  `./assets/' is left as is: it is
an alias for the canonical asset root, not a path under DIR."
  (let ((file-p (string-prefix-p "file:" path)))
    (let ((p (if file-p (substring path 5) path)))
      (if (and (not (string-prefix-p "./assets/" p))
               (not (file-name-absolute-p p))
               (or file-p
                   (and (not (a3madkour-pub--link-scheme p))
                        (or (string-match-p "\\`\\.\\.?/" p)
                            (a3madkour-pub--asset-shaped-link-p p)))))
          (concat (if file-p "file:" "") (expand-file-name p dir))
        path))))

(defconst a3madkour-library--copy-keyword-re
  "\\`\\(?:TITLE\\|FILETAGS\\|DATE\\|HUGO_.+\\)\\'"
  "Preamble keywords the site-only copy keeps (matched ignoring case).
Anything else may carry private text into the export: `#+hugo:', `#+html:'
and `#+md:' emit their value verbatim, `#+caption:', `#+name:' and
`#+attr_*:' attach to the first site element, `#+setupfile:' and
`#+include:' pull other files in.")

(defconst a3madkour-library--copy-property-re
  "\\`\\(?:ID\\|ROAM_REFS\\|LIBRARY_.+\\)\\'"
  "File-drawer properties the site-only copy keeps (matched ignoring case).")

(defun a3madkour-library--copy-drawer (drawer)
  "DRAWER (a `:PROPERTIES:' block's text) keeping only allowlisted properties."
  (let ((case-fold-search t))
    (mapconcat
     (lambda (line)
       (if (and (string-match "\\`[ \t]*:\\([^: \t\n]+\\):" line)
                (or (member (upcase (match-string 1 line)) '("PROPERTIES" "END"))
                    (string-match-p a3madkour-library--copy-property-re
                                    (match-string 1 line))))
           (concat line "\n")
         ""))
     (split-string drawer "\n" t)
     "")))

(defun a3madkour-library--drop-includes (body file)
  "BODY without its `#+INCLUDE:' lines, warning (against FILE) for each."
  (let ((case-fold-search t))
    (replace-regexp-in-string
     "^[ \t]*#\\+include:.*\\(?:\n\\|\\'\\)"
     (lambda (line)
       (save-match-data
         (a3madkour-pub/warn "library" file
                             "dropped #+INCLUDE from the :site: section: %s"
                             (string-trim line)))
       "")
     body t t)))

(defun a3madkour-library/site-only-copy (file)
  "Write a temp `.org' holding only what FILE may publish; return its path.
The copy is FILE's file-level drawer (only `ID', `ROAM_REFS' and
`LIBRARY_*'), its preamble `TITLE', `FILETAGS', `DATE' and `HUGO_*'
keywords, and its `:site:' body minus any `#+INCLUDE:' (warned), with
relative link paths made absolute against FILE's directory so links and
assets resolve as they would from FILE.  Fuzzy and `#custom-id' links
from the site body to private headings do not resolve in the copy and
fail at export (fail closed).  It lives in `temporary-file-directory',
never beside FILE.  The caller deletes it.
Signals an error when FILE has no usable `:site:' section."
  (let ((body (a3madkour-library--drop-includes
               (or (a3madkour-library/site-body file)
                   (error "%s: library item has no :site: section" file))
               file))
        (dir (file-name-directory (expand-file-name file)))
        head)
    (a3madkour-library--with-file file
      (goto-char (point-min))
      (let ((end (save-excursion
                   (if (re-search-forward "^\\*+ " nil t)
                       (match-beginning 0)
                     (point-max))))
            (case-fold-search t))
        (when (looking-at a3madkour-library--drawer-re)
          (push (a3madkour-library--copy-drawer (match-string-no-properties 0))
                head)
          (goto-char (match-end 0)))
        (while (re-search-forward "^[ \t]*#\\+\\([A-Za-z0-9_-]+\\):.*$" end t)
          (when (string-match-p a3madkour-library--copy-keyword-re (match-string 1))
            (push (concat (match-string-no-properties 0) "\n") head)))))
    (let ((tmp (make-temp-file
                (expand-file-name "a3-pub-site-only-" temporary-file-directory)
                nil ".org")))
      (with-temp-file tmp
        (insert (apply #'concat (nreverse head)) "\n" body "\n")
        (goto-char (point-min))
        (while (re-search-forward a3madkour-library--link-re nil t)
          ;; The path test runs `string-match', so take the bounds first.
          (let ((beg (match-beginning 0))
                (end (match-end 0))
                (path (match-string 1))
                (desc (or (match-string 2) "")))
            (delete-region beg end)
            (goto-char beg)
            (insert "[[" (a3madkour-library--absolute-link-path path dir)
                    desc "]]"))))
      tmp)))

(defun a3madkour-library--strip-emphasis (s)
  "S without org emphasis markers around words."
  (replace-regexp-in-string
   "\\([ \t\n(]\\|\\`\\)[*/_=~+]\\([^ \t\n][^\n]*?[^ \t\n]\\|[^ \t\n]\\)[*/_=~+]\\([ \t\n.,;:!?)]\\|\\'\\)"
   "\\1\\2\\3" s))

(defun a3madkour-library/preview (file)
  "FILE's `LIBRARY_PREVIEW', else the first sentence of its site body."
  (or (a3madkour-library--with-file file
        (a3madkour-pub-author--drawer-get "preview"))
      (let ((body (a3madkour-library/site-body file)))
        (when body
          (let* ((s (replace-regexp-in-string
                     "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" body))
                 (s (replace-regexp-in-string
                      "\\[\\[\\(https?://[^]]*\\)\\]\\]" "\\1" s))
                 (s (replace-regexp-in-string "\\[\\[[^]]*\\]\\]" "" s))
                 (s (a3madkour-library--strip-emphasis s))
                 (s (string-trim (replace-regexp-in-string "[ \t\n]+" " " s))))
            (if (string-match "\\`.*?[.!?]\\(?:[ \t\n]\\|\\'\\)" s)
                (string-trim (match-string 0 s))
              s))))))

;; -- interactive commands --

(defvar a3madkour-library/notes-dir
  (if (boundp 'org-roam-directory) org-roam-directory "~/org/notes/")
  "Directory `a3-library-add' creates item notes in.")

(defvar a3madkour-library/status-changed-functions nil
  "Abnormal hook run with (FILE STATUS) after `a3-library-status' saves.")

(defun a3madkour-library--require-org (command)
  "Signal a `user-error' unless the current buffer is an org buffer for COMMAND."
  (unless (derived-mode-p 'org-mode)
    (user-error "%s: current buffer is not org-mode" command)))

(defun a3madkour-library--require-item (command)
  "Signal a `user-error' unless the current buffer is a library item note."
  (a3madkour-library--require-org command)
  (unless (a3madkour-pub-author--drawer-get "media_type")
    (user-error "%s: this note is not a library item (no LIBRARY_MEDIA_TYPE)"
                command)))

(defun a3madkour-library--read-required (prompt &optional digits)
  "Read a non-empty string with PROMPT, re-prompting; DIGITS demands digits."
  (let (v)
    (while (let ((raw (string-trim (read-string prompt))))
             (setq v raw)
             (or (string-empty-p raw)
                 (and digits (not (string-match-p "\\`[0-9]+\\'" raw)))))
      (message "%s" (if digits "Enter digits only" "A value is required"))
      (sit-for 0))
    v))

;;;###autoload
(defun a3-library-add ()
  "Create a library item note and visit it.
Prompts for media type, title, creator, year and status, writes
`<notes-dir>/<slug>.org' (file-level drawer first, then the title and an
empty `* Notes :site:' heading) and stamps the dates via `set-status'.
Refuses when the file already exists."
  (interactive)
  (let* ((media (completing-read "Media type: "
                                 (mapcar #'car a3madkour-library--shelf-by-media)
                                 nil t))
         (title (a3madkour-library--read-required "Title: "))
         (creator (a3madkour-library--read-required "Creator: "))
         (year (a3madkour-library--read-required "Year: " t))
         (slug (a3madkour-pub-slug/slugify title))
         (file (expand-file-name (concat slug ".org") a3madkour-library/notes-dir)))
    (when (string-empty-p slug)
      (user-error "a3-library-add: title %S yields an empty slug" title))
    (when (file-exists-p file)
      (user-error "a3-library-add: %s already exists" file))
    (let ((status (completing-read
                   "Status: " (a3madkour-library/statuses media) nil t nil nil
                   (if (equal media "film") "finished"
                     (a3madkour-library/in-progress-status media)))))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert (format ":PROPERTIES:\n:ID: %s\n:LIBRARY_MEDIA_TYPE: %s\n:LIBRARY_CREATOR: %s\n:LIBRARY_YEAR: %s\n:END:\n#+title: %s\n\n* Notes :site:\n"
                        (org-id-new) media creator year title)))
      (find-file file)
      (a3madkour-library/set-status status)
      (save-buffer)
      file)))

;;;###autoload
(defun a3-library-status ()
  "Set the current item note's status, then run `status-changed-functions'."
  (interactive)
  (a3madkour-library--require-item "a3-library-status")
  (let* ((mt (a3madkour-pub-author--drawer-get "media_type"))
         (status (completing-read
                  "Status: " (a3madkour-library/statuses mt) nil t nil nil
                  (a3madkour-pub-author--drawer-get "status"))))
    (a3madkour-library/set-status status)
    (save-buffer)
    (run-hook-with-args 'a3madkour-library/status-changed-functions
                        buffer-file-name status)
    status))

;;;###autoload
(defun a3-library-share ()
  "Share the current item note by marking it for the garden.
An item with no `:site:' section only offers to insert one; write it,
then share again."
  (interactive)
  (a3madkour-library--require-item "a3-library-share")
  (when (and buffer-file-name (buffer-modified-p)) (save-buffer))
  (unless (and buffer-file-name (a3madkour-library/site-body buffer-file-name))
    (when (a3madkour-library/site-heading-region)
      (user-error "the :site: section is empty; write it, then share again"))
    (when (y-or-n-p "No :site: section; insert `* Notes :site:'? ")
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "* Notes :site:\n"))
    (user-error "write the :site: section, then share again"))
  (a3-publish-mark "garden"))

;;;###autoload
(defun a3-library-unshare ()
  "Stop publishing the current item note (`#+HUGO_PUBLISH: nil')."
  (interactive)
  (a3madkour-library--require-item "a3-library-unshare")
  (a3-publish-unmark))

(provide 'a3madkour-library-items)
;;; a3madkour-library-items.el ends here
