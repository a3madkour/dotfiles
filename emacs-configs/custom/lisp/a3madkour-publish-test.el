;;; a3madkour-publish-test.el --- Tests for a3madkour-publish -*- lexical-binding: t; -*-

;;; Commentary:

;; ert tests for a3madkour-publish.  Run via the `run-tests.sh' wrapper
;; in this directory, or directly:
;;
;;   emacs --batch -L . -l ert -l a3madkour-publish-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'a3madkour-publish)

(ert-deftest a3madkour-pub-test/library-loads ()
  "Smoke test: the library loads and exposes its version constant."
  (should (stringp a3madkour-pub/version))
  (should (string-match-p "^[0-9]+\\.[0-9]+\\." a3madkour-pub/version)))

;; -- Section enum --

(ert-deftest a3madkour-pub-test/sections-includes-known-values ()
  "The section enum includes every section documented in the design spec."
  (dolist (s '("essays" "garden"
               "research/themes" "research/questions"
               "works/games" "works/music" "works/poetry"
               "library/reading" "library/listening" "library/playing" "library/watching"
               "streams" "about"))
    (should (a3madkour-pub/valid-section-p s))))

(ert-deftest a3madkour-pub-test/sections-rejects-unknown-values ()
  "The section enum rejects typos and unknown values."
  (should-not (a3madkour-pub/valid-section-p "esays"))
  (should-not (a3madkour-pub/valid-section-p "garden/topic"))
  (should-not (a3madkour-pub/valid-section-p ""))
  (should-not (a3madkour-pub/valid-section-p nil)))

;; -- published-p --

(defun a3madkour-pub-test--with-org-file (content thunk)
  "Write CONTENT to a tmp .org file and call THUNK with the file path.
Cleans up the tmp file afterwards."
  (let ((tmp (make-temp-file "a3-pub-test-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert content))
          (funcall thunk tmp))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-test/published-p-live ()
  "File with HUGO_PUBLISH: t + valid HUGO_SECTION + no HUGO_DRAFT → 'live."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f) (should (eq 'live (a3madkour-pub/published-p f))))))

(ert-deftest a3madkour-pub-test/published-p-draft ()
  "Add HUGO_DRAFT: t → 'draft."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+HUGO_DRAFT: t\n* Body\n"
   (lambda (f) (should (eq 'draft (a3madkour-pub/published-p f))))))

(ert-deftest a3madkour-pub-test/published-p-private-missing-publish ()
  "No HUGO_PUBLISH → nil."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f) (should (null (a3madkour-pub/published-p f))))))

(ert-deftest a3madkour-pub-test/published-p-publish-without-section-errors ()
  "HUGO_PUBLISH without HUGO_SECTION → user-error.
Default-deny means both keywords are required; setting just one is a likely
typo that should not silently succeed nor silently fail-private."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n* Body\n"
   (lambda (f) (should-error (a3madkour-pub/published-p f) :type 'user-error))))

(ert-deftest a3madkour-pub-test/published-p-unknown-section-errors ()
  "Unknown section value → user-error."
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: gardn\n* Body\n"
   (lambda (f) (should-error (a3madkour-pub/published-p f) :type 'user-error))))

;; -- note-slug / note-section / note-url --

(ert-deftest a3madkour-pub-test/note-slug-uses-title-by-default ()
  (a3madkour-pub-test--with-org-file
   "#+title: Bayesian Statistics\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f)
     (should (equal "bayesian-statistics" (a3madkour-pub/note-slug f))))))

(ert-deftest a3madkour-pub-test/note-slug-honors-override ()
  (a3madkour-pub-test--with-org-file
   "#+title: Tractable Boolean Arithmetic\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+HUGO_SLUG: tba-2022\n* Body\n"
   (lambda (f)
     (should (equal "tba-2022" (a3madkour-pub/note-slug f))))))

(ert-deftest a3madkour-pub-test/note-section-returns-string-or-nil ()
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f) (should (equal "garden" (a3madkour-pub/note-section f)))))
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n* Body\n"
   (lambda (f) (should (null (a3madkour-pub/note-section f))))))

(ert-deftest a3madkour-pub-test/note-url-shape ()
  (a3madkour-pub-test--with-org-file
   "#+title: Bayesian Statistics\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n* Body\n"
   (lambda (f)
     (should (equal "/garden/bayesian-statistics/" (a3madkour-pub/note-url f))))))

(ert-deftest a3madkour-pub-test/note-url-with-nested-section ()
  (a3madkour-pub-test--with-org-file
   "#+title: Q One\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: research/questions\n* Body\n"
   (lambda (f)
     (should (equal "/research/questions/q-one/" (a3madkour-pub/note-url f))))))

(ert-deftest a3madkour-pub-test/note-url-nil-for-private ()
  (a3madkour-pub-test--with-org-file
   "#+title: Foo\n* Body\n"
   (lambda (f) (should (null (a3madkour-pub/note-url f))))))

(provide 'a3madkour-publish-test)

;;; a3madkour-publish-test.el ends here
