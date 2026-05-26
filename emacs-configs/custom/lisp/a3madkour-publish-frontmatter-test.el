;;; a3madkour-publish-frontmatter-test.el --- tests for -frontmatter.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the per-section frontmatter normalizer dispatch.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-frontmatter)

(ert-deftest a3madkour-pub-fm-test/normalize-returns-alist-with-section ()
  "B.0 — `normalize' returns the input alist annotated with section symbol.
Per-section transforms land in B.1+; B.0 ships pass-through behavior."
  (let* ((raw '((title . "Hello") (tags . ("a" "b"))))
         (result (a3madkour-pub-frontmatter/normalize 'garden raw "/tmp/foo.org")))
    (should (listp result))
    (should (equal "Hello" (alist-get 'title result)))
    (should (equal '("a" "b") (alist-get 'tags result)))))

(ert-deftest a3madkour-pub-fm-test/normalize-accepts-all-known-sections ()
  "B.0 — `normalize' dispatches without error for every section enum value."
  (dolist (section '(garden essays research-theme research-question
                     works-games works-music works-poetry
                     streams about
                     library-reading library-listening
                     library-playing library-watching))
    (should (a3madkour-pub-frontmatter/normalize section '((title . "X")) "/tmp/x.org"))))

(ert-deftest a3madkour-pub-fm-test/normalize-errors-on-unknown-section ()
  "B.0 — `normalize' signals an error for unknown section symbol."
  (should-error (a3madkour-pub-frontmatter/normalize 'made-up-section '() "/tmp/x.org")))

(ert-deftest a3madkour-pub-frontmatter--dispatch-routes-by-section ()
  "normalize dispatches to per-section logic; unknown sections still error."
  (should-error
   (a3madkour-pub-frontmatter/normalize 'bogus '((title . "x")) "/tmp/x.org"))
  ;; Non-garden known sections still pass-through (B.1 only adds garden).
  (should (equal (a3madkour-pub-frontmatter/normalize 'essays
                                                       '((title . "Hi"))
                                                       "/tmp/x.org")
                 '((title . "Hi")))))

(ert-deftest a3madkour-pub-frontmatter--growth-stage-from-progress ()
  "PROGRESS property maps to growth_stage per spec §7."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (progn
          ;; none / unset
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "seedling"))
          ;; highlighting → seedling
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :PROGRESS: highlighting\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "seedling"))
          ;; ref-notes → budding
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :PROGRESS: ref-notes\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "budding"))
          ;; main-notes → evergreen
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :PROGRESS: main-notes\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "evergreen"))
          ;; done → evergreen
          (with-temp-file src (insert "* Note\n  :PROPERTIES:\n  :PROGRESS: done\n  :END:\n"))
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden '() src))
                         "evergreen")))
      (delete-file src))))

(ert-deftest a3madkour-pub-frontmatter--growth-stage-keyword-override ()
  "HUGO_GROWTH_STAGE keyword overrides PROGRESS derivation."
  (let ((src (make-temp-file "garden-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "#+HUGO_GROWTH_STAGE: budding\n"
                    "* Note\n  :PROPERTIES:\n  :PROGRESS: done\n  :END:\n"))
          ;; ox-hugo would have parsed HUGO_GROWTH_STAGE into the alist.
          ;; We simulate that here by pre-populating raw-alist.
          (should (equal (alist-get 'growth_stage
                                    (a3madkour-pub-frontmatter/normalize
                                     'garden
                                     '((growth_stage . "budding"))
                                     src))
                         "budding")))
      (delete-file src))))

(provide 'a3madkour-publish-frontmatter-test)
;;; a3madkour-publish-frontmatter-test.el ends here
