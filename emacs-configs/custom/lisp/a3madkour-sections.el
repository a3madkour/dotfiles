;;; a3madkour-sections.el --- reader for the site's section contract  -*- lexical-binding: t; -*-

;;; Commentary:

;; Per-section field contracts are NOT defined in elisp.  They live in the
;; site repo at `data/sections.json', which the site's fixture linters read
;; through `tools/sections.py', so the two languages cannot drift.  This
;; module generalises (and replaces) `a3madkour-works-vocab', which did the
;; same for games/music only.
;;
;; A missing or malformed contract is an error, never a skipped check and
;; never a fallback to a hardcoded copy: a fallback would silently restore
;; the drift surface the file exists to remove.
;;
;; No load-time dependency on the publish stack: the site-root helper is
;; required lazily inside `--path', so `a3madkour-publish-frontmatter'
;; (which requires this module) still loads on a bare `emacs -Q'.
;;
;; JSON `false' and `null' decode to nil.  `closed' is not consumed here
;; (the site linter owns the closed-set rule); `store' is read only for the
;; value "data" (library), whose items `a3-publish-mark' leaves alone.

;;; Code:

(require 'json)
(require 'cl-lib)

(defconst a3madkour-sections--rel "data/sections.json"
  "Contract path, relative to the site root.")

(defconst a3madkour-sections--version 1
  "The contract schema version this reader understands.")

(defvar a3madkour-sections-file nil
  "Absolute path of the contract to read instead of the site root's.
nil (the default) resolves `data/sections.json' under the root derived
from `a3madkour-pub/site-data-dir'.")

(defvar a3madkour-sections--cache nil
  "(PATH MTIME . PARSED) for the last read, or nil.
Keyed on mtime as well as path: async publish keeps one Emacs alive
across runs, so an edited contract must be noticed without a restart.")

(defvar a3madkour-pub/site-data-dir)
(declare-function a3madkour-pub-yaml/site-root "a3madkour-publish-yaml")

(defun a3madkour-sections--path ()
  "Absolute path of the contract file."
  (or a3madkour-sections-file
      (progn
        (unless (bound-and-true-p a3madkour-pub/site-data-dir)
          (error "a3madkour-sections: a3madkour-pub/site-data-dir is not set; \
cannot locate %s" a3madkour-sections--rel))
        ;; Lazy: keeps this module free of the org-roam/yaml stack.
        (require 'a3madkour-publish-yaml)
        (expand-file-name a3madkour-sections--rel
                          (a3madkour-pub-yaml/site-root)))))

(defun a3madkour-sections--case-field-p (variants name)
  "Non-nil when some case of VARIANTS declares a field called NAME."
  (cl-some (lambda (case)
             (assq (intern name) (alist-get 'fields (cdr case))))
           (alist-get 'cases variants)))

(defun a3madkour-sections--validate (parsed path)
  "Signal unless PARSED (read from PATH) is a usable version-1 contract."
  (let ((version (and (consp parsed) (alist-get 'version parsed))))
    (unless (equal version a3madkour-sections--version)
      (error "a3madkour-sections: contract at %s has version %S, expected %d"
             path version a3madkour-sections--version)))
  (let ((sections (alist-get 'sections parsed)))
    (unless (consp sections)
      (error "a3madkour-sections: contract at %s has no sections" path))
    (dolist (cell sections)
      (let* ((name (symbol-name (car cell)))
             (fields-cell (assq 'fields (cdr cell)))
             (fields (cdr fields-cell))
             (variants (alist-get 'variants (cdr cell))))
        ;; Key presence, not non-emptiness: `\"fields\": {}' (about)
        ;; decodes to nil and is a legal, empty field set.
        (unless fields-cell
          (error "a3madkour-sections: section %s in %s has no fields"
                 name path))
        (when variants
          (let ((on (alist-get 'on variants)))
            ;; The selector may be a base field or a field only the cases
            ;; declare (garden's `media_type').
            (unless (and (stringp on)
                         (or (assq (intern on) fields)
                             (a3madkour-sections--case-field-p variants on)))
              (error "a3madkour-sections: section %s variants.on %S is \
not a field (%s)" name on path))))))))

(defun a3madkour-sections/read ()
  "Read, validate and cache the contract.  Signal `error' on any problem."
  (let* ((path (a3madkour-sections--path))
         (attrs (file-attributes path))
         (mtime (and attrs (file-attribute-modification-time attrs))))
    (if (and a3madkour-sections--cache
             (equal (car a3madkour-sections--cache) path)
             (equal (cadr a3madkour-sections--cache) mtime))
        (cddr a3madkour-sections--cache)
      (unless attrs
        (error "a3madkour-sections: contract not found at %s" path))
      (let* ((text (with-temp-buffer
                     (insert-file-contents path)
                     (buffer-string)))
             (parsed (condition-case err
                         (json-parse-string text
                                            :object-type 'alist
                                            :array-type 'list
                                            :null-object nil
                                            :false-object nil)
                       (error
                        (error "a3madkour-sections: contract at %s is not \
valid JSON: %S" path err)))))
        (a3madkour-sections--validate parsed path)
        (setq a3madkour-sections--cache (cons path (cons mtime parsed)))
        parsed))))

(defun a3madkour-sections/names ()
  "Section names, as slash-form strings, in file order."
  (mapcar (lambda (c) (symbol-name (car c)))
          (alist-get 'sections (a3madkour-sections/read))))

(defun a3madkour-sections/spec (section)
  "The raw spec alist of SECTION (a slash-form string).  Signal if unknown."
  (or (alist-get (intern section) (alist-get 'sections (a3madkour-sections/read)))
      (error "a3madkour-sections: unknown section %S (contract at %s)"
             section (a3madkour-sections--path))))

(defun a3madkour-sections--cells (fields)
  "FIELDS (a parsed JSON object) as ((NAME-STRING . SPEC) ...)."
  (mapcar (lambda (c) (cons (symbol-name (car c)) (cdr c))) fields))

(defun a3madkour-sections--cases (spec)
  "The parsed `variants.cases' object of section SPEC, or nil."
  (alist-get 'cases (alist-get 'variants spec)))

(defun a3madkour-sections/fields (section &optional variant-case)
  "SECTION's fields as ((NAME . SPEC) ...).
NAME is a string; SPEC an alist keyed by the JSON's field-spec keys as
symbols.  Base fields come first in file order, then the fields of
VARIANT-CASE (a case name string) when given."
  (let* ((spec (a3madkour-sections/spec section))
         (base (a3madkour-sections--cells (alist-get 'fields spec))))
    (if (not variant-case)
        base
      (let ((case (assq (intern variant-case)
                        (a3madkour-sections--cases spec))))
        (unless case
          (error "a3madkour-sections: section %s has no variant case %S"
                 section variant-case))
        (append base (a3madkour-sections--cells
                      (alist-get 'fields (cdr case))))))))

(defun a3madkour-sections/variant-case (section value)
  "Name of SECTION's variant case selected by VALUE, or nil.
VALUE is the buffer's value of the section's `variants.on' field (nil
when that field is absent).  nil when SECTION has no variants.  Signal
when VALUE selects no case."
  (let ((cases (a3madkour-sections--cases (a3madkour-sections/spec section))))
    (when cases
      (or (cl-loop for (name . case) in cases
                   when (member value (alist-get 'values case))
                   return (symbol-name name))
          (error "a3madkour-sections: section %s has no variant case for %S"
                 section value)))))

(defun a3madkour-sections--all-cells (section)
  "Base fields of SECTION, then each case's new fields, de-duplicated."
  (let* ((spec (a3madkour-sections/spec section))
         (cells (a3madkour-sections--cells (alist-get 'fields spec))))
    (dolist (case (a3madkour-sections--cases spec))
      (dolist (f (a3madkour-sections--cells (alist-get 'fields (cdr case))))
        (unless (assoc (car f) cells)
          (setq cells (append cells (list f))))))
    cells))

(defun a3madkour-sections--sub-field (spec name)
  "Sub-field NAME of object field SPEC: its own fields, then its cases'."
  (or (alist-get (intern name) (alist-get 'fields spec))
      (cl-some (lambda (case)
                 (alist-get (intern name) (alist-get 'fields (cdr case))))
               (alist-get 'cases (alist-get 'variants spec)))))

(defun a3madkour-sections/field (section path)
  "Spec of field PATH in SECTION, searching base fields then every case.
PATH is a field name, or \"OBJECT.SUB\" for a sub-field of an `object'
field.  Signal when absent."
  (let* ((parts (split-string path "\\." t))
         (spec (cdr (assoc (car parts) (a3madkour-sections--all-cells section)))))
    (dolist (p (cdr parts))
      (setq spec (and spec (a3madkour-sections--sub-field spec p))))
    (or spec
        (error "a3madkour-sections: section %s has no field %s" section path))))

(defun a3madkour-sections/enum (section path)
  "Allowed values of enum field PATH in SECTION.  Signal if not an enum."
  (let ((spec (a3madkour-sections/field section path)))
    (unless (equal (alist-get 'type spec) "enum")
      (error "a3madkour-sections: %s.%s is not an enum (type %S)"
             section path (alist-get 'type spec)))
    (alist-get 'values spec)))

(defun a3madkour-sections/emitted-keys (section)
  "Every field name legal in SECTION's emitted frontmatter, as strings.
Base fields plus every variant case's, de-duplicated, in file order."
  (mapcar #'car (a3madkour-sections--all-cells section)))

(defun a3madkour-sections/required-authored (section)
  "Base fields of SECTION that are required and not derived by the pipeline."
  (cl-loop for (name . spec) in (a3madkour-sections/fields section)
           when (and (alist-get 'required spec)
                     (not (equal (alist-get 'from spec) "pipeline")))
           collect name))

(provide 'a3madkour-sections)

;;; a3madkour-sections.el ends here
