;;; test-project-lifecycle.el --- Tier 2: project lifecycle  -*- lexical-binding: t; -*-

(require 'test-helpers)

;;; Helper: open a file from the test org env and run BODY with point at min.
(defmacro a3madkour-test/in-org-file (rel-path &rest body)
  (declare (indent 1) (debug t))
  `(with-current-buffer (find-file-noselect (a3madkour/org-file ,rel-path))
     (goto-char (point-min))
     ,@body))

;;; ---- a3madkour/create-project ----

(ert-deftest a3madkour-test/create-project-non-interactive-no-placeholder ()
  ;; Bug-fix regression: calling create-project from code (not M-x) must NOT
  ;; emit an empty `** TODO ` placeholder.
  (a3madkour-test/with-org-env '(("projects.org" . ""))
    (cl-letf (((symbol-function 'read-string)
               (a3madkour-test/queue '("Foo" "Ship it" "")))
              ((symbol-function 'completing-read)
               (a3madkour-test/queue '("intellectual" "inactive")))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (let ((marker (a3madkour/create-project)))
        (should (markerp marker))
        (a3madkour-test/in-org-file "projects.org"
          (should (re-search-forward "^\\* Foo" nil t))
          (goto-char (point-min))
          (should-not (re-search-forward "^\\*\\* TODO " nil t)))))))

(ert-deftest a3madkour-test/create-project-sets-properties ()
  (a3madkour-test/with-org-env '(("projects.org" . ""))
    (cl-letf (((symbol-function 'read-string)
               (a3madkour-test/queue '("Foo" "Done thing" "Annual goal")))
              ((symbol-function 'completing-read)
               (a3madkour-test/queue '("career" "active")))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (a3madkour/create-project)
      (a3madkour-test/in-org-file "projects.org"
        (re-search-forward "^\\* Foo")
        (org-back-to-heading t)
        (let ((tags (org-get-tags nil t)))
          (should (member "project" tags))
          (should (member "active" tags))
          (should (member "career" tags)))
        (should (equal "Done thing" (org-entry-get nil "DONE_ENOUGH")))
        (should (equal "Annual goal" (org-entry-get nil "GOAL")))
        (should (null (org-entry-get nil "REPO")))))))

(ert-deftest a3madkour-test/create-project-empty-goal-becomes-exploratory ()
  (a3madkour-test/with-org-env '(("projects.org" . ""))
    (cl-letf (((symbol-function 'read-string)
               (a3madkour-test/queue '("Foo" "Done" "")))  ;; blank goal
              ((symbol-function 'completing-read)
               (a3madkour-test/queue '("artistic" "inactive")))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (a3madkour/create-project)
      (a3madkour-test/in-org-file "projects.org"
        (re-search-forward "^\\* Foo")
        (org-back-to-heading t)
        (should (equal "exploratory" (org-entry-get nil "GOAL")))))))

(ert-deftest a3madkour-test/create-project-with-repo ()
  (a3madkour-test/with-org-env '(("projects.org" . ""))
    (cl-letf (((symbol-function 'read-string)
               (a3madkour-test/queue '("Foo" "Done" "Goal")))
              ((symbol-function 'completing-read)
               (a3madkour-test/queue '("intellectual" "inactive")))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
              ((symbol-function 'read-directory-name)
               (lambda (&rest _) "/tmp/repo-dir")))
      (a3madkour/create-project)
      (a3madkour-test/in-org-file "projects.org"
        (re-search-forward "^\\* Foo")
        (org-back-to-heading t)
        (should (string-match-p "repo-dir" (or (org-entry-get nil "REPO") "")))))))

(ert-deftest a3madkour-test/create-project-wip-limit-error ()
  ;; With 3 already-active projects and limit=3, creating another active errors.
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* A                                                         :project:active:
* B                                                         :project:active:
* C                                                         :project:active:
"))
    (let ((a3madkour/project-wip-limit 3))
      (cl-letf (((symbol-function 'read-string)
                 (a3madkour-test/queue '("D" "Done" "")))
                ((symbol-function 'completing-read)
                 (a3madkour-test/queue '("intellectual" "active")))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (should-error (a3madkour/create-project) :type 'user-error)))))

(ert-deftest a3madkour-test/create-project-inactive-bypasses-wip ()
  ;; Even with 3 active projects, status=inactive should succeed.
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* A                                                         :project:active:
* B                                                         :project:active:
* C                                                         :project:active:
"))
    (let ((a3madkour/project-wip-limit 3))
      (cl-letf (((symbol-function 'read-string)
                 (a3madkour-test/queue '("D" "Done" "")))
                ((symbol-function 'completing-read)
                 (a3madkour-test/queue '("intellectual" "inactive")))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (let ((marker (a3madkour/create-project)))
          (should (markerp marker)))))))

;;; ---- a3madkour/deactivate-on-done ----

(ert-deftest a3madkour-test/deactivate-on-done-swaps-tags ()
  (a3madkour-test/in-buffer "\
* TODO Some task                                                    :active:
"
    (re-search-forward "TODO")
    (let ((org-state "DONE"))
      (a3madkour/deactivate-on-done))
    (org-back-to-heading t)
    (let ((tags (org-get-tags nil t)))
      (should-not (member "active" tags))
      (should (member "inactive" tags)))))

(ert-deftest a3madkour-test/deactivate-on-done-noop-when-not-done ()
  (a3madkour-test/in-buffer "\
* TODO Some task                                                    :active:
"
    (re-search-forward "TODO")
    (let ((org-state "TODO"))
      (a3madkour/deactivate-on-done))
    (org-back-to-heading t)
    (should (member "active" (org-get-tags nil t)))))

(ert-deftest a3madkour-test/deactivate-on-done-noop-when-not-active ()
  ;; Only tagged with :inactive: — no change should occur.
  (a3madkour-test/in-buffer "\
* TODO Some task                                                  :inactive:
"
    (re-search-forward "TODO")
    (let ((org-state "DONE"))
      (a3madkour/deactivate-on-done))
    (org-back-to-heading t)
    (let ((tags (org-get-tags nil t)))
      (should (member "inactive" tags))
      (should (= 1 (length tags))))))

;;; ---- a3madkour/toggle-active ----

(ert-deftest a3madkour-test/toggle-active-active-to-inactive ()
  (a3madkour-test/in-buffer "\
* Foo                                                       :project:active:
"
    (re-search-forward "Foo")
    (org-back-to-heading t)
    (a3madkour/toggle-active)
    (let ((tags (org-get-tags nil t)))
      (should-not (member "active" tags))
      (should (member "inactive" tags)))))

(ert-deftest a3madkour-test/toggle-active-respects-wip-limit ()
  ;; Heading is inactive, but 3 projects are already active. Toggling on should
  ;; error.
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* A                                                         :project:active:
* B                                                         :project:active:
* C                                                         :project:active:
* D                                                       :project:inactive:
"))
    (let ((a3madkour/project-wip-limit 3))
      (a3madkour-test/in-org-file "projects.org"
        (re-search-forward "^\\* D")
        (org-back-to-heading t)
        (should-error (a3madkour/toggle-active) :type 'user-error)
        ;; Tags should be unchanged after the error
        (org-back-to-heading t)
        (let ((tags (org-get-tags nil t)))
          (should (member "inactive" tags))
          (should-not (member "active" tags)))))))

;;; ---- a3madkour/sort-by-active-tag ----

(ert-deftest a3madkour-test/sort-by-active-tag-orders-correctly ()
  (a3madkour-test/in-buffer "\
* C                                                       :project:inactive:
* A                                                         :project:active:
* B                                                                :project:
* D                                                         :project:active:
"
    ;; org-sort-entries needs an active mark; in batch we have to opt in.
    (let ((transient-mark-mode t))
      (a3madkour/sort-by-active-tag))
    (goto-char (point-min))
    (let ((order '()))
      (while (re-search-forward "^\\* \\([A-Z]\\) " nil t)
        (push (match-string 1) order))
      (setq order (nreverse order))
      (should (= 4 (length order)))
      ;; Groups: active first (A, D in some stable order), untagged middle (B),
      ;; inactive last (C).
      (let ((active (cl-subseq order 0 2))
            (middle (nth 2 order))
            (last (nth 3 order)))
        (should (equal '("A" "D") (sort (copy-sequence active) #'string<)))
        (should (equal "B" middle))
        (should (equal "C" last))))))

;;; ---- a3madkour/archive-subtree-to-file ----

(ert-deftest a3madkour-test/archive-subtree-to-file-explicit-target ()
  (a3madkour-test/with-org-env
      '(("source.org" . "\
* Keep me
* Archive me
some body
")
        ("archive.org" . ""))
    (a3madkour-test/in-org-file "source.org"
      (re-search-forward "^\\* Archive me")
      (a3madkour/archive-subtree-to-file (a3madkour/org-file "archive.org")))
    (a3madkour-test/in-org-file "source.org"
      (let ((content (buffer-string)))
        (should (string-match-p "Keep me" content))
        (should-not (string-match-p "Archive me" content))))
    (a3madkour-test/in-org-file "archive.org"
      (let ((content (buffer-string)))
        (should (string-match-p "Archive me" content))
        (should (string-match-p "some body" content))))))

(ert-deftest a3madkour-test/archive-subtree-to-file-creates-target-dir ()
  (a3madkour-test/with-org-env
      '(("source.org" . "* Archive me\n"))
    (a3madkour-test/in-org-file "source.org"
      (re-search-forward "^\\* Archive me")
      (let ((target (a3madkour/org-file "nested/dir/archive.org")))
        (a3madkour/archive-subtree-to-file target)
        (should (file-exists-p target))))))

;;; ---- a3madkour/add-project-task ----

(ert-deftest a3madkour-test/add-project-task-from-project-heading ()
  (a3madkour-test/in-buffer "\
* Foo                                                       :project:active:
:PROPERTIES:
:GOAL: g
:END:
"
    (re-search-forward "^\\* Foo")
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "New task"))
              ((symbol-function 'completing-read) (lambda (&rest _) "high"))
              ((symbol-function 'org-set-property)
               (lambda (key val &rest _) nil))) ;; ignore property writes
      (a3madkour/add-project-task))
    (goto-char (point-min))
    (should (re-search-forward "^\\*\\* TODO New task" nil t))))

(ert-deftest a3madkour-test/add-project-task-from-subtask-walks-up ()
  ;; Even when called from a level-3 subtask, the new TODO should be added at
  ;; the project level (sibling to the existing subtask).
  (a3madkour-test/in-buffer "\
* Project                                                   :project:active:
** Subtask
*** Deep subtask
"
    (re-search-forward "^\\*\\*\\* Deep subtask")
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Sibling task"))
              ((symbol-function 'completing-read) (lambda (&rest _) "high"))
              ((symbol-function 'org-set-property)
               (lambda (&rest _) nil)))
      (a3madkour/add-project-task))
    (goto-char (point-min))
    (should (re-search-forward "^\\*\\* TODO Sibling task" nil t))))

(ert-deftest a3madkour-test/add-project-task-rejects-non-project ()
  (a3madkour-test/in-buffer "\
* Random heading
"
    (re-search-forward "Random")
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "x"))
              ((symbol-function 'completing-read) (lambda (&rest _) "high")))
      (should-error (a3madkour/add-project-task) :type 'user-error))))

;;; ---- a3madkour/show-project-status ----

(ert-deftest a3madkour-test/show-project-status-lists-projects ()
  (a3madkour-test/with-org-env
      '(("projects.org" . "\
* Current Season: Spring
* Alpha                                                     :project:active:
:PROPERTIES:
:GOAL: Goal-A
:END:
* Beta                                                    :project:inactive:
:PROPERTIES:
:GOAL: Goal-B
:END:
* Gamma                                                     :project:active:
"))
    (let ((a3madkour/project-wip-limit 3))
      (a3madkour/show-project-status)
      (with-current-buffer "*Project Status*"
        (let ((content (buffer-string)))
          (should (string-match-p "Spring" content))
          (should (string-match-p "Alpha" content))
          (should (string-match-p "Beta" content))
          (should (string-match-p "Gamma" content))
          (should (string-match-p "Goal-A" content))
          (should (string-match-p "Goal-B" content))
          (should (string-match-p "Active (2/3)" content)))))))

;;; ---- a3madkour/complete-project ----

(ert-deftest a3madkour-test/complete-project-happy-path ()
  (a3madkour-test/in-buffer "\
* Foo                                                       :project:active:
:PROPERTIES:
:DONE_ENOUGH: ship
:GOAL: g
:END:

Context: [[id:abc][note]]
"
    (re-search-forward "^\\* Foo")
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
              ((symbol-function 'read-string)
               (lambda (&rest _) "Shipped it"))
              ((symbol-function 'a3madkour/archive-subtree-to-file)
               (lambda (&rest _) nil)))
      (a3madkour/complete-project))
    (goto-char (point-min))
    (re-search-forward "^\\* Foo")
    (org-back-to-heading t)
    (should (equal "Shipped it" (org-entry-get nil "ACCOMPLISHED")))
    (should (org-entry-get nil "COMPLETED"))
    (let ((tags (org-get-tags nil t)))
      (should-not (member "active" tags))
      (should (member "done" tags)))))

(ert-deftest a3madkour-test/complete-project-no-notes-creates-then-aborts ()
  ;; Body has no [[id:…]] link, user opts to create notes — should call
  ;; create-project-notes and NOT proceed to set ACCOMPLISHED.
  (a3madkour-test/in-buffer "\
* Foo                                                       :project:active:
:PROPERTIES:
:DONE_ENOUGH: ship
:END:
"
    (re-search-forward "^\\* Foo")
    (let ((create-notes-called nil))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'read-string)
                 (lambda (&rest _) "should-not-be-read"))
                ((symbol-function 'a3madkour/create-project-notes)
                 (lambda (&rest _) (setq create-notes-called t)))
                ((symbol-function 'a3madkour/archive-subtree-to-file)
                 (lambda (&rest _) (error "should not archive"))))
        (a3madkour/complete-project))
      (should create-notes-called)
      (goto-char (point-min))
      (re-search-forward "^\\* Foo")
      (org-back-to-heading t)
      ;; No completion side effects:
      (should-not (org-entry-get nil "ACCOMPLISHED"))
      (should (member "active" (org-get-tags nil t)))
      (should-not (member "done" (org-get-tags nil t))))))

(ert-deftest a3madkour-test/complete-project-rejects-non-project ()
  (a3madkour-test/in-buffer "* Some random heading\n"
    (re-search-forward "Some random")
    (should-error (a3madkour/complete-project) :type 'user-error)))

;;; ---- a3madkour/drop-project ----

(ert-deftest a3madkour-test/drop-project-happy-path ()
  (a3madkour-test/in-buffer "\
* Foo                                                       :project:active:
"
    (re-search-forward "^\\* Foo")
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
              ((symbol-function 'read-string) (lambda (&rest _) "no time"))
              ((symbol-function 'a3madkour/archive-subtree-to-file)
               (lambda (&rest _) nil)))
      (a3madkour/drop-project))
    (goto-char (point-min))
    (re-search-forward "^\\* Foo")
    (org-back-to-heading t)
    (should (equal "no time" (org-entry-get nil "DROP_REASON")))
    (should (org-entry-get nil "DROPPED"))
    (let ((tags (org-get-tags nil t)))
      (should-not (member "active" tags))
      (should (member "dropped" tags)))))

(ert-deftest a3madkour-test/drop-project-cancelled ()
  (a3madkour-test/in-buffer "\
* Foo                                                       :project:active:
"
    (re-search-forward "^\\* Foo")
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
              ((symbol-function 'a3madkour/archive-subtree-to-file)
               (lambda (&rest _) (error "should not archive"))))
      (should-error (a3madkour/drop-project) :type 'user-error))))

(provide 'test-project-lifecycle)
;;; test-project-lifecycle.el ends here
