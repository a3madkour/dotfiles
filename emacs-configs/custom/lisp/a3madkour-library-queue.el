;;; a3madkour-library-queue.el --- reading queue -> book item note  -*- lexical-binding: t; -*-
;;; Commentary:
;;; The reading queue (`queue.org') and the Boox round trip keep a BOOK's
;;; library item note in step: adding a book marks it `reading', toggling
;;; its entry inactive/active marks it `queued'/`reading', DONE/DROP mark
;;; it `finished'/`abandoned', and finishing or abandoning the note from
;;; `a3-library-status' closes its open queue entry.  Papers are never
;;; touched: an entry resolves to a note only when its bib type is a book
;;; or it carries a `:BOOX_KEY:', and only a note with a `LIBRARY_MEDIA_TYPE'
;;; is ever written.  Every step is additive and demotes its own errors, so
;;; a failure here never breaks the queue command that called it.
;;;
;;; The Boox helpers and `org-ref-notes' come from config.org; this module
;;; only declares them, so it loads in batch for its tests.
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)
(require 'a3madkour-publish-author)
(require 'a3madkour-library-items)

(defvar org-ref-notes)                       ; config.org: ref-note directory
(defvar a3madkour/reading-queue-wip-limit)   ; config.org: WIP limit defcustom
(defvar org-state)                           ; bound by `org-todo' for its hooks

(declare-function citar-get-entry "citar" (key))
(declare-function citar-create-note "citar" (key &optional entry))
(declare-function a3madkour/boox--slug "boox-core" (title &optional max-length))
(declare-function a3madkour/boox--book-key "boox-core" (file existing-keys))
(declare-function a3madkour/boox--all-known-keys "config" ())
(declare-function a3madkour/boox--ensure-book-note "config" (key source))
(declare-function a3madkour/boox--close-queue-entry "config" (key))

(defcustom a3madkour/library-book-bib-types '("book" "mvbook" "inbook")
  "Bib entry types (downcased `=type=') whose queue entries are books."
  :type '(repeat string) :group 'a3madkour)

(defvar a3madkour-library/queue-file nil
  "The reading queue file (config.org sets it to queue.org).")

(defvar a3madkour/library--syncing nil
  "Non-nil while this module writes the queue or a note.
The todo-state hook and `a3madkour/library-close-queue-entry' do nothing
while it is set, so closing an entry cannot re-enter the note sync.")

;; -- resolution --

(defun a3madkour/library--queue-file ()
  "The queue file, or a `user-error' when it is not configured."
  (or a3madkour-library/queue-file
      (user-error "a3madkour-library/queue-file is not set")))

(defun a3madkour/library--ref-note (key)
  "Existing ref-note file for KEY, or nil."
  (let ((file (expand-file-name (concat key ".org") org-ref-notes)))
    (and (file-exists-p file) file)))

(defun a3madkour/library--bib-book-p (entry)
  "Non-nil when citar bib ENTRY's `=type=' is a book type."
  (let ((type (alist-get "=type=" entry nil nil #'string=)))
    (and type (member (downcase type) a3madkour/library-book-bib-types) t)))

(defun a3madkour/queue-entry-note-file ()
  "The existing book note file for the queue heading at point, or nil.
`:CITEKEY:' resolves when its bib type is a book; else `:BOOX_KEY:'
resolves; a paper, or a key with no note on disk, gives nil."
  (let ((citekey (org-entry-get nil "CITEKEY"))
        (boox-key (org-entry-get nil "BOOX_KEY")))
    (cond
     ((and citekey
           (a3madkour/library--bib-book-p
            (and (fboundp 'citar-get-entry)
                 (ignore-errors (citar-get-entry citekey)))))
      (a3madkour/library--ref-note citekey))
     (boox-key (a3madkour/library--ref-note boox-key)))))

(defun a3madkour/library--set-note-status (file status)
  "Set book note FILE's STATUS and save it; nil when FILE is not a book item.
The guard is bound while the note is written."
  (when (and file
             (equal (alist-get "media_type" (a3madkour-library/properties file)
                               nil nil #'equal)
                    "book"))
    ;; Silenced so the queue command's own message stays in the echo area.
    (let ((a3madkour/library--syncing t)
          (inhibit-message t))
      (with-current-buffer (find-file-noselect file)
        (a3madkour-library/set-status status)
        (save-buffer)))
    status))

(defun a3madkour/library--write-book-fields (creator year)
  "Write `LIBRARY_MEDIA_TYPE' book, CREATOR and YEAR where each is blank."
  (dolist (field (list (cons "media_type" "book")
                       (cons "creator" creator)
                       (cons "year" year)))
    (when (and (cdr field) (not (string-empty-p (cdr field)))
               (not (a3madkour-pub-author--drawer-get (car field))))
      (a3madkour-pub-author--drawer-put (car field) (cdr field)))))

;; -- citar add --

(defun a3madkour/library-citar-add-book (key entry)
  "Mark citar KEY's note `reading' when bib ENTRY is a book; else do nothing.
Creates the note with `citar-create-note' when missing, then writes the
blank `LIBRARY_*' fields (book, author, year) and sets status `reading'.
Returns the note file, or nil for a paper."
  (when (a3madkour/library--bib-book-p entry)
    (with-demoted-errors "library: citar book step failed: %S"
      (let ((file (expand-file-name (concat key ".org") org-ref-notes))
            (year (let ((d (or (alist-get "date" entry nil nil #'string=)
                               (alist-get "year" entry nil nil #'string=))))
                    (and d (>= (length d) 4) (substring d 0 4)))))
        (unless (file-exists-p file)
          (save-window-excursion
            (save-current-buffer (citar-create-note key entry))))
        (let ((a3madkour/library--syncing t))
          (with-current-buffer (find-file-noselect file)
            (a3madkour/library--write-book-fields
             (or (alist-get "author" entry nil nil #'string=)
                 (alist-get "editor" entry nil nil #'string=))
             year)
            (a3madkour-library/set-status "reading")
            (save-buffer)))
        file))))

;; -- add a book without a bib entry --

(defun a3madkour/library--active-count ()
  "Number of `:active:' entries in the queue."
  (with-current-buffer (find-file-noselect (a3madkour/library--queue-file))
    (length (org-map-entries t "+active" 'file))))

(defun a3madkour/library--write-bare-book-note (key title)
  "Create the ref note for KEY titled TITLE, with no document; return it.
The shape of `a3madkour/boox--ensure-book-note' minus the document lines."
  (let ((file (expand-file-name (concat key ".org") org-ref-notes)))
    (unless (file-exists-p file)
      (with-current-buffer (find-file-noselect file)
        (insert (format ":PROPERTIES:\n:ID: %s\n:DATE_CREATED: %s\n:LAST_MODIFIED: %s\n:END:\n#+title: %s\n#+filetags: :Ref:Book:\n\n"
                        (org-id-new)
                        (format-time-string "[%Y-%m-%d %a]")
                        (format-time-string "[%Y-%m-%d %a]")
                        title))
        (save-buffer)))
    file))

;;;###autoload
(defun a3-reading-queue-add-book (title creator year &optional file)
  "Add the book TITLE by CREATOR (YEAR), read from FILE if given, to the queue.
Assigns a `:BOOX_KEY:' (from FILE, else from TITLE), creates the ref
note, marks it a `reading' book item, and appends an `:active:toread:'
entry.  Refuses at the reading-queue WIP limit.  Returns the note file."
  (interactive
   (list (a3madkour-library--read-required "Title: ")
         (string-trim (read-string "Creator: "))
         (string-trim (read-string "Year: "))
         (let ((f (string-trim (read-file-name "Book file (empty for none): "
                                               nil "" nil))))
           ;; RET on the prompt's bare directory means no file too.
           (cond ((or (string-empty-p f) (file-directory-p f)) nil)
                 ((file-regular-p f) f)
                 (t (user-error "No such file: %s" f))))))
  (let ((count (a3madkour/library--active-count))
        (limit a3madkour/reading-queue-wip-limit))
    (when (>= count limit)
      (user-error "Reading queue WIP limit reached (%d/%d active). Finish something first"
                  count limit))
    (let* ((source (and file (expand-file-name file)))
           (key (a3madkour/boox--book-key
                 (or source (concat (a3madkour/boox--slug title) ".title"))
                 (a3madkour/boox--all-known-keys)))
           (note (if source
                     (a3madkour/boox--ensure-book-note key source)
                   (a3madkour/library--write-bare-book-note key title)))
           (a3madkour/library--syncing t))
      (with-current-buffer (find-file-noselect note)
        (a3madkour-pub-author--upsert-keyword "title" title)
        (a3madkour/library--write-book-fields creator year)
        (a3madkour-library/set-status "reading")
        (save-buffer))
      (with-current-buffer (find-file-noselect (a3madkour/library--queue-file))
        (save-excursion
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (format "* TODO Read %s :active:toread:\n:PROPERTIES:\n:ENERGY: high\n:BOOX_KEY: %s\n%s:END:\n\n"
                          title key
                          (if source
                              (format ":READING_FILE: %s\n"
                                      (abbreviate-file-name source))
                            ""))))
        (save-buffer))
      (message "Added %s to reading queue (%d/%d active)" title (1+ count) limit)
      note)))

;; -- queue -> note --

(defun a3madkour/library-sync-on-toggle ()
  "After `toggle-active': mark the heading's book note `reading' or `queued'."
  (when (member "toread" (org-get-tags))
    (with-demoted-errors "library: toggle sync failed: %S"
      (a3madkour/library--set-note-status
       (a3madkour/queue-entry-note-file)
       (if (member "active" (org-get-tags)) "reading" "queued")))))

(defun a3madkour/library-sync-on-todo-change ()
  "On DONE/DROP of a `:toread:' entry, mark its book note finished/abandoned.
For `org-after-todo-state-change-hook'.  A finished date already set is
kept (`a3madkour-library/set-status' stamps only a blank one)."
  (let ((status (cdr (assoc org-state '(("DONE" . "finished")
                                        ("DROP" . "abandoned"))))))
    (when (and status
               (not a3madkour/library--syncing)
               (member "toread" (org-get-tags)))
      (with-demoted-errors "library: todo sync failed: %S"
        (a3madkour/library--set-note-status
         (a3madkour/queue-entry-note-file) status)))))

;; -- note -> queue --

(defun a3madkour/library--drop-queue-entry (key)
  "Mark every open queue entry for KEY as DROP and drop its `:active:' tag.
The DROP counterpart of `a3madkour/boox--close-queue-entry'.  Returns the
number of entries dropped."
  (let ((dropped 0))
    (with-current-buffer (find-file-noselect (a3madkour/library--queue-file))
      (org-map-entries
       (lambda ()
         (when (and (member key (list (org-entry-get nil "CITEKEY")
                                      (org-entry-get nil "BOOX_KEY")))
                    (not (member (org-get-todo-state) org-done-keywords)))
           (org-todo "DROP")
           (org-set-tags (delete "active" (org-get-tags nil t)))
           (setq dropped (1+ dropped))))
       nil 'file)
      (when (> dropped 0) (save-buffer)))
    dropped))

(defun a3madkour/library-close-queue-entry (file status)
  "Close FILE's queue entry when its book note becomes finished or abandoned.
For `a3madkour-library/status-changed-functions'.  Acts only on a book
item note in `org-ref-notes', whose basename is its queue key."
  (when (and (member status '("finished" "abandoned"))
             (not a3madkour/library--syncing)
             file
             (file-equal-p (file-name-directory file)
                           (file-name-as-directory org-ref-notes))
             (equal (alist-get "media_type" (a3madkour-library/properties file)
                               nil nil #'equal)
                    "book"))
    (let ((a3madkour/library--syncing t)
          (key (file-name-base file)))
      (if (equal status "finished")
          (a3madkour/boox--close-queue-entry key)
        (a3madkour/library--drop-queue-entry key)))))

(provide 'a3madkour-library-queue)
;;; a3madkour-library-queue.el ends here
