;;; a3madkour-publish-multi-pdf.el --- D.2 PDF backend (ox-latex + xelatex + biber) -*- lexical-binding: t; -*-

;;; Commentary:

;; D.2 PDF backend. Wraps ox-latex export + xelatex/biber compile loop.
;; Tool paths come from defcustoms in the `a3madkour-pub-multi' group.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish-multi-filter)

(defgroup a3madkour-pub-multi nil
  "D.2 multi-target export pipeline." :group 'org)

(defcustom a3madkour-pub-multi-xelatex-command "xelatex"
  "External `xelatex' command name or absolute path."
  :type 'string :group 'a3madkour-pub-multi)

(defcustom a3madkour-pub-multi-biber-command "biber"
  "External `biber' command name or absolute path."
  :type 'string :group 'a3madkour-pub-multi)

(defcustom a3madkour-pub-multi-rsvg-convert-command "rsvg-convert"
  "External `rsvg-convert' command name or absolute path."
  :type 'string :group 'a3madkour-pub-multi)

(defun a3madkour-pub-multi-pdf--probe-tools ()
  "Return list of missing required commands (xelatex/biber/rsvg-convert), or nil if all present."
  (let (missing)
    (dolist (cmd (list a3madkour-pub-multi-xelatex-command
                       a3madkour-pub-multi-biber-command
                       a3madkour-pub-multi-rsvg-convert-command))
      (unless (executable-find cmd)
        (push cmd missing)))
    (nreverse missing)))

(provide 'a3madkour-publish-multi-pdf)
;;; a3madkour-publish-multi-pdf.el ends here
