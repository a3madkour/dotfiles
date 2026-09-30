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

(defconst a3madkour-pub-works--track-cols '("title" "duration")
  "Required columns of the `#+NAME: tracks' table, in any order.")

(defun a3madkour-pub-works--named-table (ast name)
  "Return the table element in AST carrying `#+NAME: NAME', or nil."
  (org-element-map ast 'table
    (lambda (tbl)
      (when (string-equal (or (org-element-property :name tbl) "") name)
        tbl))
    nil t))

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

(cl-defun a3madkour-pub-works/publish-works-file (file run &key on-done)
  "Publish a works FILE.  Filled in by Task 7."
  (ignore file run)
  (when on-done (funcall on-done 'err)))

(provide 'a3madkour-publish-works)

;;; a3madkour-publish-works.el ends here
