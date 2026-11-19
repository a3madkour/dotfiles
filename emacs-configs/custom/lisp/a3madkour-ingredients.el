;;; a3madkour-ingredients.el --- shared ingredient registry  -*- lexical-binding: t; -*-

;;; Commentary:

;; One org file names every ingredient once, as a flat list: each level-1
;; heading is an ingredient and its text is the canonical name.  Deeper
;; headings are notes and are ignored.  An ingredient's state is an org tag on
;; its heading (:have:, :low: or :out:; none = untracked), so the heading's
;; TODO keyword stays free for ordinary use.  Its other names and usual unit
;; are the :ALIASES: and :UNIT: properties.
;;
;; Tags are otherwise open.  An optional header line names the tags that are
;; store aisles, in the order the store is walked:
;;
;;   #+TAGS: [ aisle : produce dairy oils_vinegar ]
;;
;; An ingredient's aisle is the first of those it carries.  The line restricts
;; nothing; it only tells the grocery list what to group by and in what order.
;;
;; Recipes, the pantry and the grocery list all refer to ingredients through
;; `a3madkour-ingredients/lookup'.  This module depends on nothing but org, so
;; non-publishing code can use it.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ucs-normalize)
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
  '(("have" . have) ("low" . low) ("out" . out))
  "State tag → state symbol.  Tags are matched without regard to case.")

(defconst a3madkour-ingredients--foreign-keywords
  '("TODO" "NEXT" "WAIT" "DONE" "DROP" "HAVE" "LOW" "OUT")
  "Keywords that must not start an ingredient's name.
State is a tag, never a keyword; a heading that starts with one of these
would be read as part of the name.")

(defun a3madkour-ingredients--leading-keyword (name)
  "The keyword NAME starts with, when more text follows it, or nil.
Case-sensitive, and only real keywords count: \"BBQ sauce\" has none."
  (let ((case-fold-search nil))
    (when (string-match "\\`\\([^ \t]+\\)[ \t]+[^ \t]" name)
      (car (member (match-string 1 name)
                   a3madkour-ingredients--foreign-keywords)))))

(defvar a3madkour-ingredients--cache nil
  "(KEY . PARSED) for the last registry read; see `a3madkour-ingredients--parsed'.")

(defun a3madkour-ingredients/normalize (string)
  "Return STRING downcased, trimmed, with inner whitespace runs collapsed.
Accented letters are composed first, so text that arrives decomposed (a paste
from some phones and websites) matches the same name typed normally."
  (downcase (string-join (split-string (ucs-normalize-NFC-string (or string ""))
                                       "[[:space:]]+" t)
                         " ")))

;;; Parsing

(defun a3madkour-ingredients--strip-tags (title)
  "Return heading TITLE without trailing org tags, trimmed."
  (string-trim
   (replace-regexp-in-string "[ \t]+:[[:alnum:]_@#%:]+:[ \t]*\\'" "" title)))

(defun a3madkour-ingredients--heading-tags (heading)
  "The org tags at the end of HEADING, as a list of strings."
  (when (string-match "[ \t]+:\\([[:alnum:]_@#%:]+\\):[ \t]*\\'" heading)
    (split-string (match-string 1 heading) ":" t)))

(defun a3madkour-ingredients--state-tag-p (tag)
  "Non-nil when TAG is one of the state tags, in any case."
  (assoc (downcase tag) a3madkour-ingredients--states))

(defun a3madkour-ingredients--split-aliases (value)
  "Split a comma-separated :ALIASES: VALUE, dropping empty pieces."
  (split-string (or value "") "," t "[[:space:]]+"))

(defun a3madkour-ingredients--aisle-group-tags (line)
  "The members of every `aisle' tag group on #+TAGS: LINE, in order.
A group is [ aisle : a b ] or { aisle : a b }; a member's (k) fast-select
suffix is dropped.  Nil for any other line."
  (let ((case-fold-search t) (start 0) (out '()))
    (when (string-match "\\`[ \t]*#\\+TAGS:" line)
      (while (string-match "[[{][ \t]+aisle[ \t]*:\\([^]}]*\\)[]}]" line start)
        (setq start (match-end 0))
        (dolist (tag (split-string (match-string 1 line) "[ \t]+" t))
          (push (replace-regexp-in-string "(.)\\'" "" tag) out))))
    (nreverse out)))

(defun a3madkour-ingredients--tag-member (tag tags)
  "The element of TAGS equal to TAG without regard to case, or nil."
  (car (cl-member tag tags :test (lambda (a b) (string= (downcase a) (downcase b))))))

(defun a3madkour-ingredients--parse (text)
  "Parse registry TEXT.  Return a plist (:entries LIST :aisles LIST).
The state is read from the heading's tags as written, so the result does not
depend on the session's settings.  :aisles is what the file's aisle lines
name, in order."
  (let ((case-fold-search nil)
        (line 0) (aisles '()) (entries '())
        (current nil) (in-drawer nil) (found nil))
    (cl-flet ((finish ()
                (when current (push current entries) (setq current nil))
                (setq in-drawer nil)))
      (dolist (l (split-string text "\n"))
        (cl-incf line)
        (cond
         ((setq found (a3madkour-ingredients--aisle-group-tags l))
          (dolist (tag found)
            (unless (a3madkour-ingredients--tag-member tag aisles)
              (setq aisles (append aisles (list tag))))))
         ((string-match "\\`\\* +\\(.*\\)\\'" l)
          (finish)
          (let* ((raw (match-string 1 l))
                 (title (a3madkour-ingredients--strip-tags raw))
                 (tags (a3madkour-ingredients--heading-tags raw))
                 (state-tags (cl-remove-if-not
                              #'a3madkour-ingredients--state-tag-p tags))
                 (state (and state-tags
                             (cdr (a3madkour-ingredients--state-tag-p
                                   (car state-tags))))))
            (unless (string-empty-p title)
              (setq current (list :name title :aliases nil :aisle nil
                                  :unit nil :state state :line line
                                  :tags tags
                                  :state-tags (length state-tags))))))
         ;; A deeper heading is a note: it ends the ingredient above it.
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
    ;; The aisle lines may sit anywhere, so aisles are settled last: an
    ;; ingredient's aisle is the first aisle, in aisle-line order, it carries.
    (dolist (e entries)
      (plist-put e :aisle
                 (cl-find-if (lambda (a) (a3madkour-ingredients--tag-member
                                          a (plist-get e :tags)))
                             aisles)))
    (list :entries (nreverse entries) :aisles aisles)))

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
Each is a plist (:name :aliases :aisle :unit :state :line :tags).  :state is
`have', `low', `out' or nil (untracked); :tags is every tag on the heading;
:aisle is the first aisle tag among them, or nil.  Nil when the registry is
unset or missing."
  (plist-get (a3madkour-ingredients--parsed) :entries))

(defun a3madkour-ingredients/aisles ()
  "The aisle tags the registry's aisle lines name, in order."
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
          (dolist (n (cons name (plist-get e :aliases)))
            (let* ((norm (a3madkour-ingredients/normalize n))
                   (first (gethash norm seen)))
              (if first
                  (emit "duplicate name %S (also line %d)" norm first)
                (puthash norm line seen))))
          (let ((keyword (a3madkour-ingredients--leading-keyword name)))
            (when keyword
              (emit "%S is a keyword, not part of a name; mark state with a tag (:have:, :low: or :out:)"
                    keyword)))
          (when (> (or (plist-get e :state-tags) 0) 1)
            (emit "ingredient %S has more than one state tag" name)))))
    (nreverse out)))

;;; Editing the registry

(defconst a3madkour-ingredients--header
  "#+TITLE: Ingredients\n#+TAGS: { have(h) low(l) out(o) }\n\n"
  "What a new registry file starts with.
The braces make the three state tags one mutually exclusive group, so org's
tag command (\\[org-set-tags-command]) sets a state with h, l or o and
replaces the previous one.")

(defun a3madkour-ingredients--state-tag (state)
  "The tag for STATE (`have', `low', `out'), or nil for untracked."
  (car (rassq state a3madkour-ingredients--states)))

(defmacro a3madkour-ingredients--editing (&rest body)
  "Run BODY in the registry's buffer, widened, then save it.
The buffer is the one visiting the file, so an open registry stays current.  If
the file changed on disk under an unmodified buffer (a sync), the buffer is
reverted first, so BODY never edits stale text.  If the buffer has unsaved
edits as well, neither side can be dropped safely: refuse, and leave both."
  (declare (indent 0))
  `(let ((file (or a3madkour-ingredients/file
                   (user-error "a3madkour-ingredients/file is not set"))))
     (make-directory (file-name-directory file) t)
     ;; `find-file-noselect' would ask "reread from disk?" about a buffer whose
     ;; file changed underneath it; take the existing buffer and decide here.
     (with-current-buffer (or (get-file-buffer file) (find-file-noselect file))
       (when (and (file-exists-p file)
                  (not (verify-visited-file-modtime (current-buffer))))
         (when (buffer-modified-p)
           (user-error "The registry buffer has unsaved changes and the file changed on disk; save or revert it first"))
         (revert-buffer t t t))
       (prog1 (save-excursion (save-restriction (widen) ,@body))
         (save-buffer)))))

(defun a3madkour-ingredients--refuse-if-known (string)
  "Signal a `user-error' when STRING is already a name or alias."
  (let ((e (a3madkour-ingredients/lookup string)))
    (when e
      (user-error "\"%s\" is already in the registry as \"%s\"%s"
                  string (plist-get e :name)
                  (if (plist-get e :aisle)
                      (format " (%s)" (plist-get e :aisle))
                    "")))))

(defun a3madkour-ingredients--check-name (name)
  "Signal a `user-error' when NAME would not read back as written."
  (cond
   ((string-empty-p name) (user-error "Ingredient name is empty"))
   ((string-match-p "\n" name)
    (user-error "An ingredient name cannot span lines: %S" name))
   ((not (string= name (a3madkour-ingredients--strip-tags name)))
    (user-error "\"%s\" ends in what org would read as a tag" name))
   ((a3madkour-ingredients--leading-keyword name)
    (user-error "\"%s\" starts with the keyword %s; write it in lower case"
                name (a3madkour-ingredients--leading-keyword name)))))

(defun a3madkour-ingredients--check-alias (alias)
  "Signal a `user-error' when ALIAS could not be stored in :ALIASES:."
  (cond
   ((string-empty-p alias) (user-error "Alias is empty"))
   ((string-match-p "," alias)
    (user-error "An alias cannot contain a comma: \"%s\"" alias))
   ((string-match-p "\n" alias)
    (user-error "An alias cannot span lines: %S" alias))))

(defun a3madkour-ingredients--entry-or-error (name)
  "The entry for NAME, or a `user-error'."
  (or (a3madkour-ingredients/lookup name)
      (user-error "No ingredient \"%s\" in the registry" name)))

(defun a3madkour-ingredients--goto-line (line)
  (goto-char (point-min))
  (forward-line (1- line)))

(defun a3madkour-ingredients--aisle-tag (string)
  "STRING as an org tag, or nil when nothing of it can be one.
Trimmed and downcased, with every run of characters a tag cannot hold turned
into one underscore: \"Oils & vinegar\" is \"oils_vinegar\"."
  (let ((tag (replace-regexp-in-string
              "\\`_+\\|_+\\'" ""
              (replace-regexp-in-string "[^[:alnum:]_@#%]+" "_"
                                        (downcase (or string ""))))))
    (unless (string-empty-p tag) tag)))

(defun a3madkour-ingredients--declare-aisle (tag)
  "Put TAG at the end of the buffer's aisle line, writing one when missing.
A new aisle line goes after the last #+TAGS: line, or first in the buffer."
  (let ((case-fold-search t))
    (goto-char (point-max))
    (cond
     ((re-search-backward
       "^[ \t]*#\\+TAGS:.*[[{][ \t]+aisle[ \t]*:[^]}\n]*\\([]}]\\)" nil t)
      (goto-char (match-beginning 1))
      (skip-chars-backward " \t")
      (insert " " tag)
      (unless (looking-at-p "[ \t]") (insert " ")))
     ((re-search-backward "^[ \t]*#\\+TAGS:.*$" nil t)
      (goto-char (match-end 0))
      (insert "\n#+TAGS: [ aisle : " tag " ]"))
     (t
      (goto-char (point-min))
      (insert "#+TAGS: [ aisle : " tag " ]\n")))))

(defun a3madkour-ingredients/add-entry (name &optional aisle aliases unit state)
  "Add ingredient NAME at the end of the registry and save.  Return its entry.
AISLE is free text, stored as a tag (see `a3madkour-ingredients--aisle-tag')
and added to the aisle line when new; nil or empty means no aisle.  ALIASES is
a list of strings, UNIT a string, STATE `have', `low', `out' or nil
\(untracked).  Creates the registry when it does not exist.  Refuses a NAME or
alias that the registry already knows."
  (a3madkour-ingredients--editing
    (let* ((name (string-trim (or name "")))
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
           (state-tag (a3madkour-ingredients--state-tag state))
           (aisle-tag (a3madkour-ingredients--aisle-tag aisle))
           (header-changed nil))
      (a3madkour-ingredients--check-name name)
      (mapc #'a3madkour-ingredients--check-alias aliases)
      (mapc #'a3madkour-ingredients--refuse-if-known (cons name aliases))
      (when (= (point-min) (point-max))
        (insert a3madkour-ingredients--header)
        (setq header-changed t))
      (when aisle-tag
        (let ((known (a3madkour-ingredients--tag-member
                      aisle-tag (a3madkour-ingredients/aisles))))
          (if known
              ;; Write the aisle the way the aisle line spells it.
              (setq aisle-tag known)
            (a3madkour-ingredients--declare-aisle aisle-tag)
            (setq header-changed t))))
      ;; The buffer was set up before these #+TAGS: lines existed; teach it
      ;; now so org's tag command offers them straight away.
      (when (and header-changed (derived-mode-p 'org-mode))
        (org-set-regexps-and-options))
      (goto-char (point-max))
      (unless (or (bobp) (bolp)) (insert "\n"))
      (let ((tags (delq nil (list state-tag aisle-tag))))
        (insert "* " name
                (if tags (concat " :" (string-join tags ":") ":") "")
                "\n"))
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
      (a3madkour-ingredients--check-alias alias)
      (unless (and holder (= (plist-get holder :line) (plist-get entry :line)))
        (a3madkour-ingredients--refuse-if-known alias)
        (let ((value (string-join (append (plist-get entry :aliases) (list alias)) ", "))
              (case-fold-search t))
          (a3madkour-ingredients--goto-line (plist-get entry :line))
          (forward-line 1)
          ;; The heading may be the file's last line, with no newline after it.
          (unless (bolp) (insert "\n"))
          ;; Only a drawer that directly follows the heading (after an optional
          ;; planning line) is its property drawer; anything further down is
          ;; body text and is left alone.
          (let ((after-heading (point)))
            (when (looking-at-p "[ \t]*\\(?:SCHEDULED\\|DEADLINE\\|CLOSED\\):")
              (forward-line 1))
            (if (not (looking-at "\\([ \t]*\\):PROPERTIES:[ \t]*$"))
                (progn (goto-char after-heading)
                       (insert ":PROPERTIES:\n:ALIASES: " value "\n:END:\n"))
              (let ((indent (match-string 1))
                    (end (save-excursion
                           (and (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                                (match-beginning 0)))))
                (forward-line 1)
                (if (and end (save-excursion
                               (re-search-forward "^[ \t]*:ALIASES:.*$" end t)))
                    (progn (goto-char (match-beginning 0))
                           (delete-region (point) (line-end-position))
                           (insert indent ":ALIASES: " value))
                  (insert indent ":ALIASES: " value "\n")))))))
      (setq name (plist-get entry :name))))
  (a3madkour-ingredients/lookup name))

(defun a3madkour-ingredients/set-entry-state (name state)
  "Set ingredient NAME to STATE (`have', `low', `out', nil = untracked) and save.
Return the entry.  The state tag on the heading is replaced; its other tags,
its TODO keyword and its name are left alone."
  (a3madkour-ingredients--editing
    (let ((entry (a3madkour-ingredients--entry-or-error name))
          (tag (a3madkour-ingredients--state-tag state)))
      (a3madkour-ingredients--goto-line (plist-get entry :line))
      (let* ((line (a3madkour-ingredients--current-line))
             (others (cl-remove-if #'a3madkour-ingredients--state-tag-p
                                   (a3madkour-ingredients--heading-tags line)))
             (tags (if tag (cons tag others) others))
             (head (string-trim-right
                    (replace-regexp-in-string
                     "[ \t]+:[[:alnum:]_@#%:]+:[ \t]*\\'" "" line))))
        (delete-region (line-beginning-position) (line-end-position))
        (insert head (if tags (concat " :" (string-join tags ":") ":") "")))
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
          ;; Case-insensitive, and exclusive: in an item cell the registry is
          ;; the only sensible source, so a miss must not fall through to
          ;; dabbrev and friends.
          (list start end
                (completion-table-case-fold (hash-table-keys aisle-of))
                ;; Corfu's automatic popup waits for `corfu-auto-prefix'
                ;; (three) letters; here one is enough.
                :company-prefix-length (> end start)
                :annotation-function
                (lambda (candidate)
                  (let ((aisle (gethash candidate aisle-of)))
                    (and aisle (concat "  " aisle))))))))))

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
         (aisle (completing-read "Aisle (optional): " (a3madkour-ingredients/aisles)))
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
    (if (plist-get entry :aisle)
        (message "Added %s to %s" (plist-get entry :name) (plist-get entry :aisle))
      (message "Added %s" (plist-get entry :name)))))

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
                             ;; With nothing in the registry there is nothing
                             ;; to be another name for.
                             (if (a3madkour-ingredients/entries)
                                 '((?a "add as new") (?l "alias of existing")
                                   (?s "skip") (?q "quit"))
                               '((?a "add as new") (?s "skip") (?q "quit")))))
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
