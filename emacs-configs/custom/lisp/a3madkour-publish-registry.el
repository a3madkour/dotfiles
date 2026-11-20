;;; a3madkour-publish-registry.el --- the one table of publishable sections  -*- lexical-binding: t; -*-

;;; Commentary:

;; Every section the publisher knows, stored once in slash form.  It
;; replaces the scattered lists (`a3madkour-pub/sections',
;; `a3madkour-pub-deliberate-sections', the living and deliberate handler
;; tables, frontmatter's `--known-sections', library's `--config', works'
;; `--sections') and the hand-written slash→hyphen converters.
;;
;; Holds only what the PIPELINE needs: mode, handler, library data config.
;; Field contracts live in the site's `data/sections.json' (read by
;; `a3madkour-sections').  The two key sets are pinned equal by a
;; cross-repo test.
;;
;; Handlers are named by SYMBOL and resolved when called; this module
;; requires none of them.  That removes the old load-order coupling (five
;; `with-eval-after-load' registrations) and keeps `a3madkour-publish' from
;; depending on the deliberate modules.  A registered handler that is not
;; loaded at dispatch is a loud per-file error, not a silent skip.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish-paths)

(defconst a3madkour-pub-registry
  '(("essays"             :mode deliberate
     :folder a3madkour-pub/essays-dir
     :handler a3madkour-pub-essays/publish-essay-file)
    ("garden"             :mode living
     :folder a3madkour-pub/org-notes-dir
     :handler a3madkour-pub-garden/publish-garden-file)
    ("research/themes"    :mode living
     :folder a3madkour-pub/org-notes-dir
     :handler a3madkour-pub-research/publish-research-file)
    ("research/questions" :mode living
     :folder a3madkour-pub/org-notes-dir
     :handler a3madkour-pub-research/publish-research-file)
    ("works/games"        :mode living
     :folder a3madkour-pub/org-notes-dir
     :handler a3madkour-pub-works/publish-works-file)
    ("works/music"        :mode living
     :folder a3madkour-pub/org-notes-dir
     :handler a3madkour-pub-works/publish-works-file)
    ("works/poetry"       :mode deliberate
     :folder a3madkour-pub/poetry-dir
     :handler a3madkour-pub-poetry/publish-poetry-file)
    ("library/reading"    :mode living
     :handler a3madkour-pub-library/refuse-shelf-file
     :data-file "reading.yaml"   :default-medium "book")
    ("library/listening"  :mode living
     :handler a3madkour-pub-library/refuse-shelf-file
     :data-file "listening.yaml" :default-medium "album")
    ("library/playing"    :mode living
     :handler a3madkour-pub-library/refuse-shelf-file
     :data-file "playing.yaml"   :default-medium "game")
    ("library/watching"   :mode living
     :handler a3madkour-pub-library/refuse-shelf-file
     :data-file "watching.yaml"  :default-medium "film")
    ("streams"            :mode nil :handler nil)
    ("recipes"            :mode living
     :folder a3madkour-pub-recipes-dir
     :handler a3madkour-pub-recipes/publish-recipe-file)
    ("about"              :mode nil :handler nil))
  "Every publishable section, keyed by its `#+HUGO_SECTION:' slash form.

Each entry is (SECTION . PLIST):
  :mode            `living' (published by `a3-publish-living'),
                   `deliberate' (by `a3-publish-deliberate'), or nil
                   (valid section, no handler yet: streams, about).
  :handler         handler function SYMBOL, signature
                   (file run &key on-done); resolved at dispatch.
  :folder          the variable naming the folder this section's files
                   live in, or absent.  `a3-publish-mark' suggests the
                   sections of the folder the file is in; it never
                   restricts them.
  :data-file       library only: the data/ yaml file the section writes.
  :default-medium  library only: the media_type used when a heading
                   declares none.

Order is the `a3-publish-mark' completion order.")

(defun a3madkour-pub-registry/names ()
  "Every registered section, as slash-form strings, in registry order."
  (mapcar #'car a3madkour-pub-registry))

(defun a3madkour-pub-registry/entry (section)
  "The plist registered for SECTION.  Signal if SECTION is unknown."
  (let ((cell (assoc section a3madkour-pub-registry)))
    (unless cell
      (error "a3madkour-pub-registry: unknown section %S" section))
    (cdr cell)))

(defun a3madkour-pub-registry/get (section prop)
  "Property PROP of SECTION's registry entry."
  (plist-get (a3madkour-pub-registry/entry section) prop))

(defun a3madkour-pub-registry/sections-with-mode (mode)
  "Sections whose :mode is MODE, in registry order."
  (let (out)
    (dolist (cell a3madkour-pub-registry (nreverse out))
      (when (eq (plist-get (cdr cell) :mode) mode)
        (push (car cell) out)))))

(defun a3madkour-pub-registry/sections-for-handler (handler)
  "Sections whose :handler is HANDLER, in registry order."
  (let (out)
    (dolist (cell a3madkour-pub-registry (nreverse out))
      (when (eq (plist-get (cdr cell) :handler) handler)
        (push (car cell) out)))))

(defun a3madkour-pub-registry/handler (section mode)
  "Handler symbol of SECTION when it is registered with MODE, else nil.
An unknown SECTION also yields nil: callers see the section first as a
note's `#+HUGO_SECTION:', which `a3madkour-pub/valid-section-p' guards."
  (let ((entry (cdr (assoc section a3madkour-pub-registry))))
    (and entry
         (eq (plist-get entry :mode) mode)
         (plist-get entry :handler))))

(defun a3madkour-pub-registry-living-folders ()
  "The folders living publish walks, as absolute directory names.
One per distinct `:folder' variable of the living sections, in registry
order, without duplicates.  `a3madkour-pub/org-notes-dir' is resolved with
`a3madkour-pub/path', so an unset notes folder signals.  Any other
folder variable is included only when it is a non-empty string naming
an existing directory; an unset (nil) or missing folder, such as an
unset `a3madkour-pub-recipes-dir', is skipped."
  (let (out)
    (dolist (section (a3madkour-pub-registry/sections-with-mode 'living))
      (let ((dir (a3madkour-pub-registry--folder-dir
                  (a3madkour-pub-registry/get section :folder))))
        (when (and dir (not (member dir out)))
          (push dir out))))
    (nreverse out)))

(defun a3madkour-pub-registry--folder-dir (var)
  "The directory folder variable VAR names, as a directory name, or nil.
Resolved as `a3madkour-pub-registry-living-folders' describes: nil when
VAR is nil, unset, empty or names no existing directory."
  (let* ((value (and var (boundp var) (symbol-value var)))
         (dir (cond
               ((eq var 'a3madkour-pub/org-notes-dir)
                (a3madkour-pub/path var))
               ((and (stringp value) (not (string-empty-p value))
                     (file-directory-p (expand-file-name value)))
                (expand-file-name value)))))
    (and dir (file-name-as-directory dir))))

(defun a3madkour-pub-registry-section-walked-p (section)
  "Non-nil when living publish walks SECTION's folder this run.
True when SECTION has no `:folder' (or is not registered), or when its
folder is among `a3madkour-pub-registry-living-folders'.  False for a
section whose folder is unset or missing, such as recipes while
`a3madkour-pub-recipes-dir' is nil: its pages are absent from the walk
because nothing was looked at, not because they were unpublished.

The notes folder is always walked (the walk signals without it), so it
counts as walked without being resolved; this predicate never signals."
  (let ((var (plist-get (cdr (assoc section a3madkour-pub-registry)) :folder)))
    (or (null var)
        (eq var 'a3madkour-pub/org-notes-dir)
        (and (a3madkour-pub-registry--folder-dir var)
             (cl-some (lambda (living)
                        (eq var (a3madkour-pub-registry/get living :folder)))
                      (a3madkour-pub-registry/sections-with-mode 'living))
             t))))

(defun a3madkour-pub-registry-living-files ()
  "Every `.org' file under `a3madkour-pub-registry-living-folders'.
Recursive, without duplicates, folder by folder in registry order."
  (let ((seen (make-hash-table :test 'equal))
        out)
    (dolist (dir (a3madkour-pub-registry-living-folders))
      (dolist (file (directory-files-recursively dir "\\.org\\'"))
        (unless (gethash file seen)
          (puthash file t seen)
          (push file out))))
    (nreverse out)))

(defun a3madkour-pub-section/symbol (section)
  "The hyphen-form symbol of slash-form SECTION.
\"works/poetry\" -> `works-poetry'.  The only slash->hyphen conversion in
the publisher.  Signal if SECTION is not registered."
  (a3madkour-pub-registry/entry section)
  (intern (replace-regexp-in-string "/" "-" section)))

(defun a3madkour-pub-section/from-symbol (symbol)
  "The slash-form section whose hyphen form is SYMBOL.  Signal if none."
  (or (catch 'found
        (dolist (s (a3madkour-pub-registry/names))
          (when (eq (a3madkour-pub-section/symbol s) symbol)
            (throw 'found s))))
      (error "a3madkour-pub-registry: no section for symbol %S" symbol)))

(provide 'a3madkour-publish-registry)

;;; a3madkour-publish-registry.el ends here
