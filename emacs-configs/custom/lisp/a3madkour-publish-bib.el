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

(defvar a3madkour-pub-bib--string-table nil
  "Hash table mapping @string shortcut symbol to its expansion (string).
Reset by `parser-init'; populated during buffer parse.")

;; ---------------------------------------------------------------------
;; Parser: entry recognition + simple field reading
;; ---------------------------------------------------------------------

(defun a3madkour-pub-bib--parser-init ()
  "Allocate a fresh empty parser cache + @string table."
  (setq a3madkour-pub-bib--parser-cache (make-hash-table :test 'equal :size 256))
  (setq a3madkour-pub-bib--string-table (make-hash-table :test 'eq :size 32)))

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
read one value form: `{...}', `\"...\"', a bare numeric token, or a
bare identifier matched against the @string table."
  (skip-chars-forward " \t\n\r")
  (cond
   ((eq (char-after) ?{)  (forward-char 1) (a3madkour-pub-bib--read-balanced-braces))
   ((eq (char-after) ?\") (forward-char 1) (a3madkour-pub-bib--read-quoted-value))
   ((looking-at "\\([0-9]+\\)")
    (goto-char (match-end 0))
    (match-string-no-properties 1))
   ((looking-at "\\([A-Za-z][A-Za-z0-9_-]*\\)")
    (let ((token (intern (downcase (match-string-no-properties 1)))))
      (goto-char (match-end 0))
      (or (and a3madkour-pub-bib--string-table
               (gethash token a3madkour-pub-bib--string-table))
          (symbol-name token))))
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
       ((looking-at "@string[ \t]*{[ \t]*\\([A-Za-z][A-Za-z0-9_-]*\\)[ \t]*=[ \t]*")
        (let ((shortcut (intern (downcase (match-string-no-properties 1)))))
          (goto-char (match-end 0))
          (let ((expansion (a3madkour-pub-bib--parse-field-value)))
            (puthash shortcut expansion a3madkour-pub-bib--string-table)
            ;; Skip the trailing `}'.
            (skip-chars-forward " \t\n\r")
            (when (eq (char-after) ?})
              (forward-char 1)))))
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

(defun a3madkour-pub-bib--split-authors (s)
  "Split S on ` and ' (BibTeX author-list convention).  Returns a list
of trimmed author strings; empty input → nil."
  (when (and (stringp s) (not (string-empty-p (string-trim s))))
    (mapcar #'string-trim
            (split-string s " and " t "[ \t\n\r]+"))))

(defun a3madkour-pub-bib--year-from-date (s)
  "Extract a 4-digit year int from S (an ISO date string, year-only, or
junk).  Returns int or nil."
  (when (and (stringp s)
             (string-match "\\`\\([0-9]\\{4\\}\\)" s))
    (string-to-number (match-string 1 s))))

;; ---------------------------------------------------------------------
;; normalize-entry: raw alist → schema plist (Task 6)
;; ---------------------------------------------------------------------

(defconst a3madkour-pub-bib--type-enum
  '("article" "book" "inproceedings" "incollection" "online" "misc"
    "report" "thesis" "unpublished")
  "Known yaml :type enum.  Unknown @entrytypes collapse to \"misc\".")

(defun a3madkour-pub-bib--normalize-venue (raw)
  "Pick venue from RAW alist by priority chain."
  (or (alist-get 'journaltitle raw)
      (alist-get 'booktitle raw)
      (alist-get 'publisher raw)
      (alist-get 'eventtitle raw)))

(defun a3madkour-pub-bib--normalize-url (raw)
  "Return RAW's url field iff it starts with http(s)://; else nil."
  (let ((u (alist-get 'url raw)))
    (and (stringp u)
         (or (string-prefix-p "http://" u) (string-prefix-p "https://" u))
         u)))

(defun a3madkour-pub-bib--normalize-type (raw)
  "Return RAW's :bibtype iff in the known enum; else \"misc\"."
  (let ((t1 (alist-get :bibtype raw)))
    (if (and t1 (member t1 a3madkour-pub-bib--type-enum))
        t1
      "misc")))

(defun a3madkour-pub-bib--normalize-entry (raw)
  "Map a parser-cache RAW alist to the schema plist.  Returns nil for nil."
  (when raw
    (let* ((authors-raw (alist-get 'author raw))
           (authors (or (a3madkour-pub-bib--split-authors authors-raw)
                        '("Unknown")))
           (year (or (a3madkour-pub-bib--year-from-date (alist-get 'date raw))
                     (a3madkour-pub-bib--year-from-date (alist-get 'year raw))))
           (title-raw (alist-get 'title raw))
           ;; The parser already stripped the outer brace-pair that delimited
           ;; the field value ({...}).  A second call to strip-outer-braces
           ;; would remove the inner case-protection braces (e.g. the inner
           ;; `{Egyptian Streets}' inside `{{Egyptian Streets}}').  We keep
           ;; the raw title string verbatim so callers can decide whether to
           ;; strip case-protection braces when serialising to YAML.
           (title title-raw)
           (venue (a3madkour-pub-bib--normalize-venue raw)))
      (list :authors   authors
            :year      year
            :title     title
            :venue     venue
            :url       (a3madkour-pub-bib--normalize-url raw)
            :doi       (alist-get 'doi raw)
            :publisher (alist-get 'publisher raw)
            :volume    (alist-get 'volume raw)
            :issue     (or (alist-get 'issue raw) (alist-get 'number raw))
            :pages     (alist-get 'pages raw)
            :isbn      (alist-get 'isbn raw)
            :type      (a3madkour-pub-bib--normalize-type raw)))))

(provide 'a3madkour-publish-bib)

;;; a3madkour-publish-bib.el ends here
