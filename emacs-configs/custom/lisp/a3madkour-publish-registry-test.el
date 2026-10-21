;;; a3madkour-publish-registry-test.el --- tests for the section registry  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-registry)
(require 'a3madkour-sections)
(require 'a3madkour-sections-fixture)

(ert-deftest a3madkour-pub-registry--unknown-section-signals ()
  (should-error (a3madkour-pub-registry/entry "bogus"))
  (should-not (a3madkour-pub-registry/handler "bogus" 'living)))

(ert-deftest a3madkour-pub-registry--section-symbol-total-and-injective ()
  (let ((syms (mapcar #'a3madkour-pub-section/symbol (a3madkour-pub-registry/names))))
    (should (eq (a3madkour-pub-section/symbol "works/poetry") 'works-poetry))
    (should (eq (a3madkour-pub-section/symbol "research/themes") 'research-themes))
    (should (eq (a3madkour-pub-section/symbol "garden") 'garden))
    (should (= (length syms) (length (delete-dups (copy-sequence syms)))))
    (dolist (s (a3madkour-pub-registry/names))
      (should (equal (a3madkour-pub-section/from-symbol
                      (a3madkour-pub-section/symbol s))
                     s)))
    (should-error (a3madkour-pub-section/symbol "works/bogus"))
    (should-error (a3madkour-pub-section/from-symbol 'works-bogus))))

(ert-deftest a3madkour-pub-registry--modes-and-handlers ()
  (should (equal (a3madkour-pub-registry/sections-with-mode 'deliberate)
                 '("essays" "works/poetry")))
  (should (equal (a3madkour-pub-registry/sections-with-mode nil)
                 '("streams" "about")))
  (should (eq (a3madkour-pub-registry/handler "garden" 'living)
              'a3madkour-pub-garden/publish-garden-file))
  (should-not (a3madkour-pub-registry/handler "essays" 'living))
  (should (eq (a3madkour-pub-registry/handler "essays" 'deliberate)
              'a3madkour-pub-essays/publish-essay-file))
  (should-not (a3madkour-pub-registry/handler "streams" 'living))
  (should (equal (a3madkour-pub-registry/sections-for-handler
                  'a3madkour-pub-works/publish-works-file)
                 '("works/games" "works/music"))))

(ert-deftest a3madkour-pub-registry--every-handler-fboundp-after-load ()
  (dolist (f '(a3madkour-publish-garden a3madkour-publish-library
               a3madkour-publish-research a3madkour-publish-recipes
               a3madkour-publish-works a3madkour-publish-essays
               a3madkour-publish-poetry))
    (require f))
  (dolist (s (a3madkour-pub-registry/names))
    (let ((h (a3madkour-pub-registry/get s :handler)))
      (when h
        (should (fboundp h))))))

(ert-deftest a3madkour-pub-registry--library-entries-carry-data-config ()
  (let ((libs (a3madkour-pub-registry/sections-for-handler
               'a3madkour-pub-library/publish-library-file)))
    (should (equal libs '("library/reading" "library/listening"
                          "library/playing" "library/watching")))
    (dolist (s libs)
      (should (string-suffix-p ".yaml" (a3madkour-pub-registry/get s :data-file)))
      (should (member (a3madkour-pub-registry/get s :default-medium)
                      (a3madkour-sections/enum s "media_type"))))))

(ert-deftest a3madkour-pub-registry--keys-equal-fixture-contract ()
  (should (equal (sort (a3madkour-pub-registry/names) #'string<)
                 (sort (a3madkour-sections/names) #'string<))))

(ert-deftest a3madkour-pub-registry--keys-equal-real-sections-json ()
  "Cross-repo: the registry's section keys equal the site file's."
  (a3madkour-sections-test--with-real-site
    (should (equal (sort (a3madkour-pub-registry/names) #'string<)
                   (sort (a3madkour-sections/names) #'string<)))
    (dolist (s (a3madkour-pub-registry/sections-for-handler
                'a3madkour-pub-library/publish-library-file))
      (should (member (a3madkour-pub-registry/get s :default-medium)
                      (a3madkour-sections/enum s "media_type"))))))

(ert-deftest a3madkour-pub-registry--loads-without-handler-modules ()
  "Handlers are named, never required: the registry loads on `emacs -Q'
and pulls in no handler or dispatch module."
  (let* ((dir (file-name-directory (locate-library "a3madkour-publish-registry")))
         (emacs (expand-file-name invocation-name invocation-directory))
         (status (call-process
                  emacs nil nil nil "-Q" "--batch"
                  "--eval" "(setq load-prefer-newer t)"
                  "-L" dir
                  "--eval" "(require 'a3madkour-publish-registry)"
                  "--eval" "(kill-emacs (if (or (featurep 'a3madkour-publish-garden) (featurep 'a3madkour-publish-deliberate) (featurep 'a3madkour-publish-essays) (featurep 'a3madkour-publish)) 3 0))")))
    (should (equal status 0))))

(provide 'a3madkour-publish-registry-test)

;;; a3madkour-publish-registry-test.el ends here
