;;; a3madkour-groceries.el --- the grocery list  -*- lexical-binding: t; -*-

;;; Commentary:

;; One standing org file, groceries.org beside the ingredient registry, to
;; shop from in Emacs on the phone.  It is plain org: checkbox lines under one
;; heading per aisle, then "Other" (ingredients with no aisle) and "Extra".
;;
;; `a3-grocery-list' rebuilds the aisle sections from the registry (every
;; ingredient tagged :out: or :low:), keeping ticks.  "Extra" belongs to the
;; owner: what is typed there is carried over untouched, and anything typed
;; elsewhere that is not a current item is moved there rather than dropped.
;; `a3-grocery-done' closes a trip: ticked items that are ingredients become
;; :have:, and every ticked line leaves the list.
;;
;; The registry is read through `a3madkour-ingredients/entries' and
;; `a3madkour-ingredients/aisles' and written only through
;; `a3madkour-ingredients/set-entry-state'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'a3madkour-ingredients)

(defconst a3madkour-groceries--other "Other"
  "Heading for ingredients that carry no aisle tag.")
(defconst a3madkour-groceries--extra "Extra"
  "Heading of the section the owner types into; always last.")

(defconst a3madkour-groceries--checkbox-re
  "\\`\\([ \t]*\\)- \\[\\([ Xx-]\\)\\] +\\(.*?\\)[ \t]*\\'"
  "A checkbox line: indentation, the mark, the text.")

(defun a3madkour-groceries/file ()
  "The grocery list's path: groceries.org beside the ingredient registry."
  (expand-file-name
   "groceries.org"
   (file-name-directory
    (or a3madkour-ingredients/file
        (user-error "a3madkour-ingredients/file is not set")))))

(defun a3madkour-groceries/conflict-files ()
  "Sync-conflict copies of the grocery list.  Listed only, never touched."
  (let ((dir (file-name-directory (a3madkour-groceries/file))))
    (when (file-directory-p dir)
      (directory-files dir t "\\`groceries\\.sync-conflict-"))))

(defun a3madkour-groceries--heading (aisle)
  "The heading shown for AISLE tag: \"oils_vinegar\" is \"Oils vinegar\"."
  (let ((name (replace-regexp-in-string "_+" " " aisle)))
    (setq name (concat (upcase (substring name 0 1)) (substring name 1)))
    ;; An aisle must not pass for the owner's section.
    (if (string= (downcase name) (downcase a3madkour-groceries--extra))
        (concat name " (aisle)")
      name)))

(defun a3madkour-groceries--item-name (text)
  "The ingredient a checkbox's TEXT names: TEXT without a \" (low)\" suffix."
  (string-trim (replace-regexp-in-string "[ \t]*(low)\\'" "" text)))

(defun a3madkour-groceries--ticked-p (mark)
  (member mark '("X" "x")))

(defun a3madkour-groceries--parse (text)
  "Parse grocery list TEXT.
Return a plist: :ticked, the registry names of ticked items outside Extra;
:extra, Extra's lines as written; :strays, lines outside Extra that are not a
checkbox naming a registry ingredient."
  (let ((in-extra nil) (ticked '()) (extra '()) (strays '()))
    (dolist (l (split-string text "\n"))
      (cond
       ((string-match "\\`\\* +\\(.*?\\)[ \t]*\\'" l)
        (setq in-extra (string= (match-string 1 l) a3madkour-groceries--extra)))
       (in-extra (push l extra))
       ((string-match-p "\\`[ \t]*\\'" l))
       ((string-match-p "\\`#\\+" l))
       ((string-match a3madkour-groceries--checkbox-re l)
        (let* ((mark (match-string 2 l))
               (entry (a3madkour-ingredients/lookup
                       (a3madkour-groceries--item-name (match-string 3 l)))))
          (cond ((null entry) (push l strays))
                ((a3madkour-groceries--ticked-p mark)
                 (push (plist-get entry :name) ticked)))))
       (t (push l strays))))
    ;; Blank lines at the end of Extra are padding, not content.
    (while (and extra (string-match-p "\\`[ \t]*\\'" (car extra)))
      (pop extra))
    (list :ticked ticked :extra (nreverse extra) :strays (nreverse strays))))

(defun a3madkour-groceries--render (old)
  "The grocery list's text, built from the registry and OLD, a parsed list."
  (let* ((needed (cl-remove-if-not
                  (lambda (e) (memq (plist-get e :state) '(out low)))
                  (a3madkour-ingredients/entries)))
         (ticked (plist-get old :ticked))
         (sections (append (mapcar (lambda (a) (cons a (a3madkour-groceries--heading a)))
                                   (a3madkour-ingredients/aisles))
                           (list (cons nil a3madkour-groceries--other)))))
    (with-temp-buffer
      (insert "#+TITLE: Groceries\n\n")
      (dolist (section sections)
        (let ((items (cl-remove-if-not
                      (lambda (e) (equal (plist-get e :aisle) (car section)))
                      needed)))
          (when items
            (insert "* " (cdr section) "\n")
            (dolist (e items)
              (insert "- [" (if (member (plist-get e :name) ticked) "X" " ") "] "
                      (plist-get e :name)
                      (if (eq (plist-get e :state) 'low) " (low)" "")
                      "\n")))))
      (insert "* " a3madkour-groceries--extra "\n")
      (dolist (l (append (plist-get old :extra) (plist-get old :strays)))
        (insert l "\n"))
      (buffer-string))))

(defun a3madkour-groceries--count (text)
  "(:to-buy N :ticked M): TEXT's unticked and ticked checkbox lines."
  (let ((to-buy 0) (ticked 0))
    (dolist (l (split-string text "\n"))
      (when (string-match a3madkour-groceries--checkbox-re l)
        (if (a3madkour-groceries--ticked-p (match-string 2 l))
            (cl-incf ticked)
          (cl-incf to-buy))))
    (list :to-buy to-buy :ticked ticked)))

(defun a3madkour-groceries--buffer ()
  "The buffer visiting the grocery list, holding the newest text there is.
Ticks synced in from the phone under an unmodified buffer are reverted in.
Unsaved edits plus a newer file cannot both be kept: refuse."
  (let* ((file (a3madkour-groceries/file))
         (buf (or (get-file-buffer file)
                  (progn (make-directory (file-name-directory file) t)
                         (find-file-noselect file)))))
    (with-current-buffer buf
      (when (and (file-exists-p file)
                 (not (verify-visited-file-modtime buf)))
        (when (buffer-modified-p)
          (user-error "The grocery list has unsaved changes and the file changed on disk; save or revert it first"))
        (revert-buffer t t t)))
    buf))

(defun a3madkour-groceries--rewrite (transform)
  "Replace the list's text with (TRANSFORM old-text), save, return the new text."
  (with-current-buffer (a3madkour-groceries--buffer)
    (save-restriction
      (widen)
      (let* ((old (buffer-substring-no-properties (point-min) (point-max)))
             (new (funcall transform old)))
        (unless (string= old new)
          (let ((line (line-number-at-pos)))
            (erase-buffer)
            (insert new)
            (goto-char (point-min))
            (forward-line (1- line))))
        (when (or (buffer-modified-p) (not (file-exists-p (buffer-file-name))))
          (set-buffer-modified-p t)
          (save-buffer))
        new))))

(defun a3madkour-groceries/refresh ()
  "Rebuild the grocery list from the registry and save it.
Return (:to-buy N :ticked M), counting every checkbox line on the list."
  (a3madkour-groceries--count
   (a3madkour-groceries--rewrite
    (lambda (old)
      (a3madkour-groceries--render (a3madkour-groceries--parse old))))))

(defun a3madkour-groceries--conflict-note ()
  "\"; sync conflict copy: FILE\" when there is one, else the empty string."
  (let ((copies (a3madkour-groceries/conflict-files)))
    (if copies (concat "; sync conflict copy: " (car copies)) "")))

;;;###autoload
(defun a3-grocery-list ()
  "Refresh the grocery list from the pantry and open it."
  (interactive)
  (let ((counts (a3madkour-groceries/refresh)))
    (switch-to-buffer (a3madkour-groceries--buffer))
    (message "%s%s"
             (if (and (= 0 (plist-get counts :to-buy)) (= 0 (plist-get counts :ticked)))
                 "Nothing to buy"
               (format "%d to buy, %d ticked"
                       (plist-get counts :to-buy) (plist-get counts :ticked)))
             (a3madkour-groceries--conflict-note))))

;;;###autoload
(defun a3-grocery-done ()
  "Close the shopping trip.
Ticked items that are registry ingredients become :have:; every ticked line
leaves the list; the list is then refreshed."
  (interactive)
  (let* ((text (with-current-buffer (a3madkour-groceries--buffer)
                 (save-restriction
                   (widen)
                   (buffer-substring-no-properties (point-min) (point-max)))))
         (bought '()) (ticked 0))
    (dolist (l (split-string text "\n"))
      (when (and (string-match a3madkour-groceries--checkbox-re l)
                 (a3madkour-groceries--ticked-p (match-string 2 l)))
        (cl-incf ticked)
        (let ((entry (a3madkour-ingredients/lookup
                      (a3madkour-groceries--item-name (match-string 3 l)))))
          (when entry (cl-pushnew (plist-get entry :name) bought :test #'string=)))))
    (cond
     ((= 0 ticked) (message "Nothing is ticked"))
     ((y-or-n-p (format "Mark %d ticked item%s as bought? "
                        ticked (if (= 1 ticked) "" "s")))
      (dolist (name bought)
        (a3madkour-ingredients/set-entry-state name 'have))
      (a3madkour-groceries--rewrite
       (lambda (old)
         (mapconcat
          #'identity
          (cl-remove-if
           (lambda (l)
             (and (string-match a3madkour-groceries--checkbox-re l)
                  (a3madkour-groceries--ticked-p (match-string 2 l))))
           (split-string old "\n"))
          "\n")))
      (let ((counts (a3madkour-groceries/refresh)))
        (message "Marked %d as have; %d still to buy%s"
                 (length bought) (plist-get counts :to-buy)
                 (a3madkour-groceries--conflict-note)))))))

(provide 'a3madkour-groceries)
;;; a3madkour-groceries.el ends here
