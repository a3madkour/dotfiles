;;; a3madkour-sections-fixture.el --- test support for the section contract  -*- lexical-binding: t; -*-

;;; Commentary:

;; Test support, not a test.  Its name deliberately does not match
;; run-tests.sh's `*-test.el' glob: a file that is both `require'd by test
;; files and loaded by the runner makes ert refuse to redefine its tests.
;;
;; `a3madkour-sections-fixture.json' is a TEST INPUT, not a copy of the
;; contract.  The contract lives in the site repo's `data/sections.json'.
;; The cross-repo tests in `a3madkour-sections-test.el' pin the fixture's
;; section NAMES to that file and check every structural fact the pipeline
;; depends on against the real file itself.
;;
;; Session default: in a batch test run (`noninteractive'), loading this
;; file points `a3madkour-sections-file' at the fixture, so the ~150
;; existing tests whose code paths now read the contract need no wrapper.
;; `a3madkour-sections-test--with-root' unbinds it, so tests written with
;; that macro exercise the production resolution through
;; `a3madkour-pub/site-data-dir'.  It is never set in an interactive Emacs:
;; running ert there must not silently repoint a real publish at a fixture.

;;; Code:

(require 'ert)
(require 'a3madkour-sections)
;; Defines `a3madkour-pub/site-data-dir', so the `let' in the macros below is
;; a DYNAMIC binding (a `let' over a variable Emacs does not yet know to be
;; special is lexical under `lexical-binding: t', and the reader never sees
;; it).
(require 'a3madkour-publish-history)
;; Loaded eagerly so `a3madkour-pub-yaml/site-root' exists before any test
;; mocks it: the reader requires it lazily, and a `cl-letf' over an
;; undefined symbol is clobbered when that lazy `require' loads the defun.
(require 'a3madkour-publish-yaml)

(defconst a3madkour-sections-test--fixture-path
  (expand-file-name "a3madkour-sections-fixture.json"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Absolute path of the committed fixture contract.")

(defconst a3madkour-sections-test--json
  (with-temp-buffer
    (insert-file-contents a3madkour-sections-test--fixture-path)
    (buffer-string))
  "Text of the fixture contract.")

(when noninteractive
  (setq a3madkour-sections-file a3madkour-sections-test--fixture-path))

(defun a3madkour-sections-test/write (site-root &optional json)
  "Write JSON (default: the fixture) to SITE-ROOT's data/sections.json."
  (make-directory (expand-file-name "data" site-root) t)
  (with-temp-file (expand-file-name "data/sections.json" site-root)
    (insert (or json a3madkour-sections-test--json))))

(defun a3madkour-sections-test/mutate (old new &optional json)
  "Return JSON (default: the fixture) with every OLD replaced by NEW.
Signals when OLD does not occur, so a mutation test cannot pass
vacuously against a fixture whose spelling has drifted."
  (let ((json (or json a3madkour-sections-test--json)))
    (unless (string-search old json)
      (error "a3madkour-sections-test/mutate: %S not in fixture" old))
    (string-replace old new json)))

(defmacro a3madkour-sections-test--with-root (json &rest body)
  "Run BODY over a temp site root whose data/sections.json holds JSON.
When JSON is nil no contract file is written.  The root is supplied the
way production supplies it, through `a3madkour-pub/site-data-dir', with
the session-default `a3madkour-sections-file' unbound."
  (declare (indent 1))
  `(let* ((a3madkour-sections--cache nil)
          (a3madkour-sections-file nil)
          (root (file-name-as-directory (make-temp-file "a3-sections" t))))
     (unwind-protect
         (progn
           (when ,json (a3madkour-sections-test/write root ,json))
           (let ((a3madkour-pub/site-data-dir
                  (file-name-as-directory (expand-file-name "data" root))))
             ,@body))
       (delete-directory root t))))

(defun a3madkour-sections-test--real-site-root ()
  "The real site checkout: $A3_PUB_SITE_ROOT, else the author's path."
  (file-name-as-directory
   (expand-file-name (or (getenv "A3_PUB_SITE_ROOT")
                         "~/Sync/Workspace/a3madkour.github.io"))))

(defmacro a3madkour-sections-test--with-real-site (&rest body)
  "Run BODY against the REAL site repo's data/sections.json.
Skips only when the site checkout itself is absent; a checkout without
data/sections.json is a failure (the plan's prerequisite)."
  (declare (indent 0))
  `(let ((real-root (a3madkour-sections-test--real-site-root)))
     (unless (file-directory-p real-root)
       (ert-skip (format "site repo not found at %s" real-root)))
     (let ((a3madkour-sections--cache nil)
           (a3madkour-sections-file nil)
           (a3madkour-pub/site-data-dir
            (file-name-as-directory (expand-file-name "data" real-root))))
       ,@body)))

(provide 'a3madkour-sections-fixture)

;;; a3madkour-sections-fixture.el ends here
