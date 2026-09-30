;;; a3madkour-works-lint.el --- works pre-publish linter  -*- lexical-binding: t; -*-

;;; Commentary:

;; Pre-publish lint for works/games and works/music org sources.  Reports
;; org `FILE:LINE: message' strings, mirroring a3madkour-recipe-lint.el.
;;
;; The four enum vocabularies are NOT defined here.  They live in the site
;; repo at data/works-vocab.json and are shared with
;; tools/check_works_fixtures.py, so the two languages cannot drift.  A
;; missing or malformed vocabulary is an error, never a skipped check.

;;; Code:

(require 'cl-lib)
(require 'org-element)
(require 'a3madkour-publish-yaml)
;; `a3madkour-pub/poetry-dir' is defined in `a3madkour-publish-poetry', not
;; `a3madkour-publish' -- the brief's requested `(require 'a3madkour-publish)'
;; does not bring it in.  Requiring the poetry module directly is safe: it
;; does not depend on this module or on `a3madkour-publish-works'.
(require 'a3madkour-publish-poetry)

(defvar a3madkour-works-lint-enabled t
  "When non-nil, the works handler runs this linter before publishing.")

(defconst a3madkour-works-lint--vocab-rel "data/works-vocab.json"
  "Vocabulary path, relative to the site root.")

(defconst a3madkour-works-lint--vocab-keys
  '("game_statuses" "game_kinds" "music_formats" "platform_kinds")
  "Keys every vocabulary file must define.")

(defvar a3madkour-works-lint--vocab-cache nil
  "Cons of (PATH . ALIST) for the last vocabulary read, or nil.")

(defun a3madkour-works-lint--read-vocab ()
  "Read and validate the vocabulary.  Signal `error' on any problem."
  (let ((path (expand-file-name a3madkour-works-lint--vocab-rel
                                (a3madkour-pub-yaml/site-root))))
    (if (and a3madkour-works-lint--vocab-cache
             (equal (car a3madkour-works-lint--vocab-cache) path))
        (cdr a3madkour-works-lint--vocab-cache)
      (unless (file-exists-p path)
        (error "a3madkour-works-lint: vocabulary not found at %s" path))
      (let* ((text (with-temp-buffer (insert-file-contents path) (buffer-string)))
             (parsed (condition-case err
                         (json-parse-string text :object-type 'alist
                                                 :array-type 'list)
                       (error
                        (error "a3madkour-works-lint: vocabulary at %s is not valid JSON: %S"
                               path err)))))
        ;; `json-parse-string' with :object-type 'alist returns object keys
        ;; as symbols, not strings, so lookups below intern KEY before
        ;; probing the alist.
        (dolist (k a3madkour-works-lint--vocab-keys)
          (unless (assq (intern k) parsed)
            (error "a3madkour-works-lint: vocabulary at %s missing key %s" path k)))
        (setq a3madkour-works-lint--vocab-cache (cons path parsed))
        parsed))))

(defun a3madkour-works-lint/vocab (key)
  "Return the list of allowed values for KEY (a string)."
  (unless (member key a3madkour-works-lint--vocab-keys)
    (error "a3madkour-works-lint: unknown vocabulary key %s" key))
  (cdr (assq (intern key) (a3madkour-works-lint--read-vocab))))

(defconst a3madkour-works-lint--required
  '((works-games . (status game_kind tagline year))
    (works-music . (format year)))
  "Required `#+HUGO_CUSTOM_FRONT_MATTER' keys per section.
title/date/lastmod/draft come from ox-hugo and are not authored here.")

(defun a3madkour-works-lint--kw (ast name)
  "Value of keyword NAME (upcased) in AST, or nil."
  (org-element-map ast 'keyword
    (lambda (kw)
      (when (string-equal (upcase (org-element-property :key kw)) name)
        (org-element-property :value kw)))
    nil t))

(defun a3madkour-works-lint--parse-plist (s)
  "Parse `:key value :key \"quoted value\"' string S into ((SYMBOL . STRING) ...)."
  (let ((pos 0) (len (length s)) (out '()))
    (while (and (< pos len)
                (string-match ":\\([A-Za-z0-9_-]+\\)[ \t]+" s pos))
      (let* ((key (intern (match-string 1 s)))
             (vstart (match-end 0)))
        (if (and (< vstart len) (eq (aref s vstart) ?\"))
            (let ((end (string-match "\"" s (1+ vstart))))
              (push (cons key (substring s (1+ vstart) (or end len))) out)
              (setq pos (if end (1+ end) len)))
          (let ((end (or (string-match "[ \t]+:[A-Za-z0-9_-]+[ \t]" s vstart) len)))
            (push (cons key (string-trim (substring s vstart end))) out)
            (setq pos end)))))
    (nreverse out)))

(defun a3madkour-works-lint--cfm-cells (ast)
  "Merged custom-front-matter cells as ((KEY VALUE . LINE) ...), later lines winning."
  (let ((cells '()))
    (org-element-map ast 'keyword
      (lambda (kw)
        (when (string-equal (upcase (org-element-property :key kw))
                            "HUGO_CUSTOM_FRONT_MATTER")
          (let ((line (line-number-at-pos (org-element-property :begin kw))))
            (dolist (pair (a3madkour-works-lint--parse-plist
                           (or (org-element-property :value kw) "")))
              (setf (alist-get (car pair) cells) (cons (cdr pair) line)))))))
    cells))

(defun a3madkour-works-lint--looks-like-filename-p (v)
  "Non-nil when V has a file extension."
  (and (stringp v) (string-match-p "\\.[A-Za-z0-9]+\\'" v)))

(defun a3madkour-works-lint--poem-declares-set-to-music-p (poem-file)
  "Non-nil when POEM-FILE's custom front matter declares `set_to_music'."
  (with-temp-buffer
    (insert-file-contents poem-file)
    (org-mode)
    (and (alist-get 'set_to_music
                    (a3madkour-works-lint--cfm-cells (org-element-parse-buffer)))
         t)))

(defun a3madkour-works-lint--check-lyrics-symmetry (base cells)
  "Return a list of symmetry errors for the music item described by CELLS.

`check_works_links.py' enforces lyrics_poem <-> set_to_music in both
directions, but the two ends are written by different handlers in different
modes, so satisfying one never satisfies the other.  Catching it here turns a
post-push CI failure into a file:line error."
  (let* ((cell (alist-get 'lyrics_poem cells))
         (slug (car cell))
         (line (or (cdr cell) 1))
         (errs '()))
    (when slug
      (let ((poem (expand-file-name (format "%s.org" slug) a3madkour-pub/poetry-dir)))
        (cond
         ((not (file-exists-p poem))
          (push (format "%s:%d: :lyrics_poem %S has no org source at %s"
                        base line slug poem)
                errs))
         ((not (a3madkour-works-lint--poem-declares-set-to-music-p poem))
          (push (format "%s:%d: :lyrics_poem %S but %s does not declare :set_to_music"
                        base line slug (file-name-nondirectory poem))
                errs)))))
    errs))

(defun a3madkour-works-lint/lint-file (file)
  "Lint works FILE.  Return a list of \"FILE:LINE: message\" strings (empty = clean)."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (let* ((ast     (org-element-parse-buffer))
           (base    (file-name-nondirectory file))
           (section (a3madkour-works-lint--kw ast "HUGO_SECTION"))
           (errs    '()))
      (when (member section '("works/games" "works/music"))
        (let* ((games-p (string-equal section "works/games"))
               (sym     (if games-p 'works-games 'works-music))
               (cells   (a3madkour-works-lint--cfm-cells ast))
               (id      (a3madkour-works-lint--kw ast "ID"))
               (asset-dir (expand-file-name
                           (format "assets/%s/" (or id ""))
                           (file-name-directory file))))
          (cl-flet* ((val (k) (car (alist-get k cells)))
                     (ln  (k) (or (cdr (alist-get k cells)) 1))
                     (add (k fmt &rest args)
                          (push (format "%s:%d: %s" base (ln k)
                                        (apply #'format fmt args))
                                errs)))
            ;; 1 — required keys
            (dolist (k (cdr (assq sym a3madkour-works-lint--required)))
              (unless (alist-get k cells)
                (push (format "%s:1: missing required key :%s" base k) errs)))
            ;; 2 — enum membership, against the shared vocabulary
            (dolist (spec (if games-p
                              '((status . "game_statuses") (game_kind . "game_kinds"))
                            '((format . "music_formats"))))
              (let ((v (val (car spec))))
                (when v
                  (let ((allowed (a3madkour-works-lint/vocab (cdr spec))))
                    (unless (member v allowed)
                      (add (car spec) ":%s=%S not in %S" (car spec) v allowed))))))
            ;; 3 — hero polymorphism: filename for games, bool for music
            (let ((h (val 'hero)))
              (when h
                (if games-p
                    (unless (a3madkour-works-lint--looks-like-filename-p h)
                      (add 'hero ":hero must be a filename for works/games, got %S" h))
                  (when (a3madkour-works-lint--looks-like-filename-p h)
                    (add 'hero ":hero must be a boolean for works/music, got %S" h)))))
            ;; 4 — asset filenames: present on disk
            (dolist (k (if games-p '(hero screenshots) '(cover)))
              (let ((raw (val k)))
                (when (and raw (or (not (eq k 'hero)) games-p))
                  (dolist (name (split-string raw "[ \t]+" t))
                    (unless (file-exists-p (expand-file-name name asset-dir))
                      (add k ":%s entry %S not found in %s" k name asset-dir))))))
            ;; A quoted multi-word filename survives `val' intact, so catch it
            ;; before the split above can hide it as two names.
            (dolist (k (if games-p '(hero screenshots) '(cover)))
              (let ((raw (val k)))
                (when (and raw (string-match-p "[^ \t]\\(?:[ \t]\\)[^ \t]*\\.[A-Za-z0-9]+\\'" raw)
                           (not (string-match-p "\\`[^ \t]+\\'" raw)))
                  (add k ":%s value %S contains a space; filenames may not" k raw))))
            ;; 5 — lyrics_poem must have its reciprocal set_to_music
            (unless games-p
              (setq errs (append (a3madkour-works-lint--check-lyrics-symmetry base cells)
                                 errs)))))
        (setq errs (nreverse errs)))
      errs)))

(provide 'a3madkour-works-lint)

;;; a3madkour-works-lint.el ends here
