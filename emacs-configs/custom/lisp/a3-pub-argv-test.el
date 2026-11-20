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

(defvar a3-pub-argv-test--script nil
  "The a3-pub.sh to run; nil means the one beside this file.")

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
                               (or a3-pub-argv-test--script
                                   (expand-file-name "a3-pub.sh"
                                                     a3-pub-argv-test--lisp-dir))
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

(defun a3-pub-argv-test--placeholders (arg)
  "ARG with its paths replaced by placeholders, newlines kept.
Replacements, in this order: the lisp dir -> <LISP_DIR>, the custom dir ->
<CUSTOM_DIR>, <TMP>/publish-paths.el -> <PATHS_FILE>, <TMP>/data ->
<SITE_DATA>, any other <TMP> -> <TMP>."
  (let* ((lisp (directory-file-name a3-pub-argv-test--lisp-dir))
         (custom (directory-file-name (file-name-directory lisp)))
         (tmp a3-pub-argv-test--tmp))
    (dolist (r (list (cons lisp "<LISP_DIR>") (cons custom "<CUSTOM_DIR>")
                     (cons (concat tmp "/publish-paths.el") "<PATHS_FILE>")
                     (cons (concat tmp "/data") "<SITE_DATA>")
                     (cons tmp "<TMP>")))
      (setq arg (replace-regexp-in-string (regexp-quote (car r)) (cdr r) arg t t)))
    arg))

(defun a3-pub-argv-test--normalise (argv)
  "ARGV as text: one argument per line, newlines as backslash-n, paths as placeholders.
See `a3-pub-argv-test--placeholders' for the replacements."
  (mapconcat
   (lambda (a)
     (replace-regexp-in-string "\n" "\\n" (a3-pub-argv-test--placeholders a) t t))
   argv "\n"))

(defconst a3-pub-argv-test--modes
  '(("check-orphans" "--check-orphans")
    ("publish-living" "--publish-living")
    ("publish-deliberate" "--publish-deliberate" "<TMP>/x.org")
    ("sync-citations" "--sync-citations")
    ("default" "--eval" "(message \"hi\")"))
  "Mode name followed by its argument list; <TMP> is replaced by a temp dir.")

(defun a3-pub-argv-test--run-mode (mode &rest extra)
  "Run MODE's arguments, then EXTRA; return (EXIT . ARGV) with the raw argv."
  (let* ((tmpfile (make-temp-file "a3-pub-x-" nil ".org"))
         (args (append
                (mapcar (lambda (a) (if (equal a "<TMP>/x.org") tmpfile a))
                        (cdr (assoc mode a3-pub-argv-test--modes)))
                extra)))
    (unwind-protect (apply #'a3-pub-argv-test--run args)
      (delete-file tmpfile))))

(defun a3-pub-argv-test-dump (dir &optional raw)
  "Write the normalised argv of each mode to DIR/<mode>.txt, plus exit codes.
With RAW, write DIR/<mode>.raw instead: each argument with placeholders but
its newlines kept, NUL-terminated."
  (make-directory dir t)
  (dolist (m a3-pub-argv-test--modes)
    (let* ((r (a3-pub-argv-test--run-mode (car m)))
           (text (if raw
                     (mapconcat (lambda (a) (concat (a3-pub-argv-test--placeholders a) "\0"))
                                (cdr r) "")
                   (concat (a3-pub-argv-test--normalise (cdr r)) "\n"))))
      (let ((coding-system-for-write 'utf-8-unix))
        (with-temp-file (expand-file-name (concat (car m) (if raw ".raw" ".txt")) dir)
          (insert text)))
      (message "%s exit=%s" (car m) (car r)))))

(defun a3-pub-argv-test--modules (argv)
  "The arguments following \"-l\" in ARGV that start with \"a3madkour-\"."
  (cl-loop for (a b) on argv
           when (and (equal a "-l") b (string-prefix-p "a3madkour-" b))
           collect b))

(defun a3-pub-argv-test--common-block (argv)
  "The bootstrap part of ARGV: from \"--batch\" through the paths file.
The module `-l's that follow it are left out.  Paths are replaced by
placeholders so runs in different temp dirs compare."
  (let ((start (cl-position "--batch" argv :test #'equal))
        (paths (cl-position-if (lambda (a) (string-suffix-p "/publish-paths.el" a))
                               argv)))
    (mapcar #'a3-pub-argv-test--placeholders (cl-subseq argv start (1+ paths)))))

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

(defconst a3-pub-argv-test--todays-modules
  '(("check-orphans"
     "a3madkour-publish" "a3madkour-publish-registry" "a3madkour-publish-rewrite"
     "a3madkour-publish-assets" "a3madkour-publish-unpublish")
    ("publish-living"
     "a3madkour-publish" "a3madkour-publish-registry" "a3madkour-publish-rewrite"
     "a3madkour-publish-assets" "a3madkour-publish-unpublish"
     "a3madkour-publish-export" "a3madkour-publish-frontmatter" "a3madkour-sections"
     "a3madkour-publish-living" "a3madkour-publish-deliberate" "a3madkour-publish-garden"
     "a3madkour-publish-library" "a3madkour-library-items"
     "a3madkour-publish-library-notes" "a3madkour-publish-research"
     "a3madkour-recipe-lint" "a3madkour-publish-recipes" "a3madkour-works-lint"
     "a3madkour-publish-works" "a3madkour-publish-bib" "a3madkour-publish-citations")
    ("publish-deliberate"
     "a3madkour-publish" "a3madkour-publish-registry" "a3madkour-publish-rewrite"
     "a3madkour-publish-assets" "a3madkour-publish-unpublish"
     "a3madkour-publish-export" "a3madkour-publish-frontmatter" "a3madkour-sections"
     "a3madkour-publish-living" "a3madkour-publish-deliberate" "a3madkour-publish-garden"
     "a3madkour-publish-library" "a3madkour-library-items"
     "a3madkour-publish-library-notes" "a3madkour-publish-research"
     "a3madkour-recipe-lint" "a3madkour-publish-recipes" "a3madkour-works-lint"
     "a3madkour-publish-works" "a3madkour-publish-essays" "a3madkour-publish-poetry"
     "a3madkour-publish-bib" "a3madkour-publish-citations"
     "a3madkour-publish-multi-filter" "a3madkour-publish-multi-pdf"
     "a3madkour-publish-multi-word" "a3madkour-publish-multi")
    ("sync-citations"
     "a3madkour-publish" "a3madkour-publish-registry" "a3madkour-publish-rewrite"
     "a3madkour-publish-assets" "a3madkour-publish-unpublish"
     "a3madkour-publish-history" "a3madkour-publish-bib" "a3madkour-publish-citations"))
  "Each publish mode's modules, in order, as recorded before the one-bootstrap refactor.
Some modules act on load, so these lists change only on purpose.")

(ert-deftest a3-pub-argv-test-publish-modes-load-exactly-todays-modules ()
  (skip-unless (a3-pub-argv-test--straight-p))
  (dolist (entry a3-pub-argv-test--todays-modules)
    (should (equal (cons (car entry)
                         (a3-pub-argv-test--modules
                          (cdr (a3-pub-argv-test--run-mode (car entry)))))
                   entry)))
  (let ((default (a3-pub-argv-test--modules
                  (cdr (a3-pub-argv-test--run-mode "default")))))
    (dolist (entry a3-pub-argv-test--todays-modules)
      (dolist (m (cdr entry))
        (should (member m default))))))

(ert-deftest a3-pub-argv-test-custom-dir-is-not-spliced-into-lisp ()
  ;; A copy of the script in a lisp dir under a custom dir whose name holds a
  ;; space and a double quote, beside a stand-in straight bootstrap.
  (let* ((root (file-name-as-directory (make-temp-file "a3-pub-custom-" t)))
         (custom (expand-file-name "my \"custom\" dir" root))
         (lisp (expand-file-name "lisp" custom))
         (bootstrap (expand-file-name "straight/repos/straight.el/bootstrap.el" custom))
         (a3-pub-argv-test--script (expand-file-name "a3-pub.sh" lisp)))
    (unwind-protect
        (progn
          (make-directory lisp t)
          (make-directory (file-name-directory bootstrap) t)
          (with-temp-file bootstrap (insert ";; stand-in\n"))
          (copy-file (expand-file-name "a3-pub.sh" a3-pub-argv-test--lisp-dir)
                     a3-pub-argv-test--script)
          (dolist (m a3-pub-argv-test--modes)
            (let* ((r (a3-pub-argv-test--run-mode (car m)))
                   (argv (cdr r)))
              (should (= (car r) 0))
              (should argv)
              (should-not (cl-loop for (a b) on argv
                                   thereis (and (equal a "--eval")
                                                (string-match-p "custom\\\\?\"" b))))
              (should (equal (cadr (member "-L" argv)) lisp))
              (should (member bootstrap argv)))))
      (delete-directory root t))))

(ert-deftest a3-pub-argv-test-script-has-one-batch-invocation ()
  (let ((text (with-temp-buffer
                (insert-file-contents (expand-file-name "a3-pub.sh"
                                                        a3-pub-argv-test--lisp-dir))
                (buffer-string))))
    (should (= 1 (with-temp-buffer
                   (insert text)
                   (goto-char (point-min))
                   (how-many "emacs --batch"))))))

(ert-deftest a3-pub-argv-test-every-mode-passes-extra-args-through ()
  ;; Each non-default mode appends the arguments after its own to emacs's
  ;; argv unchanged, after the mode's own --evals.
  (skip-unless (a3-pub-argv-test--straight-p))
  (let ((extra '("--eval" "(message \"extra %s\" \"a b\")" "plain arg")))
    (dolist (m '("check-orphans" "publish-living" "publish-deliberate" "sync-citations"))
      (let* ((r (apply #'a3-pub-argv-test--run-mode m extra))
             (with (mapcar #'a3-pub-argv-test--placeholders (cdr r)))
             (without (mapcar #'a3-pub-argv-test--placeholders
                              (cdr (a3-pub-argv-test--run-mode m)))))
        (should (= (car r) 0))
        (should (equal (last with 3) extra))
        (should (equal (butlast with 3) without))))))

(ert-deftest a3-pub-argv-test-common-block-is-identical-across-modes ()
  (skip-unless (a3-pub-argv-test--straight-p))
  (let ((blocks (mapcar (lambda (m)
                          (a3-pub-argv-test--common-block
                           (cdr (a3-pub-argv-test--run-mode (car m)))))
                        a3-pub-argv-test--modes)))
    (should (member "-L" (car blocks)))
    (should (member "<PATHS_FILE>" (car blocks)))
    (should (member "(straight-use-package 'yaml)" (car blocks)))
    (should-not (member "a3madkour-publish" (car blocks)))
    (should (cl-every (lambda (b) (equal b (car blocks))) blocks))))

(provide 'a3-pub-argv-test)

;;; a3-pub-argv-test.el ends here
