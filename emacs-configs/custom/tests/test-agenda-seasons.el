;;; test-agenda-seasons.el --- Tier 2: agenda + season  -*- lexical-binding: t; -*-

(require 'test-helpers)

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

;;; ---- tag validation ----

(ert-deftest a3madkour-test/valid-tag-p ()
  (dolist (ok '("rust" "side_project" "a@b" "x1"))
    (should (a3madkour/-valid-tag-p ok)))
  (dolist (bad '("deep work" "side-project" "" "a:b"))
    (should-not (a3madkour/-valid-tag-p bad))))

(ert-deftest a3madkour-test/read-tags-done-is-first-candidate ()
  (let (seen)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_p coll &rest _) (setq seen coll) "-- Done --")))
      (a3madkour/-read-tags "Tags" '("tag1" "tag2")))
    (should (equal (seq-take seen 4)
                   '("-- Done --" "-- Enter new tag --" "tag1" "tag2")))))

(ert-deftest a3madkour-test/read-tags-rejects-invalid-new-tag ()
  (cl-letf (((symbol-function 'completing-read)
             (a3madkour-test/queue '("-- Enter new tag --" "-- Done --")))
            ((symbol-function 'read-string)
             (a3madkour-test/queue '("deep work")))
            ((symbol-function 'message) (lambda (&rest _) nil)))
    (should (null (a3madkour/-read-tags "Tags" '("tag1"))))))

(ert-deftest a3madkour-test/read-tags-rejects-invalid-free-typed ()
  (cl-letf (((symbol-function 'completing-read)
             (a3madkour-test/queue '("side-project" "rust" "-- Done --")))
            ((symbol-function 'message) (lambda (&rest _) nil)))
    (should (equal '("rust") (a3madkour/-read-tags "Tags" '("tag1"))))))

;;; ---- a3madkour/setup-agenda-commands ----

;;; ---- dashboard ----

(defun a3madkour-test/-group-names (groups)
  (mapcar (lambda (g) (or (plist-get g :name) (car g))) groups))

(ert-deftest a3madkour-test/dashboard-groups-order-with-season ()
  (cl-letf (((symbol-function 'a3madkour/current-season)
             (lambda () '(:status ok :name "S" :tags ("foo" "bar")))))
    (let ((groups (a3madkour/-dashboard-groups)))
      (should (equal '("⏰ Scheduled" "🔁 Core Habits" "🔁 Seasonal Habits"
                       "🔁 Untagged Habits" :discard "⚠️ Overdue")
                     (a3madkour-test/-group-names groups)))
      (should (equal '(:habit t) (plist-get (nth 4 groups) :discard)))
      (should (string-match-p (regexp-quote ":tag (\"foo\" \"bar\")")
                              (prin1-to-string (nth 2 groups)))))))

(ert-deftest a3madkour-test/dashboard-groups-without-season-tags ()
  (dolist (season '((:status ok :name "S" :tags nil)
                    (:status no-file)
                    (:status no-heading)))
    (cl-letf (((symbol-function 'a3madkour/current-season)
               (lambda () season)))
      (should (equal '("⏰ Scheduled" "🔁 Core Habits"
                       "🔁 Untagged Habits" :discard "⚠️ Overdue")
                     (a3madkour-test/-group-names
                      (a3madkour/-dashboard-groups)))))))

(ert-deftest a3madkour-test/dashboard-overdue-is-not-filtered-by-tag ()
  (cl-letf (((symbol-function 'a3madkour/current-season)
             (lambda () '(:status ok :name "S" :tags ("foo")))))
    (let ((dump (prin1-to-string (a3madkour/-dashboard-groups)))
          (count 0) (start 0))
      (while (string-match ":discard" dump start)
        (setq count (1+ count) start (match-end 0)))
      (should (= 1 count)))))

(ert-deftest a3madkour-test/untagged-habit-predicate ()
  (should (a3madkour/-untagged-p "item"))
  (should-not (a3madkour/-untagged-p (propertize "item" 'tags '("x")))))

(ert-deftest a3madkour-test/setup-agenda-commands-reads-no-file ()
  (cl-letf (((symbol-function 'a3madkour/current-season)
             (lambda () (error "read at setup"))))
    (let ((org-agenda-custom-commands nil))
      (a3madkour/setup-agenda-commands)
      (let ((dump (prin1-to-string (assoc "d" org-agenda-custom-commands))))
        (should (string-match-p "a3madkour/-dashboard-groups" dump))
        (should (string-match-p "a3madkour/-dashboard-header" dump))))))

(defconst a3madkour-test/-now (encode-time 0 0 12 1 1 2027))

(defun a3madkour-test/-notices-match (season regexp)
  (cl-some (lambda (n) (string-match-p regexp n))
           (a3madkour/-season-notices season a3madkour-test/-now)))

(ert-deftest a3madkour-test/season-notices-no-file ()
  (let ((n (a3madkour/-season-notices '(:status no-file) a3madkour-test/-now)))
    (dolist (r '("No current season" "projects.org not found" "rotate-season"))
      (should (cl-some (lambda (x) (string-match-p r x)) n)))))

(ert-deftest a3madkour-test/season-notices-no-heading ()
  (let ((n (a3madkour/-season-notices '(:status no-heading) a3madkour-test/-now)))
    (dolist (r '("No current season" "Current Season" "rotate-season"))
      (should (cl-some (lambda (x) (string-match-p r x)) n)))))

(ert-deftest a3madkour-test/season-notices-no-tags ()
  (should (a3madkour-test/-notices-match '(:status ok :name "S" :tags nil)
                                         "no tags")))

(ert-deftest a3madkour-test/season-notices-ended ()
  (should (a3madkour-test/-notices-match
           '(:status ok :name "S" :tags ("x") :end "[2026-12-26 Sat]")
           "ended")))

(ert-deftest a3madkour-test/season-notices-bad-or-missing-end ()
  (dolist (end '(nil "garbage"))
    (should-not (a3madkour-test/-notices-match
                 `(:status ok :name "S" :tags ("x") :end ,end) "ended"))))

(ert-deftest a3madkour-test/season-notices-healthy ()
  (should-not (a3madkour/-season-notices
               '(:status ok :name "S" :tags ("x") :end "[2027-02-01 Mon]")
               a3madkour-test/-now)))

(ert-deftest a3madkour-test/dashboard-header-shows-name-and-notices ()
  (cl-letf (((symbol-function 'a3madkour/current-season)
             (lambda () '(:status ok :name "Rust" :tags nil))))
    (let ((h (a3madkour/-dashboard-header)))
      (should (string-match-p "Season: Rust" h))
      (should (string-match-p "⚠ .*no tags" h))
      (should (string-suffix-p "\n" h)))))

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
               (lambda () '("new1" "new2"))))
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

(ert-deftest a3madkour-test/rotate-season-in-narrowed-buffer ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* Current Season: Old Season                                          :old:
:PROPERTIES:
:START: [2025-12-01 Mon]
:END:   [2026-01-15 Thu]
:END:
* Some project                                              :project:active:
"))
    (a3madkour-test/in-org-file "projects.org"
      (re-search-forward "^\\* Some project")
      (org-narrow-to-subtree))
    (cl-letf (((symbol-function 'read-string)
               (a3madkour-test/queue '("Spring 2026" "Done")))
              ((symbol-function 'read-number) (lambda (&rest _) 6))
              ((symbol-function 'a3madkour/select-season-tags)
               (lambda () nil)))
      (a3madkour/rotate-season))
    (a3madkour-test/in-org-file "projects.org"
      (widen)
      (let ((content (buffer-string)))
        (should (= 1 (with-temp-buffer (insert content) (goto-char (point-min))
                                       (let ((n 0)) (while (re-search-forward "^\\* Current Season:" nil t) (cl-incf n)) n))))
        (should (= 1 (with-temp-buffer (insert content) (goto-char (point-min))
                                       (let ((n 0)) (while (re-search-forward "^\\* ARCHIVE Season:" nil t) (cl-incf n)) n))))))))

(ert-deftest a3madkour-test/rotate-season-no-existing-season ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "* Some project                                    :project:active:\n"))
    (cl-letf (((symbol-function 'read-string)
               (a3madkour-test/queue '("First Season")))
              ((symbol-function 'read-number)
               (lambda (&rest _) 6))
              ((symbol-function 'a3madkour/select-season-tags)
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
