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

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-yaml)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)

(defcustom a3madkour-pub-garden/section-dir-name "garden"
  "Hugo content section directory name for garden notes (relative to site root)."
  :type 'string
  :group 'a3madkour-pub)

;; P3.1: the frontmatter-render stack is shared via `a3madkour-publish-yaml';
;; these per-section names stay as thin wrappers so call sites + tests are
;; unchanged.  Garden uses the plain variant (no key-hook, non-strict values).
(defun a3madkour-pub-garden--site-root ()
  "Thin wrapper over `a3madkour-pub-yaml/site-root' (P3.1)."
  (a3madkour-pub-yaml/site-root))

(defun a3madkour-pub-garden--write-if-different (path content)
  "Thin wrapper over `a3madkour-pub-yaml/write-if-different' (P3.1)."
  (a3madkour-pub-yaml/write-if-different path content))

(defun a3madkour-pub-garden--render-yaml-value (v)
  "Thin wrapper over `a3madkour-pub-yaml/render-value' (P3.1)."
  (a3madkour-pub-yaml/render-value v))

(defun a3madkour-pub-garden--render-frontmatter (alist)
  "Thin wrapper over `a3madkour-pub-yaml/render-frontmatter' (P3.1)."
  (a3madkour-pub-yaml/render-frontmatter alist))

(cl-defun a3madkour-pub-garden/publish-garden-file (file run &key on-done)
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
Hugo's REF_NOT_FOUND check against B's hyphen-slug bundle paths.

RUN is the a3-pub-async-run handle (used for log-step in later tasks).
ON-DONE is invoked with \\='ok on completion or \\='err if any step throws."
  (condition-case _err
      (progn
        (ignore run)
        (let* ((md        (a3madkour-pub/note-metadata file))
               (id        (plist-get md :id))
               (slug      (a3madkour-pub/note-slug file))
               (new-url   (a3madkour-pub/note-url file))
               (site-root (a3madkour-pub-garden--site-root))
               (bundle-dir (expand-file-name
                            (format "content/%s/%s/"
                                    a3madkour-pub-garden/section-dir-name slug)
                            site-root))
               (out-path   (expand-file-name "index.md" bundle-dir))
               (tmp-src    (a3madkour-pub-rewrite/rewrite-to-tmp-file
                            file id "a3-pub-garden"))
               ;; unwind-protect deletes tmp-src whether export-file succeeds or signals.
               (exported   (unwind-protect
                               (a3madkour-pub-export/export-file tmp-src)
                             (when (file-exists-p tmp-src)
                               (delete-file tmp-src))))
               ;; P2.14: reuse the note's previously-recorded last_modified as
               ;; the cascade's prior value so an uncommitted republish keeps a
               ;; stable date instead of churning to the filesystem mtime.
               (normalized (let ((a3madkour-pub-frontmatter--prior-last-modified
                                  (a3madkour-pub-history/recorded-last-modified id new-url)))
                             (a3madkour-pub-frontmatter/normalize
                              'garden (plist-get exported :frontmatter) file)))
               (body       (plist-get exported :body)))
          (a3madkour-pub/asset-validate-and-copy file bundle-dir id)
          (a3madkour-pub-garden--write-if-different
           out-path
           (concat (a3madkour-pub-garden--render-frontmatter normalized) body))
          (a3madkour-pub-history/record-publish id new-url (or (plist-get md :state) 'live)
                                                :last-modified
                                                (or (alist-get 'lastmod normalized)
                                                    (alist-get 'last_modified normalized))))
        (when on-done (funcall on-done 'ok)))
    (error
     (when on-done (funcall on-done 'err)))))

(defun a3madkour-pub-garden/planned-steps (_file)
  "Return rough step count for B.1 garden handler."
  3)

(provide 'a3madkour-publish-garden)

;;; a3madkour-publish-garden.el ends here
