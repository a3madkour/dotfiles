;;; a3madkour-publish-multi-filter.el --- D.2 multi-export visibility + vocab filter -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared filter module for the D.2 multi-target export pipeline.
;; Provides: opt-in detection, visibility-tag filter, D.1 vocab translation.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'a3madkour-publish-keywords)

(defconst a3madkour-pub-multi-filter--opt-in-keyword "MULTI_EXPORT"
  "Org buffer-keyword that opts a document into the multi-export pipeline.")

(defun a3madkour-pub-multi-filter--doc-p ()
  "Return non-nil iff current buffer carries `#+multi_export: t'."
  (a3madkour-pub-keywords/boolean-p
   (a3madkour-pub-keywords/extract
    a3madkour-pub-multi-filter--opt-in-keyword)))

(defconst a3madkour-pub-multi-filter--skip-rules
  '((hugo   . ("NOEXPORT_WEB"  "PAPER_ONLY"))
    (md     . ("NOEXPORT_WEB"  "PAPER_ONLY"))
    (latex  . ("NOEXPORT_PDF"  "WEB_ONLY"))
    (pandoc . ("NOEXPORT_WORD" "WEB_ONLY" "PAPER_ONLY")))
  "Alist of backend → list of tag names whose subtrees must be dropped.
Stock `:noexport:' is dropped natively by each backend and is not listed.")

(defun a3madkour-pub-multi-filter--skip-tags-for (backend)
  "Return the list of tag names to drop for BACKEND, or nil if unknown."
  (cdr (assq backend a3madkour-pub-multi-filter--skip-rules)))

(defun a3madkour-pub-multi-filter--apply-visibility (backend)
  "Delete subtrees in the current buffer that are tagged for BACKEND skip.
No-op when BACKEND has no rules.  Iterates from last to first so deletions
do not invalidate the position of earlier subtrees."
  (let ((skip-tags (a3madkour-pub-multi-filter--skip-tags-for backend)))
    (when skip-tags
      (save-excursion
        (let (positions)
          (org-map-entries
           (lambda ()
             (let ((tags (org-get-tags nil t)))
               (when (cl-some (lambda (tag) (member tag tags)) skip-tags)
                 (push (point) positions)))))
          (dolist (pos (sort positions #'>))
            (goto-char pos)
            (let ((inhibit-message t))
              (org-cut-subtree))))))))

(provide 'a3madkour-publish-multi-filter)
;;; a3madkour-publish-multi-filter.el ends here
