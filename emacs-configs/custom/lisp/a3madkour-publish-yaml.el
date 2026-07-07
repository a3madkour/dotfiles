;;; a3madkour-publish-yaml.el --- Shared YAML frontmatter rendering (P3.1) -*- lexical-binding: t; -*-

;;; Commentary:
;; P3.1 (publish-pipeline audit roadmap): the per-section content handlers
;; (garden / essays / poetry / research) each carried a byte-identical copy of
;; the same frontmatter-emission stack — `--site-root', `--write-if-different',
;; the YYYY-MM-DD `--date-re', `--render-yaml-value', and `--render-frontmatter'
;; — which had begun to drift (the `tags: []' special-case existed in
;; essays/poetry but not garden/research; the strict-string-list guard only in
;; research).  This module is the single source of truth; each handler's
;; per-section helpers are now thin wrappers that supply the divergent bits as
;; parameters (a `key-hook' for section-specific keys, a `value-fn' for the
;; strict variant).  Behavior is preserved exactly — the drift is now explicit
;; parameters rather than copy-paste.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)                 ; a3madkour-pub/yaml-escape-scalar

(defconst a3madkour-pub-yaml--date-re
  "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
  "Regex for bare YYYY-MM-DD date strings.
These must be emitted UNQUOTED in YAML so the PyYAML / YAML 1.1 loader parses
them as `datetime.date' objects (which the fixture linters + Hugo templates
expect).  A quoted \"2026-05-25\" stays a string and fails the linter's
`isinstance(val, datetime.date)' check.")

(defun a3madkour-pub-yaml/site-root ()
  "Derive the Hugo site root from `a3madkour-pub/site-data-dir'.
Convention: site-data-dir is `<root>/data/'; site root is its parent."
  (file-name-as-directory
   (directory-file-name
    (file-name-directory
     (directory-file-name
      (file-name-as-directory a3madkour-pub/site-data-dir))))))

(defun a3madkour-pub-yaml/write-if-different (path content)
  "Write CONTENT to PATH only if it differs from existing on-disk content.
Returns t if a write happened, nil if no-op."
  (let ((existing (when (file-exists-p path)
                    (with-temp-buffer
                      (insert-file-contents path)
                      (buffer-string)))))
    (unless (string= existing content)
      (make-directory (file-name-directory path) t)
      (with-temp-file path (insert content))
      t)))

(defun a3madkour-pub-yaml/render-value (v &optional strict-string-list)
  "Render V as a YAML scalar/list value.
Strings → \"...\" (escaped); YYYY-MM-DD date strings → unquoted (YAML native
date); numbers → as-is; t → true; nil → false; lists of strings → [\"a\", \"b\"].

NOTE: nil is also a list in Emacs Lisp, so the nil/false case is tested BEFORE
the listp case.

When STRICT-STRING-LIST is non-nil, a list containing a non-string element
signals an error (research uses this to force structured lists — e.g. outputs —
through their dedicated renderer instead of the scalar-list path)."
  (cond
   ((null v)    "false")
   ((eq v t)    "true")
   ((and (stringp v)
         (string-match-p a3madkour-pub-yaml--date-re v))
    v)                                        ; unquoted YYYY-MM-DD → YAML date
   ((stringp v) (format "\"%s\"" (a3madkour-pub/yaml-escape-scalar v)))
   ((numberp v) (format "%s" v))
   ((listp v)
    (when strict-string-list
      (unless (cl-every #'stringp v)
        (error "a3madkour-pub-yaml/render-value: list contains a non-string \
element; caller must render structured lists via their own helper")))
    (format "[%s]"
            (mapconcat (lambda (s)
                         (format "\"%s\"" (a3madkour-pub/yaml-escape-scalar s)))
                       v ", ")))))

(defun a3madkour-pub-yaml/tags-empty-array-hook (k v)
  "A `render-frontmatter' KEY-HOOK: render an empty `tags' list as `[]'.
Boolean fields (draft / has_*) keep the standard nil → `false' path, so this
special-case is key-scoped to `tags'.  Used by the essays + poetry handlers."
  (when (and (eq k 'tags) (null v)) "tags: []"))

(cl-defun a3madkour-pub-yaml/render-frontmatter
    (alist &key key-hook (value-fn #'a3madkour-pub-yaml/render-value))
  "Render ALIST as YAML frontmatter (alphabetical key order; deterministic).
Returns a string with leading/trailing `---' delimiters.

KEY-HOOK, when supplied, is called as (KEY VALUE) for each cell and may return:
  - a string      → used verbatim as that entry's full line (e.g. `tags: []',
                    or a multi-line block sequence for `outputs');
  - the symbol `:omit' → the key is dropped from the output entirely;
  - nil           → fall through to the default `KEY: (VALUE-FN VALUE)' line.

VALUE-FN renders a bare value (defaults to `a3madkour-pub-yaml/render-value');
pass a closure that sets the strict flag for the research variant."
  (let* ((sorted (sort (copy-sequence alist)
                       (lambda (a b)
                         (string< (symbol-name (car a)) (symbol-name (car b))))))
         (lines (mapcar
                 (lambda (cell)
                   (let* ((k (car cell))
                          (v (cdr cell))
                          (hooked (and key-hook (funcall key-hook k v))))
                     (cond
                      ((eq hooked :omit) nil)
                      ((stringp hooked) hooked)
                      (t (format "%s: %s" (symbol-name k) (funcall value-fn v))))))
                 sorted)))
    (concat "---\n"
            (mapconcat #'identity (delq nil lines) "\n")
            "\n---\n")))

(provide 'a3madkour-publish-yaml)
;;; a3madkour-publish-yaml.el ends here
