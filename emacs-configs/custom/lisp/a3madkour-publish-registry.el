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

(defconst a3madkour-pub-registry
  '(("essays"             :mode deliberate
     :handler a3madkour-pub-essays/publish-essay-file)
    ("garden"             :mode living
     :handler a3madkour-pub-garden/publish-garden-file)
    ("research/themes"    :mode living
     :handler a3madkour-pub-research/publish-research-file)
    ("research/questions" :mode living
     :handler a3madkour-pub-research/publish-research-file)
    ("works/games"        :mode living
     :handler a3madkour-pub-works/publish-works-file)
    ("works/music"        :mode living
     :handler a3madkour-pub-works/publish-works-file)
    ("works/poetry"       :mode deliberate
     :handler a3madkour-pub-poetry/publish-poetry-file)
    ("library/reading"    :mode living
     :handler a3madkour-pub-library/publish-library-file
     :data-file "reading.yaml"   :default-medium "book")
    ("library/listening"  :mode living
     :handler a3madkour-pub-library/publish-library-file
     :data-file "listening.yaml" :default-medium "album")
    ("library/playing"    :mode living
     :handler a3madkour-pub-library/publish-library-file
     :data-file "playing.yaml"   :default-medium "game")
    ("library/watching"   :mode living
     :handler a3madkour-pub-library/publish-library-file
     :data-file "watching.yaml"  :default-medium "film")
    ("streams"            :mode nil :handler nil)
    ("recipes"            :mode living
     :handler a3madkour-pub-recipes/publish-recipe-file)
    ("about"              :mode nil :handler nil))
  "Every publishable section, keyed by its `#+HUGO_SECTION:' slash form.

Each entry is (SECTION . PLIST):
  :mode            `living' (published by `a3-publish-living'),
                   `deliberate' (by `a3-publish-deliberate'), or nil
                   (valid section, no handler yet: streams, about).
  :handler         handler function SYMBOL, signature
                   (file run &key on-done); resolved at dispatch.
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
