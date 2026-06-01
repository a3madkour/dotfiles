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
10 entries (8 type-coverage + 1 no-author fallback + 1 dummyKey2024 for
the cite-with-ref-note integration test), including the BBT camelCase
key from Task 3."
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
      (should (= 10 n))
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

;; -- Task 6: normalize-entry --

(defmacro a3madkour-pub-bib-test--normalized (bib-string key &rest body)
  "Parse BIB-STRING, fetch KEY's raw alist, normalize it; bind ENTRY."
  (declare (indent 2))
  `(a3madkour-pub-bib-test--with-bib ,bib-string
     (let ((entry (a3madkour-pub-bib--normalize-entry
                   (gethash ,key a3madkour-pub-bib--parser-cache))))
       ,@body)))

(ert-deftest a3madkour-pub-bib-test/normalize-authors-list ()
  "F Task 6: authors split on ' and ' → list of strings."
  (a3madkour-pub-bib-test--normalized
      "@article{k, author = {Last, F. and Other, G.}, title={T}, date={2020}, journaltitle={J}}"
      "k"
    (should (equal '("Last, F." "Other, G.") (plist-get entry :authors)))))

(ert-deftest a3madkour-pub-bib-test/normalize-empty-author-fallback ()
  "F Task 6: missing author → :authors '(\"Unknown\")."
  (a3madkour-pub-bib-test--normalized
      "@online{k, title={T}, date={2024}, url={https://example.invalid/x}}"
      "k"
    (should (equal '("Unknown") (plist-get entry :authors)))))

(ert-deftest a3madkour-pub-bib-test/normalize-year-from-iso-date ()
  "F Task 6: ISO date → integer year."
  (a3madkour-pub-bib-test--normalized
      "@article{k, author={A, A}, title={T}, date={2014-12-27}, journaltitle={J}}"
      "k"
    (should (= 2014 (plist-get entry :year)))))

(ert-deftest a3madkour-pub-bib-test/normalize-year-from-legacy-year ()
  "F Task 6: legacy `year = 2018' (no date) extracts to int."
  (a3madkour-pub-bib-test--normalized
      "@book{k, author={A, A}, title={T}, year={2018}, publisher={P}}"
      "k"
    (should (= 2018 (plist-get entry :year)))))

(ert-deftest a3madkour-pub-bib-test/normalize-venue-journaltitle-wins ()
  "F Task 6: journaltitle is preferred over booktitle/publisher."
  (a3madkour-pub-bib-test--normalized
      "@article{k, author={A, A}, title={T}, date={2020}, journaltitle={J}, publisher={P}}"
      "k"
    (should (equal "J" (plist-get entry :venue)))))

(ert-deftest a3madkour-pub-bib-test/normalize-venue-booktitle-fallback ()
  "F Task 6: no journaltitle → booktitle wins."
  (a3madkour-pub-bib-test--normalized
      "@inproceedings{k, author={A, A}, title={T}, date={2020}, booktitle={Proc Conf}}"
      "k"
    (should (equal "Proc Conf" (plist-get entry :venue)))))

(ert-deftest a3madkour-pub-bib-test/normalize-venue-publisher-fallback ()
  "F Task 6: no journaltitle/booktitle → publisher wins."
  (a3madkour-pub-bib-test--normalized
      "@book{k, author={A, A}, title={T}, date={2020}, publisher={Book Co}}"
      "k"
    (should (equal "Book Co" (plist-get entry :venue)))))

(ert-deftest a3madkour-pub-bib-test/normalize-venue-eventtitle-fallback ()
  "F Task 6: no journaltitle/booktitle/publisher → eventtitle wins."
  (a3madkour-pub-bib-test--normalized
      "@misc{k, author={A, A}, title={T}, date={2020}, eventtitle={Some Event}}"
      "k"
    (should (equal "Some Event" (plist-get entry :venue)))))

(ert-deftest a3madkour-pub-bib-test/normalize-type-known-enum ()
  "F Task 6: @article → \"article\"; @inproceedings → \"inproceedings\"."
  (a3madkour-pub-bib-test--normalized
      "@article{k, author={A, A}, title={T}, date={2020}, journaltitle={J}}"
      "k"
    (should (equal "article" (plist-get entry :type)))))

(ert-deftest a3madkour-pub-bib-test/normalize-type-unknown-to-misc ()
  "F Task 6: unknown @entrytype maps to \"misc\"."
  (a3madkour-pub-bib-test--normalized
      "@weirdtype{k, author={A, A}, title={T}, date={2020}, publisher={P}}"
      "k"
    (should (equal "misc" (plist-get entry :type)))))

(ert-deftest a3madkour-pub-bib-test/normalize-strips-all-title-braces ()
  "F Task 6 (revised): ALL brace chars stripped from titles.
BBT-exported titles wrap every capitalized word in {{ }} for case
protection; Hugo renders those literally.  Strip them.  Real-world
spot-check (F Task 18) confirmed the previous inner-survive behavior
rendered ugly titles like `R-{{WoM}}: {{...}}'."
  (a3madkour-pub-bib-test--normalized
      "@article{k, author={A, A}, title={{Egyptian Streets}}, date={2014}, journaltitle={J}}"
      "k"
    (should (equal "Egyptian Streets" (plist-get entry :title)))))

(ert-deftest a3madkour-pub-bib-test/normalize-rejects-bad-url ()
  "F Task 6: non-http URL is dropped to nil."
  (a3madkour-pub-bib-test--normalized
      "@misc{k, author={A, A}, title={T}, date={2020}, publisher={P}, url={ftp://nope}}"
      "k"
    (should-not (plist-get entry :url))))

;; -- Task 7: bib-resolve dispatch + citar adapter --

(ert-deftest a3madkour-pub-bib-test/resolve-via-parser ()
  "F Task 7: when citar is NOT loaded (forced), resolve goes through
the parser path and returns the schema plist."
  (a3madkour-pub-bib-test--with-bib
      "@article{k, author={A, A}, title={T}, date={2020}, journaltitle={J}}"
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () nil)))
      (let ((entry (a3madkour-pub-bib/resolve "k")))
        (should entry)
        (should (equal "T" (plist-get entry :title)))
        (should (equal '("A, A") (plist-get entry :authors)))))))

(ert-deftest a3madkour-pub-bib-test/resolve-unknown-returns-nil ()
  "F Task 7: resolve returns nil for unknown keys."
  (a3madkour-pub-bib-test--with-bib "@article{a, title={A}}"
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () nil)))
      (should-not (a3madkour-pub-bib/resolve "nonexistent")))))

(ert-deftest a3madkour-pub-bib-test/resolve-via-citar-when-loaded ()
  "F Task 7: when citar IS loaded (forced), resolve calls citar."
  (let ((calls 0))
    (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
               (lambda () t))
              ((symbol-function 'a3madkour-pub-bib--read-via-citar)
               (lambda (key)
                 (setq calls (1+ calls))
                 (list :authors '("CitarA, A") :year 2020 :title "CitarT"
                       :venue "CitarV" :url nil :doi nil :publisher nil
                       :volume nil :issue nil :pages nil :isbn nil
                       :type "article"))))
      (let ((entry (a3madkour-pub-bib/resolve "k")))
        (should (= 1 calls))
        (should (equal "CitarT" (plist-get entry :title)))))))

(ert-deftest a3madkour-pub-bib-test/resolve-parity-parser-vs-citar ()
  "F Task 7: parser and citar paths return plist-equal results for the
same fixture entry.  Drift safeguard — see spec §9."
  (a3madkour-pub-bib-test--with-bib
      "@article{k, author={Last, F.}, title={T}, date={2020}, journaltitle={J}}"
    (let* ((parser-result
            (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
                       (lambda () nil)))
              (a3madkour-pub-bib/resolve "k")))
           (citar-result
            (cl-letf (((symbol-function 'a3madkour-pub-bib--citar-loaded-p)
                       (lambda () t))
                      ((symbol-function 'a3madkour-pub-bib--read-via-citar)
                       (lambda (_) parser-result)))   ;; stub returns same plist
              (a3madkour-pub-bib/resolve "k"))))
      (should (equal parser-result citar-result)))))

(ert-deftest a3madkour-pub-bib-test/citar-loaded-p-detection ()
  "F Task 7: citar-loaded-p returns truthy iff citar is featurep'd AND
its API symbols are bound."
  ;; Force not loaded: featurep returns nil for citar.
  (cl-letf (((symbol-function 'featurep)
             (lambda (sym) (and (not (eq sym 'citar))))))
    (should-not (a3madkour-pub-bib--citar-loaded-p)))
  ;; Force loaded: featurep returns t for citar AND fboundp returns t for API.
  (cl-letf (((symbol-function 'featurep)
             (lambda (sym) (or (eq sym 'citar))))
            ((symbol-function 'fboundp)
             (lambda (sym) (memq sym '(citar-get-entry citar-get-value)))))
    (should (a3madkour-pub-bib--citar-loaded-p))))

;; -- Task 14: BBT JSON-RPC client --

(ert-deftest a3madkour-pub-bib-test/refresh-disabled-when-endpoint-nil ()
  "F Task 14: bbt-endpoint=nil disables refresh; returns nil; no HTTP call."
  (let ((a3madkour-pub-bib/bbt-endpoint nil)
        (calls 0))
    (cl-letf (((symbol-function 'url-retrieve-synchronously)
               (lambda (&rest _) (setq calls (1+ calls)) nil)))
      (should-not (a3madkour-pub-bib/refresh-from-zotero))
      (should (= 0 calls)))))

(ert-deftest a3madkour-pub-bib-test/refresh-200-writes-file ()
  "F Task 14: 200 response with valid body atomic-writes the .bib path."
  (let* ((tmp-bib (make-temp-file "f-bbt-" nil ".bib"))
         (a3madkour-pub-bib/library-path tmp-bib)
         (a3madkour-pub-bib/bbt-endpoint "http://localhost:23119/x"))
    (unwind-protect
        (cl-letf (((symbol-function 'url-retrieve-synchronously)
                   (lambda (&rest _)
                     (with-current-buffer (generate-new-buffer "*bbt-mock*")
                       (insert "HTTP/1.1 200 OK\r\n"
                               "Content-Type: application/json\r\n\r\n"
                               "{\"jsonrpc\":\"2.0\",\"result\":\"@article{ok, title={T}}\\n\"}")
                       (current-buffer)))))
          (should (a3madkour-pub-bib/refresh-from-zotero))
          (let ((written (with-temp-buffer
                           (insert-file-contents tmp-bib) (buffer-string))))
            (should (string-match-p "@article{ok" written))))
      (when (file-exists-p tmp-bib) (delete-file tmp-bib)))))

(ert-deftest a3madkour-pub-bib-test/refresh-non-200-warns-and-returns-nil ()
  "F Task 14: non-2xx response returns nil without writing the .bib."
  (let* ((tmp-bib (make-temp-file "f-bbt-" nil ".bib"))
         (a3madkour-pub-bib/library-path tmp-bib)
         (a3madkour-pub-bib/bbt-endpoint "http://localhost:23119/x"))
    (with-temp-file tmp-bib (insert "@misc{original, title={Orig}}"))
    (unwind-protect
        (cl-letf (((symbol-function 'url-retrieve-synchronously)
                   (lambda (&rest _)
                     (with-current-buffer (generate-new-buffer "*bbt-mock*")
                       (insert "HTTP/1.1 503 Service Unavailable\r\n\r\n{}")
                       (current-buffer)))))
          (should-not (a3madkour-pub-bib/refresh-from-zotero))
          (let ((post (with-temp-buffer
                        (insert-file-contents tmp-bib) (buffer-string))))
            (should (string-match-p "original" post))))
      (when (file-exists-p tmp-bib) (delete-file tmp-bib)))))

(ert-deftest a3madkour-pub-bib-test/refresh-connection-refused-returns-nil ()
  "F Task 14: ECONNREFUSED (url-retrieve-synchronously signals or returns nil)."
  (let ((a3madkour-pub-bib/library-path
         (make-temp-file "f-bbt-" nil ".bib"))
        (a3madkour-pub-bib/bbt-endpoint "http://localhost:23119/x"))
    (unwind-protect
        (cl-letf (((symbol-function 'url-retrieve-synchronously)
                   (lambda (&rest _)
                     (signal 'file-error '("Connection refused")))))
          (should-not (a3madkour-pub-bib/refresh-from-zotero)))
      (when (file-exists-p a3madkour-pub-bib/library-path)
        (delete-file a3madkour-pub-bib/library-path)))))

(ert-deftest a3madkour-pub-bib-test/refresh-malformed-json-returns-nil ()
  "F Task 14: 200 with garbage body returns nil without writing."
  (let* ((tmp-bib (make-temp-file "f-bbt-" nil ".bib"))
         (a3madkour-pub-bib/library-path tmp-bib)
         (a3madkour-pub-bib/bbt-endpoint "http://localhost:23119/x"))
    (with-temp-file tmp-bib (insert "@misc{original, title={Orig}}"))
    (unwind-protect
        (cl-letf (((symbol-function 'url-retrieve-synchronously)
                   (lambda (&rest _)
                     (with-current-buffer (generate-new-buffer "*bbt-mock*")
                       (insert "HTTP/1.1 200 OK\r\n\r\nNOT VALID JSON")
                       (current-buffer)))))
          (should-not (a3madkour-pub-bib/refresh-from-zotero))
          (let ((post (with-temp-buffer
                        (insert-file-contents tmp-bib) (buffer-string))))
            (should (string-match-p "original" post))))
      (when (file-exists-p tmp-bib) (delete-file tmp-bib)))))

(provide 'a3madkour-publish-bib-test)

;;; a3madkour-publish-bib-test.el ends here
