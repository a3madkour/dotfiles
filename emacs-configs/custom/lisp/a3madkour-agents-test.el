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

;;;; Perspectives

(defvar persp-mode)

(defmacro a3madkour-agents-test--with-persps (current table &rest body)
  "Run BODY with perspective.el stubbed: CURRENT name, TABLE alist name->buffers.
Binds `switched' to the name passed to `persp-switch', if any."
  (declare (indent 2))
  `(let ((persp-mode t) (switched nil))
     (cl-letf (((symbol-function 'persp-current-name) (lambda () ,current))
               ((symbol-function 'persp-names) (lambda () (mapcar #'car ,table)))
               ((symbol-function 'persp-get-buffers)
                (lambda (&optional name _frame) (cdr (assoc (or name ,current) ,table))))
               ((symbol-function 'persp-switch)
                (lambda (name &rest _) (setq switched name))))
       ,@body)))

(ert-deftest a3madkour-agents-test/persp-switches-to-owner ()
  (let ((buf (generate-new-buffer " a3ag")))
    (unwind-protect
        (a3madkour-agents-test--with-persps "main" `(("main") ("work" ,buf))
          (a3madkour-agents-switch-to-owner-persp buf)
          (should (equal "work" switched)))
      (kill-buffer buf))))

(ert-deftest a3madkour-agents-test/persp-noop-when-in-current ()
  (let ((buf (generate-new-buffer " a3ag")))
    (unwind-protect
        (a3madkour-agents-test--with-persps "main" `(("main" ,buf) ("work" ,buf))
          (a3madkour-agents-switch-to-owner-persp buf)
          (should-not switched))
      (kill-buffer buf))))

(ert-deftest a3madkour-agents-test/persp-noop-when-unowned ()
  (let ((buf (generate-new-buffer " a3ag")))
    (unwind-protect
        (a3madkour-agents-test--with-persps "main" '(("main") ("work"))
          (a3madkour-agents-switch-to-owner-persp buf)
          (should-not switched))
      (kill-buffer buf))))

(ert-deftest a3madkour-agents-test/persp-noop-when-mode-off ()
  (let ((buf (generate-new-buffer " a3ag")))
    (unwind-protect
        (a3madkour-agents-test--with-persps "main" `(("main") ("work" ,buf))
          (let ((persp-mode nil))
            (a3madkour-agents-switch-to-owner-persp buf))
          (should-not switched))
      (kill-buffer buf))))

;;;; Evil remaps

(require 'evil)

(defvar a3madkour-agents-test--map (make-sparse-keymap))

(ert-deftest a3madkour-agents-test/evil-bind-from-table ()
  (let ((a3madkour-agents-evil-bindings
         '((a3madkour-agents-test--map nil (("x" . kill-buffer) ("gr" . revert-buffer))))))
    (a3madkour-agents-evil-bind 'a3madkour-agents-test--map)
    (let ((aux (evil-get-auxiliary-keymap a3madkour-agents-test--map 'normal)))
      (should (eq 'kill-buffer (lookup-key aux (kbd "x"))))
      (should (eq 'revert-buffer (lookup-key aux (kbd "gr")))))))

(ert-deftest a3madkour-agents-test/evil-table-pins-design ()
  "Keys from spec §1.4 that collide with evil or evil-collection."
  (cl-flet ((cmd (map key)
              (alist-get key (nth 2 (assq map a3madkour-agents-evil-bindings))
                         nil nil #'equal)))
    (should (eq 'agent-shell-manager-kill (cmd 'agent-shell-manager-mode-map "x")))
    (should (eq 'agent-shell-manager-goto (cmd 'agent-shell-manager-mode-map "RET")))
    (should (eq 'agent-shell-manager-refresh (cmd 'agent-shell-manager-mode-map "gr")))
    (should (eq 'agent-shell-attention-dashboard-open-ambient-directory
                (cmd 'agent-shell-attention-dashboard-mode-map "J")))
    (should (eq 'agent-review-send-to-agent-shell (cmd 'agent-review-mode-map "S")))
    (should (eq 'agent-review-refresh (cmd 'agent-review-mode-map "gr")))
    ;; every key must parse
    (dolist (entry a3madkour-agents-evil-bindings)
      (dolist (binding (nth 2 entry))
        (should (kbd (car binding)))))))

;;;; meta-agent-shell

(defvar agent-shell-cwd-function nil)
(defvar meta-agent-shell--pending-decorator nil)

(defmacro a3madkour-agents-test--with-fake-start (&rest body)
  "Run BODY with `agent-shell--start' stubbed.
Binds `start-args' (keyword plist received) and `start-cwd' (value of
`agent-shell-cwd-function' at call time, funcalled), and `made' (buffers)."
  (declare (indent 0))
  `(let (start-args start-cwd made)
     (cl-letf (((symbol-function 'agent-shell--start)
                (lambda (&rest args)
                  (setq start-args args
                        start-cwd (and agent-shell-cwd-function
                                       (funcall agent-shell-cwd-function)))
                  (car (push (generate-new-buffer "*fake-agent*") made)))))
       (unwind-protect (progn ,@body)
         (mapc #'kill-buffer (seq-filter #'buffer-live-p made))))))

(ert-deftest a3madkour-agents-test/meta-start-defaults ()
  (let ((a3madkour-agents-meta-config-function (lambda () '((:identifier . claude-code)))))
    (a3madkour-agents-test--with-fake-start
      (let ((buf (a3madkour-agents-meta-start)))
        (should (bufferp buf))
        (should (eq buf (current-buffer)))
        (should (equal '((:identifier . claude-code)) (plist-get start-args :config)))
        (should (eq t (plist-get start-args :new-session)))
        (should (eq 'new (plist-get start-args :session-strategy)))
        (should-not start-cwd)))))

(ert-deftest a3madkour-agents-test/meta-start-use-current-dir-and-name ()
  (let ((a3madkour-agents-meta-config-function #'ignore)
        (default-directory "/tmp/proj/sub/"))
    (a3madkour-agents-test--with-fake-start
      (let ((buf (a3madkour-agents-meta-start 'use-current-dir "Worker")))
        (should (equal "/tmp/proj/sub/" start-cwd))
        (should (equal "Worker" (buffer-name buf)))))))

(ert-deftest a3madkour-agents-test/meta-start-name-collision-is-unique ()
  (let ((a3madkour-agents-meta-config-function #'ignore)
        (taken (get-buffer-create "Dispatcher")))
    (unwind-protect
        (a3madkour-agents-test--with-fake-start
          (let ((buf (a3madkour-agents-meta-start nil "Dispatcher")))
            (should (buffer-live-p buf))
            (should-not (eq buf taken))
            (should (string-prefix-p "Dispatcher" (buffer-name buf)))))
      (kill-buffer taken))))

(ert-deftest a3madkour-agents-test/meta-start-passes-pending-decorator ()
  (let ((a3madkour-agents-meta-config-function #'ignore)
        (meta-agent-shell--pending-decorator #'identity))
    (a3madkour-agents-test--with-fake-start
      (a3madkour-agents-meta-start)
      (should (eq #'identity (plist-get start-args :outgoing-request-decorator))))))

(ert-deftest a3madkour-agents-test/meta-project-path-prefers-project-el ()
  (cl-letf (((symbol-function 'project-current) (lambda (&rest _) 'proj))
            ((symbol-function 'project-root) (lambda (_) "/tmp/root/")))
    (should (equal "/tmp/root/"
                   (a3madkour-agents--meta-project-path (lambda () "/fallback/"))))))

(ert-deftest a3madkour-agents-test/meta-project-path-falls-back ()
  (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil)))
    (should (equal "/fallback/"
                   (a3madkour-agents--meta-project-path (lambda () "/fallback/"))))))

;;;; agent-circus

(defmacro a3madkour-agents-test--with-circus (root on &rest body)
  "Run BODY with agent-shell stubbed: cwd ROOT, circus ON for ROOT if non-nil."
  (declare (indent 2))
  `(let ((a3madkour-agents-circus-projects (and ,on (list ,root))))
     (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () ,root)))
       ,@body)))

(ert-deftest a3madkour-agents-test/circus-prefix-off-is-nil ()
  (a3madkour-agents-test--with-circus "/p/" nil
    (with-temp-buffer
      (should-not (a3madkour-agents-circus-command-prefix (current-buffer))))))

(ert-deftest a3madkour-agents-test/circus-prefix-maps-identifiers ()
  (a3madkour-agents-test--with-circus "/p/" t
    (with-temp-buffer
      (dolist (pair '((claude-code . "claude-code") (codex . "codex") (opencode . "opencode")))
        (cl-letf (((symbol-function 'agent-shell-get-config)
                   (lambda (_) `((:identifier . ,(car pair))))))
          (should (equal (list "agent-circus" "exec" (cdr pair) "--")
                         (a3madkour-agents-circus-command-prefix (current-buffer)))))))))

(ert-deftest a3madkour-agents-test/circus-prefix-unknown-agent-errors ()
  (a3madkour-agents-test--with-circus "/p/" t
    (with-temp-buffer
      (cl-letf (((symbol-function 'agent-shell-get-config)
                 (lambda (_) '((:identifier . gemini-cli)))))
        (should-error (a3madkour-agents-circus-command-prefix (current-buffer))
                      :type 'user-error)))))

(ert-deftest a3madkour-agents-test/circus-dir-local-enables ()
  (a3madkour-agents-test--with-circus "/p/" nil
    (with-temp-buffer
      (setq-local a3madkour-agents-circus-enabled t)
      (should (a3madkour-agents-circus-active-p (current-buffer))))))

(ert-deftest a3madkour-agents-test/circus-resolve-identity-when-off ()
  (a3madkour-agents-test--with-circus "/p/" nil
    (with-temp-buffer
      (should (equal "/p/a.el" (a3madkour-agents-circus-resolve-path "/p/a.el")))
      (should (equal "/workspace/a.el" (a3madkour-agents-circus-resolve-path "/workspace/a.el"))))))

(ert-deftest a3madkour-agents-test/circus-resolve-round-trip ()
  (a3madkour-agents-test--with-circus "/p/" t
    (with-temp-buffer
      (should (equal "/workspace/src/a.el" (a3madkour-agents-circus-resolve-path "/p/src/a.el")))
      (should (equal "/p/src/a.el" (a3madkour-agents-circus-resolve-path "/workspace/src/a.el"))))))

(ert-deftest a3madkour-agents-test/circus-resolve-edges ()
  (a3madkour-agents-test--with-circus "/p/" t
    (with-temp-buffer
      (should (equal "/p/" (a3madkour-agents-circus-resolve-path "/workspace")))
      (should (equal "/workspace/" (a3madkour-agents-circus-resolve-path "/p")))
      (should (equal "/etc/hosts" (a3madkour-agents-circus-resolve-path "/etc/hosts")))
      (should-error (a3madkour-agents-circus-resolve-path "/workspace/../etc/passwd")))))

(ert-deftest a3madkour-agents-test/circus-toggle-flips-project ()
  (a3madkour-agents-test--with-circus "/p/" nil
    (with-temp-buffer
      (a3madkour-agents-circus-toggle)
      (should (member "/p/" a3madkour-agents-circus-projects))
      (a3madkour-agents-circus-toggle)
      (should-not (member "/p/" a3madkour-agents-circus-projects)))))

;;;; Slack (agent-shell-to-go)

(defvar agent-shell-to-go-bot-token nil)
(defvar agent-shell-to-go-app-token nil)
(defvar agent-shell-to-go-channel-id nil)
(defvar agent-shell-to-go-user-id nil)
(defvar agent-shell-to-go-authorized-users nil)

(defmacro a3madkour-agents-test--with-keychain (items &rest body)
  "Run BODY with Keychain stubbed to ITEMS (alist account -> secret)."
  (declare (indent 1))
  `(let ((agent-shell-to-go-bot-token nil) (agent-shell-to-go-app-token nil)
         (agent-shell-to-go-channel-id nil) (agent-shell-to-go-user-id nil)
         (agent-shell-to-go-authorized-users nil))
     (cl-letf (((symbol-function 'a3madkour-agents-keychain-secret)
                (lambda (account) (cdr (assoc account ,items)))))
       ,@body)))

(ert-deftest a3madkour-agents-test/slack-load-all ()
  (a3madkour-agents-test--with-keychain
      '(("bot-token" . "xoxb-1") ("app-token" . "xapp-1")
        ("channel-id" . "C1") ("user-id" . "U1"))
    (should-not (a3madkour-agents-slack-load-credentials))
    (should (equal "xoxb-1" agent-shell-to-go-bot-token))
    (should (equal "xapp-1" agent-shell-to-go-app-token))
    (should (equal "C1" agent-shell-to-go-channel-id))
    (should (equal '("U1") agent-shell-to-go-authorized-users))))

(ert-deftest a3madkour-agents-test/slack-partial-refuses-connect ()
  (a3madkour-agents-test--with-keychain '(("bot-token" . "xoxb-1"))
    (let (setup-called)
      (cl-letf (((symbol-function 'a3madkour-agents--slack-available-p) (lambda () t))
                ((symbol-function 'agent-shell-to-go-setup)
                 (lambda () (setq setup-called t))))
        (let ((err (should-error (a3madkour-agents-slack-connect) :type 'user-error)))
          (should (string-match-p "app-token" (cadr err)))
          (should (string-match-p "user-id" (cadr err))))
        (should-not setup-called)
        (should-not agent-shell-to-go-authorized-users)))))

(ert-deftest a3madkour-agents-test/slack-connect-calls-setup ()
  (a3madkour-agents-test--with-keychain
      '(("bot-token" . "b") ("app-token" . "a") ("channel-id" . "c") ("user-id" . "u"))
    (let (setup-called)
      (cl-letf (((symbol-function 'a3madkour-agents--slack-available-p) (lambda () t))
                ((symbol-function 'agent-shell-to-go-setup)
                 (lambda () (setq setup-called t))))
        (a3madkour-agents-slack-connect)
        (should setup-called)))))

(ert-deftest a3madkour-agents-test/keychain-secret-missing-is-nil ()
  (cl-letf (((symbol-function 'process-lines)
             (lambda (&rest _) (error "security: item not found"))))
    (should-not (a3madkour-agents-keychain-secret "bot-token"))))

(provide 'a3madkour-agents-test)
;;; a3madkour-agents-test.el ends here
