;;; a3madkour-publish-slug-test.el --- Tests for slug derivation -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'a3madkour-publish-slug)

(ert-deftest a3madkour-pub-slug-test/basic-ascii ()
  (should (equal "bayesian-statistics" (a3madkour-pub-slug/slugify "Bayesian Statistics"))))

(ert-deftest a3madkour-pub-slug-test/lowercase-and-hyphens ()
  (should (equal "my-note-title" (a3madkour-pub-slug/slugify "My Note Title"))))

(ert-deftest a3madkour-pub-slug-test/strip-punctuation ()
  (should (equal "whats-going-on" (a3madkour-pub-slug/slugify "What's going on?!")))
  (should (equal "foo-bar" (a3madkour-pub-slug/slugify "foo / bar")))
  (should (equal "x-y-z" (a3madkour-pub-slug/slugify "x_y_z"))))

(ert-deftest a3madkour-pub-slug-test/collapse-runs ()
  "Runs of hyphens collapse to one."
  (should (equal "a-b" (a3madkour-pub-slug/slugify "a   b")))
  (should (equal "a-b" (a3madkour-pub-slug/slugify "a---b")))
  (should (equal "a-b" (a3madkour-pub-slug/slugify "a..b"))))

(ert-deftest a3madkour-pub-slug-test/strip-leading-trailing-hyphens ()
  (should (equal "foo" (a3madkour-pub-slug/slugify "  foo  ")))
  (should (equal "foo" (a3madkour-pub-slug/slugify "-foo-")))
  (should (equal "foo" (a3madkour-pub-slug/slugify "...foo..."))))

(ert-deftest a3madkour-pub-slug-test/unicode-ascii-fold ()
  "Non-ASCII letters are folded to ASCII where possible (NFKD)."
  (should (equal "cafe" (a3madkour-pub-slug/slugify "Café")))
  (should (equal "naive" (a3madkour-pub-slug/slugify "naïve"))))

(ert-deftest a3madkour-pub-slug-test/non-ascii-unfoldable-drops ()
  "Non-foldable characters (e.g., Arabic, CJK) drop entirely; author should set HUGO_SLUG."
  (should (equal "" (a3madkour-pub-slug/slugify "بسم الله")))
  (should (equal "" (a3madkour-pub-slug/slugify "私"))))

(ert-deftest a3madkour-pub-slug-test/empty-or-nil ()
  (should (equal "" (a3madkour-pub-slug/slugify "")))
  (should (equal "" (a3madkour-pub-slug/slugify "   ")))
  (should (equal "" (a3madkour-pub-slug/slugify nil))))

(ert-deftest a3madkour-pub-slug-test/camel-case-not-split ()
  "camelCase is NOT split — author uses HUGO_SLUG for camelCase filenames.
This test documents the deliberate behavior so a future contributor doesn't
add a `camel→kebab' transform without considering existing notes."
  (should (equal "darwichetractablebooleanarithmetic2022"
                 (a3madkour-pub-slug/slugify "darwicheTractableBooleanArithmetic2022"))))

(provide 'a3madkour-publish-slug-test)

;;; a3madkour-publish-slug-test.el ends here
