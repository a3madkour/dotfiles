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

(defun a3madkour-pub-garden--rewrite-to-tmp-file (source-file source-note-id)
  "Copy SOURCE-FILE to a fresh temp `.org' file with all org links
pre-rewritten via `a3madkour-pub-rewrite/rewrite-buffer-links'.

Returns the absolute path of the temp file.  Caller is responsible for
`delete-file' on the returned path (typical pattern: wrap the consumer
in an `unwind-protect' that deletes on cleanup).

Warnings from the rewriter are surfaced via `message' with the SOURCE-FILE
included so authors can grep the publish log.  (Future slices may route
these through a structured warning channel; for now they ride the same
stderr stream as the rest of the publish pipeline's messages.)"
  (let ((tmp (make-temp-file "a3-pub-pre-export-" nil ".org"))
        warnings)
    (with-temp-buffer
      (insert-file-contents source-file)
      (setq warnings
            (a3madkour-pub-rewrite/rewrite-buffer-links source-note-id))
      (write-region (point-min) (point-max) tmp nil 'quiet))
    (dolist (w warnings)
      (message "[a3-pub-garden] rewrite WARN (%s): %s" source-file w))
    tmp))

(defun a3madkour-pub-garden/publish-garden-file (file)
  "Publish a single garden-section FILE to content/garden/<slug>/index.md.

Pipeline per spec §10:
  pre-export-rewrite-links → export → frontmatter/normalize →
  asset-validate-and-copy → write-if-different → record-publish.

The pre-export rewrite step copies FILE to a temp .org file and calls
`a3madkour-pub-rewrite/rewrite-buffer-links' on it (B.1.1) so that org
bracket-link forms `[[id:UUID]]', `[[file:...]]', and `[[<type>:UUID]]'
are resolved to inline HTML anchors (or inert plain text for unpublished
targets) before ox-hugo sees them.  Without this step ox-hugo emits
`{{< relref \"<underscore_filename>.md\" >}}' shortcodes that fail
Hugo's REF_NOT_FOUND check against B's hyphen-slug bundle paths."
  (let* ((id        (plist-get (a3madkour-pub/note-metadata file) :id))
         (slug      (a3madkour-pub/note-slug file))
         (new-url   (a3madkour-pub/note-url file))
         (site-root (a3madkour-pub-garden--site-root))
         (bundle-dir (expand-file-name
                      (format "content/%s/%s/"
                              a3madkour-pub-garden/section-dir-name slug)
                      site-root))
         (out-path   (expand-file-name "index.md" bundle-dir))
         (tmp-src    (a3madkour-pub-garden--rewrite-to-tmp-file file id))
         (exported   (unwind-protect
                         (a3madkour-pub-export/export-file tmp-src)
                       (when (file-exists-p tmp-src)
                         (delete-file tmp-src))))
         (normalized (a3madkour-pub-frontmatter/normalize
                      'garden (plist-get exported :frontmatter) file))
         (body       (plist-get exported :body)))
    (a3madkour-pub/asset-validate-and-copy file bundle-dir)
    (a3madkour-pub-garden--write-if-different
     out-path
     (concat (a3madkour-pub-garden--render-frontmatter normalized) body))
    (a3madkour-pub-history/record-publish id new-url 'live)))

(provide 'a3madkour-publish-garden)

;;; a3madkour-publish-garden.el ends here
