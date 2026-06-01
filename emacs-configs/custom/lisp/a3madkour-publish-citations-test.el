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

(provide 'a3madkour-publish-citations-test)

;;; a3madkour-publish-citations-test.el ends here
