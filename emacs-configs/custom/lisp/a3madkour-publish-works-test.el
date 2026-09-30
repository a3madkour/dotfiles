;;; a3madkour-publish-works-test.el --- tests for the works handler  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-works)

(defun a3madkour-pub-works-test--parse (org-text)
  "Parse ORG-TEXT and return its element AST."
  (with-temp-buffer (insert org-text) (org-mode) (org-element-parse-buffer)))

(ert-deftest a3madkour-pub-works--module-loads ()
  (should (fboundp 'a3madkour-pub-works/publish-works-file)))

(ert-deftest a3madkour-pub-works--parse-tracks-basic ()
  (let* ((ast (a3madkour-pub-works-test--parse "
#+NAME: tracks
| title     | duration |
|-----------+----------|
| Lorem One | 3:14     |
| Lorem Two | 4:20     |
"))
         (tracks (a3madkour-pub-works--parse-tracks ast)))
    (should (equal (length tracks) 2))
    (should (equal (alist-get 'title (car tracks)) "Lorem One"))
    (should (equal (alist-get 'duration (car tracks)) "3:14"))
    (should (equal (alist-get 'duration (nth 1 tracks)) "4:20"))))

(ert-deftest a3madkour-pub-works--parse-tracks-absent-is-nil ()
  (should (null (a3madkour-pub-works--parse-tracks
                 (a3madkour-pub-works-test--parse "Just a body.")))))

;; Review Focus #4 — header row only must yield nil, not an empty list,
;; so the key is omitted rather than emitted as `tracks: []'.
(ert-deftest a3madkour-pub-works--parse-tracks-header-only-is-nil ()
  (should (null (a3madkour-pub-works--parse-tracks
                 (a3madkour-pub-works-test--parse "
#+NAME: tracks
| title | duration |
|-------+----------|
")))))

(ert-deftest a3madkour-pub-works--parse-tracks-trims-cells ()
  (let ((tracks (a3madkour-pub-works--parse-tracks
                 (a3madkour-pub-works-test--parse "
#+NAME: tracks
| title       | duration |
|-------------+----------|
|   Padded    |   1:05   |
"))))
    (should (equal (alist-get 'title (car tracks)) "Padded"))))

;; Guard mutation test: verify both-empty-drop logic at line 61 (and vs or).
;; Row with title but empty duration is kept; row with both empty is dropped.
(ert-deftest a3madkour-pub-works--parse-tracks-filters-all-empty-rows ()
  (let ((tracks (a3madkour-pub-works--parse-tracks
                 (a3madkour-pub-works-test--parse "
#+NAME: tracks
| title      | duration |
|------------+----------|
| Song One   |          |
|            |          |
| Song Two   | 2:30     |
"))))
    (should (equal (length tracks) 2))
    (should (equal (alist-get 'title (car tracks)) "Song One"))
    (should (equal (alist-get 'duration (car tracks)) ""))
    (should (equal (alist-get 'title (nth 1 tracks)) "Song Two"))
    (should (equal (alist-get 'duration (nth 1 tracks)) "2:30"))))

(ert-deftest a3madkour-pub-works--renders-tracks-block ()
  (let ((out (a3madkour-pub-works--render-frontmatter
              '((title . "M")
                (tracks . (((title . "Lorem One") (duration . "3:14"))
                           ((title . "Lorem Two") (duration . "4:20"))))))))
    (should (string-match-p "tracks:\n" out))
    (should (string-match-p
             "  - { title: \"Lorem One\", duration: \"3:14\" }" out))
    (should (string-match-p
             "  - { title: \"Lorem Two\", duration: \"4:20\" }" out))))

(ert-deftest a3madkour-pub-works--renders-platform-embed-map ()
  (let ((out (a3madkour-pub-works--render-frontmatter
              '((title . "M")
                (platform_embed . ((kind . "bandcamp")
                                   (url . "https://example.bandcamp.com/album/x")))))))
    (should (string-match-p
             "platform_embed: { kind: bandcamp, url: \"https://example.bandcamp.com/album/x\" }"
             out))))

(ert-deftest a3madkour-pub-works--omits-empty-structured-keys ()
  (let ((out (a3madkour-pub-works--render-frontmatter
              '((title . "M") (tracks . nil) (platform_embed . nil)))))
    (should-not (string-match-p "tracks:" out))
    (should-not (string-match-p "platform_embed:" out))))

;; Strengthened from the brief's draft: the brief only asserted the absence
;; of the *unescaped* line, which passes trivially if rendering changes
;; shape for an unrelated reason.  This pins the actual escaped output that
;; `a3madkour-pub/yaml-escape-scalar' produces (backslash-quote each `"'),
;; so the test fails if escaping regresses to no-op, double-escapes, or
;; drops a character -- not just if the naive unescaped form reappears.
(ert-deftest a3madkour-pub-works--escapes-quotes-in-track-titles ()
  (let ((out (a3madkour-pub-works--render-frontmatter
              '((title . "M")
                (tracks . (((title . "He said \"hi\"") (duration . "1:00"))))))))
    (should-not (string-match-p "title: \"He said \"hi\"\"" out))
    (should (string-match-p
             (regexp-quote
              "  - { title: \"He said \\\"hi\\\"\", duration: \"1:00\" }")
             out))))

(provide 'a3madkour-publish-works-test)

;;; a3madkour-publish-works-test.el ends here
