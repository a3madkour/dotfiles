;;; a3madkour-library-queue-test.el --- tests for -library-queue.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the reading-queue <-> book item note glue.  The Boox
;;; helpers that live in config.el are replaced by copies of their
;;; config.org definitions, pointed at the test queue; `boox-core.el' (the
;;; tangled pure helpers) is loaded from the Emacs dir when present.
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-sections-fixture)
(require 'a3madkour-library-queue)

(defvar org-ref-notes)
(defvar a3madkour/reading-queue-wip-limit)

(defconst a3madkour-library-queue-test--boox-core
  (expand-file-name "../boox-core.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The tangled Boox pure helpers (an untracked build artifact).")

(when (file-exists-p a3madkour-library-queue-test--boox-core)
  (load a3madkour-library-queue-test--boox-core nil t))

;; -- copies of the config.el Boox helpers, against the test queue --

(defun a3madkour-library-queue-test--close-queue-entry (key)
  "`a3madkour/boox--close-queue-entry' as config.org defines it."
  (let ((closed 0))
    (with-current-buffer (find-file-noselect a3madkour-library/queue-file)
      (org-map-entries
       (lambda ()
         (when (and (member key (list (org-entry-get nil "CITEKEY")
                                      (org-entry-get nil "BOOX_KEY")))
                    (not (equal (org-get-todo-state) "DONE")))
           (org-todo "DONE")
           (org-set-tags (delete "active" (org-get-tags nil t)))
           (setq closed (1+ closed))))
       nil 'file)
      (when (> closed 0) (save-buffer)))
    closed))

(defun a3madkour-library-queue-test--ensure-book-note (key source)
  "`a3madkour/boox--ensure-book-note' as config.org defines it."
  (let ((file (expand-file-name (concat key ".org") org-ref-notes)))
    (unless (file-exists-p file)
      (with-current-buffer (find-file-noselect file)
        (insert (format ":PROPERTIES:\n:ID: %s\n:NOTER_DOCUMENT: %s\n:ORIGINAL_DOCUMENT: %s\n:DATE_CREATED: %s\n:LAST_MODIFIED: %s\n:END:\n#+title: %s\n#+filetags: :Ref:Book:\n\n"
                        (org-id-new) source source
                        (format-time-string "[%Y-%m-%d %a]")
                        (format-time-string "[%Y-%m-%d %a]")
                        (file-name-base source)))
        (save-buffer)))
    file))

(defun a3madkour-library-queue-test--note-for-key (key)
  "`a3madkour/boox--note-for-key' as config.org defines it (no citar)."
  (let ((citar-note (expand-file-name (concat key ".org") org-ref-notes)))
    (if (file-exists-p citar-note) citar-note
      (a3madkour-library-queue-test--ensure-book-note key "unused"))))

(defun a3madkour-library-queue-test--known-keys ()
  "`a3madkour/boox--all-known-keys' with an empty bibliography."
  (with-current-buffer (find-file-noselect a3madkour-library/queue-file)
    (delq nil (org-map-entries
               (lambda () (org-entry-get nil "BOOX_KEY")) nil 'file))))

(defvar a3madkour-library-queue-test--bib nil
  "Alist KEY -> citar entry served by the `citar-get-entry' stub.")

(defvar a3madkour-library-queue-test--created nil
  "Keys `citar-create-note' was called with.")

(defun a3madkour-library-queue-test--create-note (key &optional _entry)
  "Stand-in for `citar-create-note': a citar-shaped ref note, unsaved."
  (push key a3madkour-library-queue-test--created)
  (with-current-buffer (find-file-noselect
                        (expand-file-name (concat key ".org") org-ref-notes))
    ;; citar's default title template is "${author editor}, ${title}".
    (insert (format ":PROPERTIES:\n:ID: %s\n:ROAM_REFS: @%s\n:END:\n#+title: Example Author, Example\n#+filetags: :Ref:\n\n" (org-id-new) key))))

(defmacro a3madkour-library-queue-test--with-env (queue &rest body)
  "Run BODY with a temp queue.org holding QUEUE and an empty ref-notes dir."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "lib-queue-" t))
          (a3madkour-library/queue-file (expand-file-name "queue.org" dir))
          (org-ref-notes (file-name-as-directory (expand-file-name "ref-notes" dir)))
          (a3madkour/reading-queue-wip-limit 5)
          (a3madkour-library-queue-test--created nil)
          (org-todo-keywords '((sequence "TODO" "NEXT" "WAIT" "|" "DONE" "DROP")))
          (org-log-done nil)
          (org-todo-log-states nil)
          (org-after-todo-state-change-hook
           (list #'a3madkour/library-sync-on-todo-change))
          (a3madkour-library/status-changed-functions
           (list #'a3madkour/library-close-queue-entry)))
     (make-directory org-ref-notes t)
     (with-temp-file a3madkour-library/queue-file (insert ,queue))
     (unwind-protect
         (cl-letf (((symbol-function 'citar-get-entry)
                    (lambda (key)
                      (cdr (assoc key a3madkour-library-queue-test--bib))))
                   ((symbol-function 'citar-create-note)
                    #'a3madkour-library-queue-test--create-note)
                   ((symbol-function 'a3madkour/boox--close-queue-entry)
                    #'a3madkour-library-queue-test--close-queue-entry)
                   ((symbol-function 'a3madkour/boox--ensure-book-note)
                    #'a3madkour-library-queue-test--ensure-book-note)
                   ((symbol-function 'a3madkour/boox--all-known-keys)
                    #'a3madkour-library-queue-test--known-keys))
           ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (string-prefix-p dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory dir t))))

(defun a3madkour-library-queue-test--read (file)
  "FILE's text."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun a3madkour-library-queue-test--drawer (file field)
  "FILE's `LIBRARY_<FIELD>' value."
  (alist-get field (a3madkour-library/properties file) nil nil #'equal))

(defun a3madkour-library-queue-test--at-entry (key fn)
  "Call FN at the queue heading whose CITEKEY or BOOX_KEY is KEY."
  (with-current-buffer (find-file-noselect a3madkour-library/queue-file)
    (goto-char (point-min))
    (re-search-forward (format "^:\\(?:CITEKEY\\|BOOX_KEY\\): %s$" (regexp-quote key)))
    (org-back-to-heading t)
    (funcall fn)))

(defun a3madkour-library-queue-test--book-note (key status)
  "Write a book item note for KEY with STATUS; return its file."
  (let ((f (expand-file-name (concat key ".org") org-ref-notes)))
    (with-temp-file f
      (insert (format ":PROPERTIES:\n:ID: x\n:LIBRARY_MEDIA_TYPE: book\n:LIBRARY_STATUS: %s\n:END:\n#+title: Example 1\n" status)))
    f))

(defconst a3madkour-library-queue-test--book-entry
  "* TODO Read Example 1 :active:toread:\n:PROPERTIES:\n:BOOX_KEY: ex1\n:END:\n"
  "A queue entry for the book note `ex1'.")

(defconst a3madkour-library-queue-test--bib-book
  '(("ex1" . (("=type=" . "Book") ("title" . "Example 1")
              ("author" . "Example Author") ("date" . "1999-04-01")))
    ("ex2" . (("=type=" . "article") ("title" . "Example 2")
              ("author" . "Example Author") ("date" . "2001")))))

;; -- citar add --

(ert-deftest a3madkour-library-queue-test/citar-book-sets-reading ()
  (a3madkour-library-queue-test--with-env ""
    (let* ((a3madkour-library-queue-test--bib a3madkour-library-queue-test--bib-book)
           (file (a3madkour/library-citar-add-book
                  "ex1" (cdr (assoc "ex1" a3madkour-library-queue-test--bib)))))
      (should (equal file (expand-file-name "ex1.org" org-ref-notes)))
      (should (equal a3madkour-library-queue-test--created '("ex1")))
      (should (equal (a3madkour-library-queue-test--drawer file "media_type") "book"))
      (should (equal (a3madkour-library-queue-test--drawer file "creator") "Example Author"))
      (should (equal (a3madkour-library-queue-test--drawer file "year") "1999"))
      (should (equal (a3madkour-library-queue-test--drawer file "status") "reading"))
      (should (a3madkour-library-queue-test--drawer file "started"))
      ;; The citar preamble's drawer is kept, with the fields added to it.
      (should (string-match-p "\\`:PROPERTIES:\n:ID: .*\n:ROAM_REFS: @ex1\n"
                              (a3madkour-library-queue-test--read file))))))

(ert-deftest a3madkour-library-queue-test/citar-paper-untouched ()
  (let ((queue "* TODO Read Example 2 (2001) :active:toread:\n:PROPERTIES:\n:ENERGY: high\n:CITEKEY: ex2\n:AUTHOR: Example Author\n:END:\n[cite:@ex2]\n\n"))
    (a3madkour-library-queue-test--with-env queue
      (let* ((a3madkour-library-queue-test--bib a3madkour-library-queue-test--bib-book)
             (note (expand-file-name "ex2.org" org-ref-notes)))
        (with-temp-file note (insert "#+title: Example 2\n"))
        (should-not (a3madkour/library-citar-add-book
                     "ex2" (cdr (assoc "ex2" a3madkour-library-queue-test--bib))))
        (should-not a3madkour-library-queue-test--created)
        (should (equal (a3madkour-library-queue-test--read note) "#+title: Example 2\n"))
        (should (equal (a3madkour-library-queue-test--read a3madkour-library/queue-file)
                       queue))
        ;; Nor does the paper's queue entry resolve to a note.
        (a3madkour-library-queue-test--at-entry
         "ex2" (lambda () (should-not (a3madkour/queue-entry-note-file))))
        ;; DONE on the paper writes nothing.
        (a3madkour-library-queue-test--at-entry "ex2" (lambda () (org-todo "DONE")))
        (should (equal (a3madkour-library-queue-test--read note) "#+title: Example 2\n"))))))

(ert-deftest a3madkour-library-queue-test/citar-book-keeps-existing-fields ()
  (a3madkour-library-queue-test--with-env ""
    (let* ((a3madkour-library-queue-test--bib a3madkour-library-queue-test--bib-book)
           (f (a3madkour-library-queue-test--book-note "ex1" "finished")))
      (with-current-buffer (find-file-noselect f)
        (a3madkour-pub-author--drawer-put "creator" "Example Editor")
        (save-buffer))
      (a3madkour/library-citar-add-book
       "ex1" (cons '("title" . "Example Bib Title")
                   (cdr (assoc "ex1" a3madkour-library-queue-test--bib))))
      (should-not a3madkour-library-queue-test--created)
      (should (equal (a3madkour-library-queue-test--drawer f "creator") "Example Editor"))
      (should (equal (a3madkour-library-queue-test--drawer f "status") "reading"))
      ;; A note that already existed keeps its title.
      (should (string-match-p "^#\\+title: Example 1$"
                              (a3madkour-library-queue-test--read f))))))

(ert-deftest a3madkour-library-queue-test/citar-book-created-note-gets-bib-title ()
  "A note this step creates is titled with the bib title, braces stripped,
not citar's \"author, title\" template; its creator reads First Last."
  (a3madkour-library-queue-test--with-env ""
    (let* ((entry '(("=type=" . "book")
                    ("title" . "{{Example}} of {Programming} {{Languages}}")
                    ("author" . "Pierce, Benjamin C. and {Example Org} and {van} Doe, Jane")
                    ("date" . "2002")))
           (file (a3madkour/library-citar-add-book "ex3" entry))
           (txt (a3madkour-library-queue-test--read file)))
      (should (string-match-p "^#\\+title: Example of Programming Languages$" txt))
      (should (= 1 (with-temp-buffer (insert txt) (how-many "^#\\+title:" (point-min) (point-max)))))
      (should (equal (a3madkour-library-queue-test--drawer file "creator")
                     "Benjamin C. Pierce, Example Org, Jane van Doe")))))

(ert-deftest a3madkour-library-queue-test/bib-names ()
  (should (equal (a3madkour/library--bib-names "Example Author") "Example Author"))
  (should (equal (a3madkour/library--bib-names "Doe, Jane and Roe, Rick")
                 "Jane Doe, Rick Roe"))
  (should (equal (a3madkour/library--bib-names "Doe, Jr., Jane") "Jane Doe Jr."))
  (should (equal (a3madkour/library--bib-names "{World Health Organization}")
                 "World Health Organization"))
  (should-not (a3madkour/library--bib-names nil)))

(ert-deftest a3madkour-library-queue-test/citar-editor-when-no-author ()
  (a3madkour-library-queue-test--with-env ""
    (let ((file (a3madkour/library-citar-add-book
                 "ex4" '(("=type=" . "book") ("title" . "Example 4")
                         ("editor" . "Roe, Rick") ("date" . "2010")))))
      (should (equal (a3madkour-library-queue-test--drawer file "creator") "Rick Roe")))))

(ert-deftest a3madkour-library-queue-test/entry-resolves-when-citar-is-loadable ()
  "A Zotero book's queue entry resolves even before citar is loaded: the
lookup loads citar rather than silently treating the entry as a paper."
  (a3madkour-library-queue-test--with-env
      "* TODO Read Example 1 :active:toread:\n:PROPERTIES:\n:CITEKEY: ex1\n:END:\n"
    (let* ((libdir (make-temp-file "fake-citar-" t))
           (load-path (cons libdir load-path))
           (features (remq 'citar features))
           (f (a3madkour-library-queue-test--book-note "ex1" "reading")))
      (unwind-protect
          (progn
            (with-temp-file (expand-file-name "citar.el" libdir)
              (insert "(defun citar-get-entry (_key) '((\"=type=\" . \"book\")))\n"
                      "(provide 'citar)\n"))
            (cl-letf (((symbol-function 'citar-get-entry) nil))
              (should-not (fboundp 'citar-get-entry))
              (a3madkour-library-queue-test--at-entry
               "ex1" (lambda () (should (equal (a3madkour/queue-entry-note-file) f))))))
        (delete-directory libdir t)))))

;; -- add a book without a bib entry --

(ert-deftest a3madkour-library-queue-test/add-book-uses-boox-key-filename ()
  (skip-unless (fboundp 'a3madkour/boox--book-key))
  (a3madkour-library-queue-test--with-env
      "* TODO Read Other :active:toread:\n:PROPERTIES:\n:BOOX_KEY: Example-1\n:END:\n"
    (let* ((src (expand-file-name "Example 1.epub" org-ref-notes))
           (note (progn (with-temp-file src (insert "x"))
                        (a3-reading-queue-add-book "Example 1" "Example Author" "1999" src)))
           (key "Example-1-2"))
      (should (equal note (expand-file-name (concat key ".org") org-ref-notes)))
      (should (equal (a3madkour-library-queue-test--note-for-key key) note))
      (should (equal (a3madkour-library-queue-test--drawer note "status") "reading"))
      (should (equal (a3madkour-library-queue-test--drawer note "creator") "Example Author"))
      (let ((q (a3madkour-library-queue-test--read a3madkour-library/queue-file)))
        (should (string-match-p
                 (concat "^\\* TODO Read Example 1 :active:toread:\n:PROPERTIES:\n:ENERGY: high\n:BOOX_KEY: "
                         key "\n:READING_FILE: .*Example 1\\.epub\n:END:\n")
                 q)))
      (should (equal (a3madkour/library--active-count) 2)))))

(ert-deftest a3madkour-library-queue-test/add-book-without-file-titles-the-key ()
  (skip-unless (fboundp 'a3madkour/boox--book-key))
  (a3madkour-library-queue-test--with-env ""
    (let ((note (a3-reading-queue-add-book "Dr. Example: 2" "" "")))
      (should (equal note (expand-file-name "Dr.-Example-2.org" org-ref-notes)))
      (should (string-match-p "^#\\+title: Dr\\. Example: 2$"
                              (a3madkour-library-queue-test--read note)))
      (should-not (string-match-p "READING_FILE\\|NOTER_DOCUMENT"
                                  (concat (a3madkour-library-queue-test--read note)
                                          (a3madkour-library-queue-test--read
                                           a3madkour-library/queue-file)))))))

(ert-deftest a3madkour-library-queue-test/add-book-prompt-file ()
  (a3madkour-library-queue-test--with-env ""
    (let ((answers nil))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop answers)))
                ((symbol-function 'read-file-name) (lambda (&rest _) (pop answers))))
        (setq answers (list "Example 1" "" "" org-ref-notes))
        ;; RET on the bare directory the prompt starts in: no file.
        (should (equal (advice-eval-interactive-spec
                        (cadr (interactive-form 'a3-reading-queue-add-book)))
                       '("Example 1" "" "" nil)))
        (setq answers (list "Example 1" "" "" (expand-file-name "missing.pdf" org-ref-notes)))
        (should-error (advice-eval-interactive-spec
                       (cadr (interactive-form 'a3-reading-queue-add-book)))
                      :type 'user-error)))))

(ert-deftest a3madkour-library-queue-test/add-book-respects-wip-limit ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((a3madkour/reading-queue-wip-limit 1))
      (should-error (a3-reading-queue-add-book "Example 2" "" "") :type 'user-error)
      (should (equal (directory-files org-ref-notes nil "\\.org\\'") nil)))))

;; -- queue -> note --

(ert-deftest a3madkour-library-queue-test/toggle-inactive-sets-queued ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((f (a3madkour-library-queue-test--book-note "ex1" "reading")))
      (a3madkour-library-queue-test--at-entry
       "ex1" (lambda ()
               (org-toggle-tag "active" 'off)
               (org-toggle-tag "inactive" 'on)
               (a3madkour/library-sync-on-toggle)))
      (should (equal (a3madkour-library-queue-test--drawer f "status") "queued"))
      (a3madkour-library-queue-test--at-entry
       "ex1" (lambda ()
               (org-toggle-tag "inactive" 'off)
               (org-toggle-tag "active" 'on)
               (a3madkour/library-sync-on-toggle)))
      (should (equal (a3madkour-library-queue-test--drawer f "status") "reading")))))

(ert-deftest a3madkour-library-queue-test/done-sets-finished ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((f (a3madkour-library-queue-test--book-note "ex1" "reading")))
      (a3madkour-library-queue-test--at-entry "ex1" (lambda () (org-todo "DONE")))
      (should (equal (a3madkour-library-queue-test--drawer f "status") "finished"))
      (should (a3madkour-library-queue-test--drawer f "finished")))))

(ert-deftest a3madkour-library-queue-test/drop-sets-abandoned ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((f (a3madkour-library-queue-test--book-note "ex1" "reading")))
      (a3madkour-library-queue-test--at-entry "ex1" (lambda () (org-todo "DROP")))
      (should (equal (a3madkour-library-queue-test--drawer f "status") "abandoned"))
      (should-not (a3madkour-library-queue-test--drawer f "finished")))))

(ert-deftest a3madkour-library-queue-test/queue-done-twice-keeps-first-date ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((f (a3madkour-library-queue-test--book-note "ex1" "reading")))
      (a3madkour-library-queue-test--at-entry "ex1" (lambda () (org-todo "DONE")))
      (with-current-buffer (find-file-noselect f)
        (a3madkour-pub-author--drawer-put "finished" "2020-01-01")
        (save-buffer))
      (a3madkour-library-queue-test--at-entry
       "ex1" (lambda () (org-todo "TODO") (org-todo "DONE")))
      (should (equal (a3madkour-library-queue-test--drawer f "finished") "2020-01-01")))))

(ert-deftest a3madkour-library-queue-test/hook-ignores-note-without-media-type ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((f (expand-file-name "ex1.org" org-ref-notes)))
      (with-temp-file f (insert "#+title: Example 1\n"))
      (a3madkour-library-queue-test--at-entry "ex1" (lambda () (org-todo "DONE")))
      (should (equal (a3madkour-library-queue-test--read f) "#+title: Example 1\n")))))

;; -- note -> queue --

(ert-deftest a3madkour-library-queue-test/status-finished-closes-entry-once ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((f (a3madkour-library-queue-test--book-note "ex1" "reading"))
          (calls 0))
      (should (equal (a3madkour/library--active-count) 1))
      (cl-letf* ((orig (symbol-function 'a3madkour-library/set-status))
                 ((symbol-function 'a3madkour-library/set-status)
                  (lambda (&rest args) (cl-incf calls) (apply orig args))))
        ;; What `a3-library-status' does once the status is chosen.
        (with-current-buffer (find-file-noselect f)
          (a3madkour-library/set-status "finished")
          (save-buffer)
          (run-hook-with-args 'a3madkour-library/status-changed-functions
                              buffer-file-name "finished")))
      (should (= calls 1))
      (should (equal (a3madkour/library--active-count) 0))
      (a3madkour-library-queue-test--at-entry
       "ex1" (lambda () (should (equal (org-get-todo-state) "DONE"))))
      (should (equal (a3madkour-library-queue-test--drawer f "status") "finished")))))

(ert-deftest a3madkour-library-queue-test/status-abandoned-drops-entry ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((f (a3madkour-library-queue-test--book-note "ex1" "abandoned")))
      (a3madkour/library-close-queue-entry f "abandoned")
      (a3madkour-library-queue-test--at-entry
       "ex1" (lambda ()
               (should (equal (org-get-todo-state) "DROP"))
               (should-not (member "active" (org-get-tags nil t)))))
      (should (equal (a3madkour-library-queue-test--drawer f "status") "abandoned")))))

(ert-deftest a3madkour-library-queue-test/close-does-nothing-while-syncing ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let ((f (a3madkour-library-queue-test--book-note "ex1" "finished")))
      (let ((a3madkour/library--syncing t))
        (should-not (a3madkour/library-close-queue-entry f "finished")))
      (should (equal (a3madkour/library--active-count) 1)))))

(ert-deftest a3madkour-library-queue-test/close-ignores-note-outside-ref-notes ()
  (a3madkour-library-queue-test--with-env a3madkour-library-queue-test--book-entry
    (let* ((other (make-temp-file "lib-queue-other-" t))
           (f (expand-file-name "ex1.org" other)))
      (unwind-protect
          (progn
            (with-temp-file f
              (insert ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:END:\n"))
            (should-not (a3madkour/library-close-queue-entry f "finished"))
            (should (equal (a3madkour/library--active-count) 1)))
        (delete-directory other t)))))

(provide 'a3madkour-library-queue-test)
;;; a3madkour-library-queue-test.el ends here
