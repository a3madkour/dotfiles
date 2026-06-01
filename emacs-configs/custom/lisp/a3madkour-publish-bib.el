;;; a3madkour-publish-bib.el --- bib resolver for F citation pipeline -*- lexical-binding: t; -*-

;;; Commentary:

;; F sub-project resolver module.  Reads BibTeX entries via three
;; engines hidden behind one interface:
;;
;;   (a3madkour-pub-bib/resolve KEY)  → entry plist or nil
;;     ├─ citar path     (preferred when citar is loaded; M-x context)
;;     ├─ parser path    (stdlib .bib parser; batch / shell context)
;;     └─ BBT JSON-RPC   (NEVER called from resolve; only from
;;                        `bib-refresh-from-zotero', invoked by
;;                        `a3-sync-citations')
;;
;; Plist shape returned by resolve:
;;   (:authors ("Last, F" ...) :year INT :title STR :venue STR
;;    :url STR-or-nil :doi STR-or-nil :publisher STR-or-nil
;;    :volume STR-or-nil :issue STR-or-nil :pages STR-or-nil
;;    :isbn STR-or-nil :type STR-or-nil)
;;
;; The parser produces a raw per-entry alist; `normalize-entry' is the
;; lossy projection from raw → schema plist.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defcustom a3madkour-pub-bib/library-path
  (expand-file-name "~/org/notes/ref-notes/library.bib")
  "Path to the BibTeX library used by F.  Default is the author's
Zotero/BBT-exported file."
  :type 'file
  :group 'a3madkour-pub)

(defcustom a3madkour-pub-bib/bbt-endpoint
  "http://localhost:23119/better-bibtex/json-rpc"
  "Better-BibTeX JSON-RPC endpoint.  Set to nil to disable
`bib-refresh-from-zotero' entirely."
  :type '(choice (const :tag "Disabled" nil) string)
  :group 'a3madkour-pub)

(defvar a3madkour-pub-bib--parser-cache nil
  "Hash table mapping cite-key (string) to raw-field-alist for the
current publish run.  Reset by `a3madkour-pub-bib--parser-init'.")

;; ---------------------------------------------------------------------
;; Parser: entry recognition + simple field reading
;; ---------------------------------------------------------------------

(defun a3madkour-pub-bib--parser-init ()
  "Allocate a fresh empty parser cache hash."
  (setq a3madkour-pub-bib--parser-cache
        (make-hash-table :test 'equal :size 256)))

(defun a3madkour-pub-bib--strip-outer-braces (s)
  "Strip exactly one pair of OUTERMOST braces from S if present.
Inner braces survive verbatim."
  (let ((trimmed (string-trim s)))
    (if (and (string-prefix-p "{" trimmed)
             (string-suffix-p "}" trimmed)
             (>= (length trimmed) 2))
        (substring trimmed 1 -1)
      trimmed)))

(defun a3madkour-pub-bib--read-balanced-braces ()
  "Reader: at point just AFTER an opening `{', read forward until the
matching `}', honoring nested braces.  Returns the inside-braces string
WITHOUT the closing brace.  Point is left just AFTER the matching brace."
  (let ((start (point))
        (depth 1))
    (while (and (> depth 0) (not (eobp)))
      (let ((next (re-search-forward "[{}]" nil t)))
        (cond
         ((not next) (error "a3-pub-bib: unbalanced braces (parse start %d)" start))
         ((eq (char-before) ?{) (setq depth (1+ depth)))
         ((eq (char-before) ?}) (setq depth (1- depth))))))
    (when (> depth 0)
      (error "a3-pub-bib: unbalanced braces (parse start %d)" start))
    ;; (point) is just AFTER the closing brace; the inside spans (start..(point)-1).
    (buffer-substring-no-properties start (1- (point)))))

(defun a3madkour-pub-bib--read-quoted-value ()
  "Reader: at point just AFTER an opening `\"', read forward until the
closing `\"' (no escapes — BibTeX doesn't have them inside double-quotes
for our V1 corpus).  Returns the inside string; point is just AFTER the
closing quote."
  (let ((start (point)))
    (unless (re-search-forward "\"" nil t)
      (error "a3-pub-bib: unterminated quoted value at pos %d" start))
    (buffer-substring-no-properties start (1- (point)))))

(defun a3madkour-pub-bib--parse-field-value ()
  "Reader: at point at the first non-whitespace char of a field value,
read one value form: `{...}', `\"...\"', or a bare numeric token like
`2018'.  Returns the value string."
  (skip-chars-forward " \t\n\r")
  (cond
   ((eq (char-after) ?{)  (forward-char 1) (a3madkour-pub-bib--read-balanced-braces))
   ((eq (char-after) ?\") (forward-char 1) (a3madkour-pub-bib--read-quoted-value))
   ((looking-at "\\([0-9]+\\)")
    (goto-char (match-end 0))
    (match-string-no-properties 1))
   (t (error "a3-pub-bib: unexpected field-value start at pos %d" (point)))))

(defun a3madkour-pub-bib--parse-one-entry ()
  "Reader: at point at the `@' of an entry, parse one `@type{key, ...}'.
Returns (KEY . ALIST-OF-FIELDS).  KEY is the entry key (string).  ALIST
keys are interned symbols of lowercased field names.  Special pseudo-key
:bibtype carries the entry type string (without `@')."
  (unless (looking-at "@\\([A-Za-z]+\\)[ \t]*{[ \t]*\\([^ \t,\n]+\\)[ \t]*,")
    (error "a3-pub-bib: not at entry start at pos %d" (point)))
  (let ((entry-key  (match-string-no-properties 2))
        (fields     `((:bibtype . ,(downcase (match-string-no-properties 1))))))
    (goto-char (match-end 0))
    (cl-block field-loop
      (while t
        (skip-chars-forward " \t\n\r,")
        (cond
         ((eq (char-after) ?}) (forward-char 1) (cl-return-from field-loop))
         ((eobp) (error "a3-pub-bib: unexpected EOF inside entry %s" entry-key))
         ((looking-at "\\([A-Za-z][A-Za-z0-9_-]*\\)[ \t]*=[ \t]*")
          (let ((name (intern (downcase (match-string-no-properties 1)))))
            (goto-char (match-end 0))
            (let ((value (a3madkour-pub-bib--parse-field-value)))
              (push (cons name value) fields))))
         (t (error "a3-pub-bib: malformed field in entry %s at pos %d"
                   entry-key (point))))))
    (cons entry-key (nreverse fields))))

(defun a3madkour-pub-bib--parse-buffer ()
  "Parse the current buffer (assumed to hold .bib text), populating
`a3madkour-pub-bib--parser-cache'.  Skips bare-line BibTeX comments,
recognizes (but does not yet substitute) @string and skips @preamble.
Returns the number of entries cached."
  (a3madkour-pub-bib--parser-init)
  (goto-char (point-min))
  (let ((count 0))
    (while (re-search-forward "^@" nil t)
      (backward-char 1)
      (cond
       ((looking-at "@string[ \t]*{")
        (goto-char (match-end 0))
        (a3madkour-pub-bib--read-balanced-braces))     ;; skip for Task 3
       ((looking-at "@preamble[ \t]*{")
        (goto-char (match-end 0))
        (a3madkour-pub-bib--read-balanced-braces))
       (t
        (let ((pair (a3madkour-pub-bib--parse-one-entry)))
          (puthash (car pair) (cdr pair) a3madkour-pub-bib--parser-cache)
          (setq count (1+ count))))))
    count))

(defun a3madkour-pub-bib/parse-file (path)
  "Parse the .bib file at PATH into the parser cache.  Returns the
number of entries cached.  Signals if PATH does not exist."
  (unless (file-exists-p path)
    (error "a3-pub-bib: library.bib not found at %s" path))
  (with-temp-buffer
    (insert-file-contents path)
    (a3madkour-pub-bib--parse-buffer)))

(provide 'a3madkour-publish-bib)

;;; a3madkour-publish-bib.el ends here
