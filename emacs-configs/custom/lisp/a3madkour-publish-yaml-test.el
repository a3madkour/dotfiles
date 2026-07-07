;;; a3madkour-publish-yaml-test.el --- Tests for shared YAML rendering (P3.1) -*- lexical-binding: t; -*-
;;; Code:

(require 'ert)
(require 'a3madkour-publish-yaml)

(ert-deftest a3madkour-pub-yaml-test/render-value-scalars ()
  "Strings quoted+escaped, dates unquoted, numbers/booleans/lists."
  (should (equal (a3madkour-pub-yaml/render-value "hello") "\"hello\""))
  (should (equal (a3madkour-pub-yaml/render-value "The \"x\" y") "\"The \\\"x\\\" y\""))
  (should (equal (a3madkour-pub-yaml/render-value "2026-05-25") "2026-05-25"))
  (should (equal (a3madkour-pub-yaml/render-value 42) "42"))
  (should (equal (a3madkour-pub-yaml/render-value t) "true"))
  (should (equal (a3madkour-pub-yaml/render-value nil) "false"))
  (should (equal (a3madkour-pub-yaml/render-value '("a" "b")) "[\"a\", \"b\"]")))

(ert-deftest a3madkour-pub-yaml-test/render-value-strict-list ()
  "STRICT-STRING-LIST signals on a non-string element; permissive by default."
  (should-error (a3madkour-pub-yaml/render-value '("a" 3) t))
  ;; Non-strict silently formats (matches garden/essays/poetry).
  (should (a3madkour-pub-yaml/render-value '("a" "b"))))

(ert-deftest a3madkour-pub-yaml-test/render-frontmatter-plain ()
  "No hook → alphabetical `key: value' lines with --- delimiters."
  (should (equal (a3madkour-pub-yaml/render-frontmatter
                  '((title . "Z") (draft . nil)))
                 "---\ndraft: false\ntitle: \"Z\"\n---\n")))

(ert-deftest a3madkour-pub-yaml-test/render-frontmatter-key-hook-line-and-omit ()
  "KEY-HOOK may substitute a full line, or omit a key."
  (let ((hook (lambda (k v)
                (cond ((and (eq k 'tags) (null v)) "tags: []")
                      ((eq k 'drop) :omit)))))
    (should (equal (a3madkour-pub-yaml/render-frontmatter
                    '((tags . nil) (drop . "x") (title . "T")) :key-hook hook)
                   "---\ntags: []\ntitle: \"T\"\n---\n"))))

(ert-deftest a3madkour-pub-yaml-test/render-frontmatter-value-fn ()
  "VALUE-FN customizes bare-value rendering (research's strict variant)."
  (should-error
   (a3madkour-pub-yaml/render-frontmatter
    '((xs . ("a" 3)))
    :value-fn (lambda (v) (a3madkour-pub-yaml/render-value v t)))))

(provide 'a3madkour-publish-yaml-test)
;;; a3madkour-publish-yaml-test.el ends here
