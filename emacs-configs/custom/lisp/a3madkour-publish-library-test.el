;;; a3madkour-publish-library-test.el --- tests for library shelf rendering  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-library)
(require 'a3madkour-sections-fixture)

(ert-deftest a3madkour-pub-library--module-loads ()
  "Smoke: module loadable; exposes the row renderer and the shelf refuser."
  (should (fboundp 'a3madkour-pub-library--render-row))
  (should (fboundp 'a3madkour-pub-library/refuse-shelf-file)))

(defun a3madkour-pub-library-test--rows (rows)
  "Render ROWS (plists) as the item lines of a shelf."
  (mapconcat #'a3madkour-pub-library--render-row rows "\n"))

(ert-deftest a3madkour-pub-library--render-yaml-shape ()
  "Rows render as yaml list items, matching the shelf fixture shape."
  (let* ((rows (list (list :slug "abc"
                           :title "Abc Title"
                           :creator "Author A"
                           :year 2024
                           :media_type "book"
                           :status "reading"
                           :last_modified "2026-05-01"
                           :tags '("alpha" "beta"))
                     (list :slug "def"
                           :title "Def Title"
                           :creator "Author B"
                           :year 2023
                           :media_type "book"
                           :status "finished"
                           :last_modified "2026-04-15"
                           :finished "2026-04-14"
                           :tags '())))
         (out (a3madkour-pub-library-test--rows rows)))
    ;; Each row is a list item opening on its slug.
    (should (string-match-p "^  - slug: abc$" out))
    ;; Input order (abc before def).
    (let ((abc-pos (string-match-p "slug: abc" out))
          (def-pos (string-match-p "slug: def" out)))
      (should (and abc-pos def-pos (< abc-pos def-pos))))
    ;; Dates emitted unquoted (PyYAML loads as datetime.date).
    (should (string-match-p "last_modified: 2026-05-01" out))
    (should-not (string-match-p "last_modified: \"" out))
    ;; Tags inline array.
    (should (string-match-p "tags: \\[alpha, beta\\]" out))
    ;; Empty-tag row renders as empty inline array.
    (should (string-match-p "tags: \\[\\]" out))))

(ert-deftest a3madkour-pub-library--render-yaml-extras-nested ()
  "Extras render as a nested map."
  (let* ((rows (list (list :slug "x" :title "X" :creator "y" :year 2024
                           :media_type "game" :status "playing"
                           :last_modified "2026-05-01"
                           :tags '("puzzle")
                           :extras (list :igdb_id 12345
                                         :hours_played 22
                                         :platform "PC"))))
         (out (a3madkour-pub-library-test--rows rows)))
    (should (string-match-p "extras:" out))
    (should (string-match-p "  igdb_id: 12345" out))
    (should (string-match-p "  hours_played: 22" out))
    (should (string-match-p "  platform: PC" out))))

(ert-deftest a3madkour-pub-library--render-yaml-deterministic ()
  "Same input produces byte-identical output across calls."
  (let* ((rows (list (list :slug "x" :title "X" :creator "y" :year 2024
                           :media_type "book" :status "queued"
                           :last_modified "2026-05-01" :tags '("a")))))
    (should (string= (a3madkour-pub-library-test--rows rows)
                     (a3madkour-pub-library-test--rows rows)))))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-embedded-double-quote ()
  "Embedded double-quote in string with `:' or `#' → single-quoted yaml output."
  ;; `:#` branch
  (should (equal (a3madkour-pub-library--render-scalar "He said \"hello\": fine.")
                 "'He said \"hello\": fine.'"))
  ;; URL branch
  (should (equal (a3madkour-pub-library--render-scalar "http://example.com/path?q=\"foo\"")
                 "'http://example.com/path?q=\"foo\"'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-embedded-single-quote ()
  "Embedded `'' inside a single-quoted yaml scalar is doubled to `'''."
  ;; `:#` branch with single-quote
  (should (equal (a3madkour-pub-library--render-scalar "title: It's fine.")
                 "'title: It''s fine.'"))
  ;; URL branch with single-quote
  (should (equal (a3madkour-pub-library--render-scalar "http://example.com/it's/here")
                 "'http://example.com/it''s/here'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-leading-indicator ()
  "Strings starting with `\"' or `'' are single-quoted to avoid YAML indicator confusion."
  ;; Real-world example from the bug report: \"Hello,\" He Lied.
  (should (equal (a3madkour-pub-library--render-scalar "\"Hello,\" He Lied")
                 "'\"Hello,\" He Lied'"))
  ;; Leading single-quote (embedded `'' doubled).
  (should (equal (a3madkour-pub-library--render-scalar "'tis a title")
                 "'''tis a title'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-leading-bracket ()
  "Leading `[' triggers single-quoted yaml output (would corrupt as flow-seq otherwise)."
  (should (equal (a3madkour-pub-library--render-scalar "[Insert Title Here]")
                 "'[Insert Title Here]'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-leading-asterisk ()
  "Leading `*' triggers single-quoted yaml output (would break as alias otherwise)."
  (should (equal (a3madkour-pub-library--render-scalar "*Asterisk Author*")
                 "'*Asterisk Author*'")))

(ert-deftest a3madkour-pub-library--render-scalar-quotes-leading-blockscalar ()
  "Leading `>' / `|' (block scalar indicators) trigger single-quoted output."
  (should (equal (a3madkour-pub-library--render-scalar "> Quoted Opening")
                 "'> Quoted Opening'"))
  (should (equal (a3madkour-pub-library--render-scalar "| Pipe Title")
                 "'| Pipe Title'")))

(ert-deftest a3madkour-pub-library--render-scalar-fallback-hashtable-single-quoted ()
  "Tier 4.4: the `%S' fallback wraps non-scalar values (hashtable, struct,
vector) in a YAML single-quoted scalar so the row remains parseable. Without
the wrapper the raw `%S' print form contains `#<...>' / `#s(...)' / `[...]'
sequences that PyYAML rejects."
  (let ((ht (make-hash-table :test 'equal)))
    (puthash "k" "v" ht)
    (let ((out (a3madkour-pub-library--render-scalar ht)))
      (should (string-prefix-p "'" out))
      (should (string-suffix-p "'" out)))))

(ert-deftest a3madkour-pub-library--render-scalar-fallback-vector-single-quoted ()
  "Tier 4.4: vector input falls through to the wrapped `%S' branch."
  (let ((out (a3madkour-pub-library--render-scalar [1 2 3])))
    (should (string-prefix-p "'" out))
    (should (string-suffix-p "'" out))
    ;; Single-quote-doubling rule still applies to any embedded `''.
    (should (string-match-p "1 2 3" out))))

;; -- Tier 5.2: public wrappers for author.el --

(ert-deftest a3madkour-pub-library/sections-returns-config-section-keys ()
  "Tier 5.2: `/sections' enumerates the slash-form section strings from --config."
  (let ((result (a3madkour-pub-library/sections)))
    (should (member "library/reading" result))
    (should (member "library/listening" result))
    (should (member "library/playing" result))
    (should (member "library/watching" result))
    (should (= (length result) 4))))

(ert-deftest a3madkour-pub-library/extras-for-book-returns-book-extras ()
  "Tier 5.2: `/extras-for' looks up the per-medium extras spec."
  (let ((book (a3madkour-pub-library/extras-for "book")))
    (should book)
    ;; Book extras include ISBN as the first drawer key per --extras-by-media.
    (should (equal (caar book) "ISBN"))))

(ert-deftest a3madkour-pub-library/extras-for-unknown-medium-nil ()
  "Tier 5.2: `/extras-for' returns nil for an unknown medium (not an error)."
  (should (null (a3madkour-pub-library/extras-for "bogus"))))

(defun a3madkour-pub-library-test--yaml (section row)
  "Render ROW (plist) as a SECTION shelf row."
  (a3madkour-pub-library--render-row row section))

(defun a3madkour-pub-library-test--row (&rest props)
  "A minimal valid row plist with PROPS overriding the defaults."
  (let ((row (list :slug "x" :title "Dune" :creator "Y" :year 1949
                   :last_modified "2026-05-01" :tags '("a"))))
    (while props
      (setq row (plist-put row (pop props) (pop props))))
    row))

(ert-deftest a3madkour-pub-library--render-quotes-number-looking-text ()
  "Text-typed strings that YAML reads as non-strings are single-quoted."
  (a3madkour-sections-test--with-real-site
    (should (string-match-p
             "title: '1984'"
             (a3madkour-pub-library-test--yaml
              "library/reading"
              (a3madkour-pub-library-test--row :title "1984"))))
    (should (string-match-p
             "creator: '21'"
             (a3madkour-pub-library-test--yaml
              "library/listening"
              (a3madkour-pub-library-test--row :creator "21"))))
    (should (string-match-p
             "title: '1917'"
             (a3madkour-pub-library-test--yaml
              "library/watching"
              (a3madkour-pub-library-test--row :title "1917"))))
    (should (string-match-p
             "title: 'true'"
             (a3madkour-pub-library-test--yaml
              "library/reading"
              (a3madkour-pub-library-test--row :title "true"))))
    (should (string-match-p
             "title: '-3.5'"
             (a3madkour-pub-library-test--yaml
              "library/reading"
              (a3madkour-pub-library-test--row :title "-3.5"))))
    (should (string-match-p
             "title: 'null'"
             (a3madkour-pub-library-test--yaml
              "library/reading"
              (a3madkour-pub-library-test--row :title "null"))))
    (should (string-match-p
             "title: '2026-05-01'"
             (a3madkour-pub-library-test--yaml
              "library/reading"
              (a3madkour-pub-library-test--row :title "2026-05-01"))))))

(ert-deftest a3madkour-pub-library--render-leaves-ordinary-text-unquoted ()
  (a3madkour-sections-test--with-real-site
    (should (string-match-p
             "title: Dune$"
             (a3madkour-pub-library-test--yaml
              "library/reading" (a3madkour-pub-library-test--row))))))

(ert-deftest a3madkour-pub-library--render-int-and-date-fields-stay-bare ()
  "int/date fields are never quoted, number or digit string alike."
  (a3madkour-sections-test--with-real-site
    (should (string-match-p
             "year: 1949"
             (a3madkour-pub-library-test--yaml
              "library/reading" (a3madkour-pub-library-test--row))))
    (should (string-match-p
             "year: 1949$"
             (a3madkour-pub-library-test--yaml
              "library/reading"
              (a3madkour-pub-library-test--row :year "1949"))))
    (should (string-match-p
             "last_modified: 2026-05-01$"
             (a3madkour-pub-library-test--yaml
              "library/reading" (a3madkour-pub-library-test--row))))))

(ert-deftest a3madkour-pub-library--render-extras-typed-by-contract ()
  "extras.isbn (text) quotes digit strings; int extras stay bare."
  (a3madkour-sections-test--with-real-site
    (should (string-match-p
             "isbn: '9780451524935'"
             (a3madkour-pub-library-test--yaml
              "library/reading"
              (a3madkour-pub-library-test--row
               :extras (list :isbn "9780451524935")))))
    (should (string-match-p
             "runtime_min: 120$"
             (a3madkour-pub-library-test--yaml
              "library/watching"
              (a3madkour-pub-library-test--row
               :extras (list :runtime_min 120)))))
    (should (string-match-p
             "runtime_min: 120$"
             (a3madkour-pub-library-test--yaml
              "library/watching"
              (a3madkour-pub-library-test--row
               :extras (list :runtime_min "120")))))))

(ert-deftest a3madkour-pub-library--render-unknown-key-signals ()
  "A key outside the contract is a bug, not something to swallow."
  (a3madkour-sections-test--with-real-site
    (let ((err (should-error
                (a3madkour-pub-library-test--yaml
                 "library/reading"
                 (a3madkour-pub-library-test--row
                  :extras (list :bogus_key "1"))))))
      (should (string-match-p "extras.bogus_key" (error-message-string err))))))

(provide 'a3madkour-publish-library-test)

;;; a3madkour-publish-library-test.el ends here
