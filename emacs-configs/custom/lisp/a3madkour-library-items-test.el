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

(ert-deftest a3madkour-library-items-test/preview-falls-back-to-first-sentence ()
  (a3madkour-library-items-test--with-note f "#+title: x\n\n* Notes :site:\nFirst one. Second.\n"
    (should (equal (a3madkour-library/preview f) "First one.")))
  (a3madkour-library-items-test--with-note f "#+title: x\n\n* Notes :site:\n*Bold* see [[http://x.org][the site]] now! More.\n"
    (should (equal (a3madkour-library/preview f) "Bold see the site now!"))))

(ert-deftest a3madkour-library-items-test/preview-prefers-drawer ()
  (a3madkour-library-items-test--with-note f
      ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:LIBRARY_PREVIEW: Hand written.\n:END:\n* Notes :site:\nOther text.\n"
    (should (equal (a3madkour-library/preview f) "Hand written."))))

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

(ert-deftest a3madkour-library-items-test/preview-ignores-logbook ()
  (a3madkour-library-items-test--with-note f
      "* Notes :site:\n:PROPERTIES:\n:ID: a\n:END:\n:LOGBOOK:\nprivate thought.\n:END:\nPublic.\n"
    (should (equal (a3madkour-library/preview f) "Public."))))

(ert-deftest a3madkour-library-items-test/site-body-drops-noexport-and-comment-subtrees ()
  (let ((b (a3madkour-library-items-test--body
            "* Notes :site:\nPublic.\n** Private sub :noexport:\nSECRET\n*** Deeper\nSECRET2\n** COMMENT Draft\nSECRET3\n** Kept\nAlso public.\n")))
    (should (string-match-p "Public\\." b))
    (should (string-match-p "Also public\\." b))
    (should-not (string-match-p "SECRET\\|Private sub\\|Draft" b))))

(ert-deftest a3madkour-library-items-test/preview-links ()
  (dolist (c '(("[[id:abc-123]] is good. Next." . "is good.")
               ("See [[file:x.org]] here. Next." . "See here.")
               ("Go [[https://x.org/a]] now. Next." . "Go https://x.org/a now.")
               ("Go [[https://x.org][site]] now. Next." . "Go site now.")))
    (a3madkour-library-items-test--with-note f (concat "* Notes :site:\n" (car c) "\n")
      (should (equal (a3madkour-library/preview f) (cdr c))))))

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

(provide 'a3madkour-library-items-test)
;;; a3madkour-library-items-test.el ends here
