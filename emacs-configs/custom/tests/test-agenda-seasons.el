;;; test-agenda-seasons.el --- Tier 2: agenda + season  -*- lexical-binding: t; -*-

(require 'test-helpers)

(defmacro a3madkour-test/in-org-file (rel-path &rest body)
  (declare (indent 1) (debug t))
  `(with-current-buffer (find-file-noselect (a3madkour/org-file ,rel-path))
     (goto-char (point-min))
     ,@body))

;;; ---- a3madkour/select-season-tags ----

(ert-deftest a3madkour-test/select-season-tags-picks-existing ()
  (cl-letf (((symbol-function 'a3madkour/get-habit-tags)
             (lambda () '("tag1" "tag2" "tag3")))
            ((symbol-function 'completing-read)
             (a3madkour-test/queue '("tag1" "tag2" "-- Done --"))))
    (should (equal '("tag1" "tag2") (a3madkour/select-season-tags)))))

(ert-deftest a3madkour-test/select-season-tags-new-tag ()
  (cl-letf (((symbol-function 'a3madkour/get-habit-tags)
             (lambda () '("tag1")))
            ((symbol-function 'completing-read)
             (a3madkour-test/queue '("-- Enter new tag --" "-- Done --")))
            ((symbol-function 'read-string)
             (a3madkour-test/queue '("newtag"))))
    (should (equal '("newtag") (a3madkour/select-season-tags)))))

(ert-deftest a3madkour-test/select-season-tags-empty ()
  (cl-letf (((symbol-function 'a3madkour/get-habit-tags) (lambda () '()))
            ((symbol-function 'completing-read)
             (a3madkour-test/queue '("-- Done --"))))
    (should (null (a3madkour/select-season-tags)))))

(ert-deftest a3madkour-test/select-season-tags-no-duplicates ()
  (cl-letf (((symbol-function 'a3madkour/get-habit-tags)
             (lambda () '("tag1" "tag2")))
            ((symbol-function 'completing-read)
             (a3madkour-test/queue '("tag1" "tag1" "-- Done --"))))
    ;; The function removes already-selected tags from the offered list,
    ;; so the second "tag1" would not appear; but even if user typed it,
    ;; the unless-member guard prevents duplicates.
    (should (equal '("tag1") (a3madkour/select-season-tags)))))

;;; ---- a3madkour/setup-agenda-commands ----

(ert-deftest a3madkour-test/setup-agenda-commands-with-season-tags ()
  (cl-letf (((symbol-function 'a3madkour/get-current-season-tags)
             (lambda () '("foo" "bar")))
            ((symbol-function 'a3madkour/get-current-season)
             (lambda () "Spring 2026")))
    (let ((org-agenda-custom-commands nil))
      (a3madkour/setup-agenda-commands)
      (let* ((dashboard (assoc "d" org-agenda-custom-commands))
             (dump (prin1-to-string dashboard)))
        (should dashboard)
        ;; The Seasonal Habits group must include the OR-joined tag glob
        (should (string-match-p "Seasonal Habits" dump))
        (should (string-match-p "foo|bar" dump))
        (should (string-match-p "Core Habits" dump))
        (should (string-match-p "Overdue" dump))))))

(ert-deftest a3madkour-test/setup-agenda-commands-without-season-tags ()
  (cl-letf (((symbol-function 'a3madkour/get-current-season-tags)
             (lambda () nil))
            ((symbol-function 'a3madkour/get-current-season)
             (lambda () "No season set")))
    (let ((org-agenda-custom-commands nil))
      (a3madkour/setup-agenda-commands)
      (let* ((dashboard (assoc "d" org-agenda-custom-commands))
             (dump (prin1-to-string dashboard)))
        (should dashboard)
        ;; No Seasonal Habits group when there are no tags
        (should-not (string-match-p "Seasonal Habits" dump))
        ;; Core Habits and Overdue still present
        (should (string-match-p "Core Habits" dump))
        (should (string-match-p "Overdue" dump))))))

;;; ---- a3madkour/rotate-season ----

(ert-deftest a3madkour-test/rotate-season-archives-and-replaces ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* Current Season: Old Season                                          :old:
:PROPERTIES:
:START: [2025-12-01 Mon]
:END:   [2026-01-15 Thu]
:END:
* Some project                                              :project:active:
"))
    (cl-letf (((symbol-function 'read-string)
               (a3madkour-test/queue '("Spring 2026"
                                       "Got some things done")))
              ((symbol-function 'read-number)
               (lambda (&rest _) 6))
              ((symbol-function 'a3madkour/select-season-tags)
               (lambda () '("new1" "new2")))
              ((symbol-function 'a3madkour/setup-agenda-commands)
               (lambda () nil)))
      (a3madkour/rotate-season))
    (a3madkour-test/in-org-file "projects.org"
      (let ((content (buffer-string)))
        ;; Old season heading renamed to ARCHIVE Season:
        (should (string-match-p "^\\* ARCHIVE Season: Old Season" content))
        ;; Old season has ACCOMPLISHED property
        (should (string-match-p ":ACCOMPLISHED: +Got some things done" content))
        ;; New current season heading present with tags
        (should (string-match-p "^\\* Current Season: Spring 2026" content))
        (should (string-match-p ":new1:new2:" content))
        ;; Existing project untouched
        (should (string-match-p "^\\* Some project" content))))))

(ert-deftest a3madkour-test/rotate-season-no-existing-season ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "* Some project                                    :project:active:\n"))
    (cl-letf (((symbol-function 'read-string)
               (a3madkour-test/queue '("First Season")))
              ((symbol-function 'read-number)
               (lambda (&rest _) 6))
              ((symbol-function 'a3madkour/select-season-tags)
               (lambda () nil))
              ((symbol-function 'a3madkour/setup-agenda-commands)
               (lambda () nil)))
      (a3madkour/rotate-season))
    (a3madkour-test/in-org-file "projects.org"
      (let ((content (buffer-string)))
        (should (string-match-p "^\\* Current Season: First Season" content))
        (should-not (string-match-p "ARCHIVE Season:" content))
        ;; No tag-string appended to the season heading itself.
        (goto-char (point-min))
        (re-search-forward "^\\* Current Season: First Season.*$")
        (should-not (string-match-p ":[a-z]+:" (match-string 0)))))))

(provide 'test-agenda-seasons)
;;; test-agenda-seasons.el ends here
