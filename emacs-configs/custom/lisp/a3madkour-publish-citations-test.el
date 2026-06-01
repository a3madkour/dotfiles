;;; a3madkour-publish-citations-test.el --- ert tests for F citations -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'a3madkour-publish-citations)
(require 'a3madkour-publish-bib-test)

;; -- Helpers --

(defmacro a3madkour-pub-citations-test--with-org (org-string &rest body)
  "Insert ORG-STRING into a temp org buffer, run BODY there."
  (declare (indent 1))
  `(with-temp-buffer
     (org-mode)
     (insert ,org-string)
     (goto-char (point-min))
     ,@body))

;; -- Task 8: cite--scan-buffer --

(ert-deftest a3madkour-pub-citations-test/scan-bare-cite ()
  "F Task 8: a bare [cite:@k] is discovered."
  (a3madkour-pub-citations-test--with-org
      "* Heading\nBody [cite:@key1] more.\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should (= 1 (length pairs)))
      (should (equal "key1" (car (car pairs)))))))

(ert-deftest a3madkour-pub-citations-test/scan-multi-cite ()
  "F Task 8: [cite:@a;@b;@c] yields 3 pairs in source order."
  (a3madkour-pub-citations-test--with-org
      "Body [cite:@a;@b;@c] tail.\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should (= 3 (length pairs)))
      (should (equal '("a" "b" "c") (mapcar #'car pairs))))))

(ert-deftest a3madkour-pub-citations-test/scan-skips-src-blocks ()
  "F Task 8: [cite:@k] inside a #+BEGIN_SRC block is NOT discovered."
  (a3madkour-pub-citations-test--with-org
      "Body.\n#+BEGIN_SRC text\n[cite:@should-skip]\n#+END_SRC\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should-not pairs))))

(ert-deftest a3madkour-pub-citations-test/scan-skips-noexport-subtree ()
  "F Task 8: a :noexport: subtree is excluded from the scan."
  (a3madkour-pub-citations-test--with-org
      "* Public\nBody [cite:@public]\n* Private :noexport:\n[cite:@hidden]\n"
    (let* ((pairs (a3madkour-pub-citations--scan-buffer))
           (keys (mapcar #'car pairs)))
      ;; In org-element, :noexport: trees are still parsed; we filter them.
      ;; If org-element-parse-buffer does NOT filter them, this test pins
      ;; the requirement: scan must filter manually.
      (should (member "public" keys))
      (should-not (member "hidden" keys)))))

(ert-deftest a3madkour-pub-citations-test/scan-finds-cite-in-footnote ()
  "F Task 8: cite inside [fn:: ...] inline footnote is discovered."
  (a3madkour-pub-citations-test--with-org
      "Body[fn::See [cite:@fnkey].]\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should (member "fnkey" (mapcar #'car pairs))))))

(ert-deftest a3madkour-pub-citations-test/scan-finds-cite-in-table ()
  "F Task 8: cite inside a table cell is discovered."
  (a3madkour-pub-citations-test--with-org
      "| col |\n|-----|\n| [cite:@tab] |\n"
    (let ((pairs (a3madkour-pub-citations--scan-buffer)))
      (should (member "tab" (mapcar #'car pairs))))))

(ert-deftest a3madkour-pub-citations-test/scan-empty-buffer ()
  "F Task 8: empty buffer returns nil."
  (a3madkour-pub-citations-test--with-org ""
    (should-not (a3madkour-pub-citations--scan-buffer))))

;; -- Task 9: rewrite-cite-keys-in-buffer --

(defmacro a3madkour-pub-citations-test--rewritten (org-string &rest body)
  "Insert ORG-STRING, init accumulator, prime parser cache with a stub
.bib that resolves a/b/c/key1/fnkey/tab/public, run rewriter, run BODY."
  (declare (indent 1))
  `(progn
     (a3madkour-pub-citations--accumulator-init)
     (a3madkour-pub-bib-test--with-bib
         "@misc{key1, title={T}, date={2020}, author={A, A}, publisher={P}}
@misc{a, title={T}, date={2020}, author={A, A}, publisher={P}}
@misc{b, title={T}, date={2020}, author={A, A}, publisher={P}}
@misc{c, title={T}, date={2020}, author={A, A}, publisher={P}}
@misc{fnkey, title={T}, date={2020}, author={A, A}, publisher={P}}
@misc{tab, title={T}, date={2020}, author={A, A}, publisher={P}}
@misc{public, title={T}, date={2020}, author={A, A}, publisher={P}}"
       (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
                  (lambda () nil)))
         (a3madkour-pub-citations-test--with-org ,org-string
           (a3madkour-pub-citations/rewrite-cite-keys-in-buffer "/fake/source.org")
           ,@body)))))

(ert-deftest a3madkour-pub-citations-test/rewrite-bare-cite ()
  "F Task 9: [cite:@key1] becomes @@hugo:{{< cite \"key1\" >}}@@."
  (a3madkour-pub-citations-test--rewritten
      "Body [cite:@key1] tail.\n"
    (goto-char (point-min))
    (should (search-forward "@@hugo:{{< cite \"key1\" >}}@@" nil t))
    (should-not (search-forward "[cite:" nil t))))

(ert-deftest a3madkour-pub-citations-test/rewrite-multi-cite ()
  "F Task 9: [cite:@a;@b;@c] becomes 3 adjacent shortcodes inside one
@@hugo: wrapper."
  (a3madkour-pub-citations-test--rewritten
      "Body [cite:@a;@b;@c] tail.\n"
    (goto-char (point-min))
    (should (search-forward
             "@@hugo:{{< cite \"a\" >}}{{< cite \"b\" >}}{{< cite \"c\" >}}@@"
             nil t))))

(ert-deftest a3madkour-pub-citations-test/rewrite-populates-accumulator ()
  "F Task 9: each rewritten key lands in the accumulator with source file."
  (a3madkour-pub-citations-test--rewritten
      "Body [cite:@a;@b] tail.\n"
    (should (gethash "a" a3madkour-pub-citations--accumulator))
    (should (gethash "b" a3madkour-pub-citations--accumulator))
    (let ((a-entries (gethash "a" a3madkour-pub-citations--accumulator)))
      (should (equal "/fake/source.org" (caar a-entries))))))

(ert-deftest a3madkour-pub-citations-test/rewrite-fails-on-unknown-key ()
  "F Task 9: missing bib entry → fail-fast with source pointer."
  (a3madkour-pub-citations--accumulator-init)
  (a3madkour-pub-bib-test--with-bib "@misc{known, title={T}}"
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () nil)))
      (a3madkour-pub-citations-test--with-org "Body [cite:@nope] tail.\n"
        (let ((err (should-error
                    (a3madkour-pub-citations/rewrite-cite-keys-in-buffer
                     "/fake/source.org"))))
          (should (string-match-p "nope" (format "%s" err))))))))

(ert-deftest a3madkour-pub-citations-test/rewrite-fails-on-style-override ()
  "F Task 9: [cite/text:@k] signals an unsupported-form error."
  (a3madkour-pub-citations--accumulator-init)
  (a3madkour-pub-bib-test--with-bib "@misc{k, title={T}}"
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () nil)))
      (a3madkour-pub-citations-test--with-org "[cite/text:@k]"
        (let ((err (should-error
                    (a3madkour-pub-citations/rewrite-cite-keys-in-buffer
                     "/fake/source.org"))))
          (should (string-match-p "cite/style\\|not supported"
                                  (format "%s" err))))))))

(ert-deftest a3madkour-pub-citations-test/rewrite-fails-on-prefix-suffix ()
  "F Task 9: [cite:see @k] (prefix text) signals unsupported."
  (a3madkour-pub-citations--accumulator-init)
  (a3madkour-pub-bib-test--with-bib "@misc{k, title={T}}"
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () nil)))
      (a3madkour-pub-citations-test--with-org "[cite:see @k]"
        (should-error
         (a3madkour-pub-citations/rewrite-cite-keys-in-buffer
          "/fake/source.org"))))))

(ert-deftest a3madkour-pub-citations-test/rewrite-strips-print-bibliography ()
  "F Task 9: #+print_bibliography: lines are removed."
  (a3madkour-pub-citations--accumulator-init)
  (a3madkour-pub-bib-test--with-bib "@misc{k, title={T}}"
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () nil)))
      (a3madkour-pub-citations-test--with-org
          "Body [cite:@k]\n\n#+print_bibliography:\n"
        (a3madkour-pub-citations/rewrite-cite-keys-in-buffer "/fake/source.org")
        (goto-char (point-min))
        (should-not (search-forward "#+print_bibliography" nil t))))))

(ert-deftest a3madkour-pub-citations-test/rewrite-no-cites-is-noop ()
  "F Task 9: buffer without any [cite:] is unchanged."
  (a3madkour-pub-citations--accumulator-init)
  (a3madkour-pub-bib-test--with-bib ""
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () nil)))
      (a3madkour-pub-citations-test--with-org "Body without cites.\n"
        (let ((before (buffer-string)))
          (a3madkour-pub-citations/rewrite-cite-keys-in-buffer "/fake/source.org")
          (should (equal before (buffer-string))))))))

(ert-deftest a3madkour-pub-citations-test/rewrite-stops-on-first-error ()
  "F Task 9: when [cite:@nope1] and [cite:@nope2] both fail, the first one
stops the run (no second-error reporting)."
  (a3madkour-pub-citations--accumulator-init)
  (a3madkour-pub-bib-test--with-bib ""
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () nil)))
      (a3madkour-pub-citations-test--with-org "[cite:@nope1] [cite:@nope2]"
        (let ((err (should-error
                    (a3madkour-pub-citations/rewrite-cite-keys-in-buffer
                     "/fake/source.org"))))
          (should (string-match-p "nope1" (format "%s" err)))
          (should-not (string-match-p "nope2" (format "%s" err))))))))

(ert-deftest a3madkour-pub-citations-test/rewrite-preserves-non-cite-content ()
  "F Task 9: rewriter only touches [cite:...] forms; everything else is verbatim."
  (a3madkour-pub-citations-test--rewritten
      "* Heading\n\nA paragraph with [cite:@key1] inline.\n\nSecond paragraph.\n"
    (goto-char (point-min))
    (should (search-forward "Heading" nil t))
    (goto-char (point-min))
    (should (search-forward "Second paragraph" nil t))))

(ert-deftest a3madkour-pub-citations-test/rewrite-multiple-bare-cites ()
  "F Task 9: two separate [cite:@a] [cite:@b] sites both rewrite."
  (a3madkour-pub-citations-test--rewritten
      "First [cite:@a] middle [cite:@b] last.\n"
    (goto-char (point-min))
    (should (search-forward "@@hugo:{{< cite \"a\" >}}@@" nil t))
    (goto-char (point-min))
    (should (search-forward "@@hugo:{{< cite \"b\" >}}@@" nil t))))

;; -- Task 10: cite--lookup-notes-ref --

(defmacro a3madkour-pub-citations-test--with-manifest (manifest-alist &rest body)
  "Let-bind the manifest snapshot defvar to MANIFEST-ALIST and run BODY."
  (declare (indent 1))
  `(let ((a3madkour-pub--manifest-snapshot ,manifest-alist))
     ,@body))

(defmacro a3madkour-pub-citations-test--with-ref-note-dir (specs &rest body)
  "SPECS is an alist of (KEY-SYMBOL . PROPERTY-STRINGS).  Create a temp
ref-notes directory with one .org file per key; let-bind the F ref-notes
dir to it; run BODY."
  (declare (indent 1))
  `(let ((tmp (make-temp-file "a3-pub-ref-notes-" t)))
     (unwind-protect
         (progn
           (dolist (spec ,specs)
             (let* ((key (car spec))
                    (props (cdr spec))
                    (path (expand-file-name
                           (format "%s.org" key) tmp)))
               (with-temp-file path
                 (insert props))))
           (let ((a3madkour-pub-citations--ref-notes-dir
                  (file-name-as-directory tmp)))
             ,@body))
       (delete-directory tmp t))))

(ert-deftest a3madkour-pub-citations-test/notes-ref-absent-returns-nil ()
  "F Task 10: no ref-note file → nil."
  (a3madkour-pub-citations-test--with-ref-note-dir nil
    (a3madkour-pub-citations-test--with-manifest nil
      (should-not (a3madkour-pub-citations--lookup-notes-ref "abc")))))

(ert-deftest a3madkour-pub-citations-test/notes-ref-unpublished-returns-nil ()
  "F Task 10: ref-note exists but HUGO_PUBLISH is missing → nil."
  (a3madkour-pub-citations-test--with-ref-note-dir
      '(("myKey2020" . "#+HUGO_SECTION: garden\n#+title: T\n"))
    (a3madkour-pub-citations-test--with-manifest nil
      (should-not (a3madkour-pub-citations--lookup-notes-ref "myKey2020")))))

(ert-deftest a3madkour-pub-citations-test/notes-ref-wrong-section-returns-nil ()
  "F Task 10: ref-note has HUGO_SECTION other than garden → nil."
  (a3madkour-pub-citations-test--with-ref-note-dir
      '(("myKey2020" .
         "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: essays\n#+title: T\n"))
    (a3madkour-pub-citations-test--with-manifest nil
      (should-not (a3madkour-pub-citations--lookup-notes-ref "myKey2020")))))

(ert-deftest a3madkour-pub-citations-test/notes-ref-not-in-manifest-returns-nil ()
  "F Task 10: ref-note is published but not in the manifest snapshot → nil."
  (a3madkour-pub-citations-test--with-ref-note-dir
      '(("myKey2020" .
         "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+title: T\n"))
    (a3madkour-pub-citations-test--with-manifest
        '((notes . [((id . "id-x")
                     (current_url . "/garden/some-other/")
                     (state . "live"))]))
      (should-not (a3madkour-pub-citations--lookup-notes-ref "myKey2020")))))

(ert-deftest a3madkour-pub-citations-test/notes-ref-happy-path-returns-slug ()
  "F Task 10: ref-note published AND in manifest under /garden/<slug>/ →
returns <slug> string."
  (a3madkour-pub-citations-test--with-ref-note-dir
      '(("myKey2020" .
         "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+title: My Key\n"))
    (a3madkour-pub-citations-test--with-manifest
        '((notes . [((id . "id-key")
                     (current_url . "/garden/mykey2020/")
                     (state . "live"))]))
      (should (equal "mykey2020"
                     (a3madkour-pub-citations--lookup-notes-ref "myKey2020"))))))

;; -- Task 11: cite-emit-yaml --

(defmacro a3madkour-pub-citations-test--with-yaml-dir (&rest body)
  "Set up a temp site root with data/ subdir; let-bind a3madkour-pub/site-data-dir."
  (declare (indent 0))
  `(let* ((tmp-root (make-temp-file "a3-pub-citations-" t))
          (tmp-data (expand-file-name "data/" tmp-root)))
     (make-directory tmp-data t)
     (unwind-protect
         (let ((a3madkour-pub/site-data-dir tmp-data))
           ,@body)
       (delete-directory tmp-root t))))

(ert-deftest a3madkour-pub-citations-test/emit-writes-yaml-for-cited-keys ()
  "F Task 11: emit-yaml writes data/citations.yaml with each accumulated key."
  (a3madkour-pub-citations-test--with-yaml-dir
    (a3madkour-pub-bib-test--with-bib
        "@misc{a, author={A,A}, title={T-A}, date={2020}, publisher={P}}"
      (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p) (lambda () nil)))
        (a3madkour-pub-citations--accumulator-init)
        (puthash "a" '(("/fake/x.org" . 1)) a3madkour-pub-citations--accumulator)
        (a3madkour-pub-citations/emit-yaml)
        (let ((yaml-text (with-temp-buffer
                           (insert-file-contents
                            (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir))
                           (buffer-string))))
          (should (string-match-p "^citations:" yaml-text))
          (should (string-match-p "  a:" yaml-text))
          (should (string-match-p "title: \"T-A\"" yaml-text)))))))

(ert-deftest a3madkour-pub-citations-test/emit-merges-with-existing ()
  "F Task 11: pre-existing keys NOT in accumulator survive untouched."
  (a3madkour-pub-citations-test--with-yaml-dir
    (let ((existing (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir)))
      (with-temp-file existing
        (insert "citations:\n  preexisting:\n    authors: [\"X, Y\"]\n"
                "    year: 2010\n    title: \"Old\"\n    venue: \"V\"\n"))
      (a3madkour-pub-bib-test--with-bib
          "@misc{newkey, author={A,A}, title={NT}, date={2020}, publisher={P}}"
        (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p) (lambda () nil)))
          (a3madkour-pub-citations--accumulator-init)
          (puthash "newkey" '(("/fake/x.org" . 1))
                   a3madkour-pub-citations--accumulator)
          (a3madkour-pub-citations/emit-yaml)
          (let ((yaml-text (with-temp-buffer
                             (insert-file-contents existing)
                             (buffer-string))))
            (should (string-match-p "  preexisting:" yaml-text))
            (should (string-match-p "  newkey:" yaml-text))))))))

(ert-deftest a3madkour-pub-citations-test/emit-sorted-by-key ()
  "F Task 11: keys in output are sorted lexicographically for deterministic diffs."
  (a3madkour-pub-citations-test--with-yaml-dir
    (a3madkour-pub-bib-test--with-bib
        "@misc{zeta, author={A,A}, title={Z}, date={2020}, publisher={P}}
@misc{alpha, author={A,A}, title={A}, date={2020}, publisher={P}}
@misc{mu, author={A,A}, title={M}, date={2020}, publisher={P}}"
      (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p) (lambda () nil)))
        (a3madkour-pub-citations--accumulator-init)
        (dolist (k '("zeta" "alpha" "mu"))
          (puthash k '(("/x.org" . 1)) a3madkour-pub-citations--accumulator))
        (a3madkour-pub-citations/emit-yaml)
        (let* ((yaml-text (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir))
                            (buffer-string)))
               (a-pos    (string-match "^  alpha:" yaml-text))
               (m-pos    (string-match "^  mu:"    yaml-text))
               (z-pos    (string-match "^  zeta:"  yaml-text)))
          (should (and a-pos m-pos z-pos))
          (should (< a-pos m-pos))
          (should (< m-pos z-pos)))))))

(ert-deftest a3madkour-pub-citations-test/emit-idempotent ()
  "F Task 11: re-running emit-yaml with same accumulator yields identical bytes."
  (a3madkour-pub-citations-test--with-yaml-dir
    (a3madkour-pub-bib-test--with-bib
        "@misc{k, author={A,A}, title={T}, date={2020}, publisher={P}}"
      (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p) (lambda () nil)))
        (a3madkour-pub-citations--accumulator-init)
        (puthash "k" '(("/x.org" . 1)) a3madkour-pub-citations--accumulator)
        (a3madkour-pub-citations/emit-yaml)
        (let ((first (with-temp-buffer
                       (insert-file-contents
                        (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir))
                       (buffer-string))))
          (a3madkour-pub-citations/emit-yaml)
          (let ((second (with-temp-buffer
                          (insert-file-contents
                           (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir))
                          (buffer-string))))
            (should (equal first second))))))))

(ert-deftest a3madkour-pub-citations-test/emit-empty-accumulator-noop ()
  "F Task 11: empty accumulator does NOT write or modify the yaml."
  (a3madkour-pub-citations-test--with-yaml-dir
    (let ((existing (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir)))
      (with-temp-file existing (insert "citations:\n  k:\n    authors: [\"X\"]\n"))
      (let ((before (with-temp-buffer (insert-file-contents existing) (buffer-string))))
        (a3madkour-pub-citations--accumulator-init)
        (a3madkour-pub-citations/emit-yaml)
        (let ((after (with-temp-buffer (insert-file-contents existing) (buffer-string))))
          (should (equal before after)))))))

(ert-deftest a3madkour-pub-citations-test/emit-fails-on-missing-required-field ()
  "F Task 11: bib entry without title fails-fast at emit."
  (a3madkour-pub-citations-test--with-yaml-dir
    (a3madkour-pub-bib-test--with-bib
        "@misc{k, author={A,A}, date={2020}, publisher={P}}"
      (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p) (lambda () nil)))
        (a3madkour-pub-citations--accumulator-init)
        (puthash "k" '(("/x.org" . 1)) a3madkour-pub-citations--accumulator)
        (let ((err (should-error (a3madkour-pub-citations/emit-yaml))))
          (should (string-match-p "title\\|required" (format "%s" err))))))))

(ert-deftest a3madkour-pub-citations-test/emit-replace-purge-mode ()
  "F Task 11: emit-yaml with :mode 'replace drops keys not in accumulator."
  (a3madkour-pub-citations-test--with-yaml-dir
    (let ((existing (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir)))
      (with-temp-file existing
        (insert "citations:\n  stale:\n    authors: [\"X\"]\n"
                "    year: 2010\n    title: \"S\"\n    venue: \"V\"\n"))
      (a3madkour-pub-bib-test--with-bib
          "@misc{kept, author={A,A}, title={K}, date={2020}, publisher={P}}"
        (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p) (lambda () nil)))
          (a3madkour-pub-citations--accumulator-init)
          (puthash "kept" '(("/x.org" . 1)) a3madkour-pub-citations--accumulator)
          (a3madkour-pub-citations/emit-yaml :mode 'replace)
          (let ((yaml-text (with-temp-buffer
                             (insert-file-contents existing) (buffer-string))))
            (should     (string-match-p "  kept:"  yaml-text))
            (should-not (string-match-p "  stale:" yaml-text))))))))

(ert-deftest a3madkour-pub-citations-test/emit-uses-tmp-rename ()
  "F Task 11: write goes via .tmp file (atomicity)."
  (a3madkour-pub-citations-test--with-yaml-dir
    (a3madkour-pub-bib-test--with-bib
        "@misc{k, author={A,A}, title={T}, date={2020}, publisher={P}}"
      (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p) (lambda () nil)))
        (let ((calls nil))
          (cl-letf (((symbol-function 'rename-file)
                     (lambda (from to &optional ok-overwrite)
                       (push (cons from to) calls))))
            (a3madkour-pub-citations--accumulator-init)
            (puthash "k" '(("/x.org" . 1)) a3madkour-pub-citations--accumulator)
            (a3madkour-pub-citations/emit-yaml)
            (should (cl-some (lambda (pair) (string-match-p "\\.tmp\\'" (car pair)))
                             calls))))))))

(provide 'a3madkour-publish-citations-test)

;;; a3madkour-publish-citations-test.el ends here
