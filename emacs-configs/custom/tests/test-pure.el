;;; test-pure.el --- Tier 1 tests: pure / fixture-only  -*- lexical-binding: t; -*-

(require 'test-helpers)

;;; ---- a3madkour/active-project-count ----

(ert-deftest a3madkour-test/active-project-count-empty ()
  (a3madkour-test/with-org-env '(("projects.org" . ""))
    (should (= 0 (a3madkour/active-project-count)))))

(ert-deftest a3madkour-test/active-project-count-one ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* Foo                                                       :project:active:
"))
    (should (= 1 (a3madkour/active-project-count)))))

(ert-deftest a3madkour-test/active-project-count-mixed ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* Foo                                                       :project:active:
* Bar                                                      :project:inactive:
* Baz                                                       :project:active:
"))
    (should (= 2 (a3madkour/active-project-count)))))

(ert-deftest a3madkour-test/active-project-count-skips-nested ()
  ;; Level-2 headings should never be counted even when they match the tag query
  ;; (via inheritance or explicit tags).
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* Top                                                       :project:active:
** Sub                                                      :project:active:
"))
    (should (= 1 (a3madkour/active-project-count)))))

;;; ---- a3madkour/reading-queue-active-count ----

(ert-deftest a3madkour-test/reading-queue-active-count-empty ()
  (a3madkour-test/with-org-env '(("queue.org" . ""))
    (should (= 0 (a3madkour/reading-queue-active-count)))))

(ert-deftest a3madkour-test/reading-queue-active-count-mixed ()
  (a3madkour-test/with-org-env
      '(("queue.org" . "\
* TODO Book A                                                :toread:active:
* TODO Book B                                                       :toread:
* TODO Book C                                                :toread:active:
"))
    (should (= 2 (a3madkour/reading-queue-active-count)))))

;;; ---- a3madkour/has-logbook-p ----

(ert-deftest a3madkour-test/has-logbook-p-positive ()
  (a3madkour-test/in-buffer "\
* A heading
:LOGBOOK:
CLOCK: [2026-05-09 Sat 10:00]--[2026-05-09 Sat 10:30] =>  0:30
:END:
"
    (should (a3madkour/has-logbook-p))))

(ert-deftest a3madkour-test/has-logbook-p-negative ()
  (a3madkour-test/in-buffer "\
* A heading
some body text
"
    (should-not (a3madkour/has-logbook-p))))

(ert-deftest a3madkour-test/has-logbook-p-stops-at-next-heading ()
  ;; Point on heading A — LOGBOOK belongs to heading B and should NOT match.
  (a3madkour-test/in-buffer "\
* Heading A
just body
* Heading B
:LOGBOOK:
CLOCK: [2026-05-09 Sat 10:00]--[2026-05-09 Sat 10:30] =>  0:30
:END:
"
    (should-not (a3madkour/has-logbook-p))))

;;; ---- a3madkour/get-refile-marker ----

(ert-deftest a3madkour-test/get-refile-marker-found ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "\
* Actions
* Habits
"))
    (let* ((file (a3madkour/org-file "actions.org"))
           (marker (a3madkour/get-refile-marker file "Habits")))
      (should (markerp marker))
      (with-current-buffer (marker-buffer marker)
        (goto-char marker)
        (should (looking-at "^\\* Habits"))))))

(ert-deftest a3madkour-test/get-refile-marker-not-found ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Actions\n"))
    (should-error
     (a3madkour/get-refile-marker (a3madkour/org-file "actions.org") "Nonexistent"))))

;;; ---- a3madkour/get-current-season ----

(ert-deftest a3madkour-test/get-current-season-with-name-and-tags ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* Current Season: Spring 2026                                    :foo:bar:
"))
    (should (equal "Spring 2026" (a3madkour/get-current-season)))))

(ert-deftest a3madkour-test/get-current-season-no-tags ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "* Current Season: Quiet Time\n"))
    (should (equal "Quiet Time" (a3madkour/get-current-season)))))

(ert-deftest a3madkour-test/get-current-season-absent ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "* Some Project                                     :project:active:\n"))
    (should (equal "No season set" (a3madkour/get-current-season)))))

;;; ---- a3madkour/get-current-season-tags ----

(ert-deftest a3madkour-test/get-current-season-tags-with-tags ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* Current Season: Spring 2026                                    :foo:bar:
"))
    (should (equal '("foo" "bar") (a3madkour/get-current-season-tags)))))

(ert-deftest a3madkour-test/get-current-season-tags-no-tags ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "* Current Season: Quiet Time\n"))
    (should (null (a3madkour/get-current-season-tags)))))

(ert-deftest a3madkour-test/get-current-season-tags-no-season ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "* Random heading\n"))
    (should (null (a3madkour/get-current-season-tags)))))

;;; ---- a3madkour/get-habit-tags ----

(ert-deftest a3madkour-test/get-habit-tags-basic ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "\
* Habit A                                                       :tag1:tag2:
:PROPERTIES:
:STYLE: habit
:END:

* Habit B                                                       :tag2:tag3:
:PROPERTIES:
:STYLE: habit
:END:

* Plain task                                                          :tag4:
:PROPERTIES:
:ENERGY: high
:END:
"))
    (let ((tags (a3madkour/get-habit-tags)))
      (should (equal (sort (copy-sequence tags) #'string<)
                     '("tag1" "tag2" "tag3"))))))

(ert-deftest a3madkour-test/get-habit-tags-no-habits ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Plain task                                                          :tag4:\n"))
    (should (null (a3madkour/get-habit-tags)))))

(provide 'test-pure)
;;; test-pure.el ends here
