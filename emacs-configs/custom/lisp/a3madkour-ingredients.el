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

(defgroup a3madkour-ingredients nil
  "The shared ingredient registry."
  :group 'org)

(defcustom a3madkour-ingredients/file nil
  "Absolute path of the ingredient registry org file, or nil.
With nil every reader returns nil and the recipe linter skips its registry
rule.  Like the publisher's folders it names no location itself: config.org
sets it (see `a3madkour-pub/path-variables')."
  :type '(choice (const :tag "No registry" nil) file)
  :group 'a3madkour-ingredients)

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
                             (buffer-string))))))
            ;; Said once per re-read.  The copy itself is never touched.
            (let ((copies (a3madkour-ingredients/conflict-files)))
              (when copies
                (message "Ingredient registry has a sync conflict copy: %s"
                         (car copies)))))
          (cdr a3madkour-ingredients--cache))))))

(defun a3madkour-ingredients/conflict-files ()
  "Sync-conflict copies sitting beside the registry, as absolute paths.
They are only ever listed: never read, merged or deleted."
  (let ((file a3madkour-ingredients/file))
    (when (and file (file-directory-p (file-name-directory file)))
      (directory-files
       (file-name-directory file) t
       (concat "\\`" (regexp-quote (file-name-base file)) "\\.sync-conflict-")))))

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

;;; Problems in the registry itself

(defun a3madkour-ingredients/problems ()
  "Problems in the registry, as \"FILE:LINE: message\" strings in file order.
Nil when it is clean, unset or missing."
  (let ((base (and a3madkour-ingredients/file
                   (file-name-nondirectory a3madkour-ingredients/file)))
        (seen (make-hash-table :test #'equal))
        (out '()))
    (dolist (e (a3madkour-ingredients/entries))
      (let ((line (plist-get e :line))
            (name (plist-get e :name)))
        (cl-flet ((emit (fmt &rest args)
                    (push (format "%s:%d: %s" base line (apply #'format fmt args)) out)))
          (unless (plist-get e :aisle)
            (emit "ingredient %S is outside any aisle" name))
          (dolist (n (cons name (plist-get e :aliases)))
            (let* ((norm (a3madkour-ingredients/normalize n))
                   (first (gethash norm seen)))
              (if first
                  (emit "duplicate name %S (also line %d)" norm first)
                (puthash norm line seen))))
          (let ((case-fold-search nil))
            (when (string-match "\\`\\([[:upper:]]\\{2,\\}\\)[ \t]+[^ \t]" name)
              (emit "%S is not a state (use HAVE, LOW or OUT)"
                    (match-string 1 name)))))))
    (nreverse out)))

;;; Editing the registry

(defconst a3madkour-ingredients--header
  "#+TITLE: Ingredients\n#+TODO: HAVE LOW | OUT\n#+STARTUP: nologdone\n\n"
  "What a new registry file starts with.
Org always treats the last keyword of a sequence as a done state (a trailing
`|' does not prevent it), so OUT is written as one and `nologdone' keeps the
in-file keyword keys from stamping CLOSED when an ingredient runs out.")

(defun a3madkour-ingredients--state-keyword (state)
  "The keyword for STATE (`have', `low', `out'), or nil for untracked."
  (car (rassq state a3madkour-ingredients--states)))

(defmacro a3madkour-ingredients--editing (&rest body)
  "Run BODY in the registry's buffer, widened, then save it.
The buffer is the one visiting the file, so an open registry stays current.  If
the file changed on disk under an unmodified buffer (a sync), the buffer is
reverted first, so BODY never edits stale text."
  (declare (indent 0))
  `(let ((file (or a3madkour-ingredients/file
                   (user-error "a3madkour-ingredients/file is not set"))))
     (make-directory (file-name-directory file) t)
     ;; `find-file-noselect' would ask "reread from disk?" about a buffer whose
     ;; file changed underneath it; take the existing buffer and decide here.
     (with-current-buffer (or (get-file-buffer file) (find-file-noselect file))
       (when (and (not (buffer-modified-p))
                  (file-exists-p file)
                  (not (verify-visited-file-modtime (current-buffer))))
         (revert-buffer t t t))
       (prog1 (save-excursion (save-restriction (widen) ,@body))
         (save-buffer)))))

(defun a3madkour-ingredients--refuse-if-known (string)
  "Signal a `user-error' when STRING is already a name or alias."
  (let ((e (a3madkour-ingredients/lookup string)))
    (when e
      (user-error "\"%s\" is already in the registry as \"%s\" (%s)"
                  string (plist-get e :name) (plist-get e :aisle)))))

(defun a3madkour-ingredients--entry-or-error (name)
  "The entry for NAME, or a `user-error'."
  (or (a3madkour-ingredients/lookup name)
      (user-error "No ingredient \"%s\" in the registry" name)))

(defun a3madkour-ingredients--goto-line (line)
  (goto-char (point-min))
  (forward-line (1- line)))

(defun a3madkour-ingredients--end-of-aisle (aisle)
  "Move point to where a new ingredient of AISLE goes, creating AISLE if new."
  (let ((want (a3madkour-ingredients/normalize aisle))
        (case-fold-search nil)
        (found nil))
    (goto-char (point-min))
    (while (and (not found) (re-search-forward "^\\* +\\(.*\\)$" nil t))
      (when (string= want (a3madkour-ingredients/normalize
                           (a3madkour-ingredients--strip-tags (match-string 1))))
        (setq found t)))
    (if found
        (if (re-search-forward "^\\* " nil t)
            (goto-char (match-beginning 0))
          (goto-char (point-max)))
      (goto-char (point-max))
      (unless (or (bobp) (bolp)) (insert "\n"))
      (insert "* " (string-trim aisle) "\n"))
    (unless (or (bobp) (bolp)) (insert "\n"))))

(defun a3madkour-ingredients/add-entry (name aisle &optional aliases unit state)
  "Add ingredient NAME under AISLE and save the registry.  Return its entry.
ALIASES is a list of strings, UNIT a string, STATE `have', `low', `out' or nil
\(untracked).  Creates the registry, and AISLE, when they do not exist.  Refuses
a NAME or alias that the registry already knows."
  (a3madkour-ingredients--editing
    (let* ((name (string-trim (or name "")))
           (aisle (string-trim (or aisle "")))
           (unit (string-trim (or unit "")))
           (aliases (cl-remove-duplicates
                     (cl-remove-if
                      (lambda (a) (or (string-empty-p a)
                                      (string= (a3madkour-ingredients/normalize a)
                                               (a3madkour-ingredients/normalize name))))
                      (mapcar #'string-trim aliases))
                     :test (lambda (a b) (string= (a3madkour-ingredients/normalize a)
                                                  (a3madkour-ingredients/normalize b)))
                     :from-end t))
           (keyword (a3madkour-ingredients--state-keyword state)))
      (when (string-empty-p name) (user-error "Ingredient name is empty"))
      (when (string-empty-p aisle) (user-error "Aisle is empty"))
      (mapc #'a3madkour-ingredients--refuse-if-known (cons name aliases))
      (when (= (point-min) (point-max))
        (insert a3madkour-ingredients--header))
      (a3madkour-ingredients--end-of-aisle aisle)
      (insert "** " (if keyword (concat keyword " ") "") name "\n")
      (when (or aliases (not (string-empty-p unit)))
        (insert ":PROPERTIES:\n")
        (when aliases (insert ":ALIASES: " (string-join aliases ", ") "\n"))
        (unless (string-empty-p unit) (insert ":UNIT: " unit "\n"))
        (insert ":END:\n"))
      name))
  (a3madkour-ingredients/lookup name))

(defun a3madkour-ingredients/add-alias (name alias)
  "Record ALIAS as another name for ingredient NAME and save.  Return the entry.
NAME may itself be an alias.  Refuses an ALIAS another ingredient already has."
  (a3madkour-ingredients--editing
    (let* ((entry (a3madkour-ingredients--entry-or-error name))
           (alias (string-trim (or alias "")))
           (holder (a3madkour-ingredients/lookup alias)))
      (when (string-empty-p alias) (user-error "Alias is empty"))
      (unless (and holder (= (plist-get holder :line) (plist-get entry :line)))
        (a3madkour-ingredients--refuse-if-known alias)
        (let ((value (string-join (append (plist-get entry :aliases) (list alias)) ", "))
              (case-fold-search t)
              (limit nil))
          (a3madkour-ingredients--goto-line (plist-get entry :line))
          (forward-line 1)
          (setq limit (save-excursion
                        (if (re-search-forward "^\\*+ " nil t) (match-beginning 0) (point-max))))
          (cond
           ((save-excursion
              (re-search-forward "^[ \t]*:ALIASES:.*$" limit t))
            (goto-char (match-beginning 0))
            (delete-region (point) (line-end-position))
            (insert ":ALIASES: " value))
           ((save-excursion
              (re-search-forward "^[ \t]*:PROPERTIES:[ \t]*\n" limit t))
            (goto-char (match-end 0))
            (insert ":ALIASES: " value "\n"))
           (t
            (insert ":PROPERTIES:\n:ALIASES: " value "\n:END:\n")))))
      (setq name (plist-get entry :name))))
  (a3madkour-ingredients/lookup name))

(defun a3madkour-ingredients/set-entry-state (name state)
  "Set ingredient NAME to STATE (`have', `low', `out', nil = untracked) and save.
Return the entry.  The keyword in the heading is rewritten directly: no org
hooks run and nothing is logged."
  (a3madkour-ingredients--editing
    (let ((entry (a3madkour-ingredients--entry-or-error name))
          (keyword (a3madkour-ingredients--state-keyword state))
          (case-fold-search nil))
      (a3madkour-ingredients--goto-line (plist-get entry :line))
      (when (looking-at "\\*\\* +\\(?:\\(?:HAVE\\|LOW\\|OUT\\)[ \t]+\\)?")
        (replace-match (concat "** " (if keyword (concat keyword " ") "")) t t))
      (setq name (plist-get entry :name))))
  (a3madkour-ingredients/lookup name))

;;; Reading a recipe's ingredient table

;; The module reads the table itself, line by line, so that it depends on
;; nothing from the publish pipeline.

(defun a3madkour-ingredients--rule-line-p (line)
  "Non-nil when LINE is a table rule (|---+---|)."
  (string-match-p "\\`[ \t]*|[-+]" line))

(defun a3madkour-ingredients--row-cells (line)
  "The trimmed cells of table row LINE."
  (let ((s (string-trim line)))
    (setq s (string-remove-suffix "|" (string-remove-prefix "|" s)))
    (mapcar #'string-trim (split-string s "|"))))

(defun a3madkour-ingredients--ingredients-heading-p (line)
  "Non-nil when LINE is a heading titled Ingredients (any level, any case)."
  (and (string-match "\\`\\*+ +\\(.*\\)\\'" line)
       (string= "ingredients"
                (a3madkour-ingredients/normalize
                 (a3madkour-ingredients--strip-tags (match-string 1 line))))))

(defun a3madkour-ingredients--current-line ()
  (buffer-substring-no-properties (line-beginning-position) (line-end-position)))

(defun a3madkour-ingredients--recipe-rows (&optional buffer)
  "Cell lists of the first table under BUFFER's Ingredients heading, rules
dropped, header row first.  Nil when there is no such heading or table."
  (with-current-buffer (or buffer (current-buffer))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (while (and (not (eobp))
                    (not (a3madkour-ingredients--ingredients-heading-p
                          (a3madkour-ingredients--current-line))))
          (forward-line 1))
        (unless (eobp)
          (forward-line 1)
          (while (and (not (eobp))
                      (not (looking-at "\\*+ "))
                      (not (looking-at "[ \t]*|")))
            (forward-line 1))
          (let ((rows '()))
            (while (and (not (eobp)) (looking-at "[ \t]*|"))
              (let ((line (a3madkour-ingredients--current-line)))
                (unless (a3madkour-ingredients--rule-line-p line)
                  (push (a3madkour-ingredients--row-cells line) rows)))
              (forward-line 1))
            (nreverse rows)))))))

(defun a3madkour-ingredients/recipe-items (&optional buffer)
  "The non-empty `item' cells of BUFFER's Ingredients table, in row order.
Nil when the recipe has no Ingredients heading, table or item column."
  (let* ((rows (a3madkour-ingredients--recipe-rows buffer))
         (index (cl-position "item" (mapcar #'downcase (car rows)) :test #'string=)))
    (when index
      (cl-loop for row in (cdr rows)
               for cell = (nth index row)
               when (and cell (not (string-empty-p cell)))
               collect cell))))

(defun a3madkour-ingredients/unknown-items (&optional buffer)
  "The items of BUFFER's recipe that are not in the registry.
Each appears once, in its first spelling."
  (let ((seen '()) (out '()))
    (dolist (item (a3madkour-ingredients/recipe-items buffer))
      (let ((norm (a3madkour-ingredients/normalize item)))
        (unless (or (member norm seen) (a3madkour-ingredients/lookup item))
          (push norm seen)
          (push item out))))
    (nreverse out)))

;;; The item cell at point, and completion in it

(defun a3madkour-ingredients--item-cell ()
  "The `item' cell point is in, as (START . END), or nil.
Non-nil only in a data row (not the header, not a rule) of a table whose
nearest heading above is Ingredients, and only in the column whose header is
`item'.  START is just after the cell's opening bar, END just before its
closing bar or at end of line."
  (save-excursion
    (let* ((pt (point))
           (bol (line-beginning-position))
           (eol (line-end-position))
           (line (a3madkour-ingredients--current-line))
           (bars 0) (cell-start nil) (first-row nil) (header-pos nil))
      (when (and (string-match-p "\\`[ \t]*|" line)
                 (not (a3madkour-ingredients--rule-line-p line)))
        (goto-char bol)
        (while (search-forward "|" pt t)
          (cl-incf bars)
          (setq cell-start (point)))
        (when cell-start
          ;; Top of this table, then its header (the first row that is not a rule).
          (goto-char bol)
          (setq first-row bol)
          (while (and (= 0 (forward-line -1)) (looking-at "[ \t]*|"))
            (setq first-row (point)))
          (goto-char first-row)
          (while (and (< (point) bol)
                      (a3madkour-ingredients--rule-line-p
                       (a3madkour-ingredients--current-line)))
            (forward-line 1))
          (setq header-pos (point))
          (when (and (< header-pos bol)
                     (string= "item"
                              (downcase
                               (or (nth (1- bars)
                                        (a3madkour-ingredients--row-cells
                                         (a3madkour-ingredients--current-line)))
                                   ""))))
            ;; The nearest heading above the table.
            (goto-char first-row)
            (while (and (= 0 (forward-line -1)) (not (looking-at "\\*+ "))))
            (when (a3madkour-ingredients--ingredients-heading-p
                   (a3madkour-ingredients--current-line))
              (goto-char pt)
              (cons cell-start
                    (if (search-forward "|" eol t) (1- (point)) eol)))))))))

(defun a3madkour-ingredients--item-at-point ()
  "The text of the recipe `item' cell at point, or nil."
  (let ((cell (a3madkour-ingredients--item-cell)))
    (when cell
      (let ((text (string-trim (buffer-substring-no-properties (car cell) (cdr cell)))))
        (unless (string-empty-p text) text)))))

(defun a3madkour-ingredients/capf ()
  "Complete registry names and aliases in a recipe table's `item' column.
Returns nil anywhere else, so other completion sources are untouched."
  (when a3madkour-ingredients/file
    (let ((cell (a3madkour-ingredients--item-cell)))
      (when cell
        (let* ((end (point))
               (start (save-excursion
                        (goto-char (car cell))
                        (skip-chars-forward " \t" end)
                        (point)))
               (aisle-of (make-hash-table :test #'equal)))
          (dolist (e (a3madkour-ingredients/entries))
            (dolist (n (cons (plist-get e :name) (plist-get e :aliases)))
              (puthash n (plist-get e :aisle) aisle-of)))
          (list start end (hash-table-keys aisle-of)
                :annotation-function
                (lambda (candidate)
                  (let ((aisle (gethash candidate aisle-of)))
                    (and aisle (concat "  " aisle))))
                :exclusive 'no))))))

(defun a3madkour-ingredients/setup-capf ()
  "Offer ingredient completion in this buffer.  For `org-mode-hook'."
  (add-hook 'completion-at-point-functions #'a3madkour-ingredients/capf nil t))

;;; Commands

(defconst a3madkour-ingredients--state-names
  '(("out" . out) ("have" . have) ("low" . low) ("untracked" . nil))
  "What the state prompt offers, in order; \"out\" is the default.")

(defun a3madkour-ingredients--prompt-and-add (&optional initial)
  "Prompt for a new ingredient, its name starting as INITIAL, and add it."
  (let* ((name (read-string "Ingredient: " initial))
         (aisle (completing-read "Aisle: " (a3madkour-ingredients/aisles)))
         (aliases (a3madkour-ingredients--split-aliases
                   (read-string "Other names (comma-separated, optional): ")))
         (unit (read-string "Usual unit (optional): "))
         (state (completing-read "State (default out): "
                                 (mapcar #'car a3madkour-ingredients--state-names)
                                 nil t nil nil "out")))
    (a3madkour-ingredients/add-entry
     name aisle aliases unit
     (cdr (assoc state a3madkour-ingredients--state-names)))))

(defun a3-ingredient-add ()
  "Add an ingredient to the registry.
In a recipe's Ingredients table, the name starts as the item at point."
  (interactive)
  (let ((entry (a3madkour-ingredients--prompt-and-add
                (a3madkour-ingredients--item-at-point))))
    (message "Added %s to %s" (plist-get entry :name) (plist-get entry :aisle))))

(defun a3-ingredient-set-state ()
  "Pick an ingredient and mark it have, low, out or untracked."
  (interactive)
  (let* ((names (mapcar (lambda (e) (plist-get e :name)) (a3madkour-ingredients/entries)))
         (name (completing-read "Ingredient: " names nil t))
         (choice (read-multiple-choice
                  (format "%s is" name)
                  '((?h "have") (?l "low") (?o "out") (?u "untracked"))))
         (state (cdr (assoc (cadr choice) a3madkour-ingredients--state-names))))
    (a3madkour-ingredients/set-entry-state name state)
    (message "%s: %s" name (cadr choice))))

(defun a3-ingredient-resolve-recipe ()
  "Walk this recipe's ingredients that are not in the registry.
Each can be added as a new ingredient, recorded as another name for an
existing one, or skipped."
  (interactive)
  (let* ((unknown (a3madkour-ingredients/unknown-items))
         (total (length unknown))
         (resolved 0))
    (if (null unknown)
        (message "All ingredients are in the registry")
      (catch 'quit
        (dolist (item unknown)
          ;; An earlier answer may have covered this one (as an alias).
          (if (a3madkour-ingredients/lookup item)
              (cl-incf resolved)
            (condition-case err
                (pcase (car (read-multiple-choice
                             (format "\"%s\" is not in the registry" item)
                             '((?a "add as new") (?l "alias of existing")
                               (?s "skip") (?q "quit"))))
                  (?a (a3madkour-ingredients--prompt-and-add item)
                      (cl-incf resolved))
                  (?l (a3madkour-ingredients/add-alias
                       (completing-read
                        "Alias of: "
                        (mapcar (lambda (e) (plist-get e :name))
                                (a3madkour-ingredients/entries))
                        nil t)
                       item)
                      (cl-incf resolved))
                  (?q (throw 'quit nil)))
              ;; A refused name (say, a clash) skips that one item only.
              (user-error (message "%s" (error-message-string err))
                          (sit-for 1.5))))))
      (message "Resolved %d of %d ingredients" resolved total))))

(provide 'a3madkour-ingredients)
;;; a3madkour-ingredients.el ends here
