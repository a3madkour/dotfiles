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

(defun a3madkour-pub-multi--test--with-temp-bundle (body)
  (let* ((dir (make-temp-file "multi-bundle-" t))
         (idx (expand-file-name "index.md" dir)))
    (unwind-protect (funcall body dir idx)
      (delete-directory dir t))))

(ert-deftest a3madkour-pub-multi/patch-adds-keys-when-pdf-only ()
  (a3madkour-pub-multi--test--with-temp-bundle
   (lambda (dir idx)
     (write-region "---\ntitle: \"X\"\n---\nBody\n" nil idx)
     (a3madkour-pub-multi--patch-downloads-frontmatter idx "x" "/b/x.pdf" nil)
     (let ((text (with-temp-buffer (insert-file-contents idx) (buffer-string))))
       (should (string-match-p "multi_export: true" text))
       (should (string-match-p "downloads: {pdf: \"x\\.pdf\"}" text))
       (should-not (string-match-p "word:" text))))))

(ert-deftest a3madkour-pub-multi/patch-emits-false-when-both-fail ()
  (a3madkour-pub-multi--test--with-temp-bundle
   (lambda (dir idx)
     (write-region "---\ntitle: \"X\"\n---\nBody\n" nil idx)
     (a3madkour-pub-multi--patch-downloads-frontmatter idx "x" nil nil)
     (let ((text (with-temp-buffer (insert-file-contents idx) (buffer-string))))
       (should (string-match-p "multi_export: false" text))
       (should-not (string-match-p "downloads:" text))))))

(ert-deftest a3madkour-pub-multi/patch-idempotent ()
  (a3madkour-pub-multi--test--with-temp-bundle
   (lambda (dir idx)
     (write-region "---\ntitle: \"X\"\n---\nBody\n" nil idx)
     (a3madkour-pub-multi--patch-downloads-frontmatter idx "x" "/b/x.pdf" "/b/x.docx")
     (let* ((after-first (file-attributes idx))
            (mtime-1 (file-attribute-modification-time after-first)))
       (sleep-for 1.1)  ;; ensure mtime resolution; tolerated for the idempotency check
       (a3madkour-pub-multi--patch-downloads-frontmatter idx "x" "/b/x.pdf" "/b/x.docx")
       (let* ((after-second (file-attributes idx))
              (mtime-2 (file-attribute-modification-time after-second)))
         (should (equal mtime-1 mtime-2)))))))

(ert-deftest a3madkour-pub-multi/auto-trigger-fires-on-opt-in ()
  "When source has #+multi_export: t, the after-publish hook dispatches orchestrate."
  (let* ((called nil)
         (tmp (make-temp-file "multi-trigger-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+title: T\n#+multi_export: t\n"))
          (cl-letf (((symbol-function 'a3madkour-pub-multi/orchestrate)
                     (lambda (&rest args) (setq called args))))
            (a3madkour-pub-multi--after-essay-publish-handler
             tmp "demo-slug" "/bundle/demo-slug/")
            (should called)))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-multi/auto-trigger-skips-without-opt-in ()
  "When source lacks the opt-in keyword, orchestrate is not called."
  (let* ((called nil)
         (tmp (make-temp-file "multi-trigger-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+title: T\n"))
          (cl-letf (((symbol-function 'a3madkour-pub-multi/orchestrate)
                     (lambda (&rest args) (setq called args))))
            (a3madkour-pub-multi--after-essay-publish-handler
             tmp "demo-slug" "/bundle/demo-slug/")
            (should-not called)))
      (delete-file tmp))))

(provide 'a3madkour-publish-multi-test)
;;; a3madkour-publish-multi-test.el ends here
