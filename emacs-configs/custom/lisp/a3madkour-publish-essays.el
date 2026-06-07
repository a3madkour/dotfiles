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

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)

;; Task 4: has_* body scanner.

(defun a3madkour-pub-essays--strip-code-fences (body)
  "Return BODY with ```-fenced code blocks and org `#+begin_src'/`#+begin_example'
regions removed.  Inline backtick spans and org `~…~' / `=…=' spans are NOT
stripped (single-line, math-rare, stripping would over-complicate the helper).

Used before the has_math marker scan so that code examples teaching LaTeX
syntax don't false-positive on \\(, \\[, or \\begin{…}."
  (let ((s body))
    ;; ```-fenced (Hugo markdown style; post-export form)
    (setq s (replace-regexp-in-string
             "```[a-zA-Z0-9_+-]*\n\\(.\\|\n\\)*?\n```" "" s t t))
    ;; #+begin_src / #+end_src (org-mode form; pre-export form)
    (setq s (replace-regexp-in-string
             "#\\+begin_src\\(.\\|\n\\)*?#\\+end_src" "" s t t))
    ;; #+begin_example / #+end_example (org-mode form)
    (setq s (replace-regexp-in-string
             "#\\+begin_example\\(.\\|\n\\)*?#\\+end_example" "" s t t))
    s))

(defun a3madkour-pub-essays--scan-has-flags (body)
  "Return a plist of 6 has_* booleans derived from substring scan of BODY
\(post-export markdown).

Patterns (all case-sensitive; shortcodes match the trailing space):
  :has_sidenotes  <- `{{< sidenote '
  :has_citations  <- `{{< cite '
  :has_footnotes  <- `[^N]' markdown footnote reference
  :has_math       <- `{{< math ' OR raw KaTeX delim `\\(' OR `\\[' OR `\\begin{<env>}'
                     (fenced code blocks are stripped before this scan to avoid
                     false-positives on code teaching LaTeX syntax)
  :has_widgets    <- `{{< widget '
  :has_video_sync <- `{{< video-sync '

Each value is `t' on a positive match or `nil' on no match.  Callers
merge with per-keyword `#+HUGO_HAS_<X>:' overrides (see Task 5)."
  (let ((math-body (a3madkour-pub-essays--strip-code-fences body)))
    (list :has_sidenotes  (and (string-match-p "{{< sidenote "   body) t)
          :has_citations  (and (string-match-p "{{< cite "        body) t)
          :has_footnotes  (and (string-match-p "\\[\\^[^]]+\\]"  body) t)
          :has_math       (and (or (string-match-p "{{< math "    math-body)
                                   (string-match-p "\\\\("        math-body)
                                   (string-match-p "\\\\\\["      math-body)
                                   (string-match-p "\\\\begin{[a-zA-Z]+\\*?}" math-body)) t)
          :has_widgets    (and (string-match-p "{{< widget "      body) t)
          :has_video_sync (and (string-match-p "{{< video-sync "  body) t))))

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

;; Spot-check fix-up: per-essay asset directory copy.
;; `asset-validate-and-copy' only walks [[org-link]] references; this helper
;; covers the `#+HUGO_HERO: hero.svg' + `{{< figure src="hero.svg" >}}'
;; patterns where the source lives at `essays-dir/assets/<id>/'.

(defun a3madkour-pub-essays--copy-asset-dir (id bundle-dest-dir)
  "Recursively copy `essays-dir/assets/ID/' into BUNDLE-DEST-DIR.
No-op when the source directory does not exist.  Returns the list of
basenames copied, or nil if no source dir."
  (let* ((src-dir (expand-file-name (format "assets/%s/" id)
                                    a3madkour-pub/essays-dir))
         (src-dir-as-dir (file-name-as-directory src-dir)))
    (when (file-directory-p src-dir-as-dir)
      (make-directory bundle-dest-dir t)
      (let ((copied nil))
        (dolist (f (directory-files src-dir-as-dir t directory-files-no-dot-files-regexp))
          (let ((dest (expand-file-name (file-name-nondirectory f) bundle-dest-dir)))
            (if (file-directory-p f)
                (copy-directory f dest t t t)
              (copy-file f dest t))
            (push (file-name-nondirectory f) copied)))
        (nreverse copied)))))

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
Returns a string with leading/trailing `---' delimiters.

Key-aware special cases applied before the generic --render-yaml-value dispatch:
  `tags' with an empty list → `[]' (not `false').  All other nil values (e.g.
  `draft', `has_*') render as `false' via the standard dispatch, which is
  correct for boolean fields."
  (let ((sorted (sort (copy-sequence alist)
                      (lambda (a b)
                        (string< (symbol-name (car a)) (symbol-name (car b)))))))
    (concat "---\n"
            (mapconcat
             (lambda (cell)
               (let* ((k   (car cell))
                      (v   (cdr cell))
                      ;; tags: [] when value is an empty list (nil).
                      ;; Boolean fields like draft/has_* must keep the standard
                      ;; nil → "false" path, so this special-case is key-scoped.
                      (str (if (and (eq k 'tags) (null v))
                               "[]"
                             (a3madkour-pub-essays--render-yaml-value v))))
                 (format "%s: %s" (symbol-name k) str)))
             sorted "\n")
            "\n---\n")))

;; Task 14: after-publish hook surface (consumed by D.2's auto-trigger).

(defvar a3madkour-pub-essays-after-publish-hook nil
  "Hook run after a successful essay publish.
Args: SOURCE-FILE (org), SLUG (string), BUNDLE-DIR (path).
D.2's multi-target export orchestrator installs here.")

;; Task 8: pipeline entry.

(cl-defun a3madkour-pub-essays/publish-essay-file (file run &key on-done)
  "Publish a single essay FILE to content/essays/<slug>/index.md.

Pipeline:
  1. resolve metadata (id / slug)
  2. pre-export rewrite via shared rewrite-to-tmp-file
  3. ox-hugo export
  4. scan post-export body for has_* shortcodes
  5. inject :scan-plist into raw fm; normalize via \\='essays dispatch arm
  6. asset-validate-and-copy (hero.svg etc.)
  7. render frontmatter + body; write if different
  8. record-publish
  9. run after-publish hook (D.2 multi-export attaches here; currently sync)

RUN is the a3-pub-async-run handle (used for log-step in later tasks).
ON-DONE is invoked with \\='ok on completion or \\='err if any step throws."
  (condition-case _err
      (progn
        (ignore run)
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
               ;; Scan the org source content for shortcode patterns.  ox-hugo
               ;; HTML-encodes `{{<' to `{{&lt;' in the exported body, so shortcodes
               ;; are only reliably detected in the unescaped org source.  Append
               ;; the post-export markdown body so that markdown-native patterns
               ;; (e.g. footnote references `[^N]') are also found.
               (src-content (with-temp-buffer
                              (insert-file-contents file)
                              (buffer-string)))
               (scan-pl    (a3madkour-pub-essays--scan-has-flags
                            (concat src-content "\n" (or body ""))))
               (raw-fm     (cons (cons :scan-plist scan-pl)
                                 (or (plist-get exported :frontmatter) '())))
               (normalized (a3madkour-pub-frontmatter/normalize 'essays raw-fm file)))
          (a3madkour-pub/asset-validate-and-copy file bundle-dir id)
          (a3madkour-pub-essays--copy-asset-dir id bundle-dir)
          (a3madkour-pub-essays--write-if-different
           out-path
           (concat (a3madkour-pub-essays--render-frontmatter normalized) (or body "")))
          (a3madkour-pub-history/record-publish id new-url 'live)
          (run-hook-with-args 'a3madkour-pub-essays-after-publish-hook
                              file slug bundle-dir))
        (when on-done (funcall on-done 'ok)))
    (error
     (when on-done (funcall on-done 'err)))))

(defun a3madkour-pub-essays/planned-steps (file)
  "Return rough step count for B.4 essays handler.
Returns 9 when FILE opts into D.2 multi-export, else 5."
  (condition-case _
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (if (re-search-forward "^#\\+multi_export:[ \t]*t$" nil t) 9 5))
    (error 5)))

(provide 'a3madkour-publish-essays)

;;; a3madkour-publish-essays.el ends here
