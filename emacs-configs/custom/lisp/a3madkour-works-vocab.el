;;; a3madkour-works-vocab.el --- reader for the shared works vocabulary  -*- lexical-binding: t; -*-

;;; Commentary:

;; The works vocabulary is NOT defined in elisp.  It lives in the site repo at
;; `data/works-vocab.json' and is shared with `tools/check_works_fixtures.py',
;; so the two languages cannot drift.  A missing or malformed vocabulary is an
;; error, never a skipped check and never a fallback to a hardcoded copy — a
;; fallback would silently restore the drift surface the file exists to remove.
;;
;; It carries two kinds of list:
;;
;;   * the four ENUM vocabularies (`game_statuses', `game_kinds',
;;     `music_formats', `platform_kinds'), read by `a3madkour-works-lint';
;;   * the games/music EMITTED-FIELD sets (`game_required', `game_optional',
;;     `music_required', `music_optional', `umbrella_optional'), read by
;;     `a3madkour-publish-frontmatter' to filter emitted frontmatter.
;;
;; The field sets were transcribed into elisp — twice, counting the test
;; constants — until 2026-09-29.  Nothing could observe both halves: the
;; `-key-set-matches-contract' tests compared the elisp defconst against the
;; elisp test constant, so a key added on the Python side left all three stale
;; and green, and the normalizer's allowed-key filter then dropped the new
;; field from every published page with no error at any layer.
;;
;; This module exists as a separate file rather than living in
;; `a3madkour-works-lint' because BOTH consumers need it and
;; `a3madkour-works-lint' sits downstream of `a3madkour-publish-frontmatter'
;; (via `a3madkour-publish-poetry').  A `require' the other way round would be
;; a load cycle.  It therefore has no load-time dependency of its own: the
;; site-root helper is required lazily, inside the one function that needs it,
;; so `a3madkour-publish-frontmatter' stays loadable on a bare `emacs -Q'.

;;; Code:

(require 'json)

(defconst a3madkour-works-vocab--rel "data/works-vocab.json"
  "Vocabulary path, relative to the site root.")

(defconst a3madkour-works-vocab-enum-keys
  '("game_statuses" "game_kinds" "music_formats" "platform_kinds")
  "Enum vocabulary keys.  Consumed by `a3madkour-works-lint'.")

(defconst a3madkour-works-vocab-field-keys
  '("umbrella_optional"
    "game_required" "game_optional"
    "music_required" "music_optional")
  "Emitted-field contract keys.  Consumed by the works frontmatter normalizer.

The per-type unions are composed, not stored: games' legal key set is
`game_required' + `game_optional' + `umbrella_optional'.  See
`a3madkour-works-vocab/emitted-keys'.")

(defconst a3madkour-works-vocab--keys
  (append a3madkour-works-vocab-enum-keys a3madkour-works-vocab-field-keys)
  "Every key a vocabulary file must define.")

(defvar a3madkour-works-vocab--cache nil
  "Cache of (PATH MTIME . ALIST) for the last vocabulary read, or nil.

Keyed on the file's modification time as well as its path.  A path-only key
served a stale vocabulary for the rest of the session once the file changed
under a long-lived Emacs — and async publish on this project is long-lived by
design, so editing `data/works-vocab.json' and re-publishing without
restarting Emacs was a real workflow.")

(declare-function a3madkour-pub-yaml/site-root "a3madkour-publish-yaml")

(defun a3madkour-works-vocab--path ()
  "Absolute path to the vocabulary file under the current site root."
  ;; Lazy require: keeps this module (and therefore
  ;; `a3madkour-publish-frontmatter') free of a load-time dependency on the
  ;; org-roam/yaml stack that `a3madkour-publish-yaml' pulls in.
  (require 'a3madkour-publish-yaml)
  (expand-file-name a3madkour-works-vocab--rel (a3madkour-pub-yaml/site-root)))

(defun a3madkour-works-vocab/read ()
  "Read and validate the vocabulary.  Signal `error' on any problem."
  (let* ((path (a3madkour-works-vocab--path))
         (attrs (file-attributes path))
         (mtime (and attrs (file-attribute-modification-time attrs))))
    (if (and a3madkour-works-vocab--cache
             (equal (car a3madkour-works-vocab--cache) path)
             (equal (cadr a3madkour-works-vocab--cache) mtime))
        (cddr a3madkour-works-vocab--cache)
      (unless attrs
        (error "a3madkour-works-vocab: vocabulary not found at %s" path))
      (let* ((text (with-temp-buffer (insert-file-contents path) (buffer-string)))
             (parsed (condition-case err
                         (json-parse-string text :object-type 'alist
                                                 :array-type 'list)
                       (error
                        (error "a3madkour-works-vocab: vocabulary at %s is not valid JSON: %S"
                               path err)))))
        ;; `json-parse-string' with :object-type 'alist returns object keys as
        ;; symbols, not strings, so lookups intern KEY before probing.
        (dolist (k a3madkour-works-vocab--keys)
          (unless (assq (intern k) parsed)
            (error "a3madkour-works-vocab: vocabulary at %s missing key %s" path k)))
        (setq a3madkour-works-vocab--cache (cons path (cons mtime parsed)))
        parsed))))

(defun a3madkour-works-vocab/list (key)
  "Return the list of strings the vocabulary defines for KEY."
  (unless (member key a3madkour-works-vocab--keys)
    (error "a3madkour-works-vocab: unknown vocabulary key %s" key))
  (cdr (assq (intern key) (a3madkour-works-vocab/read))))

(defun a3madkour-works-vocab/emitted-keys (section)
  "Every frontmatter key legal for SECTION, as interned symbols.

SECTION is the hyphen-form symbol `works-games' or `works-music'.  The set is
`<type>_required' + `<type>_optional' + `umbrella_optional', composed here so
one Bento-grid key added to the vocabulary reaches both types at once."
  (let ((prefix (pcase section
                  ('works-games "game")
                  ('works-music "music")
                  (_ (error "a3madkour-works-vocab: no field contract for %S" section)))))
    (mapcar #'intern
            (append (a3madkour-works-vocab/list (format "%s_required" prefix))
                    (a3madkour-works-vocab/list (format "%s_optional" prefix))
                    (a3madkour-works-vocab/list "umbrella_optional")))))

(provide 'a3madkour-works-vocab)

;;; a3madkour-works-vocab.el ends here
