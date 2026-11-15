;;; test-inbox.el --- Tier 2: inbox triage  -*- lexical-binding: t; -*-

(require 'test-helpers)

;;; ---- shared: abort-safety fixtures ----

(defconst a3madkour-test--abort-item
  "* TODO Keep me
Some body text
** child note
"
  "An inbox item with a body and a child, for the abort tests.")

(defun a3madkour-test--make-inbox ()
  "Write the abort-test item to inbox.org and return its buffer at point-min."
  (let ((buf (find-file-noselect
              (let ((f (a3madkour/org-file "inbox.org")))
                (with-temp-file f (insert a3madkour-test--abort-item))
                f))))
    (with-current-buffer buf (goto-char (point-min)))
    buf))

(defun a3madkour-test--should-be-intact (buf)
  "Assert the item in BUF is still a TODO with its body and child.
ENERGY/EFFORT properties are tolerated."
  (with-current-buffer buf
    (let ((s (buffer-string)))
      (should (string-match-p "\\`\\* TODO Keep me" s))
      (should (string-match-p "Some body text" s))
      (should (string-match-p "^\\*\\* child note$" s)))))

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

;; Content carried into the note.

(ert-deftest a3madkour-test/inbox-roam-content-relevels-children ()
  (a3madkour-test/in-buffer "\
* TODO Parent                                                     :ptag:
:PROPERTIES:
:CAPTURED: [2026-11-01 Sun]
:END:
body line
*** NEXT Child                                                    :ctag:
:PROPERTIES:
:X: 1
:END:
**** Grandchild
* TODO Sibling
"
    (let ((content (a3madkour/-inbox-roam-content)))
      (should (string-prefix-p "body line" content))
      (should (string-match-p "^\\* NEXT Child +:ctag:$" content))
      (should (string-match-p "^:X: +1$" content))
      (should (string-match-p "^\\*\\* Grandchild$" content))
      (should-not (string-match-p "CAPTURED\\|ptag\\|Sibling" content)))))

(ert-deftest a3madkour-test/inbox-roam-content-empty-body-with-children ()
  (a3madkour-test/in-buffer "* TODO Parent\n** Child\nchild body\n* TODO Sibling\n"
    (should (equal (a3madkour/-inbox-roam-content) "* Child\nchild body"))))

(ert-deftest a3madkour-test/inbox-roam-content-no-children ()
  (a3madkour-test/in-buffer "\
* TODO Parent
SCHEDULED: <2026-11-20 Fri>
:PROPERTIES:
:CAPTURED: [2026-11-01 Sun]
:END:

just the body

* TODO Sibling
"
    (should (equal (a3madkour/-inbox-roam-content) "just the body"))))

(ert-deftest a3madkour-test/inbox-roam-content-empty ()
  (a3madkour-test/in-buffer "* TODO Parent\n* TODO Sibling\n"
    (should (equal (a3madkour/-inbox-roam-content) "")))
  (a3madkour-test/in-buffer "* TODO Last line, no newline"
    (should (equal (a3madkour/-inbox-roam-content) ""))))

;; The hand-off, with org-roam's capture stubbed.  The stub does what
;; `org-roam-capture-' does on success: it returns with a capture buffer
;; current.  A finalise is simulated the way `org-capture-finalize' runs it:
;; the prepare hook in the capture buffer, the capture buffer killed, then the
;; after hook in some other buffer.

(defun a3madkour-test/-fake-roam-capture (name)
  "Return a stub for `org-roam-capture-' that makes buffer NAME current as a capture buffer."
  (lambda (&rest args)
    (set-buffer (get-buffer-create name))
    (setq-local org-capture-mode t)
    (setq-local a3madkour-test/-capture-args args)))

(defun a3madkour-test/-hand-off (inbox heading capture-name)
  "Hand the INBOX item titled HEADING to a fake roam capture named CAPTURE-NAME.
Return the capture buffer."
  (with-current-buffer inbox
    (goto-char (point-min))
    (re-search-forward (concat "^\\* TODO " (regexp-quote heading)))
    (cl-letf (((symbol-function 'org-roam-capture-)
               (a3madkour-test/-fake-roam-capture capture-name)))
      (a3madkour/inbox-to-org-roam)))
  (get-buffer capture-name))

(defun a3madkour-test/-capture-template (capture)
  "The template body string the hand-off passed to `org-roam-capture-' for CAPTURE."
  (let ((args (buffer-local-value 'a3madkour-test/-capture-args capture)))
    (nth 3 (car (plist-get args :templates)))))

(defun a3madkour-test/-finalize (capture &optional abort)
  "Simulate `org-capture-finalize' of buffer CAPTURE; ABORT non-nil is `org-capture-kill'."
  (let ((org-note-abort abort))
    (with-current-buffer capture (a3madkour--inbox-roam-prepare-finalize))
    (kill-buffer capture)
    (with-temp-buffer (a3madkour--inbox-to-roam-finalize))))

(defun a3madkour-test/-finalize-unrelated ()
  "Simulate successfully finalising some capture the hand-off did not start."
  (let ((org-note-abort nil))
    (with-temp-buffer
      (setq-local org-capture-mode t)
      (a3madkour--inbox-roam-prepare-finalize)
      (a3madkour--inbox-to-roam-finalize))))

(defmacro a3madkour-test/-with-captures (names &rest body)
  "Run BODY, then kill capture buffers NAMES and disarm any finalise in flight."
  (declare (indent 1) (debug t))
  `(unwind-protect (progn ,@body)
     (dolist (n ,names) (when (get-buffer n) (kill-buffer n)))
     (setq a3madkour--inbox-roam-finalizing nil)))

(defconst a3madkour-test--roam-inbox "\
* TODO Send me to roam
body text here
** child note
*** grandchild
* TODO Sibling
"
  "An inbox with an item that has a body and children, and a sibling after it.")

(ert-deftest a3madkour-test/inbox-to-org-roam-defers-cut-until-finalize ()
  (a3madkour-test/-with-captures '("*cap*")
    (a3madkour-test/in-buffer a3madkour-test--roam-inbox
      (let ((cap (a3madkour-test/-hand-off (current-buffer) "Send me" "*cap*")))
        (should (string-match-p "Send me to roam" (buffer-string)))
        (should (buffer-live-p cap))
        (a3madkour-test/-finalize cap)
        (should-not (string-match-p "Send me to roam" (buffer-string)))))))

(ert-deftest a3madkour-test/inbox-to-org-roam-empty-body-template ()
  (a3madkour-test/-with-captures '("*cap*")
    (a3madkour-test/in-buffer "* TODO No body item\n"
      (let ((cap (a3madkour-test/-hand-off (current-buffer) "No body" "*cap*")))
        (should (equal (a3madkour-test/-capture-template cap) "%?"))
        (should (equal (with-current-buffer cap (buffer-string)) ""))))))

(ert-deftest a3madkour-test/inbox-to-org-roam-body-is-not-a-template ()
  (let ((body "100% %20 %^{x} %(error \"x\") ${foo}"))
    (a3madkour-test/-with-captures '("*cap*")
      (a3madkour-test/in-buffer (concat "* TODO Tricky\n" body "\n")
        (let ((cap (a3madkour-test/-hand-off (current-buffer) "Tricky" "*cap*")))
          (should (equal (a3madkour-test/-capture-template cap) "%?"))
          (should (equal (with-current-buffer cap (buffer-string)) body)))))))

(ert-deftest a3madkour-test/inbox-to-org-roam-own-finalize-cuts-whole-item ()
  (a3madkour-test/-with-captures '("*cap*")
    (a3madkour-test/in-buffer a3madkour-test--roam-inbox
      (let ((cap (a3madkour-test/-hand-off (current-buffer) "Send me" "*cap*")))
        ;; The whole item reached the note, children included.
        (should (equal (with-current-buffer cap (buffer-string))
                       "body text here\n* child note\n** grandchild"))
        (a3madkour-test/-finalize cap)
        (should (equal (buffer-string) "* TODO Sibling\n"))
        (should-not a3madkour--inbox-roam-finalizing)))))

(ert-deftest a3madkour-test/inbox-to-org-roam-preserves-on-abort ()
  (a3madkour-test/-with-captures '("*cap*")
    (a3madkour-test/in-buffer a3madkour-test--roam-inbox
      (let ((cap (a3madkour-test/-hand-off (current-buffer) "Send me" "*cap*")))
        (a3madkour-test/-finalize cap 'abort)
        (should (equal (buffer-string) a3madkour-test--roam-inbox))
        (should-not a3madkour--inbox-roam-finalizing)))))

(ert-deftest a3madkour-test/inbox-to-org-roam-unrelated-capture-cuts-nothing ()
  (a3madkour-test/-with-captures '("*cap*")
    (a3madkour-test/in-buffer a3madkour-test--roam-inbox
      (let ((cap (a3madkour-test/-hand-off (current-buffer) "Send me" "*cap*")))
        (a3madkour-test/-finalize-unrelated)
        (should (equal (buffer-string) a3madkour-test--roam-inbox))
        ;; The hand-off is still armed for its own capture.
        (a3madkour-test/-finalize cap)
        (should (equal (buffer-string) "* TODO Sibling\n"))))))

(ert-deftest a3madkour-test/inbox-to-org-roam-two-in-flight ()
  (a3madkour-test/-with-captures '("*cap-a*" "*cap-b*")
    (a3madkour-test/in-buffer "* TODO Item A\nbody a\n* TODO Item B\nbody b\n* TODO Sibling\n"
      (let ((cap-a (a3madkour-test/-hand-off (current-buffer) "Item A" "*cap-a*"))
            (cap-b (a3madkour-test/-hand-off (current-buffer) "Item B" "*cap-b*")))
        (should (equal (with-current-buffer cap-a (buffer-string)) "body a"))
        (should (equal (with-current-buffer cap-b (buffer-string)) "body b"))
        (a3madkour-test/-finalize cap-b)
        (should (equal (buffer-string) "* TODO Item A\nbody a\n* TODO Sibling\n"))
        (a3madkour-test/-finalize cap-a)
        (should (equal (buffer-string) "* TODO Sibling\n"))))))

(ert-deftest a3madkour-test/inbox-to-org-roam-capture-fails-to-start ()
  (a3madkour-test/in-buffer a3madkour-test--roam-inbox
    (re-search-forward "Send me")
    (cl-letf (((symbol-function 'org-roam-capture-) #'ignore))
      (should-error (a3madkour/inbox-to-org-roam) :type 'user-error))
    (should-not a3madkour--inbox-roam-finalizing)
    (should-not (local-variable-p 'a3madkour--inbox-roam-marker))
    (a3madkour-test/-finalize-unrelated)
    (should (equal (buffer-string) a3madkour-test--roam-inbox))))

(ert-deftest a3madkour-test/inbox-to-org-roam-interrupted-finalize-arms-nothing ()
  ;; If the after hook never runs for the hand-off's capture (another after
  ;; hook signalled first), the next unrelated finalise must not cut the item.
  (a3madkour-test/-with-captures '("*cap*")
    (a3madkour-test/in-buffer a3madkour-test--roam-inbox
      (let ((cap (a3madkour-test/-hand-off (current-buffer) "Send me" "*cap*")))
        (with-current-buffer cap (a3madkour--inbox-roam-prepare-finalize))
        (kill-buffer cap)
        (a3madkour-test/-finalize-unrelated)
        (should (equal (buffer-string) a3madkour-test--roam-inbox))))))

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
    (let ((inbox-buf (a3madkour-test--make-inbox)))
      (with-current-buffer inbox-buf
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "Nope")))
          (should-error (a3madkour/inbox-to-someday) :type 'user-error)))
      (a3madkour-test--should-be-intact inbox-buf))))

(ert-deftest a3madkour-test/inbox-to-someday-abort-keeps-keyword ()
  (a3madkour-test/with-org-env
      '(("someday.org" . "* Parking Lot\n"))
    (find-file-noselect (a3madkour/org-file "someday.org"))
    (let ((inbox-buf (a3madkour-test--make-inbox)))
      (with-current-buffer inbox-buf
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) (signal 'quit nil))))
          (condition-case nil (a3madkour/inbox-to-someday) (quit nil))))
      (a3madkour-test--should-be-intact inbox-buf))))

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
                   (a3madkour-test/queue '("")))  ;; no flexibility
                  ((symbol-function 'completing-read-multiple)
                   (lambda (&rest _) nil)))
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
                   (a3madkour-test/queue '("5")))
                  ((symbol-function 'completing-read-multiple)
                   (lambda (&rest _) nil)))
          (a3madkour/inbox-to-habit)))
      (let ((content
             (with-current-buffer
                 (find-file-noselect (a3madkour/org-file "actions.org"))
               (buffer-string))))
        (should (string-match-p "SCHEDULED:.*\\.\\+3d/5d" content))))))

;;; prompts for tags, offering existing habit tags and "core"
(ert-deftest a3madkour-test/inbox-to-habit-sets-tags ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Habits\n** TODO Old :health:\n:PROPERTIES:\n:STYLE: habit\n:END:\n"))
    (find-file-noselect (a3madkour/org-file "actions.org"))
    (let ((inbox-buf
           (find-file-noselect
            (let ((f (a3madkour/org-file "inbox.org")))
              (with-temp-file f (insert "* TODO Stretch\n"))
              f)))
          offered)
      (with-current-buffer inbox-buf
        (goto-char (point-min))
        (re-search-forward "Stretch")
        (cl-letf (((symbol-function 'completing-read)
                   (a3madkour-test/queue '("daily")))
                  ((symbol-function 'read-string)
                   (a3madkour-test/queue '("")))
                  ((symbol-function 'completing-read-multiple)
                   (lambda (_prompt table &rest _)
                     (setq offered table)
                     '("core" "health"))))
          (a3madkour/inbox-to-habit)))
      (should (member "core" offered))
      (should (member "health" offered))
      (let ((content
             (with-current-buffer
                 (find-file-noselect (a3madkour/org-file "actions.org"))
               (buffer-string))))
        (should (string-match-p "Stretch +:core:health:" content))))))

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

;;; ---- aborting a hand-off leaves the item as it was ----

(ert-deftest a3madkour-test/inbox-to-new-project-abort-leaves-no-project ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "* Existing :project:active:\n"))
    (let* ((pbuf (find-file-noselect (a3madkour/org-file "projects.org")))
           (before (with-current-buffer pbuf (buffer-string)))
           (inbox-buf (a3madkour-test--make-inbox)))
      (with-current-buffer inbox-buf
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (prompt &rest _)
                     (cond ((string-match-p "Energy" prompt) (signal 'quit nil))
                           ((string-match-p "Life area" prompt) "artistic")
                           (t "active"))))
                  ((symbol-function 'read-string) (lambda (&rest _) "x"))
                  ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
          (condition-case nil (a3madkour/inbox-to-new-project) (quit nil))))
      (should (equal before (with-current-buffer pbuf (buffer-string))))
      (should (equal before (with-temp-buffer
                              (insert-file-contents (a3madkour/org-file "projects.org"))
                              (buffer-string))))
      (a3madkour-test--should-be-intact inbox-buf))))

(ert-deftest a3madkour-test/inbox-to-habit-bad-flexibility-touches-nothing ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Habits\n"))
    (find-file-noselect (a3madkour/org-file "actions.org"))
    (let ((inbox-buf (a3madkour-test--make-inbox)))
      (with-current-buffer inbox-buf
        (cl-letf (((symbol-function 'completing-read)
                   (a3madkour-test/queue '("every 3 days")))
                  ((symbol-function 'read-string)
                   (a3madkour-test/queue '("3")))
                  ((symbol-function 'completing-read-multiple)
                   (lambda (&rest _) nil)))
          (should-error (a3madkour/inbox-to-habit) :type 'user-error))
        (should-not (string-match-p "STYLE\\|SCHEDULED:" (buffer-string))))
      (a3madkour-test--should-be-intact inbox-buf))))

(ert-deftest a3madkour-test/inbox-to-habit-abort-at-tags ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Habits\n"))
    (find-file-noselect (a3madkour/org-file "actions.org"))
    (let ((inbox-buf (a3madkour-test--make-inbox)))
      (with-current-buffer inbox-buf
        (cl-letf (((symbol-function 'completing-read)
                   (a3madkour-test/queue '("daily")))
                  ((symbol-function 'read-string)
                   (a3madkour-test/queue '("")))
                  ((symbol-function 'completing-read-multiple)
                   (lambda (&rest _) (signal 'quit nil))))
          (condition-case nil (a3madkour/inbox-to-habit) (quit nil)))
        (should-not (string-match-p "STYLE\\|SCHEDULED:" (buffer-string))))
      (a3madkour-test--should-be-intact inbox-buf))))

(ert-deftest a3madkour-test/inbox-to-action-abort-at-schedule ()
  (a3madkour-test/with-org-env
      '(("actions.org" . "* Actions\n"))
    (let ((inbox-buf (a3madkour-test--make-inbox)))
      (with-current-buffer inbox-buf
        (cl-letf (((symbol-function 'completing-read)
                   (a3madkour-test/queue '("high")))
                  ((symbol-function 'read-string)
                   (a3madkour-test/queue '("0:30")))
                  ((symbol-function 'yes-or-no-p)
                   (lambda (&rest _) (signal 'quit nil))))
          (condition-case nil (a3madkour/inbox-to-action) (quit nil))))
      (should-not (string-match-p
                   "Keep me"
                   (with-current-buffer
                       (find-file-noselect (a3madkour/org-file "actions.org"))
                     (buffer-string))))
      (a3madkour-test--should-be-intact inbox-buf))))

(ert-deftest a3madkour-test/inbox-to-existing-project-abort-in-refile ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "* Some Project :project:active:\n"))
    (find-file-noselect (a3madkour/org-file "projects.org"))
    (let ((inbox-buf (a3madkour-test--make-inbox)))
      (with-current-buffer inbox-buf
        (cl-letf (((symbol-function 'completing-read)
                   (a3madkour-test/queue '("high")))
                  ((symbol-function 'read-string)
                   (a3madkour-test/queue '("0:30")))
                  ((symbol-function 'org-refile)
                   (lambda (&rest _) (signal 'quit nil))))
          (condition-case nil (a3madkour/inbox-to-existing-project) (quit nil))))
      (a3madkour-test--should-be-intact inbox-buf))))

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

(ert-deftest a3madkour-test/inbox-to-existing-project-offers-only-projects ()
  (a3madkour-test/with-org-env '(("projects.org" . ""))
    (let (targets)
      (cl-letf (((symbol-function 'a3madkour/set-task-properties) #'ignore)
                ((symbol-function 'message) #'ignore)
                ((symbol-function 'org-refile)
                 (lambda (&rest _) (setq targets org-refile-targets))))
        (a3madkour/inbox-to-existing-project))
      (should (equal targets
                     `((,(a3madkour/org-file "projects.org") :tag . "project")))))))

(provide 'test-inbox)
;;; test-inbox.el ends here
