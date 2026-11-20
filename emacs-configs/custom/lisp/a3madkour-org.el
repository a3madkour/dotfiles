;;; a3madkour-org.el --- Shared org-reading helpers -*- lexical-binding: t; -*-

;;; Commentary:

;; One home for the small org-reading helpers the publisher and the kitchen
;; modules both need.  This is a leaf module: it requires only `org',
;; `org-element', `subr-x' and `cl-lib', and must never require another
;; `a3madkour-*' module.

;;; Code:

(require 'org)
(require 'org-element)
(require 'subr-x)
(require 'cl-lib)

(defun a3madkour-org--keyword-regexp (key)
  "Regexp matching a `#+KEY: value' line, value in group 1."
  (format "^#\\+%s:\\(.*\\)$" (regexp-quote key)))

(defun a3madkour-org-keyword (key)
  "Return the value of the first `#+KEY:' line in the current buffer.
The whole buffer is searched (narrowing ignored) and KEY matches
case-insensitively.  The value is trimmed; a keyword present with no value
gives \"\".  Return nil when absent."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward (a3madkour-org--keyword-regexp key) nil t)
          (string-trim (match-string 1)))))))

(defun a3madkour-org-keyword-in-string (text key)
  "Like `a3madkour-org-keyword', but reading the string TEXT."
  (let ((case-fold-search t))
    (when (string-match (a3madkour-org--keyword-regexp key) text)
      (string-trim (match-string 1 text)))))

(defun a3madkour-org-ast-keyword (ast name)
  "Return the value of the first keyword element in AST whose key is NAME.
The element's key is upcased before comparing.  Return nil when absent."
  (org-element-map ast 'keyword
    (lambda (kw)
      (when (string-equal (upcase (org-element-property :key kw)) name)
        (org-element-property :value kw)))
    nil t))

(provide 'a3madkour-org)

;;; a3madkour-org.el ends here
