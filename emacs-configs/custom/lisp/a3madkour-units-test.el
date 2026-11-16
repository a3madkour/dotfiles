;;; a3madkour-units-test.el --- tests for cooking quantities  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-units)

(ert-deftest a3madkour-units--parse-qty ()
  (should (equal (a3madkour-units/parse-qty "2") 2))
  (should (equal (a3madkour-units/parse-qty " 1.5 ") 1.5))
  (should (equal (a3madkour-units/parse-qty "1/2") 0.5))
  (should (equal (a3madkour-units/parse-qty "1 1/2") 1.5))
  (should (equal (a3madkour-units/parse-qty "½") 0.5))
  (should (equal (a3madkour-units/parse-qty "1 ½") 1.5))
  (should (equal (a3madkour-units/parse-qty "1½") 1.5))
  (should (equal (a3madkour-units/parse-qty "4/2") 2))
  ;; A range is its upper end.
  (should (equal (a3madkour-units/parse-qty "2-3") 3))
  (should (equal (a3madkour-units/parse-qty "1 to 1 1/2") 1.5))
  (dolist (s '("" "  " nil "a few" "1/0" "1 2 3" "2x"))
    (should-not (a3madkour-units/parse-qty s))))

(ert-deftest a3madkour-units--canonical ()
  (should (equal (a3madkour-units/canonical "Tablespoons") "tbsp"))
  (should (equal (a3madkour-units/canonical " Tbsp ") "tbsp"))
  (should (equal (a3madkour-units/canonical "cups") "cup"))
  (should (equal (a3madkour-units/canonical "lbs") "lb"))
  (should (equal (a3madkour-units/canonical "Cloves") "cloves"))
  (should-not (a3madkour-units/canonical ""))
  (should-not (a3madkour-units/canonical nil)))

(ert-deftest a3madkour-units--sum ()
  ;; Volumes fold into the first unit seen.
  (should (equal (a3madkour-units/format
                  (a3madkour-units/sum '((1 . "tbsp") (3 . "tsp") (1 . "Tablespoon"))))
                 "3 tbsp"))
  ;; Or into the preferred unit, when it measures the same thing.
  (should (equal (a3madkour-units/format
                  (a3madkour-units/sum '((1 . "cup") (8 . "tbsp")) "ml"))
                 "354.88 ml"))
  (should (equal (a3madkour-units/format
                  (a3madkour-units/sum '((1 . "cup")) "g"))
                 "1 cup"))
  ;; Volume and mass never mix; unknown units and bare counts keep to
  ;; themselves; an amount with no number adds nothing.
  (should (equal (a3madkour-units/format
                  (a3madkour-units/sum '((200 . "g") (1 . "cup") (0.5 . "kg") (2 . "cloves")
                                         (1 . nil) (nil . "pinch") (3 . "Cloves") (2 . ""))))
                 "700 g + 1 cup + 5 cloves + 3"))
  (should-not (a3madkour-units/sum '((nil . "pinch") (nil))))
  (should-not (a3madkour-units/format nil)))

(provide 'a3madkour-units-test)
;;; a3madkour-units-test.el ends here
