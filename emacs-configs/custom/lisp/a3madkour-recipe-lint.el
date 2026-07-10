;;; a3madkour-recipe-lint.el --- recipe pre-publish linter  -*- lexical-binding: t; -*-

;;; Commentary:
;; Slice 2: pre-publish validator for org recipe sources.  Returns a list of
;; "file:line: message" strings (empty = clean).  The recipes publish handler
;; calls this before export and aborts on errors unless disabled.

;;; Code:
(require 'cl-lib)
(require 'org-element)

(defvar a3madkour-recipe-lint-enabled t
  "When nil, the recipes handler skips the lint gate (--skip-recipe-check).")

(defconst a3madkour-recipe-lint--cols '("qty" "unit" "item" "group" "note" "alt")
  "Required ingredient-table header columns.")
(defconst a3madkour-recipe-lint--timecode-re
  "\\`\\[[0-9]\\{1,2\\}:[0-5][0-9]\\(?:\\.[0-9]\\{1,2\\}\\)?\\]"
  "Matches a leading [mm:ss] or [mm:ss.ff] step marker.")
(defconst a3madkour-recipe-lint--video-re "\\`[A-Za-z0-9_-]\\{11\\}\\'"
  "Matches a bare 11-char YouTube id.")

(defun a3madkour-recipe-lint--line-of (element)
  "1-based source line of ELEMENT's :begin (1 if absent)."
  (let ((b (and element (org-element-property :begin element))))
    (if b (line-number-at-pos b) 1)))

(defun a3madkour-recipe-lint--kw (ast name)
  "Value of `#+NAME:'-style keyword NAME (upcased) in AST, or nil."
  (org-element-map ast 'keyword
    (lambda (kw)
      (when (string-equal (upcase (org-element-property :key kw)) name)
        (org-element-property :value kw)))
    nil t))

(defun a3madkour-recipe-lint--drawer-value (ast key)
  "Value of :PROPERTIES: drawer KEY (upcased) in AST, or nil.
Reuses the handler's position-robust extraction so a drawer authored after
#+TITLE:/#+HUGO_SUMMARY: keywords is still read."
  (cdr (assoc (upcase key) (a3madkour-pub-recipes--drawer-alist ast))))

;; Re-use the handler's AST helpers.
(declare-function a3madkour-pub-recipes--drawer-alist "a3madkour-publish-recipes")
(declare-function a3madkour-pub-recipes--find-heading-named "a3madkour-publish-recipes")
(declare-function a3madkour-pub-recipes--find-table-under "a3madkour-publish-recipes")
(declare-function a3madkour-pub-recipes--table-rows "a3madkour-publish-recipes")
(declare-function a3madkour-pub-recipes--top-level-items "a3madkour-publish-recipes")
(declare-function a3madkour-pub-recipes--item-text "a3madkour-publish-recipes")
(declare-function a3madkour-pub-recipes--coerce-qty "a3madkour-publish-recipes")
(declare-function a3madkour-pub-recipes--cell "a3madkour-publish-recipes")

(defun a3madkour-recipe-lint/lint-file (file)
  "Lint recipe FILE.  Return a list of \"FILE:LINE: message\" strings (empty = clean)."
  (require 'a3madkour-publish-recipes)
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (let* ((ast (org-element-parse-buffer))
           (errs '())
           (base (file-name-nondirectory file))
           (emit (lambda (line msg) (push (format "%s:%d: %s" base line msg) errs))))
      ;; Rule 6: required metadata.
      (unless (a3madkour-recipe-lint--kw ast "TITLE")
        (funcall emit 1 "missing #+TITLE:"))
      (unless (a3madkour-recipe-lint--kw ast "HUGO_SUMMARY")
        (funcall emit 1 "missing #+HUGO_SUMMARY:"))
      (let ((sv (a3madkour-recipe-lint--drawer-value ast "SERVINGS")))
        (unless (and sv (string-match-p "\\`[0-9]+\\'" (string-trim sv))
                     (> (string-to-number sv) 0))
          (funcall emit 1 "missing or non-positive :servings:")))
      ;; Rule 1: required subheadings.
      (let ((ing (a3madkour-pub-recipes--find-heading-named ast "ingredients"))
            (steps (a3madkour-pub-recipes--find-heading-named ast "steps"))
            (sources (a3madkour-pub-recipes--find-heading-named ast "sources")))
        (unless ing (funcall emit 1 "missing ** Ingredients heading"))
        (unless steps (funcall emit 1 "missing ** Steps heading"))
        (if (not sources)
            (funcall emit 1 "missing ** Sources heading")
          (unless (a3madkour-pub-recipes--top-level-items sources)
            (funcall emit (a3madkour-recipe-lint--line-of sources)
                     "** Sources has no list items")))
        ;; Rules 2-3: ingredient table + rows.
        (when ing
          (let ((table (a3madkour-pub-recipes--find-table-under ing)))
            (if (not table)
                (funcall emit (a3madkour-recipe-lint--line-of ing)
                         "** Ingredients has no table")
              (let* ((rows (a3madkour-pub-recipes--table-rows table))
                     (header (mapcar #'downcase (car rows)))
                     (data (cdr rows)))
                (dolist (col a3madkour-recipe-lint--cols)
                  (unless (cl-position col header :test #'string-equal)
                    (funcall emit (a3madkour-recipe-lint--line-of table)
                             (format "ingredients table missing column %S" col))))
                (let ((ln (a3madkour-recipe-lint--line-of table)))
                  (dolist (row data)
                    (let ((qty (a3madkour-pub-recipes--cell row header "qty"))
                          (item (a3madkour-pub-recipes--cell row header "item")))
                      (when (and qty (not (a3madkour-pub-recipes--coerce-qty qty)))
                        (funcall emit ln (format "ingredient qty %S is not numeric-or-empty" qty)))
                      (unless item
                        (funcall emit ln "ingredient row missing item")))))))))
        ;; Rule 4: step timecodes.
        (when steps
          (dolist (item (a3madkour-pub-recipes--top-level-items steps))
            (let ((txt (a3madkour-pub-recipes--item-text item)))
              (when (and (string-prefix-p "[" txt)
                         (not (string-match-p a3madkour-recipe-lint--timecode-re txt)))
                (funcall emit (a3madkour-recipe-lint--line-of item)
                         (format "malformed [mm:ss] timecode in step: %S"
                                 (substring txt 0 (min 12 (length txt))))))))))
      ;; Rule 5: video id shape.
      (let ((vid (a3madkour-recipe-lint--drawer-value ast "VIDEO")))
        (when (and vid (not (string-match-p a3madkour-recipe-lint--video-re (string-trim vid))))
          (funcall emit 1 (format ":video: %S is not an 11-char YouTube id" vid))))
      (nreverse errs))))

(provide 'a3madkour-recipe-lint)
;;; a3madkour-recipe-lint.el ends here
