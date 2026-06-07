;;; a3madkour-publish-garden-test.el --- tests for garden handler  -*- lexical-binding: t; -*-

(require 'ert)
(require 'a3madkour-publish-garden)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-async)

(ert-deftest a3madkour-pub-garden--module-loads ()
  "Smoke: module is loadable and exposes publish-garden-file."
  (should (fboundp 'a3madkour-pub-garden/publish-garden-file)))

(ert-deftest a3madkour-pub-garden--render-yaml-value-strings ()
  "render-yaml-value handles strings, numbers, booleans, lists."
  (should (equal (a3madkour-pub-garden--render-yaml-value "hello") "\"hello\""))
  (should (equal (a3madkour-pub-garden--render-yaml-value 42) "42"))
  (should (equal (a3madkour-pub-garden--render-yaml-value t) "true"))
  (should (equal (a3madkour-pub-garden--render-yaml-value nil) "false"))
  (should (equal (a3madkour-pub-garden--render-yaml-value '("a" "b"))
                 "[\"a\", \"b\"]")))

(ert-deftest a3madkour-pub-garden--render-frontmatter-sorted ()
  "render-frontmatter emits alphabetical keys with ---delimiters."
  (let* ((alist '((title . "Z Note") (draft . nil) (growth_stage . "seedling")))
         (rendered (a3madkour-pub-garden--render-frontmatter alist)))
    (should (string-prefix-p "---\n" rendered))
    (should (string-suffix-p "---\n" rendered))
    ;; Keys must appear in alphabetical order.
    (let ((draft-pos   (string-search "draft:" rendered))
          (growth-pos  (string-search "growth_stage:" rendered))
          (title-pos   (string-search "title:" rendered)))
      (should (< draft-pos growth-pos))
      (should (< growth-pos title-pos)))))

(ert-deftest a3madkour-pub-garden--write-if-different-writes-new ()
  "write-if-different creates a new file and returns t."
  (let* ((dir (make-temp-file "a3-pub-test-" t))
         (path (expand-file-name "test.md" dir)))
    (unwind-protect
        (progn
          (should (eq t (a3madkour-pub-garden--write-if-different path "content")))
          (should (file-exists-p path))
          (with-temp-buffer
            (insert-file-contents path)
            (should (equal (buffer-string) "content"))))
      (delete-directory dir t))))

(ert-deftest a3madkour-pub-garden--write-if-different-noop-on-match ()
  "write-if-different returns nil and does not rewrite when content matches."
  (let* ((dir (make-temp-file "a3-pub-test-" t))
         (path (expand-file-name "test.md" dir)))
    (unwind-protect
        (progn
          (with-temp-file path (insert "same content"))
          ;; First call: already matches → no-op.
          (should (eq nil (a3madkour-pub-garden--write-if-different path "same content")))
          ;; File still exists with unchanged content.
          (with-temp-buffer
            (insert-file-contents path)
            (should (equal (buffer-string) "same content"))))
      (delete-directory dir t))))

(ert-deftest a3madkour-pub-garden--site-root-from-data-dir ()
  "site-root returns the parent of the data/ dir."
  (let* ((dir (make-temp-file "a3-pub-site-" t))
         (data-dir (file-name-as-directory (expand-file-name "data" dir)))
         (a3madkour-pub/site-data-dir data-dir))
    (unwind-protect
        (progn
          (make-directory data-dir t)
          (let ((root (a3madkour-pub-garden--site-root)))
            ;; Root should be the parent of data/, i.e. dir itself.
            (should (equal (file-name-as-directory root)
                           (file-name-as-directory dir)))))
      (delete-directory dir t))))

(ert-deftest a3madkour-pub-garden--publish-garden-file-end-to-end ()
  "publish-garden-file writes content/garden/<slug>/index.md with
normalized frontmatter + body + record-publish call."
  (let* ((notes-dir (make-temp-file "a3-pub-notes-" t))
         (site-dir  (make-temp-file "a3-pub-site-" t))
         (src       (expand-file-name "example-note.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (make-directory (expand-file-name "content/garden" site-dir) t)
          (with-temp-file src
            (insert ":PROPERTIES:\n"
                    ":ID: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n"
                    ":END:\n"
                    "#+title: Example Note\n"
                    "#+filetags: :alpha:\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "* The Heading\n"
                    "  :PROPERTIES:\n"
                    "  :PROGRESS: ref-notes\n"
                    "  :END:\n"
                    "Body text.\n"))
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir))
            ;; Stub org-roam-db-sync so we don't touch the real DB.
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-garden/publish-garden-file
               src (make-a3-pub-async-run) :on-done (lambda (_) nil))
              (a3madkour-pub/finish-publish)))
          (let ((out (expand-file-name
                      "content/garden/example-note/index.md" site-dir)))
            (should (file-exists-p out))
            (with-temp-buffer
              (insert-file-contents out)
              (should (string-match-p "title:" (buffer-string)))
              (should (string-match-p "growth_stage:" (buffer-string)))
              (should (string-match-p "budding" (buffer-string)))
              (should (string-match-p "Body text" (buffer-string))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(ert-deftest a3madkour-pub-garden--publish-garden-file-rewrites-links ()
  "publish-garden-file pre-rewrites [[id:UUID]] links so the emitted
markdown has resolved HTML anchors and zero `{{< relref' shortcodes.

This is the B.1.1 regression test: prior to pre-export buffer rewriting,
ox-hugo emitted `[text]({{< relref \"<filename>.md\" >}})' for every
id-link, which then failed Hugo's REF_NOT_FOUND check against B's
hyphen-slug bundles."
  (let* ((notes-dir (make-temp-file "a3-pub-notes-b11-" t))
         (site-dir  (make-temp-file "a3-pub-site-b11-" t))
         ;; Two notes — `source` links to `target`.  Order is enforced by
         ;; the explicit hardcoded calls below (target first, then source),
         ;; so the manifest entry exists when the source is processed.
         ;; (Alphabetical file naming is for the Task 5 integration fixture
         ;; where walk-section drives ordering — not relevant here.)
         (target-src (expand-file-name "a-target.org" notes-dir))
         (source-src (expand-file-name "b-source.org" notes-dir))
         (target-id  "11111111-2222-3333-4444-555555555555")
         (source-id  "66666666-7777-8888-9999-aaaaaaaaaaaa"))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (make-directory (expand-file-name "content/garden" site-dir) t)
          (with-temp-file target-src
            (insert ":PROPERTIES:\n"
                    ":ID: " target-id "\n"
                    ":END:\n"
                    "#+title: Target Note\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "Target body.\n"))
          (with-temp-file source-src
            (insert ":PROPERTIES:\n"
                    ":ID: " source-id "\n"
                    ":END:\n"
                    "#+title: Source Note\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "Body text linking to [[id:" target-id "][the target]] "
                    "and to [[id:00000000-0000-0000-0000-000000000000][a private one]].\n"))
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore)
                      ;; id-to-file resolves both real IDs to their .org files.
                      ;; The "private" UUID resolves to nil, exercising the
                      ;; :inert branch via published-p returning nil.
                      ((symbol-function 'a3madkour-pub--id-to-file)
                       (lambda (id)
                         (cond ((equal id target-id) target-src)
                               ((equal id source-id) source-src)
                               (t nil)))))
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-garden/publish-garden-file
               target-src (make-a3-pub-async-run) :on-done (lambda (_) nil))
              (a3madkour-pub-garden/publish-garden-file
               source-src (make-a3-pub-async-run) :on-done (lambda (_) nil))
              (a3madkour-pub/finish-publish)))
          (let* ((out  (expand-file-name
                        "content/garden/source-note/index.md" site-dir))
                 (body (with-temp-buffer
                         (insert-file-contents out)
                         (buffer-string))))
            (should (file-exists-p out))
            ;; Resolved link → HTML anchor at the right hyphen-slug URL.
            (should (string-match-p
                     "<a href=\"/garden/target-note/\">the target</a>"
                     body))
            ;; Unresolved link → inert plain text, no anchor.
            (should (string-match-p "a private one" body))
            (should-not (string-match-p
                         "<a [^>]*>a private one</a>" body))
            ;; And critically: no ox-hugo relref shortcodes survived.
            (should-not (string-match-p "{{< *relref" body))
            (should-not (string-match-p "\\[\\[id:" body))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(ert-deftest a3madkour-pub-garden-test/publisher-threads-id-to-asset-validate ()
  "publish-garden-file passes the note's :id as source-note-id to asset-validate-and-copy."
  (let ((captured-id 'unset)
        (tmp-src (make-temp-file "garden-threads-id-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp-src (insert "#+title: T\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
                     (lambda (_f)
                       (list :id "garden-id-77" :slug "test-note" :section "garden"
                             :state 'live :title "T")))
                    ((symbol-function 'a3madkour-pub/note-url)
                     (lambda (_f) "/garden/test-note/"))
                    ((symbol-function 'a3madkour-pub-garden--site-root)
                     (lambda () "/tmp/site-stub/"))
                    ((symbol-function 'a3madkour-pub-rewrite/rewrite-to-tmp-file)
                     (lambda (file _id _tag)
                       ;; Return a distinct temp copy so the unwind-protect
                       ;; delete-file in the exporter doesn't remove file itself.
                       (let ((copy (make-temp-file "garden-rewrite-stub-" nil ".org")))
                         (copy-file file copy t)
                         copy)))
                    ((symbol-function 'a3madkour-pub-export/export-file)
                     (lambda (_f) (list :body "stub-body" :frontmatter nil)))
                    ((symbol-function 'a3madkour-pub-frontmatter/normalize)
                     (lambda (_section raw _f) raw))
                    ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
                     (lambda (_org _bundle &optional source-note-id &rest _)
                       (setq captured-id source-note-id)
                       (list :copied nil :removed nil :warnings nil :errors nil)))
                    ((symbol-function 'a3madkour-pub-garden--write-if-different)
                     (lambda (_p _c) nil))
                    ((symbol-function 'a3madkour-pub-garden--render-frontmatter)
                     (lambda (_n) ""))
                    ((symbol-function 'a3madkour-pub-history/record-publish)
                     (lambda (_id _url _state) nil)))
            (a3madkour-pub-garden/publish-garden-file
             tmp-src (make-a3-pub-async-run) :on-done (lambda (_) nil))
            (should (equal captured-id "garden-id-77"))))
      (when (file-exists-p tmp-src) (delete-file tmp-src)))))

;;; -- Task 14: handler async signature --

(ert-deftest a3madkour-pub-garden-test/handler-async-signature ()
  "publish-garden-file accepts (file run &key on-done) and calls on-done."
  (let (done-status
        (tmp-src (make-temp-file "garden-async-sig-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp-src (insert "#+title: T\n"))
          (cl-letf*
              (;; Stub every step so the handler runs without I/O.
               ((symbol-function 'a3madkour-pub/note-metadata)
                (lambda (_) '(:id "fake-id" :slug "fake-slug")))
               ((symbol-function 'a3madkour-pub/note-slug)
                (lambda (_) "fake-slug"))
               ((symbol-function 'a3madkour-pub/note-url)
                (lambda (_) "/fake/url/"))
               ((symbol-function 'a3madkour-pub-garden--site-root)
                (lambda () "/tmp/"))
               ((symbol-function 'a3madkour-pub-rewrite/rewrite-to-tmp-file)
                (lambda (file _id _tag)
                  (let ((copy (make-temp-file "garden-async-stub-" nil ".org")))
                    (copy-file file copy t)
                    copy)))
               ((symbol-function 'a3madkour-pub-export/export-file)
                (lambda (_) '(:body "" :frontmatter ())))
               ((symbol-function 'a3madkour-pub-frontmatter/normalize)
                (lambda (&rest _) '((:title . "x"))))
               ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
                (lambda (&rest _) nil))
               ((symbol-function 'a3madkour-pub-garden--write-if-different)
                (lambda (&rest _) nil))
               ((symbol-function 'a3madkour-pub-garden--render-frontmatter)
                (lambda (_n) ""))
               ((symbol-function 'a3madkour-pub-history/record-publish)
                (lambda (&rest _) nil)))
            (with-a3-pub-async-sync
             (a3madkour-pub-garden/publish-garden-file
              tmp-src (make-a3-pub-async-run)
              :on-done (lambda (s) (setq done-status s))))))
      (when (file-exists-p tmp-src) (delete-file tmp-src)))
    (should (eq done-status 'ok))))

(ert-deftest a3madkour-pub-garden-test/handler-async-error-routes-on-done-err ()
  "When the sync pipeline throws, on-done fires with 'err."
  (let (done-status)
    (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
               (lambda (_) (error "boom"))))
      (with-a3-pub-async-sync
       (a3madkour-pub-garden/publish-garden-file
        "/tmp/fake.org" (make-a3-pub-async-run)
        :on-done (lambda (s) (setq done-status s)))))
    (should (eq done-status 'err))))

(provide 'a3madkour-publish-garden-test)

;;; a3madkour-publish-garden-test.el ends here
