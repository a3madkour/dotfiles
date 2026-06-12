;;; a3madkour-publish-poetry.el --- Tier 8.2 works-poetry per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; Publishes a single org-mode poem into a synced-poetry page bundle
;; under `content/works/poetry/<slug>/'.
;;
;; Peer of `a3madkour-publish-essays.el'.  Both call into shared B.0
;; infra (rewrite-to-tmp-file, export-file, asset-validate-and-copy,
;; record-publish).  The essays handler is not modified by this slice.
;;
;; Authoring contract: see
;; `docs/superpowers/specs/2026-05-19-org-synced-poetry-export.md'.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-keywords)

(defcustom a3madkour-pub-poetry/section-dir-name "works/poetry"
  "Relative content directory under `content/' for poetry bundles.
The on-disk path becomes `content/<section-dir-name>/<slug>/index.md'.
Independent of the `#+HUGO_SECTION:' dispatch symbol (`works-poetry')."
  :type 'string
  :group 'a3madkour-pub)

(defcustom a3madkour-pub/poetry-dir
  (expand-file-name "~/org/notes/works/poetry/")
  "Root directory of the author's poem org files.  Source corpus for the
`works-poetry' dispatch.  Each poem lives at `<poetry-dir>/<slug>.org'
with assets under `<poetry-dir>/assets/<id>/'.  Default matches the
`a3madkour-pub/org-notes-dir' convention (`~/org/notes/`)."
  :type 'directory
  :group 'a3madkour-pub)

(defconst a3madkour-pub-poetry--audio-extensions
  '("mp3" "m4a" "ogg" "wav")
  "Allowed audio extensions for `#+AUDIO:' relative filenames.")

(defun a3madkour-pub-poetry--site-root ()
  "Resolve the site root from `a3madkour-pub/site-data-dir' (one level up from data/)."
  (file-name-as-directory
   (directory-file-name
    (file-name-directory
     (directory-file-name
      (file-name-as-directory a3madkour-pub/site-data-dir))))))

(defun a3madkour-pub-poetry--write-if-different (path content)
  "Write CONTENT to PATH only if it differs from existing on-disk content.
Returns t if a write happened, nil if no-op.  Mirrors the per-module
write helpers in essays/garden (B.4 follow-up #3 will collapse these)."
  (let ((existing (when (file-exists-p path)
                    (with-temp-buffer
                      (insert-file-contents path)
                      (buffer-string)))))
    (unless (string= existing content)
      (make-directory (file-name-directory path) t)
      (with-temp-file path (insert content))
      t)))

(defconst a3madkour-pub-poetry--date-re
  "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
  "Regex for bare YYYY-MM-DD date strings (emitted unquoted in YAML).")

(defun a3madkour-pub-poetry--render-yaml-value (v)
  "Render V as a YAML scalar/list value.  Mirrors the garden/essays helper:
strings quoted; YYYY-MM-DD dates unquoted; numbers as-is; t/nil → true/false;
lists of strings → JSON-style array.

NOTE: nil is also a list in Emacs Lisp — test null BEFORE listp."
  (cond
   ((null v)    "false")
   ((eq v t)    "true")
   ((and (stringp v)
         (string-match-p a3madkour-pub-poetry--date-re v))
    v)
   ((stringp v) (format "\"%s\"" v))
   ((numberp v) (format "%s" v))
   ((listp v)
    (format "[%s]"
            (mapconcat (lambda (s) (format "\"%s\"" s)) v ", ")))))

(defun a3madkour-pub-poetry--render-frontmatter (alist)
  "Render ALIST as YAML frontmatter (alphabetical key order; deterministic).
Returns a string with leading/trailing `---' delimiters.

`tags' with an empty list → `[]' (not `false') — matches the essays
renderer's key-aware special-case."
  (let ((sorted (sort (copy-sequence alist)
                      (lambda (a b)
                        (string< (symbol-name (car a)) (symbol-name (car b)))))))
    (concat "---\n"
            (mapconcat
             (lambda (cell)
               (let* ((k   (car cell))
                      (v   (cdr cell))
                      (str (if (and (eq k 'tags) (null v))
                               "[]"
                             (a3madkour-pub-poetry--render-yaml-value v))))
                 (format "%s: %s" (symbol-name k) str)))
             sorted "\n")
            "\n---\n")))

(cl-defun a3madkour-pub-poetry/publish-poetry-file (file run &key on-done)
  "Publish a single poem FILE to `content/works/poetry/<slug>/index.md'.

Pipeline:
  1. Resolve metadata (id / slug).
  2. Soft-warning sweep (multi_export + marker/audio mismatch); collect for result.
  3. Pre-export rewrite via shared rewrite-to-tmp-file.
  4. ox-hugo export → markdown body string.
  5. Read `#+AUDIO:'; classify; if relative, copy to bundle; inject `audio_url'.
  6. Normalize via `works-poetry' dispatch arm (injects lines, scrubs summary).
  7. Render frontmatter + body; write if different.
  8. record-publish.

RUN is the a3-pub-async-run handle (currently unused; reserved for parity
with peer handlers).  ON-DONE is invoked with `ok' on completion or `err' on
failure.

Returns a plist:
  (:status `ok'|`err'  :id ID  :slug SLUG  :url URL  :warnings (...))"
  (ignore run)
  (let ((warnings nil) (id nil) (slug nil) (new-url nil))
    (condition-case err
        (let* ((md         (a3madkour-pub/note-metadata file))
               (_          (setq id (plist-get md :id)
                                 slug (plist-get md :slug)
                                 new-url (a3madkour-pub/note-url file)))
               (site-root  (a3madkour-pub-poetry--site-root))
               (bundle-dir (expand-file-name
                            (format "content/%s/%s/"
                                    a3madkour-pub-poetry/section-dir-name slug)
                            site-root))
               (audio-raw  (with-temp-buffer
                             (insert-file-contents file)
                             (a3madkour-pub-keywords/extract "AUDIO")))
               (audio-class (a3madkour-pub-poetry--classify-audio audio-raw)))
          ;; Stage 2: multi_export warn-and-skip.
          (setq warnings
                (append warnings
                        (a3madkour-pub-poetry--maybe-warn-multi-export file)))
          ;; Stage 3: pre-export rewrite.
          (let* ((tmp-file (a3madkour-pub-rewrite/rewrite-to-tmp-file
                            file id "a3-pub-poetry"))
                 ;; Stage 4: ox-hugo export to markdown body.
                 (export-result (unwind-protect
                                    (a3madkour-pub-export/export-file tmp-file)
                                  (when (file-exists-p tmp-file)
                                    (delete-file tmp-file))))
                 (raw-fm    (plist-get export-result :frontmatter))
                 ;; Case C: collapse `\\[mm:ss]' → `\[mm:ss]' before downstream use.
                 (body      (a3madkour-pub-poetry--collapse-escaped-markers
                             (or (plist-get export-result :body) ""))))
            ;; Stage 5a: inject audio_url + line-count into raw-fm.
            (when audio-class
              (setf (alist-get 'audio_url raw-fm) (plist-get audio-class :value)))
            (setf (alist-get :body-line-count raw-fm)
                  (a3madkour-pub-poetry--count-poem-lines body))
            ;; Stage 5b: soft warnings re. marker/audio mismatch.
            (setq warnings
                  (append warnings
                          (a3madkour-pub-poetry--collect-warnings body audio-raw)))
            ;; Stage 6: normalize.
            (let* ((normalized (a3madkour-pub-frontmatter/normalize
                                'works-poetry raw-fm file))
                   ;; Stage 7: render + write.
                   (rendered (concat
                              (a3madkour-pub-poetry--render-frontmatter normalized)
                              body))
                   (index-md (expand-file-name "index.md" bundle-dir)))
              (make-directory bundle-dir t)
              (a3madkour-pub-poetry--write-if-different index-md rendered)
              ;; Stage 7b: shared asset pipeline (body-link assets, if any).
              ;; Runs BEFORE the audio copy because asset-validate-and-copy
              ;; cleanup-stales any bundle file not in its referenced-basenames
              ;; set; we don't want it to delete the audio we just copied.
              (a3madkour-pub/asset-validate-and-copy file bundle-dir id)
              ;; Stage 7c: audio asset copy (relative form only).
              ;; Deferred to AFTER asset-validate-and-copy's cleanup-stale pass
              ;; so the audio file isn't swept as an unreferenced extra.
              (when (and audio-class (eq (plist-get audio-class :kind) :file))
                (a3madkour-pub-poetry--copy-audio-asset
                 id (plist-get audio-class :value) bundle-dir))
              ;; Stage 8: record-publish.
              (a3madkour-pub-history/record-publish id new-url 'live)
              (when on-done (funcall on-done 'ok))
              (list :status 'ok :id id :slug slug :url new-url :warnings warnings))))
      (error
       (when on-done (funcall on-done 'err))
       (list :status 'err
             :id id :slug slug :url new-url
             :warnings warnings
             :error (error-message-string err))))))

(defconst a3madkour-pub-poetry--required-keys
  '(title date lastmod draft lines)
  "5 required frontmatter keys per check_works_fixtures.py poetry contract.")

(defconst a3madkour-pub-poetry--optional-keys
  '(tags collection set_to_music summary audio_url source_stream
         tile_size featured hero)
  "9 optional frontmatter keys per spec §Authoring + check_works_fixtures.py.")

(defun a3madkour-pub-poetry--allowed-keys ()
  "All keys allowed in the emitted poetry frontmatter."
  (append a3madkour-pub-poetry--required-keys
          a3madkour-pub-poetry--optional-keys))

(defun a3madkour-pub-frontmatter--normalize-works-poetry (raw-alist source-file)
  "Tier 8.2: works-poetry frontmatter normalizer.

Pipeline:
  1. Filter RAW-ALIST to only allowed keys (drops ox-hugo noise + essay-only keys).
  2. Coerce draft to bool (default nil).
  3. Default lines=0 (Task 4 wires real auto-counting via :body-line-count
     injected into raw-alist by the handler).
  4. Default summary=\"\" (linter requires the key; marker scrub lands in Task 7).
  5. audio_url passed through if present (Tasks 5-6 wire the #+AUDIO: keyword
     reader into raw-alist injection).

SOURCE-FILE is the original .org path; required by the lastmod cascade
(below) so this normalizer cannot run safely with nil SOURCE-FILE unless
`lastmod' is already injected.  Unit tests that bypass the cascade must
supply an explicit `(lastmod . \"YYYY-MM-DD\")' cell."
  (let* ((allowed (a3madkour-pub-poetry--allowed-keys))
         (out (cl-remove-if-not
               (lambda (cell) (memq (car cell) allowed))
               (copy-alist raw-alist))))
    ;; Default draft → nil (false)
    (setf (alist-get 'draft out) (and (alist-get 'draft out) t))
    ;; lines: prefer caller-injected :body-line-count, else explicit lines,
    ;; else 0 (caught by linter when handler forgets to inject).
    (let ((injected (alist-get :body-line-count raw-alist)))
      (when injected
        (setf (alist-get 'lines out) injected)))
    (unless (alist-get 'lines out)
      (setf (alist-get 'lines out) 0))
    (setq out (assq-delete-all :body-line-count out))
    ;; summary: read from #+HUGO_SUMMARY: (ox-hugo has no built-in slot for it,
    ;; mirrors essays normalizer), scrub timing markers (per spec §6), default ""
    ;; if missing.
    (let* ((existing (alist-get 'summary out))
           (kw-summary (when source-file
                         (a3madkour-pub-frontmatter--read-org-keyword
                          source-file "HUGO_SUMMARY")))
           (s (or kw-summary existing)))
      (setf (alist-get 'summary out)
            (or (a3madkour-pub-poetry--scrub-markers s) "")))
    ;; lastmod cascade: drawer → keyword → git → fs → today (mirrors essays).
    ;; Skip when source-file is nil AND lastmod was already supplied (unit-test mode).
    (when (or source-file (not (alist-get 'lastmod out)))
      (let* ((drawer-lm (alist-get 'last_modified raw-alist))
             (kw-lm     (alist-get 'lastmod raw-alist))
             (kw-trim   (when (and (stringp kw-lm) (>= (length kw-lm) 10))
                          (substring kw-lm 0 10))))
        (setq out (assq-delete-all 'lastmod out))
        (setq out (assq-delete-all 'last_modified out))
        (setf (alist-get 'lastmod out)
              (a3madkour-pub-frontmatter/last-modified-cascade
               source-file
               :drawer  drawer-lm
               :keyword kw-trim))))
    out))

(defun a3madkour-pub-poetry--count-poem-lines (body)
  "Return the count of non-blank poem lines in markdown BODY.

Rules:
  - Stanza-break blank lines excluded.
  - Lines with only `[mm:ss]' markers still count.
  - A leading H2 (line matching `## ...') is excluded.

Used by the handler to inject `:body-line-count' into the raw frontmatter
alist; the normalizer reads it as `lines:'."
  (let* ((lines (split-string (or body "") "\n"))
         (stripped (if (and lines
                            (string-match-p "\\`##[ \t]" (car lines)))
                       (cdr lines)
                     lines)))
    (cl-count-if (lambda (l) (not (string-blank-p l))) stripped)))

(defun a3madkour-pub-poetry--classify-audio (raw)
  "Classify the value of an `#+AUDIO:' keyword.

Return nil for nil/empty input.  Otherwise return a plist:
  (:kind :url  :value <trimmed-url>)   for `http(s)://...'
  (:kind :file :value <trimmed-name>)  for bare filenames"
  (when (and raw (stringp raw))
    (let ((v (string-trim raw)))
      (cond
       ((string-empty-p v) nil)
       ((string-match-p "\\`https?://" v) (list :kind :url :value v))
       (t                                 (list :kind :file :value v))))))

(defun a3madkour-pub-poetry--copy-audio-asset (id filename bundle-dest-dir)
  "Copy `<poetry-dir>/assets/ID/FILENAME' → `BUNDLE-DEST-DIR/FILENAME'.

Validates:
  - Extension is in `a3madkour-pub-poetry--audio-extensions'.
  - Source file exists.
  - Source file is non-zero bytes.

Signals `user-error' on any validation failure.  Returns FILENAME on
success.  Creates BUNDLE-DEST-DIR if missing."
  (let* ((ext (file-name-extension filename))
         (src (expand-file-name (format "assets/%s/%s" id filename)
                                a3madkour-pub/poetry-dir))
         (dest (expand-file-name filename bundle-dest-dir)))
    (unless (and ext (member (downcase ext) a3madkour-pub-poetry--audio-extensions))
      (user-error "a3madkour-pub-poetry: #+AUDIO: extension %S not in allowlist %S"
                  ext a3madkour-pub-poetry--audio-extensions))
    (unless (file-exists-p src)
      (user-error "a3madkour-pub-poetry: #+AUDIO: source file not found: %s" src))
    (let ((size (nth 7 (file-attributes src))))
      (unless (and size (> size 0))
        (user-error "a3madkour-pub-poetry: #+AUDIO: source file is empty: %s" src)))
    (make-directory bundle-dest-dir t)
    (copy-file src dest t)
    filename))

(defun a3madkour-pub-poetry--collapse-escaped-markers (md)
  "Collapse double-backslash escape sequences ox-hugo emits.

Task 0 recon outcome: org-source `\\[mm:ss]' (single backslash) is emitted
by ox-hugo as markdown `\\\\[mm:ss]' (double backslash).  The runtime
parser (layouts/partials/works/synced-text-parser.html:21) matches only
the single-backslash form; the doubled form leaves a stray backslash in
rendered output.  This helper restores the single-backslash shape that
the parser + shipped fixture expect."
  (replace-regexp-in-string
   "\\\\\\\\\\(\\[[0-9]\\{1,2\\}:[0-9]\\{2\\}\\(?:\\.[0-9]\\{1,2\\}\\)?\\]\\)"
   "\\\\\\1"
   md t))

(defconst a3madkour-pub-poetry--marker-regexp
  "\\\\?\\[[0-9]\\{1,2\\}:[0-9]\\{2\\}\\(?:\\.[0-9]\\{1,2\\}\\)?\\]"
  "Matches `[mm:ss]', `[mm:ss.f]', `\\[mm:ss]', `\\[mm:ss.f]'.
Used to scrub timing markers from `summary:' values.")

(defun a3madkour-pub-poetry--scrub-markers (s)
  "Return S with all `[mm:ss]'-shaped markers removed.
Returns nil for nil input."
  (when s
    (replace-regexp-in-string a3madkour-pub-poetry--marker-regexp "" s t t)))

(defun a3madkour-pub-poetry--body-has-markers-p (body)
  "Non-nil if BODY contains at least one `[mm:ss]' marker (unescaped).
Treats `\\[mm:ss]' as escaped (literal) and excludes it."
  (and body
       (let ((case-fold-search nil))
         (string-match-p
          ;; Negative lookbehind isn't supported in elisp; emulate by requiring
          ;; the char before [mm:ss] to be either start-of-line, whitespace, or
          ;; nothing (and not a backslash).  Use a non-capturing leading group.
          "\\(?:^\\|[^\\\\]\\)\\[[0-9]\\{1,2\\}:[0-9]\\{2\\}\\(?:\\.[0-9]\\{1,2\\}\\)?\\]"
          body))))

(defun a3madkour-pub-poetry--collect-warnings (body audio-raw)
  "Return the list of soft-warning strings for BODY + AUDIO-RAW.
AUDIO-RAW is the raw `#+AUDIO:' keyword value (string or nil)."
  (let ((warnings nil)
        (has-markers (a3madkour-pub-poetry--body-has-markers-p body))
        (has-audio   (and audio-raw (not (string-blank-p audio-raw)))))
    (cond
     ((and has-audio (not has-markers))
      (push "#+AUDIO: declared but the poem isn't timed — the synced runtime won't engage."
            warnings))
     ((and has-markers (not has-audio))
      (push "Body has [mm:ss] markers but no #+AUDIO: — the runtime will use animation-driven sync."
            warnings)))
    (nreverse warnings)))

(defun a3madkour-pub-poetry--maybe-warn-multi-export (file)
  "Return a warning list iff FILE has `#+multi_export: t' (poetry doesn't support it).
Returns nil otherwise.  D.2 dispatch is never invoked on poetry."
  (with-temp-buffer
    (insert-file-contents file)
    (when (a3madkour-pub-keywords/boolean-p
           (a3madkour-pub-keywords/extract "multi_export"))
      (list "#+multi_export: t set on a poem — D.2 PDF/Word target shape doesn't exist for synced poetry; ignoring."))))

(provide 'a3madkour-publish-poetry)

;;; a3madkour-publish-poetry.el ends here
