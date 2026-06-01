;;; a3madkour-publish-citations.el --- F citation pipeline -*- lexical-binding: t; -*-

;;; Commentary:

;; F sub-project orchestrator.  Owns:
;;   - pre-export buffer rewriter: [cite:@key] → @@hugo:{{< cite "key" >}}@@
;;   - per-run cite-key accumulator
;;   - notes_ref auto-detection
;;   - data/citations.yaml emitter (merge-on-publish, purge-on-sync)
;;   - M-x a3-sync-citations command

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-element)
(require 'a3madkour-publish-bib)

(defvar a3madkour-pub-citations--accumulator nil
  "Hash table mapping cite-key (string) to list of (SOURCE-FILE . POS)
pairs, populated by the rewriter during the publish run.")

(defun a3madkour-pub-citations--accumulator-init ()
  "Allocate a fresh empty accumulator hash."
  (setq a3madkour-pub-citations--accumulator
        (make-hash-table :test 'equal :size 64)))

(defun a3madkour-pub-citations--in-noexport-p (cite tree)
  "Return non-nil iff CITE element is inside a heading marked :noexport:."
  (let ((node (org-element-property :parent cite)))
    (while (and node
                (not (and (eq (org-element-type node) 'headline)
                          (member "noexport"
                                  (org-element-property :tags node)))))
      (setq node (org-element-property :parent node)))
    node))

(defun a3madkour-pub-citations--scan-buffer ()
  "Walk the current org buffer via `org-element-parse-buffer'; return a
list of (KEY . POS) pairs for every citation element.  POS is the
buffer position of the element's `begin' marker.  Multi-cite forms
return one pair per key in source order.  Style-overrides (`/text',
`/noauthor', `/locators') and prefix/suffix text are NOT filtered here
— Task 9's rewriter checks those and signals."
  (let ((tree (org-element-parse-buffer))
        (acc nil))
    (org-element-map tree 'citation
      (lambda (cite)
        (unless (a3madkour-pub-citations--in-noexport-p cite tree)
          (let ((begin (org-element-property :begin cite)))
            (dolist (ref (org-element-map cite 'citation-reference #'identity))
              (let ((key (org-element-property :key ref)))
                (when (and key (not (string-empty-p key)))
                  (push (cons key begin) acc))))))))
    (nreverse acc)))

(provide 'a3madkour-publish-citations)

;;; a3madkour-publish-citations.el ends here
