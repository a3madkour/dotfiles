;;; a3-pub-argv-test.el --- record what a3-pub.sh passes to emacs  -*- lexical-binding: t; -*-
;;; Commentary:
;;; Runs a3-pub.sh with a fake `emacs' first on PATH that records each
;;; argument as a NUL-terminated record and exits 0.  The tests describe the
;;; script as it is; `a3-pub-argv-test-dump' writes the normalised argv of
;;; every mode to a directory so a refactor can be diffed against it.
;;; Code:

(require 'ert)
(require 'cl-lib)

(defconst a3-pub-argv-test--lisp-dir
  (file-name-directory (or load-file-name buffer-file-name)))

(defun a3-pub-argv-test--straight-p ()
  (file-exists-p (expand-file-name
                  "../straight/repos/straight.el/bootstrap.el"
                  a3-pub-argv-test--lisp-dir)))

(defvar a3-pub-argv-test--tmp nil
  "Temp root of the current run, for `a3-pub-argv-test--normalise'.")

(defun a3-pub-argv-test--run (&rest args)
  "Run a3-pub.sh with ARGS under a fake emacs.
Returns (EXIT-CODE . ARGV), ARGV being the arguments the fake recorded."
  (let* ((tmp (file-name-as-directory (make-temp-file "a3-pub-argv-" t)))
         (bin (expand-file-name "bin/" tmp))
         (fake (expand-file-name "emacs" bin))
         (record (expand-file-name "argv.rec" tmp))
         (paths (expand-file-name "publish-paths.el" tmp))
         (data (expand-file-name "data/" tmp)))
    (unwind-protect
        (progn
          (make-directory bin)
          (make-directory data)
          (with-temp-file paths (insert ";; empty\n"))
          (with-temp-file fake
            (insert "#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$A3_PUB_ARGV_FILE\"\nexit 0\n"))
          (set-file-modes fake #o755)
          (setq a3-pub-argv-test--tmp (directory-file-name tmp))
          (let ((process-environment
                 (append (list (format "PATH=%s:%s" (directory-file-name bin)
                                       (getenv "PATH"))
                               (format "A3_PUB_ARGV_FILE=%s" record)
                               (format "A3_PUB_PATHS_FILE=%s" paths)
                               (format "A3_PUB_SITE_DATA_DIR=%s" data)
                               "A3_PUB_SKIP_MATH_CHECK=1")
                         process-environment)))
            (let ((code (apply #'call-process "bash" nil nil nil
                               (expand-file-name "a3-pub.sh"
                                                 a3-pub-argv-test--lisp-dir)
                               args)))
              (cons code
                    (when (file-exists-p record)
                      (let ((s (with-temp-buffer
                                 (set-buffer-multibyte nil)
                                 (insert-file-contents-literally record)
                                 (decode-coding-string (buffer-string) 'utf-8))))
                        (butlast (split-string s "\0"))))))))
      (delete-directory tmp t))))

(defun a3-pub-argv-test--before-p (a b argv)
  "Non-nil when A occurs in ARGV before B."
  (let ((ia (cl-position a argv :test #'equal))
        (ib (cl-position b argv :test #'equal)))
    (and ia ib (< ia ib))))

(defun a3-pub-argv-test--normalise (argv)
  "ARGV as text: one argument per line, newlines as backslash-n, paths as placeholders.
Replacements, in this order: the lisp dir -> <LISP_DIR>, the custom dir ->
<CUSTOM_DIR>, <TMP>/publish-paths.el -> <PATHS_FILE>, <TMP>/data ->
<SITE_DATA>, any other <TMP> -> <TMP>."
  (let* ((lisp (directory-file-name a3-pub-argv-test--lisp-dir))
         (custom (file-name-directory lisp))
         (custom (directory-file-name custom))
         (tmp a3-pub-argv-test--tmp))
    (mapconcat
     (lambda (a)
       (dolist (r (list (cons lisp "<LISP_DIR>") (cons custom "<CUSTOM_DIR>")
                        (cons (concat tmp "/publish-paths.el") "<PATHS_FILE>")
                        (cons (concat tmp "/data") "<SITE_DATA>")
                        (cons tmp "<TMP>")))
         (setq a (replace-regexp-in-string (regexp-quote (car r)) (cdr r) a t t)))
       (replace-regexp-in-string "\n" "\\n" a t t))
     argv "\n")))

(defconst a3-pub-argv-test--modes
  '(("check-orphans" "--check-orphans")
    ("publish-living" "--publish-living")
    ("publish-deliberate" "--publish-deliberate" "<TMP>/x.org")
    ("sync-citations" "--sync-citations")
    ("default" "--eval" "(message \"hi\")"))
  "Mode name followed by its argument list; <TMP> is replaced by a temp dir.")

(defun a3-pub-argv-test--run-mode (mode)
  "Run MODE's arguments; return (EXIT . ARGV) with the raw argv."
  (let* ((tmpfile (make-temp-file "a3-pub-x-" nil ".org"))
         (args (mapcar (lambda (a) (if (equal a "<TMP>/x.org") tmpfile a))
                       (cdr (assoc mode a3-pub-argv-test--modes)))))
    (unwind-protect (apply #'a3-pub-argv-test--run args)
      (delete-file tmpfile))))

(defun a3-pub-argv-test-dump (dir)
  "Write the normalised argv of each mode to DIR/<mode>.txt, plus exit codes."
  (make-directory dir t)
  (dolist (m a3-pub-argv-test--modes)
    (let* ((r (a3-pub-argv-test--run-mode (car m)))
           (text (let ((a3-pub-argv-test--tmp a3-pub-argv-test--tmp))
                   (a3-pub-argv-test--normalise (cdr r)))))
      (with-temp-file (expand-file-name (concat (car m) ".txt") dir)
        (insert text "\n"))
      (message "%s exit=%s" (car m) (car r)))))

(ert-deftest a3-pub-argv-test-every-mode-has-the-common-block ()
  (skip-unless (a3-pub-argv-test--straight-p))
  (dolist (m a3-pub-argv-test--modes)
    (let* ((r (a3-pub-argv-test--run-mode (car m)))
           (argv (cdr r)))
      (should (= (car r) 0))
      (should (equal (car argv) "--batch"))
      (should (member "(setq load-prefer-newer t)" argv))
      (should (member "(setq native-comp-enable-subr-trampolines nil)" argv))
      (should (member "(straight-use-package 'yaml)" argv))
      (should (a3-pub-argv-test--before-p "-L" "a3madkour-publish" argv))
      (should (cl-some (lambda (a) (string-suffix-p "/publish-paths.el" a)) argv)))))

(ert-deftest a3-pub-argv-test-deliberate-passes-its-path-through-the-environment ()
  (skip-unless (a3-pub-argv-test--straight-p))
  (let ((argv (cdr (a3-pub-argv-test--run "--publish-deliberate"
                                          "/tmp/has \"quote\".org"))))
    (should argv)
    (should-not (cl-some (lambda (a) (string-match-p "has \\\\?\"quote" a)) argv))))

(ert-deftest a3-pub-argv-test-default-mode-passes-user-args-last ()
  (skip-unless (a3-pub-argv-test--straight-p))
  (let ((argv (cdr (a3-pub-argv-test--run "--eval" "(message \"hi\")"))))
    (should (equal (last argv 2) '("--eval" "(message \"hi\")")))))

(provide 'a3-pub-argv-test)

;;; a3-pub-argv-test.el ends here
