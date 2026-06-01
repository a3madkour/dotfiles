;;; a3madkour-publish-bib-test.el --- ert tests for F bib resolver -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-bib)

;; -- Helpers --

(defmacro a3madkour-pub-bib-test--with-bib (bib-string &rest body)
  "Parse BIB-STRING into the parser cache, then run BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,bib-string)
     (a3madkour-pub-bib--parse-buffer)
     ,@body))

;; -- Task 3: entry recognition + simple fields --

(ert-deftest a3madkour-pub-bib-test/parses-single-entry ()
  "F Task 3: a minimal @article entry parses into the cache."
  (a3madkour-pub-bib-test--with-bib
      "@article{key1, title = {Hello}, year = 2020}"
    (let ((entry (gethash "key1" a3madkour-pub-bib--parser-cache)))
      (should entry)
      (should (equal (alist-get 'title entry) "Hello"))
      (should (equal (alist-get 'year entry) "2020"))
      (should (equal (alist-get :bibtype entry) "article")))))

(ert-deftest a3madkour-pub-bib-test/parses-quoted-field ()
  "F Task 3: double-quoted field value is read."
  (a3madkour-pub-bib-test--with-bib
      "@misc{key2, title = \"Quoted Title\"}"
    (should (equal (alist-get 'title
                              (gethash "key2" a3madkour-pub-bib--parser-cache))
                   "Quoted Title"))))

(ert-deftest a3madkour-pub-bib-test/parses-bare-numeric-field ()
  "F Task 3: bare numeric field value (e.g. year = 2018) is read."
  (a3madkour-pub-bib-test--with-bib
      "@book{key3, title = {T}, year = 2018}"
    (should (equal (alist-get 'year
                              (gethash "key3" a3madkour-pub-bib--parser-cache))
                   "2018"))))

(ert-deftest a3madkour-pub-bib-test/parses-multiple-entries ()
  "F Task 3: 3 sibling entries all land in the cache."
  (a3madkour-pub-bib-test--with-bib
      "@article{a, title={A}}\n@book{b, title={B}}\n@misc{c, title={C}}"
    (should (= 3 (hash-table-count a3madkour-pub-bib--parser-cache)))
    (should (equal "A" (alist-get 'title (gethash "a" a3madkour-pub-bib--parser-cache))))
    (should (equal "B" (alist-get 'title (gethash "b" a3madkour-pub-bib--parser-cache))))
    (should (equal "C" (alist-get 'title (gethash "c" a3madkour-pub-bib--parser-cache))))))

(ert-deftest a3madkour-pub-bib-test/skips-bibtex-comments ()
  "F Task 3: lines starting with `%' (BibTeX comment) are skipped."
  (a3madkour-pub-bib-test--with-bib
      "% comment line\n@article{ok, title = {T}}"
    (should (gethash "ok" a3madkour-pub-bib--parser-cache))))

(ert-deftest a3madkour-pub-bib-test/skips-string-and-preamble ()
  "F Task 3: @string and @preamble blocks are recognized and skipped."
  (a3madkour-pub-bib-test--with-bib
      "@string{me = \"Author\"}\n@preamble{\"junk\"}\n@misc{ok, title={T}}"
    (should (gethash "ok" a3madkour-pub-bib--parser-cache))
    (should-not (gethash "me" a3madkour-pub-bib--parser-cache))))

(ert-deftest a3madkour-pub-bib-test/case-preserves-key ()
  "F Task 3: BBT camelCase keys keep their case in the cache."
  (a3madkour-pub-bib-test--with-bib
      "@article{abelaConstructiveApproachGeneration2015, title={T}}"
    (should (gethash "abelaConstructiveApproachGeneration2015"
                     a3madkour-pub-bib--parser-cache))
    (should-not (gethash "abelaconstructiveapproachgeneration2015"
                         a3madkour-pub-bib--parser-cache))))

(ert-deftest a3madkour-pub-bib-test/parse-file-returns-count ()
  "F Task 3: parse-file returns the number of entries cached."
  (let* ((tmp (make-temp-file "bib-fixture-" nil ".bib")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "@article{a, title={A}}\n@book{b, title={B}}"))
          (should (= 2 (a3madkour-pub-bib/parse-file tmp))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-bib-test/parse-file-signals-on-missing ()
  "F Task 3: parse-file signals when path doesn't exist."
  (should-error
   (a3madkour-pub-bib/parse-file "/nonexistent/path/library.bib")))

;; -- Task 4: nested braces + author splitting + date extraction --

(ert-deftest a3madkour-pub-bib-test/preserves-nested-braces ()
  "F Task 4: nested {{...}} brace protection — outer pair stripped by
normalize-entry; for the raw parser, both braces survive on the value
string (normalize is Task 6)."
  (a3madkour-pub-bib-test--with-bib
      "@article{k, title = {{Egyptian Streets}}}"
    (let ((title (alist-get 'title (gethash "k" a3madkour-pub-bib--parser-cache))))
      (should (equal title "{Egyptian Streets}")))))

(ert-deftest a3madkour-pub-bib-test/strip-outer-braces-one-pair ()
  "F Task 4: helper strips exactly one outer brace-pair."
  (should (equal (a3madkour-pub-bib--strip-outer-braces "{Hello}")    "Hello"))
  (should (equal (a3madkour-pub-bib--strip-outer-braces "{{Hello}}")  "{Hello}"))
  (should (equal (a3madkour-pub-bib--strip-outer-braces "Hello")      "Hello"))
  (should (equal (a3madkour-pub-bib--strip-outer-braces "  {Hi}  ")   "Hi")))

(ert-deftest a3madkour-pub-bib-test/split-authors-on-and ()
  "F Task 4: BibTeX author field splits on ' and ' (BibTeX convention)."
  (should (equal (a3madkour-pub-bib--split-authors "Lastname, F. and Other, G.")
                 '("Lastname, F." "Other, G.")))
  (should (equal (a3madkour-pub-bib--split-authors "One, A. and Two, B. and Three, C.")
                 '("One, A." "Two, B." "Three, C.")))
  (should (equal (a3madkour-pub-bib--split-authors "Solo, A.")
                 '("Solo, A."))))

(ert-deftest a3madkour-pub-bib-test/split-authors-empty-string ()
  "F Task 4: empty author field returns empty list."
  (should (equal (a3madkour-pub-bib--split-authors "") nil))
  (should (equal (a3madkour-pub-bib--split-authors "   ") nil)))

(ert-deftest a3madkour-pub-bib-test/year-from-date-iso ()
  "F Task 4: extract year int from ISO date string."
  (should (= 2014 (a3madkour-pub-bib--year-from-date "2014-12-27")))
  (should (= 2014 (a3madkour-pub-bib--year-from-date "2014-12-27T16:00:18+00:00")))
  (should (= 2014 (a3madkour-pub-bib--year-from-date "2014"))))

(ert-deftest a3madkour-pub-bib-test/year-from-date-nil-on-junk ()
  "F Task 4: junk input returns nil."
  (should-not (a3madkour-pub-bib--year-from-date "junk"))
  (should-not (a3madkour-pub-bib--year-from-date ""))
  (should-not (a3madkour-pub-bib--year-from-date nil)))

(ert-deftest a3madkour-pub-bib-test/parser-handles-real-fixture ()
  "F Task 4: the stub library.bib fixture parses without error and yields
9 entries, including the BBT camelCase key from Task 3."
  ;; tools/fixtures/citations/library.bib lives in the SITE repo; locate
  ;; via a robust path discovery (a3-pub.sh sets cwd, so use $PWD or env).
  (let ((fixture
         (or (and (boundp 'a3madkour-pub-test/site-root)
                  (expand-file-name
                   "tools/fixtures/citations/library.bib"
                   a3madkour-pub-test/site-root))
             (expand-file-name
              "../../../../Sync/Workspace/a3madkour.github.io/tools/fixtures/citations/library.bib"
              (file-name-directory (or load-file-name buffer-file-name "."))))))
    (skip-unless (file-exists-p fixture))
    (let ((n (a3madkour-pub-bib/parse-file fixture)))
      (should (= 9 n))
      (should (gethash "loremIpsumDolorSit2020" a3madkour-pub-bib--parser-cache)))))

(ert-deftest a3madkour-pub-bib-test/multiline-field-value-survives ()
  "F Task 4: a {...} value spanning multiple lines reads as one string."
  (a3madkour-pub-bib-test--with-bib
      "@article{k,\n  title = {Line one\n  line two},\n  year = 2020}"
    (let ((title (alist-get 'title (gethash "k" a3madkour-pub-bib--parser-cache))))
      (should (string-match-p "Line one" title))
      (should (string-match-p "line two" title)))))

;; -- Task 5: @string substitution + error paths --

(ert-deftest a3madkour-pub-bib-test/string-substitution ()
  "F Task 5: @string{shortcut = \"expansion\"} substitutes when a field
value is the bare shortcut token (BibTeX `concat`-by-#-of-strings is OUT
of V1; we only handle the bare-reference form because real Zotero/BBT
output doesn't use the `#` concat form)."
  (a3madkour-pub-bib-test--with-bib
      "@string{acm = \"ACM\"}\n@article{k, title = {T}, publisher = acm}"
    (should (equal "ACM"
                   (alist-get 'publisher
                              (gethash "k" a3madkour-pub-bib--parser-cache))))))

(ert-deftest a3madkour-pub-bib-test/unbalanced-braces-signals ()
  "F Task 5: unbalanced braces in a field value signal a clear error."
  (should-error
   (a3madkour-pub-bib-test--with-bib
       "@article{k, title = {Hello"
     nil)))

(ert-deftest a3madkour-pub-bib-test/malformed-entry-header-signals ()
  "F Task 5: an `@type' without `{key,' signals."
  (should-error
   (a3madkour-pub-bib-test--with-bib
       "@article corrupt"
     nil)))

(ert-deftest a3madkour-pub-bib-test/unterminated-quoted-value-signals ()
  "F Task 5: an opened `\"' with no closing `\"' signals."
  (should-error
   (a3madkour-pub-bib-test--with-bib
       "@article{k, title = \"unterminated"
     nil)))

(ert-deftest a3madkour-pub-bib-test/empty-file-returns-zero ()
  "F Task 5: parsing an empty buffer is a no-op returning 0."
  (a3madkour-pub-bib-test--with-bib ""
    (should (= 0 (hash-table-count a3madkour-pub-bib--parser-cache)))))

(provide 'a3madkour-publish-bib-test)

;;; a3madkour-publish-bib-test.el ends here
