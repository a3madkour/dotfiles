;;; a3madkour-ingredients.el --- shared ingredient registry  -*- lexical-binding: t; -*-

;;; Commentary:

;; One org file names every ingredient once.  Level-1 headings are store
;; aisles, in the order the store is walked; level-2 headings are ingredients,
;; whose heading text is the canonical name.  An ingredient's state is the
;; keyword in front of its name (HAVE, LOW, OUT; none = untracked), and its
;; other names and usual unit are the :ALIASES: and :UNIT: properties.
;;
;; Recipes, the pantry and the grocery list all refer to ingredients through
;; `a3madkour-ingredients/lookup'.  This module depends on nothing but org, so
;; non-publishing code can use it.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)

(defvar a3madkour-ingredients/file nil
  "Absolute path of the ingredient registry org file, or nil.
With nil every reader returns nil and the recipe linter skips its registry
rule.")

(defconst a3madkour-ingredients--states
  '(("HAVE" . have) ("LOW" . low) ("OUT" . out))
  "State keyword → state symbol.")

(defvar a3madkour-ingredients--cache nil
  "(KEY . PARSED) for the last registry read; see `a3madkour-ingredients--parsed'.")

(defun a3madkour-ingredients/normalize (string)
  "Return STRING downcased, trimmed, with inner whitespace runs collapsed."
  (downcase (string-join (split-string (or string "") "[[:space:]]+" t) " ")))

;;; Parsing

(defun a3madkour-ingredients--strip-tags (title)
  "Return heading TITLE without trailing org tags, trimmed."
  (string-trim
   (replace-regexp-in-string "[ \t]+:[[:alnum:]_@#%:]+:[ \t]*\\'" "" title)))

(defun a3madkour-ingredients--split-aliases (value)
  "Split a comma-separated :ALIASES: VALUE, dropping empty pieces."
  (split-string (or value "") "," t "[[:space:]]+"))

(defun a3madkour-ingredients--parse (text)
  "Parse registry TEXT.  Return a plist (:entries LIST :aisles LIST).
The state is read from the heading text itself, so the result does not depend
on the file's #+TODO: line or on the session's keywords."
  (let ((case-fold-search nil)
        (line 0) (aisle nil) (aisles '()) (entries '())
        (current nil) (in-drawer nil))
    (cl-flet ((finish ()
                (when current (push current entries) (setq current nil))
                (setq in-drawer nil)))
      (dolist (l (split-string text "\n"))
        (cl-incf line)
        (cond
         ((string-match "\\`\\* +\\(.*\\)\\'" l)
          (finish)
          (setq aisle (a3madkour-ingredients--strip-tags (match-string 1 l)))
          (push aisle aisles))
         ((string-match "\\`\\*\\* +\\(.*\\)\\'" l)
          (finish)
          (let* ((title (a3madkour-ingredients--strip-tags (match-string 1 l)))
                 (state nil))
            (when (string-match "\\`\\(HAVE\\|LOW\\|OUT\\)\\(?:[ \t]+\\(.*\\)\\)?\\'" title)
              (setq state (cdr (assoc (match-string 1 title)
                                      a3madkour-ingredients--states))
                    title (string-trim (or (match-string 2 title) ""))))
            (unless (string-empty-p title)
              (setq current (list :name title :aliases nil :aisle aisle
                                  :unit nil :state state :line line)))))
         ((string-match-p "\\`\\*+ " l) (finish))
         ((null current))
         ((string-match-p "\\`[ \t]*:PROPERTIES:[ \t]*\\'" l) (setq in-drawer t))
         ((string-match-p "\\`[ \t]*:END:[ \t]*\\'" l) (setq in-drawer nil))
         ((and in-drawer
               (let ((case-fold-search t))
                 (string-match "\\`[ \t]*:\\(ALIASES\\|UNIT\\):[ \t]*\\(.*?\\)[ \t]*\\'" l)))
          (let ((key (upcase (match-string 1 l))) (val (match-string 2 l)))
            (if (string= key "ALIASES")
                (setq current (plist-put current :aliases
                                         (a3madkour-ingredients--split-aliases val)))
              (unless (string-empty-p val)
                (setq current (plist-put current :unit val))))))))
      (finish))
    (list :entries (nreverse entries) :aisles (nreverse aisles))))

;;; Reading, with a cache

(defun a3madkour-ingredients--visiting-buffer ()
  "The live buffer visiting the registry, or nil."
  (and a3madkour-ingredients/file
       (get-file-buffer a3madkour-ingredients/file)))

(defun a3madkour-ingredients--parsed ()
  "Return the parsed registry plist, or nil when unset or missing.
Unsaved edits in a buffer visiting the registry win over the file on disk.
The result is cached until the file (or that buffer) changes."
  (let ((file a3madkour-ingredients/file))
    (when file
      (let* ((buf (a3madkour-ingredients--visiting-buffer))
             (dirty (and buf (buffer-modified-p buf)))
             (key (cond
                   (dirty (list file 'buffer (buffer-chars-modified-tick buf)))
                   ((file-exists-p file)
                    (let ((attrs (file-attributes file)))
                      (list file 'file
                            (file-attribute-modification-time attrs)
                            (file-attribute-size attrs)))))))
        (when key
          (unless (equal key (car a3madkour-ingredients--cache))
            (setq a3madkour-ingredients--cache
                  (cons key
                        (a3madkour-ingredients--parse
                         (if dirty
                             (with-current-buffer buf
                               (save-restriction
                                 (widen)
                                 (buffer-substring-no-properties (point-min) (point-max))))
                           (with-temp-buffer
                             (insert-file-contents file)
                             (buffer-string)))))))
          (cdr a3madkour-ingredients--cache))))))

(defun a3madkour-ingredients/entries ()
  "Every ingredient in the registry, in file order.
Each is a plist (:name :aliases :aisle :unit :state :line); :state is `have',
`low', `out' or nil (untracked).  Nil when the registry is unset or missing."
  (plist-get (a3madkour-ingredients--parsed) :entries))

(defun a3madkour-ingredients/aisles ()
  "Aisle names (level-1 headings) in file order."
  (plist-get (a3madkour-ingredients--parsed) :aisles))

(defun a3madkour-ingredients/lookup (string)
  "The registry entry whose name or alias matches STRING, or nil.
Matching is case-insensitive and ignores padding and repeated whitespace."
  (let ((want (a3madkour-ingredients/normalize string)))
    (unless (string-empty-p want)
      (cl-find-if
       (lambda (e)
         (or (string= want (a3madkour-ingredients/normalize (plist-get e :name)))
             (cl-some (lambda (a) (string= want (a3madkour-ingredients/normalize a)))
                      (plist-get e :aliases))))
       (a3madkour-ingredients/entries)))))

(provide 'a3madkour-ingredients)
;;; a3madkour-ingredients.el ends here
