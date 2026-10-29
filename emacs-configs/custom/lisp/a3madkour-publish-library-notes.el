;;; a3madkour-publish-library-notes.el --- library shelves from item notes  -*- lexical-binding: t; -*-

;;; Commentary:

;; The library collector.  Every living-publish run rebuilds the four
;; shelves (`data/{reading,listening,playing,watching}.yaml') from the
;; run's shared library item notes: one row per live garden note whose
;; drawer carries `:LIBRARY_MEDIA_TYPE:' and whose garden bundle exists.
;;
;; Shelves are no longer built one org file -> one shelf: a shelf file
;; (`#+HUGO_SECTION: library/...') is refused by
;; `a3madkour-pub-library/refuse-shelf-file'.  Rendering reuses
;; `a3madkour-pub-library--render-row' and its key order.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'a3madkour-publish)
(require 'a3madkour-publish-keywords)
(require 'a3madkour-publish-yaml)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-history)
(require 'a3madkour-publish-registry)
(require 'a3madkour-sections)
(require 'a3madkour-publish-library)
(require 'a3madkour-publish-citations)  ; `--parse-existing-yaml'
(require 'a3madkour-publish-garden)     ; `section-dir-name'
(require 'a3madkour-library-items)

(defun a3madkour-pub-library-notes--bundle-path (slug)
  "Path of the garden bundle `index.md' for SLUG, resolved as the garden
handler resolves it."
  (expand-file-name
   (format "content/%s/%s/index.md" a3madkour-pub-garden/section-dir-name slug)
   (a3madkour-pub-yaml/site-root)))

(defun a3madkour-pub-library-notes--known-cite-keys ()
  "Top-level keys of the site's `data/citations.yaml' (nil when absent)."
  (mapcar #'car (a3madkour-pub-citations--parse-existing-yaml
                 (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir))))

(defun a3madkour-pub-library-notes--file-fields (file)
  "FILE's (FILETAGS-LIST . ROAM_REFS-STRING-OR-NIL)."
  (with-temp-buffer
    (insert-file-contents file)
    (delay-mode-hooks (org-mode))
    (cons (split-string (or (a3madkour-pub-keywords/extract "FILETAGS") "")
                        ":" t "[ \t]+")
          (org-entry-get (point-min) "ROAM_REFS"))))

(defun a3madkour-pub-library-notes--first-ref-key (refs)
  "The first `@key' citation key in ROAM_REFS string REFS, or nil.
An `@' inside a URL (`https://host/@user') is not a key."
  (when (and refs
             (string-match "\\(?:\\`\\|[ \t[:]\\)@\\([^][ \t\n;,]+\\)" refs))
    (match-string 1 refs)))

(defun a3madkour-pub-library-notes--problems (row props section)
  "Why ROW (built from drawer PROPS) would fail library SECTION's contract.
A list of messages, nil when ROW is valid.  Required fields are the
contract's authored ones (`a3madkour-sections/required-authored'); the
status must be one of the shelf's; dates must be YYYY-MM-DD; a finished
item needs its finished date.  These mirror the site's
`tools/check_library_fixtures.py', which fails CI on any of them."
  (let ((problems nil)
        (raw-year (alist-get "year" props nil nil #'equal)))
    (dolist (f (a3madkour-sections/required-authored section))
      (unless (plist-get row (intern (concat ":" f)))
        (push (if (and (equal f "year") raw-year)
                  (format "LIBRARY_YEAR %S is not a number" raw-year)
                (format "missing required LIBRARY_%s" (upcase f)))
              problems)))
    (let ((status (plist-get row :status))
          (allowed (a3madkour-library/statuses (plist-get row :media_type))))
      (when (and status (not (member status allowed)))
        (push (format "LIBRARY_STATUS %S is not one of %S" status allowed)
              problems))
      (when (and (equal status "finished") (not (plist-get row :finished)))
        (push "status finished needs LIBRARY_FINISHED" problems)))
    (dolist (f '(:started :finished))
      (let ((v (plist-get row f)))
        (when (and v (not (string-match-p
                           "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" v)))
          (push (format "LIBRARY_%s %S is not YYYY-MM-DD"
                        (upcase (substring (symbol-name f) 1)) v)
                problems))))
    (nreverse problems)))

(defun a3madkour-pub-library-notes--row-result (file known-cite-keys)
  "FILE's shelf row plist; nil when it has no garden bundle; or
\(invalid . PROBLEMS) when the row would fail its shelf's contract.
Every nil or invalid result is warned about, naming FILE."
  (let* ((md (a3madkour-pub/note-metadata file))
         (slug (plist-get md :slug)))
    (cond
     ((null slug)
      (a3madkour-pub/warn "library-notes" file "no slug; no shelf row")
      nil)
     ((not (file-exists-p (a3madkour-pub-library-notes--bundle-path slug)))
      (a3madkour-pub/warn "library-notes" file
                          "no garden bundle at %s; no shelf row"
                          (a3madkour-pub-library-notes--bundle-path slug))
      nil)
     (t
      (let* ((props (a3madkour-library/properties file))
             (fields (a3madkour-pub-library-notes--file-fields file))
             (cite (a3madkour-pub-library-notes--first-ref-key (cdr fields)))
             (known (or known-cite-keys
                        (a3madkour-pub-library-notes--known-cite-keys)))
             (preview (a3madkour-library/preview file))
             (extras (alist-get 'extras props))
             (row (list :slug slug :note_slug slug
                        :title (plist-get md :title))))
        (cl-flet ((prop (f) (alist-get f props nil nil #'equal)))
          (when (prop "creator") (setq row (plist-put row :creator (prop "creator"))))
          (when (and (prop "year") (string-match-p "\\`[0-9]+\\'" (prop "year")))
            (setq row (plist-put row :year (string-to-number (prop "year")))))
          (dolist (f '("media_type" "status" "started" "finished"))
            (when (prop f)
              (setq row (plist-put row (intern (concat ":" f)) (prop f))))))
        (setq row (plist-put
                   row :last_modified
                   (or (a3madkour-pub-history/recorded-last-modified
                        (plist-get md :id) (a3madkour-pub/note-url file))
                       (a3madkour-pub-frontmatter/last-modified-cascade file))))
        (when preview (setq row (plist-put row :preview preview)))
        (setq row (plist-put row :tags (a3madkour-library/clean-tags (car fields))))
        (when (and cite (member cite known))
          (setq row (plist-put row :cite_key cite)))
        (when extras (setq row (plist-put row :extras extras)))
        (let* ((shelf (a3madkour-library/shelf-for (plist-get row :media_type)))
               (problems
                (if shelf
                    (a3madkour-pub-library-notes--problems row props shelf)
                  (list (format "LIBRARY_MEDIA_TYPE %S has no shelf"
                                (plist-get row :media_type))))))
          (if (not problems)
              row
            (a3madkour-pub/warn "library-notes" file "no shelf row: %s"
                                (string-join problems "; "))
            (cons 'invalid problems))))))))

(defun a3madkour-pub-library-notes/row (file &optional known-cite-keys)
  "The shelf row plist for shared item note FILE, or nil.
Nil (with a warning) when FILE's garden bundle does not exist, since a row
must link to a published page, or when the row would fail its shelf's
contract (see `a3madkour-pub-library-notes--problems').  KNOWN-CITE-KEYS
defaults to the keys of `data/citations.yaml'; `:cite_key' is emitted
only for one of them."
  (let ((r (a3madkour-pub-library-notes--row-result file known-cite-keys)))
    (and (not (eq (car-safe r) 'invalid)) r)))

(defun a3madkour-pub-library-notes--render-shelf (rows section)
  "The whole yaml document for library SECTION holding ROWS."
  (concat
   "# Generated by a3madkour-publish-library-notes from shared item notes.\n"
   "# Manual edits will be overwritten on next publish-living run.\n"
   (if rows
       (concat "items:\n"
               (mapconcat (lambda (row)
                            (a3madkour-pub-library--render-row row section))
                          rows "\n")
               "\n")
     "items: []\n")))

(defun a3madkour-pub-library-notes/build-shelves (files)
  "Write all four library shelves from item notes FILES; return their paths.
FILES are the run's live garden item notes.  Each note's row goes to the
shelf of its media type, rows ordered by slug.  Every shelf is written on
every run (unchanged content is not rewritten), so a shelf whose last
item stopped being shared becomes `items: []'.

A note whose row would fail its shelf's contract gets no row; the shelves
are still written from the valid rows, and then an error naming every
such note is signalled, so the run reports `err'."
  (unless a3madkour-pub/site-data-dir
    (error "a3madkour-pub-library-notes: a3madkour-pub/site-data-dir is nil"))
  (let ((known (a3madkour-pub-library-notes--known-cite-keys))
        (by-shelf nil)
        (invalid nil))
    (dolist (file files)
      (let* ((media (alist-get "media_type" (a3madkour-library/properties file)
                               nil nil #'equal))
             (shelf (a3madkour-library/shelf-for media)))
        (if (not shelf)
            (a3madkour-pub/warn "library-notes" file
                                "media type %S has no shelf; no shelf row" media)
          (let ((r (a3madkour-pub-library-notes--row-result file known)))
            (cond
             ((eq (car-safe r) 'invalid)
              (push (format "%s: %s" file (string-join (cdr r) "; ")) invalid))
             (r (push r (alist-get shelf by-shelf nil nil #'equal))))))))
    (prog1
        (mapcar
         (lambda (section)
           (let ((path (expand-file-name (a3madkour-pub-registry/get section :data-file)
                                         a3madkour-pub/site-data-dir))
                 (rows (sort (copy-sequence (alist-get section by-shelf nil nil #'equal))
                             (lambda (a b) (string< (plist-get a :slug)
                                                    (plist-get b :slug))))))
             (a3madkour-pub-yaml/write-if-different
              path (a3madkour-pub-library-notes--render-shelf rows section))
             path))
         (a3madkour-pub-library/sections))
      (when invalid
        (error "item notes left off their shelf: %s"
               (string-join (nreverse invalid) " | "))))))

(provide 'a3madkour-publish-library-notes)

;;; a3madkour-publish-library-notes.el ends here
