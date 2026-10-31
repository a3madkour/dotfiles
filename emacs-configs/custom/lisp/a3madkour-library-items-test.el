;;; a3madkour-library-items-test.el --- tests for -library-items.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the library item-note reader (file-level `LIBRARY_*'
;;; drawer, status stamping, tag cleaning, the `:site:' body).
;;; Code:

(require 'ert)
(require 'a3madkour-sections-fixture)
(require 'a3madkour-library-items)

(defmacro a3madkour-library-items-test--with-note (var text &rest body)
  "Write TEXT to a temp file bound to VAR, run BODY, delete the file."
  (declare (indent 2))
  `(let ((,var (make-temp-file "lib-item-" nil ".org")))
     (unwind-protect
         (progn (with-temp-file ,var (insert ,text)) ,@body)
       (delete-file ,var))))

(defconst a3madkour-library-items-test--book
  ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:LIBRARY_STATUS: queued\n:LIBRARY_CREATOR: Example Author\n:LIBRARY_YEAR: 1999\n:LIBRARY_PROGRESS_PCT: 42\n:PROGRESS: highlighting\n:END:\n#+title: Example 1\n\n* Types\nSECRET\n\n* Notes :site:\nPublic.\n")

(ert-deftest a3madkour-library-items-test/item-p-needs-media-type ()
  (a3madkour-library-items-test--with-note f a3madkour-library-items-test--book
    (should (a3madkour-library/item-p f)))
  (a3madkour-library-items-test--with-note f "#+title: Plain\n\n* Heading\n"
    (should-not (a3madkour-library/item-p f)))
  (a3madkour-library-items-test--with-note f ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE:\n:END:\n#+title: x\n"
    (should-not (a3madkour-library/item-p f))))

(ert-deftest a3madkour-library-items-test/properties-reads-prefixed-drawer-only ()
  (a3madkour-library-items-test--with-note f a3madkour-library-items-test--book
    (let ((p (a3madkour-library/properties f)))
      (should (equal (alist-get "media_type" p nil nil #'equal) "book"))
      (should (equal (alist-get "creator" p nil nil #'equal) "Example Author"))
      (should (equal (alist-get "year" p nil nil #'equal) "1999"))
      (should-not (assoc "started" p))
      (should (equal (plist-get (alist-get 'extras p) :progress_pct) 42))
      (should-not (plist-member (alist-get 'extras p) :progress)))))

(ert-deftest a3madkour-library-items-test/shelf-for-every-media-type ()
  (should (equal (mapcar #'a3madkour-library/shelf-for
                         '("book" "album" "track" "game" "film" "series"))
                 '("library/reading" "library/listening" "library/listening"
                   "library/playing" "library/watching" "library/watching")))
  (should-not (a3madkour-library/shelf-for "paper")))

(ert-deftest a3madkour-library-items-test/statuses-and-in-progress ()
  (should (member "reading" (a3madkour-library/statuses "book")))
  (should (equal (a3madkour-library/in-progress-status "game") "playing"))
  (should (equal (a3madkour-library/in-progress-status "film") "watching")))

(defun a3madkour-library-items-test--set (media status &rest days)
  "Return the drawer after setting STATUS on a MEDIA note once per DAYS."
  (with-temp-buffer
    (org-mode)
    (insert (format ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: %s\n:END:\n#+title: x\n" media))
    (dolist (d days) (a3madkour-library/set-status status d))
    (list (a3madkour-pub-author--drawer-get "status")
          (a3madkour-pub-author--drawer-get "started")
          (a3madkour-pub-author--drawer-get "finished"))))

(ert-deftest a3madkour-library-items-test/set-status-stamps-started-once ()
  (should (equal (a3madkour-library-items-test--set
                  "book" "reading" "2026-01-01" "2026-01-02")
                 '("reading" "2026-01-01" nil))))

(ert-deftest a3madkour-library-items-test/set-status-finished-stamps-finished ()
  (should (equal (a3madkour-library-items-test--set
                  "book" "finished" "2026-02-01" "2026-02-09")
                 '("finished" nil "2026-02-01"))))

(ert-deftest a3madkour-library-items-test/set-status-100pct-stamps-finished ()
  (should (equal (a3madkour-library-items-test--set "game" "100pct" "2026-03-03")
                 '("100pct" nil "2026-03-03"))))

(ert-deftest a3madkour-library-items-test/set-status-rejects-wrong-shelf-word ()
  (should-error (a3madkour-library-items-test--set "book" "listening" "2026-01-01")
                :type 'user-error))

(ert-deftest a3madkour-library-items-test/clean-tags ()
  (should (equal (a3madkour-library/clean-tags
                  '("Ref" "Book" "ProgrammingLanguages" "TODO" "fiction"))
                 '("programming-languages" "fiction")))
  (should (equal (a3madkour-library/clean-tags '("sci_fi" "Sci Fi" "!!" "HTMLParser"))
                 '("sci-fi" "html-parser"))))

(ert-deftest a3madkour-library-items-test/site-body-only-site-subtree ()
  (a3madkour-library-items-test--with-note f a3madkour-library-items-test--book
    (let ((b (a3madkour-library/site-body f)))
      (should (string-match-p "Public\\." b))
      (should-not (string-match-p "SECRET" b))
      (should-not (string-match-p "Notes" b)))))

(ert-deftest a3madkour-library-items-test/site-body-skips-drawer-and-stops-at-next-h1 ()
  (a3madkour-library-items-test--with-note f
      "#+title: x\n\n* Notes :site:\n:PROPERTIES:\n:ID: abc\n:END:\nPublic.\n** Sub\nNested.\n* Private\nSECRET\n"
    (let ((b (a3madkour-library/site-body f)))
      (should (string-match-p "Public\\." b))
      (should (string-match-p "Nested\\." b))
      (should-not (string-match-p "SECRET\\|abc" b))))
  (a3madkour-library-items-test--with-note f "#+title: x\n\n** Deep :site:\nNo.\n"
    (should-not (a3madkour-library/site-body f))))

(ert-deftest a3madkour-library-items-test/site-body-blank-is-nil ()
  (a3madkour-library-items-test--with-note f "#+title: x\n\n* Notes :site:\n  \n\n* Other\nx\n"
    (should-not (a3madkour-library/site-body f)))
  (a3madkour-library-items-test--with-note f "#+title: x\n\n* Other\nx\n"
    (should-not (a3madkour-library/site-body f))))

(ert-deftest a3madkour-library-items-test/preview-only-from-drawer ()
  "The preview is the note's own `LIBRARY_PREVIEW' or nothing: an excerpt of
the site section read as a stray quote on the 2026-10-30 TAPL card."
  (a3madkour-library-items-test--with-note f
      ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:LIBRARY_PREVIEW: Hand written.\n:END:\n* Notes :site:\nOther text.\n"
    (should (equal (a3madkour-library/preview f) "Hand written.")))
  (a3madkour-library-items-test--with-note f
      ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:END:\n* Notes :site:\nFirst one. Second.\n"
    (should-not (a3madkour-library/preview f))))

(defun a3madkour-library-items-test--body (text)
  "Site body of a note whose text is TEXT."
  (a3madkour-library-items-test--with-note f text
    (a3madkour-library/site-body f)))

(ert-deftest a3madkour-library-items-test/site-body-strips-every-drawer ()
  (let ((b (a3madkour-library-items-test--body
            "* Notes :site:\n:PROPERTIES:\n:ID: abc\n:END:\n:LOGBOOK:\n- Note taken on [2026-01-01] \\\\\n  private thought.\n:END:\nPublic.\n:MYDRAWER:\nhidden mid\n:END:\nMore.\n")))
    (should (string-match-p "Public\\." b))
    (should (string-match-p "More\\." b))
    (should-not (string-match-p "private\\|hidden\\|abc" b))))

(ert-deftest a3madkour-library-items-test/site-body-drops-noexport-and-comment-subtrees ()
  (let ((b (a3madkour-library-items-test--body
            "* Notes :site:\nPublic.\n** Private sub :noexport:\nSECRET\n*** Deeper\nSECRET2\n** COMMENT Draft\nSECRET3\n** Kept\nAlso public.\n")))
    (should (string-match-p "Public\\." b))
    (should (string-match-p "Also public\\." b))
    (should-not (string-match-p "SECRET\\|Private sub\\|Draft" b))))

(ert-deftest a3madkour-library-items-test/site-heading-selection ()
  (should-not (a3madkour-library-items-test--body "* COMMENT Notes :site:\nSECRET\n"))
  (should-not (a3madkour-library-items-test--body "* Notes :website:\nSECRET\n"))
  (should-not (a3madkour-library-items-test--body "#+FILETAGS: :site:\n\n* Notes\nSECRET\n"))
  (should-not (a3madkour-library-items-test--body "* Top\n** X :site:\nSECRET\n"))
  (should (equal (a3madkour-library-items-test--body "* Notes :book:site:fun:\nPublic.\n")
                 "Public."))
  (let ((b (a3madkour-library-items-test--body
            "* Types\nSECRET\n* Notes :site:\nPublic.\n** Sub\nPublic sub.\n* Private\nSECRET\n** Private sub\nSECRET\n")))
    (should (string-match-p "Public sub\\." b))
    (should-not (string-match-p "SECRET\\|Private" b))))

;; -- final-review fixes: comments, excluded headings, preview noise --

(ert-deftest a3madkour-library-items-test/site-body-strips-comment-lines-and-blocks ()
  "Org comment lines and comment blocks never reach the site body."
  (let ((b (a3madkour-library-items-test--body
            (concat "* Notes :site:\n# private aside SECRET1.\nPublic.\n"
                    "  # indented SECRET2\n#not-a-comment stays\n"
                    "#+begin_comment\nSECRET3\n#+end_comment\n"
                    "#+BEGIN_COMMENT\nSECRET4\n#+END_COMMENT\nMore.\n#\n"))))
    (should (string-match-p "Public\\." b))
    (should (string-match-p "More\\." b))
    (should (string-match-p "#not-a-comment stays" b))
    (should-not (string-match-p "SECRET\\|_comment\\|_COMMENT" b)))
  (let ((b (a3madkour-library-items-test--body
            "* Notes :site:\nPublic.\n#+begin_src python\n# code comment\nx = 1\n#+end_src\n")))
    (should (string-match-p "^# code comment$" b))))

(ert-deftest a3madkour-library-items-test/site-body-comment-only-is-nil ()
  "A section holding only comments is blank: share and the gate refuse it."
  (should-not (a3madkour-library-items-test--body
               "* Notes :site:\n# aside\n#+begin_comment\nx\n#+end_comment\n")))

(ert-deftest a3madkour-library-items-test/site-heading-never-excluded ()
  "A `:site:' heading tagged noexport, an export-exclude tag or ARCHIVE is
never the site heading; a later clean one still is."
  (dolist (tags '(":site:noexport:" ":noexport:site:" ":site:ARCHIVE:" ":site:private:"))
    (let ((org-export-exclude-tags '("noexport" "private")))
      (should-not (a3madkour-library-items-test--body
                   (format "* Notes %s\nSECRET\n" tags)))
      (should (equal (a3madkour-library-items-test--body
                      (format "* Notes %s\nSECRET\n* Later :site:\nPublic.\n" tags))
                     "Public.")))))

(ert-deftest a3madkour-library-items-test/site-body-drops-archive-and-exclude-tag-subtrees ()
  (let ((org-export-exclude-tags '("noexport" "private")))
    (let ((b (a3madkour-library-items-test--body
              "* Notes :site:\nPublic.\n** Old :ARCHIVE:\nSECRET\n** Mine :private:\nSECRET2\n** Kept\nOK.\n")))
      (should (string-match-p "OK\\." b))
      (should-not (string-match-p "SECRET\\|Old\\|Mine" b)))))

(defmacro a3madkour-library-items-test--with-copy (var text &rest body)
  "Write TEXT to a note in a temp dir, bind VAR to its site-only copy's
text and `dir' to the note's directory, run BODY."
  (declare (indent 2))
  `(let* ((dir (file-name-as-directory (make-temp-file "lib-copy-" t)))
          (note (expand-file-name "note.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file note (insert ,text))
           (let* ((tmp (a3madkour-library/site-only-copy note))
                  (,var (unwind-protect
                            (with-temp-buffer
                              (insert-file-contents tmp)
                              (buffer-string))
                          (delete-file tmp))))
             (should (string-prefix-p
                      (file-name-as-directory
                       (file-truename temporary-file-directory))
                      (file-truename tmp)))
             ,@body))
       (delete-directory dir t))))

(ert-deftest a3madkour-library-items-test/site-only-copy-keeps-drawer-keywords-site ()
  "The copy is the file drawer, the `#+' keywords and the site body only."
  (a3madkour-library-items-test--with-copy c
      (concat ":PROPERTIES:\n:ID: x-1\n:LIBRARY_MEDIA_TYPE: book\n:END:\n"
              "#+title: Example 1\n#+INCLUDE: \"other.org\"\n#+filetags: :Ref:\n"
              "Preamble SECRET.\n* Types\nSECRET\n* Notes :site:\nPublic.\n* After\nSECRET\n")
    (should (string-match-p "\\`:PROPERTIES:\n:ID: x-1\n:LIBRARY_MEDIA_TYPE: book\n:END:\n" c))
    (should (string-match-p "^#\\+title: Example 1$" c))
    (should (string-match-p "^#\\+filetags: :Ref:$" c))
    (should (string-match-p "^Public\\.$" c))
    (should-not (string-match-p "SECRET\\|INCLUDE\\|Notes\\|Types" c))))

(ert-deftest a3madkour-library-items-test/site-only-copy-absolutizes-relative-links ()
  "Relative file and asset links resolve against the note's directory, not
the temp dir; canonical `./assets/', absolute, id and web links are kept."
  (a3madkour-library-items-test--with-copy c
      (concat "#+title: Example 1\n* Notes :site:\n"
              "[[file:other.org][o]] [[../up/x.png]] [[pic.png][p]]\n"
              "[[./assets/page/s/a.png]] [[/abs/b.png]] [[~/c.png]]\n"
              "[[id:abc][i]] [[https://example.com/d.png]] [[Some Heading]]\n")
    (should (string-match-p (regexp-quote (format "[[file:%sother.org][o]]" dir)) c))
    (should (string-match-p (regexp-quote
                             (format "[[%s]]" (expand-file-name "../up/x.png" dir)))
                            c))
    (should (string-match-p (regexp-quote (format "[[%spic.png][p]]" dir)) c))
    (dolist (kept '("[[./assets/page/s/a.png]]" "[[/abs/b.png]]" "[[~/c.png]]"
                    "[[id:abc][i]]" "[[https://example.com/d.png]]"
                    "[[Some Heading]]"))
      (should (string-match-p (regexp-quote kept) c)))))

(ert-deftest a3madkour-library-items-test/site-only-copy-errors-without-site ()
  (a3madkour-library-items-test--with-note f "#+title: x\n* Notes\nSECRET\n"
    (should-error (a3madkour-library/site-only-copy f))))

(ert-deftest a3madkour-library-items-test/site-only-copy-allowlists-preamble ()
  "Only TITLE, FILETAGS, DATE and HUGO_* keywords and the ID, ROAM_REFS and
LIBRARY_* drawer properties reach the copy; everything else in the
preamble may carry private text into the export."
  (a3madkour-library-items-test--with-copy c
      (concat ":PROPERTIES:\n:ID: x-1\n:ROAM_REFS: @key\n"
              ":EXPORT_DESCRIPTION: PRIVATE-E\n:PROGRESS: PRIVATE-F\n"
              ":LIBRARY_MEDIA_TYPE: book\n:END:\n"
              "#+title: Example 1\n#+date: 2026-01-01\n#+filetags: :Ref:\n"
              "#+HUGO_SECTION: garden\n#+hugo_custom_front_matter: :weight 3\n"
              "#+hugo: PRIVATE-A\n#+caption: PRIVATE-B\n#+html: PRIVATE-C\n"
              "#+setupfile: /tmp/PRIVATE-D.org\n#+name: PRIVATE-G\n"
              "#+attr_html: :alt PRIVATE-H\n#+md: PRIVATE-I\n"
              "* Notes :site:\nPublic.\n")
    (should (string-match-p
             "\\`:PROPERTIES:\n:ID: x-1\n:ROAM_REFS: @key\n:LIBRARY_MEDIA_TYPE: book\n:END:\n"
             c))
    (dolist (kept '("#+title: Example 1" "#+date: 2026-01-01" "#+filetags: :Ref:"
                    "#+HUGO_SECTION: garden" "#+hugo_custom_front_matter: :weight 3"))
      (should (string-match-p (concat "^" (regexp-quote kept) "$") c)))
    (should-not (string-match-p "PRIVATE" c))))

(ert-deftest a3madkour-library-items-test/site-only-copy-drops-include-in-site-body ()
  "An `#+INCLUDE:' inside the `:site:' body is dropped, with a warning."
  (let (warned)
    (cl-letf (((symbol-function 'a3madkour-pub/warn)
               (lambda (_m _f fmt &rest args)
                 (push (apply #'format fmt args) warned))))
      (a3madkour-library-items-test--with-copy c
          "#+title: Example 1\n* Notes :site:\nPublic.\n  #+INCLUDE: \"/tmp/x.org\"\nMore.\n"
        (should-not (string-match-p "INCLUDE" c))
        (should (string-match-p "^Public\\.\nMore\\.$" c))))
    (should (cl-some (lambda (w) (string-match-p "INCLUDE" w)) warned))))

;; -- commands --

(defmacro a3madkour-library-items-test--with-dir (var &rest body)
  "Run BODY with VAR and `notes-dir' bound to a fresh temp dir."
  (declare (indent 1))
  `(let* ((,var (make-temp-file "lib-notes-" t))
          (a3madkour-library/notes-dir ,var))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (string-prefix-p ,var (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory ,var t))))

(defmacro a3madkour-library-items-test--stub-prompts (answers &rest body)
  "Run BODY with `completing-read' answered from ANSWERS (alist prompt-regexp
-> value, or `default' for the DEF arg) and `read-string' from `:read'."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'completing-read)
              (lambda (prompt _coll &optional _p _r _i _h def)
                (let ((a (cl-find-if (lambda (c) (string-match-p (car c) prompt))
                                     ,answers)))
                  (if (and a (not (eq (cdr a) 'default))) (cdr a) def))))
             ((symbol-function 'read-string)
              (lambda (prompt &rest _)
                (cond ((string-match-p "Title" prompt) "Example Film")
                      ((string-match-p "Creator" prompt) "Example Director")
                      ((string-match-p "Year" prompt) "2001")))))
     ,@body))

(ert-deftest a3madkour-library-items-test/commands/add-film-defaults-finished-and-stamps ()
  (a3madkour-library-items-test--with-dir d
    (a3madkour-library-items-test--stub-prompts '(("Media" . "film") ("Status" . default))
      (let ((file (a3-library-add)))
        (should (equal file (expand-file-name "example-film.org" d)))
        (let ((txt (with-temp-buffer (insert-file-contents file) (buffer-string))))
          (should (string-match-p "\\`:PROPERTIES:\n:ID: [^\n]+\n:LIBRARY_MEDIA_TYPE: film" txt))
          (should (string-match-p ":LIBRARY_STATUS: finished" txt))
          (should (string-match-p ":LIBRARY_FINISHED: [0-9-]+" txt))
          (should-not (string-match-p "LIBRARY_STARTED" txt))
          (should (string-match-p "#\\+title: Example Film\n\n\\* Notes :site:\n" txt)))
        (should (equal (buffer-file-name) file))))))

(ert-deftest a3madkour-library-items-test/commands/add-book-defaults-in-progress ()
  (a3madkour-library-items-test--with-dir d
    (a3madkour-library-items-test--stub-prompts '(("Media" . "book") ("Status" . default))
      (let ((txt (with-temp-buffer (insert-file-contents (a3-library-add)) (buffer-string))))
        (should (string-match-p ":LIBRARY_STATUS: reading" txt))
        (should (string-match-p ":LIBRARY_STARTED: " txt))))))

(ert-deftest a3madkour-library-items-test/commands/add-refuses-existing ()
  (a3madkour-library-items-test--with-dir d
    (let ((f (expand-file-name "example-film.org" d)))
      (with-temp-file f (insert "KEEP"))
      (a3madkour-library-items-test--stub-prompts '(("Media" . "film"))
        (should-error (a3-library-add) :type 'user-error))
      (should (equal (with-temp-buffer (insert-file-contents f) (buffer-string)) "KEEP")))))

(ert-deftest a3madkour-library-items-test/commands/outside-org-refuses ()
  (with-temp-buffer
    (dolist (c '(a3-library-status a3-library-share a3-library-unshare))
      (should-error (funcall c) :type 'user-error))))

(defmacro a3madkour-library-items-test--with-visited (var text &rest body)
  "Visit a temp item note holding TEXT in a buffer, bind VAR to the file."
  (declare (indent 2))
  `(a3madkour-library-items-test--with-note ,var ,text
     (let ((buf (find-file-noselect ,var)))
       (unwind-protect (with-current-buffer buf ,@body)
         (with-current-buffer buf (set-buffer-modified-p nil))
         (kill-buffer buf)))))

(ert-deftest a3madkour-library-items-test/commands/share-refuses-without-site-section ()
  (let ((no-site ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:LIBRARY_STATUS: queued\n:LIBRARY_CREATOR: A\n:LIBRARY_YEAR: 1999\n:END:\n#+title: Example 1\n\n* Private\nx\n"))
    (dolist (yes '(nil t))
      (a3madkour-library-items-test--with-visited f no-site
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) yes)))
          (should-error (a3-library-share) :type 'user-error))
        (should (eq yes (and (string-match-p "^\\* Notes :site:$" (buffer-string)) t)))
        (should-not (string-match-p "HUGO_PUBLISH" (buffer-string)))))))

(ert-deftest a3madkour-library-items-test/commands/share-after-add-does-not-duplicate-heading ()
  (a3madkour-library-items-test--with-dir d
    (a3madkour-library-items-test--stub-prompts '(("Media" . "film") ("Status" . default))
      (a3-library-add)
      (dolist (yes '(nil t))
        (let (asked)
          (cl-letf (((symbol-function 'y-or-n-p)
                     (lambda (&rest _) (setq asked t) yes)))
            (should-error (a3-library-share) :type 'user-error))
          (should-not asked)
          (should (= 1 (with-temp-buffer
                         (insert (with-current-buffer (current-buffer) ""))
                         (let ((n 0))
                           (with-current-buffer (find-buffer-visiting
                                                 (expand-file-name "example-film.org" d))
                             (save-excursion
                               (goto-char (point-min))
                               (while (re-search-forward "^\\* Notes :site:$" nil t)
                                 (cl-incf n))))
                           n))))
          (should-not (string-match-p "HUGO_PUBLISH" (buffer-string))))))))

(ert-deftest a3madkour-library-items-test/commands/share-marks-garden ()
  (a3madkour-library-items-test--with-visited f a3madkour-library-items-test--book
    (let (prompts)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (p _c &optional _a _b _i _h d) (push p prompts) d))
                ((symbol-function 'read-string)
                 (lambda (p &rest _) (push p prompts) ""))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (a3-library-share))
      (should (string-match-p "^#\\+HUGO_PUBLISH: t$" (buffer-string)))
      (should (string-match-p "^#\\+HUGO_SECTION: garden$" (buffer-string)))
      (should-not (cl-some (lambda (p) (string-match-p "tatus\\|year\\|creator" p))
                           prompts)))))

(defconst a3madkour-library-items-test--book-no-year
  (replace-regexp-in-string ":LIBRARY_YEAR: 1999\n" "" a3madkour-library-items-test--book))

(ert-deftest a3madkour-library-items-test/commands/share-asks-missing-shelf-field ()
  "Share asks for a shelf-required field the garden contract does not
\(year), re-prompting until digits, and writes it to the drawer."
  (a3madkour-library-items-test--with-visited f a3madkour-library-items-test--book-no-year
    (let (prompts (years '("nineteen" "1999")))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (p _c &optional _a _b _i _h d) (push p prompts) d))
                ((symbol-function 'read-string)
                 (lambda (p &rest _) (push p prompts)
                   (if (string-match-p "year" p) (pop years) "")))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (a3-library-share))
      (should (= 2 (cl-count-if (lambda (p) (string-match-p "year" p)) prompts)))
      (should (equal (a3madkour-pub-author--drawer-get "year") "1999"))
      (should (string-match-p "^#\\+HUGO_PUBLISH: t$" (buffer-string))))))

(ert-deftest a3madkour-library-items-test/commands/share-asks-invalid-shelf-status ()
  "A status that is not one of the shelf's words is asked for again."
  (a3madkour-library-items-test--with-visited f
      (replace-regexp-in-string "LIBRARY_STATUS: queued" "LIBRARY_STATUS: listening"
                                a3madkour-library-items-test--book)
    (let (asked)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (p c &optional _a _b _i _h d)
                   (if (string-match-p "status" p)
                       (progn (setq asked (all-completions "" c)) "finished")
                     d)))
                ((symbol-function 'read-string) (lambda (&rest _) ""))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (a3-library-share))
      (should (equal (sort asked #'string<) '("abandoned" "finished" "queued" "reading")))
      (should (equal (a3madkour-pub-author--drawer-get "status") "finished")))))

(ert-deftest a3madkour-library-items-test/commands/share-asks-non-numeric-year ()
  (a3madkour-library-items-test--with-visited f
      (replace-regexp-in-string "LIBRARY_YEAR: 1999" "LIBRARY_YEAR: MCMXCIX"
                                a3madkour-library-items-test--book)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_p _c &optional _a _b _i _h d) d))
              ((symbol-function 'read-string)
               (lambda (p &rest _) (if (string-match-p "year" p) "1999" "")))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
      (a3-library-share))
    (should (equal (a3madkour-pub-author--drawer-get "year") "1999"))))

(ert-deftest a3madkour-library-items-test/commands/share-quit-leaves-buffer-untouched ()
  "C-g at the shelf prompt undoes the mark too: the buffer is as it was."
  (a3madkour-library-items-test--with-visited f a3madkour-library-items-test--book-no-year
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_p _c &optional _a _b _i _h d) d))
                ((symbol-function 'read-string)
                 (lambda (p &rest _) (if (string-match-p "year" p) (signal 'quit nil) "")))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (should (condition-case nil (progn (a3-library-share) nil) (quit t))))
      (should (equal (buffer-string) before)))))

(ert-deftest a3madkour-library-items-test/commands/status-runs-hook ()
  (a3madkour-library-items-test--with-visited f a3madkour-library-items-test--book
    (let (got)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "reading")))
        (let ((a3madkour-library/status-changed-functions
               (list (lambda (file status) (push (list file status) got)))))
          (a3-library-status)))
      (should (equal got (list (list f "reading"))))
      (should-not (buffer-modified-p))
      (should (string-match-p ":LIBRARY_STATUS: reading"
                              (with-temp-buffer (insert-file-contents f) (buffer-string))))
      (should (string-match-p ":LIBRARY_STARTED: " (buffer-string))))))

(ert-deftest a3madkour-library-items-test/commands/unshare-flips-publish ()
  (a3madkour-library-items-test--with-visited f
      (replace-regexp-in-string "#\\+title" "#+HUGO_PUBLISH: t\n#+title"
                                a3madkour-library-items-test--book)
    (a3-library-unshare)
    (should (string-match-p "^#\\+HUGO_PUBLISH: nil$" (buffer-string)))))

(provide 'a3madkour-library-items-test)
;;; a3madkour-library-items-test.el ends here
