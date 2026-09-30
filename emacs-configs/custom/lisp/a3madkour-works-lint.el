;;; a3madkour-works-lint.el --- works pre-publish linter  -*- lexical-binding: t; -*-

;;; Commentary:

;; Pre-publish lint for works/games and works/music org sources.  Reports
;; org `FILE:LINE: message' strings, mirroring a3madkour-recipe-lint.el.
;;
;; The four enum vocabularies are NOT defined here.  They live in the site
;; repo at data/works-vocab.json, are read by `a3madkour-works-vocab' and are
;; shared with tools/check_works_fixtures.py, so the two languages cannot
;; drift.  A missing or malformed vocabulary is an error, never a skipped
;; check.

;;; Code:

(require 'cl-lib)
(require 'org-element)
;; `a3madkour-works-vocab/list' — the vocabulary reader, which is a separate
;; module because the frontmatter normalizer needs the same file and sits
;; upstream of this one (via `a3madkour-publish-poetry'), so it cannot
;; `require' this module back.
(require 'a3madkour-works-vocab)
;; `a3madkour-pub--extract-id' lives here.  The note ID must be read from the
;; file-level `:PROPERTIES: :ID: ... :END:' drawer, which is the documented
;; authoring convention (design spec §3.1) and what the handler itself uses
;; via `a3madkour-pub/note-metadata'.  Reading a `#+ID:' KEYWORD instead made
;; the asset directory resolve to `<dir>/assets/' for every real file, so
;; every declared hero/screenshots/cover false-failed rule 4.
(require 'a3madkour-publish)
;; `a3madkour-pub/poetry-dir' is defined in `a3madkour-publish-poetry', not
;; `a3madkour-publish'.  Requiring the poetry module directly is safe: it
;; does not depend on this module or on `a3madkour-publish-works'.
(require 'a3madkour-publish-poetry)

(defvar a3madkour-works-lint-enabled t
  "When non-nil, the works handler runs this linter before publishing.")

(defvaralias 'a3madkour-works-lint--vocab-cache 'a3madkour-works-vocab--cache
  "Compatibility alias for the reader's cache, which now lives in
`a3madkour-works-vocab'.  Kept so callers and tests that rebind the cache by
its historical name still reach the one real cache.")

(defun a3madkour-works-lint/vocab (key)
  "Return the list of allowed values for KEY (a string).

A thin accessor over `a3madkour-works-vocab/list'.  The reader moved into its
own module because the frontmatter normalizer needs the same file for the
emitted-field sets and cannot `require' this one (it sits upstream of it via
`a3madkour-publish-poetry')."
  (a3madkour-works-vocab/list key))

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
               ;; Position-robust file-level `:ID:' drawer read, via the SAME
               ;; helper `a3madkour-pub/note-metadata' uses.  Sharing the
               ;; handler's own reader (rather than adding a third drawer
               ;; parser beside recipes' `--drawer-alist') makes it impossible
               ;; for the lint's asset directory to drift from the one the
               ;; handler copies assets out of.
               (id      (a3madkour-pub--extract-id))
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
            ;; 5 — a single quoted filename containing a space.  Rule 4 splits
            ;; on whitespace, so "my shot.png" would otherwise be hidden as two
            ;; independent not-found names.
            ;;
            ;; `hero'/`cover' name exactly ONE file, so any whitespace in them
            ;; is wrong.  `screenshots' is documented and implemented as a
            ;; whitespace-separated LIST (design spec §3.1's own example is
            ;; `:screenshots "shot-1.png shot-2.png"'), so whitespace there is
            ;; legitimate and the test has to be per-token instead: every token
            ;; must itself look like a filename.  "my shot.png" fails that
            ;; ("my" carries no extension) while "shot-1.png shot-2.png"
            ;; passes.  The previous form asked only whether the WHOLE value
            ;; held a space and ended in an extension, which rejected every
            ;; multi-screenshot game outright.
            (dolist (k (if games-p '(hero screenshots) '(cover)))
              (let ((raw (val k)))
                (when (and raw (string-match-p "[ \t]" raw))
                  (if (eq k 'screenshots)
                      (unless (cl-every #'a3madkour-works-lint--looks-like-filename-p
                                        (split-string raw "[ \t]+" t))
                        (add k ":%s value %S has a space inside a filename; \
filenames may not contain spaces" k raw))
                    (add k ":%s value %S contains a space; filenames may not" k raw)))))
            ;; 6 — map-valued keys cannot be carried by custom front matter.
            ;;
            ;; `#+HUGO_CUSTOM_FRONT_MATTER:' round-trips every custom value as
            ;; a flat scalar, so a nested map is not expressible through the
            ;; authoring channel at all: the value arrives as a string, the
            ;; render key-hook's `listp' test fails, its `:omit' branch fires,
            ;; and the field vanishes from the page with nothing anywhere
            ;; reporting it.
            ;;
            ;; Design spec §3.3 states the general rule: a works field whose
            ;; emitted shape is a map or a list of maps is authored either as
            ;; flat component keys the normalizer assembles (`platform_embed'
            ;; <- `:platform_kind' + `:platform_url') or as a named org table
            ;; parsed from the AST (`tracks' <- `#+NAME: tracks').  Those two
            ;; are the whole class today.  BOTH are in the emitted contract, so
            ;; both survive the normalizer's allowed-key filter as strings --
            ;; which is exactly why the rule has to be enforced here rather
            ;; than assumed.  Without it §3.3 is a comment, not a guarantee.
            (unless games-p
              (dolist (spec
                       '((platform_embed . "use :platform_kind + :platform_url")
                         (tracks . "supply a `#+NAME: tracks' org table instead")))
                (when (val (car spec))
                  (add (car spec)
                       ":%s cannot be authored directly (HUGO_CUSTOM_FRONT_MATTER \
carries flat scalars only, and a map-valued key is then silently dropped); %s"
                       (car spec) (cdr spec))))
              (let ((kind (val 'platform_kind))
                    (url  (val 'platform_url)))
                (cond
                 ((and kind (not url))
                  (add 'platform_kind ":platform_kind %S needs a matching :platform_url" kind))
                 ((and url (not kind))
                  (add 'platform_url ":platform_url %S needs a matching :platform_kind" url)))
                (when kind
                  (let ((allowed (a3madkour-works-lint/vocab "platform_kinds")))
                    (unless (member kind allowed)
                      (add 'platform_kind ":platform_kind=%S not in %S" kind allowed))))))
            ;; 7 — lyrics_poem must have its reciprocal set_to_music
            (unless games-p
              (setq errs (append (a3madkour-works-lint--check-lyrics-symmetry base cells)
                                 errs)))))
        (setq errs (nreverse errs)))
      errs)))

(provide 'a3madkour-works-lint)

;;; a3madkour-works-lint.el ends here
