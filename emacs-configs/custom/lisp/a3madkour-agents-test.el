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

(provide 'a3madkour-agents-test)
;;; a3madkour-agents-test.el ends here
