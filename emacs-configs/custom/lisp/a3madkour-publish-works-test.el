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

(provide 'a3madkour-publish-works-test)

;;; a3madkour-publish-works-test.el ends here
