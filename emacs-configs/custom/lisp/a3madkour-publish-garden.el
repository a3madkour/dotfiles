;;; a3madkour-publish-garden.el --- garden per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; B.1: garden per-file publish handler.  Wires together ox-hugo export,
;; frontmatter normalization, A.1's link rewriter + asset copier, and
;; A.1's record-publish into one entry point: `publish-garden-file'.
;;
;; Registered into `a3madkour-pub-living--handlers' (see Task 11) as
;;   (garden . a3madkour-pub-garden/publish-garden-file)
;; per spec §10.

;;; Code:

(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)

(defcustom a3madkour-pub-garden/section-dir-name "garden"
  "Hugo content section directory name for garden notes (relative to site root)."
  :type 'string
  :group 'a3madkour-pub)

(defun a3madkour-pub-garden--site-root ()
  "Derive the Hugo site root from `a3madkour-pub/site-data-dir'.
Convention: site-data-dir is `<root>/data/'; site root is its parent."
  (file-name-as-directory
   (directory-file-name
    (file-name-directory
     (directory-file-name
      (file-name-as-directory a3madkour-pub/site-data-dir))))))

(defun a3madkour-pub-garden--write-if-different (path content)
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

(defconst a3madkour-pub-garden--date-re
  "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
  "Regex for bare YYYY-MM-DD date strings.
These must be emitted unquoted in YAML so the PyYAML / YAML 1.1 loader
parses them as `datetime.date' objects (which is what check_garden_fixtures.py
and the Hugo template both expect).  A quoted string like \"2026-05-25\"
stays a string and fails `isinstance(val, datetime.date)' in the linter.")

(defun a3madkour-pub-garden--render-yaml-value (v)
  "Render V as a YAML scalar/list value.  Internal helper.
Strings → \"...\"; YYYY-MM-DD date strings → unquoted (YAML native date);
numbers → as-is; t → true; nil → false; lists of strings → [\"a\", \"b\"].

NOTE: nil is also a list in Emacs Lisp, so the nil/false case must be
tested before the listp case."
  (cond
   ((null v)    "false")
   ((eq v t)    "true")
   ((and (stringp v)
         (string-match-p a3madkour-pub-garden--date-re v))
    v)                                    ; unquoted YYYY-MM-DD → YAML date
   ((stringp v) (format "\"%s\"" v))
   ((numberp v) (format "%s" v))
   ((listp v)
    (format "[%s]"
            (mapconcat (lambda (s) (format "\"%s\"" s)) v ", ")))))

(defun a3madkour-pub-garden--render-frontmatter (alist)
  "Render ALIST as YAML frontmatter (alphabetical key order; deterministic).
Returns a string with leading/trailing `---' delimiters."
  (let ((sorted (sort (copy-sequence alist)
                      (lambda (a b)
                        (string< (symbol-name (car a)) (symbol-name (car b)))))))
    (concat "---\n"
            (mapconcat
             (lambda (cell)
               (format "%s: %s"
                       (symbol-name (car cell))
                       (a3madkour-pub-garden--render-yaml-value (cdr cell))))
             sorted "\n")
            "\n---\n")))

(defun a3madkour-pub-garden/publish-garden-file (file)
  "Publish a single garden-section FILE to content/garden/<slug>/index.md.

Pipeline per spec §10:
  export → frontmatter/normalize → [rewrite-links: B.1 follow-on] →
  asset-validate-and-copy → write-if-different → record-publish.

NOTE — link rewriting is intentionally deferred (B.1 follow-on): A.1's
`a3madkour-pub/rewrite-link' operates on raw [[id:UUID]] org bracket syntax,
but ox-hugo translates those to its own markdown link form during export, so
the post-export :body has no [[...]] patterns left to find.  Resolving this
cleanly needs either pre-export buffer rewriting or org-link-set-parameters
hooks — an architectural decision gated on Task 17's spot-check feedback.
The body is passed through unchanged from ox-hugo's output for now."
  (let* ((id        (plist-get (a3madkour-pub/note-metadata file) :id))
         (slug      (a3madkour-pub/note-slug file))
         (new-url   (a3madkour-pub/note-url file))
         (site-root (a3madkour-pub-garden--site-root))
         (bundle-dir (expand-file-name
                      (format "content/%s/%s/"
                              a3madkour-pub-garden/section-dir-name slug)
                      site-root))
         (out-path   (expand-file-name "index.md" bundle-dir))
         (exported   (a3madkour-pub-export/export-file file))
         (normalized (a3madkour-pub-frontmatter/normalize
                      'garden (plist-get exported :frontmatter) file))
         ;; B.1 follow-on: link rewriting deferred — see docstring above.
         (body       (plist-get exported :body)))
    (a3madkour-pub/asset-validate-and-copy file bundle-dir)
    (a3madkour-pub-garden--write-if-different
     out-path
     (concat (a3madkour-pub-garden--render-frontmatter normalized) body))
    (a3madkour-pub-history/record-publish id new-url 'live)))

(provide 'a3madkour-publish-garden)

;;; a3madkour-publish-garden.el ends here
