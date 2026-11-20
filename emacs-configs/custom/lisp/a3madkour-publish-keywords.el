;;; a3madkour-publish-keywords.el --- Keyword extraction helpers -*- lexical-binding: t; -*-

;;; Commentary:

;; Extract `#+KEYWORD: value' lines from an org buffer / file.  Used by the
;; main `a3madkour-publish' library.  Pure functions — no side effects.

;;; Code:

(require 'a3madkour-org)

(defalias 'a3madkour-pub-keywords/extract #'a3madkour-org-keyword
  "Return the value of org keyword KEY in the current buffer, or nil if absent.
Alias of `a3madkour-org-keyword', kept until the rename pass.")

(defun a3madkour-pub-keywords/boolean-p (v)
  "Return non-nil iff V is the string \"t\" (case-insensitive).
Used for `#+HUGO_PUBLISH:' and `#+HUGO_DRAFT:' parsing.  The contract is
deliberately strict — \"true\"/\"yes\"/\"1\" do NOT count, only \"t\"."
  (and (stringp v)
       (string-match-p "\\`[Tt]\\'" v)
       t))

(defun a3madkour-pub-keywords/parse-aliases (v)
  "Parse HUGO_ALIASES value V (a string or nil) into a list of URL strings.
Accepts whitespace and commas as separators.  Drops empty tokens.  Returns
nil for nil / empty / whitespace-only input."
  (when (and (stringp v) (not (string-blank-p v)))
    (split-string v "[ \t\n,]+" t "[ \t\n]+")))

(provide 'a3madkour-publish-keywords)

;;; a3madkour-publish-keywords.el ends here
