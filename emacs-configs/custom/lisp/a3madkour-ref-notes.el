;;; a3madkour-ref-notes.el --- find a ref note by its key  -*- lexical-binding: t; -*-
;;; Commentary:
;;; A ref note's filename is not its identity.  New notes are created as
;;; `<key>.org', but the rename-to-title save hook in config.org renames a
;;; note to its title's slug on its first save, so a lookup by filename
;;; loses the note and the next step creates a duplicate.  A note is found
;;; by the keys its file-level drawer declares -- every citekey in
;;; `:ROAM_REFS:' and its `:BOOX_KEY:' -- with `<key>.org' checked first.
;;;
;;; Also here: the org tags a new citar note gets from its bib keywords.
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar org-ref-notes)                  ; config.org: ref-note directory

(defconst a3madkour-ref-notes--head-bytes 8192
  "How much of a note is read to find its file-level drawer.")

;; -- keys --

(defun a3madkour-ref-notes/ref-keys (refs)
  "Citekeys in the `:ROAM_REFS:' value REFS, in order.
Reads `@key', `cite:key', `cite:&key' and `[cite:@key]'; URLs and
other refs are skipped.  Nil for a nil REFS."
  (delq nil
        (mapcar (lambda (tok)
                  (cond ((string-match "\\`\\[?cite:[@&]?\\([^];[:space:]]+\\)\\]?\\'" tok)
                         (match-string 1 tok))
                        ((string-match "\\`@\\([^[:space:]]+\\)\\'" tok)
                         (match-string 1 tok))))
                (split-string (or refs "") "[[:space:]]+" t))))

(defun a3madkour-ref-notes--drawer (file)
  "FILE's file-level drawer keys as (BOOX-KEY . CITEKEYS), or nil.
Only a `:PROPERTIES:' drawer opening the file counts; a heading's
drawer belongs to that heading, not to the file."
  (with-temp-buffer
    (insert-file-contents file nil 0 a3madkour-ref-notes--head-bytes)
    (goto-char (point-min))
    (skip-chars-forward " \t\n")
    (let ((case-fold-search t))
      (when (looking-at "[ \t]*:PROPERTIES:[ \t]*$")
        (let ((end (save-excursion
                     (and (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                          (point))))
              boox refs)
          (when end
            (while (re-search-forward
                    "^[ \t]*:\\(ROAM_REFS\\|BOOX_KEY\\):[ \t]*\\(.*?\\)[ \t]*$" end t)
              (if (string-equal (upcase (match-string 1)) "BOOX_KEY")
                  (unless (string-empty-p (match-string 2))
                    (setq boox (match-string 2)))
                (setq refs (append refs (a3madkour-ref-notes/ref-keys
                                         (match-string 2))))))
            (cons boox refs)))))))

(defun a3madkour-ref-notes/key (file)
  "The key ref note FILE is filed under.
Its `:BOOX_KEY:', else the first citekey in its `:ROAM_REFS:', else its
basename (a note created as `<key>.org' and never renamed)."
  (let ((drawer (a3madkour-ref-notes--drawer file)))
    (or (car drawer) (cadr drawer) (file-name-base file))))

;; -- lookup --

(defun a3madkour-ref-notes/index (&optional dir)
  "Hash table KEY -> ref-note files in DIR whose drawer declares KEY.
DIR defaults to `org-ref-notes'.  Files are in name order."
  (let ((index (make-hash-table :test #'equal))
        (dir (or dir org-ref-notes)))
    (when (and dir (file-directory-p dir))
      (dolist (file (directory-files dir t "\\`[^.].*\\.org\\'"))
        (when (file-regular-p file)
          (let ((drawer (a3madkour-ref-notes--drawer file)))
            (dolist (key (delete-dups (delq nil (cons (car drawer) (cdr drawer)))))
              (puthash key (append (gethash key index) (list file)) index))))))
    index))

(defun a3madkour-ref-notes/new-file (key &optional dir)
  "The file a new ref note for KEY is created as: `<key>.org' in DIR."
  (expand-file-name (concat key ".org") (or dir org-ref-notes)))

(defun a3madkour-ref-notes/file (key &optional dir)
  "The existing ref note for KEY in DIR (default `org-ref-notes'), or nil.
`<key>.org' when it exists; else the note whose drawer declares KEY.
When several do, says so and returns the first by name."
  (let ((named (a3madkour-ref-notes/new-file key dir)))
    (if (file-exists-p named)
        named
      (let ((hits (gethash key (a3madkour-ref-notes/index dir))))
        (when (cdr hits)
          (message "ref-notes: %d notes declare %s: %s; using %s"
                   (length hits) key
                   (mapconcat #'file-name-nondirectory hits ", ")
                   (file-name-nondirectory (car hits))))
        (car hits)))))

;; -- citar notes source --

(defun a3madkour-ref-notes/citar-items (&optional keys)
  "Ref-note files for citar KEYS, as a citar notes source's `:items'.
A hash table KEY -> files: each note under every key its drawer
declares and under its basename.  With KEYS, only those keys."
  (let ((index (a3madkour-ref-notes/index))
        (dir org-ref-notes))
    (when (and dir (file-directory-p dir))
      (dolist (file (directory-files dir t "\\`[^.].*\\.org\\'"))
        (let ((base (file-name-base file)))
          (unless (member file (gethash base index))
            (puthash base (append (gethash base index) (list file)) index)))))
    (if (null keys)
        index
      (let ((out (make-hash-table :test #'equal)))
        (dolist (key keys out)
          (when-let* ((files (gethash key index)))
            (puthash key files out)))))))

(defun a3madkour-ref-notes/citar-hasitems ()
  "A citar notes source's `:hasitems': a predicate on citekeys, or nil
when there are no notes at all."
  (let ((notes (a3madkour-ref-notes/citar-items)))
    (unless (hash-table-empty-p notes)
      (lambda (key) (and (gethash key notes) t)))))

;; -- tags --

(defun a3madkour-ref-notes/keyword-tags (keywords)
  "Org tags for the bib KEYWORDS field (comma- or semicolon-separated).
Each subject becomes one CamelCase tag with its parenthetical qualifier
dropped (\"Programming languages (Electronic computers)\" ->
ProgrammingLanguages); zotlib's `zotlib/...' import bookkeeping is
dropped; duplicates (ignoring case) are kept once."
  (let (tags)
    (dolist (kw (split-string (or keywords "") "[,;]" t "[[:space:]]+"))
      (unless (string-match-p "\\`zotlib\\(?:/\\|\\'\\)" kw)
        (let ((tag (mapconcat #'upcase-initials
                              (split-string
                               (replace-regexp-in-string "[[:space:]]*([^)]*)" "" kw)
                               "[^[:alnum:]]+" t)
                              "")))
          (unless (or (string-empty-p tag) (member-ignore-case tag tags))
            (push tag tags)))))
    (nreverse tags)))

(defun a3madkour-ref-notes/filetags (keywords book-p)
  "The `#+filetags:' value for a new ref note: Ref, Book when BOOK-P,
then KEYWORDS' tags (`keyword-tags'), each once."
  (let ((tags (append (list "Ref") (and book-p (list "Book")))))
    (dolist (tag (a3madkour-ref-notes/keyword-tags keywords))
      (unless (member-ignore-case tag tags)
        (setq tags (append tags (list tag)))))
    (concat ":" (mapconcat #'identity tags ":") ":")))

(provide 'a3madkour-ref-notes)
;;; a3madkour-ref-notes.el ends here
