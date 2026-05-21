;;; a3madkour-publish.el --- Org → Hugo publish pipeline (sub-project A) -*- lexical-binding: t; -*-

;; Author: Abdelrahman Madkour <a3madkour@gmail.com>
;; Version: 0.1.0-bootstrap
;; Package-Requires: ((emacs "30.2"))
;; Keywords: org, hugo, publish

;;; Commentary:

;; Phase 3 sub-project A: access control + link semantics for the
;; org → Hugo publish pipeline driving https://a3madkour.github.io/.
;;
;; This is the bootstrap shell.  A.1.{a..d} implement keyword parsing,
;; slug derivation, URL-history, link rewriting, asset handling, and
;; the unpublish flow.  Consumed by sub-project B (the per-section
;; publisher) via the function surface documented in the design spec at
;; docs/superpowers/specs/2026-05-20-phase-3-access-control-link-semantics-design.md
;; (in the site repo).

;;; Code:

(defgroup a3madkour-pub nil
  "Org → Hugo publish pipeline (sub-project A: access control + link semantics)."
  :group 'org
  :prefix "a3madkour-pub/")

(require 'a3madkour-publish-keywords)
(require 'a3madkour-publish-slug)
(require 'a3madkour-publish-history)

(defconst a3madkour-pub/version "0.1.0-bootstrap"
  "Current version of the publish library.")

(defconst a3madkour-pub/sections
  '("essays"
    "garden"
    "research/themes" "research/questions"
    "works/games" "works/music" "works/poetry"
    "library/reading" "library/listening" "library/playing" "library/watching"
    "streams"
    "about")
  "Permitted values for the org-side `#+HUGO_SECTION:' keyword.
See docs/superpowers/specs/2026-05-20-phase-3-access-control-link-semantics-design.md §4.")

(defun a3madkour-pub/valid-section-p (s)
  "Return non-nil iff S is a string matching one of `a3madkour-pub/sections'."
  (and (stringp s)
       (member s a3madkour-pub/sections)
       t))

(defun a3madkour-pub--parse-file (file)
  "Open FILE and return a plist of parsed publish-relevant keywords.

Plist keys: :title :publish-p :section :draft-p :slug :aliases.
Empty-string values for :section and :slug are normalized to nil so
downstream `null'-checks behave uniformly.

Errors with `user-error' if FILE is missing.  Does not validate the
keyword combination — that is `published-p''s job.

NOTE: each public accessor (`published-p', `note-section', `note-slug',
`note-url') currently re-invokes this function.  For a caller that needs
multiple values from the same file, this means redundant file I/O.  A.1.b
will introduce a single-pass `note-metadata' accessor + cache; until then,
publish loops should hoist the parse manually if perf matters.

Uses pure regex extraction (no `(org-mode)' activation needed) to avoid
the ~1s org autoload on cold cache."
  (unless (file-readable-p file)
    (user-error "a3madkour-pub: cannot read file: %s" file))
  (with-temp-buffer
    (insert-file-contents file)
    (let ((raw-section (a3madkour-pub-keywords/extract "HUGO_SECTION"))
          (raw-slug    (a3madkour-pub-keywords/extract "HUGO_SLUG")))
      (list :title     (a3madkour-pub-keywords/extract "title")
            :publish-p (a3madkour-pub-keywords/boolean-p
                        (a3madkour-pub-keywords/extract "HUGO_PUBLISH"))
            :section   (and raw-section (not (string-empty-p raw-section)) raw-section)
            :draft-p   (a3madkour-pub-keywords/boolean-p
                        (a3madkour-pub-keywords/extract "HUGO_DRAFT"))
            :slug      (and raw-slug (not (string-empty-p raw-slug)) raw-slug)
            :aliases   (a3madkour-pub-keywords/parse-aliases
                        (a3madkour-pub-keywords/extract "HUGO_ALIASES"))))))

(defun a3madkour-pub/published-p (file)
  "Return the publish-state of FILE: `live', `draft', or nil.

Signals `user-error' for invalid combinations:
  - `#+HUGO_PUBLISH: t' without `#+HUGO_SECTION:'
  - `#+HUGO_SECTION:' with an unknown value (typo guard)

File path input only.  A.1.b will add an org-roam ID dispatching layer."
  (let* ((parsed (a3madkour-pub--parse-file file))
         (publish-p (plist-get parsed :publish-p))
         (section (plist-get parsed :section))
         (draft-p (plist-get parsed :draft-p)))
    (cond
     ;; Not opted-in → private (most common case).
     ((not publish-p) nil)
     ;; Opted-in but no section → likely typo / incomplete config.
     ((null section)
      (user-error "a3madkour-pub: %s has #+HUGO_PUBLISH but no #+HUGO_SECTION" file))
     ;; Unknown section value → likely typo.
     ((not (a3madkour-pub/valid-section-p section))
      (user-error "a3madkour-pub: %s has unknown #+HUGO_SECTION value %S"
                  file section))
     ;; All good.
     (draft-p 'draft)
     (t 'live))))

(defun a3madkour-pub/note-section (file)
  "Return the `#+HUGO_SECTION:' string value of FILE, or nil if absent."
  (let ((s (plist-get (a3madkour-pub--parse-file file) :section)))
    (and s (not (string-empty-p s)) s)))

(defun a3madkour-pub/note-slug (file)
  "Return the slug for FILE: `#+HUGO_SLUG:' if set, else slugified `#+title:'.
Returns nil if neither yields a non-empty result."
  (let* ((parsed (a3madkour-pub--parse-file file))
         (override (plist-get parsed :slug))
         (title (plist-get parsed :title)))
    (cond
     ((and override (not (string-empty-p override))) override)
     (title (let ((s (a3madkour-pub-slug/slugify title)))
              (and s (not (string-empty-p s)) s)))
     (t nil))))

(defun a3madkour-pub/note-url (file)
  "Return the URL path for FILE: `/<section>/<slug>/', or nil if FILE is not published.
Does NOT validate the publish state (use `published-p' for that) — it just
returns nil if the necessary pieces are missing."
  (let ((section (a3madkour-pub/note-section file))
        (slug (a3madkour-pub/note-slug file)))
    (when (and section slug)
      (format "/%s/%s/" section slug))))

(provide 'a3madkour-publish)

;;; a3madkour-publish.el ends here
