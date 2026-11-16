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

(provide 'a3madkour-ingredients-test)
;;; a3madkour-ingredients-test.el ends here
