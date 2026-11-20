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

(defun a3madkour-org-ast-table-under (headline)
  "Return the first table element in HEADLINE's own section, or nil.
Org wraps a headline's body in a section element; look one level into that
section rather than at HEADLINE's direct children."
  (let ((section (cl-loop for child in (org-element-contents headline)
                          when (eq (org-element-type child) 'section)
                          return child)))
    (when section
      (cl-loop for child in (org-element-contents section)
               when (eq (org-element-type child) 'table)
               return child))))

(defun a3madkour-org-ast-table-rows (table)
  "Return TABLE's rows as a list of lists of trimmed cell strings.
Horizontal-rule rows are skipped.  An empty cell is \"\".  A cell whose
content is not a plain string is its interpreted org text, trimmed, without
text properties."
  (cl-loop for row in (org-element-map table 'table-row #'identity)
           when (eq (org-element-property :type row) 'standard)
           collect (mapcar (lambda (cell)
                             (let ((c (car (org-element-contents cell))))
                               (cond
                                ((stringp c) (string-trim c))
                                ((null c) "")
                                (t (string-trim
                                    (substring-no-properties
                                     (org-element-interpret-data c)))))))
                           (org-element-contents row))))

(provide 'a3madkour-org)

;;; a3madkour-org.el ends here
