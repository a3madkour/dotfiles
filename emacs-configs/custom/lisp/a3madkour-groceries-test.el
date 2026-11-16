;;; a3madkour-groceries-test.el --- tests for the grocery list  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'a3madkour-groceries)

(defconst a3madkour-groceries-test--registry "#+TAGS: { have(h) low(l) out(o) }
#+TAGS: [ aisle : produce oils_vinegar dairy ]
* olive oil :low:oils_vinegar:
:PROPERTIES:
:ALIASES: EVOO
:END:
* leeks :out:produce:
* milk :have:dairy:
* rice :out:
* lemons :out:produce:
* salt
")

(defmacro a3madkour-groceries-test--with (registry list &rest body)
  "Run BODY in a temp dir holding REGISTRY and, when non-nil, grocery LIST.
`file' is the grocery list's path."
  (declare (indent 2))
  `(let* ((dir (file-name-as-directory (make-temp-file "groc" t)))
          (a3madkour-ingredients/file (expand-file-name "ingredients.org" dir))
          (file (expand-file-name "groceries.org" dir))
          (said nil))
     (ignore said)
     (unwind-protect
         (cl-letf (((symbol-function 'message)
                    (lambda (fmt &rest args) (setq said (apply #'format fmt args)))))
           (with-temp-file a3madkour-ingredients/file (insert ,registry))
           (when ,list (with-temp-file file (insert ,list)))
           ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b) (string-prefix-p dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory dir t))))

(defun a3madkour-groceries-test--text (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun a3madkour-groceries-test--state (name)
  (plist-get (a3madkour-ingredients/lookup name) :state))

(defconst a3madkour-groceries-test--fresh "#+TITLE: Groceries

* Produce
- [ ] leeks
- [ ] lemons
* Oils vinegar
- [ ] olive oil (low)
* Other
- [ ] rice
* Extra
")

(ert-deftest a3madkour-groceries--refresh-creates-the-list ()
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry nil
    (should (equal (a3madkour-groceries/file) file))
    (should (equal (a3madkour-groceries/refresh) '(:to-buy 4 :ticked 0)))
    (should (equal (a3madkour-groceries-test--text file) a3madkour-groceries-test--fresh))
    ;; Refreshing again changes nothing.
    (a3madkour-groceries/refresh)
    (should (equal (a3madkour-groceries-test--text file) a3madkour-groceries-test--fresh))))

(ert-deftest a3madkour-groceries--refresh-keeps-ticks-and-extras ()
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry
      "#+TITLE: Groceries
stray before any heading
* Produce
- [X] Leeks
- [ ] carrots
a note
* Oils vinegar
- [x] EVOO (low)
* Dairy
- [X] milk
* Extra
- [ ] bin bags
  - [X] the big ones

still extra
"
    (should (equal (a3madkour-groceries/refresh) '(:to-buy 4 :ticked 3)))
    (should (equal (a3madkour-groceries-test--text file) "#+TITLE: Groceries

* Produce
- [X] leeks
- [ ] lemons
* Oils vinegar
- [X] olive oil (low)
* Other
- [ ] rice
* Extra
- [ ] bin bags
  - [X] the big ones

still extra
stray before any heading
- [ ] carrots
a note
"))))

(ert-deftest a3madkour-groceries--an-aisle-called-extra-does-not-shadow-extra ()
  (a3madkour-groceries-test--with
      "#+TAGS: [ aisle : extra ]\n* gum :out:extra:\n" nil
    (a3madkour-groceries/refresh)
    (should (equal (a3madkour-groceries-test--text file)
                   "#+TITLE: Groceries\n\n* Extra (aisle)\n- [ ] gum\n* Extra\n"))
    (with-temp-buffer
      (insert-file-contents file) (goto-char (point-max)) (insert "- [ ] tape\n")
      (write-region nil nil file nil 'silent))
    (a3madkour-groceries/refresh)
    (should (equal (a3madkour-groceries-test--text file)
                   "#+TITLE: Groceries\n\n* Extra (aisle)\n- [ ] gum\n* Extra\n- [ ] tape\n"))))

(ert-deftest a3madkour-groceries--list-command ()
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry nil
    (a3-grocery-list)
    (should (equal (buffer-file-name) file))
    (should (equal said "4 to buy, 0 ticked"))
    ;; A sync conflict copy is mentioned, never touched.
    (let ((copy (expand-file-name "groceries.sync-conflict-20261115-101010-ABCDEFG.org" dir)))
      (with-temp-file copy (insert "x"))
      (a3-grocery-list)
      (should (equal said (concat "4 to buy, 0 ticked; sync conflict copy: " copy)))
      (should (equal (a3madkour-groceries-test--text copy) "x"))))
  (a3madkour-groceries-test--with "* salt :have:\n" nil
    (a3-grocery-list)
    (should (equal said "Nothing to buy"))
    (should (equal (a3madkour-groceries-test--text file) "#+TITLE: Groceries\n\n* Extra\n")))
  (let ((a3madkour-ingredients/file nil))
    (should (equal (cadr (should-error (a3-grocery-list) :type 'user-error))
                   "a3madkour-ingredients/file is not set"))))

(defconst a3madkour-groceries-test--shopped "#+TITLE: Groceries

* Produce
- [X] leeks
- [ ] lemons
* Oils vinegar
- [X] EVOO (low)
* Other
- [ ] rice
* Extra
- [X] bin bags
- [X] Salt
- [ ] tape
")

(ert-deftest a3madkour-groceries--done-marks-what-was-bought ()
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry
      a3madkour-groceries-test--shopped
    (let ((asked nil))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (setq asked prompt) t)))
        (a3-grocery-done))
      (should (equal asked "Mark 4 ticked items as bought? ")))
    (should (equal (mapcar #'a3madkour-groceries-test--state
                           '("leeks" "olive oil" "salt" "lemons" "rice" "milk"))
                   '(have have have out out have)))
    (should (equal (a3madkour-groceries-test--text file) "#+TITLE: Groceries

* Produce
- [ ] lemons
* Other
- [ ] rice
* Extra
- [ ] tape
"))
    (should (equal said "Marked 3 as have; 3 still to buy"))))

(ert-deftest a3madkour-groceries--done-declined-or-empty-changes-nothing ()
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry
      a3madkour-groceries-test--shopped
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) nil)))
      (a3-grocery-done))
    (should (equal (a3madkour-groceries-test--text file) a3madkour-groceries-test--shopped))
    (should (eq (a3madkour-groceries-test--state "leeks") 'out)))
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry
      a3madkour-groceries-test--fresh
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) (error "must not ask"))))
      (a3-grocery-done))
    (should (equal said "Nothing is ticked"))
    (should (equal (a3madkour-groceries-test--text file) a3madkour-groceries-test--fresh))))

(ert-deftest a3madkour-groceries--ticks-synced-in-under-an-open-buffer-are-kept ()
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry
      a3madkour-groceries-test--fresh
    (find-file-noselect file)
    (with-temp-file file
      (insert (replace-regexp-in-string "\\[ \\] rice" "[X] rice"
                                        a3madkour-groceries-test--fresh)))
    (set-file-times file (time-add (current-time) 7))
    (should (equal (a3madkour-groceries/refresh) '(:to-buy 3 :ticked 1)))
    (should (string-match-p "^- \\[X\\] rice$" (a3madkour-groceries-test--text file)))))

(ert-deftest a3madkour-groceries--refuses-unsaved-edits-over-a-changed-file ()
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry
      a3madkour-groceries-test--fresh
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max)) (insert "- [ ] tape\n"))
    (with-temp-file file (insert a3madkour-groceries-test--fresh "- [ ] glue\n"))
    (set-file-times file (time-add (current-time) 7))
    (let ((disk (a3madkour-groceries-test--text file)))
      (should (equal (cadr (should-error (a3madkour-groceries/refresh) :type 'user-error))
                     "The grocery list has unsaved changes and the file changed on disk; save or revert it first"))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
        (should-error (a3-grocery-done) :type 'user-error))
      (should (equal (a3madkour-groceries-test--text file) disk)))))

(ert-deftest a3madkour-groceries--unsaved-ticks-in-the-buffer-count ()
  "Ticks made in the buffer but not yet saved are what a refresh works from."
  (a3madkour-groceries-test--with a3madkour-groceries-test--registry
      a3madkour-groceries-test--fresh
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min)) (search-forward "[ ] rice") (replace-match "[X] rice" t t))
    (a3madkour-groceries/refresh)
    (should (string-match-p "^- \\[X\\] rice$" (a3madkour-groceries-test--text file)))))

(provide 'a3madkour-groceries-test)
;;; a3madkour-groceries-test.el ends here
