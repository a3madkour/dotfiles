;;; a3madkour-agents.el --- Helpers for agent-shell and its extensions -*- lexical-binding: t; -*-

;;; Commentary:

;; Named, testable pieces of the agent-shell setup wired up in config.org
;; (* "AI" "Agents").  See docs/superpowers/specs/2026-10-11-agent-shell-only-design.md.

;;; Code:

(require 'cl-lib)
(require 'map)
(require 'seq)
(require 'subr-x)

(defgroup a3madkour-agents nil
  "Personal glue for agent-shell."
  :group 'tools)

(defvar agent-shell--state)

;;;; Advice

(defun a3madkour-agents--project-files-truename (orig-fn &rest args)
  "Call ORIG-FN with ARGS, `default-directory' resolved through symlinks.
project.el does not find projects reached through a symlinked directory."
  (let ((default-directory (file-truename default-directory)))
    (apply orig-fn args)))

(defun a3madkour-agents--opencode-diff-info (orig-fn &rest args)
  "Call ORIG-FN with ARGS; fall back to OpenCode's diff keys.
OpenCode sends oldString/newString/filePath where agent-shell expects
old_str/new_str/path."
  (or (apply orig-fn args)
      (when-let* ((acp-tool-call (plist-get args :acp-tool-call))
                  (raw-input (map-elt acp-tool-call 'rawInput))
                  (new-text (map-elt raw-input 'newString))
                  (old-text (or (map-elt raw-input 'oldString) "")))
        (append (list (cons :old old-text)
                      (cons :new new-text))
                (when-let* ((path (or (map-elt raw-input 'filePath)
                                      (map-elt raw-input 'filepath))))
                  (list (cons :file path)))))))

(defun a3madkour-agents--opencode-permission-title (orig-fn &rest args)
  "Call ORIG-FN with ARGS; recover OpenCode's bash command when generic.
OpenCode sends an empty rawInput in bash permission requests, so the
title degrades to \"bash\"/\"execute\".  Use the command saved when the
tool call was announced instead."
  (let ((result (apply orig-fn args)))
    (if (and result
             (not (string= result "bash"))
             (not (string= result "execute")))
        result
      (when-let* ((acp-request (plist-get args :acp-request))
                  (tool-call-id (map-nested-elt acp-request
                                                '(params toolCall toolCallId)))
                  (saved (map-nested-elt agent-shell--state
                                         (list :tool-calls tool-call-id)))
                  (command (map-elt saved :command)))
        (if (equal (map-elt saved :kind) "execute")
            (concat "```console\n" command "\n```")
          command)))))

(provide 'a3madkour-agents)
;;; a3madkour-agents.el ends here
