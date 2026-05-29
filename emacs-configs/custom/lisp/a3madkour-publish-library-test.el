;;; a3madkour-publish-library-test.el --- tests for library handler  -*- lexical-binding: t; -*-

(require 'ert)
(require 'a3madkour-publish-library)

(ert-deftest a3madkour-pub-library--module-loads ()
  "Smoke: module loadable and exposes publish-library-file."
  (should (fboundp 'a3madkour-pub-library/publish-library-file)))

(ert-deftest a3madkour-pub-library--config-table-shape ()
  "Per-medium config table has all 4 library sections with the right shape."
  (dolist (section '(library-reading library-listening library-playing library-watching))
    (let ((cfg (a3madkour-pub-library--config-for section)))
      (should (= 4 (length cfg)))
      (should (stringp (nth 0 cfg)))           ; yaml filename
      (should (stringp (nth 1 cfg)))           ; default media_type
      (should (listp (nth 2 cfg)))             ; allowed media_types
      (should (listp (nth 3 cfg)))             ; allowed statuses
      (should (member (nth 1 cfg) (nth 2 cfg))))) ; default ∈ allowed
  (should-error (a3madkour-pub-library--config-for 'bogus)))

(ert-deftest a3madkour-pub-library--title-to-slug ()
  "Title-to-slug derivation covers spec §5 edge cases."
  (should (equal (a3madkour-pub-library--title-to-slug "Pride and Prejudice")
                 "pride-and-prejudice"))
  (should (equal (a3madkour-pub-library--title-to-slug "L'Étranger")
                 "l-etranger"))
  (should (equal (a3madkour-pub-library--title-to-slug "Köyaanisqatsi")
                 "koyaanisqatsi"))
  (should (equal (a3madkour-pub-library--title-to-slug "Crime & Punishment")
                 "crime-punishment"))
  (should (equal (a3madkour-pub-library--title-to-slug "Dune: Part One")
                 "dune-part-one"))
  (should (equal (a3madkour-pub-library--title-to-slug "Maximum a Posteriori (MAP)")
                 "maximum-a-posteriori-map"))
  (should (equal (a3madkour-pub-library--title-to-slug "1984")
                 "1984"))
  (should (equal (a3madkour-pub-library--title-to-slug "  Leading-Trailing  ")
                 "leading-trailing"))
  (should (equal (a3madkour-pub-library--title-to-slug "!?!")
                 ""))
  (should (equal (a3madkour-pub-library--title-to-slug "Severance S2")
                 "severance-s2")))

(provide 'a3madkour-publish-library-test)

;;; a3madkour-publish-library-test.el ends here
