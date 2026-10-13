;;; test-lsp-plists.el --- lsp-mode plist guard tests  -*- lexical-binding: t; -*-

;; `a3madkour/lsp-plists-consistent-p' is loaded from config.org by
;; test-helpers.el.  lsp-mode is not available in batch, so the compiled
;; accessor is stubbed with a plist-reading or a hash-reading version.

(require 'ert)
(require 'cl-lib)

(defvar lsp-use-plists)

(defun a3madkour-test/plist-accessor (x)
  (plist-get x :capabilities))

(defun a3madkour-test/hash-accessor (x)
  (gethash "capabilities" x))

(defmacro a3madkour-test/with-lsp-build (plists accessor &rest body)
  "Run BODY with `lsp-use-plists' bound to PLISTS and the accessor stubbed."
  (declare (indent 2))
  `(let ((lsp-use-plists ,plists))
     (cl-letf (((symbol-function 'lsp:initialize-result-capabilities)
                ,accessor))
       ,@body)))

(ert-deftest lsp-plists-consistent-plist-build-plist-env ()
  (a3madkour-test/with-lsp-build "true" #'a3madkour-test/plist-accessor
    (should (a3madkour/lsp-plists-consistent-p))))

(ert-deftest lsp-plists-inconsistent-hash-build-plist-env ()
  "The bug: hash-table byte-code with LSP_USE_PLISTS set."
  (a3madkour-test/with-lsp-build "true" #'a3madkour-test/hash-accessor
    (should-not (a3madkour/lsp-plists-consistent-p))))

(ert-deftest lsp-plists-inconsistent-nil-returning-build-plist-env ()
  "The live stale build returned nil on a plist instead of signalling."
  (a3madkour-test/with-lsp-build "true" #'ignore
    (should-not (a3madkour/lsp-plists-consistent-p))))

(ert-deftest lsp-plists-consistent-hash-build-hash-env ()
  (a3madkour-test/with-lsp-build nil #'a3madkour-test/hash-accessor
    (should (a3madkour/lsp-plists-consistent-p))))

(ert-deftest lsp-plists-inconsistent-plist-build-hash-env ()
  (a3madkour-test/with-lsp-build nil #'a3madkour-test/plist-accessor
    (should-not (a3madkour/lsp-plists-consistent-p))))

;;; test-lsp-plists.el ends here
