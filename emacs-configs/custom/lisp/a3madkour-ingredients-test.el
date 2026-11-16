;;; a3madkour-ingredients-test.el --- tests for the ingredient registry  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'a3madkour-ingredients)

(defconst a3madkour-ingredients-test--registry "#+TITLE: Ingredients
#+TODO: HAVE LOW OUT |

* Oils & vinegar
** HAVE olive oil :staple:
:PROPERTIES:
:ALIASES: extra-virgin olive oil, , EVOO,
:UNIT: tbsp
:END:
Bought at the co-op.
*** a note heading
** OUT rice vinegar
* Dairy
** LOW crème fraîche
** water
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
      (should (equal (plist-get (car es) :aisle) "Oils & vinegar"))
      (should (equal (plist-get (car es) :unit) "tbsp"))
      (should (= (plist-get (car es) :line) 5))
      (should (equal (a3madkour-ingredients/aisles) '("Oils & vinegar" "Dairy"))))))

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
  (a3madkour-ingredients-test--with "#+TITLE: Ingredients\n#+TODO: HAVE LOW OUT |\n"
    (should-not (a3madkour-ingredients/entries))
    (should-not (a3madkour-ingredients/lookup "olive oil"))))

(ert-deftest a3madkour-ingredients--cache-follows-file-and-buffer ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (should-not (a3madkour-ingredients/lookup "saffron"))
    ;; A change on disk is seen (force a different mtime).
    (with-temp-file a3madkour-ingredients/file
      (insert a3madkour-ingredients-test--registry "** OUT saffron\n"))
    (set-file-times a3madkour-ingredients/file (time-add (current-time) 5))
    (should (a3madkour-ingredients/lookup "saffron"))
    ;; Unsaved edits in a visiting buffer win over the file.
    (with-current-buffer (find-file-noselect a3madkour-ingredients/file)
      (goto-char (point-max)) (insert "** OUT sumac\n")
      (should (a3madkour-ingredients/lookup "sumac")))))

;;; Problems and sync-conflict copies

(ert-deftest a3madkour-ingredients--problems-clean ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (should-not (a3madkour-ingredients/problems))))

(ert-deftest a3madkour-ingredients--problems-found ()
  (a3madkour-ingredients-test--with "** HAVE stray
* Spices
** HAVE cumin
:PROPERTIES:
:ALIASES: jeera
:END:
** OUT Jeera
** TODO paprika
"
    (should (equal (a3madkour-ingredients/problems)
                   '("ingredients.org:1: ingredient \"stray\" is outside any aisle"
                     "ingredients.org:7: duplicate name \"jeera\" (also line 3)"
                     "ingredients.org:8: \"TODO\" is not a state (use HAVE, LOW or OUT)")))))

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
    (a3madkour-ingredients/add-entry "cumin" "Spices" '("jeera") "tsp" 'low)
    (should (equal (a3madkour-ingredients-test--file-text)
                   "#+TITLE: Ingredients\n#+TODO: HAVE LOW | OUT\n#+STARTUP: nologdone\n\n* Spices\n** LOW cumin\n:PROPERTIES:\n:ALIASES: jeera\n:UNIT: tsp\n:END:\n"))))

(ert-deftest a3madkour-ingredients--add-into-existing-aisle ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (a3madkour-ingredients/add-entry "sesame oil" "oils &  VINEGAR" nil nil nil)
    (should (equal (mapcar (lambda (e) (plist-get e :name)) (a3madkour-ingredients/entries))
                   '("olive oil" "rice vinegar" "sesame oil" "crème fraîche" "water")))
    (should (equal (plist-get (a3madkour-ingredients/lookup "sesame oil") :aisle) "Oils & vinegar"))
    (should-not (plist-get (a3madkour-ingredients/lookup "sesame oil") :state))
    (should-not (a3madkour-ingredients/problems))))

(ert-deftest a3madkour-ingredients--add-refuses-clash ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (should (equal (cadr (should-error (a3madkour-ingredients/add-entry "EVOO" "Dairy") :type 'user-error))
                   "\"EVOO\" is already in the registry as \"olive oil\" (Oils & vinegar)"))
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
      (should (string-match-p "^\\*\\* OUT olive oil +:staple:$" text))
      (should-not (string-match-p "CLOSED" text)))
    (should (equal (cadr (should-error (a3madkour-ingredients/set-entry-state "saffron" 'out)
                                       :type 'user-error))
                   "No ingredient \"saffron\" in the registry"))))

(ert-deftest a3madkour-ingredients--header-flips-without-a-closed-stamp ()
  "The header the module writes gives the in-file org keys exactly the three
states, and flipping to any of them never stamps CLOSED, even with done-logging
on globally.  (Org always makes the last keyword a done state; a trailing `|'
does not prevent that, so the header turns logging off for the file.)"
  (let ((org-log-done 'time))
    (with-temp-buffer
      (insert a3madkour-ingredients--header "* A\n** HAVE x\n")
      (org-mode)
      (should (equal org-todo-keywords-1 '("HAVE" "LOW" "OUT")))
      (goto-char (point-max)) (forward-line -1)
      (org-todo "OUT")
      (should (string-match-p "^\\*\\* OUT x$" (buffer-string)))
      (org-todo "LOW")
      (org-todo "OUT")
      (should-not (string-match-p "CLOSED" (buffer-string))))))

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
      (insert "* Spices\n** OUT sumac\n" a3madkour-ingredients-test--registry))
    (set-file-times a3madkour-ingredients/file (time-add (current-time) 7))
    (a3madkour-ingredients/set-entry-state "rice vinegar" 'have)
    (should (eq (plist-get (a3madkour-ingredients/lookup "sumac") :state) 'out))
    (should (eq (plist-get (a3madkour-ingredients/lookup "rice vinegar") :state) 'have))
    (should (eq (plist-get (a3madkour-ingredients/lookup "olive oil") :state) 'have))))

(ert-deftest a3madkour-ingredients--add-command ()
  (a3madkour-ingredients-test--with a3madkour-ingredients-test--registry
    (let ((answers '("ghee" "clarified butter, " "tbsp")))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop answers)))
                ((symbol-function 'completing-read)
                 (lambda (prompt &rest _) (if (string-match-p "[Aa]isle" prompt) "Dairy" "have"))))
        (call-interactively #'a3-ingredient-add)))
    (let ((e (a3madkour-ingredients/lookup "clarified butter")))
      (should (equal (plist-get e :name) "ghee"))
      (should (equal (plist-get e :aisle) "Dairy"))
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
      (should (equal (plist-get (a3madkour-ingredients/lookup "smoked paprika") :aisle) "Spices"))
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

(provide 'a3madkour-ingredients-test)
;;; a3madkour-ingredients-test.el ends here
