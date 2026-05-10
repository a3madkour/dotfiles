;;; test-helpers.el --- Shared infra for task-management tests  -*- lexical-binding: t; -*-

;; Loads only the a3madkour/ defun/defvar/defcustom forms from config.org —
;; avoids pulling in use-package and other unavailable third-party packages.
;; Stubs org-roam (override per-test where finer behavior is needed).

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-agenda)
(require 'subr-x)

;; ---- Stubs for unavailable third-party packages ----
(unless (fboundp 'org-roam-node-create)
  (defun org-roam-node-create (&rest _) nil))
(unless (fboundp 'org-roam-node-slug)
  (defun org-roam-node-slug (_node) "test-slug"))
(unless (fboundp 'org-roam-capture-)
  (defun org-roam-capture- (&rest _) nil))
(unless (fboundp 'org-roam-db-update-file)
  (defun org-roam-db-update-file (&rest _) nil))
(unless (boundp 'org-roam-directory)
  (defvar org-roam-directory "/tmp/test-org-roam-unused"))

;; cl-incf is needed by active-project-count
(eval-when-compile (require 'cl-macs))

;; org-state is a dynamic var set by org-mode during state-change hooks.
;; Declaring it here lets test `let` bindings be dynamic (file uses
;; lexical-binding, so we must defvar to opt into dynamic scope).
(defvar org-state nil)
(defvar org-note-abort nil)

;; ---- Loader: extract a3madkour defs from config.org ----
(defvar a3madkour-test/config-org-path
  (expand-file-name "../config.org"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun a3madkour-test/load-target-defs ()
  "Read all top-level a3madkour defun/defvar/defcustom/defalias/defmacro forms
from `a3madkour-test/config-org-path' and evaluate each. This avoids loading
the full tangled config (which would pull in use-package and third-party
packages that aren't installed during batch testing)."
  (with-temp-buffer
    (insert-file-contents a3madkour-test/config-org-path)
    (goto-char (point-min))
    (let ((pattern (concat "^("
                           "\\(?:defun\\|defvar\\|defcustom\\|defalias\\|defmacro\\)"
                           "\\s-+a3madkour")))
      (while (re-search-forward pattern nil t)
        (beginning-of-line)
        (condition-case err
            (let ((form (read (current-buffer))))
              (eval form t))
          (error (message "test-helpers: skipped form near point %d: %S"
                          (point) err)
                 ;; Skip past the malformed form
                 (forward-line 1)))))))

;; Load immediately so test files can refer to the functions
(a3madkour-test/load-target-defs)

;; ---- Test macros ----
(defmacro a3madkour-test/with-org-env (files &rest body)
  "Bind `a3madkour/org-base-dir' to a fresh tmp dir, seed FILES, run BODY.
FILES is an alist of (REL-PATH . CONTENT-STRING). The tmp dir is cleaned
up unconditionally after BODY."
  (declare (indent 1) (debug t))
  `(let ((dir (make-temp-file "a3madkour-test-" t)))
     (unwind-protect
         (let ((a3madkour/org-base-dir dir))
           (dolist (f ,files)
             (let ((path (expand-file-name (car f) dir)))
               (make-directory (file-name-directory path) t)
               (with-temp-file path
                 (insert (cdr f)))))
           ,@body)
       (delete-directory dir t))))

(defun a3madkour-test/queue (values)
  "Return a lambda that pops one value from VALUES on each call.
Useful for stubbing interactive prompts that fire multiple times in sequence.
After VALUES is exhausted, the lambda returns nil."
  (let ((remaining (copy-sequence values)))
    (lambda (&rest _) (pop remaining))))

(defmacro a3madkour-test/in-buffer (content &rest body)
  "Run BODY in a temp org-mode buffer pre-filled with CONTENT.
Point starts at `point-min'."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,content)
     (org-mode)
     (goto-char (point-min))
     ,@body))

(provide 'test-helpers)
;;; test-helpers.el ends here
