;;; a3madkour-ref-notes-test.el --- tests for a3madkour-ref-notes.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for finding a ref note by the keys its drawer declares, and
;;; for the org tags a new citar note gets from its bib keywords.
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-ref-notes)

(defvar org-ref-notes)

(defmacro a3madkour-ref-notes-test--with-dir (files &rest body)
  "Run BODY with `dir' bound to a temp dir holding FILES ((NAME . TEXT) ...)."
  (declare (indent 1))
  `(let ((dir (file-name-as-directory (make-temp-file "ref-notes-" t))))
     (unwind-protect
         (progn
           (dolist (f ,files)
             (with-temp-file (expand-file-name (car f) dir) (insert (cdr f))))
           ,@body)
       (delete-directory dir t))))

(defun a3madkour-ref-notes-test--note (refs &optional boox title)
  "A ref note's text with ROAM_REFS REFS, optional BOOX_KEY BOOX and TITLE."
  (concat ":PROPERTIES:\n:ID: x\n"
          (if refs (format ":ROAM_REFS: %s\n" refs) "")
          (if boox (format ":BOOX_KEY: %s\n" boox) "")
          ":END:\n#+title: " (or title "Example") "\n"))

;; -- ref-keys --

(ert-deftest a3madkour-ref-notes-test/ref-keys-reads-every-cite-form ()
  (should (equal (a3madkour-ref-notes/ref-keys
                  "@ex1 https://example.com/x cite:ex2 [cite:@ex3] cite:&ex4")
                 '("ex1" "ex2" "ex3" "ex4")))
  (should-not (a3madkour-ref-notes/ref-keys "https://example.com"))
  (should-not (a3madkour-ref-notes/ref-keys nil)))

;; -- file --

(ert-deftest a3madkour-ref-notes-test/file-finds-renamed-note-by-roam-refs ()
  "The defect: a note renamed to its title is still the note for its citekey."
  (a3madkour-ref-notes-test--with-dir
      `(("types_and_programming_languages.org"
         . ,(a3madkour-ref-notes-test--note "@pierce2002")))
    (should (equal (a3madkour-ref-notes/file "pierce2002" dir)
                   (expand-file-name "types_and_programming_languages.org" dir)))))

(ert-deftest a3madkour-ref-notes-test/file-finds-boox-key ()
  (a3madkour-ref-notes-test--with-dir
      `(("example_one.org" . ,(a3madkour-ref-notes-test--note nil "Example-1")))
    (should (equal (a3madkour-ref-notes/file "Example-1" dir)
                   (expand-file-name "example_one.org" dir)))))

(ert-deftest a3madkour-ref-notes-test/file-prefers-the-key-filename ()
  (a3madkour-ref-notes-test--with-dir
      `(("ex1.org" . "#+title: Example\n")
        ("aaa.org" . ,(a3madkour-ref-notes-test--note "@ex1")))
    (should (equal (a3madkour-ref-notes/file "ex1" dir)
                   (expand-file-name "ex1.org" dir)))))

(ert-deftest a3madkour-ref-notes-test/file-nil-when-no-note-declares-key ()
  (a3madkour-ref-notes-test--with-dir
      `(("a.org" . ,(a3madkour-ref-notes-test--note "@ex10"))
        ;; A key named only below the file drawer is not the file's key.
        ("b.org" . "#+title: B\n* H\n:PROPERTIES:\n:ROAM_REFS: @ex1\n:END:\n"))
    (should-not (a3madkour-ref-notes/file "ex1" dir))))

(ert-deftest a3madkour-ref-notes-test/file-reports-duplicates ()
  (a3madkour-ref-notes-test--with-dir
      `(("a.org" . ,(a3madkour-ref-notes-test--note "@ex1"))
        ("b.org" . ,(a3madkour-ref-notes-test--note "@ex1")))
    (let (said)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) said))))
        (should (equal (a3madkour-ref-notes/file "ex1" dir)
                       (expand-file-name "a.org" dir))))
      (should (cl-some (lambda (m) (string-match-p "2 notes declare ex1" m)) said)))))

;; -- key --

(ert-deftest a3madkour-ref-notes-test/key-prefers-boox-then-citekey-then-name ()
  (a3madkour-ref-notes-test--with-dir
      `(("a.org" . ,(a3madkour-ref-notes-test--note "@ex1" "Example-1"))
        ("b.org" . ,(a3madkour-ref-notes-test--note "https://example.com @ex2 @ex3"))
        ("ex4.org" . "#+title: Example\n"))
    (should (equal (a3madkour-ref-notes/key (expand-file-name "a.org" dir)) "Example-1"))
    (should (equal (a3madkour-ref-notes/key (expand-file-name "b.org" dir)) "ex2"))
    (should (equal (a3madkour-ref-notes/key (expand-file-name "ex4.org" dir)) "ex4"))))

;; -- citar notes source --

(ert-deftest a3madkour-ref-notes-test/citar-items-find-renamed-and-named-notes ()
  "citar sees a title-named note under its citekey, so opening the
citekey's notes opens it instead of creating a second note."
  (a3madkour-ref-notes-test--with-dir
      `(("types_and_programming_languages.org"
         . ,(a3madkour-ref-notes-test--note "@pierce2002"))
        ("ex1.org" . "#+title: Example\n"))
    (let ((org-ref-notes dir))
      (let ((items (a3madkour-ref-notes/citar-items '("pierce2002" "ex1" "ex9"))))
        (should (equal (gethash "pierce2002" items)
                       (list (expand-file-name "types_and_programming_languages.org" dir))))
        (should (equal (gethash "ex1" items) (list (expand-file-name "ex1.org" dir))))
        (should-not (gethash "ex9" items)))
      (let ((has (a3madkour-ref-notes/citar-hasitems)))
        (should (funcall has "pierce2002"))
        (should (funcall has "ex1"))
        (should-not (funcall has "ex9"))))))

(ert-deftest a3madkour-ref-notes-test/citar-hasitems-nil-without-notes ()
  (a3madkour-ref-notes-test--with-dir nil
    (let ((org-ref-notes dir))
      (should-not (a3madkour-ref-notes/citar-hasitems)))))

;; -- tags --

(ert-deftest a3madkour-ref-notes-test/keyword-tags-camelcase-and-drop-bookkeeping ()
  (should (equal (a3madkour-ref-notes/keyword-tags
                  "Programming languages (Electronic computers),zotlib/imported,zotlib/imported/2026-10-25")
                 '("ProgrammingLanguages")))
  (should (equal (a3madkour-ref-notes/keyword-tags "type theory; Type Theory, lambda-calculus")
                 '("TypeTheory" "LambdaCalculus")))
  (should-not (a3madkour-ref-notes/keyword-tags nil))
  (should-not (a3madkour-ref-notes/keyword-tags "zotlib")))

(ert-deftest a3madkour-ref-notes-test/filetags-line ()
  (should (equal (a3madkour-ref-notes/filetags
                  "Programming languages (Electronic computers),zotlib/imported" t)
                 ":Ref:Book:ProgrammingLanguages:"))
  (should (equal (a3madkour-ref-notes/filetags "book, ref" t) ":Ref:Book:"))
  (should (equal (a3madkour-ref-notes/filetags nil nil) ":Ref:"))
  ;; Every tag is a legal org tag.
  (should (string-match-p "\\`:\\(?:[[:alnum:]_@#%]+:\\)+\\'"
                          (a3madkour-ref-notes/filetags "C++ (language), a/b, x.y" nil))))

(provide 'a3madkour-ref-notes-test)
;;; a3madkour-ref-notes-test.el ends here
