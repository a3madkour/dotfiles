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

(provide 'a3madkour-ingredients-test)
;;; a3madkour-ingredients-test.el ends here
