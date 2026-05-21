;;; a3madkour-publish-slug.el --- Slug derivation -*- lexical-binding: t; -*-

;;; Commentary:

;; Convert a title string to a URL slug.  Lowercase, ASCII-fold (Unicode
;; normalization), spaces → hyphens, strip punctuation.

;;; Code:

(require 'ucs-normalize)

(defun a3madkour-pub-slug--ascii-fold (s)
  "Decompose S to NFKD and drop combining marks, leaving ASCII where possible."
  (let* ((decomposed (ucs-normalize-NFKD-string s)))
    ;; U+0300–U+036F = Combining Diacritical Marks block.
    (replace-regexp-in-string "[̀-ͯ]" "" decomposed)))

(defun a3madkour-pub-slug/slugify (title)
  "Convert TITLE (string or nil) to a URL slug.

Rules (in order):
  1. nil / empty → \"\".
  2. NFKD-normalize, drop combining marks → ASCII-fold accented letters.
  3. Drop any character that isn't [a-zA-Z0-9], whitespace, hyphen, or
     a separator-class punctuation (`._/\\').
  4. Replace whitespace and separator-class punctuation with a hyphen.
  5. Lowercase.
  6. Collapse runs of hyphens.
  7. Strip leading/trailing hyphens.

Separator-class punctuation (`.', `_', `/', `\\') acts as a word boundary
and becomes a hyphen.  Other punctuation (apostrophes, `?', `!', etc.) is
dropped so that contractions and end-marks don't introduce spurious hyphens.

camelCase is NOT split — set `#+HUGO_SLUG:' for camelCase source filenames."
  (if (or (null title) (string-blank-p title))
      ""
    (let* ((folded (a3madkour-pub-slug--ascii-fold title))
           ;; Step 3: keep alphanumerics + whitespace + hyphen + separator punctuation.
           (clean (replace-regexp-in-string "[^a-zA-Z0-9 \t\n._/\\-]" "" folded))
           ;; Step 4: separators → hyphen.
           (hyphenated (replace-regexp-in-string "[ \t\n._/\\]+" "-" clean))
           (lower (downcase hyphenated))
           (collapsed (replace-regexp-in-string "-+" "-" lower))
           (trimmed (replace-regexp-in-string "\\`-+\\|-+\\'" "" collapsed)))
      trimmed)))

(provide 'a3madkour-publish-slug)

;;; a3madkour-publish-slug.el ends here
