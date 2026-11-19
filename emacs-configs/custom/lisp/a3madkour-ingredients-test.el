;;; a3madkour-ingredients-test.el --- tests for the ingredient registry  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'ucs-normalize)
(require 'a3madkour-ingredients)

(defconst a3madkour-ingredients-test--registry "#+TITLE: Ingredients
#+TAGS: { have(h) low(l) out(o) }
#+TAGS: [ aisle : oils_vinegar dairy(d) ]

* olive oil :have:staple:oils_vinegar:
:PROPERTIES:
:ALIASES: extra-virgin olive oil, , EVOO,
:UNIT: tbsp
:END:
Bought at the co-op.
** a note heading :out:
* rice vinegar :out:oils_vinegar:
* crème fraîche :low:Dairy:
* water
")

(defmacro a3madkour-ingredients-test--with (text &rest body)
  "Run BODY with `a3madkour-ingredients/file' bound to a temp file holding TEXT."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "ingr" t))
          (a3madkour-ingredients/file (expand-file-name "ingredients.org" dir)))
     (unwind-protect
         (progn (when ,text (with-temp-file a3madkour-ingredients/file (insert ,text)))
                ,@body)
       (let ((b (get-file-buffer a3madkour-ingredients/file)))
         (when b (with-current-buffer b (set-buffer-modified-p nil)) (kill-buffer b)))
       (delete-directory dir t))))

;;; Reading

(ert-deftest a3madkour-ingredients--entries-parse ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (let ((es (a3madkour-ingredients/entries)))
      (should (equal (mapcar (lambda (e) (plist-get e :name)) es)
                     '("olive oil" "rice vinegar" "crème fraîche" "water")))
      (should (equal (mapcar (lambda (e) (plist-get e :state)) es) '(have out low nil)))
      (should (equal (plist-get (car es) :aliases) '("extra-virgin olive oil" "EVOO")))
      ;; The aisle is the aisle line's spelling of a tag the heading carries.
      (should (equal (mapcar (lambda (e) (plist-get e :aisle)) es)
                     '("oils_vinegar" "oils_vinegar" "dairy" nil)))
      (should (equal (plist-get (car es) :tags) '("have" "staple" "oils_vinegar")))
      (should (equal (plist-get (car es) :unit) "tbsp"))
      (should (= (plist-get (car es) :line) 5))
      (should (equal (a3madkour-ingredients/aisles) '("oils_vinegar" "dairy"))))))

(ert-deftest a3madkour-ingredients--aisle-line-forms ()
  "Both groups on one line, braces, and an ingredient carrying two aisles."
  (a3madkour-ingredients-test--with "#+tags: { have low out } { aisle : b a }\n* x :a:b:\n* y :other:\n"
    (should (equal (a3madkour-ingredients/aisles) '("b" "a")))
    (should (equal (mapcar (lambda (e) (plist-get e :aisle)) (a3madkour-ingredients/entries))
                   '("b" nil)))
    (should-not (a3madkour-ingredients/problems)))
  ;; Several aisle lines read as one; no aisle line at all is fine.
  (a3madkour-ingredients-test--with "#+TAGS: [ aisle : a ]\n#+TAGS: [ aisle : b ]\n* x :b:\n"
    (should (equal (a3madkour-ingredients/aisles) '("a" "b"))))
  (a3madkour-ingredients-test--with "* x :have:b:\n"
    (should-not (a3madkour-ingredients/aisles))
    (should-not (plist-get (car (a3madkour-ingredients/entries)) :aisle))
    (should-not (a3madkour-ingredients/problems))))

(ert-deftest a3madkour-ingredients--lookup-normalises ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (should (equal (plist-get (a3madkour-ingredients/lookup "  Crème   Fraîche ") :name) "crème fraîche"))
    (should (equal (plist-get (a3madkour-ingredients/lookup "evoo") :name) "olive oil"))
    (should-not (a3madkour-ingredients/lookup "a note heading"))
    (should-not (a3madkour-ingredients/lookup "saffron"))
    (should-not (a3madkour-ingredients/lookup ""))))

(ert-deftest a3madkour-ingredients--unset-missing-empty ()
  (let ((a3madkour-ingredients/file nil)) (should-not (a3madkour-ingredients/entries)))
  (a3madkour-ingredients-test--with nil (should-not (a3madkour-ingredients/entries)))
  (a3madkour-ingredients-test--with "#+TITLE: Ingredients\n#+TAGS: { have(h) low(l) out(o) }\n"
    (should-not (a3madkour-ingredients/entries))
    (should-not (a3madkour-ingredients/lookup "olive oil"))))

(ert-deftest a3madkour-ingredients--cache-follows-file-and-buffer ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (should-not (a3madkour-ingredients/lookup "saffron"))
    ;; A change on disk is seen (force a different mtime).
    (with-temp-file a3madkour-ingredients/file
      (insert a3madkour-ingredients-test--registry "* saffron :out:\n"))
    (set-file-times a3madkour-ingredients/file (time-add (current-time) 5))
    (should (a3madkour-ingredients/lookup "saffron"))
    ;; Unsaved edits in a visiting buffer win over the file.
    (with-current-buffer (find-file-noselect a3madkour-ingredients/file)
      (goto-char (point-max)) (insert "* sumac :out:\n")
      (should (a3madkour-ingredients/lookup "sumac")))))

;;; Problems and sync-conflict copies

(ert-deftest a3madkour-ingredients--problems-clean ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (should-not (a3madkour-ingredients/problems))))

(ert-deftest a3madkour-ingredients--problems-found ()
  (a3madkour-ingredients-test--with "* cumin :have:
:PROPERTIES:
:ALIASES: jeera
:END:
* Jeera :out:
* TODO paprika
* HAVE salt
* pepper :have:out:
* thyme :whatever:else:
** deeper :have:out:
"
    (should (equal (a3madkour-ingredients/problems)
                   '("ingredients.org:5: duplicate name \"jeera\" (also line 1)"
                     "ingredients.org:6: \"TODO\" is a keyword, not part of a name; mark state with a tag (:have:, :low: or :out:)"
                     "ingredients.org:7: \"HAVE\" is a keyword, not part of a name; mark state with a tag (:have:, :low: or :out:)"
                     "ingredients.org:8: ingredient \"pepper\" has more than one state tag")))))

(ert-deftest a3madkour-ingredients--conflict-files ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (should-not (a3madkour-ingredients/conflict-files))
    (let ((c (expand-file-name "ingredients.sync-conflict-20261115-101010-ABCDEFG.org"
                               (file-name-directory a3madkour-ingredients/file))))
      (with-temp-file c (insert "x"))
      (should (equal (a3madkour-ingredients/conflict-files) (list c)))
      ;; The conflict copy is never read: the registry still answers from the main file.
      (should (equal (length (a3madkour-ingredients/entries)) 4))
      (should (equal (with-temp-buffer (insert-file-contents c) (buffer-string)) "x"))
      ;; A re-read says so, once.
      (set-file-times a3madkour-ingredients/file (time-add (current-time) 9))
      (let ((said '()))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args) (push (apply #'format fmt args) said))))
          (a3madkour-ingredients/entries)
          (a3madkour-ingredients/entries))
        (should (equal said (list (concat "Ingredient registry has a sync conflict copy: " c))))))))

;;; Editing the registry

(defun a3madkour-ingredients-test--file-text ()
  (with-temp-buffer (insert-file-contents a3madkour-ingredients/file) (buffer-string)))

(ert-deftest a3madkour-ingredients--add-creates-file ()
  (a3madkour-ingredients-test--with nil
    (a3madkour-ingredients/add-entry "cumin" "Spices & herbs" '("jeera") "tsp" 'low)
    (should (equal (a3madkour-ingredients-test--file-text)
                   "#+TITLE: Ingredients\n#+TAGS: { have(h) low(l) out(o) }\n#+TAGS: [ aisle : spices_herbs ]\n\n* cumin :low:spices_herbs:\n:PROPERTIES:\n:ALIASES: jeera\n:UNIT: tsp\n:END:\n"))))

(ert-deftest a3madkour-ingredients--add-appends-at-the-end ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (a3madkour-ingredients/add-entry "sesame oil" " Oils &  VINEGAR ")
    (should (equal (mapcar (lambda (e) (plist-get e :name)) (a3madkour-ingredients/entries))
                   '("olive oil" "rice vinegar" "crème fraîche" "water" "sesame oil")))
    (should (equal (plist-get (a3madkour-ingredients/lookup "sesame oil") :aisle) "oils_vinegar"))
    (should-not (plist-get (a3madkour-ingredients/lookup "sesame oil") :state))
    ;; A known aisle leaves the aisle line alone.
    (should (equal (a3madkour-ingredients/aisles) '("oils_vinegar" "dairy")))
    ;; The aisle is optional.
    (a3madkour-ingredients/add-entry "bin bags")
    (should-not (plist-get (a3madkour-ingredients/lookup "bin bags") :aisle))
    (should (string-match-p "^\\* bin bags$" (a3madkour-ingredients-test--file-text)))
    ;; A new aisle joins the end of the aisle line.
    (a3madkour-ingredients/add-entry "leeks" "Produce" nil nil 'out)
    (should (string-match-p "^#\\+TAGS: \\[ aisle : oils_vinegar dairy(d) produce \\]$"
                            (a3madkour-ingredients-test--file-text)))
    (should (string-match-p "^\\* leeks :out:produce:$" (a3madkour-ingredients-test--file-text)))
    (should (equal (plist-get (a3madkour-ingredients/lookup "leeks") :aisle) "produce"))
    ;; An aisle with nothing a tag can hold is no aisle.
    (a3madkour-ingredients/add-entry "string" " & ")
    (should (string-match-p "^\\* string$" (a3madkour-ingredients-test--file-text)))
    (should-not (a3madkour-ingredients/problems))))

(ert-deftest a3madkour-ingredients--add-to-a-file-without-a-final-newline ()
  (a3madkour-ingredients-test--with "* salt :have:"
    (a3madkour-ingredients/add-entry "pepper")
    (should (equal (a3madkour-ingredients-test--file-text) "* salt :have:\n* pepper\n"))))

(ert-deftest a3madkour-ingredients--add-refuses-clash ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (should (equal (cadr (should-error (a3madkour-ingredients/add-entry "EVOO" "Dairy") :type 'user-error))
                   "\"EVOO\" is already in the registry as \"olive oil\" (oils_vinegar)"))
    (should (equal (cadr (should-error (a3madkour-ingredients/add-entry "WATER") :type 'user-error))
                   "\"WATER\" is already in the registry as \"water\""))
    (should-error (a3madkour-ingredients/add-entry "ghee" "Dairy" '("water")) :type 'user-error)
    (should-not (a3madkour-ingredients/lookup "ghee"))))

(ert-deftest a3madkour-ingredients--add-alias ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (a3madkour-ingredients/add-alias "rice vinegar" "rice wine vinegar")
    (a3madkour-ingredients/add-alias "evoo" "good olive oil")
    (should (equal (plist-get (a3madkour-ingredients/lookup "rice wine vinegar") :name) "rice vinegar"))
    (should (equal (plist-get (a3madkour-ingredients/lookup "olive oil") :aliases)
                   '("extra-virgin olive oil" "EVOO" "good olive oil")))
    (should-error (a3madkour-ingredients/add-alias "saffron" "x") :type 'user-error)
    (should-error (a3madkour-ingredients/add-alias "rice vinegar" "water") :type 'user-error)
    (should-not (a3madkour-ingredients/problems))))

(ert-deftest a3madkour-ingredients--set-state ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (a3madkour-ingredients/set-entry-state "EVOO" 'out)
    (a3madkour-ingredients/set-entry-state "water" 'have)
    (a3madkour-ingredients/set-entry-state "rice vinegar" nil)
    (should (equal (mapcar (lambda (e) (plist-get e :state)) (a3madkour-ingredients/entries))
                   '(out nil low have)))
    (let ((text (a3madkour-ingredients-test--file-text)))
      ;; The state tag is replaced; other tags and the name are left alone.
      (should (string-match-p "^\\* olive oil :out:staple:oils_vinegar:$" text))
      (should (string-match-p "^\\* water :have:$" text))
      (should (string-match-p "^\\* rice vinegar :oils_vinegar:$" text)))
    (should (equal (cadr (should-error (a3madkour-ingredients/set-entry-state "saffron" 'out)
                                       :type 'user-error))
                   "No ingredient \"saffron\" in the registry"))))

(ert-deftest a3madkour-ingredients--header-makes-the-states-one-exclusive-tag-group ()
  "The header the module writes gives org's tag command (C-c C-q) the three
states as a mutually exclusive group with h/l/o shortcuts, and leaves the
buffer's TODO keywords alone."
  (let ((global (with-temp-buffer (insert "* A\n") (org-mode) org-todo-keywords-1)))
    (with-temp-buffer
      (insert a3madkour-ingredients--header "* A\n** x :have:\n")
      (org-mode)
      (should (equal (cl-remove-if-not #'stringp (mapcar #'car org-current-tag-alist))
                     '("have" "low" "out")))
      (should (assq :startgroup org-current-tag-alist))
      (should (equal (assoc "low" org-current-tag-alist) '("low" . ?l)))
      (should (equal org-todo-keywords-1 global)))))

(ert-deftest a3madkour-ingredients--state-tags-read-in-any-case-and-position ()
  (a3madkour-ingredients-test--with "* salt :staple:HAVE:\n* TODO-list paper   :Out:\n"
    (should (equal (mapcar (lambda (e) (list (plist-get e :name) (plist-get e :state)))
                           (a3madkour-ingredients/entries))
                   '(("salt" have) ("TODO-list paper" out))))
    (should-not (a3madkour-ingredients/problems))
    ;; Setting a state normalises the tag and keeps the others.
    (a3madkour-ingredients/set-entry-state "salt" 'low)
    (should (string-match-p "^\\* salt :low:staple:$" (a3madkour-ingredients-test--file-text)))))

(ert-deftest a3madkour-ingredients--commands-need-a-file ()
  (let ((a3madkour-ingredients/file nil))
    (should (equal (cadr (should-error (a3madkour-ingredients/add-entry "x" "A") :type 'user-error))
                   "a3madkour-ingredients/file is not set"))
    (should-error (a3madkour-ingredients/add-alias "x" "y") :type 'user-error)
    (should-error (a3madkour-ingredients/set-entry-state "x" 'out) :type 'user-error)))

(ert-deftest a3madkour-ingredients--edit-sees-a-file-changed-under-an-open-buffer ()
  "The registry changed on disk (a sync) while an unmodified buffer visits it."
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (find-file-noselect a3madkour-ingredients/file)
    (with-temp-file a3madkour-ingredients/file
      (insert a3madkour-ingredients-test--registry "* sumac :out:\n"))
    (set-file-times a3madkour-ingredients/file (time-add (current-time) 7))
    (a3madkour-ingredients/set-entry-state "rice vinegar" 'have)
    (should (eq (plist-get (a3madkour-ingredients/lookup "sumac") :state) 'out))
    (should (eq (plist-get (a3madkour-ingredients/lookup "rice vinegar") :state) 'have))
    (should (eq (plist-get (a3madkour-ingredients/lookup "olive oil") :state) 'have))))

(ert-deftest a3madkour-ingredients--add-command ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (let ((answers '("ghee" "clarified butter, " "tbsp")) (said nil) (prompts '()))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop answers)))
                ((symbol-function 'completing-read)
                 (lambda (prompt &rest _)
                   (push prompt prompts)
                   (if (string-match-p "[Aa]isle" prompt) "Dairy" "have")))
                ((symbol-function 'message)
                 (lambda (fmt &rest args) (setq said (apply #'format fmt args)))))
        (call-interactively #'a3-ingredient-add)
        (should (equal said "Added ghee to dairy"))
        (should (member "Aisle (optional): " prompts))
        ;; No aisle given: the message names none.
        (setq answers '("twine" "" ""))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (prompt &rest _) (if (string-match-p "[Aa]isle" prompt) "" "out"))))
          (call-interactively #'a3-ingredient-add))
        (should (equal said "Added twine"))))
    (let ((e (a3madkour-ingredients/lookup "clarified butter")))
      (should (equal (plist-get e :name) "ghee"))
      (should (equal (plist-get e :aisle) "dairy"))
      (should (equal (plist-get e :unit) "tbsp"))
      (should (eq (plist-get e :state) 'have)))))

(ert-deftest a3madkour-ingredients--set-state-command ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "rice vinegar"))
              ((symbol-function 'read-multiple-choice) (lambda (_p cs &rest _) (assq ?l cs))))
      (call-interactively #'a3-ingredient-set-state))
    (should (eq (plist-get (a3madkour-ingredients/lookup "rice vinegar") :state) 'low))))

;;; Resolving a recipe

(defconst a3madkour-ingredients-test--recipe "#+TITLE: X
** ingredients
| qty | unit | item           | group | note | alt |
|-----+------+----------------+-------+------+-----|
| 2   | tbsp | EVOO           |       |      |     |
| 1   | tsp  | Smoked Paprika |       |      |     |
|     |      |                |       |      |     |
| 1   |      | smoked paprika |       |      |     |
| 1   |      | rice wine vinegar |    |      |     |
** Steps
1. Cook.
")

(ert-deftest a3madkour-ingredients--recipe-items-and-unknown ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (with-temp-buffer
      (insert a3madkour-ingredients-test--recipe) (org-mode)
      (should (equal (a3madkour-ingredients/recipe-items)
                     '("EVOO" "Smoked Paprika" "smoked paprika" "rice wine vinegar")))
      (should (equal (a3madkour-ingredients/unknown-items)
                     '("Smoked Paprika" "rice wine vinegar"))))))

(ert-deftest a3madkour-ingredients--recipe-items-degenerate ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (dolist (text '("" "#+TITLE: X\n** Steps\n1. Cook.\n" "** Ingredients\nNo table here.\n"
                    "** Ingredients\n| qty | unit |\n| 1 | g |\n"
                    "** Ingredients\n** Steps\n| qty | item |\n| 1 | saffron |\n"))
      (with-temp-buffer
        (insert text) (org-mode)
        (should-not (a3madkour-ingredients/recipe-items))
        (should-not (a3madkour-ingredients/unknown-items))
        (let ((said nil))
          (cl-letf (((symbol-function 'message)
                     (lambda (fmt &rest args) (setq said (apply #'format fmt args)))))
            (a3-ingredient-resolve-recipe))
          (should (equal said "All ingredients are in the registry")))))))

(defmacro a3madkour-ingredients-test--resolving (choices &rest body)
  "Run BODY in a buffer holding the test recipe, answering the per-item
question with CHOICES (a list of characters) in turn."
  (declare (indent 1))
  `(with-temp-buffer
     (insert a3madkour-ingredients-test--recipe) (org-mode)
     (let ((choices ,choices) (said nil))
       (ignore said)
       (cl-letf (((symbol-function 'read-multiple-choice)
                  (lambda (_prompt cs &rest _) (assq (pop choices) cs)))
                 ((symbol-function 'completing-read)
                  (lambda (prompt &rest _)
                    (cond ((string-match-p "[Aa]isle" prompt) "Spices")
                          ((string-match-p "[Ss]tate" prompt) "out")
                          (t "rice vinegar"))))
                 ((symbol-function 'read-string)
                  (lambda (_prompt &optional initial &rest _) (or initial "")))
                 ((symbol-function 'message)
                  (lambda (fmt &rest args) (setq said (apply #'format fmt args)))))
         ,@body))))

(ert-deftest a3madkour-ingredients--resolve-recipe ()
  "First unknown is added as new, second becomes an alias."
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (a3madkour-ingredients-test--resolving '(?a ?l)
      (a3-ingredient-resolve-recipe)
      (should (equal said "Resolved 2 of 2 ingredients"))
      (should (equal (plist-get (a3madkour-ingredients/lookup "smoked paprika") :aisle) "spices"))
      (should (eq (plist-get (a3madkour-ingredients/lookup "smoked paprika") :state) 'out))
      (should (equal (plist-get (a3madkour-ingredients/lookup "rice wine vinegar") :name) "rice vinegar"))
      (should-not (a3madkour-ingredients/unknown-items)))))

(ert-deftest a3madkour-ingredients--resolve-recipe-skip-and-quit ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (a3madkour-ingredients-test--resolving '(?s ?q)
      (a3-ingredient-resolve-recipe)
      (should (equal said "Resolved 0 of 2 ingredients"))
      (should (equal (a3madkour-ingredients/unknown-items)
                     '("Smoked Paprika" "rice wine vinegar"))))))

;;; Completion in the item column

(defun a3madkour-ingredients-test--capf-at (text marker)
  "Insert TEXT, put point where MARKER was, return the capf result."
  (with-temp-buffer
    (insert text) (org-mode)
    (goto-char (point-min)) (search-forward marker) (replace-match "")
    (a3madkour-ingredients/capf)))

(ert-deftest a3madkour-ingredients--capf-in-item-cell ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (let ((r (a3madkour-ingredients-test--capf-at
              "** Ingredients\n| qty | unit | Item | group | note | alt |\n|---+---+---+---+---+---|\n| 2 | tbsp | oli@ | | | |\n" "@")))
      (should r)
      (should (= (- (nth 1 r) (nth 0 r)) 3))
      (should (member "olive oil" (all-completions "" (nth 2 r))))
      (should (member "EVOO" (all-completions "" (nth 2 r))))
      ;; Case does not matter, and the cell is ours: nothing falls through to
      ;; other sources just because the typed text is not an exact-case prefix.
      (should (equal (all-completions "evoo" (nth 2 r)) '("EVOO")))
      (should (equal (all-completions "Olive" (nth 2 r)) '("olive oil")))
      (should-not (plist-member (nthcdr 3 r) :exclusive))
      (should (equal (funcall (plist-get (nthcdr 3 r) :annotation-function) "EVOO")
                     "  oils_vinegar"))
      (should-not (funcall (plist-get (nthcdr 3 r) :annotation-function) "water")))
    ;; An empty cell, and one under a #+NAME: line, complete too.
    (should (a3madkour-ingredients-test--capf-at
             "* Ingredients\n#+NAME: ingredients\n| qty | unit | item |\n| 2 | tbsp | @ |\n" "@"))))

(ert-deftest a3madkour-ingredients--capf-pops-up-from-the-first-letter ()
  "Corfu's automatic popup waits for three letters unless the capf says otherwise."
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (cl-flet ((len (cell)
                (plist-get (nthcdr 3 (a3madkour-ingredients-test--capf-at
                                      (concat "** Ingredients\n| qty | unit | item |\n| 2 | tbsp | "
                                              cell " |\n")
                                      "@"))
                           :company-prefix-length)))
      (should (eq (len "o@") t))
      (should (eq (len "ol@") t))
      ;; Nothing typed yet: no popup just for moving into the cell.
      (should-not (len "@")))))

(ert-deftest a3madkour-ingredients--capf-elsewhere-is-nil ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (dolist (text '("** Ingredients\n| qty | unit | item |\n| 2 | tb@ | oil |\n"      ; other column
                    "** Ingredients\n| qty | unit | it@ |\n| 2 | tbsp | oil |\n"      ; header row
                    "** Ingredients\n| qty | unit | item |\n|---+---+--@-|\n"         ; rule line
                    "** Ingredients\n| qty | unit | item |\n| 2 | tbsp | oil | @\n"   ; past the last bar
                    "** Ingredients\n| qty | unit | item |\n@| 2 | tbsp | oil |\n"    ; before the first bar
                    "** Steps\n| qty | unit | item |\n| 2 | tbsp | ol@ |\n"          ; other heading
                    "| qty | unit | item |\n| 2 | tbsp | ol@ |\n"                     ; no heading
                    "** Ingredients\nplain te@xt\n"                                   ; no table
                    "@"))                                                             ; empty buffer
      (should-not (a3madkour-ingredients-test--capf-at text "@"))))
  (let ((a3madkour-ingredients/file nil))
    (should-not (a3madkour-ingredients-test--capf-at
                 "** Ingredients\n| qty | unit | item |\n| 2 | tbsp | ol@ |\n" "@"))))

(ert-deftest a3madkour-ingredients--setup-capf-is-buffer-local ()
  (with-temp-buffer
    (a3madkour-ingredients/setup-capf)
    (should (eq (car completion-at-point-functions) #'a3madkour-ingredients/capf))
    (should (local-variable-p 'completion-at-point-functions)))
  (should-not (memq #'a3madkour-ingredients/capf (default-value 'completion-at-point-functions))))

(ert-deftest a3madkour-ingredients--add-command-starts-from-the-item-at-point ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (with-temp-buffer
      (insert "** Ingredients\n| qty | unit | item |\n| 1 | tsp | Smoked Paprika |\n") (org-mode)
      (goto-char (point-min)) (search-forward "Smoked")
      (let ((initials '()))
        (cl-letf (((symbol-function 'read-string)
                   (lambda (_p &optional initial &rest _) (push initial initials) (or initial "")))
                  ((symbol-function 'completing-read)
                   (lambda (prompt &rest _) (if (string-match-p "[Aa]isle" prompt) "Spices" "out"))))
          (call-interactively #'a3-ingredient-add))
        (should (equal (car (last initials)) "Smoked Paprika"))
        (should (a3madkour-ingredients/lookup "smoked paprika"))))))

;;; Review fixes: the editor never writes what the reader rejects

(ert-deftest a3madkour-ingredients--add-alias-on-a-last-line-without-newline ()
  (a3madkour-ingredients-test--with "* pepper"
    (a3madkour-ingredients/add-alias "pepper" "black pepper")
    (should (equal (a3madkour-ingredients-test--file-text)
                   "* pepper\n:PROPERTIES:\n:ALIASES: black pepper\n:END:\n"))
    (should (equal (plist-get (a3madkour-ingredients/lookup "black pepper") :name) "pepper"))))

(ert-deftest a3madkour-ingredients--alias-with-a-comma-is-refused ()
  (a3madkour-ingredients-test--with "* tomato\n:PROPERTIES:\n:ALIASES: tomatoes\n:END:\n"
    (let ((before (a3madkour-ingredients-test--file-text)))
      (should (equal (cadr (should-error (a3madkour-ingredients/add-alias "tomato" "tomatoes, crushed")
                                         :type 'user-error))
                     "An alias cannot contain a comma: \"tomatoes, crushed\""))
      (should-error (a3madkour-ingredients/add-entry "passata" "Veg" '("sieved, tomatoes"))
                    :type 'user-error)
      (should (equal (a3madkour-ingredients-test--file-text) before))
      (should-not (a3madkour-ingredients/problems)))
    ;; A name may contain one: it is a heading, not a list.
    (a3madkour-ingredients/add-entry "tomatoes, crushed" "Veg")
    (should (a3madkour-ingredients/lookup "Tomatoes, Crushed"))))

(ert-deftest a3madkour-ingredients--capitalised-names-are-not-states ()
  (a3madkour-ingredients-test--with "* MSG powder :have:\n"
    (a3madkour-ingredients/add-entry "BBQ sauce" "Sauces" nil nil 'out)
    (should (a3madkour-ingredients/lookup "bbq sauce"))
    (should-not (a3madkour-ingredients/problems))))

(ert-deftest a3madkour-ingredients--names-the-reader-would-misread-are-refused ()
  (a3madkour-ingredients-test--with "* butter :have:\n"
    (let ((before (a3madkour-ingredients-test--file-text)))
      (dolist (name '("LOW fat milk" "TODO cream" "stock :homemade:" "two\nlines" "  "))
        (should-error (a3madkour-ingredients/add-entry name "Dairy") :type 'user-error))
      (should-error (a3madkour-ingredients/add-alias "butter" "two\nlines") :type 'user-error)
      (should (equal (a3madkour-ingredients-test--file-text) before)))
    (a3madkour-ingredients/add-entry "low fat milk" "Dairy")
    (should-not (plist-get (a3madkour-ingredients/lookup "low fat milk") :state))))

(ert-deftest a3madkour-ingredients--a-new-registry-buffer-knows-its-states ()
  "After the first add creates the file, the in-file keyword keys cycle
the three state tags as one exclusive group, with their one-key shortcuts."
  (a3madkour-ingredients-test--with nil
    (a3madkour-ingredients/add-entry "cumin" "Spices" nil nil 'low)
    (with-current-buffer (get-file-buffer a3madkour-ingredients/file)
      (should (equal (assoc "have" org-current-tag-alist) '("have" . ?h)))
      (should (equal (assoc "out" org-current-tag-alist) '("out" . ?o))))))

;;; Leftovers from the registry review

(ert-deftest a3madkour-ingredients--edit-refuses-a-dirty-buffer-over-a-changed-file ()
  "Unsaved edits in the buffer and a newer file on disk: neither may be lost."
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (with-current-buffer (find-file-noselect a3madkour-ingredients/file)
      (goto-char (point-max)) (insert "* sumac :out:\n"))
    (with-temp-file a3madkour-ingredients/file
      (insert a3madkour-ingredients-test--registry "* saffron :out:\n"))
    (set-file-times a3madkour-ingredients/file (time-add (current-time) 7))
    (let ((disk (a3madkour-ingredients-test--file-text)))
      (should (equal (cadr (should-error (a3madkour-ingredients/set-entry-state "water" 'have)
                                         :type 'user-error))
                     "The registry buffer has unsaved changes and the file changed on disk; save or revert it first"))
      (should-error (a3madkour-ingredients/add-entry "ghee") :type 'user-error)
      (should (equal (a3madkour-ingredients-test--file-text) disk)))))

(ert-deftest a3madkour-ingredients--add-alias-stays-inside-the-drawer ()
  (a3madkour-ingredients-test--with
      "* salt :have:\n  :PROPERTIES:\n  :UNIT: tsp\n  :END:\nIn body text:\n:ALIASES: not a property\n* pepper\nSome text.\n:PROPERTIES:\n:END:\n"
    (a3madkour-ingredients/add-alias "salt" "sea salt")
    (a3madkour-ingredients/add-alias "salt" "table salt")
    ;; A drawer that does not directly follow the heading is body text.
    (a3madkour-ingredients/add-alias "pepper" "black pepper")
    (should (equal (a3madkour-ingredients-test--file-text)
                   "* salt :have:\n  :PROPERTIES:\n  :ALIASES: sea salt, table salt\n  :UNIT: tsp\n  :END:\nIn body text:\n:ALIASES: not a property\n* pepper\n:PROPERTIES:\n:ALIASES: black pepper\n:END:\nSome text.\n:PROPERTIES:\n:END:\n"))
    (should (equal (plist-get (a3madkour-ingredients/lookup "table salt") :name) "salt"))
    (should (equal (plist-get (a3madkour-ingredients/lookup "black pepper") :name) "pepper"))))

(ert-deftest a3madkour-ingredients--decomposed-names-match ()
  (let ((nfd (ucs-normalize-NFD-string "crème fraîche")))
    (should-not (string= nfd "crème fraîche"))
    (a3madkour-ingredients-test--with "* crème fraîche\n"
      (should (a3madkour-ingredients/lookup nfd)))
    (a3madkour-ingredients-test--with (concat "* crème fraîche\n* " nfd "\n")
      (should (= (length (a3madkour-ingredients/problems)) 1)))))

(ert-deftest a3madkour-ingredients--resolve-does-not-offer-alias-on-an-empty-registry ()
  (a3madkour-ingredients-test--with nil
    (with-temp-buffer
      (insert a3madkour-ingredients-test--recipe) (org-mode)
      (let ((offered '()))
        (cl-letf (((symbol-function 'read-multiple-choice)
                   (lambda (_prompt cs &rest _)
                     (setq offered (mapcar #'car cs))
                     (assq ?s cs)))
                  ((symbol-function 'message) #'ignore))
          (a3-ingredient-resolve-recipe))
        (should (equal offered '(?a ?s ?q)))))))

(provide 'a3madkour-ingredients-test)
;;; a3madkour-ingredients-test.el ends here
