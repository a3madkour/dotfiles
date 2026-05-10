;;; test-inbox.el --- Tier 2: inbox triage  -*- lexical-binding: t; -*-

(require 'test-helpers)

(defmacro a3madkour-test/in-org-file (rel-path &rest body)
  (declare (indent 1) (debug t))
  `(with-current-buffer (find-file-noselect (a3madkour/org-file ,rel-path))
     (goto-char (point-min))
     ,@body))

;;; ---- a3madkour/inbox-delete ----

(ert-deftest a3madkour-test/inbox-delete-removes-subtree ()
  (a3madkour-test/in-buffer "\
* TODO Item to delete
* TODO Other item
"
    (re-search-forward "Item to delete")
    (org-back-to-heading t)
    (a3madkour/inbox-delete)
    (let ((content (buffer-string)))
      (should-not (string-match-p "Item to delete" content))
      (should (string-match-p "Other item" content)))))

;;; ---- a3madkour/inbox-to-org-roam ----

(ert-deftest a3madkour-test/inbox-to-org-roam-defers-cut-until-finalize ()
  ;; Bug-fix regression: cut should happen on finalize, not immediately.
  (a3madkour-test/in-buffer "\
* TODO Send me to roam
body text here
"
    (re-search-forward "Send me")
    (let ((captured-templates nil))
      (cl-letf (((symbol-function 'org-roam-capture-)
                 (lambda (&rest args) (setq captured-templates args))))
        (a3madkour/inbox-to-org-roam))
      ;; Subtree still present (deferred)
      (should (string-match-p "Send me to roam" (buffer-string)))
      ;; org-roam-capture- was called
      (should captured-templates)
      ;; Body text is included in the captured template
      (should (string-match-p "body text here"
                              (prin1-to-string captured-templates))))
    ;; Simulate successful finalize
    (let ((org-note-abort nil))
      (a3madkour--inbox-to-roam-finalize))
    (should-not (string-match-p "Send me to roam" (buffer-string)))))

(ert-deftest a3madkour-test/inbox-to-org-roam-preserves-on-abort ()
  ;; If the user aborts capture, the inbox subtree must remain.
  (a3madkour-test/in-buffer "\
* TODO Send me to roam
body text
"
    (re-search-forward "Send me")
    (cl-letf (((symbol-function 'org-roam-capture-) (lambda (&rest _) nil)))
      (a3madkour/inbox-to-org-roam))
    ;; Simulate abort (org-note-abort = t)
    (let ((org-note-abort t))
      (a3madkour--inbox-to-roam-finalize))
    ;; Inbox subtree must still be present
    (should (string-match-p "Send me to roam" (buffer-string)))))

(ert-deftest a3madkour-test/inbox-to-org-roam-empty-body-template ()
  ;; Empty body produces "%?" only; non-empty body wraps as "<body>\n\n%?"
  (a3madkour-test/in-buffer "* TODO No body item\n"
    (re-search-forward "No body")
    (let ((captured-templates nil))
      (cl-letf (((symbol-function 'org-roam-capture-)
                 (lambda (&rest args) (setq captured-templates args))))
        (a3madkour/inbox-to-org-roam))
      (let ((dump (prin1-to-string captured-templates)))
        (should (string-match-p "\"%\\?\"" dump))))))

;;; ---- a3madkour/inbox-to-someday ----

(ert-deftest a3madkour-test/inbox-to-someday-default-parking-lot ()
  (a3madkour-test/with-org-env
      '(("someday.org" . "* Parking Lot\n* Books\n"))
    ;; Open the someday buffer so org-refile can locate the heading
    (find-file-noselect (a3madkour/org-file "someday.org"))
    (let ((inbox-buf
           (find-file-noselect
            (let ((f (a3madkour/org-file "inbox.org")))
              (with-temp-file f (insert "* TODO Maybe later\n"))
              f))))
      (with-current-buffer inbox-buf
        (goto-char (point-min))
        (re-search-forward "Maybe later")
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "")))
          (a3madkour/inbox-to-someday)))
      ;; Inbox is now empty
      (with-current-buffer inbox-buf
        (should-not (string-match-p "Maybe later" (buffer-string)))))
    ;; Someday has it under Parking Lot
    (let ((content
           (with-current-buffer
               (find-file-noselect (a3madkour/org-file "someday.org"))
             (buffer-string))))
      (should (string-match-p "Maybe later" content)))))

(ert-deftest a3madkour-test/inbox-to-someday-explicit-heading ()
  (a3madkour-test/with-org-env
      '(("someday.org" . "* Parking Lot\n* Books\n"))
    (find-file-noselect (a3madkour/org-file "someday.org"))
    (let ((inbox-buf
           (find-file-noselect
            (let ((f (a3madkour/org-file "inbox.org")))
              (with-temp-file f (insert "* TODO A book to read\n"))
              f))))
      (with-current-buffer inbox-buf
        (goto-char (point-min))
        (re-search-forward "A book")
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "Books")))
          (a3madkour/inbox-to-someday))))
    (with-current-buffer (find-file-noselect (a3madkour/org-file "someday.org"))
      (goto-char (point-min))
      (re-search-forward "^\\* Books")
      (let ((bound (save-excursion
                     (or (re-search-forward "^\\* " nil t) (point-max)))))
        (should (re-search-forward "A book to read" bound t))))))

(ert-deftest a3madkour-test/inbox-to-someday-unknown-heading-errors ()
  (a3madkour-test/with-org-env
      '(("someday.org" . "* Parking Lot\n"))
    (find-file-noselect (a3madkour/org-file "someday.org"))
    (let ((inbox-buf
           (find-file-noselect
            (let ((f (a3madkour/org-file "inbox.org")))
              (with-temp-file f (insert "* TODO Foo\n"))
              f))))
      (with-current-buffer inbox-buf
        (goto-char (point-min))
        (re-search-forward "Foo")
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "Nonexistent")))
          (should-error (a3madkour/inbox-to-someday) :type 'user-error))))))

;;; ---- a3madkour/inbox-to-habit ----

(ert-deftest a3madkour-test/inbox-to-habit-daily ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Actions\n* Habits\n"))
    (find-file-noselect (a3madkour/org-file "actions.org"))
    (let ((inbox-buf
           (find-file-noselect
            (let ((f (a3madkour/org-file "inbox.org")))
              (with-temp-file f (insert "* TODO Brush teeth\n"))
              f))))
      (with-current-buffer inbox-buf
        (goto-char (point-min))
        (re-search-forward "Brush")
        (cl-letf (((symbol-function 'completing-read)
                   (a3madkour-test/queue '("daily")))
                  ((symbol-function 'read-string)
                   (a3madkour-test/queue '(""))))  ;; no flexibility
          (a3madkour/inbox-to-habit)))
      ;; Actions.org has the habit under Habits with right properties
      (let ((content
             (with-current-buffer
                 (find-file-noselect (a3madkour/org-file "actions.org"))
               (buffer-string))))
        (should (string-match-p "Brush teeth" content))
        (should (string-match-p ":STYLE: +habit" content))
        (should (string-match-p "SCHEDULED:.*\\.\\+1d" content))))))

(ert-deftest a3madkour-test/inbox-to-habit-with-flexibility ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Habits\n"))
    (find-file-noselect (a3madkour/org-file "actions.org"))
    (let ((inbox-buf
           (find-file-noselect
            (let ((f (a3madkour/org-file "inbox.org")))
              (with-temp-file f (insert "* TODO Floss\n"))
              f))))
      (with-current-buffer inbox-buf
        (goto-char (point-min))
        (re-search-forward "Floss")
        (cl-letf (((symbol-function 'completing-read)
                   (a3madkour-test/queue '("every 3 days")))
                  ((symbol-function 'read-string)
                   (a3madkour-test/queue '("5"))))
          (a3madkour/inbox-to-habit)))
      (let ((content
             (with-current-buffer
                 (find-file-noselect (a3madkour/org-file "actions.org"))
               (buffer-string))))
        (should (string-match-p "SCHEDULED:.*\\.\\+3d/5d" content))))))

;;; ---- a3madkour/inbox-to-action ----

(ert-deftest a3madkour-test/inbox-to-action-without-schedule ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Actions\n"))
    (find-file-noselect (a3madkour/org-file "actions.org"))
    (let ((inbox-buf
           (find-file-noselect
            (let ((f (a3madkour/org-file "inbox.org")))
              (with-temp-file f (insert "* TODO Pay bills\n"))
              f))))
      (with-current-buffer inbox-buf
        (goto-char (point-min))
        (re-search-forward "Pay bills")
        (cl-letf (((symbol-function 'completing-read)
                   (a3madkour-test/queue '("high")))    ;; ENERGY
                  ((symbol-function 'read-string)
                   (a3madkour-test/queue '("0:30")))    ;; EFFORT
                  ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
          (a3madkour/inbox-to-action)))
      (let ((content
             (with-current-buffer
                 (find-file-noselect (a3madkour/org-file "actions.org"))
               (buffer-string))))
        (should (string-match-p "Pay bills" content))
        (should (string-match-p ":ENERGY: +high" content))
        (should (string-match-p ":EFFORT: +0:30" content))
        (should-not (string-match-p "SCHEDULED:" content))))))

;;; ---- a3madkour/inbox-to-existing-project ----

(ert-deftest a3madkour-test/inbox-to-existing-project-refiles ()
  (let ((refile-captured nil))
    (a3madkour-test/with-org-env
        '(("projects.org" . "* Some Project                                    :project:active:\n"))
      (find-file-noselect (a3madkour/org-file "projects.org"))
      (let ((inbox-buf
             (find-file-noselect
              (let ((f (a3madkour/org-file "inbox.org")))
                (with-temp-file f (insert "* TODO Sub-task\n"))
                f))))
        (with-current-buffer inbox-buf
          (goto-char (point-min))
          (re-search-forward "Sub-task")
          (cl-letf (((symbol-function 'completing-read)
                     (a3madkour-test/queue '("high")))
                    ((symbol-function 'read-string)
                     (a3madkour-test/queue '("0:30")))
                    ((symbol-function 'org-refile)
                     (lambda (&rest _) (setq refile-captured 'was-called))))
            (a3madkour/inbox-to-existing-project)))
        ;; ENERGY/EFFORT set on the inbox item before refile
        (with-current-buffer inbox-buf
          (goto-char (point-min))
          (re-search-forward "Sub-task")
          (org-back-to-heading t)
          (should (equal "high" (org-entry-get nil "ENERGY")))
          (should (equal "0:30" (org-entry-get nil "EFFORT"))))
        ;; org-refile was called
        (should refile-captured)))))

;;; ---- a3madkour/inbox-to-new-project ----

(ert-deftest a3madkour-test/inbox-to-new-project-creates-and-refiles ()
  (let ((create-called nil)
        (refile-captured nil))
    (a3madkour-test/with-org-env
        '(("projects.org" . ""))
      (let ((stub-marker
             (with-current-buffer
                 (find-file-noselect (a3madkour/org-file "projects.org"))
               (goto-char (point-min))
               (insert "* Stub Project                                       :project:active:\n")
               (goto-char (point-min))
               (point-marker))))
        (let ((inbox-buf
               (find-file-noselect
                (let ((f (a3madkour/org-file "inbox.org")))
                  (with-temp-file f (insert "* TODO Inbox task\n"))
                  f))))
          (with-current-buffer inbox-buf
            (goto-char (point-min))
            (re-search-forward "Inbox task")
            (cl-letf (((symbol-function 'a3madkour/create-project)
                       (lambda (&rest _) (setq create-called t) stub-marker))
                      ((symbol-function 'completing-read)
                       (a3madkour-test/queue '("high")))
                      ((symbol-function 'read-string)
                       (a3madkour-test/queue '("0:30")))
                      ((symbol-function 'org-refile)
                       (lambda (&rest args) (setq refile-captured args))))
              (a3madkour/inbox-to-new-project)))
          (should create-called)
          (should refile-captured))))))

;;; ---- a3madkour/process-inbox-item ----

(ert-deftest a3madkour-test/process-inbox-item-rejects-non-todo ()
  (a3madkour-test/in-buffer "* Plain heading\n"
    (re-search-forward "Plain")
    (should-error (a3madkour/process-inbox-item) :type 'user-error)))

(ert-deftest a3madkour-test/process-inbox-item-routes-delete ()
  (let ((called nil))
    (a3madkour-test/in-buffer "* TODO Foo\n"
      (re-search-forward "TODO")
      (cl-letf (((symbol-function 'completing-read)
                 (a3madkour-test/queue '("delete")))
                ((symbol-function 'a3madkour/inbox-delete)
                 (lambda () (setq called 'delete))))
        (a3madkour/process-inbox-item))
      (should (eq called 'delete)))))

(ert-deftest a3madkour-test/process-inbox-item-routes-org-roam ()
  (let ((called nil))
    (a3madkour-test/in-buffer "* TODO Foo\n"
      (re-search-forward "TODO")
      (cl-letf (((symbol-function 'completing-read)
                 (a3madkour-test/queue '("org-roam")))
                ((symbol-function 'a3madkour/inbox-to-org-roam)
                 (lambda () (setq called 'roam))))
        (a3madkour/process-inbox-item))
      (should (eq called 'roam)))))

(ert-deftest a3madkour-test/process-inbox-item-routes-someday ()
  (let ((called nil))
    (a3madkour-test/in-buffer "* TODO Foo\n"
      (re-search-forward "TODO")
      (cl-letf (((symbol-function 'completing-read)
                 (a3madkour-test/queue '("someday")))
                ((symbol-function 'a3madkour/inbox-to-someday)
                 (lambda () (setq called 'someday))))
        (a3madkour/process-inbox-item))
      (should (eq called 'someday)))))

(ert-deftest a3madkour-test/process-inbox-item-routes-action-habit ()
  (let ((called nil))
    (a3madkour-test/in-buffer "* TODO Foo\n"
      (re-search-forward "TODO")
      (cl-letf (((symbol-function 'completing-read)
                 (a3madkour-test/queue '("action")))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'a3madkour/inbox-to-habit)
                 (lambda () (setq called 'habit))))
        (a3madkour/process-inbox-item))
      (should (eq called 'habit)))))

(ert-deftest a3madkour-test/process-inbox-item-routes-action-plain ()
  (let ((called nil))
    (a3madkour-test/in-buffer "* TODO Foo\n"
      (re-search-forward "TODO")
      (cl-letf (((symbol-function 'completing-read)
                 (a3madkour-test/queue '("action")))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
                ((symbol-function 'a3madkour/inbox-to-action)
                 (lambda () (setq called 'action))))
        (a3madkour/process-inbox-item))
      (should (eq called 'action)))))

(ert-deftest a3madkour-test/process-inbox-item-routes-project-new ()
  (let ((called nil))
    (a3madkour-test/in-buffer "* TODO Foo\n"
      (re-search-forward "TODO")
      (cl-letf (((symbol-function 'completing-read)
                 (a3madkour-test/queue '("project" "create new project")))
                ((symbol-function 'a3madkour/inbox-to-new-project)
                 (lambda () (setq called 'new-project))))
        (a3madkour/process-inbox-item))
      (should (eq called 'new-project)))))

(ert-deftest a3madkour-test/process-inbox-item-routes-project-existing ()
  (let ((called nil))
    (a3madkour-test/in-buffer "* TODO Foo\n"
      (re-search-forward "TODO")
      (cl-letf (((symbol-function 'completing-read)
                 (a3madkour-test/queue '("project" "existing project")))
                ((symbol-function 'a3madkour/inbox-to-existing-project)
                 (lambda () (setq called 'existing-project))))
        (a3madkour/process-inbox-item))
      (should (eq called 'existing-project)))))

(provide 'test-inbox)
;;; test-inbox.el ends here
