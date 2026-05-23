;;; a3madkour-publish-rewrite.el --- Link rewriting for org-mode publish -*- lexical-binding: t; -*-

;;; Commentary:

;; Implements parent-spec §6 link rewriting contract for A.1.b.
;; - `a3madkour-pub/rewrite-link' — per-link-type dispatcher.
;; - `a3madkour-pub--heading-anchor' — Hugo `github`-style heading anchor slug.
;; - `a3madkour-pub-typed-link-types' — defcustom listing recognized custom
;;   typed-link types (e.g., `supports`, `contradicts`).
;;
;; Asset-shaped links return `:pending-asset` in A.1.b; A.1.c upgrades
;; to real handling.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-id)

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
        (list :html (format "<a href=\"%s\">%s</a>" href display)
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

(defun a3madkour-pub--rewrite-file-link (raw-path text source-note-id)
  "Rewrite a `[[file:...]]' link by resolving target's `:ID:` and
recursing into id-link semantics, OR emit :inert + WARN if no :ID:.

RAW-PATH is the full path with `file:` prefix; stripped internally.
Relative paths in RAW-PATH are resolved against the SOURCE-NOTE-ID's
file directory (matches org-mode semantics — `[[file:foo.org]]` is
relative to the buffer containing the link)."
  (let* ((file-path (substring raw-path 5))                ; drop "file:"
         (source-file (and source-note-id
                           (a3madkour-pub--id-to-file source-note-id)))
         (source-dir (and source-file
                          (file-name-directory source-file)))
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

(defun a3madkour-pub/rewrite-link (org-link source-note-id)
  "Rewrite ORG-LINK to web HTML, inert text, or asset placeholder.

ORG-LINK is the raw org bracket form, e.g., `\"[[id:UUID][text]]\"`.
SOURCE-NOTE-ID is the id of the org file containing ORG-LINK
(used to determine source state for the live→draft WARN).

Returns one of:
  (:html HTML-STRING :warnings (WARN ...))    ; rendered anchor
  (:inert TEXT-STRING :warnings (WARN ...))   ; link erased; text preserved
  (:pending-asset ORIG-LINK :warnings (...))  ; A.1.b stub; A.1.c upgrades

See parent spec §6 for the per-link-type rules."
  (let* ((parsed (a3madkour-pub--parse-org-link org-link))
         (path (plist-get parsed :path))
         (text (plist-get parsed :text))
         (scheme (a3madkour-pub--link-scheme path)))
    (cond
     ;; id-link
     ((equal scheme "id")
      (a3madkour-pub--rewrite-id-link path text source-note-id))
     ;; file-link — auto-convert to id-link via target's :ID:
     ((equal scheme "file")
      (a3madkour-pub--rewrite-file-link path text source-note-id))
     ;; Custom typed link (`[[supports:UUID][text]]` etc.) — id-link with
     ;; class=\"link-<type>\" injected on the rendered anchor.
     ((member scheme a3madkour-pub-typed-link-types)
      (a3madkour-pub--rewrite-typed-link
       scheme
       (substring path (1+ (length scheme)))  ; drop "<type>:"
       text source-note-id))
     ;; External URL scheme — pass through unchanged.
     ((a3madkour-pub--external-scheme-p scheme)
      (list :html (format "<a href=\"%s\">%s</a>" path text)
            :warnings nil))
     ;; Asset-shaped link (no scheme, non-`.org` extension) — A.1.b stub;
     ;; A.1.c will replace with canonical-root resolution.
     ((a3madkour-pub--asset-shaped-link-p path)
      (list :pending-asset org-link
            :warnings (list (format "asset link %S; rewriting deferred to A.1.c"
                                    org-link))))
     ;; Other branches added in later tasks.
     (t
      (error "rewrite-link: scheme %S not yet handled (this branch lands in a later task)"
             scheme)))))

(provide 'a3madkour-publish-rewrite)

;;; a3madkour-publish-rewrite.el ends here
