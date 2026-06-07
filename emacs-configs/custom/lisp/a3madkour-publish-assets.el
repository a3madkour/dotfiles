;;; a3madkour-publish-assets.el --- Asset link handling for org-mode publish -*- lexical-binding: t; -*-

;;; Commentary:

;; Implements parent-spec §7 (asset handling) for A.1.c.  Replaces the
;; `:pending-asset' stub shipped in A.1.b's `rewrite-link' dispatcher.
;;
;; Public API:
;;   - `a3madkour-pub/rewrite-asset-link'      ; called by rewrite-link
;;   - `a3madkour-pub/asset-validate-and-copy' ; called by B's per-section publisher

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-rewrite)         ; for --html-escape
(require 'a3madkour-publish-async)           ; for run-process + with-a3-pub-async-sync

(defgroup a3madkour-pub-assets nil
  "Asset link handling for the a3madkour-publish library."
  :group 'a3madkour-pub)

(defcustom a3madkour-pub-canonical-asset-root
  "~/org/notes/assets"
  "Root directory for canonical assets.  Two sub-folders below:
  page/<note-slug>/   — per-note assets (copied into the bundle)
  shared/             — assets referenced by many notes (one copy site-wide
                        in static/notes-shared/)

See parent spec §7."
  :type 'directory
  :group 'a3madkour-pub-assets)

(defcustom a3madkour-pub-asset-image-extensions
  '("png" "jpg" "jpeg" "gif" "svg" "webp" "avif")
  "Extensions classified as images.

Image-classified assets render as `<img src alt>'; other extensions
render as `<a href>text</a>'.  Unknown extensions fall through to the
link form (safest default)."
  :type '(repeat string)
  :group 'a3madkour-pub-assets)

(defcustom a3madkour-pub-asset-auto-remediate t
  "When non-nil (default), out-of-canonical-root assets are git-mv'd
into `<root>/page/<source-slug>/' and the .org source link is rewritten.
When nil, out-of-root assets emit `(missing asset: X)' + WARN.

Per parent spec §7 §Auto-remediation."
  :type 'boolean
  :group 'a3madkour-pub-assets)

(defcustom a3madkour-pub-notes-shared-static-dir
  nil
  "Absolute path to the site repo's `static/notes-shared/' directory.

Set explicitly by the publish driver (must be non-nil at publish time).
Shared assets are copied here once site-wide."
  :type '(choice (const :tag "Unset" nil) directory)
  :group 'a3madkour-pub-assets)

(defun a3madkour-pub--essay-slug-from-source-file (source-file)
  "Return the published slug for SOURCE-FILE, or nil.
Thin wrapper around `a3madkour-pub/note-metadata' that pulls `:slug'.
Used by `--asset-resolve-path' to synthesize the per-essay namespace
key on the essays-aware branch."
  (when source-file
    (plist-get (a3madkour-pub/note-metadata source-file) :slug)))

(defun a3madkour-pub--asset-resolve-path (path source-file)
  "Normalize PATH + classify against the canonical asset root.

PATH may be relative (resolved against SOURCE-FILE's directory), absolute,
or tilde-expanded.  SOURCE-FILE may be nil — in which case relative paths
resolve against `default-directory'.

When SOURCE-FILE is under `a3madkour-pub/essays-dir' AND carries a top-
level :ID:, an essays-aware lookup runs first: PATH is looked up under
`essays-dir/assets/<source-id>/'.  If found, classification is `:page'
with the per-essay slug as the namespace key.  This matches the
convention enforced by `a3madkour-pub-essays--copy-asset-dir'.

Returns a plist:
  (:kind page|shared|out-of-root|missing
   :abs-path \"/canonical/absolute/path\"
   :rel-path \"page/<slug>/<filename>\" or \"shared/<filename>\" or nil)

`:kind missing' takes priority over location-based classification — a
non-existent file at a canonical-looking path still reports missing."
  (when source-file
    (setq source-file (expand-file-name source-file)))
  (let* ((source-dir (or (and source-file (file-name-directory source-file))
                         default-directory))
         (essays-dir (and (boundp 'a3madkour-pub/essays-dir)
                          a3madkour-pub/essays-dir))
         (essays-page-path
          (and source-file essays-dir
               (string-prefix-p (expand-file-name essays-dir) source-file)
               (let* ((id (a3madkour-pub--file-top-level-id source-file))
                      (slug (and id
                                 (a3madkour-pub--essay-slug-from-source-file source-file)))
                      (page-dir (and slug
                                     (expand-file-name
                                      (format "assets/%s/" id) essays-dir)))
                      (candidate (and page-dir
                                      (expand-file-name
                                       (file-name-nondirectory path) page-dir))))
                 (and candidate (file-exists-p candidate) candidate))))
         (abs (or essays-page-path
                  (expand-file-name path source-dir)))
         (root (expand-file-name a3madkour-pub-canonical-asset-root))
         (root-page (file-name-as-directory (expand-file-name "page" root)))
         (root-shared (file-name-as-directory (expand-file-name "shared" root)))
         (exists (file-exists-p abs)))
    (cond
     ((not exists)
      (list :kind 'missing :abs-path abs :rel-path nil))
     (essays-page-path
      (list :kind 'page :abs-path abs
            :rel-path (format "page/%s/%s"
                              (a3madkour-pub--essay-slug-from-source-file source-file)
                              (file-name-nondirectory abs))))
     ((string-prefix-p root-page abs)
      (list :kind 'page :abs-path abs
            :rel-path (substring abs (length root))))
     ((string-prefix-p root-shared abs)
      (list :kind 'shared :abs-path abs
            :rel-path (substring abs (length root))))
     (t
      (list :kind 'out-of-root :abs-path abs :rel-path nil)))))

(defun a3madkour-pub--asset-cross-namespace-p (resolved source-slug)
  "Return non-nil iff RESOLVED's page-namespace conflicts with SOURCE-SLUG.

Only fires when `:kind' is `page' AND the rel-path's page-subdir slug
differs from SOURCE-SLUG.  `shared' and `out-of-root' kinds never trigger
this check (shared has no slug component; out-of-root is a separate concern
handled by auto-remediation)."
  (when (eq (plist-get resolved :kind) 'page)
    (let* ((rel (plist-get resolved :rel-path))      ; \"page/<slug>/<filename>\"
           (parts (split-string rel "/" t))
           ;; parts = (\"page\" \"<slug>\" \"<filename>\")
           (path-slug (cadr parts)))
      (not (equal path-slug source-slug)))))

(defun a3madkour-pub--asset-bundle-dest (resolved bundle-dir)
  "Return the on-disk destination path for RESOLVED asset.

For `:kind page', dest = BUNDLE-DIR/<filename>.
For `:kind shared', dest = `a3madkour-pub-notes-shared-static-dir'/<filename>
(the variable MUST be set; error otherwise — caller's publish driver should
set it at publish start).

Other kinds (`out-of-root', `missing') are not valid input — should be
resolved by the caller before calling this function."
  (let ((filename (file-name-nondirectory (plist-get resolved :abs-path)))
        (kind (plist-get resolved :kind)))
    (cond
     ((eq kind 'page)
      (expand-file-name filename bundle-dir))
     ((eq kind 'shared)
      (unless a3madkour-pub-notes-shared-static-dir
        (error "asset-bundle-dest: shared asset but notes-shared-static-dir unset"))
      (expand-file-name filename a3madkour-pub-notes-shared-static-dir))
     (t
      (error "asset-bundle-dest: unsupported kind %S" kind)))))

(defun a3madkour-pub--asset-kind-from-ext (path)
  "Return 'image if PATH's extension is in `a3madkour-pub-asset-image-extensions';
'other otherwise.  Unknown extensions fall through to 'other (link form,
safest default)."
  (let ((ext (downcase (or (file-name-extension path) ""))))
    (if (member ext a3madkour-pub-asset-image-extensions)
        'image
      'other)))

(defun a3madkour-pub--asset-emit-html (src display kind)
  "Format HTML for an asset link.

SRC is the rewritten link path (relative filename for page; `/notes-shared/X'
for shared).  DISPLAY is the link text (alt for images, body for others).
KIND is `'image' or `'other'.

All interpolated values pass through `a3madkour-pub--html-escape'."
  (if (eq kind 'image)
      (format "<img src=\"%s\" alt=\"%s\" />"
              (a3madkour-pub--html-escape src)
              (a3madkour-pub--html-escape display))
    (format "<a href=\"%s\">%s</a>"
            (a3madkour-pub--html-escape src)
            (a3madkour-pub--html-escape display))))

(defun a3madkour-pub--asset-emit-inert (filename)
  "Format the inert `(missing asset: FILENAME)' marker.
FILENAME passes through `a3madkour-pub--html-escape' to handle weird names."
  (format "(missing asset: %s)" (a3madkour-pub--html-escape filename)))

(defun a3madkour-pub--extract-asset-refs (org-file)
  "Return a list of (PATH . TEXT) pairs for every asset-shaped link in ORG-FILE.

Walks all `[[<path>][<text>]]' and `[[<path>]]' forms; filters via
`a3madkour-pub--asset-shaped-link-p' (no URL scheme; extension != org).

The org `file:' link type is normalized away before the shape check so
`[[file:diagram-1.svg]]' and `[[diagram-1.svg]]' are treated as the
same asset — without this normalization `[[file:…]]' forms used to
fall through B.4's asset pipeline entirely (link-scheme \"file\" tripped
the no-scheme filter), surfacing as publish-time errors when the
referenced file wasn't somewhere ox-hugo expected."
  (let ((refs nil))
    (with-temp-buffer
      (insert-file-contents org-file)
      (goto-char (point-min))
      (while (re-search-forward
              "\\[\\[\\([^]]+\\)\\(?:\\]\\[\\([^]]+\\)\\)?\\]\\]"
              nil t)
        (let* ((raw-path (match-string 1))
               (path (replace-regexp-in-string "\\`file:" "" raw-path))
               (text (or (match-string 2) path)))
          (when (a3madkour-pub--asset-shaped-link-p path)
            (push (cons path text) refs)))))
    (nreverse refs)))

(defun a3madkour-pub--asset-content-hash (file)
  "Return the first 6 hex chars of SHA-1 of FILE's contents.
Used for filename-collision suffixing in auto-remediation."
  (substring (secure-hash 'sha1
                          (with-temp-buffer
                            (set-buffer-multibyte nil)
                            (insert-file-contents-literally file)
                            (buffer-string)))
             0 6))

(defun a3madkour-pub--asset-files-byte-equal-p (a b)
  "Return non-nil iff files A and B have identical byte contents."
  (and (file-exists-p a) (file-exists-p b)
       (= (file-attribute-size (file-attributes a))
          (file-attribute-size (file-attributes b)))
       (string=
        (with-temp-buffer
          (set-buffer-multibyte nil)
          (insert-file-contents-literally a)
          (buffer-string))
        (with-temp-buffer
          (set-buffer-multibyte nil)
          (insert-file-contents-literally b)
          (buffer-string)))))

(defun a3madkour-pub--asset-remediate-dest (src dest-slug)
  "Compute the canonical destination for SRC under page/DEST-SLUG/.

Filename-collision handling:
  - If dest doesn't exist                     → dest unchanged.
  - If dest exists + byte-equal to src        → dest unchanged (no-op move).
  - If dest exists + content differs          → append -<6hex> SHA-1 of src.

Returns the absolute destination path (no I/O performed)."
  (let* ((root (expand-file-name a3madkour-pub-canonical-asset-root))
         (dest-dir (expand-file-name (format "page/%s" dest-slug) root))
         (filename (file-name-nondirectory src))
         (dest (expand-file-name filename dest-dir)))
    (cond
     ((not (file-exists-p dest))
      dest)
     ((a3madkour-pub--asset-files-byte-equal-p src dest)
      dest)
     (t
      (let* ((base (file-name-base filename))
             (ext (file-name-extension filename))
             (hash (a3madkour-pub--asset-content-hash src)))
        (expand-file-name
         (if ext
             (format "%s-%s.%s" base hash ext)
           (format "%s-%s" base hash))
         dest-dir))))))

(defun a3madkour-pub--asset-do-move-async (src dest dry-run on-done)
  "Async variant of `a3madkour-pub--asset-do-move'.

Calls ON-DONE with the result plist when the move (or git mv → fallback)
completes.

Result plist shapes:
  (:method dry-run :info \"would move: SRC -> DEST\")  ;; when dry-run
  (:method git-mv  :info \"...\")                       ;; when git mv succeeds
  (:method mv      :info \"...\")                       ;; when not git, OR git mv failed → rename-file
  (:method failed  :rc <rc>)                            ;; if rename-file also raised

Behavior change vs. the prior sync function: a non-zero git-mv exit no
longer signals an error.  Instead the async path falls through to
`rename-file' (mirroring the not-git branch), and only routes to
:method 'failed when that secondary attempt also raises.  Caller is
responsible for creating DEST's directory if needed."
  (when (not dry-run)
    (make-directory (file-name-directory dest) t))
  (cond
   (dry-run
    (funcall on-done (list :method 'dry-run
                           :info (format "would move: %s -> %s" src dest))))
   ((eq (vc-backend src) 'Git)
    (a3-pub-async/run-process
     "git" (list "mv" src dest)
     :name "asset-git-mv"
     :on-done
     (lambda (rc _tail)
       (if (zerop rc)
           (funcall on-done (list :method 'git-mv
                                  :info (format "moved (git mv): %s -> %s" src dest)))
         (condition-case _
             (progn (rename-file src dest)
                    (funcall on-done (list :method 'mv
                                           :info (format "moved (fallback): %s -> %s" src dest))))
           (error (funcall on-done (list :method 'failed :rc rc))))))))
   (t (rename-file src dest)
      (funcall on-done (list :method 'mv
                             :info (format "moved: %s -> %s" src dest))))))

(defun a3madkour-pub--asset-do-move (src dest dry-run)
  "Move SRC to DEST.  Uses `git mv' if SRC is git-tracked, plain rename otherwise.

When DRY-RUN is non-nil, no I/O performed; returns
  (:method dry-run :info \"would move: SRC -> DEST\")

When DRY-RUN is nil, performs the move and returns one of:
  (:method git-mv :info \"moved (git mv): SRC -> DEST\")
  (:method mv     :info \"moved: SRC -> DEST\")
  (:method failed :rc <rc>)                ;; git mv non-zero AND rename-file raised

Sync wrapper around `a3madkour-pub--asset-do-move-async'.  Caller is
responsible for creating DEST's directory if needed."
  (let (result)
    (with-a3-pub-async-sync
     (a3madkour-pub--asset-do-move-async
      src dest dry-run (lambda (r) (setq result r))))
    result))

(defun a3madkour-pub--asset-rewrite-source-link (org-file old-link new-link)
  "In ORG-FILE, replace every occurrence of OLD-LINK with NEW-LINK.

OLD-LINK and NEW-LINK are the full `[[...]]' bracket forms.  Match is
literal (case-sensitive, no regex interpretation); replacement is literal.
File is saved to disk after rewriting.

This is the visible side effect of auto-remediation — author sees both the
asset move and the link rewrite in `git status' after the publish."
  (with-temp-buffer
    (insert-file-contents org-file)
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (while (search-forward old-link nil t)
        (replace-match new-link t t)))
    (write-region (point-min) (point-max) org-file nil 'silent)))

(defun a3madkour-pub/rewrite-asset-link (path text source-note-id &optional dry-run source-file)
  "Resolve an asset link to HTML + path metadata.

PATH is the link path (relative `./assets/...', absolute `~/...' or `/...').
TEXT is the link display text (may equal PATH for [[no-text]] form).
SOURCE-NOTE-ID is the source note's UUID — used to derive source slug
for cross-namespace validation + auto-remediation destination.
DRY-RUN, when non-nil, prevents auto-remediation I/O (Task 15).
SOURCE-FILE, when supplied, is the source note's absolute file path —
used directly instead of `--id-to-file' so essays under directories
outside `org-roam-directory' (and therefore absent from the org-roam DB)
still resolve via the essays-aware branch of `--asset-resolve-path'.
When nil, falls back to `--id-to-file' (legacy callers).

Returns one of:
  (:html STRING :resolved-path REL :source-path SRC :kind image|other
   :warnings (WARN ...))
  (:inert \"(missing asset: NAME)\" :warnings (WARN ...))
  ;; DRY-RUN out-of-root case: neither :html nor :inert; just metadata
  ;; + a single \"would move: SRC -> DEST\" warning.  Used by
  ;; asset-validate-and-copy to preview without side effects.
  (:resolved-path nil :source-path ABS :kind image|other
   :warnings (WOULD-MOVE-STRING))

See parent spec §7 + design doc §5."
  (let* ((source-file (or source-file
                          (a3madkour-pub--id-to-file source-note-id)))
         (source-slug (and source-note-id
                           (a3madkour-pub/note-slug source-note-id)))
         (resolved (a3madkour-pub--asset-resolve-path path source-file))
         (kind (plist-get resolved :kind))
         (abs (plist-get resolved :abs-path))
         (filename (file-name-nondirectory abs))
         (display (if (and text (not (equal text path))) text filename))
         (html-kind (a3madkour-pub--asset-kind-from-ext filename)))
    (cond
     ;; Missing file → inert + WARN.
     ((eq kind 'missing)
      (list :inert (a3madkour-pub--asset-emit-inert filename)
            :warnings (list (format "asset source file does not exist: %s" abs))))
     ;; Cross-namespace use → inert + WARN.
     ((and (eq kind 'page)
           source-slug
           (a3madkour-pub--asset-cross-namespace-p resolved source-slug))
      (list :inert (a3madkour-pub--asset-emit-inert filename)
            :warnings (list
                       (format "cross-namespace asset: %s; move to assets/shared/ to share"
                               (plist-get resolved :rel-path)))))
     ;; Out-of-root: auto-remediation (Task 15).
     ((eq kind 'out-of-root)
      (cond
       ((not a3madkour-pub-asset-auto-remediate)
        (list :inert (a3madkour-pub--asset-emit-inert filename)
              :warnings (list
                         (format "out-of-canonical-root: %s; set auto-remediate or move manually"
                                 abs))))
       (t
        (let* ((dest (a3madkour-pub--asset-remediate-dest abs source-slug))
               (move-result (a3madkour-pub--asset-do-move abs dest dry-run)))
          (cond
           (dry-run
            (list :resolved-path nil :source-path abs :kind html-kind
                  :warnings (list (plist-get move-result :info))))
           (t
            ;; Rewrite the .org source link to the new canonical relative form:
            (let* ((dest-rel (concat "./" (file-relative-name
                                            dest
                                            (file-name-directory (or source-file ""))))))
              (when source-file
                (a3madkour-pub--asset-rewrite-source-link
                 source-file
                 (format "[[%s]]" path)
                 (format "[[%s]]" dest-rel))
                ;; Also handle [[path][text]] form:
                (when (and text (not (equal text path)))
                  (a3madkour-pub--asset-rewrite-source-link
                   source-file
                   (format "[[%s][%s]]" path text)
                   (format "[[%s][%s]]" dest-rel text))))
              ;; Re-dispatch as page-kind with the new dest:
              (let* ((new-filename (file-name-nondirectory dest))
                     (src new-filename))
                (list :html (a3madkour-pub--asset-emit-html src display html-kind)
                      :resolved-path src
                      :source-path dest
                      :kind html-kind
                      :warnings (list (plist-get move-result :info)))))))))))
     ;; page + same namespace → emit page-relative HTML.

     ((eq kind 'page)
      (let ((src filename))
        (list :html (a3madkour-pub--asset-emit-html src display html-kind)
              :resolved-path src
              :source-path abs
              :kind html-kind
              :warnings nil)))
     ;; shared → emit /notes-shared/ HTML.
     ((eq kind 'shared)
      (let ((src (format "/notes-shared/%s" filename)))
        (list :html (a3madkour-pub--asset-emit-html src display html-kind)
              :resolved-path src
              :source-path abs
              :kind html-kind
              :warnings nil))))))

(defun a3madkour-pub--asset-cleanup-stale (bundle-dir referenced-files)
  "Remove files in BUNDLE-DIR not in REFERENCED-FILES.

Preserves:
  - index.md, _index.md, index.*.md (Hugo bundle conventions)
  - Files starting with `.` (dotfiles like .publish-state, .DS_Store)
  - Directories (cleanup is shallow; nested subdirs untouched)

Returns the list of removed absolute paths."
  (let ((removed nil))
    (when (file-directory-p bundle-dir)
      (dolist (f (directory-files bundle-dir t "^[^.]"))   ; skip dotfiles
        (let ((basename (file-name-nondirectory f)))
          (when (and (file-regular-p f)
                     (not (equal basename "index.md"))
                     (not (equal basename "_index.md"))
                     (not (string-match "\\`index\\..*\\.md\\'" basename))
                     (not (member basename referenced-files)))
            (delete-file f)
            (push f removed)))))
    (nreverse removed)))

(defun a3madkour-pub--asset-normalize-link-path (path org-file)
  "Normalize PATH to an absolute path for asset resolution.

Handles the canonical `./assets/<rest>' convention: when PATH starts with
`./assets/' the prefix is treated as an alias for
`a3madkour-pub-canonical-asset-root', and the remainder is resolved against
that root directly (returning an absolute path).

Any other relative path is resolved against ORG-FILE's directory via
`expand-file-name'.  Absolute and tilde-prefixed paths pass through
`expand-file-name' unchanged."
  (let ((assets-prefix "./assets/"))
    (if (string-prefix-p assets-prefix path)
        ;; Strip the ./assets/ alias and resolve against the canonical root:
        (expand-file-name (substring path (length assets-prefix))
                          (expand-file-name a3madkour-pub-canonical-asset-root))
      ;; All other paths: resolve against the org file's directory.
      (expand-file-name path
                        (file-name-directory (expand-file-name org-file))))))

(defun a3madkour-pub/asset-validate-and-copy
    (org-file bundle-dest-dir &optional source-note-id dry-run)
  "Walk ORG-FILE for asset links; copy referenced assets; remove stale per-page assets.

For each `[[<path>][text]]' that is asset-shaped:
  - Resolve via `rewrite-asset-link' (which handles auto-remediation).
  - For `:kind page' results, copy abs-path → BUNDLE-DEST-DIR/<filename>.
  - For `:kind shared' results (resolved-path starts with `/notes-shared/'),
    copy abs-path → `a3madkour-pub-notes-shared-static-dir'/<filename>.

After all copies, remove stale per-page files (cleanup-stale).

Returns:
  (:copied   (DEST-PATH ...)
   :removed  (DEST-PATH ...)
   :warnings (WARN ...)
   :errors   (ERR ...))

SOURCE-NOTE-ID is the org-roam :ID: (UUID) of the source note containing
the asset references.  When provided, the per-asset cross-namespace check
runs against the source's slug.  When nil, the cross-namespace check is
suppressed (no source slug to compare against).  Sub-
project B's per-section publishers thread their `:id' here; see
`a3madkour-pub-essays/publish-essay-file' for the canonical caller.

DRY-RUN, when non-nil, propagates to rewrite-asset-link's auto-remediation
and suppresses file I/O for copies + cleanup."
  (let ((refs (a3madkour-pub--extract-asset-refs org-file))
        (copied nil)
        (warnings nil)
        (errors nil)
        (referenced-basenames nil))
    (dolist (ref refs)
      (let* ((path (car ref))
             ;; Normalize the link path: ./assets/<rest> → absolute under
             ;; canonical-asset-root; other relative paths → absolute via
             ;; org-file's directory.
             (abs-path (a3madkour-pub--asset-normalize-link-path path org-file))
             (text (cdr ref))
             (rewrite-result (a3madkour-pub/rewrite-asset-link
                              abs-path text source-note-id dry-run org-file))
             (src (plist-get rewrite-result :source-path))
             (resolved (plist-get rewrite-result :resolved-path)))
        ;; Always merge WARNs:
        (setq warnings (append warnings (plist-get rewrite-result :warnings)))
        ;; If :html (not :inert) AND not dry-run, perform the copy:
        (when (and (plist-get rewrite-result :html) (not dry-run) src)
          (let* ((basename (file-name-nondirectory src))
                 (dest (if (and resolved (string-prefix-p "/notes-shared/" resolved))
                           (expand-file-name basename
                                              a3madkour-pub-notes-shared-static-dir)
                         (expand-file-name basename bundle-dest-dir))))
            (make-directory (file-name-directory dest) t)
            (condition-case err
                (progn
                  (copy-file src dest t)                ; t = ok-if-already-exists
                  (push dest copied)
                  ;; Track for cleanup only when destination is the bundle:
                  (when (string-prefix-p (file-name-as-directory bundle-dest-dir) dest)
                    (push basename referenced-basenames)))
              (error
               (push (format "copy failed: %s -> %s (%S)" src dest err) errors)))))))
    (let ((removed (and (not dry-run)
                        (a3madkour-pub--asset-cleanup-stale
                         bundle-dest-dir referenced-basenames))))
      (list :copied (nreverse copied)
            :removed removed
            :warnings warnings
            :errors (nreverse errors)))))

(defun a3madkour-pub-assets/list-referenced-files (source-file)
  "Return the absolute paths of every existing asset referenced by SOURCE-FILE.

Walks `[[<path>][<text>]]' and `[[<path>]]' forms via
`a3madkour-pub--extract-asset-refs', resolves each path via
`a3madkour-pub--asset-resolve-path', and returns the subset whose
resolved `:abs-path' exists on disk.  D.2's PDF + Word backends call
this to find SVG figures that need rsvg-convert → PDF / PNG conversion
ahead of the actual export."
  (let ((result nil))
    (dolist (ref (a3madkour-pub--extract-asset-refs source-file))
      (let* ((path (car ref))
             (resolved (a3madkour-pub--asset-resolve-path path source-file))
             (abs (plist-get resolved :abs-path)))
        (when (and abs (file-exists-p abs))
          (push abs result))))
    (nreverse result)))

(provide 'a3madkour-publish-assets)

;;; a3madkour-publish-assets.el ends here
