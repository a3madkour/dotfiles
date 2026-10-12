;;; a3madkour-agents-test.el --- Tests for agent-shell helpers -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-agents)

;; Special in the module; declare here too so `let' binds dynamically.
(defvar agent-shell--state)

;;;; OpenCode diff info

(ert-deftest a3madkour-agents-test/diff-info-passes-through ()
  (should (eq 'orig (a3madkour-agents--opencode-diff-info
                     (lambda (&rest _) 'orig) :acp-tool-call nil))))

(ert-deftest a3madkour-agents-test/diff-info-opencode-keys ()
  (let ((call '((rawInput . ((oldString . "a") (newString . "b") (filePath . "/p/x.el"))))))
    (should (equal '((:old . "a") (:new . "b") (:file . "/p/x.el"))
                   (a3madkour-agents--opencode-diff-info
                    (lambda (&rest _) nil) :acp-tool-call call)))))

(ert-deftest a3madkour-agents-test/diff-info-lowercase-filepath-missing-old ()
  (let ((call '((rawInput . ((newString . "b") (filepath . "/p/y.el"))))))
    (should (equal '((:old . "") (:new . "b") (:file . "/p/y.el"))
                   (a3madkour-agents--opencode-diff-info
                    (lambda (&rest _) nil) :acp-tool-call call)))))

(ert-deftest a3madkour-agents-test/diff-info-no-path ()
  (let ((call '((rawInput . ((oldString . "a") (newString . "b"))))))
    (should (equal '((:old . "a") (:new . "b"))
                   (a3madkour-agents--opencode-diff-info
                    (lambda (&rest _) nil) :acp-tool-call call)))))

(ert-deftest a3madkour-agents-test/diff-info-no-newstring-is-nil ()
  (let ((call '((rawInput . ((oldString . "a"))))))
    (should-not (a3madkour-agents--opencode-diff-info
                 (lambda (&rest _) nil) :acp-tool-call call))))

;;;; OpenCode permission title

(defun a3madkour-agents-test--request (id)
  `((params . ((toolCall . ((toolCallId . ,id)))))))

(ert-deftest a3madkour-agents-test/permission-title-specific-passes-through ()
  (should (equal "Edit foo.el"
                 (a3madkour-agents--opencode-permission-title
                  (lambda (&rest _) "Edit foo.el") :acp-request nil))))

(ert-deftest a3madkour-agents-test/permission-title-execute-from-state ()
  (let ((agent-shell--state
         '((:tool-calls . (("t1" . ((:command . "ls -la") (:kind . "execute"))))))))
    (should (equal "```console\nls -la\n```"
                   (a3madkour-agents--opencode-permission-title
                    (lambda (&rest _) "bash")
                    :acp-request (a3madkour-agents-test--request "t1"))))))

(ert-deftest a3madkour-agents-test/permission-title-other-kind-plain ()
  (let ((agent-shell--state
         '((:tool-calls . (("t2" . ((:command . "rm x") (:kind . "other"))))))))
    (should (equal "rm x"
                   (a3madkour-agents--opencode-permission-title
                    (lambda (&rest _) "execute")
                    :acp-request (a3madkour-agents-test--request "t2"))))))

(ert-deftest a3madkour-agents-test/permission-title-generic-unknown-id-is-nil ()
  "Pins the pre-existing behaviour: generic title + no saved call => nil."
  (let ((agent-shell--state '((:tool-calls . nil))))
    (should-not (a3madkour-agents--opencode-permission-title
                 (lambda (&rest _) "bash")
                 :acp-request (a3madkour-agents-test--request "nope")))))

;;;; Symlinked project dirs

(ert-deftest a3madkour-agents-test/project-files-truename ()
  (let* ((real (make-temp-file "a3ag-real" t))
         (link (expand-file-name (make-temp-name "a3ag-link") temporary-file-directory)))
    (unwind-protect
        (progn
          (make-symbolic-link real link)
          (let ((default-directory (file-name-as-directory link)))
            (should (equal (file-name-as-directory (file-truename real))
                           (file-name-as-directory
                            (a3madkour-agents--project-files-truename
                             (lambda () default-directory)))))))
      (delete-file link)
      (delete-directory real))))

;;;; Prerequisites

(ert-deftest a3madkour-agents-test/missing-executables ()
  (cl-letf (((symbol-function 'executable-find)
             (lambda (name &rest _) (member name '("present" "podman")))))
    (should (equal '(("absent" . "install absent"))
                   (a3madkour-agents-missing-executables
                    '(("present" . "x")
                      ("absent" . "install absent")
                      (("docker" "podman") . "any one is fine")))))))

(ert-deftest a3madkour-agents-test/check-prereqs-warns-once ()
  (let ((a3madkour-agents--prereqs-checked nil)
        (a3madkour-agents-required-executables '(("absent" . "install it")))
        (warnings nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil))
              ((symbol-function 'display-warning)
               (lambda (type msg &rest _) (push (cons type msg) warnings))))
      (a3madkour-agents-check-prereqs)
      (a3madkour-agents-check-prereqs)
      (should (= 1 (length warnings)))
      (should (eq 'a3madkour-agents (caar warnings)))
      (should (string-match-p "absent.*install it" (cdar warnings))))))

(ert-deftest a3madkour-agents-test/check-prereqs-silent-when-all-present ()
  (let ((a3madkour-agents--prereqs-checked nil)
        (a3madkour-agents-required-executables '(("here" . "x")))
        (warned nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/bin/here"))
              ((symbol-function 'display-warning) (lambda (&rest _) (setq warned t))))
      (a3madkour-agents-check-prereqs)
      (should-not warned))))

;;;; Optional commands

(ert-deftest a3madkour-agents-test/optional-missing-command-errors ()
  (let ((err (should-error (a3madkour-agents--call-optional
                            'a3madkour-agents-test--does-not-exist "fake-pkg")
                           :type 'user-error)))
    (should (string-match-p "fake-pkg" (cadr err)))))

(ert-deftest a3madkour-agents-test/optional-calls-through-with-prefix ()
  (let (seen)
    (cl-letf (((symbol-function 'a3madkour-agents-test--target)
               (lambda (arg) (interactive "P") (setq seen (list 'called arg)))))
      (let ((current-prefix-arg '(4)))
        (a3madkour-agents--call-optional 'a3madkour-agents-test--target "x"))
      (should (equal '(called (4)) seen)))))

(ert-deftest a3madkour-agents-test/define-optional-makes-command ()
  (should (commandp 'a3madkour-agents-meta-session))
  (should (commandp 'a3madkour-agents-circus-toggle-cmd))
  (should (commandp 'a3madkour-agents-slack-connect-cmd)))

(provide 'a3madkour-agents-test)
;;; a3madkour-agents-test.el ends here
