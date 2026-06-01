;;; a3madkour-publish-citations.el --- F citation pipeline -*- lexical-binding: t; -*-

;;; Commentary:

;; F sub-project orchestrator.  Owns:
;;   - pre-export buffer rewriter: [cite:@key] → @@hugo:{{< cite "key" >}}@@
;;   - per-run cite-key accumulator
;;   - notes_ref auto-detection
;;   - data/citations.yaml emitter (merge-on-publish, purge-on-sync)
;;   - M-x a3-sync-citations command

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-element)
(require 'a3madkour-publish-bib)

;; Forward declaration only — the real defcustom lives in
;; `a3madkour-publish-history.el'.  We avoid `require'ing history here
;; because it transitively pulls in `yaml', which may not be on
;; load-path yet during early init (straight bootstrap order).
;; Callers MUST `setq' this before invoking emit-yaml / a3-sync-citations.
(defvar a3madkour-pub/site-data-dir)

(defvar a3madkour-pub-citations--accumulator nil
  "Hash table mapping cite-key (string) to list of (SOURCE-FILE . POS)
pairs, populated by the rewriter during the publish run.")

(defun a3madkour-pub-citations--accumulator-init ()
  "Allocate a fresh empty accumulator hash."
  (setq a3madkour-pub-citations--accumulator
        (make-hash-table :test 'equal :size 64)))

(defun a3madkour-pub-citations--in-noexport-p (cite tree)
  "Return non-nil iff CITE element is inside a heading marked :noexport:."
  (let ((node (org-element-property :parent cite)))
    (while (and node
                (not (and (eq (org-element-type node) 'headline)
                          (member "noexport"
                                  (org-element-property :tags node)))))
      (setq node (org-element-property :parent node)))
    node))

(defun a3madkour-pub-citations--scan-buffer ()
  "Walk the current org buffer via `org-element-parse-buffer'; return a
list of (KEY . POS) pairs for every citation element.  POS is the
buffer position of the element's `begin' marker.  Multi-cite forms
return one pair per key in source order.  Style-overrides (`/text',
`/noauthor', `/locators') and prefix/suffix text are NOT filtered here
— Task 9's rewriter checks those and signals."
  (let ((tree (org-element-parse-buffer))
        (acc nil))
    (org-element-map tree 'citation
      (lambda (cite)
        (unless (a3madkour-pub-citations--in-noexport-p cite tree)
          (let ((begin (org-element-property :begin cite)))
            (dolist (ref (org-element-map cite 'citation-reference #'identity))
              (let ((key (org-element-property :key ref)))
                (when (and key (not (string-empty-p key)))
                  (push (cons key begin) acc))))))))
    (nreverse acc)))

;; ---------------------------------------------------------------------
;; rewrite-cite-keys-in-buffer (Task 9)
;; ---------------------------------------------------------------------

(defun a3madkour-pub-citations--shortcode-for-keys (keys)
  "Build `@@hugo:{{< cite \"k1\" >}}{{< cite \"k2\" >}}@@' for KEYS."
  (concat "@@hugo:"
          (mapconcat (lambda (k) (format "{{< cite \"%s\" >}}" k)) keys "")
          "@@"))

(defun a3madkour-pub-citations--source-line-of (pos source-file)
  "Compute the 1-indexed line number of POS for error messages.
SOURCE-FILE is included in the returned `FILE:LINE' string."
  (format "%s:%d"
          source-file
          (save-excursion
            (goto-char pos)
            (line-number-at-pos))))

(defun a3madkour-pub-citations--non-empty-interpret (obj)
  "Return non-nil iff OBJ, interpreted via `org-element-interpret-data', is non-empty.
Guards against OBJ being a non-list (e.g. a propertized string in newer org)."
  (when obj
    (let ((text (condition-case nil
                    (org-element-interpret-data obj)
                  (error nil))))
      (and (stringp text) (not (string-empty-p (string-trim text)))))))

(defun a3madkour-pub-citations--check-supported-form (cite source-file)
  "Signal if CITE uses style override, prefix, or suffix.  Returns t on OK.
Checks both the citation-level and citation-reference-level prefix/suffix
properties, as their location varies between org-element versions."
  (let* ((style (org-element-property :style cite))
         (pos (org-element-property :begin cite))
         (loc (a3madkour-pub-citations--source-line-of pos source-file)))
    ;; Style override check.
    (when (and style (not (string-empty-p style)))
      (error "%s: cite/style not supported in V1: [cite/%s:...]\n  hint: V1 supports [cite:@key] and [cite:@k1;@k2]. Style overrides, prefix, and suffix are tracked as F-follow-up work; see docs/superpowers/specs/2026-06-01-phase-3-f-citation-pipeline-design.md §1 non-goals."
             loc style))
    ;; Prefix/suffix check on citation element.
    (when (or (a3madkour-pub-citations--non-empty-interpret
               (org-element-property :prefix cite))
              (a3madkour-pub-citations--non-empty-interpret
               (org-element-property :suffix cite)))
      (error "%s: cite prefix/suffix not supported in V1\n  hint: V1 supports [cite:@key] and [cite:@k1;@k2]. Style overrides, prefix, and suffix are tracked as F-follow-up work."
             loc))
    ;; Prefix/suffix check on each citation-reference child (newer org-element
    ;; stores per-reference prefix/suffix on the reference node, not the parent).
    (org-element-map cite 'citation-reference
      (lambda (ref)
        (when (or (a3madkour-pub-citations--non-empty-interpret
                   (org-element-property :prefix ref))
                  (a3madkour-pub-citations--non-empty-interpret
                   (org-element-property :suffix ref)))
          (error "%s: cite prefix/suffix not supported in V1\n  hint: V1 supports [cite:@key] and [cite:@k1;@k2]. Style overrides, prefix, and suffix are tracked as F-follow-up work."
                 loc))))
    t))

(defun a3madkour-pub-citations--strip-print-bibliography ()
  "Remove any `#+print_bibliography:' line from the current buffer."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^\\s-*#\\+print_bibliography:.*$" nil t)
      (replace-match "" nil t))))

(defun a3madkour-pub-citations/rewrite-cite-keys-in-buffer (source-file)
  "Walk current buffer for [cite:...] forms; rewrite each to
`@@hugo:{{< cite \"k\" >}}@@'; populate the run accumulator.
SOURCE-FILE is the original path, used for error messages and
accumulator provenance.  Fail-fast on the first error.

Validation runs in forward (source) order so error messages cite the
first problematic key as the author encounters it.  Rewriting runs in
reverse order so earlier rewrites don't corrupt the buffer positions
recorded by org-element-parse-buffer."
  (unless a3madkour-pub-citations--accumulator
    (a3madkour-pub-citations--accumulator-init))
  (a3madkour-pub-citations--strip-print-bibliography)
  ;; Collect citation elements in forward order.
  (let* ((tree (org-element-parse-buffer))
         (cites
          (org-element-map tree 'citation
            (lambda (cite)
              (let ((begin (org-element-property :begin cite))
                    (end   (org-element-property :end   cite)))
                (list :cite cite :begin begin :end end))))))
    ;; Pass 1: validate in source order (fail-fast on first error).
    (dolist (info cites)
      (let* ((cite  (plist-get info :cite))
             (begin (plist-get info :begin))
             (_     (a3madkour-pub-citations--check-supported-form cite source-file))
             (keys
              (org-element-map cite 'citation-reference
                (lambda (ref) (org-element-property :key ref)))))
        (dolist (k keys)
          (unless (a3madkour-pub-bib/resolve k)
            (error "%s: cite key %s not found in library.bib"
                   (a3madkour-pub-citations--source-line-of begin source-file)
                   k)))))
    ;; Pass 2: accumulate + rewrite in reverse order (preserves positions).
    (dolist (info (nreverse cites))
      (let* ((cite   (plist-get info :cite))
             (begin  (plist-get info :begin))
             (end    (plist-get info :end))
             (keys
              (org-element-map cite 'citation-reference
                (lambda (ref) (org-element-property :key ref)))))
        ;; Accumulate.
        (dolist (k keys)
          (let ((current (gethash k a3madkour-pub-citations--accumulator)))
            (puthash k (cons (cons source-file begin) current)
                     a3madkour-pub-citations--accumulator)))
        ;; Replace [cite:...] span with the shortcode wrapper.  The
        ;; org-element `end' property includes trailing whitespace; trim
        ;; back to just past the closing `]'.
        (save-excursion
          (goto-char end)
          (skip-chars-backward " \t\n\r")
          (let ((replace-end (point)))
            (delete-region begin replace-end)
            (goto-char begin)
            (insert (a3madkour-pub-citations--shortcode-for-keys keys))))))))

;; ---------------------------------------------------------------------
;; cite--lookup-notes-ref: manifest-backed ref-note auto-detect (Task 10)
;; ---------------------------------------------------------------------

(defcustom a3madkour-pub-citations--ref-notes-dir
  (expand-file-name "~/org/notes/ref-notes/")
  "Directory holding per-cite-key reference org notes.  For a cite key
KEY, F probes for `<ref-notes-dir>/<KEY>.org' to auto-populate the
:notes_ref yaml field."
  :type 'directory
  :group 'a3madkour-pub)

(defun a3madkour-pub-citations--read-keyword (file keyword)
  "Read first `#+<KEYWORD>: <VALUE>' line from FILE; return VALUE or nil."
  (with-temp-buffer
    (insert-file-contents file nil 0 4096)  ; first 4KB is enough for keywords
    (goto-char (point-min))
    (when (re-search-forward
           (format "^#\\+%s:[ \t]*\\(.*\\)$" (upcase keyword)) nil t)
      (string-trim (match-string 1)))))

(defun a3madkour-pub-citations--manifest-slug-for-garden-url (manifest url)
  "Search MANIFEST (the snapshot alist) for an entry whose current_url
equals URL; return its slug (the path component between /garden/ and /),
or nil if not found."
  (let ((notes (alist-get 'notes manifest)))
    (cl-some
     (lambda (note-alist)
       (let ((cur-url (alist-get 'current_url note-alist))
             (state   (alist-get 'state       note-alist)))
         (and (equal cur-url url)
              (equal state "live")
              (when (string-match "\\`/garden/\\([^/]+\\)/\\'" cur-url)
                (match-string 1 cur-url)))))
     ;; alist-get may return vector or list; coerce to list.
     (if (vectorp notes) (append notes nil) notes))))

(defun a3madkour-pub-citations--lookup-notes-ref (cite-key)
  "If a ref-note exists for CITE-KEY, is published as garden, and resolves
in the manifest snapshot, return its garden slug.  Otherwise nil."
  (let ((path (expand-file-name
               (format "%s.org" cite-key)
               a3madkour-pub-citations--ref-notes-dir)))
    (when (file-exists-p path)
      (let ((publish (a3madkour-pub-citations--read-keyword path "HUGO_PUBLISH"))
            (section (a3madkour-pub-citations--read-keyword path "HUGO_SECTION"))
            (slug-override (a3madkour-pub-citations--read-keyword path "HUGO_SLUG")))
        (when (and (equal publish "t")
                   (equal section "garden"))
          (let* ((default-slug (or slug-override
                                   (downcase
                                    (file-name-base path))))
                 (url (format "/garden/%s/" default-slug)))
            (a3madkour-pub-citations--manifest-slug-for-garden-url
             (and (boundp 'a3madkour-pub--manifest-snapshot)
                  a3madkour-pub--manifest-snapshot)
             url)))))))

;; ---------------------------------------------------------------------
;; cite-emit-yaml: merge / replace into data/citations.yaml (Task 11)
;; ---------------------------------------------------------------------

(defconst a3madkour-pub-citations--required-fields
  '(:authors :year :title :venue)
  "Yaml fields that MUST be non-nil for a citation entry to be valid.")

(defun a3madkour-pub-citations--yaml-escape (s)
  "Escape S for embedding in a double-quoted yaml scalar (basic)."
  (let ((out (replace-regexp-in-string "\\\\" "\\\\\\\\" s)))
    (replace-regexp-in-string "\"" "\\\\\"" out)))

(defun a3madkour-pub-citations--yaml-format-value (key val)
  "Format VAL for yaml.  KEY is the plist key (used for :authors list shape)."
  (cond
   ((eq key :authors)
    (concat "[" (mapconcat
                 (lambda (a) (format "\"%s\""
                                     (a3madkour-pub-citations--yaml-escape a)))
                 val ", ") "]"))
   ((eq key :year) (format "%d" val))
   ((stringp val)  (format "\"%s\"" (a3madkour-pub-citations--yaml-escape val)))
   (t              (format "%s" val))))

(defconst a3madkour-pub-citations--yaml-key-order
  '(:authors :year :title :venue :url :doi :publisher :volume
    :issue :pages :isbn :type :notes_ref))

(defun a3madkour-pub-citations--render-entry (key entry)
  "Render `<key>: ...' yaml block for ENTRY plist."
  (with-output-to-string
    (princ (format "  %s:\n" key))
    (dolist (k a3madkour-pub-citations--yaml-key-order)
      (let ((v (plist-get entry k)))
        (when (and v (not (and (listp v) (null v))))
          (let ((field-name (substring (symbol-name k) 1)))
            (princ (format "    %s: %s\n"
                           field-name
                           (a3madkour-pub-citations--yaml-format-value k v)))))))))

(defun a3madkour-pub-citations--parse-existing-yaml (path)
  "Read PATH and return an alist (KEY . RAW-ENTRY-STRING) of citation
blocks.  Lightweight parse: each `  <key>:' header starts a block; the
block ends at the next `  <key>:' or EOF."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (let ((entries nil)
            current-key
            block-start)
        (while (re-search-forward "^  \\([A-Za-z0-9][A-Za-z0-9-]*\\):\\s-*$"
                                  nil t)
          (when current-key
            (let ((blk (string-trim-right
                        (buffer-substring-no-properties
                         block-start (match-beginning 0))
                        "\n+")))
              (push (cons current-key blk) entries)))
          (setq current-key (match-string-no-properties 1)
                block-start (match-beginning 0)))
        (when current-key
          (let ((blk (string-trim-right
                      (buffer-substring-no-properties block-start (point-max))
                      "\n+")))
            (push (cons current-key blk) entries)))
        (nreverse entries)))))

(defun a3madkour-pub-citations--validate-entry (key entry)
  "Signal if ENTRY is missing any required field."
  (dolist (req a3madkour-pub-citations--required-fields)
    (unless (plist-get entry req)
      (error "%s: bib entry missing required field %s"
             key (substring (symbol-name req) 1)))))

(cl-defun a3madkour-pub-citations/emit-yaml (&key (mode 'merge))
  "Write `data/citations.yaml' from the accumulator.

MODE: `'merge' (default) keeps existing keys not in the accumulator.
      `'replace' drops keys not in the accumulator (sync command path).

Skips file write entirely if the accumulator is empty and MODE is merge."
  (unless a3madkour-pub-citations--accumulator
    (a3madkour-pub-citations--accumulator-init))
  (let ((acc-keys (sort (let (keys)
                          (maphash (lambda (k _) (push k keys))
                                   a3madkour-pub-citations--accumulator)
                          keys)
                        #'string-lessp)))
    (when (or acc-keys (eq mode 'replace))
      (let* ((yaml-path (expand-file-name "citations.yaml"
                                          a3madkour-pub/site-data-dir))
             (tmp-path  (concat yaml-path ".tmp"))
             (existing  (a3madkour-pub-citations--parse-existing-yaml yaml-path))
             ;; New-from-accumulator entries (plists)
             (new-rendered
              (mapcar
               (lambda (k)
                 (let ((entry (a3madkour-pub-bib/resolve k)))
                   (a3madkour-pub-citations--validate-entry k entry)
                   ;; Attach notes_ref if auto-detect resolves.
                   (let ((nref (a3madkour-pub-citations--lookup-notes-ref k)))
                     (when nref
                       (setq entry (plist-put entry :notes_ref nref))))
                   (cons k (a3madkour-pub-citations--render-entry k entry))))
               acc-keys))
             ;; Final entries: per-MODE merge with existing.
             (final
              (cond
               ((eq mode 'replace) new-rendered)
               (t
                (let* ((carry
                        (cl-remove-if
                         (lambda (pair) (assoc (car pair) new-rendered))
                         existing))
                       (merged (append new-rendered carry)))
                  (sort merged
                        (lambda (a b) (string-lessp (car a) (car b)))))))))
        (with-temp-file tmp-path
          (insert "citations:\n")
          (dolist (pair final)
            (insert (cdr pair) "\n")))
        (rename-file tmp-path yaml-path t)))))

;; ---------------------------------------------------------------------
;; a3-sync-citations: full rebuild (Task 15)
;; ---------------------------------------------------------------------

(defun a3madkour-pub-citations--published-source-files ()
  "Walk the manifest snapshot, return list of currently-published `.org'
source-file paths.  Skips entries whose state ≠ \"live\" or whose id
does not resolve via org-roam-id-find."
  (let* ((manifest (and (boundp 'a3madkour-pub--manifest-snapshot)
                        a3madkour-pub--manifest-snapshot))
         (notes (alist-get 'notes manifest)))
    (when (vectorp notes) (setq notes (append notes nil)))
    (delq nil
          (mapcar
           (lambda (note)
             (let ((id (alist-get 'id note))
                   (state (alist-get 'state note)))
               (when (and (equal state "live")
                          (fboundp 'org-roam-id-find))
                 (let ((hit (org-roam-id-find id)))
                   (when hit (car hit))))))
           notes))))

;;;###autoload
(defun a3-sync-citations ()
  "Full rebuild: refresh library.bib from Zotero (best-effort), walk
all currently-published org source files, re-resolve every cite-key,
and overwrite data/citations.yaml in replace mode (purge unused keys).

Errors fail-fast on first unresolvable cite-key."
  (interactive)
  ;; 0. Ensure the manifest snapshot + roam DB are ready.  The shell
  ;; wrapper invokes `begin-publish' before this; the interactive M-x
  ;; path does not.  Lazy-require the parent modules at call time so
  ;; this file can still load early in init (before straight bootstraps
  ;; yaml, which `a3madkour-publish-history' depends on).  Skip
  ;; `begin-publish' when the snapshot is already populated to avoid
  ;; double-init when called from inside an existing publish run.
  (require 'a3madkour-publish-history)
  (require 'a3madkour-publish)
  (unless (and (boundp 'a3madkour-pub--manifest-snapshot)
               a3madkour-pub--manifest-snapshot)
    (a3madkour-pub/begin-publish))
  ;; 1. Refresh .bib (best effort).  When it succeeds (returns non-nil),
  ;; re-parse the file so the updated content is in the parser cache.
  ;; When it fails or is skipped (returns nil), keep the existing cache
  ;; — the on-disk file is used as-is (no re-parse, no cache wipe).
  (let ((refreshed (a3madkour-pub-bib/refresh-from-zotero)))
    ;; 2. Re-parse only if Zotero actually wrote a new file to disk.
    (when (and refreshed
               (not (a3madkour-pub-bib--citar-loaded-p))
               a3madkour-pub-bib/library-path
               (file-exists-p a3madkour-pub-bib/library-path))
      (a3madkour-pub-bib/parse-file a3madkour-pub-bib/library-path)))
  ;; 3. Walk corpus + accumulate.
  (a3madkour-pub-citations--accumulator-init)
  (let ((added 0))
    (dolist (src (a3madkour-pub-citations--published-source-files))
      (when (file-exists-p src)
        (with-temp-buffer
          (insert-file-contents src)
          (org-mode)
          (let ((pairs (a3madkour-pub-citations--scan-buffer)))
            (dolist (pair pairs)
              (let* ((k (car pair))
                     (pos (cdr pair))
                     (existing (gethash k a3madkour-pub-citations--accumulator)))
                (unless (a3madkour-pub-bib/resolve k)
                  (error "%s:%d: cite key %s not found in library.bib" src pos k))
                (puthash k (cons (cons src pos) existing)
                         a3madkour-pub-citations--accumulator)
                (setq added (1+ added))))))))
    ;; 4. Overwrite yaml in replace mode.
    (a3madkour-pub-citations/emit-yaml :mode 'replace)
    (message "[a3-sync-citations] %d cite refs across %d keys synced."
             added
             (hash-table-count a3madkour-pub-citations--accumulator))))

(provide 'a3madkour-publish-citations)

;;; a3madkour-publish-citations.el ends here
