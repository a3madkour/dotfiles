;;; a3madkour-publish-rewrite.el --- Link rewriting for org-mode publish -*- lexical-binding: t; -*-

;;; Commentary:

;; Implements parent-spec §6 link rewriting contract for A.1.b / A.1.c.
;; - `a3madkour-pub/rewrite-link' — per-link-type dispatcher.
;; - `a3madkour-pub-rewrite/rewrite-buffer-links' — buffer-scan pre-export
;;   step that substitutes [[id:UUID]]/[[file:]]/typed-link forms with the
;;   resolved HTML (wrapped in @@html:@@ org export snippets) before
;;   ox-hugo touches the source.  Used by B.1.1's garden handler.
;; - `a3madkour-pub--heading-anchor' — Hugo `github`-style heading anchor slug.
;; - `a3madkour-pub-typed-link-types' — defcustom listing recognized custom
;;   typed-link types (e.g., `supports`, `contradicts`).
;;
;; Asset-shaped links dispatch to `a3madkour-pub/rewrite-asset-link' (A.1.c).

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-id)

;; Forward declaration: rewrite-asset-link is in a3madkour-publish-assets.el,
;; which itself requires this file (for --html-escape).  Avoid the circular
;; require by autoloading the symbol.
(autoload 'a3madkour-pub/rewrite-asset-link "a3madkour-publish-assets")

(defgroup a3madkour-pub-rewrite nil
  "Link rewriter for the a3madkour-publish library."
  :group 'a3madkour-pub)

(defcustom a3madkour-pub-typed-link-types
  '("supports" "contradicts" "extends" "example-of" "causes")
  "List of recognized custom typed-link types.

For any org link of the form `[[<type>:UUID][text]]` where `<type>` is
a member of this list, `a3madkour-pub/rewrite-link' treats it as an
id-link AND emits `class=\"link-<type>\"` on the rendered anchor.

Narrowing (Task 17 implementation, spec amendment deferred to Task 19):
the class is emitted ONLY on `:html` variants (live/draft targets), NOT
on `:inert` variants — inert results have no anchor to attach a class to.

See parent spec §6 (custom typed-link CSS class emission)."
  :type '(repeat string)
  :group 'a3madkour-pub-rewrite)

(defun a3madkour-pub--heading-anchor (heading-text)
  "Compute the Hugo `github`-style heading anchor for HEADING-TEXT.

Algorithm (from gohugoio/hugo markup/goldmark/autoid.go,
`sanitizeAnchorNameWithHook' with `github' anchor name sanitizer):
  1. Trim leading/trailing whitespace.
  2. Keep only Unicode letters (Lu Ll Lt Lm Lo), decimal digits (Nd),
     and the chars ` `, `-`, `_`.  Drop everything else.
  3. Lowercase the kept string.
  4. Replace each ` ` with `-`.
  5. If the result is empty, return \"heading\" (Hugo's fallback).

Unicode letters are PRESERVED (`café' stays `café', not folded).
Consecutive spaces produce consecutive hyphens (no collapse).
Nl (letter-number, e.g. Roman numerals) and No (other-number, e.g.
½, ²) are DROPPED — Go's `unicode.IsDigit' is strictly Nd."
  (let* ((trimmed (string-trim heading-text))
         (kept (apply #'string
                      (cl-loop for c across trimmed
                               when (or (= c ?\s) (= c ?-) (= c ?_)
                                        (memq (get-char-code-property c 'general-category)
                                              '(Lu Ll Lt Lm Lo Nd)))
                               collect c)))
         (lowered (downcase kept))
         (hyphenated (replace-regexp-in-string " " "-" lowered)))
    (if (string-empty-p hyphenated)
        "heading"
      hyphenated)))

(defun a3madkour-pub--html-escape (s)
  "Escape `&', `<', `>', `\"', `'' in S for HTML attribute + element-body context.

This is the single chokepoint for HTML escaping in the publish-rewrite
+ publish-assets modules.  Per parent spec §6 (HTML escaping contract),
every `:html' emit's interpolated values route through this helper.

`&' is escaped FIRST to avoid double-encoding the other entities'
ampersands.  Returns the empty string when S is nil (defensive; some
upstream parsers may pass nil)."
  (if (or (null s) (string-empty-p s))
      ""
    (let ((out s))
      ;; Order matters: & must come first.
      (setq out (replace-regexp-in-string "&" "&amp;" out t t))
      (setq out (replace-regexp-in-string "<" "&lt;" out t t))
      (setq out (replace-regexp-in-string ">" "&gt;" out t t))
      (setq out (replace-regexp-in-string "\"" "&quot;" out t t))
      (setq out (replace-regexp-in-string "'" "&#39;" out t t))
      out)))

(defun a3madkour-pub--parse-org-link (org-link)
  "Parse an org link form `[[<path>][<text>]]` (or `[[<path>]]`) into a plist.

Returns (:path PATH :text TEXT-OR-PATH).  TEXT-OR-PATH is the display
text if present, else PATH (org's default rendering)."
  (cond
   ;; [[path][text]]
   ((string-match "\\`\\[\\[\\(.*?\\)\\]\\[\\(.*?\\)\\]\\]\\'" org-link)
    (list :path (match-string 1 org-link)
          :text (match-string 2 org-link)))
   ;; [[path]]
   ((string-match "\\`\\[\\[\\(.*?\\)\\]\\]\\'" org-link)
    (let ((path (match-string 1 org-link)))
      (list :path path :text path)))
   (t (error "Unparseable org link: %S" org-link))))

(defun a3madkour-pub--link-scheme (path)
  "Return the URL scheme of PATH as a string (e.g., \"https\"), or nil."
  (when (string-match "\\`\\([a-z][a-z0-9+.-]*\\):" path)
    (match-string 1 path)))

(defun a3madkour-pub--external-scheme-p (scheme)
  "Return non-nil if SCHEME is an external URL scheme (not id/file/custom-type)."
  (and scheme
       (not (equal scheme "id"))
       (not (equal scheme "file"))
       (not (member scheme a3madkour-pub-typed-link-types))))

(defun a3madkour-pub--strip-file-prefix-if-asset (path)
  "Return PATH with a `file:' prefix stripped if the remainder is asset-shaped.

Mirrors the normalization in `a3madkour-pub--extract-asset-refs' so both
walkers classify `[[file:asset.ext]]' and `[[asset.ext]]' identically.

Paths without `file:' prefix are returned unchanged.  `file:' paths whose
target has a `.org' extension are returned unchanged (kept as note links)."
  (cond
   ((not (string-prefix-p "file:" path)) path)
   ((let ((bare (substring path 5)))
      (and (file-name-extension bare)
           (not (member (file-name-extension bare) '("org")))))
    (substring path 5))
   (t path)))

(defun a3madkour-pub--asset-shaped-link-p (path)
  "Return non-nil if PATH looks like an asset link (image / pdf / audio / etc.).

Heuristic: PATH has no URL scheme AND its extension is not `org'.
Captures the common forms:
  - relative: `./assets/page/foo/x.png', `./assets/shared/diagram.svg'
  - absolute: `/home/.../foo.png', `~/org/notes/assets/page/foo/x.png'
A.1.c will replace this with proper canonical-root resolution."
  (and (not (a3madkour-pub--link-scheme path))
       (let ((ext (file-name-extension path)))
         (and ext (not (member ext '("org")))))))

(defun a3madkour-pub--target-has-heading-p (target-file heading-text)
  "Return non-nil iff TARGET-FILE contains an org heading matching HEADING-TEXT.
Matches case-sensitively against trimmed heading text.  Tolerates optional
TODO keywords, priority cookies, statistics cookies, and tags on the
heading line (org's standard heading decorations).
Returns nil if TARGET-FILE doesn't exist or can't be read."
  (when (and target-file (file-exists-p target-file))
    (with-temp-buffer
      (insert-file-contents target-file)
      (goto-char (point-min))
      (let ((heading-re
             (concat "^\\*+ +"
                     "\\(?:[A-Z]+ +\\)?"           ; optional TODO/DONE/NEXT (any uppercase word + spaces)
                     "\\(?:\\[#[A-Za-z0-9]\\] +\\)?"  ; optional priority cookie
                     (regexp-quote (string-trim heading-text))
                     "\\(?:\\s-+\\|$\\)"))           ; followed by whitespace or end-of-line (allows trailing cookies/tags)
            (case-fold-search nil))
        (re-search-forward heading-re nil t)))))

(defun a3madkour-pub--rewrite-id-link (raw-path text source-note-id)
  "Rewrite a `[[id:UUID...]]' link.
RAW-PATH is the full path including `id:` prefix (e.g. `id:UUID` or
`id:UUID::*Heading`).  TEXT is the display text — if it equals
RAW-PATH (no display text given in org), the resolved URL is used.
SOURCE-NOTE-ID determines whether to emit the live→draft warning.

When a `::*Heading` suffix is present and the target file is resolvable,
a WARN is emitted if the heading text is not found in the target's org
source (the href is still emitted — anchor may resolve at site-build
time once published, or may 404; the WARN surfaces the risk)."
  (let* ((text (or text raw-path ""))                ; defensive: callers may pass nil
         (id-part (substring raw-path 3))            ; drop "id:"
         (parts (split-string id-part "::" t))       ; "UUID" or ("UUID" "*Heading")
         (target-id (car parts))
         (heading-suffix (cadr parts))               ; nil or "*Heading"
         (heading-text (and heading-suffix
                            (string-trim (substring heading-suffix 1))))
         (target-state (a3madkour-pub/published-p target-id))
         (target-url (a3madkour-pub/note-url target-id))
         (source-state (a3madkour-pub/published-p source-note-id))
         ;; When org link has no display text, --parse-org-link sets text = path.
         ;; Substitute the resolved URL so the rendered text is meaningful.
         (display (if (equal text raw-path) target-url text)))
    (cond
     ;; Unknown UUID or private → :inert + WARN
     ((null target-state)
      (list :inert (or display text "")
            :warnings (list (format "link target id:%s is private or unknown" target-id))))
     ;; Live OR draft target → :html
     (t
      (let* ((target-file (and heading-suffix
                               (a3madkour-pub--id-to-file target-id)))
             (href (if heading-suffix
                       (format "%s#%s"
                               target-url
                               (a3madkour-pub--heading-anchor heading-text))
                     target-url))
             (warnings
              (delq nil
                    (list
                     (when (and (eq target-state 'draft) (eq source-state 'live))
                       (format "live note links to draft target id:%s" target-id))
                     (when (and target-file
                                (not (a3madkour-pub--target-has-heading-p
                                      target-file heading-text)))
                       (format "heading %S not found in target id:%s"
                               heading-text target-id))))))
        (list :html (format "<a href=\"%s\">%s</a>"
                            (a3madkour-pub--html-escape href)
                            (a3madkour-pub--html-escape display))
              :warnings warnings))))))

(defun a3madkour-pub--file-top-level-id (file)
  "Return the value of the top-level :ID: property in FILE as a string, or nil.

\"Top level\" here means the file-level property drawer that ox-hugo /
org-roam puts at the very top, BEFORE the first headline.  Subtree-level
IDs are out of scope for file-link resolution (authors should link to
subtree IDs via `[[id:UUID]]` directly).  Returns nil if FILE doesn't
exist or has no top-level :ID:."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((first-heading
             (save-excursion
               (when (re-search-forward "^\\*+ " nil t)
                 (match-beginning 0)))))
        (when (re-search-forward "^:ID: +\\([0-9a-f-]+\\)" first-heading t)
          (match-string 1))))))

(defun a3madkour-pub--rewrite-file-link (raw-path text source-note-id &optional source-file)
  "Rewrite a `[[file:...]]' link by resolving target's `:ID:` and
recursing into id-link semantics, OR emit :inert + WARN if no :ID:.

RAW-PATH is the full path with `file:` prefix; stripped internally.
Relative paths in RAW-PATH are resolved against the source note's
directory (matches org-mode semantics — `[[file:foo.org]]` is relative
to the buffer containing the link).

SOURCE-FILE, when supplied, is the source note's absolute file path —
used directly as the resolution root.  When not supplied, derives via
`(--id-to-file source-note-id)' (legacy callers).

Bug 1.2 (polish-and-bugfix-roadmap.md) — parity with the figref fix in
commit `1edd900' (`rewrite-asset-link').  Source notes outside
`org-roam-directory' (e.g. essays under `~/org/essays/' when org-roam
points at `~/org/notes/') aren't in the DB, so `--id-to-file' returns
nil and the resolver silently fell back to `default-directory'.  For
interactive Emacs use that's usually the source dir; for batch / CLI
publishes it isn't, and the relative path lookup silently broke.
Caller-supplied SOURCE-FILE bypasses the DB lookup entirely."
  (let* ((file-path (substring raw-path 5))                ; drop "file:"
         (effective-source-file
          (or source-file
              (and source-note-id
                   (a3madkour-pub--id-to-file source-note-id))))
         (source-dir (and effective-source-file
                          (file-name-directory effective-source-file)))
         ;; If we have a source dir, resolve relative to it; otherwise
         ;; fall back to default-directory (degrades gracefully for tests
         ;; or shell invocations without a known source).
         (target-file (expand-file-name file-path (or source-dir default-directory)))
         (target-id (a3madkour-pub--file-top-level-id target-file)))
    (if target-id
        (a3madkour-pub--rewrite-id-link
         (concat "id:" target-id) text source-note-id)
      (list :inert text
            :warnings (list (format "file-link target %s lacks :ID:; cannot resolve"
                                    target-file))))))

(defun a3madkour-pub--rewrite-typed-link (typed-link-type uuid text source-note-id)
  "Rewrite `[[<type>:UUID][text]]' for TYPED-LINK-TYPE (e.g., \"supports\").
UUID is the bare id (no `id:' prefix).  TEXT is the display text.

Resolves via id-link rules; on :html result, inserts class=\"link-<type>\"
into the rendered anchor.  :inert variants pass through unchanged
(class only applies to the anchor, which doesn't exist for inert)."
  (let* ((id-result (a3madkour-pub--rewrite-id-link
                     (concat "id:" uuid) text source-note-id))
         (html (plist-get id-result :html)))
    (if html
        (list :html
              (replace-regexp-in-string
               "\\`<a "
               (format "<a class=\"link-%s\" " typed-link-type)
               html)
              :warnings (plist-get id-result :warnings))
      id-result)))

(defun a3madkour-pub/rewrite-link (org-link source-note-id &optional source-file)
  "Rewrite ORG-LINK to web HTML, inert text, or asset placeholder.

ORG-LINK is the raw org bracket form, e.g., `\"[[id:UUID][text]]\"`.
SOURCE-NOTE-ID is the id of the org file containing ORG-LINK
(used to determine source state for the live→draft WARN).
SOURCE-FILE, when supplied, is the source note's absolute file path —
threaded through to asset-link resolution so files outside
`org-roam-directory' still hit the essays-aware branch.

Returns one of:
  (:html HTML-STRING :warnings (WARN ...))    ; rendered anchor
  (:inert TEXT-STRING :warnings (WARN ...))   ; link erased; text preserved

See parent spec §6 for the per-link-type rules."
  (let* ((parsed (a3madkour-pub--parse-org-link org-link))
         (raw-path (plist-get parsed :path))
         (path (a3madkour-pub--strip-file-prefix-if-asset raw-path))
         (text (plist-get parsed :text))
         (scheme (a3madkour-pub--link-scheme path)))
    (cond
     ;; id-link
     ((equal scheme "id")
      (a3madkour-pub--rewrite-id-link path text source-note-id))
     ;; file-link — auto-convert to id-link via target's :ID:
     ((equal scheme "file")
      (a3madkour-pub--rewrite-file-link path text source-note-id source-file))
     ;; Custom typed link (`[[supports:UUID][text]]` etc.) — id-link with
     ;; class=\"link-<type>\" injected on the rendered anchor.
     ((member scheme a3madkour-pub-typed-link-types)
      (a3madkour-pub--rewrite-typed-link
       scheme
       (substring path (1+ (length scheme)))  ; drop "<type>:"
       text source-note-id))
     ;; External URL scheme — pass through unchanged.
     ((a3madkour-pub--external-scheme-p scheme)
      (list :html (format "<a href=\"%s\">%s</a>"
                          (a3madkour-pub--html-escape path)
                          (a3madkour-pub--html-escape text))
            :warnings nil))
     ;; Asset-shaped link (no scheme, non-`.org` extension) — A.1.c dispatch.
     ((a3madkour-pub--asset-shaped-link-p path)
      (a3madkour-pub/rewrite-asset-link path text source-note-id nil source-file))
     ;; Other branches added in later tasks.
     (t
      (error "rewrite-link: scheme %S not yet handled (this branch lands in a later task)"
             scheme)))))

(defconst a3madkour-pub-rewrite--bracket-link-re
  "\\[\\[\\([^][]+\\)\\(?:\\]\\[\\([^][]+\\)\\)?\\]\\]"
  "Regex matching an org bracket-link form `[[path]]' or `[[path][text]]'.
Group 1 = path, group 2 = optional display text.  Rejects nested
brackets (`[^][]+') — org's bracket-link syntax does not permit them in
either path or text, so this is sufficient for our scan.")

(defun a3madkour-pub-rewrite/rewrite-buffer-links (source-note-id &optional source-file)
  "Scan the current buffer for org bracket-link forms; rewrite each in place.

For every `[[...]]` form whose path uses a scheme A.1 knows how to resolve
(`id:', `file:', or any member of `a3madkour-pub-typed-link-types'), calls
`a3madkour-pub/rewrite-link' and substitutes the match with the returned
`:html' (resolved → inline HTML anchor) or `:inert' (unresolved → plain
text).  External URLs and asset-shaped links are skipped by this scanner —
ox-hugo handles those correctly on its own.

SOURCE-NOTE-ID is the org-roam :ID: of the file whose contents fill the
buffer; threaded through to `rewrite-link' for source-state checks.

Returns the accumulated list of warning strings (empty list when none).

Intended for use as the pre-export step in B's per-section handlers: the
caller copies the source `.org' to a temp buffer/file, applies this helper,
then hands the rewritten text to `a3madkour-pub-export/export-file'.  This
keeps the `[[...]]` form out of ox-hugo's input → prevents ox-hugo from
emitting `{{< relref \"<underscore_filename>.md\" >}}' shortcodes that
would never resolve against B's hyphen-slug bundle paths."
  (let ((warnings nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward a3madkour-pub-rewrite--bracket-link-re nil t)
        ;; Capture bounds and text NOW, before any string-match call clobbers
        ;; the global match data.
        (let* ((match-beg (match-beginning 0))
               (match-end (match-end 0))
               (org-link  (match-string 0))
               (parsed    (a3madkour-pub--parse-org-link org-link))
               (path      (plist-get parsed :path))
               (scheme    (a3madkour-pub--link-scheme path)))
          (when (or (equal scheme "id")
                    (equal scheme "file")
                    (member scheme a3madkour-pub-typed-link-types))
            (let* ((result      (a3madkour-pub/rewrite-link
                                 org-link source-note-id source-file))
                   (raw-html    (plist-get result :html))
                   ;; @@html:...@@ is org's HTML export snippet — passes raw
                   ;; HTML verbatim through ox-hugo's markdown export rather
                   ;; than HTML-escaping bare <a> tags as paragraph text.
                   (replacement (if raw-html
                                    (format "@@html:%s@@" raw-html)
                                  (or (plist-get result :inert) "")))
                   (warns       (plist-get result :warnings)))
              ;; nconc not append: warns is a let*-local not referenced
              ;; again, so the destructive splice is safe + avoids a copy.
              (when warns
                (setq warnings (nconc warnings warns)))
              ;; Use explicit region replacement so we don't depend on match
              ;; data still being valid after the rewrite-link call chain.
              (delete-region match-beg match-end)
              (goto-char match-beg)
              (insert replacement))))))
    warnings))

(defun a3madkour-pub-rewrite/rewrite-to-tmp-file (source-file source-note-id &optional log-tag)
  "Copy SOURCE-FILE to a fresh temp `.org' file with all org links
pre-rewritten via `a3madkour-pub-rewrite/rewrite-buffer-links'.

SOURCE-NOTE-ID is the org-roam :ID: of SOURCE-FILE, threaded through to
the rewriter for source-state checks.

LOG-TAG (optional, default \"a3-pub-rewrite\") is the bracketed prefix on
rewriter warnings surfaced via `message'; per-handler callers may pass a
section-specific tag (e.g. \"a3-pub-garden\") so authors can grep the
publish log by handler.

Returns the absolute path of the temp file.  Caller is responsible for
`delete-file' on the returned path (typical pattern: wrap the consumer
in an `unwind-protect' that deletes on cleanup).

If this function signals before returning successfully, it deletes the
tmp file itself — the caller's `delete-file' obligation only applies to
the happy-path return."
  (let ((tmp (make-temp-file "a3-pub-pre-export-" nil ".org"))
        (tag (or log-tag "a3-pub-rewrite"))
        (ok nil)
        warnings)
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert-file-contents source-file)
            (setq warnings
                  (a3madkour-pub-rewrite/rewrite-buffer-links source-note-id source-file))
            ;; F Task 12: cite-key rewrite runs in the same pre-export pass.
            ;; Loaded lazily so non-F-aware tests of rewrite-to-tmp-file still
            ;; work; the citations module is part of a3-pub.sh's `-l' list
            ;; in publish-living / publish-deliberate / sync exec blocks.
            (when (require 'a3madkour-publish-citations nil 'noerror)
              (a3madkour-pub-citations/rewrite-cite-keys-in-buffer source-file))
            (write-region (point-min) (point-max) tmp nil 'quiet))
          (dolist (w warnings)
            (message "[%s] rewrite WARN (%s): %s" tag source-file w))
          (setq ok t)
          tmp)
      ;; Cleanup on error: delete the tmp file so a mid-helper signal
      ;; doesn't leave it stranded.  On success (`ok' is t) the caller
      ;; takes ownership and is responsible for delete-file.
      (unless ok
        (when (file-exists-p tmp) (delete-file tmp))))))

(provide 'a3madkour-publish-rewrite)

;;; a3madkour-publish-rewrite.el ends here
