;;; a3madkour-publish-assets-test.el --- ert tests for a3madkour-publish-assets -*- lexical-binding: t; -*-

;;; Commentary:

;; ert tests for A.1.c asset handling.  Run via run-tests.sh.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-assets)

;; -- --asset-resolve-path: classification --

(defmacro a3-pub-assets-test--with-tmp-root (root-var &rest body)
  "Bind ROOT-VAR to a fresh tmpdir; cleanup after BODY."
  (declare (indent 1))
  `(let ((,root-var (make-temp-file "a3-pub-assets-" t)))
     (unwind-protect (progn ,@body)
       (delete-directory ,root-var t))))

(ert-deftest a3madkour-pub-assets-test/resolve-page-kind ()
  "Path under <root>/page/<slug>/ classifies as :kind page."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      (with-temp-file (expand-file-name "page/foo/x.png" root) (insert "data"))
      (let ((result (a3madkour-pub--asset-resolve-path
                     (expand-file-name "page/foo/x.png" root)
                     nil)))
        (should (eq (plist-get result :kind) 'page))
        (should (string-suffix-p "page/foo/x.png" (plist-get result :abs-path)))))))

(ert-deftest a3madkour-pub-assets-test/resolve-shared-kind ()
  "Path under <root>/shared/ classifies as :kind shared."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "shared" root) t)
      (with-temp-file (expand-file-name "shared/y.svg" root) (insert "<svg/>"))
      (let ((result (a3madkour-pub--asset-resolve-path
                     (expand-file-name "shared/y.svg" root)
                     nil)))
        (should (eq (plist-get result :kind) 'shared))))))

(ert-deftest a3madkour-pub-assets-test/resolve-out-of-root-kind ()
  "Path outside canonical root classifies as :kind out-of-root."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root)
          (other (make-temp-file "a3-pub-other-" nil ".png")))
      (unwind-protect
          (progn
            (with-temp-file other (insert "data"))
            (let ((result (a3madkour-pub--asset-resolve-path other nil)))
              (should (eq (plist-get result :kind) 'out-of-root))))
        (delete-file other)))))

(ert-deftest a3madkour-pub-assets-test/resolve-missing-kind ()
  "Non-existent file classifies as :kind missing (regardless of location)."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      ;; Note: no file created.
      (let ((result (a3madkour-pub--asset-resolve-path
                     (expand-file-name "page/foo/missing.png" root)
                     nil)))
        (should (eq (plist-get result :kind) 'missing))))))

(ert-deftest a3madkour-pub-assets-test/resolve-relative-against-source-dir ()
  "Relative path resolves against the source file's directory."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (source-dir (expand-file-name "notes/sub/" root)))
      (make-directory source-dir t)
      (make-directory (expand-file-name "page/foo" root) t)
      (with-temp-file (expand-file-name "page/foo/x.png" root) (insert "d"))
      ;; Relative path from source-dir reaching into canonical root:
      (let ((result (a3madkour-pub--asset-resolve-path
                     (concat source-dir "../../page/foo/x.png")
                     nil)))
        (should (eq (plist-get result :kind) 'page))
        (should (file-exists-p (plist-get result :abs-path)))))))

(ert-deftest a3madkour-pub-assets-test/resolve-tilde-expansion ()
  "~/path expands to home; works for canonical-root references."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      ;; Even with tilde, expand-file-name handles it; here we just verify
      ;; that an already-absolute home-relative input doesn't double-expand.
      (let ((result (a3madkour-pub--asset-resolve-path
                     "~/nonexistent.png" nil)))
        (should (eq (plist-get result :kind) 'missing))))))

;; -- --asset-cross-namespace-p --

(ert-deftest a3madkour-pub-assets-test/cross-ns-own-slug-matches ()
  "page/<slug>/foo where slug == source-slug → NOT cross-namespace."
  (let ((resolved (list :kind 'page
                        :abs-path "/tmp/root/page/foo/x.png"
                        :rel-path "page/foo/x.png")))
    (should-not (a3madkour-pub--asset-cross-namespace-p resolved "foo"))))

(ert-deftest a3madkour-pub-assets-test/cross-ns-own-slug-differs ()
  "page/<slug>/foo where slug != source-slug → cross-namespace."
  (let ((resolved (list :kind 'page
                        :abs-path "/tmp/root/page/foo/x.png"
                        :rel-path "page/foo/x.png")))
    (should (a3madkour-pub--asset-cross-namespace-p resolved "bar"))))

(ert-deftest a3madkour-pub-assets-test/cross-ns-shared-never-fires ()
  "shared/ assets are never cross-namespace (no slug component)."
  (let ((resolved (list :kind 'shared
                        :abs-path "/tmp/root/shared/y.svg"
                        :rel-path "shared/y.svg")))
    (should-not (a3madkour-pub--asset-cross-namespace-p resolved "anything"))))

(ert-deftest a3madkour-pub-assets-test/cross-ns-out-of-root-never-fires ()
  "out-of-root assets are not cross-namespace (different concern)."
  (let ((resolved (list :kind 'out-of-root
                        :abs-path "/some/other/path/x.png"
                        :rel-path nil)))
    (should-not (a3madkour-pub--asset-cross-namespace-p resolved "anything"))))

;; -- --asset-bundle-dest --

(ert-deftest a3madkour-pub-assets-test/bundle-dest-page ()
  "page-kind asset destination = BUNDLE-DIR/<filename>."
  (let ((resolved (list :kind 'page
                        :abs-path "/root/page/foo/x.png"
                        :rel-path "page/foo/x.png")))
    (should (equal (a3madkour-pub--asset-bundle-dest resolved "/site/content/garden/foo/")
                   "/site/content/garden/foo/x.png"))))

(ert-deftest a3madkour-pub-assets-test/bundle-dest-shared ()
  "shared-kind asset destination = <static-notes-shared-dir>/<filename>."
  (let ((a3madkour-pub-notes-shared-static-dir "/site/static/notes-shared")
        (resolved (list :kind 'shared
                        :abs-path "/root/shared/y.svg"
                        :rel-path "shared/y.svg")))
    (should (equal (a3madkour-pub--asset-bundle-dest resolved "/site/content/garden/foo/")
                   "/site/static/notes-shared/y.svg"))))

(ert-deftest a3madkour-pub-assets-test/bundle-dest-shared-requires-dir ()
  "shared-kind without notes-shared-static-dir set → error."
  (let ((a3madkour-pub-notes-shared-static-dir nil)
        (resolved (list :kind 'shared
                        :abs-path "/root/shared/y.svg"
                        :rel-path "shared/y.svg")))
    (should-error (a3madkour-pub--asset-bundle-dest resolved "/site/content/garden/foo/"))))

;; -- --asset-emit-html --

(ert-deftest a3madkour-pub-assets-test/emit-image-with-display ()
  "Image extension → <img src alt> with display as alt."
  (should (equal (a3madkour-pub--asset-emit-html "x.png" "My screenshot" 'image)
                 "<img src=\"x.png\" alt=\"My screenshot\" />")))

(ert-deftest a3madkour-pub-assets-test/emit-non-image-with-display ()
  "Non-image extension → <a href>text</a>."
  (should (equal (a3madkour-pub--asset-emit-html "manual.pdf" "Read the manual" 'other)
                 "<a href=\"manual.pdf\">Read the manual</a>")))

(ert-deftest a3madkour-pub-assets-test/emit-shared-img-src ()
  "Shared assets get /notes-shared/ src prefix from caller."
  (should (equal (a3madkour-pub--asset-emit-html "/notes-shared/diagram.svg" "diagram" 'image)
                 "<img src=\"/notes-shared/diagram.svg\" alt=\"diagram\" />")))

(ert-deftest a3madkour-pub-assets-test/emit-display-text-escaped ()
  "Display text containing < > & escapes properly in both <img alt> and <a>."
  (should (equal (a3madkour-pub--asset-emit-html "x.png" "a < b & c" 'image)
                 "<img src=\"x.png\" alt=\"a &lt; b &amp; c\" />"))
  (should (equal (a3madkour-pub--asset-emit-html "x.pdf" "a < b & c" 'other)
                 "<a href=\"x.pdf\">a &lt; b &amp; c</a>")))

(ert-deftest a3madkour-pub-assets-test/emit-src-with-quote-escaped ()
  "src containing \" gets &quot;."
  (should (equal (a3madkour-pub--asset-emit-html "odd\"name.png" "alt" 'image)
                 "<img src=\"odd&quot;name.png\" alt=\"alt\" />")))

(ert-deftest a3madkour-pub-assets-test/emit-inert-missing-asset ()
  "(missing asset: NAME) inert marker for failed cases."
  (should (equal (a3madkour-pub--asset-emit-inert "x.png")
                 "(missing asset: x.png)"))
  ;; Filename with special chars gets escaped.
  (should (equal (a3madkour-pub--asset-emit-inert "<x>.png")
                 "(missing asset: &lt;x&gt;.png)")))

;; -- --asset-content-hash --

(ert-deftest a3madkour-pub-assets-test/content-hash-deterministic ()
  "Same content → same 6-char hash."
  (let ((tmp (make-temp-file "a3-pub-hash-")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert "hello"))
          (let ((h1 (a3madkour-pub--asset-content-hash tmp))
                (h2 (a3madkour-pub--asset-content-hash tmp)))
            (should (= 6 (length h1)))
            (should (string-match-p "\\`[0-9a-f]\\{6\\}\\'" h1))
            (should (equal h1 h2))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-assets-test/content-hash-differs-by-content ()
  "Different content → different hash."
  (let ((a (make-temp-file "a3-pub-hash-a-"))
        (b (make-temp-file "a3-pub-hash-b-")))
    (unwind-protect
        (progn
          (with-temp-file a (insert "hello"))
          (with-temp-file b (insert "world"))
          (should-not (equal (a3madkour-pub--asset-content-hash a)
                             (a3madkour-pub--asset-content-hash b))))
      (delete-file a)
      (delete-file b))))

;; -- --asset-remediate-dest: destination computation + collision --

(ert-deftest a3madkour-pub-assets-test/remediate-dest-no-collision ()
  "No collision → dest = <root>/page/<src-slug>/<filename>."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root)
          (src (make-temp-file "a3-pub-src-" nil ".png" "data")))
      (unwind-protect
          (let ((dest (a3madkour-pub--asset-remediate-dest src "foo")))
            (should (string-suffix-p "page/foo/" (file-name-directory dest)))
            (should (equal (file-name-nondirectory dest)
                           (file-name-nondirectory src))))
        (delete-file src)))))

(ert-deftest a3madkour-pub-assets-test/remediate-dest-collision-same-content ()
  "Destination exists with byte-equal content → return dest unchanged (no suffix)."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      ;; Pre-existing dest with same content.
      (with-temp-file (expand-file-name "page/foo/clash.png" root) (insert "same"))
      (let ((src (make-temp-file "a3-pub-src-" nil ".png" "same")))
        (unwind-protect
            ;; Rename src to match the dest basename for the test fixture:
            (let* ((renamed (expand-file-name "clash.png" (file-name-directory src))))
              (rename-file src renamed)
              (let ((dest (a3madkour-pub--asset-remediate-dest renamed "foo")))
                (should (equal (file-name-nondirectory dest) "clash.png"))
                (should-not (string-match-p "-[0-9a-f]\\{6\\}\\." dest))
                (delete-file renamed)))
          (when (file-exists-p src) (delete-file src)))))))

(ert-deftest a3madkour-pub-assets-test/remediate-dest-collision-different-content ()
  "Destination exists with different content → suffix with content hash."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      ;; Pre-existing dest with DIFFERENT content.
      (with-temp-file (expand-file-name "page/foo/clash.png" root) (insert "old"))
      (let ((src (make-temp-file "a3-pub-src-" nil ".png" "new")))
        (unwind-protect
            (let* ((renamed (expand-file-name "clash.png" (file-name-directory src))))
              (rename-file src renamed)
              (let ((dest (a3madkour-pub--asset-remediate-dest renamed "foo")))
                (should (string-match-p "/clash-[0-9a-f]\\{6\\}\\.png\\'" dest))
                (delete-file renamed)))
          (when (file-exists-p src) (delete-file src)))))))

;; -- --asset-do-move --

(ert-deftest a3madkour-pub-assets-test/do-move-plain-mv ()
  "Non-git-tracked source uses plain `rename-file' (mv)."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (src (make-temp-file "a3-pub-mvsrc-" nil ".png" "data"))
           (dest (expand-file-name "page/foo/moved.png" root)))
      (make-directory (file-name-directory dest) t)
      (unwind-protect
          ;; Force mv branch by stubbing vc-backend.
          (cl-letf (((symbol-function 'vc-backend) (lambda (_) nil)))
            (let ((result (a3madkour-pub--asset-do-move src dest nil)))
              (should (eq (plist-get result :method) 'mv))
              (should (file-exists-p dest))
              (should-not (file-exists-p src))))
        (when (file-exists-p src) (delete-file src))
        (when (file-exists-p dest) (delete-file dest))))))

(ert-deftest a3madkour-pub-assets-test/do-move-git-mv-branch ()
  "Git-tracked source uses `git mv'."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (src (make-temp-file "a3-pub-gitmvsrc-" nil ".png" "data"))
           (dest (expand-file-name "page/foo/gitmoved.png" root))
           (git-mv-called nil))
      (make-directory (file-name-directory dest) t)
      (unwind-protect
          (cl-letf (((symbol-function 'vc-backend) (lambda (_) 'Git))
                    ((symbol-function 'call-process)
                     (lambda (prog _ _ _ &rest args)
                       (when (and (equal prog "git") (equal (car args) "mv"))
                         (setq git-mv-called t)
                         (rename-file (cadr args) (caddr args)))
                       0)))
            (let ((result (a3madkour-pub--asset-do-move src dest nil)))
              (should (eq (plist-get result :method) 'git-mv))
              (should git-mv-called)
              (should (file-exists-p dest))))
        (when (file-exists-p src) (delete-file src))
        (when (file-exists-p dest) (delete-file dest))))))

(ert-deftest a3madkour-pub-assets-test/do-move-dry-run-no-side-effects ()
  "Dry-run reports the move without performing it."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (src (make-temp-file "a3-pub-drysrc-" nil ".png" "data"))
           (dest (expand-file-name "page/foo/dry.png" root)))
      (make-directory (file-name-directory dest) t)
      (unwind-protect
          (let ((result (a3madkour-pub--asset-do-move src dest t)))
            (should (eq (plist-get result :method) 'dry-run))
            (should (file-exists-p src))           ; source still present
            (should-not (file-exists-p dest))      ; dest not created
            (should (string-match-p "would move" (plist-get result :info))))
        (when (file-exists-p src) (delete-file src))))))

;; -- --asset-rewrite-source-link --

(ert-deftest a3madkour-pub-assets-test/rewrite-source-link-basic ()
  "Find OLD link form in org buffer, replace with NEW."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((org-file (expand-file-name "note.org" root))
           (old "[[/home/u/Downloads/x.png]]")
           (new "[[./assets/page/foo/x.png]]"))
      (with-temp-file org-file
        (insert "Some text.\nHere is " old " in the doc.\n"))
      (a3madkour-pub--asset-rewrite-source-link org-file old new)
      (with-temp-buffer
        (insert-file-contents org-file)
        (should-not (search-forward old nil t))
        (goto-char (point-min))
        (should (search-forward new nil t))))))

(ert-deftest a3madkour-pub-assets-test/rewrite-source-link-with-display-text ()
  "[[OLD-PATH][TEXT]] gets path rewritten; text preserved."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((org-file (expand-file-name "note.org" root))
           (old "[[/home/u/x.png][My pic]]")
           (new "[[./assets/page/foo/x.png][My pic]]"))
      (with-temp-file org-file (insert "Doc with " old "."))
      (a3madkour-pub--asset-rewrite-source-link org-file old new)
      (with-temp-buffer
        (insert-file-contents org-file)
        (should (search-forward new nil t))))))

(ert-deftest a3madkour-pub-assets-test/rewrite-source-link-multiple-occurrences ()
  "All occurrences of OLD get rewritten."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((org-file (expand-file-name "note.org" root))
           (old "[[/x.png]]")
           (new "[[./y.png]]"))
      (with-temp-file org-file
        (insert old "\nmid\n" old "\nend\n" old))
      (a3madkour-pub--asset-rewrite-source-link org-file old new)
      (with-temp-buffer
        (insert-file-contents org-file)
        (let ((count 0))
          (while (search-forward new nil t) (cl-incf count))
          (should (= 3 count)))))))

;; -- rewrite-asset-link: full dispatch --

(ert-deftest a3madkour-pub-assets-test/rewrite-asset-page-image ()
  "Per-page image asset → :html <img> + :resolved-path + :kind image."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      (with-temp-file (expand-file-name "page/foo/x.png" root) (insert "data"))
      (cl-letf (((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
        (let ((result (a3madkour-pub/rewrite-asset-link
                       (expand-file-name "page/foo/x.png" root)
                       "My screenshot"
                       "source-id")))
          (should (equal (plist-get result :html)
                         "<img src=\"x.png\" alt=\"My screenshot\" />"))
          (should (equal (plist-get result :resolved-path) "x.png"))
          (should (eq (plist-get result :kind) 'image))
          (should-not (plist-get result :warnings)))))))

(ert-deftest a3madkour-pub-assets-test/rewrite-asset-shared-image ()
  "Shared image asset → :html <img src=/notes-shared/...>."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root)
          (a3madkour-pub-notes-shared-static-dir "/site/static/notes-shared"))
      (make-directory (expand-file-name "shared" root) t)
      (with-temp-file (expand-file-name "shared/y.svg" root) (insert "<svg/>"))
      (cl-letf (((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
        (let ((result (a3madkour-pub/rewrite-asset-link
                       (expand-file-name "shared/y.svg" root)
                       "diagram"
                       "source-id")))
          (should (string-match-p "/notes-shared/y.svg" (plist-get result :html)))
          (should (equal (plist-get result :resolved-path) "/notes-shared/y.svg")))))))

(ert-deftest a3madkour-pub-assets-test/rewrite-asset-non-image ()
  "PDF (non-image) asset → :html <a href> + :kind other."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      (with-temp-file (expand-file-name "page/foo/manual.pdf" root) (insert "pdf"))
      (cl-letf (((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
        (let ((result (a3madkour-pub/rewrite-asset-link
                       (expand-file-name "page/foo/manual.pdf" root)
                       "Read the manual"
                       "source-id")))
          (should (string-match-p "<a href=\"manual.pdf\">" (plist-get result :html)))
          (should (eq (plist-get result :kind) 'other)))))))

(ert-deftest a3madkour-pub-assets-test/rewrite-asset-cross-namespace ()
  "page-namespace mismatch → :inert (missing asset: ...) + WARN."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      (with-temp-file (expand-file-name "page/foo/x.png" root) (insert "d"))
      ;; Source slug is "bar" but link points at page/foo/x.png:
      (cl-letf (((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "bar")))
        (let ((result (a3madkour-pub/rewrite-asset-link
                       (expand-file-name "page/foo/x.png" root)
                       "screenshot"
                       "source-id")))
          (should (string-match-p "missing asset:" (plist-get result :inert)))
          (should (= 1 (length (plist-get result :warnings))))
          (should (string-match-p "cross.*namespace\\|move to shared"
                                   (car (plist-get result :warnings)))))))))

(ert-deftest a3madkour-pub-assets-test/rewrite-asset-missing ()
  "Non-existent file → :inert + WARN."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      (cl-letf (((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
        (let ((result (a3madkour-pub/rewrite-asset-link
                       (expand-file-name "page/foo/missing.png" root)
                       "x"
                       "source-id")))
          (should (plist-get result :inert))
          (should (= 1 (length (plist-get result :warnings))))
          (should (string-match-p "does not exist\\|missing"
                                   (car (plist-get result :warnings)))))))))

(ert-deftest a3madkour-pub-assets-test/rewrite-asset-no-display-text ()
  "When text equals path (no display text), use filename basename as alt/body."
  (a3-pub-assets-test--with-tmp-root root
    (let ((a3madkour-pub-canonical-asset-root root))
      (make-directory (expand-file-name "page/foo" root) t)
      (with-temp-file (expand-file-name "page/foo/x.png" root) (insert "d"))
      (cl-letf (((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
        (let* ((path (expand-file-name "page/foo/x.png" root))
               ;; Pass text == path to simulate org's [[path]] no-display form:
               (result (a3madkour-pub/rewrite-asset-link path path "source-id")))
          (should (string-match-p "alt=\"x.png\"" (plist-get result :html))))))))

;; -- rewrite-asset-link: auto-remediation integration --

(ert-deftest a3madkour-pub-assets-test/remediate-moves-and-rewrites-link ()
  "Out-of-root asset (default auto-remediate=t) → moved + source rewritten."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (a3madkour-pub-asset-auto-remediate t)
           (source-org (expand-file-name "note.org" root))
           (src-asset (make-temp-file "a3-pub-oor-" nil ".png" "data")))
      (with-temp-file source-org
        (insert "Doc with [[" src-asset "]] in it."))
      (unwind-protect
          (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                     (lambda (_) source-org))
                    ((symbol-function 'a3madkour-pub/note-slug)
                     (lambda (_) "foo"))
                    ((symbol-function 'vc-backend) (lambda (_) nil)))
            (let ((result (a3madkour-pub/rewrite-asset-link
                           src-asset "alt" "source-id")))
              (should (plist-get result :html))
              ;; Source asset moved into canonical root:
              (should-not (file-exists-p src-asset))
              (should (file-exists-p
                       (expand-file-name
                        (format "page/foo/%s" (file-name-nondirectory src-asset))
                        root)))
              ;; .org source link rewritten:
              (with-temp-buffer
                (insert-file-contents source-org)
                (should-not (search-forward (format "[[%s]]" src-asset) nil t))
                (goto-char (point-min))
                ;; Note: in this test, canonical-asset-root = <root> (the tmpdir directly,
                ;; with no /assets subdir).  In production it's ~/org/notes/assets/, so the
                ;; relative path written into the .org source would be ./assets/page/foo/...
                ;; — here it's ./page/foo/... because the tmpdir is its own canonical root.
                (should (search-forward "[[./page/foo/" nil t)))))
        (when (file-exists-p src-asset) (delete-file src-asset))))))

(ert-deftest a3madkour-pub-assets-test/remediate-disabled-emits-inert ()
  "When auto-remediate=nil, out-of-root → inert + WARN, no move."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (a3madkour-pub-asset-auto-remediate nil)
           (src-asset (make-temp-file "a3-pub-noremed-" nil ".png" "data")))
      (unwind-protect
          (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                     (lambda (_) nil))
                    ((symbol-function 'a3madkour-pub/note-slug)
                     (lambda (_) "foo")))
            (let ((result (a3madkour-pub/rewrite-asset-link
                           src-asset "alt" "source-id")))
              (should (plist-get result :inert))
              (should (file-exists-p src-asset))))         ; not moved
        (when (file-exists-p src-asset) (delete-file src-asset))))))

(ert-deftest a3madkour-pub-assets-test/remediate-dry-run-no-side-effects ()
  "DRY-RUN suppresses both the move and the source rewrite."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (a3madkour-pub-asset-auto-remediate t)
           (source-org (expand-file-name "note.org" root))
           (src-asset (make-temp-file "a3-pub-dryoor-" nil ".png" "data")))
      (with-temp-file source-org
        (insert "Doc with [[" src-asset "]]"))
      (unwind-protect
          (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                     (lambda (_) source-org))
                    ((symbol-function 'a3madkour-pub/note-slug)
                     (lambda (_) "foo")))
            (let ((result (a3madkour-pub/rewrite-asset-link
                           src-asset "alt" "source-id" t)))   ; dry-run = t
              ;; Source still in place, .org source NOT rewritten:
              (should (file-exists-p src-asset))
              (with-temp-buffer
                (insert-file-contents source-org)
                (should (search-forward (format "[[%s]]" src-asset) nil t)))
              ;; Result reports dry-run (no html or inert; deferred)
              (should (cl-find "would move" (plist-get result :warnings)
                                :test (lambda (n s) (string-match-p n s))))))
        (when (file-exists-p src-asset) (delete-file src-asset))))))

;; -- --extract-asset-refs --

(ert-deftest a3madkour-pub-assets-test/extract-refs-finds-relative-and-absolute ()
  "Extracts all asset-shaped links from an org file."
  (a3-pub-assets-test--with-tmp-root root
    (let ((org-file (expand-file-name "note.org" root)))
      (with-temp-file org-file
        (insert "Hello\n"
                "[[./assets/page/foo/x.png]]\n"
                "[[/abs/path/y.svg][caption]]\n"
                "[[id:UUID-here][some link]]\n"          ; id link, should NOT match
                "[[~/org/notes/assets/shared/z.pdf]]\n"
                "[[https://example.com][external]]\n"))  ; external, should NOT match
      (let ((refs (a3madkour-pub--extract-asset-refs org-file)))
        (should (= 3 (length refs)))
        (should (cl-some (lambda (ref)
                           (string-match-p "x\\.png" (car ref)))
                         refs))
        (should (cl-some (lambda (ref)
                           (and (string-match-p "y\\.svg" (car ref))
                                (equal (cdr ref) "caption")))
                         refs))
        (should (cl-some (lambda (ref)
                           (string-match-p "z\\.pdf" (car ref)))
                         refs))))))

(ert-deftest a3madkour-pub-assets-test/extract-refs-empty-file ()
  "Empty org file → empty refs list."
  (a3-pub-assets-test--with-tmp-root root
    (let ((org-file (expand-file-name "empty.org" root)))
      (with-temp-file org-file (insert ""))
      (should-not (a3madkour-pub--extract-asset-refs org-file)))))

(ert-deftest a3madkour-pub-assets-test/extract-refs-no-display-text ()
  "[[path]] form sets text equal to path."
  (a3-pub-assets-test--with-tmp-root root
    (let ((org-file (expand-file-name "note.org" root)))
      (with-temp-file org-file (insert "[[./x.png]]"))
      (let ((refs (a3madkour-pub--extract-asset-refs org-file)))
        (should (= 1 (length refs)))
        (should (equal (caar refs) (cdar refs)))))))

(ert-deftest a3madkour-pub-assets-test/extract-refs-no-asset-shaped ()
  "File with only id and external links → empty refs."
  (a3-pub-assets-test--with-tmp-root root
    (let ((org-file (expand-file-name "note.org" root)))
      (with-temp-file org-file
        (insert "[[id:UUID][x]] [[https://example.com][y]] [[file:foo.org][z]]"))
      (should-not (a3madkour-pub--extract-asset-refs org-file)))))

;; -- --asset-cleanup-stale --

(ert-deftest a3madkour-pub-assets-test/cleanup-removes-orphan ()
  "Bundle file not in ref set + not index.md → removed."
  (a3-pub-assets-test--with-tmp-root bundle
    (with-temp-file (expand-file-name "index.md" bundle) (insert "..."))
    (with-temp-file (expand-file-name "kept.png" bundle) (insert "k"))
    (with-temp-file (expand-file-name "stale.png" bundle) (insert "s"))
    (let ((removed (a3madkour-pub--asset-cleanup-stale bundle '("kept.png"))))
      (should (member (expand-file-name "stale.png" bundle) removed))
      (should-not (file-exists-p (expand-file-name "stale.png" bundle)))
      (should (file-exists-p (expand-file-name "kept.png" bundle))))))

(ert-deftest a3madkour-pub-assets-test/cleanup-preserves-index-md ()
  "index.md is always preserved even if not in ref set."
  (a3-pub-assets-test--with-tmp-root bundle
    (with-temp-file (expand-file-name "index.md" bundle) (insert "..."))
    (a3madkour-pub--asset-cleanup-stale bundle '())
    (should (file-exists-p (expand-file-name "index.md" bundle)))))

(ert-deftest a3madkour-pub-assets-test/cleanup-preserves-language-variants ()
  "index.en.md / _index.md preserved."
  (a3-pub-assets-test--with-tmp-root bundle
    (with-temp-file (expand-file-name "index.md" bundle) (insert "."))
    (with-temp-file (expand-file-name "index.en.md" bundle) (insert "."))
    (with-temp-file (expand-file-name "_index.md" bundle) (insert "."))
    (a3madkour-pub--asset-cleanup-stale bundle '())
    (should (file-exists-p (expand-file-name "index.en.md" bundle)))
    (should (file-exists-p (expand-file-name "_index.md" bundle)))))

(ert-deftest a3madkour-pub-assets-test/cleanup-skips-dotfiles ()
  ".publish-state, .DS_Store, etc. preserved (not in ref set; not removed)."
  (a3-pub-assets-test--with-tmp-root bundle
    (with-temp-file (expand-file-name ".publish-state" bundle) (insert "."))
    (with-temp-file (expand-file-name "stale.png" bundle) (insert "."))
    (a3madkour-pub--asset-cleanup-stale bundle '())
    (should (file-exists-p (expand-file-name ".publish-state" bundle)))
    (should-not (file-exists-p (expand-file-name "stale.png" bundle)))))

;; -- asset-validate-and-copy --

(ert-deftest a3madkour-pub-assets-test/validate-and-copy-page-assets ()
  "Copies referenced page assets into bundle dir; returns :copied list."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (org-file (expand-file-name "note.org" root))
           (bundle (expand-file-name "bundle" root)))
      (make-directory bundle t)
      (make-directory (expand-file-name "page/foo" root) t)
      (with-temp-file (expand-file-name "page/foo/x.png" root) (insert "d"))
      (with-temp-file org-file (insert "[[./assets/page/foo/x.png]]"))
      (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                 (lambda (_) org-file))
                ((symbol-function 'a3madkour-pub/note-slug)
                 (lambda (_) "foo"))
                ;; published-p needs to be stubbed too for note-url etc:
                ((symbol-function 'a3madkour-pub/published-p)
                 (lambda (_) 'live)))
        (let ((result (a3madkour-pub/asset-validate-and-copy org-file bundle)))
          (should (file-exists-p (expand-file-name "x.png" bundle)))
          (should (member (expand-file-name "x.png" bundle)
                           (plist-get result :copied))))))))

(ert-deftest a3madkour-pub-assets-test/validate-and-copy-shared-asset ()
  "Shared assets copied to notes-shared dir (not bundle)."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (shared-static (expand-file-name "site/static/notes-shared" root))
           (a3madkour-pub-notes-shared-static-dir shared-static)
           (org-file (expand-file-name "note.org" root))
           (bundle (expand-file-name "bundle" root)))
      (make-directory bundle t)
      (make-directory shared-static t)
      (make-directory (expand-file-name "shared" root) t)
      (with-temp-file (expand-file-name "shared/y.svg" root) (insert "<svg/>"))
      (with-temp-file org-file (insert "[[./assets/shared/y.svg]]"))
      (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                 (lambda (_) org-file))
                ((symbol-function 'a3madkour-pub/note-slug)
                 (lambda (_) "foo")))
        (let ((result (a3madkour-pub/asset-validate-and-copy org-file bundle)))
          (should (file-exists-p (expand-file-name "y.svg" shared-static)))
          (should-not (file-exists-p (expand-file-name "y.svg" bundle))))))))

(ert-deftest a3madkour-pub-assets-test/validate-and-copy-removes-stale ()
  "Files in bundle not in current refs (and not index.md) get removed."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (org-file (expand-file-name "note.org" root))
           (bundle (expand-file-name "bundle" root)))
      (make-directory bundle t)
      ;; Pre-existing stale + index.md:
      (with-temp-file (expand-file-name "stale.png" bundle) (insert "old"))
      (with-temp-file (expand-file-name "index.md" bundle) (insert "doc"))
      ;; Current refs: empty org file.
      (with-temp-file org-file (insert "no asset refs"))
      (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                 (lambda (_) org-file))
                ((symbol-function 'a3madkour-pub/note-slug)
                 (lambda (_) "foo")))
        (let ((result (a3madkour-pub/asset-validate-and-copy org-file bundle)))
          (should-not (file-exists-p (expand-file-name "stale.png" bundle)))
          (should (file-exists-p (expand-file-name "index.md" bundle)))
          (should (member (expand-file-name "stale.png" bundle)
                           (plist-get result :removed))))))))

(ert-deftest a3madkour-pub-assets-test/validate-and-copy-aggregates-warnings ()
  "Per-link WARNs surface in :warnings."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (org-file (expand-file-name "note.org" root))
           (bundle (expand-file-name "bundle" root)))
      (make-directory bundle t)
      (with-temp-file org-file
        (insert "[[./assets/page/foo/missing.png]]"))         ; missing source
      (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                 (lambda (_) org-file))
                ((symbol-function 'a3madkour-pub/note-slug)
                 (lambda (_) "foo")))
        (let ((result (a3madkour-pub/asset-validate-and-copy org-file bundle)))
          (should (plist-get result :warnings)))))))

;; -- A.1.d carry-forward #1: --asset-normalize-link-path dedicated unit tests --

(ert-deftest a3madkour-pub-assets-test/normalize-link-path-dot-assets-resolves-canonical ()
  "`./assets/<rest>' resolves against canonical-root, not the org file's dir."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (org-file (expand-file-name "notes/sub/a.org" root))
           (input "./assets/page/foo/x.png"))
      (make-directory (file-name-directory org-file) t)
      (with-temp-file org-file (insert "stub"))
      (let ((normalized (a3madkour-pub--asset-normalize-link-path input org-file)))
        (should (string-prefix-p (expand-file-name root) normalized))
        (should (string-suffix-p "page/foo/x.png" normalized))))))

(ert-deftest a3madkour-pub-assets-test/normalize-link-path-other-relative-resolves-org-dir ()
  "Relative paths NOT starting with `./assets/' resolve against org-file dir."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (org-file (expand-file-name "notes/sub/a.org" root))
           (input "../shared/sibling.png"))
      (make-directory (file-name-directory org-file) t)
      (with-temp-file org-file (insert "stub"))
      (let ((normalized (a3madkour-pub--asset-normalize-link-path input org-file)))
        ;; Should resolve to <root>/notes/shared/sibling.png (org-file dir + ../).
        (should (string-suffix-p "notes/shared/sibling.png" normalized))))))

(ert-deftest a3madkour-pub-assets-test/normalize-link-path-absolute-passes-through ()
  "Absolute path is returned as-is (after expand-file-name normalization)."
  (a3-pub-assets-test--with-tmp-root root
    (let* ((a3madkour-pub-canonical-asset-root root)
           (org-file (expand-file-name "notes/a.org" root))
           (input "/tmp/some-external-asset.png"))
      (make-directory (file-name-directory org-file) t)
      (with-temp-file org-file (insert "stub"))
      (let ((normalized (a3madkour-pub--asset-normalize-link-path input org-file)))
        (should (equal normalized "/tmp/some-external-asset.png"))))))

;; -- list-referenced-files (public adapter for D.2) --

(ert-deftest a3madkour-pub-assets-test/list-referenced-files-returns-abs-paths ()
  "Public adapter resolves [[file:NAME]] / [[NAME]] refs to absolute paths."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-pub-assets-list-" t))))
    (unwind-protect
        (let ((org-file (expand-file-name "x.org" tmp))
              (svg (expand-file-name "diagram-1.svg" tmp)))
          (with-temp-file svg (insert "<svg/>"))
          (with-temp-file org-file
            (insert "* H\n[[file:diagram-1.svg]]\n[[diagram-1.svg][caption]]\n"))
          (let ((result (a3madkour-pub-assets/list-referenced-files org-file)))
            (should (= 2 (length result)))
            (should (cl-every #'file-exists-p result))
            (should (cl-every (lambda (p) (string-suffix-p "diagram-1.svg" p))
                              result))))
      (delete-directory tmp t))))

(ert-deftest a3madkour-pub-assets-test/list-referenced-files-skips-missing ()
  "Refs to non-existent files are not included."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-pub-assets-miss-" t))))
    (unwind-protect
        (let ((org-file (expand-file-name "x.org" tmp)))
          (with-temp-file org-file
            (insert "* H\n[[file:does-not-exist.png]]\n"))
          (should (null (a3madkour-pub-assets/list-referenced-files org-file))))
      (delete-directory tmp t))))

;;; asset-validate-and-copy: source-note-id threading.

(ert-deftest a3madkour-pub-assets-test/validate-threads-source-note-id ()
  "Caller-supplied source-note-id is forwarded to rewrite-asset-link."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-validate-thread-" t)))
        (captured-source-note-id nil))
    (unwind-protect
        (let ((org-file (expand-file-name "x.org" tmp))
              (svg (expand-file-name "diagram.svg" tmp))
              (bundle (file-name-as-directory
                       (expand-file-name "bundle/" tmp))))
          (make-directory bundle t)
          (with-temp-file svg (insert "<svg/>"))
          (with-temp-file org-file
            (insert "* H\n[[file:diagram.svg]]\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/rewrite-asset-link)
                     (lambda (_path _text source-note-id &optional _dry-run)
                       (setq captured-source-note-id source-note-id)
                       (list :inert "(stub)" :warnings nil))))
            (a3madkour-pub/asset-validate-and-copy
             org-file bundle "real-note-id-42"))
          (should (equal captured-source-note-id "real-note-id-42")))
      (delete-directory tmp t))))

(ert-deftest a3madkour-pub-assets-test/validate-nil-source-note-id-tolerated ()
  "Omitting source-note-id passes nil through; no user-error fires."
  (let ((tmp (file-name-as-directory (make-temp-file "a3-validate-nil-" t))))
    (unwind-protect
        (let ((org-file (expand-file-name "x.org" tmp))
              (svg (expand-file-name "diagram.svg" tmp))
              (bundle (file-name-as-directory
                       (expand-file-name "bundle/" tmp)))
              (captured-source-note-id 'unset))
          (make-directory bundle t)
          (with-temp-file svg (insert "<svg/>"))
          (with-temp-file org-file
            (insert "* H\n[[file:diagram.svg]]\n"))
          (cl-letf (((symbol-function 'a3madkour-pub/rewrite-asset-link)
                     (lambda (_path _text source-note-id &optional _dry-run)
                       (setq captured-source-note-id source-note-id)
                       (list :inert "(stub)" :warnings nil))))
            ;; Should NOT signal — formerly threw user-error on "from-validate".
            (a3madkour-pub/asset-validate-and-copy org-file bundle))
          (should (null captured-source-note-id)))
      (delete-directory tmp t))))

(provide 'a3madkour-publish-assets-test)

;;; a3madkour-publish-assets-test.el ends here
