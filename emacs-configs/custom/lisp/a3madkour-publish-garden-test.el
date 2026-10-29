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

(ert-deftest a3madkour-pub-garden--publish-file-records-draft-state ()
  "P2.1: a draft note (HUGO_DRAFT: t) must be recorded in the manifest with
state `draft', not the hard-coded `live'.  Otherwise a later draft→live flip
emits no history event and the manifest is factually wrong."
  (let* ((notes-dir (make-temp-file "a3-pub-notes-" t))
         (site-dir  (make-temp-file "a3-pub-site-" t))
         (src       (expand-file-name "draft-note.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (make-directory (expand-file-name "content/garden" site-dir) t)
          (with-temp-file src
            (insert ":PROPERTIES:\n"
                    ":ID: dddddddd-bbbb-cccc-dddd-eeeeeeeeeeee\n"
                    ":END:\n"
                    "#+title: Draft Note\n"
                    "#+filetags: :alpha:\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_DRAFT: t\n"
                    "#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "Body text.\n"))
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-garden/publish-garden-file
               src (make-a3-pub-async-run) :on-done (lambda (_) nil))
              (a3madkour-pub/finish-publish))
            (let* ((m (a3madkour-pub-history/read-manifest))
                   (note (aref (alist-get 'notes m) 0)))
              (should (equal (alist-get 'state note) "draft")))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(ert-deftest a3madkour-pub-garden--publish-file-lastmod-idempotent-uncommitted ()
  "P2.14 end-to-end: a never-committed note (git-mtime empty) republished after
a save (filesystem mtime bumped) must keep its FIRST-recorded last_modified —
the handler reuses the manifest-recorded value, so the emitted frontmatter and
manifest don't churn on every run."
  (let* ((notes-dir (make-temp-file "a3-pub-notes-" t))
         (site-dir  (make-temp-file "a3-pub-site-" t))
         (src       (expand-file-name "note.org" notes-dir))
         (fs-dates '("2026-03-03" "2026-09-09")))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (make-directory (expand-file-name "content/garden" site-dir) t)
          (with-temp-file src
            (insert ":PROPERTIES:\n:ID: cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee\n:END:\n"
                    "#+title: LM Note\n#+filetags: :alpha:\n"
                    "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "Body.\n"))
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore)
                      ;; never-committed: git-mtime empty.
                      ((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
                       (lambda (_) nil))
                      ;; each run, the filesystem mtime advances (a save).
                      ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
                       (lambda (_) (or (pop fs-dates) "2027-01-01"))))
              (dotimes (_ 2)
                (a3madkour-pub/begin-publish)
                (a3madkour-pub-garden/publish-garden-file
                 src (make-a3-pub-async-run) :on-done (lambda (_) nil))
                (a3madkour-pub/finish-publish))
              ;; Manifest keeps the first date, not the churned second one.
              (let ((note (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0)))
                (should (equal (alist-get 'last_modified note) "2026-03-03")))
              ;; Emitted frontmatter also stable.
              (with-temp-buffer
                (insert-file-contents
                 (expand-file-name "content/garden/lm-note/index.md" site-dir))
                (should (string-match-p "last_modified: 2026-03-03" (buffer-string)))
                (should-not (string-match-p "2026-09-09" (buffer-string)))))))
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

(ert-deftest a3madkour-pub-garden--render-yaml-value-escapes-quotes ()
  "P1.2: a string scalar with an embedded double-quote is escaped, not emitted
raw (which would be invalid YAML that breaks the Hugo build)."
  (should (equal (a3madkour-pub-garden--render-yaml-value "The \"x\" y")
                 "\"The \\\"x\\\" y\""))
  (should (equal (a3madkour-pub-garden--render-yaml-value '("a\"b"))
                 "[\"a\\\"b\"]")))

;;; -- Library item notes: only the `:site:' section reaches the site --

(defmacro a3madkour-pub-garden-test--publishing (src-var name text setup &rest body)
  "Write TEXT to NAME under a temp notes dir, publish it to a temp site.
SETUP is a form run after the note is written and before it publishes.
SRC-VAR is bound to the source path for TEXT (which may refer to it via
`%NOTES%' for the notes dir and `%SITE%' for the site dir).  BODY runs
with `notes-dir', `site-dir' and `bundle' (the garden bundle dir of the
note's slug) bound.  Dates are pinned so the output is reproducible."
  (declare (indent 4))
  `(let* ((notes-dir (file-name-as-directory (make-temp-file "a3-pub-notes-item-" t)))
          (site-dir  (file-name-as-directory (make-temp-file "a3-pub-site-item-" t)))
          (,src-var  (expand-file-name ,name notes-dir))
          (a3madkour-pub-canonical-asset-root (expand-file-name "assets" notes-dir)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "data" site-dir))
           (make-directory (expand-file-name "content/garden" site-dir) t)
           ;; ox-hugo refuses to export an image link without static/.
           (make-directory (expand-file-name "static" site-dir) t)
           (make-directory (file-name-directory ,src-var) t)
           (with-temp-file ,src-var
             (insert (replace-regexp-in-string
                      "%SITE%" site-dir
                      (replace-regexp-in-string "%NOTES%" notes-dir ,text t t)
                      t t)))
           ,setup
           (let ((a3madkour-pub/site-data-dir
                  (file-name-as-directory (expand-file-name "data" site-dir)))
                 (a3madkour-pub/org-notes-dir notes-dir))
             (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore)
                       ((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
                        (lambda (_) nil))
                       ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
                        (lambda (_) "2026-03-03")))
               (a3madkour-pub/begin-publish)
               (let (status)
                 (a3madkour-pub-garden/publish-garden-file
                  ,src-var (make-a3-pub-async-run)
                  :on-done (lambda (s) (setq status s)))
                 (should (eq status 'ok)))
               (a3madkour-pub/finish-publish)
               (let ((bundle (file-name-as-directory
                              (expand-file-name
                               (format "content/garden/%s/"
                                       (a3madkour-pub/note-slug ,src-var))
                               site-dir))))
                 ,@body))))
       (delete-directory notes-dir t)
       (delete-directory site-dir t))))

(defun a3madkour-pub-garden-test--index (bundle)
  "Text of BUNDLE's index.md."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "index.md" bundle))
    (buffer-string)))

(defconst a3madkour-pub-garden-test--concept
  (concat ":PROPERTIES:\n:ID: aaaaaaaa-1111-cccc-dddd-eeeeeeeeeeee\n:END:\n"
          "#+title: Example Concept\n#+filetags: :alpha:beta:\n"
          "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+HUGO_BASE_DIR: %SITE%\n"
          "Lede text.\n\n* First Heading\n:PROPERTIES:\n:PROGRESS: ref-notes\n:END:\n"
          "Body one.\n\n** Sub\nBody two.\n")
  "A concept note (no `LIBRARY_MEDIA_TYPE'): it publishes whole.")

(defconst a3madkour-pub-garden-test--concept-golden
  "---
draft: false
growth_stage: \"budding\"
last_modified: 2026-03-03
tags: [\"alpha\", \"beta\"]
title: \"Example Concept\"
---
Lede text.


## First Heading {#first-heading}

Body one.


### Sub {#sub}

Body two.
"
  "index.md for `--concept', recorded before item-note handling landed.")

(ert-deftest a3madkour-pub-garden-test/garden-concept-unchanged ()
  "A concept note's published index.md is byte-identical to the golden
recorded before item notes were handled: the item path never touches it."
  (a3madkour-pub-garden-test--publishing src "example-concept.org"
      a3madkour-pub-garden-test--concept nil
    (should (equal (a3madkour-pub-garden-test--index bundle)
                   a3madkour-pub-garden-test--concept-golden))))

(defconst a3madkour-pub-garden-test--item
  (concat ":PROPERTIES:\n:ID: bbbbbbbb-2222-cccc-dddd-eeeeeeeeeeee\n"
          ":LIBRARY_MEDIA_TYPE: book\n:LIBRARY_STATUS: reading\n"
          ":LIBRARY_CREATOR: Example Author\n:LIBRARY_YEAR: 1999\n"
          ":LIBRARY_STARTED: 2026-01-02\n:LIBRARY_FINISHED:\n:END:\n"
          "#+title: Example Book\n#+filetags: :Ref:Book:FavoriteThings:\n"
          "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+HUGO_BASE_DIR: %SITE%\n"
          "#+HUGO_CUSTOM_FRONT_MATTER: :status \"queued\"\n"
          "Lorem PREAMBLE-PRIVATE.\n\n"
          "* Highlights\nLorem HIGHLIGHT-PRIVATE [[./assets/page/example-book/a.png]]\n\n"
          "* Thoughts :site:\nLorem SITE-PUBLIC [[./assets/page/example-book/b.png]]\n\n"
          "* Later\nLorem LATER-PRIVATE.\n")
  "A library item note: only its `:site:' section may publish.")

(defun a3madkour-pub-garden-test--item-assets (notes-dir)
  "Create the item fixture's two page assets under NOTES-DIR."
  (let ((dir (expand-file-name "assets/page/example-book/" notes-dir)))
    (make-directory dir t)
    (dolist (f '("a.png" "b.png"))
      (with-temp-file (expand-file-name f dir) (insert f)))))

(ert-deftest a3madkour-pub-garden-test/garden-item-body-is-site-subtree-only ()
  "An item note's published body is its `:site:' section: the preamble and
every other heading stay in the org file."
  (a3madkour-pub-garden-test--publishing src "example-book.org"
      a3madkour-pub-garden-test--item
      (a3madkour-pub-garden-test--item-assets notes-dir)
    (let ((out (a3madkour-pub-garden-test--index bundle)))
      (should (string-match-p "SITE-PUBLIC" out))
      (should-not (string-match-p "PRIVATE" out))
      (should-not (string-match-p "Highlights\\|Later\\|Thoughts" out)))))

(ert-deftest a3madkour-pub-garden-test/garden-item-private-image-not-copied ()
  "An asset linked only outside the `:site:' section is never copied into
the bundle; the one linked inside it is."
  (a3madkour-pub-garden-test--publishing src "example-book.org"
      a3madkour-pub-garden-test--item
      (a3madkour-pub-garden-test--item-assets notes-dir)
    (should (file-exists-p (expand-file-name "b.png" bundle)))
    (should-not (file-exists-p (expand-file-name "a.png" bundle)))
    (should (equal (directory-files bundle nil "^[^.]") '("b.png" "index.md")))))

(ert-deftest a3madkour-pub-garden-test/garden-item-media-frontmatter-from-drawer ()
  "An item note's media fields come from its `LIBRARY_*' drawer (overriding
front matter written another way); its tags are cleaned of structure."
  (a3madkour-pub-garden-test--publishing src "example-book.org"
      a3madkour-pub-garden-test--item
      (a3madkour-pub-garden-test--item-assets notes-dir)
    (let ((out (a3madkour-pub-garden-test--index bundle)))
      (should (string-match-p "^media_type: \"book\"$" out))
      (should (string-match-p "^status: \"reading\"$" out))
      (should (string-match-p "^creator: \"Example Author\"$" out))
      (should (string-match-p "^started: \"?2026-01-02\"?$" out))
      (should (string-match-p "^year: 1999$" out))
      (should (string-match-p "^tags: \\[\"favorite-things\"\\]$" out))
      (should-not (string-match-p "queued\\|^finished:\\|^flavor:" out)))))

(ert-deftest a3madkour-pub-garden-test/garden-item-relative-asset-resolves-from-note ()
  "A `../'-relative asset link under `:site:' resolves against the note's
own directory, as it would without the site-only copy, not the temp dir."
  (a3madkour-pub-garden-test--publishing src "sub/example-book.org"
      (replace-regexp-in-string
       (regexp-quote "[[./assets/page/example-book/b.png]]")
       "[[../assets/page/example-book/b.png]]"
       a3madkour-pub-garden-test--item t t)
      (a3madkour-pub-garden-test--item-assets notes-dir)
    (should (equal (directory-files bundle nil "^[^.]") '("b.png" "index.md")))))

(ert-deftest a3madkour-pub-garden-test/garden-item-private-preamble-not-exported ()
  "Preamble keywords and drawer properties outside the allowlist never reach
index.md, including what a `#+setupfile:' would pull in."
  (let ((setup (make-temp-file "a3-pub-setup-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file setup (insert "#+hugo: PRIVATE-D\n"))
          (a3madkour-pub-garden-test--publishing src "example-book.org"
              (replace-regexp-in-string
               "^#\\+HUGO_CUSTOM_FRONT_MATTER: .*\n"
               (concat "#+hugo: PRIVATE-A\n#+caption: PRIVATE-B\n#+html: PRIVATE-C\n"
                       "#+setupfile: " setup "\n")
               (replace-regexp-in-string
                ":LIBRARY_FINISHED:\n"
                ":LIBRARY_FINISHED:\n:EXPORT_DESCRIPTION: PRIVATE-E\n"
                a3madkour-pub-garden-test--item t t)
               t t)
              (a3madkour-pub-garden-test--item-assets notes-dir)
            (let ((out (a3madkour-pub-garden-test--index bundle)))
              (should (string-match-p "SITE-PUBLIC" out))
              (should-not (string-match-p "PRIVATE" out)))))
      (delete-file setup))))

(ert-deftest a3madkour-pub-garden-test/garden-item-out-of-root-asset-not-moved ()
  "An item note never auto-moves an asset from outside the canonical root:
~/org is not mutated, the asset is skipped and a warning is logged."
  (let (warned)
    (cl-letf (((symbol-function 'a3madkour-pub/warn)
               (lambda (_m _f fmt &rest args)
                 (push (apply #'format fmt args) warned))))
      (a3madkour-pub-garden-test--publishing src "example-book.org"
          (replace-regexp-in-string
           (regexp-quote "[[./assets/page/example-book/b.png]]")
           "[[%NOTES%elsewhere/x.png]] [[file:%NOTES%elsewhere/y.png]]"
           a3madkour-pub-garden-test--item t t)
          (let ((d (expand-file-name "elsewhere/" notes-dir)))
            (make-directory d t)
            (dolist (f '("x.png" "y.png"))
              (with-temp-file (expand-file-name f d) (insert f))))
        (dolist (f '("x.png" "y.png"))
          (should (file-exists-p (expand-file-name (concat "elsewhere/" f) notes-dir)))
          (should-not (file-exists-p (expand-file-name f bundle)))
          (should-not (file-exists-p
                       (expand-file-name (concat "assets/page/example-book/" f)
                                         notes-dir))))
        (should (string-match-p (regexp-quote "elsewhere/x.png]]")
                                (with-temp-buffer (insert-file-contents src)
                                                  (buffer-string))))))
    (should (cl-some (lambda (w) (string-match-p "out-of-canonical-root" w))
                     warned))))

(provide 'a3madkour-publish-garden-test)

;;; a3madkour-publish-garden-test.el ends here
