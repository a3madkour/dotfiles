;;; a3madkour-publish-essays-test.el --- ert tests for B.4 essays handler -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-essays)

;; -- B.4 Task 4: has_* body scanner --

(ert-deftest a3madkour-pub-essays-test/scan-sidenotes-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags
                  "lorem {{< sidenote >}}x{{< /sidenote >}} ipsum")
                 :has_sidenotes))))

(ert-deftest a3madkour-pub-essays-test/scan-sidenotes-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_sidenotes)))

(ert-deftest a3madkour-pub-essays-test/scan-citations-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see {{< cite \"k\" >}} here")
                 :has_citations))))

(ert-deftest a3madkour-pub-essays-test/scan-citations-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_citations)))

(ert-deftest a3madkour-pub-essays-test/scan-footnotes-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "lorem[^1] ipsum\n\n[^1]: note")
                 :has_footnotes))))

(ert-deftest a3madkour-pub-essays-test/scan-footnotes-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only no refs")
               :has_footnotes)))

(ert-deftest a3madkour-pub-essays-test/scan-math-shortcode ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags
                  "see {{< math >}}\\alpha{{< /math >}}")
                 :has_math))))

(ert-deftest a3madkour-pub-essays-test/scan-math-inline-delim ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see \\(\\alpha\\) here")
                 :has_math))))

(ert-deftest a3madkour-pub-essays-test/scan-math-display-delim ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see \\[\\alpha\\] here")
                 :has_math))))

(ert-deftest a3madkour-pub-essays-test/scan-math-environment ()
  "Body contains \\begin{equation}...\\end{equation} → :has_math is t."
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags
                  "see \\begin{equation}E = mc^2\\end{equation} here")
                 :has_math))))

(ert-deftest a3madkour-pub-essays-test/scan-math-inside-code-fence-ignored ()
  "Body's only math marker is inside a ```-fenced code block → :has_math is nil."
  (let ((body (concat "Prose line.\n"
                      "```python\n"
                      "# illustrative LaTeX: \\(x = 1\\)\n"
                      "```\n"
                      "More prose.\n")))
    (should-not (plist-get
                 (a3madkour-pub-essays--scan-has-flags body)
                 :has_math))))

(ert-deftest a3madkour-pub-essays-test/scan-math-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_math)))

(ert-deftest a3madkour-pub-essays-test/scan-widgets-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see {{< widget \"x\" >}}")
                 :has_widgets))))

(ert-deftest a3madkour-pub-essays-test/scan-widgets-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_widgets)))

(ert-deftest a3madkour-pub-essays-test/scan-video-sync-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see {{< video-sync \"x\" >}}")
                 :has_video_sync))))

(ert-deftest a3madkour-pub-essays-test/scan-video-sync-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_video_sync)))

;; -- B.4 Task 5: has_* override merge --

(ert-deftest a3madkour-pub-essays-test/merge-keyword-override-wins-false ()
  "Body has sidenote shortcode AND #+HUGO_HAS_SIDENOTES: nil → false."
  (let ((tmp (make-temp-file "essays-merge-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+HUGO_HAS_SIDENOTES: nil\n"))
          (let* ((scan '(:has_sidenotes t :has_citations nil
                         :has_footnotes nil :has_math nil
                         :has_widgets nil :has_video_sync nil))
                 (merged (a3madkour-pub-essays--merge-has-flags scan tmp)))
            (should (eq (plist-get merged :has_sidenotes) nil))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-essays-test/merge-keyword-override-wins-true ()
  "No body shortcode but #+HUGO_HAS_WIDGETS: t → true."
  (let ((tmp (make-temp-file "essays-merge-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+HUGO_HAS_WIDGETS: t\n"))
          (let* ((scan '(:has_sidenotes nil :has_citations nil
                         :has_footnotes nil :has_math nil
                         :has_widgets nil :has_video_sync nil))
                 (merged (a3madkour-pub-essays--merge-has-flags scan tmp)))
            (should (eq (plist-get merged :has_widgets) t))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-essays-test/merge-absent-keyword-uses-scan ()
  "No #+HUGO_HAS_* keywords → scan result wins."
  (let ((tmp (make-temp-file "essays-merge-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+title: x\n"))
          (let* ((scan '(:has_sidenotes t :has_citations nil
                         :has_footnotes t :has_math nil
                         :has_widgets nil :has_video_sync nil))
                 (merged (a3madkour-pub-essays--merge-has-flags scan tmp)))
            (should (eq (plist-get merged :has_sidenotes) t))
            (should (eq (plist-get merged :has_citations) nil))
            (should (eq (plist-get merged :has_footnotes) t))))
      (delete-file tmp))))

;; -- B.4 Task 8: publish-essay-file end-to-end (stubbed) --

(ert-deftest a3madkour-pub-essays-test/publish-essay-file-writes-bundle-and-records ()
  "End-to-end stubbed: handler exports stub body, writes content/essays/<slug>/index.md,
calls record-publish with the correct URL."
  (let ((tmp-essays-dir (make-temp-file "essays-pub-src-" t))
        (tmp-site-data (make-temp-file "essays-pub-site-" t))
        (tmp-site-content (make-temp-file "essays-pub-content-" t))
        recorded)
    (unwind-protect
        (let* ((src (expand-file-name "example-one.org" tmp-essays-dir))
               (site-root (file-name-as-directory
                           (directory-file-name
                            (file-name-directory
                             (file-name-as-directory tmp-site-data)))))
               (a3madkour-pub/site-data-dir (file-name-as-directory tmp-site-data)))
          (with-temp-file src
            (insert ":PROPERTIES:\n:ID: essay-one-uuid\n:END:\n"
                    "#+title: Example essay one\n"
                    "#+date: 2026-04-12\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: essays\n"
                    "#+HUGO_SUMMARY: Lorem ipsum.\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
                     (lambda (_) (list :id "essay-one-uuid" :slug "example-one" :section "essays")))
                    ((symbol-function 'a3madkour-pub/note-slug)
                     (lambda (_) "example-one"))
                    ((symbol-function 'a3madkour-pub/note-url)
                     (lambda (_) "/essays/example-one/"))
                    ((symbol-function 'a3madkour-pub-export/export-file)
                     (lambda (_) (list :frontmatter '((title . "Example essay one")
                                                     (date . "2026-04-12")
                                                     (summary . "Lorem ipsum."))
                                       :body "Lorem ipsum body.")))
                    ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
                     (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-history/record-publish)
                     (lambda (id url state)
                       (setq recorded (list id url state))))
                    ((symbol-function 'a3madkour-pub-essays--site-root)
                     (lambda () site-root)))
            (a3madkour-pub-essays/publish-essay-file src))
          ;; Bundle exists.
          (should (file-exists-p (expand-file-name
                                  "content/essays/example-one/index.md" site-root)))
          ;; record-publish called with correct URL + state.
          (should (equal recorded '("essay-one-uuid" "/essays/example-one/" live)))
          ;; Body present in output.
          (let ((written (with-temp-buffer
                           (insert-file-contents
                            (expand-file-name "content/essays/example-one/index.md" site-root))
                           (buffer-string))))
            (should (string-match-p "Lorem ipsum body\\." written))
            ;; Frontmatter has all 14 required keys.
            (dolist (k '("title" "date" "lastmod" "draft" "summary" "tags"
                         "series" "series_order" "toc"
                         "has_sidenotes" "has_citations" "has_footnotes"
                         "has_math" "has_widgets" "has_video_sync"))
              (should (string-match-p (format "^%s:" k) written)))))
      (when (file-exists-p tmp-essays-dir) (delete-directory tmp-essays-dir t))
      (when (file-exists-p tmp-site-data) (delete-directory tmp-site-data t))
      (when (file-exists-p tmp-site-content) (delete-directory tmp-site-content t)))))

(ert-deftest a3madkour-pub-essays-test/publish-essay-file-injects-scan-plist ()
  "Handler scans body and threads the result into normalize via :scan-plist."
  (let ((tmp-essays-dir (make-temp-file "essays-pub-src-" t))
        (tmp-site-data (make-temp-file "essays-pub-site-" t))
        injected-raw)
    (unwind-protect
        (let* ((src (expand-file-name "example-x.org" tmp-essays-dir))
               (site-root (file-name-as-directory
                           (directory-file-name
                            (file-name-directory
                             (file-name-as-directory tmp-site-data)))))
               (a3madkour-pub/site-data-dir (file-name-as-directory tmp-site-data)))
          (with-temp-file src (insert ":PROPERTIES:\n:ID: x\n:END:\n#+title: x\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
                     (lambda (_) (list :id "x" :slug "x" :section "essays")))
                    ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "x"))
                    ((symbol-function 'a3madkour-pub/note-url) (lambda (_) "/essays/x/"))
                    ((symbol-function 'a3madkour-pub-export/export-file)
                     (lambda (_) (list :frontmatter nil
                                       :body "lorem {{< sidenote >}}n{{< /sidenote >}} ipsum")))
                    ((symbol-function 'a3madkour-pub/asset-validate-and-copy) (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-history/record-publish) (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-frontmatter/normalize)
                     (lambda (section raw _)
                       (when (eq section 'essays) (setq injected-raw raw))
                       (or raw '())))
                    ((symbol-function 'a3madkour-pub-essays--site-root)
                     (lambda () site-root)))
            (a3madkour-pub-essays/publish-essay-file src))
          (should (assq :scan-plist injected-raw))
          (should (eq (plist-get (alist-get :scan-plist injected-raw) :has_sidenotes) t)))
      (when (file-exists-p tmp-essays-dir) (delete-directory tmp-essays-dir t))
      (when (file-exists-p tmp-site-data) (delete-directory tmp-site-data t)))))

(ert-deftest a3madkour-pub-essays-test/publish-essay-file-no-hero-still-runs-asset-copy ()
  "asset-validate-and-copy is always called (it handles per-bundle assets
generally); absence of #+HUGO_HERO does not skip it."
  (let ((tmp-essays-dir (make-temp-file "essays-pub-src-" t))
        (tmp-site-data (make-temp-file "essays-pub-site-" t))
        asset-call-count)
    (setq asset-call-count 0)
    (unwind-protect
        (let* ((src (expand-file-name "example-x.org" tmp-essays-dir))
               (site-root (file-name-as-directory
                           (directory-file-name
                            (file-name-directory
                             (file-name-as-directory tmp-site-data)))))
               (a3madkour-pub/site-data-dir (file-name-as-directory tmp-site-data)))
          (with-temp-file src (insert ":PROPERTIES:\n:ID: x\n:END:\n#+title: x\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
                     (lambda (_) (list :id "x" :slug "x" :section "essays")))
                    ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "x"))
                    ((symbol-function 'a3madkour-pub/note-url) (lambda (_) "/essays/x/"))
                    ((symbol-function 'a3madkour-pub-export/export-file)
                     (lambda (_) (list :frontmatter nil :body "body")))
                    ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
                     (lambda (&rest _) (cl-incf asset-call-count)))
                    ((symbol-function 'a3madkour-pub-history/record-publish) (lambda (&rest _) nil))
                    ((symbol-function 'a3madkour-pub-essays--site-root)
                     (lambda () site-root)))
            (a3madkour-pub-essays/publish-essay-file src))
          (should (= asset-call-count 1)))
      (when (file-exists-p tmp-essays-dir) (delete-directory tmp-essays-dir t))
      (when (file-exists-p tmp-site-data) (delete-directory tmp-site-data t)))))

;; -- B.4 spot-check fix: render empty tags --

(ert-deftest a3madkour-pub-essays-test/render-empty-tags-as-array ()
  "Issue B: render-frontmatter must emit `tags: []' (not `tags: false')
when the tags value is an empty list.  The render-yaml-value cond tests
null BEFORE listp, so `nil' alone → \"false\".  The fix must ensure that
an empty-list tags value is rendered as `[]' rather than `false'."
  ;; This test drives the render path directly: given a normalized alist
  ;; containing (tags . nil) or (tags . []) or similar empty-list marker,
  ;; the rendered YAML must contain "tags: []".
  (let* ((alist-with-nil-tags
          '((title . "T") (date . "2026-04-12") (lastmod . "2026-04-12")
            (draft . nil) (summary . "") (tags . nil)
            (series . "") (series_order . 0) (toc . t)
            (has_sidenotes . nil) (has_citations . nil) (has_footnotes . nil)
            (has_math . nil) (has_widgets . nil) (has_video_sync . nil)))
         ;; We test the rendered output — the fix must NOT regress bool nil fields
         ;; (draft, has_*) which render as "false" — only tags must be [].
         ;; Since render-frontmatter dispatches by key for tags (option d),
         ;; we cannot pass nil directly and expect []; instead pass the
         ;; normalizer-produced value.  We normalise first, then render.
         (tmp (make-temp-file "render-tags-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert ":PROPERTIES:\n:ID: e1\n:END:\n#+title: T\n"))
          (let* ((raw '((title . "T") (date . "2026-04-12")))
                 (normalized (a3madkour-pub-frontmatter/normalize 'essays raw tmp))
                 (rendered (a3madkour-pub-essays--render-frontmatter normalized)))
            ;; tags line must be the array form.
            (should (string-match-p "^tags: \\[\\]$" rendered))
            ;; draft line must still be false (nil bool field untouched).
            (should (string-match-p "^draft: false$" rendered))
            ;; has_* fields must still be false.
            (should (string-match-p "^has_sidenotes: false$" rendered))))
      (delete-file tmp))))

;; -- B.4 spot-check fix-up: per-essay asset directory copy --

(ert-deftest a3madkour-pub-essays-test/copy-asset-dir-copies-when-source-exists ()
  "Per-essay asset dir at essays-dir/assets/<id>/ → copied into bundle."
  (let* ((tmp-essays-root (make-temp-file "essays-asset-src-" t))
         (tmp-bundle (make-temp-file "essays-bundle-" t))
         (assets-src (expand-file-name "assets/test-uuid/" tmp-essays-root))
         (hero (expand-file-name "hero.svg" assets-src))
         (other (expand-file-name "fig.svg" assets-src)))
    (unwind-protect
        (let ((a3madkour-pub/essays-dir (file-name-as-directory tmp-essays-root)))
          (make-directory assets-src t)
          (with-temp-file hero (insert "<svg/>"))
          (with-temp-file other (insert "<svg/>"))
          (a3madkour-pub-essays--copy-asset-dir "test-uuid" tmp-bundle)
          (should (file-exists-p (expand-file-name "hero.svg" tmp-bundle)))
          (should (file-exists-p (expand-file-name "fig.svg" tmp-bundle))))
      (delete-directory tmp-essays-root t)
      (delete-directory tmp-bundle t))))

(ert-deftest a3madkour-pub-essays-test/copy-asset-dir-no-op-when-source-absent ()
  "No asset dir for id → silent no-op (returns nil, does nothing)."
  (let ((tmp-essays-root (make-temp-file "essays-asset-src-" t))
        (tmp-bundle (make-temp-file "essays-bundle-" t)))
    (unwind-protect
        (let ((a3madkour-pub/essays-dir (file-name-as-directory tmp-essays-root)))
          (should-not (a3madkour-pub-essays--copy-asset-dir "nonexistent-uuid"
                                                            tmp-bundle))
          (should (equal '("." "..")
                         (directory-files tmp-bundle))))
      (delete-directory tmp-essays-root t)
      (delete-directory tmp-bundle t))))

;; -- D.1: ox-hugo paired-shortcodes for AMS blocks --

(ert-deftest a3madkour-pub-essays-test/special-block-round-trip ()
  "An org `#+begin_theorem' block with `#+attr_shortcode: :title Foo :id thm-foo'
must emit as a paired Hugo shortcode `{{< theorem title=\"Foo\" id=\"thm-foo\" >}}
... {{< /theorem >}}' in the post-export markdown body."
  (require 'a3madkour-publish-export)
  (let* ((tmp (make-temp-file "essays-special-block-" nil ".org"))
         (body (concat "#+title: T\n"
                       "#+date: <2026-06-01>\n"
                       "\n"
                       "#+attr_shortcode: :title Foo :id thm-foo\n"
                       "#+begin_theorem\n"
                       "Body content.\n"
                       "#+end_theorem\n")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert body))
          (let* ((result (a3madkour-pub-export/export-file tmp))
                 (md     (plist-get result :body)))
            (should (string-match-p "{{< theorem title=\"Foo\" id=\"thm-foo\" >}}" md))
            (should (string-match-p "{{< /theorem >}}" md))))
      (delete-file tmp))))

;;; B publisher threads id into asset-validate-and-copy.

(ert-deftest a3madkour-pub-essays-test/publisher-threads-id-to-asset-validate ()
  "publish-essay-file passes the note's :id as source-note-id to asset-validate-and-copy."
  (let ((captured-id 'unset)
        (tmp-src (make-temp-file "essays-threads-id-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp-src (insert "#+title: T\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
                     (lambda (_f)
                       (list :id "essay-id-99" :slug "test-essay" :section "essays"
                             :state 'live :title "T")))
                    ((symbol-function 'a3madkour-pub/note-url)
                     (lambda (_f) "/essays/test-essay/"))
                    ((symbol-function 'a3madkour-pub-essays--site-root)
                     (lambda () "/tmp/site-stub/"))
                    ((symbol-function 'a3madkour-pub-rewrite/rewrite-to-tmp-file)
                     (lambda (file _id _tag)
                       ;; Return a distinct temp copy so the unwind-protect
                       ;; delete-file in the exporter doesn't remove file itself.
                       (let ((copy (make-temp-file "essays-rewrite-stub-" nil ".org")))
                         (copy-file file copy t)
                         copy)))
                    ((symbol-function 'a3madkour-pub-export/export-file)
                     (lambda (_f) (list :body "stub-body" :frontmatter nil)))
                    ((symbol-function 'a3madkour-pub-essays--scan-has-flags)
                     (lambda (_b) nil))
                    ((symbol-function 'a3madkour-pub-frontmatter/normalize)
                     (lambda (_section raw _f) raw))
                    ((symbol-function 'a3madkour-pub/asset-validate-and-copy)
                     (lambda (_org _bundle &optional source-note-id &rest _)
                       (setq captured-id source-note-id)
                       (list :copied nil :removed nil :warnings nil :errors nil)))
                    ((symbol-function 'a3madkour-pub-essays--copy-asset-dir)
                     (lambda (_id _b) nil))
                    ((symbol-function 'a3madkour-pub-essays--write-if-different)
                     (lambda (_p _c) nil))
                    ((symbol-function 'a3madkour-pub-essays--render-frontmatter)
                     (lambda (_n) ""))
                    ((symbol-function 'a3madkour-pub-history/record-publish)
                     (lambda (_id _url _state) nil)))
            (a3madkour-pub-essays/publish-essay-file tmp-src)
            (should (equal captured-id "essay-id-99"))))
      (when (file-exists-p tmp-src) (delete-file tmp-src)))))

;;; End-to-end: [[file:asset.svg]] round-trip through publish-essay-file.

(ert-deftest a3madkour-pub-essays-test/figure-ref-round-trip ()
  "Real publish: [[file:fig.svg]] lands as <img> in index.md; svg copied to bundle."
  (let* ((tmp (file-name-as-directory
               (make-temp-file "a3-figure-roundtrip-" t)))
         (essays-dir (file-name-as-directory (expand-file-name "essays/" tmp)))
         (id "deadbeef-1234-5678-9abc-def012345678")
         (slug "test-figure-essay")
         (org-file (expand-file-name (concat slug ".org") essays-dir))
         (asset-dir (file-name-as-directory
                     (expand-file-name (format "assets/%s/" id) essays-dir)))
         (asset (expand-file-name "fig.svg" asset-dir))
         (site-root (file-name-as-directory (expand-file-name "site/" tmp)))
         (bundle-dir (file-name-as-directory
                      (expand-file-name (format "content/essays/%s/" slug)
                                        site-root))))
    (unwind-protect
        (progn
          (make-directory asset-dir t)
          (make-directory bundle-dir t)
          (with-temp-file asset (insert "<svg/>"))
          (with-temp-file org-file
            (insert (format ":PROPERTIES:
:ID:       %s
:END:
#+title: Test figure essay
#+date: 2026-06-05
#+hugo_publish: t
#+hugo_section: essays
#+hugo_slug: %s

Body text.

[[file:fig.svg]]
"
                            id slug)))
          (cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
                     (lambda (_f)
                       (list :id id :slug slug :section "essays"
                             :state 'live :title "Test figure essay")))
                    ((symbol-function 'a3madkour-pub/note-url)
                     (lambda (_f) (format "/essays/%s/" slug)))
                    ((symbol-function 'a3madkour-pub-essays--site-root)
                     (lambda () site-root))
                    ((symbol-function 'a3madkour-pub--id-to-file)
                     (lambda (i) (if (equal i id) org-file nil)))
                    ((symbol-function 'a3madkour-pub/note-slug)
                     (lambda (_f) slug))
                    ((symbol-function 'a3madkour-pub-citations/rewrite-cite-keys-in-buffer)
                     (lambda (_f) nil))
                    ((symbol-function 'a3madkour-pub-export/export-file)
                     (lambda (tmp-src)
                       ;; Simulate ox-hugo: read the pre-export-rewritten file
                       ;; and convert @@html:...@@ export snippets to raw HTML.
                       (let ((body (with-temp-buffer
                                     (insert-file-contents tmp-src)
                                     (buffer-string))))
                         (list :body
                               (replace-regexp-in-string
                                "@@html:\\(.*?\\)@@" "\\1" body)
                               :frontmatter nil))))
                    ((symbol-function 'a3madkour-pub-frontmatter/normalize)
                     (lambda (_section raw _f) raw))
                    ((symbol-function 'a3madkour-pub-essays--render-frontmatter)
                     (lambda (_n) ""))
                    ((symbol-function 'a3madkour-pub-essays--copy-asset-dir)
                     (lambda (_id _b) nil))
                    ((symbol-function 'a3madkour-pub-history/record-publish)
                     (lambda (_id _url _state) nil)))
            (let ((a3madkour-pub/essays-dir essays-dir))
              (a3madkour-pub-essays/publish-essay-file org-file)))
          (let* ((index-path (expand-file-name "index.md" bundle-dir))
                 (svg-path (expand-file-name "fig.svg" bundle-dir))
                 (index-body
                  (when (file-exists-p index-path)
                    (with-temp-buffer
                      (insert-file-contents index-path)
                      (buffer-string)))))
            (should (file-exists-p index-path))
            (should (file-exists-p svg-path))
            (should (string-match-p "<img " index-body))
            (should (string-match-p "fig\\.svg" index-body))))
      (delete-directory tmp t))))

(provide 'a3madkour-publish-essays-test)

;;; a3madkour-publish-essays-test.el ends here
