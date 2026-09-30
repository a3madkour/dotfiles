;;; a3madkour-publish-works.el --- works/games + works/music publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; Slice A1: one handler for two living sections.  Registered twice into
;; `a3madkour-pub-living--handlers' (works/games, works/music) against a
;; single entry point that branches on section.
;;
;; Authoring uses `#+HUGO_CUSTOM_FRONT_MATTER:' (the research idiom), NOT a
;; :PROPERTIES: drawer — see the design spec §3.  Only music's track list is
;; parsed from the AST, as an org table, mirroring recipes' ingredients.

;;; Code:

(require 'cl-lib)
(require 'org-element)
(require 'a3madkour-publish-yaml)
(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)
(require 'a3madkour-works-lint)
;; `a3madkour-pub/poetry-dir' (used by `a3madkour-pub-works--warn-stale-backlink')
;; is defined in `a3madkour-publish-poetry', not `a3madkour-publish'.
(require 'a3madkour-publish-poetry)

(defconst a3madkour-pub-works--track-cols '("title" "duration")
  "Required columns of the `#+NAME: tracks' table, in any order.")

(defun a3madkour-pub-works--named-table (ast name)
  "Return the table element in AST carrying `#+NAME: NAME', or nil."
  (org-element-map ast 'table
    (lambda (tbl)
      (when (string-equal (or (org-element-property :name tbl) "") name)
        tbl))
    nil t))

(defun a3madkour-pub-works--strip-named-table (org-text name)
  "Return ORG-TEXT with the `#+NAME: NAME' table removed.

The tracks table is parsed for frontmatter out of the ORIGINAL source AST, so
leaving it in the export input renders it a SECOND time -- as a raw, unstyled
HTML <table> in the page body, beside the templated Tracks section.  Recipes hit
the same class of bug and answered it with `--strip-data-subtrees'; this is the
named-table equivalent.

The design spec argued a strip stage could not be needed here because there is
no :PROPERTIES: drawer to strip.  That held for the drawer; it did not hold for
the table, which is body content by construction.

`org-element' includes affiliated keywords in an element's extent, so :begin
sits on the `#+NAME:' line itself and deleting [:begin, :end) takes the name
line with the table."
  (with-temp-buffer
    (insert org-text)
    (org-mode)
    (let* ((ast (org-element-parse-buffer))
           (tbl (a3madkour-pub-works--named-table ast name)))
      (when tbl
        (delete-region (org-element-property :begin tbl)
                       (org-element-property :end tbl))))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun a3madkour-pub-works--table-rows (table)
  "Return TABLE's non-rule rows as lists of trimmed cell strings."
  (when table
    (delq nil
          (org-element-map table 'table-row
            (lambda (row)
              (when (eq (org-element-property :type row) 'standard)
                (org-element-map row 'table-cell
                  (lambda (cell)
                    (string-trim
                     (substring-no-properties
                      (org-element-interpret-data
                       (org-element-contents cell))))))))))))

(defun a3madkour-pub-works--parse-tracks (ast)
  "Parse the `#+NAME: tracks' table in AST.

Returns a list of ((title . STR) (duration . STR)) alists, or nil when the
table is absent or carries only a header row.  Returning nil rather than an
empty list is deliberate: the caller omits the key entirely, so the page does
not render an empty track list."
  (let* ((table (a3madkour-pub-works--named-table ast "tracks"))
         (rows (a3madkour-pub-works--table-rows table)))
    (when (and rows (cdr rows))
      (let* ((header (mapcar #'downcase (car rows)))
             (ti (cl-position "title" header :test #'string-equal))
             (di (cl-position "duration" header :test #'string-equal)))
        (when (and ti di)
          (delq nil
                (mapcar (lambda (row)
                          (let ((title (nth ti row))
                                (duration (nth di row)))
                            (unless (and (or (null title) (string-empty-p title))
                                         (or (null duration) (string-empty-p duration)))
                              (list (cons 'title (or title ""))
                                    (cons 'duration (or duration ""))))))
                        (cdr rows))))))))

(defun a3madkour-pub-works--render-track (track)
  "Render one TRACK alist as an inline flow map."
  (format "  - { title: \"%s\", duration: \"%s\" }"
          (a3madkour-pub/yaml-escape-scalar (or (alist-get 'title track) ""))
          (a3madkour-pub/yaml-escape-scalar (or (alist-get 'duration track) ""))))

(defun a3madkour-pub-works--render-platform-embed (pe)
  "Render PLATFORM-EMBED alist PE as an inline flow map.
`kind' is a closed enum so it is emitted bare; `url' is quoted."
  (format "platform_embed: { kind: %s, url: \"%s\" }"
          (or (alist-get 'kind pe) "")
          (a3madkour-pub/yaml-escape-scalar (or (alist-get 'url pe) ""))))

(defun a3madkour-pub-works--key-hook (k v)
  "render-frontmatter KEY-HOOK for the two structured works keys."
  (cond
   ((eq k 'tracks)
    (if (and v (listp v))
        (format "tracks:\n%s"
                (mapconcat #'a3madkour-pub-works--render-track v "\n"))
      :omit))
   ((eq k 'platform_embed)
    (if (and v (listp v))
        (a3madkour-pub-works--render-platform-embed v)
      :omit))))

(defun a3madkour-pub-works--render-frontmatter (alist)
  "Render ALIST as works frontmatter (structured keys via the key-hook)."
  (a3madkour-pub-yaml/render-frontmatter
   alist
   :key-hook #'a3madkour-pub-works--key-hook
   :value-fn #'a3madkour-pub-yaml/render-value))

(defconst a3madkour-pub-works--sections
  '(("works/games" . works-games)
    ("works/music" . works-music))
  "Sections this handler serves, mapping the slash form to the hyphen form.")

(defun a3madkour-pub-works--bundle-subdir (section)
  "Content subdirectory for SECTION.  Signals for an unserved section."
  (unless (assoc section a3madkour-pub-works--sections)
    (error "a3madkour-pub-works: unserved section %S" section))
  section)

(defun a3madkour-pub-works--normalize-symbol (section)
  "Hyphen-form normalize symbol for slash-form SECTION."
  (or (cdr (assoc section a3madkour-pub-works--sections))
      (error "a3madkour-pub-works: unserved section %S" section)))

(defun a3madkour-pub-works--claim-slug (table slug file)
  "Claim SLUG in TABLE for FILE.  Signals when SLUG is already taken.
Two org titles that slugify identically would otherwise write the same
bundle, and the second would silently overwrite the first."
  (let ((prior (gethash slug table)))
    (when (and prior (not (equal prior file)))
      (error "a3madkour-pub-works: slug %S claimed by both %s and %s"
             slug prior file))
    (puthash slug file table)
    t))

(defvar a3madkour-pub-works--slugs-seen (make-hash-table :test #'equal)
  "Slug -> file, for the duration of ONE publish run.

MUST be cleared at the start of each run, not left to accumulate for the life
of the Emacs session: otherwise renaming a works org file leaves the old
file's claim in the table forever, and the renamed file errors as a duplicate
until Emacs restarts.  A guard that blocks correct work is worse than the bug
it prevents.  Cleared by `a3madkour-pub-works--maybe-reset-slugs-seen', keyed
on the identity of the RUN struct passed into `publish-works-file' -- see
that function's docstring for why the reset is scoped to the run rather than
to each individual file.")

(defvar a3madkour-pub-works--slugs-seen-run 'a3madkour-pub-works--no-run-yet
  "Identity of the RUN object `a3madkour-pub-works--slugs-seen' was last
cleared for.  A sentinel distinct from any real RUN value (including nil,
which ad hoc callers may pass) so the very first call always resets.")

(defun a3madkour-pub-works--maybe-reset-slugs-seen (run)
  "Clear the slug-claim table iff RUN differs (by `eq') from the last-seen run.

`a3-publish-living' shares one RUN struct (from `a3-pub-async/begin-publish')
across every file it dispatches in a single walk, so this only fires once per
publish run -- not once per file, which would defeat the duplicate-slug guard
entirely (every file would see an empty table and no collision within the
same run would ever be caught).  Each call to `begin-publish' allocates a
fresh `a3-pub-async-run' struct, so `eq' reliably distinguishes one run from
the next."
  (unless (eq run a3madkour-pub-works--slugs-seen-run)
    (clrhash a3madkour-pub-works--slugs-seen)
    (setq a3madkour-pub-works--slugs-seen-run run)))

(defun a3madkour-pub-works--asset-names (section fm)
  "Bare asset filenames declared in frontmatter FM for SECTION."
  (let ((names '()))
    (pcase section
      ("works/games"
       (when-let ((h (alist-get 'hero fm))) (when (stringp h) (push h names)))
       (dolist (s (alist-get 'screenshots fm)) (when (stringp s) (push s names))))
      ("works/music"
       (when-let ((c (alist-get 'cover fm))) (when (stringp c) (push c names)))))
    (nreverse names)))

(defun a3madkour-pub-works--drop-broken-assets (section final-fm bundle-dir copied)
  "Drop FINAL-FM asset keys for SECTION whose declared file did not land in
BUNDLE-DIR, per COPIED (the `:copied' list `a3madkour-pub/asset-validate-and-copy'
returned for this call).

`asset-validate-and-copy' reports a missing/failed frontmatter-declared
asset (an `extra-refs' entry) via its returned `:errors' list rather than
signaling -- works is the first handler to pass `extra-refs', so without
this a broken filename would ship straight into the page frontmatter and
render a dead image, with nothing else in the pipeline catching it
(`works-lint' has no asset-existence check yet; `check_works_fixtures.py'
only type-checks).  Mirrors recipes' `--copy-drawer-image' precedent
\(recipes.el\): drop the key rather than fail the publish -- a missing
screenshot should not block a release, and Task 8's lint will catch it
earlier, at authoring `file:line' time.

`hero' (games) / `cover' (music) drop the whole key when its one file is
missing; `screenshots' (games) drops only the missing entry, keeping the
rest of the list."
  (cl-flet ((landed-p (name)
              (and (stringp name)
                   (member (expand-file-name (file-name-nondirectory name) bundle-dir)
                           copied))))
    (let ((out (copy-alist final-fm)))
      (pcase section
        ("works/games"
         (when (and (assq 'hero out) (not (landed-p (alist-get 'hero out))))
           (setq out (assq-delete-all 'hero out)))
         (when (assq 'screenshots out)
           (let ((kept (seq-filter #'landed-p (alist-get 'screenshots out))))
             (if kept
                 (setf (alist-get 'screenshots out) kept)
               (setq out (assq-delete-all 'screenshots out))))))
        ("works/music"
         (when (and (assq 'cover out) (not (landed-p (alist-get 'cover out))))
           (setq out (assq-delete-all 'cover out)))))
      out)))

(defun a3madkour-pub-works--warn-stale-backlink (poem-slug site-root)
  "WARN when POEM-SLUG's published bundle lacks its set_to_music back-link.

The org sources agree (the lint enforces that), but poetry publishes
deliberately, so its bundle may legitimately lag.  A warning, not an error —
naming the exact command to close the gap."
  (let ((bundle (expand-file-name
                 (format "content/works/poetry/%s/index.md" poem-slug) site-root)))
    (when (and (file-exists-p bundle)
               (not (with-temp-buffer
                      (insert-file-contents bundle)
                      (goto-char (point-min))
                      (re-search-forward "^set_to_music:" nil t))))
      (a3madkour-pub/warn
       "works" bundle
       "poem bundle lacks set_to_music; run: a3-pub.sh --publish-deliberate %s"
       (expand-file-name (format "%s.org" poem-slug) a3madkour-pub/poetry-dir)))))

(cl-defun a3madkour-pub-works/publish-works-file (file run &key on-done)
  "Publish a works/games or works/music FILE to content/works/<type>/<slug>/index.md.
Pipeline: lint → parse tracks → rewrite links → strip tracks table →
ox-hugo → normalize →
inject tracks → render → asset-copy → write-if-different → record-publish."
  (condition-case err
      (progn
        (a3madkour-pub-works--maybe-reset-slugs-seen run)
        (when a3madkour-works-lint-enabled
          (let ((errs (a3madkour-works-lint/lint-file file)))
            (when errs
              (error "a3madkour-pub-works: lint failed for %s:\n%s"
                     file (mapconcat #'identity errs "\n")))))
        (let* ((section   (a3madkour-pub/note-section file))
               (subdir    (a3madkour-pub-works--bundle-subdir section))
               (nsym      (a3madkour-pub-works--normalize-symbol section))
               (md        (a3madkour-pub/note-metadata file))
               (id        (plist-get md :id))
               (slug      (a3madkour-pub/note-slug file))
               (new-url   (a3madkour-pub/note-url file))
               (site-root (a3madkour-pub-yaml/site-root))
               (bundle-dir (expand-file-name
                            (format "content/%s/%s/" subdir slug) site-root))
               (out-path   (expand-file-name "index.md" bundle-dir))
               ;; Only music reads the AST (for the tracks table) -- skip the
               ;; org-mode + org-element-parse-buffer cost for games, which
               ;; never consults it.
               (src-ast    (when (eq nsym 'works-music)
                             (with-temp-buffer
                               (insert-file-contents file) (org-mode)
                               (org-element-parse-buffer))))
               (tmp-src    (a3madkour-pub-rewrite/rewrite-to-tmp-file
                            file id "a3-pub-works"))
               (exported   (unwind-protect
                               (progn
                                 ;; Music only: the tracks table has already
                                 ;; been read from `src-ast' for the
                                 ;; frontmatter, so strip it from the export
                                 ;; input or ox-hugo renders it into the body
                                 ;; as well.  Mirrors recipes' strip stage.
                                 (when (eq nsym 'works-music)
                                   (let ((stripped
                                          (a3madkour-pub-works--strip-named-table
                                           (with-temp-buffer
                                             (insert-file-contents tmp-src)
                                             (buffer-string))
                                           "tracks")))
                                     (with-temp-file tmp-src (insert stripped))))
                                 (a3madkour-pub-export/export-file tmp-src))
                             (when (file-exists-p tmp-src) (delete-file tmp-src))))
               (normalized (let ((a3madkour-pub-frontmatter--prior-last-modified
                                  (a3madkour-pub-history/recorded-last-modified id new-url)))
                             (a3madkour-pub-frontmatter/normalize
                              nsym (plist-get exported :frontmatter) file)))
               (final-fm   (let ((out (copy-alist normalized)))
                             (when (eq nsym 'works-music)
                               (when-let ((tr (a3madkour-pub-works--parse-tracks src-ast)))
                                 (setf (alist-get 'tracks out) tr)))
                             out))
               (body       (plist-get exported :body)))
          (a3madkour-pub-works--claim-slug a3madkour-pub-works--slugs-seen slug file)
          (let* ((asset-result (a3madkour-pub/asset-validate-and-copy
                                 file bundle-dir id nil
                                 (a3madkour-pub-works--asset-names section final-fm)))
                 (copied (plist-get asset-result :copied)))
            (setq final-fm
                  (a3madkour-pub-works--drop-broken-assets
                   section final-fm bundle-dir copied)))
          (a3madkour-pub-yaml/write-if-different
           out-path
           (concat (a3madkour-pub-works--render-frontmatter final-fm) body))
          (a3madkour-pub-history/record-publish
           id new-url (or (plist-get md :state) 'live)
           :last-modified (alist-get 'lastmod final-fm))
          (when (and (eq nsym 'works-music) (alist-get 'lyrics_poem final-fm))
            (a3madkour-pub-works--warn-stale-backlink
             (alist-get 'lyrics_poem final-fm) site-root)))
        (when on-done (funcall on-done 'ok)))
    (error
     (message "%s" (error-message-string err))
     (when on-done (funcall on-done 'err)))))

(defun a3madkour-pub-works/planned-steps (_file)
  "Return rough step count for the works handler."
  3)

(provide 'a3madkour-publish-works)

;;; a3madkour-publish-works.el ends here
