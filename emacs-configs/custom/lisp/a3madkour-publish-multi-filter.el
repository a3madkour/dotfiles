;;; a3madkour-publish-multi-filter.el --- D.2 multi-export visibility + vocab filter -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared filter module for the D.2 multi-target export pipeline.
;; Provides: opt-in detection, visibility-tag filter, D.1 vocab translation.

;;; Code:

(require 'a3madkour-publish-keywords)

(defconst a3madkour-pub-multi-filter--opt-in-keyword "MULTI_EXPORT"
  "Org buffer-keyword that opts a document into the multi-export pipeline.")

(defun a3madkour-pub-multi-filter--doc-p ()
  "Return non-nil iff current buffer carries `#+multi_export: t'."
  (a3madkour-pub-keywords/boolean-p
   (a3madkour-pub-keywords/extract
    a3madkour-pub-multi-filter--opt-in-keyword)))

(provide 'a3madkour-publish-multi-filter)
;;; a3madkour-publish-multi-filter.el ends here
