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

(provide 'a3madkour-publish-bib-test)

;;; a3madkour-publish-bib-test.el ends here
