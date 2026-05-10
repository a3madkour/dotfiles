;;; test-tasks-scheduling.el --- Tier 2: tasks and scheduling  -*- lexical-binding: t; -*-

(require 'test-helpers)

(defmacro a3madkour-test/in-org-file (rel-path &rest body)
  (declare (indent 1) (debug t))
  `(with-current-buffer (find-file-noselect (a3madkour/org-file ,rel-path))
     (goto-char (point-min))
     ,@body))

;;; ---- a3madkour/force-time-after-todo ----

(ert-deftest a3madkour-test/force-time-after-todo-creates-logbook ()
  (a3madkour-test/in-buffer "* TODO A task\n"
    (re-search-forward "TODO")
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "0:30")))
      (let ((org-state "DONE"))
        (a3madkour/force-time-after-todo)))
    (org-back-to-heading t)
    (should (a3madkour/has-logbook-p))))

(ert-deftest a3madkour-test/force-time-after-todo-skips-habit ()
  (a3madkour-test/in-buffer "\
* TODO A habit
:PROPERTIES:
:STYLE: habit
:END:
"
    (re-search-forward "TODO")
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) (error "should not prompt for habits"))))
      (let ((org-state "DONE"))
        (a3madkour/force-time-after-todo)))
    (should-not (a3madkour/has-logbook-p))))

(ert-deftest a3madkour-test/force-time-after-todo-skips-empty-duration ()
  (a3madkour-test/in-buffer "* TODO A task\n"
    (re-search-forward "TODO")
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "")))
      (let ((org-state "DONE"))
        (a3madkour/force-time-after-todo)))
    (should-not (a3madkour/has-logbook-p))))

(ert-deftest a3madkour-test/force-time-after-todo-noop-when-not-done ()
  (a3madkour-test/in-buffer "* TODO A task\n"
    (re-search-forward "TODO")
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) (error "should not prompt when not DONE"))))
      (let ((org-state "TODO"))
        (a3madkour/force-time-after-todo)))
    (should-not (a3madkour/has-logbook-p))))

;;; ---- a3madkour/reset-checkboxes-on-repeat ----

(ert-deftest a3madkour-test/reset-checkboxes-on-repeat-resets ()
  (a3madkour-test/in-buffer "\
* TODO Repeat task
SCHEDULED: <2026-05-10 Sun +1d>
- [X] Item A
- [X] Item B
"
    (re-search-forward "TODO")
    (let ((org-state "DONE")
          (org-done-keywords '("DONE")))
      (a3madkour/reset-checkboxes-on-repeat))
    (should (string-match-p "- \\[ \\] Item A" (buffer-string)))
    (should (string-match-p "- \\[ \\] Item B" (buffer-string)))))

(ert-deftest a3madkour-test/reset-checkboxes-on-repeat-noop-no-repeater ()
  (a3madkour-test/in-buffer "\
* TODO Plain task
- [X] Item A
"
    (re-search-forward "TODO")
    (let ((org-state "DONE")
          (org-done-keywords '("DONE")))
      (a3madkour/reset-checkboxes-on-repeat))
    (should (string-match-p "- \\[X\\] Item A" (buffer-string)))))

;;; ---- a3madkour/ignore-checkbox-blocking-for-agenda ----

(ert-deftest a3madkour-test/ignore-checkbox-blocking-rebinds-var ()
  (let ((org-enforce-todo-checkbox-dependencies t)
        (observed 'unset))
    (a3madkour/ignore-checkbox-blocking-for-agenda
     (lambda (&rest _)
       (setq observed org-enforce-todo-checkbox-dependencies)))
    (should (null observed))
    ;; Original value restored after advice exits.
    (should (eq t org-enforce-todo-checkbox-dependencies))))

;;; ---- a3madkour/add-new-org-datetree-headline ----

(ert-deftest a3madkour-test/add-new-org-datetree-headline-creates ()
  (a3madkour-test/in-buffer ""
    (let ((title (a3madkour/add-new-org-datetree-headline "2026-05-10")))
      (should (stringp title))
      (should (string-match-p "2026-05-10" title)))
    (let ((content (buffer-string)))
      (should (string-match-p "^\\* 2026" content))
      (should (string-match-p "^\\*\\* 2026-05" content))
      (should (string-match-p "^\\*\\*\\* 2026-05-10" content)))))

(ert-deftest a3madkour-test/add-new-org-datetree-headline-idempotent ()
  (a3madkour-test/in-buffer ""
    (a3madkour/add-new-org-datetree-headline "2026-05-10")
    (let ((before (buffer-string)))
      (a3madkour/add-new-org-datetree-headline "2026-05-10")
      (should (equal before (buffer-string))))))

;;; ---- a3madkour/org-insert-subheading-respect-content ----

(ert-deftest a3madkour-test/org-insert-subheading-respect-content-smoke ()
  (a3madkour-test/in-buffer "\
* H1
body1
** H1.1
body11
"
    (goto-char (point-min))
    (re-search-forward "^\\* H1")
    ;; Just verify the function doesn't error and inserts something.
    (a3madkour/org-insert-subheading-respect-content)
    ;; A new heading was inserted somewhere in the buffer.
    (goto-char (point-min))
    (should (> (length (split-string (buffer-string) "^\\*+ " t)) 2))))

;;; ---- a3madkour/set-task-properties ----

(ert-deftest a3madkour-test/set-task-properties-both ()
  (a3madkour-test/in-buffer "* TODO Foo\n"
    (re-search-forward "TODO")
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "high"))
              ((symbol-function 'read-string) (lambda (&rest _) "0:30")))
      (a3madkour/set-task-properties))
    (org-back-to-heading t)
    (should (equal "high" (org-entry-get nil "ENERGY")))
    (should (equal "0:30" (org-entry-get nil "EFFORT")))))

(ert-deftest a3madkour-test/set-task-properties-empty-effort ()
  (a3madkour-test/in-buffer "* TODO Foo\n"
    (re-search-forward "TODO")
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "low"))
              ((symbol-function 'read-string) (lambda (&rest _) "")))
      (a3madkour/set-task-properties))
    (org-back-to-heading t)
    (should (equal "low" (org-entry-get nil "ENERGY")))
    (should (null (org-entry-get nil "EFFORT")))))

;;; ---- a3madkour/add-scheduled-todo ----

(ert-deftest a3madkour-test/add-scheduled-todo-creates-and-schedules ()
  (a3madkour-test/in-buffer "* Existing heading\n"
    (cl-letf (((symbol-function 'org-read-date) (lambda (&rest _) "2026-05-15"))
              ;; Stub call-interactively to skip org-set-effort prompt.
              ((symbol-function 'call-interactively) (lambda (&rest _) nil)))
      (a3madkour/add-scheduled-todo))
    (let ((content (buffer-string)))
      (should (string-match-p "^\\* TODO" content))
      (should (string-match-p "SCHEDULED:.*2026-05-15" content)))))

;;; ---- a3madkour/refile-to + a3madkour/refile-and-schedule ----

(ert-deftest a3madkour-test/refile-to-moves-and-schedules ()
  (a3madkour-test/with-org-env
      '(("source.org" . "* TODO Move me\n")
        ("target.org" . "* Destination\n"))
    (a3madkour-test/in-org-file "source.org"
      (re-search-forward "Move me")
      (org-back-to-heading t)
      (a3madkour/refile-to (a3madkour/org-file "target.org")
                           "Destination"
                           "2026-05-15"))
    ;; Source no longer has the heading
    (let ((src-content
           (with-current-buffer
               (find-file-noselect (a3madkour/org-file "source.org"))
             (buffer-string))))
      (should-not (string-match-p "Move me" src-content)))
    ;; Target has it under Destination, scheduled
    (let ((tgt-content
           (with-current-buffer
               (find-file-noselect (a3madkour/org-file "target.org"))
             (buffer-string))))
      (should (string-match-p "Move me" tgt-content))
      (should (string-match-p "SCHEDULED:.*2026-05-15" tgt-content))
      ;; Destination heading itself must NOT have been scheduled.
      (with-current-buffer
          (find-file-noselect (a3madkour/org-file "target.org"))
        (goto-char (point-min))
        (re-search-forward "^\\* Destination")
        (forward-line 1)
        (should-not (looking-at ".*SCHEDULED:.*"))))))

(ert-deftest a3madkour-test/refile-to-unknown-headline ()
  (a3madkour-test/with-org-env
      '(("source.org" . "* TODO Move me\n")
        ("target.org" . "* SomeOtherHeading\n"))
    (a3madkour-test/in-org-file "source.org"
      (re-search-forward "Move me")
      (org-back-to-heading t)
      (should-error
       (a3madkour/refile-to (a3madkour/org-file "target.org")
                            "Destination"
                            "2026-05-15")
       :type 'user-error))))

(ert-deftest a3madkour-test/refile-and-schedule-uses-datetree ()
  (a3madkour-test/with-org-env
      '(("notes.org" . "* TODO Move me\n"))
    (a3madkour-test/in-org-file "notes.org"
      (re-search-forward "Move me")
      (cl-letf (((symbol-function 'org-read-date)
                 (lambda (&rest _) "2026-05-15")))
        (a3madkour/refile-and-schedule)))
    (let ((content
           (with-current-buffer
               (find-file-noselect (a3madkour/org-file "notes.org"))
             (buffer-string))))
      (should (string-match-p "^\\* 2026" content))
      (should (string-match-p "Move me" content))
      (should (string-match-p "SCHEDULED:.*2026-05-15" content)))))

(provide 'test-tasks-scheduling)
;;; test-tasks-scheduling.el ends here
