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

;;; Recipes on the list

(defconst a3madkour-groceries-test--toast "#+TITLE: Toast
#+HUGO_SECTION: recipes
** Ingredients
| qty | unit | item   | group | note | alt |
|-----+------+--------+-------+------+-----|
| 2   | tbsp | EVOO   |       |      |     |
| 1   |      | Leeks  |       |      |     |
| 200 | g    | milk   |       |      |     |
| 1   | tsp  | salt   |       |      |     |
| 3   | cloves | Garlic |     |      |     |
|     |      |        |       |      |     |
")

(defconst a3madkour-groceries-test--soup "#+TITLE: Soup
#+HUGO_SECTION: recipes
#+HUGO_PUBLISH: nil
** Ingredients
| qty | unit   | item      | group | note | alt |
| 1   | Tablespoon | olive oil |   |      |     |
| 3   | tsp    | olive oil |       |      |     |
| 2   | cloves | garlic    |       |      |     |
|     | pinch  | salt      |       |      |     |
")

(defconst a3madkour-groceries-test--planned "#+TITLE: Groceries

* Produce
- [ ] leeks (1: Toast)
- [ ] lemons
* Oils vinegar
- [ ] olive oil (low) (4 tbsp: Toast, Soup)
* Other
- [ ] rice
- [ ] salt (1 tsp: Toast, Soup)
- [ ] Garlic (5 cloves: Toast, Soup)
* Extra
* Recipes
- [[file:toast.org][Toast]]
- [[file:soup.org][an old title]]
")

(defmacro a3madkour-groceries-test--with-recipes (list &rest body)
  (declare (indent 1))
  `(a3madkour-groceries-test--with a3madkour-groceries-test--registry ,list
     (with-temp-file (expand-file-name "toast.org" dir)
       (insert a3madkour-groceries-test--toast))
     (with-temp-file (expand-file-name "soup.org" dir)
       (insert a3madkour-groceries-test--soup))
     (with-temp-file (expand-file-name "note.org" dir) (insert "#+TITLE: Not a recipe\n"))
     ,@body))

(ert-deftest a3madkour-groceries--recipes-are-found-and-read ()
  (a3madkour-groceries-test--with-recipes nil
    (should (equal (a3madkour-recipes/files)
                   (list (cons "Soup" (expand-file-name "soup.org" dir))
                         (cons "Toast" (expand-file-name "toast.org" dir)))))
    (should (equal (a3madkour-recipes/rows (expand-file-name "soup.org" dir))
                   '((:item "olive oil" :qty "1" :unit "Tablespoon")
                     (:item "olive oil" :qty "3" :unit "tsp")
                     (:item "garlic" :qty "2" :unit "cloves")
                     (:item "salt" :qty nil :unit "pinch"))))
    (should-not (a3madkour-recipes/title (expand-file-name "note.org" dir)))))

(ert-deftest a3madkour-groceries--planned-recipes-add-what-is-not-had ()
  "Amounts are summed; what the pantry has (milk) is left off; an untracked
ingredient (salt) and one the registry does not know (garlic) are needed."
  (a3madkour-groceries-test--with-recipes
      "* Recipes\n- [[file:toast.org][Toast]]\n- [[file:soup.org][an old title]]\n- [[file:gone.org][Gone]]\nplain line\n"
    (should (equal (a3madkour-groceries/refresh) '(:to-buy 6 :ticked 0)))
    (should (equal (a3madkour-groceries-test--text file)
                   (concat a3madkour-groceries-test--planned
                           "- [[file:gone.org][Gone]]\nplain line\n")))
    ;; Stable under a second refresh, annotations and all.
    (a3madkour-groceries/refresh)
    (should (equal (a3madkour-groceries-test--text file)
                   (concat a3madkour-groceries-test--planned
                           "- [[file:gone.org][Gone]]\nplain line\n")))))

(ert-deftest a3madkour-groceries--the-registry-unit-is-the-one-shown ()
  (a3madkour-groceries-test--with
      "* olive oil :out:\n:PROPERTIES:\n:UNIT: ml\n:END:\n"
      "* Recipes\n- [[file:soup.org][Soup]]\n"
    (with-temp-file (expand-file-name "soup.org" dir)
      (insert "#+TITLE: Soup\n#+HUGO_SECTION: recipes\n** Ingredients\n| qty | unit | item |\n| 2 | tbsp | olive oil |\n"))
    (a3madkour-groceries/refresh)
    (should (string-match-p "^- \\[ \\] olive oil (29\\.57 ml: Soup)$"
                            (a3madkour-groceries-test--text file)))))

(ert-deftest a3madkour-groceries--toggle-recipe ()
  (a3madkour-groceries-test--with-recipes nil
    (should (a3madkour-groceries/toggle-recipe (expand-file-name "toast.org" dir)))
    (should (a3madkour-groceries/toggle-recipe (expand-file-name "soup.org" dir)))
    (should (equal (a3madkour-groceries-test--text file)
                   (replace-regexp-in-string "an old title" "Soup"
                                             a3madkour-groceries-test--planned)))
    (should-not (a3madkour-groceries/toggle-recipe (expand-file-name "toast.org" dir)))
    (should-not (a3madkour-groceries/toggle-recipe (expand-file-name "soup.org" dir)))
    (should (equal (a3madkour-groceries-test--text file) a3madkour-groceries-test--fresh))
    (should-error (a3madkour-groceries/toggle-recipe (expand-file-name "note.org" dir))
                  :type 'user-error)))

(ert-deftest a3madkour-groceries--plan-command-defaults-to-the-recipe-at-hand ()
  (a3madkour-groceries-test--with-recipes nil
    (find-file (expand-file-name "toast.org" dir))
    (let ((default nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_p _c &optional _pred _req _init _hist def &rest _)
                   (setq default def))))
        (call-interactively #'a3-grocery-plan-recipe)
        (should (equal default "Toast"))
        (should (equal said "Shopping for Toast: 6 to buy"))
        (call-interactively #'a3-grocery-plan-recipe)
        (should (equal said "No longer shopping for Toast"))))))

(ert-deftest a3madkour-groceries--done-with-recipe-items ()
  (a3madkour-groceries-test--with-recipes
      (replace-regexp-in-string
       "\\[ \\] \\(leeks\\|salt\\|Garlic\\)" "[X] \\1"
       a3madkour-groceries-test--planned)
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_) t)))
      (a3-grocery-done))
    (should (equal said "Marked 3 as have; 3 still to buy"))
    ;; Garlic was not in the registry: buying it put it there.
    (should (equal (mapcar #'a3madkour-groceries-test--state '("leeks" "salt" "garlic" "olive oil"))
                   '(have have have low)))
    (should (equal (a3madkour-groceries-test--text file) "#+TITLE: Groceries

* Produce
- [ ] lemons
* Oils vinegar
- [ ] olive oil (low) (4 tbsp: Toast, Soup)
* Other
- [ ] rice
* Extra
* Recipes
- [[file:toast.org][Toast]]
- [[file:soup.org][an old title]]
"))))

(ert-deftest a3madkour-groceries-test-strip-note ()
  (should (equal (a3madkour-groceries--strip-note "lentils (1 cup: Soup (Indian-Inspired))")
                 "lentils"))
  (should (equal (a3madkour-groceries--strip-note "lentils (low) (2 tbsp: Toast)") "lentils (low)"))
  (should (equal (a3madkour-groceries--strip-note "lentils (low)") "lentils"))
  (should (null (a3madkour-groceries--strip-note "lentils")))
  (should (null (a3madkour-groceries--strip-note "lentils (low")))
  (should (null (a3madkour-groceries--strip-note "lentils low)"))))

(ert-deftest a3madkour-groceries-test-refresh-is-stable-for-a-title-with-parentheses ()
  (a3madkour-groceries-test--with "* lentils :out:\n"
      "* Recipes\n- [[file:soup.org][Soup]]\n"
    (with-temp-file (expand-file-name "soup.org" dir)
      (insert "#+TITLE: Instant Pot Curried Lentil Soup (Indian-Inspired)\n#+HUGO_SECTION: recipes\n** Ingredients\n| qty | unit | item |\n| 1 | cup | lentils |\n"))
    (a3madkour-groceries/refresh)
    (let ((first (a3madkour-groceries-test--text file)))
      (with-temp-file file
        (insert (replace-regexp-in-string "- \\[ \\] lentils" "- [X] lentils" first)))
      (a3madkour-groceries/refresh)
      (let ((second (a3madkour-groceries-test--text file)))
        (a3madkour-groceries/refresh)
        (let ((third (a3madkour-groceries-test--text file)))
          (should (string-match-p
                   "^- \\[X\\] lentils (1 cup: Instant Pot Curried Lentil Soup (Indian-Inspired))$"
                   second))
          (should (equal second third))
          (should (= 1 (length (seq-filter (lambda (l) (string-match-p "lentils" l))
                                           (split-string second "\n"))))))))))

(provide 'a3madkour-groceries-test)
;;; a3madkour-groceries-test.el ends here
