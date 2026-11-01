;;; a3madkour-publish-paths-test.el --- tests for a3madkour-publish-paths.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; The publisher names none of the author's folders: each folder variable
;;; defaults to nil, an unset one is an error naming it, config.org sets
;;; every one, and a3-pub.sh loads the file config.org tangles them to.
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'a3madkour-publish-paths)
(require 'a3madkour-publish)
(require 'a3madkour-publish-poetry)
(require 'a3madkour-publish-essays)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-unpublish)
(require 'a3madkour-publish-living)
(require 'a3madkour-publish-citations)
(require 'a3madkour-publish-bib)
(require 'a3madkour-works-lint)
(require 'a3madkour-library-items)

(defconst a3madkour-pub-paths-test--lisp-dir
  (file-name-directory (or load-file-name buffer-file-name)))

(defun a3madkour-pub-paths-test--names-var-p (err var)
  "Non-nil when ERR is a `user-error' whose message names VAR."
  (and (eq (car err) 'user-error)
       (string-match-p (regexp-quote (symbol-name var)) (cadr err))))

(defmacro a3madkour-pub-paths-test--unset (var &rest body)
  "Run BODY with VAR nil; assert BODY signals a `user-error' naming VAR."
  (declare (indent 1))
  `(let ((,var nil))
     (let ((err (should-error (progn ,@body) :type 'user-error)))
       (should (a3madkour-pub-paths-test--names-var-p err ',var)))))

;; -- the library names no folder --

(ert-deftest a3madkour-pub-paths-test/library-defaults-are-nil ()
  (dolist (var a3madkour-pub/path-variables)
    (should (custom-variable-p var))
    (should (null (eval (car (get var 'standard-value)) t)))))

(ert-deftest a3madkour-pub-paths-test/path-errors-naming-the-variable ()
  (a3madkour-pub-paths-test--unset a3madkour-pub/poetry-dir
    (a3madkour-pub/path 'a3madkour-pub/poetry-dir))
  (let ((a3madkour-pub/poetry-dir ""))
    (should-error (a3madkour-pub/path 'a3madkour-pub/poetry-dir)
                  :type 'user-error)))

(ert-deftest a3madkour-pub-paths-test/path-expands-a-set-value ()
  (let ((a3madkour-pub/poetry-dir "~/somewhere/poems/"))
    (should (equal (a3madkour-pub/path 'a3madkour-pub/poetry-dir)
                   (expand-file-name "~/somewhere/poems/")))))

;; -- every consumer refuses an unset folder instead of using cwd --

(ert-deftest a3madkour-pub-paths-test/poetry-audio-needs-poetry-dir ()
  (let ((dest (make-temp-file "poem-bundle-" t)))
    (unwind-protect
        (a3madkour-pub-paths-test--unset a3madkour-pub/poetry-dir
          (a3madkour-pub-poetry--copy-audio-asset "some-id" "reading.mp3" dest))
      (delete-directory dest t))))

(ert-deftest a3madkour-pub-paths-test/works-lint-lyrics-needs-poetry-dir ()
  (a3madkour-pub-paths-test--unset a3madkour-pub/poetry-dir
    (a3madkour-works-lint--check-lyrics-symmetry
     "track.org" '((lyrics_poem . ("a-poem" . 3))))))

(ert-deftest a3madkour-pub-paths-test/essay-assets-need-essays-dir ()
  (let ((dest (make-temp-file "essay-bundle-" t)))
    (unwind-protect
        (a3madkour-pub-paths-test--unset a3madkour-pub/essays-dir
          (a3madkour-pub-essays--copy-asset-dir "some-id" dest))
      (delete-directory dest t))))

(ert-deftest a3madkour-pub-paths-test/living-walk-needs-notes-dir ()
  (a3madkour-pub-paths-test--unset a3madkour-pub/org-notes-dir
    (a3madkour-pub-living--collect-triples))
  (a3madkour-pub-paths-test--unset a3madkour-pub/org-notes-dir
    (a3madkour-pub/walk-published-source-set)))

(ert-deftest a3madkour-pub-paths-test/asset-root-must-be-set ()
  (a3madkour-pub-paths-test--unset a3madkour-pub-canonical-asset-root
    (a3madkour-pub--asset-normalize-link-path "./assets/page/x/a.png"
                                              "/tmp/note.org"))
  (a3madkour-pub-paths-test--unset a3madkour-pub-canonical-asset-root
    (a3madkour-pub--unpublish-rename-asset-dir "old" "new")))

(ert-deftest a3madkour-pub-paths-test/ref-note-lookup-needs-ref-notes-dir ()
  (a3madkour-pub-paths-test--unset a3madkour-pub-citations/ref-notes-dir
    (a3madkour-pub-citations--lookup-notes-ref "pierce2002")))

(ert-deftest a3madkour-pub-paths-test/bib-refresh-needs-library-path ()
  (let ((a3madkour-pub-bib/bbt-endpoint "http://127.0.0.1:1/never"))
    (a3madkour-pub-paths-test--unset a3madkour-pub-bib/library-path
      (a3madkour-pub-bib/refresh-from-zotero))))

(ert-deftest a3madkour-pub-paths-test/library-add-needs-notes-dir ()
  (a3madkour-pub-paths-test--unset a3madkour-library/notes-dir
    (a3madkour-library--new-item-file "Some Title")))

;; -- a renamed slug's asset links follow the configured asset root --

(ert-deftest a3madkour-pub-paths-test/slug-rename-rewrites-links-under-the-asset-root ()
  (let* ((root (file-name-as-directory (make-temp-file "asset-root-" t)))
         (notes (file-name-as-directory (make-temp-file "notes-" t)))
         (note (expand-file-name "n.org" notes))
         (a3madkour-pub-canonical-asset-root (concat root "assets")))
    (unwind-protect
        (progn
          (with-temp-file note
            (insert (format "[[file:%sassets/page/old-slug/a.png]]\n" root)))
          (a3madkour-pub--unpublish-bulk-rewrite-source-links
           "old-slug" "new-slug" notes)
          (with-temp-buffer
            (insert-file-contents note)
            (should (string-match-p
                     (regexp-quote (format "%sassets/page/new-slug/a.png" root))
                     (buffer-string)))))
      (delete-directory root t)
      (delete-directory notes t))))

;; -- config.org sets every folder, and config.el loads the tangled file --

(defun a3madkour-pub-paths-test--config-org ()
  (expand-file-name "../config.org" a3madkour-pub-paths-test--lisp-dir))

(defun a3madkour-pub-paths-test--paths-block ()
  "Body of config.org's src block tangling to publish-paths.el, or nil."
  (with-temp-buffer
    (insert-file-contents (a3madkour-pub-paths-test--config-org))
    (when (re-search-forward
           "^#\\+begin_src emacs-lisp :tangle \"\\./publish-paths\\.el\".*\n" nil t)
      (let ((start (point)))
        (re-search-forward "^#\\+end_src")
        (buffer-substring-no-properties start (match-beginning 0))))))

(ert-deftest a3madkour-pub-paths-test/config-block-sets-every-folder ()
  (let ((body (a3madkour-pub-paths-test--paths-block)))
    (should body)
    (eval
     `(let ,(mapcar (lambda (v) (list v nil)) a3madkour-pub/path-variables)
        ,@(car (read-from-string (format "(%s)" body)))
        (dolist (v a3madkour-pub/path-variables)
          (should (stringp (symbol-value v)))
          (should-not (string-empty-p (symbol-value v)))))
     t)))

(ert-deftest a3madkour-pub-paths-test/config-poems-live-outside-the-roam-tree ()
  (let ((body (a3madkour-pub-paths-test--paths-block)))
    (eval
     `(let ,(mapcar (lambda (v) (list v nil)) a3madkour-pub/path-variables)
        ,@(car (read-from-string (format "(%s)" body)))
        (should-not (string-prefix-p
                     (file-name-as-directory
                      (expand-file-name a3madkour-pub/org-notes-dir))
                     (expand-file-name a3madkour-pub/poetry-dir))))
     t)))

(ert-deftest a3madkour-pub-paths-test/config-el-loads-the-paths-file ()
  (with-temp-buffer
    (insert-file-contents (a3madkour-pub-paths-test--config-org))
    (should (re-search-forward
             "(load (expand-file-name \"publish-paths\\.el\" user-emacs-directory)"
             nil t))))

;; -- a3-pub.sh loads the paths file before every batch run --

(defun a3madkour-pub-paths-test--a3-pub (paths-file &rest args)
  "Run a3-pub.sh with A3_PUB_PATHS_FILE=PATHS-FILE and ARGS.
Returns (EXIT-CODE . OUTPUT)."
  (let ((process-environment
         (cons (format "A3_PUB_PATHS_FILE=%s" paths-file) process-environment)))
    (with-temp-buffer
      (let ((code (apply #'call-process "bash" nil t nil
                         (expand-file-name "a3-pub.sh"
                                           a3madkour-pub-paths-test--lisp-dir)
                         args)))
        (cons code (buffer-string))))))

(defun a3madkour-pub-paths-test--straight-p ()
  (file-exists-p (expand-file-name
                  "../straight/repos/straight.el/bootstrap.el"
                  a3madkour-pub-paths-test--lisp-dir)))

(ert-deftest a3madkour-pub-paths-test/a3-pub-loads-the-paths-file ()
  (skip-unless (a3madkour-pub-paths-test--straight-p))
  (let ((paths (make-temp-file "publish-paths-" nil ".el"
                               "(setq a3madkour-pub/poetry-dir \"/from/the/paths/file/\")\n")))
    (unwind-protect
        (let ((r (a3madkour-pub-paths-test--a3-pub
                  paths "--eval" "(princ (format \"POETRY=%s\\n\" a3madkour-pub/poetry-dir))")))
          (should (= (car r) 0))
          (should (string-match-p "POETRY=/from/the/paths/file/" (cdr r))))
      (delete-file paths))))

(ert-deftest a3madkour-pub-paths-test/a3-pub-refuses-a-missing-paths-file ()
  (skip-unless (a3madkour-pub-paths-test--straight-p))
  (let ((r (a3madkour-pub-paths-test--a3-pub
            "/nonexistent/publish-paths.el" "--eval" "(princ \"RAN\")")))
    (should-not (= (car r) 0))
    (should-not (string-match-p "RAN" (cdr r)))
    (should (string-match-p "publish-paths\\.el" (cdr r)))))

(provide 'a3madkour-publish-paths-test)

;;; a3madkour-publish-paths-test.el ends here
