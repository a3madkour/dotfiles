;;; a3madkour-publish-essays.el --- B.4 essays per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; B.4: essays per-file publish handler (first publish-deliberate slice).
;; Pipeline mirrors B.1/B.3 (pre-export-rewrite → export → normalize →
;; asset-copy → write-if-different → record-publish), with a novel
;; post-export markdown body scan for the 6 `has_*' frontmatter flags.
;;
;; Registered into `a3madkour-pub-deliberate--handlers' (see Task 9) as
;;   (essays . a3madkour-pub-essays/publish-essay-file)

;;; Code:

(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)

;; Task 4: has_* body scanner.

(defun a3madkour-pub-essays--scan-has-flags (body)
  "Return a plist of 6 has_* booleans derived from substring scan of BODY
\(post-export markdown).

Patterns (all case-sensitive; shortcodes match the trailing space):
  :has_sidenotes  <- `{{< sidenote '
  :has_citations  <- `{{< cite '
  :has_footnotes  <- `[^N]' markdown footnote reference
  :has_math       <- `{{< math ' OR raw KaTeX delim `\\(' OR `\\['
  :has_widgets    <- `{{< widget '
  :has_video_sync <- `{{< video-sync '

Each value is `t' on a positive match or `nil' on no match.  Callers
merge with per-keyword `#+HUGO_HAS_<X>:' overrides (see Task 5)."
  (list :has_sidenotes  (and (string-match-p "{{< sidenote "   body) t)
        :has_citations  (and (string-match-p "{{< cite "        body) t)
        :has_footnotes  (and (string-match-p "\\[\\^[^]]+\\]"  body) t)
        :has_math       (and (or (string-match-p "{{< math "    body)
                                 (string-match-p "\\\\("        body)
                                 (string-match-p "\\\\\\["      body)) t)
        :has_widgets    (and (string-match-p "{{< widget "      body) t)
        :has_video_sync (and (string-match-p "{{< video-sync "  body) t)))

;; Task 5: has_* override merge.

(defconst a3madkour-pub-essays--has-flag-keywords
  '((:has_sidenotes  . "HUGO_HAS_SIDENOTES")
    (:has_citations  . "HUGO_HAS_CITATIONS")
    (:has_footnotes  . "HUGO_HAS_FOOTNOTES")
    (:has_math       . "HUGO_HAS_MATH")
    (:has_widgets    . "HUGO_HAS_WIDGETS")
    (:has_video_sync . "HUGO_HAS_VIDEO_SYNC"))
  "Alist mapping each has_* plist key to its `#+HUGO_HAS_<X>:' keyword.")

(defun a3madkour-pub-essays--read-has-override (file plist-key)
  "Read `#+HUGO_<KEYWORD>:' from FILE for PLIST-KEY.
Returns a 3-state value: t (\"t\"/\"true\"/\"1\"/\"yes\" → t), nil (\"nil\"/\"false\"/\"0\"/\"no\" → nil),
or `:unset' if the keyword is absent or value is empty."
  (let* ((kw (cdr (assq plist-key a3madkour-pub-essays--has-flag-keywords)))
         (raw (a3madkour-pub-frontmatter--read-org-keyword file kw)))
    (cond
     ((null raw) :unset)
     ((member (downcase raw) '("t" "true" "1" "yes")) t)
     ((member (downcase raw) '("nil" "false" "0" "no")) nil)
     (t :unset))))

(defun a3madkour-pub-essays--merge-has-flags (scan-plist file)
  "Merge keyword override on top of SCAN-PLIST for FILE.
For each has_* key: if `#+HUGO_HAS_<X>:' is set in FILE, its value wins;
else SCAN-PLIST's value passes through.  Returns a new plist."
  (let ((out (copy-sequence scan-plist)))
    (dolist (cell a3madkour-pub-essays--has-flag-keywords)
      (let* ((k (car cell))
             (override (a3madkour-pub-essays--read-has-override file k)))
        (unless (eq override :unset)
          (setq out (plist-put out k override)))))
    out))

;; Task 8: rendering helpers (mirror garden's; future shared extraction
;; tracked as B.4 follow-up #3).

(defcustom a3madkour-pub-essays/section-dir-name "essays"
  "Hugo content section directory name for essays (relative to site root)."
  :type 'string
  :group 'a3madkour-pub)

(defun a3madkour-pub-essays--site-root ()
  "Derive the Hugo site root from `a3madkour-pub/site-data-dir'."
  (file-name-as-directory
   (directory-file-name
    (file-name-directory
     (directory-file-name
      (file-name-as-directory a3madkour-pub/site-data-dir))))))

(defun a3madkour-pub-essays--write-if-different (path content)
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

(defconst a3madkour-pub-essays--date-re
  "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
  "Regex for bare YYYY-MM-DD date strings (emitted unquoted in YAML).")

(defun a3madkour-pub-essays--render-yaml-value (v)
  "Render V as a YAML scalar/list value.  Same contract as garden's
helper: strings quoted; YYYY-MM-DD dates unquoted; numbers as-is;
t/nil → true/false; lists of strings → JSON-style array.

NOTE: nil is also a list in Emacs Lisp — test null BEFORE listp."
  (cond
   ((null v)    "false")
   ((eq v t)    "true")
   ((and (stringp v)
         (string-match-p a3madkour-pub-essays--date-re v))
    v)
   ((stringp v) (format "\"%s\"" v))
   ((numberp v) (format "%s" v))
   ((listp v)
    (format "[%s]"
            (mapconcat (lambda (s) (format "\"%s\"" s)) v ", ")))))

(defun a3madkour-pub-essays--render-frontmatter (alist)
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
                       (a3madkour-pub-essays--render-yaml-value (cdr cell))))
             sorted "\n")
            "\n---\n")))

;; Task 8: pipeline entry.

(defun a3madkour-pub-essays/publish-essay-file (file)
  "Publish a single essay FILE to content/essays/<slug>/index.md.

Pipeline:
  1. resolve metadata (id / slug)
  2. pre-export rewrite via shared rewrite-to-tmp-file (B.4 cleanup commit)
  3. ox-hugo export
  4. scan post-export body for has_* shortcodes
  5. inject :scan-plist into raw fm; normalize via \\='essays dispatch arm
  6. asset-validate-and-copy (hero.svg etc.)
  7. render frontmatter + body; write if different
  8. record-publish"
  (let* ((md         (a3madkour-pub/note-metadata file))
         (id         (plist-get md :id))
         (slug       (plist-get md :slug))
         (new-url    (a3madkour-pub/note-url file))
         (site-root  (a3madkour-pub-essays--site-root))
         (bundle-dir (expand-file-name
                      (format "content/%s/%s/"
                              a3madkour-pub-essays/section-dir-name slug)
                      site-root))
         (out-path   (expand-file-name "index.md" bundle-dir))
         (tmp-src    (a3madkour-pub-rewrite/rewrite-to-tmp-file
                      file id "a3-pub-essays"))
         (exported   (unwind-protect
                         (a3madkour-pub-export/export-file tmp-src)
                       (when (file-exists-p tmp-src)
                         (delete-file tmp-src))))
         (body       (plist-get exported :body))
         (scan-pl    (a3madkour-pub-essays--scan-has-flags (or body "")))
         (raw-fm     (cons (cons :scan-plist scan-pl)
                           (or (plist-get exported :frontmatter) '())))
         (normalized (a3madkour-pub-frontmatter/normalize 'essays raw-fm file)))
    (a3madkour-pub/asset-validate-and-copy file bundle-dir)
    (a3madkour-pub-essays--write-if-different
     out-path
     (concat (a3madkour-pub-essays--render-frontmatter normalized) (or body "")))
    (a3madkour-pub-history/record-publish id new-url 'live)))

(provide 'a3madkour-publish-essays)

;;; a3madkour-publish-essays.el ends here
