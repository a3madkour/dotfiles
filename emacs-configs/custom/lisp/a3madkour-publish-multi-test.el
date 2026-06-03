;;; a3madkour-publish-multi-test.el --- Tests for D.2 orchestrator -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-multi)

(ert-deftest a3madkour-pub-multi/templates-dir-resolves ()
  "When SITE_ROOT is settable via helper, templates dir resolves under it."
  (cl-letf (((symbol-function 'a3madkour-pub-essays--site-root)
             (lambda () "/site")))
    (let ((a3madkour-pub-multi-templates-dir nil))
      (should (string= "/site/tools/templates/"
                       (a3madkour-pub-multi--templates-dir))))))

(ert-deftest a3madkour-pub-multi/templates-dir-respects-custom ()
  "Explicit defcustom overrides the auto-resolved default."
  (let ((a3madkour-pub-multi-templates-dir "/custom/tpl/"))
    (should (string= "/custom/tpl/" (a3madkour-pub-multi--templates-dir)))))

(ert-deftest a3madkour-pub-multi/orchestrate-partial-success-pdf-only ()
  "When PDF succeeds and Word fails, returns plist with :pdf set, :word nil."
  (cl-letf (((symbol-function 'a3madkour-pub-multi--templates-dir)
             (lambda () "/tpl/"))
            ((symbol-function 'a3madkour-pub-multi--bib-path)
             (lambda () nil))
            ((symbol-function 'a3madkour-pub-multi--has-citations-p)
             (lambda (&rest _) nil))
            ((symbol-function 'a3madkour-pub-multi--prepare-source-for-pdf)
             (lambda (&rest _) "/tmp/x.org"))
            ((symbol-function 'a3madkour-pub-multi-pdf/run)
             (lambda (&rest _) "/bundle/x.pdf"))
            ((symbol-function 'a3madkour-pub-multi-word/run)
             (lambda (&rest _) nil))
            ((symbol-function 'a3madkour-pub-multi--patch-downloads-frontmatter)
             (lambda (&rest _) t)))
    (let ((result (a3madkour-pub-multi/orchestrate "/src.org" "x" "/bundle/")))
      (should (string= "/bundle/x.pdf" (plist-get result :pdf)))
      (should-not (plist-get result :word)))))

(ert-deftest a3madkour-pub-multi/orchestrate-both-fail ()
  "When both backends fail, plist :pdf and :word are nil."
  (cl-letf (((symbol-function 'a3madkour-pub-multi--templates-dir)
             (lambda () "/tpl/"))
            ((symbol-function 'a3madkour-pub-multi--bib-path)
             (lambda () nil))
            ((symbol-function 'a3madkour-pub-multi--has-citations-p)
             (lambda (&rest _) nil))
            ((symbol-function 'a3madkour-pub-multi--prepare-source-for-pdf)
             (lambda (&rest _) "/tmp/x.org"))
            ((symbol-function 'a3madkour-pub-multi-pdf/run) (lambda (&rest _) nil))
            ((symbol-function 'a3madkour-pub-multi-word/run) (lambda (&rest _) nil))
            ((symbol-function 'a3madkour-pub-multi--patch-downloads-frontmatter)
             (lambda (&rest _) t)))
    (let ((result (a3madkour-pub-multi/orchestrate "/src.org" "x" "/bundle/")))
      (should-not (plist-get result :pdf))
      (should-not (plist-get result :word)))))

(provide 'a3madkour-publish-multi-test)
;;; a3madkour-publish-multi-test.el ends here
