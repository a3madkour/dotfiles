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

(require 'a3madkour-publish-yaml)

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

(defun a3madkour-works-lint/lint-file (file)
  "Lint works FILE.  Return a list of \"FILE:LINE: message\" strings.
Rules are added in later tasks; this returns the empty list."
  (ignore file)
  nil)

(provide 'a3madkour-works-lint)

;;; a3madkour-works-lint.el ends here
