;;; a3madkour-units.el --- cooking quantities and units  -*- lexical-binding: t; -*-

;;; Commentary:

;; Just enough arithmetic to add up what several recipes need of one
;; ingredient.  Quantities are read the way people write them ("1 1/2", "½",
;; "2-3"); units are folded to one spelling ("Tablespoons" is "tbsp"); and
;; amounts are summed within a dimension (volume, mass), converted to one
;; unit.  Anything else (cloves, cans, pinches, bare counts) is summed only
;; with its own kind.  No ingredient densities: cups never become grams.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defconst a3madkour-units--names
  '(("tsp" "tsp" "tsp." "teaspoon" "teaspoons")
    ("tbsp" "tbsp" "tbsp." "tbs" "tablespoon" "tablespoons")
    ("cup" "cup" "cups" "c")
    ("ml" "ml" "milliliter" "milliliters" "millilitre" "millilitres")
    ("l" "l" "liter" "liters" "litre" "litres")
    ("floz" "floz" "fl oz" "fl. oz." "fluid ounce" "fluid ounces")
    ("pt" "pt" "pint" "pints")
    ("qt" "qt" "quart" "quarts")
    ("gal" "gal" "gallon" "gallons")
    ("g" "g" "gram" "grams" "gr")
    ("kg" "kg" "kilogram" "kilograms" "kilo" "kilos")
    ("oz" "oz" "oz." "ounce" "ounces")
    ("lb" "lb" "lbs" "lb." "lbs." "pound" "pounds"))
  "Canonical unit, then every spelling of it (compared downcased).")

(defconst a3madkour-units--factors
  '(("tsp" volume . 4.92892) ("tbsp" volume . 14.7868) ("floz" volume . 29.5735)
    ("cup" volume . 236.588) ("pt" volume . 473.176) ("qt" volume . 946.353)
    ("gal" volume . 3785.41) ("ml" volume . 1.0) ("l" volume . 1000.0)
    ("g" mass . 1.0) ("kg" mass . 1000.0) ("oz" mass . 28.3495) ("lb" mass . 453.592))
  "Canonical unit → (DIMENSION . size in the dimension's base unit).")

(defconst a3madkour-units--fractions
  '((?½ . 0.5) (?¼ . 0.25) (?¾ . 0.75) (?⅓ . 0.3333333333) (?⅔ . 0.6666666667)
    (?⅛ . 0.125) (?⅜ . 0.375) (?⅝ . 0.625) (?⅞ . 0.875)))

(defun a3madkour-units/canonical (unit)
  "UNIT in its one spelling, or nil for nil or blank.
A unit this module does not know is returned trimmed and downcased."
  (let ((u (downcase (string-trim (or unit "")))))
    (unless (string-empty-p u)
      (or (car (cl-find-if (lambda (row) (member u (cdr row)))
                           a3madkour-units--names))
          u))))

(defun a3madkour-units--number (s)
  "The value of one number token S (\"2\", \"1.5\", \"1/2\", \"½\"), or nil."
  (cond
   ((string-match "\\`\\([0-9]+\\)/\\([0-9]+\\)\\'" s)
    (let ((d (string-to-number (match-string 2 s))))
      (unless (= d 0) (/ (float (string-to-number (match-string 1 s))) d))))
   ((string-match-p "\\`\\(?:[0-9]+\\.?[0-9]*\\|\\.[0-9]+\\)\\'" s) (string-to-number s))
   ((and (= (length s) 1) (assq (aref s 0) a3madkour-units--fractions))
    (cdr (assq (aref s 0) a3madkour-units--fractions)))))

(defun a3madkour-units/parse-qty (string)
  "The number STRING writes, or nil when it writes none.
Reads \"2\", \"1.5\", \"1/2\", \"1 1/2\", \"½\" and \"1½\".  A range (\"2-3\",
\"2 to 3\") is its upper end: enough is bought."
  (let ((s (string-trim (or string ""))))
    (when (string-match "\\`\\(.*?\\)[ \t]*\\(?:-\\|–\\|—\\|\\bto\\b\\)[ \t]*\\(.*\\)\\'" s)
      (let ((hi (a3madkour-units/parse-qty (match-string 2 s))))
        (when hi (setq s nil) (setq string hi))))
    (if (numberp string)
        string
      ;; "1½" is "1 ½".
      (setq s (replace-regexp-in-string "\\([0-9]\\)\\([½¼¾⅓⅔⅛⅜⅝⅞]\\)" "\\1 \\2" s))
      (let ((parts (split-string s "[ \t]+" t)))
        (when (and parts (<= (length parts) 2))
          (let ((nums (mapcar #'a3madkour-units--number parts)))
            (unless (memq nil nums)
              (let ((total (apply #'+ nums)))
                (if (and (floatp total) (= total (ffloor total)))
                    (truncate total)
                  total)))))))))

(defun a3madkour-units/sum (amounts &optional preferred)
  "Add up AMOUNTS, a list of (QTY . UNIT); return a shorter such list.
QTY is a number or nil (an amount with no number adds nothing); UNIT is a
string or nil (a bare count).  Volumes are summed into one unit, masses into
one unit: PREFERRED when it is of that dimension, else the first such unit
seen.  Every other unit, and bare counts, are summed with their own kind.
Order follows first appearance."
  (let ((preferred (a3madkour-units/canonical preferred))
        (groups '()))                   ; (KEY UNIT . TOTAL-IN-UNIT)
    (dolist (amount amounts)
      (let* ((qty (car amount))
             (unit (a3madkour-units/canonical (cdr amount)))
             (factor (cdr (assoc unit a3madkour-units--factors))))
        (when (numberp qty)
          (let* ((key (if factor (car factor) (or unit 'count)))
                 (group (assoc key groups)))
            (unless group
              (let ((target (if (and factor preferred
                                     (eq (cadr (assoc preferred a3madkour-units--factors))
                                         (car factor)))
                                preferred
                              unit)))
                (setq group (cons key (cons target 0)))
                (setq groups (append groups (list group)))))
            (setcdr (cdr group)
                    (+ (cddr group)
                       (if factor
                           (/ (* qty (cdr factor))
                              (cddr (assoc (cadr group) a3madkour-units--factors)))
                         qty)))))))
    (mapcar (lambda (g) (cons (cddr g) (cadr g))) groups)))

(defun a3madkour-units/format-qty (qty)
  "QTY as people write it: at most two decimals, no trailing zeros."
  (let ((s (format "%.2f" qty)))
    (replace-regexp-in-string "\\.?0+\\'" "" s)))

(defun a3madkour-units/format (amounts)
  "AMOUNTS (a list of (QTY . UNIT)) as \"3 tbsp + 200 g + 2\", or nil if empty."
  (when amounts
    (mapconcat (lambda (a)
                 (concat (a3madkour-units/format-qty (car a))
                         (if (cdr a) (concat " " (cdr a)) "")))
               amounts " + ")))

(provide 'a3madkour-units)
;;; a3madkour-units.el ends here
