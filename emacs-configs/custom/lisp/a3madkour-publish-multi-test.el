;;; a3madkour-publish-multi-test.el --- Tests for D.2 orchestrator -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-async)
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

;; Test helpers: backend stubs that synchronously fire :on-done.
;; Plain `&rest args' + linear search avoids `cl-function' destructuring
;; pitfalls in `cl-letf' (which was unstable across our positional+keyword
;; call shapes — see Task 21 implementation log).

(defun a3madkour-pub-multi--test--find-on-done (args)
  "Return the :on-done value in ARGS (positional-then-keyword tail), or nil."
  (let ((tail args) on-done)
    (while (and tail (not on-done))
      (if (eq (car tail) :on-done)
          (setq on-done (cadr tail))
        (setq tail (cdr tail))))
    on-done))

(defun a3madkour-pub-multi--test--pdf-ok-stub (&rest args)
  (let ((on-done (a3madkour-pub-multi--test--find-on-done args)))
    (when on-done (funcall on-done '(:status ok :path "/bundle/x.pdf")))))

(defun a3madkour-pub-multi--test--pdf-err-stub (&rest args)
  (let ((on-done (a3madkour-pub-multi--test--find-on-done args)))
    (when on-done (funcall on-done '(:status err :err-snippet "boom-pdf")))))

(defun a3madkour-pub-multi--test--word-err-stub (&rest args)
  (let ((on-done (a3madkour-pub-multi--test--find-on-done args)))
    (when on-done (funcall on-done '(:status err :err-snippet "boom-word")))))

(ert-deftest a3madkour-pub-multi/orchestrate-partial-success-pdf-only ()
  "When PDF succeeds and Word fails, returns plist with :pdf set, :word nil.
Sync wrapper around `export-bundle' must preserve old (:pdf … :word …) shape."
  (cl-letf (((symbol-function 'a3madkour-pub-multi--templates-dir)
             (lambda () "/tpl/"))
            ((symbol-function 'a3madkour-pub-multi--bib-path)
             (lambda () nil))
            ((symbol-function 'a3madkour-pub-multi--has-citations-p)
             (lambda (&rest _) nil))
            ((symbol-function 'a3madkour-pub-multi--prepare-source-for-pdf)
             (lambda (&rest _) "/tmp/x.org"))
            ((symbol-function 'a3madkour-pub-multi-pdf/run)
             #'a3madkour-pub-multi--test--pdf-ok-stub)
            ((symbol-function 'a3madkour-pub-multi-word/run)
             #'a3madkour-pub-multi--test--word-err-stub)
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
            ((symbol-function 'a3madkour-pub-multi-pdf/run)
             #'a3madkour-pub-multi--test--pdf-err-stub)
            ((symbol-function 'a3madkour-pub-multi-word/run)
             #'a3madkour-pub-multi--test--word-err-stub)
            ((symbol-function 'a3madkour-pub-multi--patch-downloads-frontmatter)
             (lambda (&rest _) t)))
    (let ((result (a3madkour-pub-multi/orchestrate "/src.org" "x" "/bundle/")))
      (should-not (plist-get result :pdf))
      (should-not (plist-get result :word)))))

(ert-deftest a3madkour-pub-multi/export-bundle-runs-pdf-and-word-in-parallel ()
  "export-bundle dispatches both backends; barrier rolls up to single :status."
  (let (pdf-ran word-ran done-status)
    (cl-letf*
        (((symbol-function 'a3madkour-pub-multi-pdf/run)
          (lambda (&rest args)
            (setq pdf-ran t)
            (let ((on-done (a3madkour-pub-multi--test--find-on-done args)))
              (when on-done (funcall on-done '(:status ok :path "/x.pdf"))))))
         ((symbol-function 'a3madkour-pub-multi-word/run)
          (lambda (&rest args)
            (setq word-ran t)
            (let ((on-done (a3madkour-pub-multi--test--find-on-done args)))
              (when on-done (funcall on-done '(:status ok :path "/x.docx"))))))
         ((symbol-function 'a3madkour-pub-multi--prepare-source-for-pdf)
          (lambda (source _slug _work) source))
         ((symbol-function 'a3madkour-pub-multi--templates-dir)
          (lambda () "/tmp/templates/"))
         ((symbol-function 'a3madkour-pub-multi--bib-path) (lambda () "/tmp/lib.bib"))
         ((symbol-function 'a3madkour-pub-multi--has-citations-p) (lambda (_) nil))
         ((symbol-function 'a3madkour-pub-multi--patch-downloads-frontmatter)
          (lambda (&rest _) nil)))
      (a3madkour-pub-multi/export-bundle
       "/tmp/x.org" "x" "/tmp/bundle/"
       :run (make-a3-pub-async-run :buffer (a3-pub-async/buffer))
       :on-done (lambda (s) (setq done-status s))))
    (should pdf-ran) (should word-ran)
    (should (eq (plist-get done-status :status) 'ok))))

(ert-deftest a3madkour-pub-multi/export-bundle-word-err-rollup ()
  "If word backend errors, rolled-up :status is 'err."
  (let (done-status)
    (cl-letf*
        (((symbol-function 'a3madkour-pub-multi-pdf/run)
          (lambda (&rest args)
            (let ((on-done (a3madkour-pub-multi--test--find-on-done args)))
              (when on-done (funcall on-done '(:status ok :path "/x.pdf"))))))
         ((symbol-function 'a3madkour-pub-multi-word/run)
          (lambda (&rest args)
            (let ((on-done (a3madkour-pub-multi--test--find-on-done args)))
              (when on-done (funcall on-done '(:status err :err-snippet "boom"))))))
         ((symbol-function 'a3madkour-pub-multi--prepare-source-for-pdf)
          (lambda (s _ _) s))
         ((symbol-function 'a3madkour-pub-multi--templates-dir)
          (lambda () "/tmp/t/"))
         ((symbol-function 'a3madkour-pub-multi--bib-path) (lambda () "/tmp/lib.bib"))
         ((symbol-function 'a3madkour-pub-multi--has-citations-p) (lambda (_) nil))
         ((symbol-function 'a3madkour-pub-multi--patch-downloads-frontmatter)
          (lambda (&rest _) nil)))
      (a3madkour-pub-multi/export-bundle
       "/tmp/x.org" "x" "/tmp/bundle/"
       :run (make-a3-pub-async-run :buffer (a3-pub-async/buffer))
       :on-done (lambda (s) (setq done-status s))))
    (should (eq (plist-get done-status :status) 'err))))

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
