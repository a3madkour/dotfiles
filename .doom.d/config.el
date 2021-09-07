;; [[file:config.org::*Basic Configuration][Basic Configuration:1]]
;; ;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-
;; Basic Configuration:1 ends here

;; [[file:config.org::*Personal Information][Personal Information:1]]
;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "Abdelrahman Madkour"
      user-mail-address "a3madkour@gmail.com")
;; Personal Information:1 ends here

;; [[file:config.org::*Personal Information][Personal Information:2]]

;; Personal Information:2 ends here

;; [[file:config.org::*Font Face][Font Face:1]]
;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
(setq doom-font (font-spec :family "monospace" :size 14))
;; Font Face:1 ends here

;; [[file:config.org::*Theme and modeline][Theme and modeline:1]]
;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-monokai-classic)
;; Theme and modeline:1 ends here

;; [[file:config.org::*Miscellaneous][Miscellaneous:1]]
;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)

;; (global-display-line-numbers-mode 't)

; Disable line numbers for some modes
;; (dolist (mode '(term-mode-hook
;; 		shell-mode-hook
;;         org-mode-hook
;; 		eshell-mode-hook))
;;   (add-hook mode (lambda () (display-line-numbers-mode 0))))
;; Miscellaneous:1 ends here

;; [[file:config.org::*Systemd daemon][Systemd daemon:1]]
;; (defun greedily-do-daemon-setup ()
;;   (require 'org)
;;   (when (require 'mu4e nil t)
;;     (setq mu4e-confirm-quit t)
;;     (setq +mu4e-lock-greedy t)
;;     (setq +mu4e-lock-relaxed t)
;;     (+mu4e-lock-add-watcher)
;;     (when (+mu4e-lock-available t)
;;       (mu4e~start)))
;;   (when (require 'elfeed nil t)
;;     (run-at-time nil (* 8 60 60) #'elfeed-update)))

;; (when (daemonp)
;;   (add-hook 'emacs-startup-hook #'greedily-do-daemon-setup))
;; Systemd daemon:1 ends here

;; [[file:config.org::*Window management][Window management:1]]
(setq split-height-threshold nil)
(setq split-width-threshold 0)
;; Window management:1 ends here

;; [[file:config.org::*Eshell git prompt][Eshell git prompt:2]]
(after! eshell
          (eshell-git-prompt-use-theme 'powerline)
)
;; Eshell git prompt:2 ends here

;; [[file:config.org::*Spotify][Spotify:2]]
(use-package! smudge
  :config
  (setq smudge-oauth2-client-id "48e1012bfd264c129bf0c89966817aca"
    smudge-oauth2-client-secret "e6c298a6bf1343f1a3b05253c252af16")
)
;; Spotify:2 ends here

;; [[file:config.org::*Treemacs][Treemacs:1]]
(add-hook! treemacs-mode
  (treemacs-load-theme "doom-colors")
  )
;; Treemacs:1 ends here

;; [[file:config.org::*Command Log][Command Log:2]]
(use-package! command-log-mode)
;; Command Log:2 ends here

;; [[file:config.org::*Core][Core:2]]
;; (defun a3madkour/run-in-background (command)
;;   (let ((command-parts (split-string command "[ ]+")))
;;     (apply #'call-process `(,(car command-parts) nil 0 nil ,@(cdr command-parts)))))

;; ;; (defun a3madkour/set-wallpaper ()
;; ;;   (interactive)
;; ;;   ;; NOTE: You will need to update this to a valid background path!
;; ;;   (start-process-shell-command
;; ;;    "feh" nil  "feh --bg-scale /usr/share/backgrounds/matt-mcnulty-nyc-2nd-ave.jpg"))

;; (defun a3madkour/exwm-init-hook ()
;;   ;; Make workspace 1 be the one where we land at startup
;;   (exwm-workspace-switch-create 0)

;;   ;; Open eshell by default
;;   ;;(eshell)

;;   ;; Show battery status in the mode line
;;   (display-battery-mode 1)

;;   ;; Show the time and date in modeline
;;   ;; (setq display-time-day-and-date t)
;;   ;; (display-time-mode 1)
;;   ;; Also take a look at display-time-format and format-time-string

;;   (a3madkour/start-panel)
;;   ;; Launch apps that will run in the background
;;   (a3madkour/run-in-background "dunst")
;;   (a3madkour/run-in-background "nm-applet")
;;   (a3madkour/run-in-background "pasystray")
;;   (a3madkour/run-in-background "blueman-applet"))

;; (defun a3madkour/exwm-update-class ()
;;   (exwm-workspace-rename-buffer exwm-class-name))

;; (defun a3madkour/exwm-update-title ()
;;   (pcase exwm-class-name
;;     ("Brave-browser" (exwm-workspace-rename-buffer (format "Brave-browser: %s" exwm-title)))))

;; ;; This function should be used only after configuring autorandr!
;; (defun a3madkour/update-displays ()
;;   (a3madkour/run-in-background "autorandr --change --force")
;;   (message "Display config: %s"
;;            (string-trim (shell-command-to-string "autorandr --current"))))

;; (use-package! exwm
;;   :config
;;   ;; Set the default number of workspace
;;   (setq exwm-workspace-number 5)

;;   ;; When window "class" updates, use it to set the buffer name
;;   (add-hook! 'exwm-update-class-hook #'a3madkour/exwm-update-class)

  ;; When window title updates, use it to set the buffer name
  ;; (add-hook! 'exwm-update-title-hook #'a3madkour/exwm-update-title)

  ;; When EXWM starts up, do some extra configuration
  ;; (add-hook! 'exwm-init-hook #'a3madkour/exwm-init-hook )

  ;; (start-process-shell-command "xmodmap" nil "xmodmap ~/.emacs.d/exwm/Xmodmap")

  ;; (require 'exwm-randr)
  ;; (exwm-randr-enable)

  ;; (setq exwm-randr-workspace-monitor-plist
  ;;       (pcase (system-name)
  ;;         ("labmachine" '(2 "HDMI-1" 3 "HDMI-1"))
  ;;         ("linuxmachine" '(2 "DP-1-2" 3 "DP-1-2"))))

  ;; ;; React to display connectivity changes, do initial display update
  ;; (add-hook 'exwm-randr-screen-change-hook #'a3madkour/update-displays)
  ;; (a3madkour/update-displays)

  ;; (require 'exwm-systemtray)
  ;; (exwm-systemtray-enable)

  ;; Automatically send the mouse cursor to the selected workspace's display
  ;; (setq exwm-workspace-warp-cursor t)

  ;; Window focus should follow the mouse pointer
  ;; (setq mouse-autoselect-window t
  ;;       focus-follows-mouse t)

  ;; (setq exwm-input-prefix-keys
  ;;       '(?\C-x
  ;;         ?\C-u
  ;;         ?\C-h
  ;;         ?\M-x
  ;;         ?\M-`
  ;;         ?\M-&
  ;;         ?\M-:
  ;;         ?\C-\M-j
  ;;         ?\C-\ ))

  ;; (define-key exwm-mode-map [?\C-q]   'exwm-input-send-next-key)


  ;; (setq exwm-input-global-keys
  ;;       `(
          ;; Reset to line-mode (C-c C-k switches to char-mode via exwm-input-release-keyboard)
  ;;         ([?\s-r] . exwm-reset)

  ;;         ;; Move between windows
  ;;         ([?\s-h] . windmove-left)
  ;;         ([?\s-l] . windmove-right)
  ;;         ([?\s-k] . windmove-up)
  ;;         ([?\s-j] . windmove-down)

  ;;         ;; Launch applications via shell command
  ;;         ([?\s-&] . (lambda (command)
  ;;                      (interactive (list (read-shell-command "$ ")))
  ;;                      (start-process-shell-command command nil command)))

  ;;         ;; Switch workspace
  ;;         ([?\s-w] . exwm-workspace-switch)
  ;;         ([?\s-`] . (lambda () (interactive) (exwm-workspace-switch-create 0)))

  ;;         ;; 's-N': Switch to certain workspace with Super (Win) plus a number key (0 - 9)
  ;;         ,@(mapcar (lambda (i)
  ;;                     `(,(kbd (format "s-%d" i)) .
  ;;                       (lambda ()
  ;;                         (interactive)
  ;;                         (exwm-workspace-switch-create ,i))))
  ;;                   (number-sequence 0 9))))

  ;; (exwm-input-set-key (kbd "s-SPC") 'counsel-linux-app)

  ;; (exwm-enable)
  ;; )
;; Core:2 ends here

;; [[file:config.org::*Desktop Environment][Desktop Environment:2]]
;; (use-package! desktop-environment
;;   :after exwm
;;   :config (desktop-environment-mode)
;;   :custom
;;   (desktop-environment-brightness-small-increment "2%+")
;;   (desktop-environment-brightness-small-decrement "2%-")
;;   (desktop-environment-brightness-normal-increment "5%+")
;;   (desktop-environment-brightness-normal-decrement "5%-"))
;; Desktop Environment:2 ends here

;; [[file:config.org::*Polybar][Polybar:1]]
;; Make sure the server is started (better to do this in your main Emacs config!)
;; (server-start)

;; (defvar a3madkour/polybar-process nil
;;   "Holds the process of the running Polybar instance, if any")

;; (defun a3madkour/kill-panel ()
;;   (interactive)
;;   (when a3madkour/polybar-process
;;     (ignore-errors
;;       (kill-process a3madkour/polybar-process)))
;;   (setq a3madkour/polybar-process nil))

;; (defun a3madkour/start-panel ()
;;   (interactive)
;;   (a3madkour/kill-panel)
;;   (setq a3madkour/polybar-process (start-process-shell-command "polybar" nil "polybar panel")))

;; (defun a3madkour/send-polybar-hook (module-name hook-index)
;;   (start-process-shell-command "polybar-msg" nil (format "polybar-msg hook %s %s" module-name hook-index)))

;; (defun a3madkour/send-polybar-exwm-workspace ()
;;   (a3madkour/send-polybar-hook "exwm-workspace" 1))

;; ;; Update panel indicator when workspace changes
;; (add-hook 'exwm-workspace-switch-hook #'a3madkour/send-polybar-exwm-workspace)
;; Polybar:1 ends here

;; [[file:config.org::*Dunst][Dunst:1]]
;; (defun a3madkour/disable-desktop-notifications ()
;;   (interactive)
;;   (start-process-shell-command "notify-send" nil "notify-send \"DUNST_COMMAND_PAUSE\""))

;; (defun a3madkour/enable-desktop-notifications ()
;;   (interactive)
;;   (start-process-shell-command "notify-send" nil "notify-send \"DUNST_COMMAND_RESUME\""))

;; (defun a3madkour/toggle-desktop-notifications ()
;;   (interactive)
;;   (start-process-shell-command "notify-send" nil "notify-send \"DUNST_COMMAND_TOGGLE\""))
;; Dunst:1 ends here

;; [[file:config.org::*Mu4e][Mu4e:1]]
(after! mu4e
  ;;   :config
  ;;   ;; This is set to 't' to avoid mail syncing issues when using mbsync
  (setq mu4e-change-filenames-when-moving t)

  ;;   ;; Refresh mail using isync every 10 minutes
  (setq mu4e-update-interval (* 10 60))
  (setq mu4e-get-mail-command "mbsync -a")
  (setq mu4e-root-maildir "~/Mail")


  (setq mu4e-contexts
        (list
         ;; Personal account
         (make-mu4e-context
          :name "Personal"
          :match-func
          (lambda (msg)
            (when msg
              (string-prefix-p "/Gmail" (mu4e-message-field msg :maildir))))
          :vars '((user-mail-address . "a3madkour@gmail.com")
                  (user-full-name    . "Abdelrahman Madkour Gmail")
                  (mu4e-drafts-folder  . "/Gmail/Drafts")
                  (mu4e-sent-folder  . "/Gmail/Sent Mail")
                  (mu4e-refile-folder  . "/Gmail/All Mail")
                  (mu4e-trash-folder  . "/Gmail/Trash")))

         ;; Maroon Loop account
         (make-mu4e-context
          :name "Maroon"
          :match-func
          (lambda (msg)
            (when msg
              (string-prefix-p "/MaroonLoop" (mu4e-message-field msg :maildir))))
          :vars '((user-mail-address . "loopmaroon@gmail.com")
                  (user-full-name    . "Maroon Loop Gmail")
                  (mu4e-drafts-folder  . "/MaroonLoop/Drafts")
                  (mu4e-sent-folder  . "/MaroonLoop/Sent Mail")
                  (mu4e-refile-folder  . "/MaroonLoop/All Mail")
                  (mu4e-trash-folder  . "/MaroonLoop/Trash")))))

  (setq mu4e-maildir-shortcuts
        '((:maildir "/Gmail/Inbox"    :key ?i)
          (:maildir "/Gmail/Sent Mail" :key ?s)
          (:maildir "/Gmail/Trash"     :key ?t)
          (:maildir "/Gmail/Drafts"    :key ?d)
          (:maildir "/Gmail/All Mail"  :key ?a)))
  (mu4e t)
  )
;; Mu4e:1 ends here

;; [[file:config.org::*Org-gcal][Org-gcal:1]]
(require 'org-gcal)
(setq org-gcal-client-id "497062789073-ebje9tkqvv79gnm1e0q5uvdgaaqp6mt0.apps.googleusercontent.com"
      org-gcal-client-secret "WPeCGrJjihtqRm_D3oz9PWmS"
      org-gcal-file-alist '(("a3madkour@gmail.com" .  "~/org/gcal.org")))

(add-hook! 'evil-org-agenda-mode-hook 'org-gcal-fetch)
(add-hook! 'cfw:calendar-mode-hook 'org-gcal-fetch)
;; Org-gcal:1 ends here

;; [[file:config.org::*Debugger][Debugger:1]]
(add-hook 'python-mode-hook (lambda ()
                            (setq dap-python-debugger 'debugpy)))
;; Debugger:1 ends here

;; [[file:config.org::*Sphinx][Sphinx:2]]
(add-hook 'python-mode-hook (lambda ()
                            (require 'sphinx-doc)
                            (sphinx-doc-mode t)))
(map!
 :mode python-mode
 :localleader
       "d" #'sphinx-doc
 )
;; Sphinx:2 ends here

;; [[file:config.org::*System Config][System Config:1]]
;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")
;; System Config:1 ends here

;; [[file:config.org::*Loading Org][Loading Org:1]]
;; (defun a3madkour/org-mode-setup ()
;; (org-indent-mode)
;; (org-superstar-mode 1)
;; (variable-pitch-mode 1)
;; )
;; Loading Org:1 ends here

;; [[file:config.org::*Loading Org][Loading Org:2]]
;; (use-package! org
;; :hook (org-mode . a3madkour/org-mode-setup))
;; Loading Org:2 ends here

;; [[file:config.org::*Font Setup][Font Setup:1]]
(defun a3madkour/org-font-setup ()
  ;; Replace list hyphen with dot
  (font-lock-add-keywords 'org-mode
                          '(("^ *\\([-]\\) "
                             (0 (prog1 () (compose-region (match-beginning 1) (match-end 1) "•"))))))

  ;; Set faces for heading levels
  (dolist (face '((org-level-1 . 1.2)
                  (org-level-2 . 1.1)
                  (org-level-3 . 1.05)
                  (org-level-4 . 1.0)
                  (org-level-5 . 1.1)
                  (org-level-6 . 1.1)
                  (org-level-7 . 1.1)
                  (org-level-8 . 1.1)))
    (set-face-attribute (car face) nil :font "Cantarell" :weight 'regular :height (cdr face)))

  ;; Ensure that anything that should be fixed-pitch in Org files appears that way
  (set-face-attribute 'org-block nil :foreground nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-code nil   :inherit '(shadow fixed-pitch))
  (set-face-attribute 'org-table nil   :inherit '(shadow fixed-pitch))
  (set-face-attribute 'org-verbatim nil :inherit '(shadow fixed-pitch))
  (set-face-attribute 'org-special-keyword nil :inherit '(font-lock-comment-face fixed-pitch))
  (set-face-attribute 'org-meta-line nil :inherit '(font-lock-comment-face fixed-pitch))
  (set-face-attribute 'org-checkbox nil :inherit 'fixed-pitch))
;; Font Setup:1 ends here

;; [[file:config.org::*After Org is loaded][After Org is loaded:1]]
(after! org
;; After Org is loaded:1 ends here

;; [[file:config.org::*Basic Setup][Basic Setup:1]]
(setq
 org_notes "~/org/notes"
 bib_notes "~/org/bib-notes"
 zot_bib  "~/org/bib-notes/library.bib"
 deft-directory org_notes
 deft-strip-summary-regexp ":PROPERTIES:\n\\(.+\n\\)+:END:\n"
 org-cite-global-bibliography (list zot_bib)
 org-cite-default-bibliography (list zot_bib)
 deft-use-filename-as-title 't
 deft-recursive 't
 deft-default-extension "org"
 org-roam-directory org_notes
 )
;; Basic Setup:1 ends here

;; [[file:config.org::*Org Tempo][Org Tempo:1]]
(require 'org-tempo)
(add-to-list 'org-structure-template-alist '("sh" . "src sh"))
(add-to-list 'org-structure-template-alist '("el" . "src emacs-lisp"))
(add-to-list 'org-structure-template-alist '("sc" . "src scheme"))
(add-to-list 'org-structure-template-alist '("ts" . "src typescript"))
(add-to-list 'org-structure-template-alist '("py" . "src python"))
(add-to-list 'org-structure-template-alist '("yaml" . "src yaml"))
(add-to-list 'org-structure-template-alist '("json" . "src json"))
;; Org Tempo:1 ends here

;; [[file:config.org::*Org Capture][Org Capture:1]]
(setq org-capture-templates
      '(("t" "Todo" entry (file+datetree "~/org/tasks.org")
         "* TODO %?\n")
        ("u" "Unscheduled task" entry (file+headline "~/org/tasks.org" "Unscheduled tasks")
         "* TODO %?\n")
        ("c" "Cookbook" entry (file "~/org/cookbook.org")
         "%(org-chef-get-recipe-from-url)"
         :empty-lines 1)
        ("z" "Manual Cookbook" entry (file "~/org/cookbook.org")
         "* %^{Recipe title: }\n  :PROPERTIES:\n  :source-url:\n  :servings:\n  :prep-time:\n  :cook-time:\n  :ready-in:\n  :END:\n** Ingredients\n   %?\n** Directions\n\n")
        ("b" "Manual Book" entry (file "~/org/reading-list.org")
         "* %^{TITLE}\n:PROPERTIES:\n:ADDED: %<[%Y-%02m-%02d]>\n:END:%^{AUTHOR}p\n%?" :empty-lines 1)
        ("r" "Research Journal" entry (file+datetree "~/org/research-journal.org")
         "* %T \n %?")
        ("m" "Meeting" entry (file"~/org/meetings.org")
         "* %t \n %?")
        ("g" "Game idea" entry (file+headline "~/org/ideas.org" "Game")
         "* %?\n")
        ("p" "Paper idea" entry (file+headline "~/org/ideas.org" "Paper")
         "* %?\n")
        ("a" "App idea" entry (file+headline "~/org/ideas.org" "App")
         "* %?\n")
        ("v" "Video idea" entry (file+headline "~/org/ideas.org" "Video")
         "* %?\n")
        ("w" "Vague idea" entry (file+headline "~/org/ideas.org" "Vague af")
         "* %?\n")
        ))
;; Org Capture:1 ends here

;; [[file:config.org::*Ox-pandoc][Ox-pandoc:1]]
;; default options for all output formats
(setq org-pandoc-options '((standalone . t)))
;; cancel above settings only for 'docx' format
(setq org-pandoc-options-for-docx '((standalone . nil)))
;; special settings for beamer-pdf and latex-pdf exporters
(setq org-pandoc-options-for-beamer-pdf '((pdf-engine . "xelatex")))
(setq org-pandoc-options-for-latex-pdf '((pdf-engine . "pdflatex")))
;; special extensions for markdown_github output
(setq org-pandoc-format-extensions '(markdown_github+pipe_tables+raw_html))
;; Ox-pandoc:1 ends here

;; [[file:config.org::*Org Agenda][Org Agenda:1]]
(setq org-agenda-files
  (quote
   ("~/org/gcal.org" "~/org/tasks.org" "~/org/habits.org")))
;; Org Agenda:1 ends here

;; [[file:config.org::*Org Agenda][Org Agenda:2]]
(setq evil-org-key-theme '(textobjects navigation additional insert todo))
(setq org-todo-keywords
      '((sequence "TODO(t!)" "NEXT(n!)" "DOINGNOW(d!)" "BLOCKED(b!)" "FOLLOWUP(f!)" "TICKLE(T!)" "|" "CANCELLED(c!)" "DONE(F!)")))
(setq org-todo-keyword-faces
      '(("TODO" . org-warning)
        ("DOINGNOW" . "#E35DBF")
        ("CANCELED" . (:foreground "white" :background "#4d4d4d" :weight bold))
        ("NEXT" . "#008080")
              ("DONE" . "PaleGreen"))
      )
;; Org Agenda:2 ends here

;; [[file:config.org::*Org Agenda][Org Agenda:3]]
(setq org-agenda-start-with-log-mode t)
(setq org-log-done 'time)
(setq org-log-into-drawer t)
;; Org Agenda:3 ends here

;; [[file:config.org::*Org Habit][Org Habit:1]]
(require 'org-habit)
(add-to-list 'org-modules 'org-habit)
(setq org-habit-graph-column 60)
;; Org Habit:1 ends here

;; [[file:config.org::*Bibtex][Bibtex:1]]
(setq
 bibtex-completion-notes-path bib_notes
 bibtex-completion-bibliography zot_bib
 bibtex-completion-pdf-field "file"
 bibtex-completion-notes-template-multiple-files
 (concat
  "#+title: ${title}\n"
  "* Org Noter\n"
  ":PROPERTIES:\n"
  ":Custom_ID: ${=key=}\n"
  ":NOTER_DOCUMENT: %(orb-process-file-field \"${=key=}\")\n"
  ":AUTHOR: ${author-abbrev}\n"
  ":JOURNAL: ${journaltitle}\n"
  ":DATE: ${date}\n"
  ":YEAR: ${year}\n"
  ":DOI: ${doi}\n"
  ":URL: ${url}\n"
  ":END:\n\n"
  )
 )
;; Bibtex:1 ends here

;; [[file:config.org::*Org Latex][Org Latex:1]]
(setq org-latex-pdf-process
      '("latexmk -shell-escape -bibtex -pdf %f"))
;; Org Latex:1 ends here

;; [[file:config.org::*Load Font Setup][Load Font Setup:1]]
(a3madkour/org-font-setup)
)
;; Load Font Setup:1 ends here

;; [[file:config.org::*Org Books][Org Books:2]]
(after! org-books
  (setq org-books-file "~/org/reading-list.org")
)
;; Org Books:2 ends here

;; [[file:config.org::*Org Ref][Org Ref:2]]
(use-package! org-ref
  :config
  (setq
   org-ref-completion-library 'org-ref-ivy-cite
   org-ref-get-pdf-filename-function 'org-ref-get-pdf-filename-helm-bibtex
   org-ref-default-bibliography (list zot_bib)
   org-ref-bibliography-notes (concat bib_notes "/bibnotes.org")
   org-ref-note-title-format "%y - %t\n :PROPERTIES:\n  :Custom_ID: %k\n  :NOTER_DOCUMENT: %F\n :AUTHOR: %9a\n  :JOURNAL: %j\n  :YEAR: %y\n  :VOLUME: %v\n  :PAGES: %p\n  :DOI: %D\n  :URL: %U\n :END:\n\n"
   org-ref-notes-directory bib_notes
   org-ref-notes-function 'orb-edit-notes
   ))
;; Org Ref:2 ends here

;; [[file:config.org::*Org Roam Bibtex][Org Roam Bibtex:2]]
(use-package! org-roam-bibtex
  :after (org-roam)
  :hook (org-roam-mode . org-roam-bibtex-mode)
  :config
  (setq orb-preformat-keywords
        '("=key=" "title" "url" "file" "author-or-editor" "keywords"))
  (setq orb-templates
        '(("r" "ref" plain (function org-roam-capture--get-point) ""
           :file-name "${citekey}"
           :head "#+TITLE: ${citekey}: ${title}\n#+ROAM_KEY: ${ref}\n" ; <--
           :unnarrowed t)))
  (setq orb-preformat-keywords   '(("citekey" . "=key=") "title" "url" "file" "author-or-editor" "keywords"))

   (setq orb-templates
        '(("n" "ref+noter" plain (function org-roam-capture--get-point)
           ""
           :file-name "${slug}"
           :head "#+TITLE: ${citekey}: ${title}\n#+ROAM_KEY: ${ref}\n#+ROAM_TAGS:

- tags ::
- keywords :: ${keywords}
\* ${title}
:PROPERTIES:
:Custom_ID: ${citekey}
:URL: ${url}
:AUTHOR: ${author-or-editor}
:NOTER_DOCUMENT: %(orb-process-file-field \"${citekey}\")
:NOTER_PAGE:
:END:")))
  )
;; Org Roam Bibtex:2 ends here

;; [[file:config.org::*Org Noter][Org Noter:1]]
(use-package! org-noter
  :after (:any org pdf-view)
  :config
  (setq
   ;; Split the window horizontally
   ;; org-noter-notes-window-location 'horizontal-split
   ;; Please stop opening frames
   org-noter-always-create-frame nil
   ;; Everything is relative to the main notes file
   org-noter-notes-search-path (list bib_notes)
   )
  )
;; Org Noter:1 ends here

;; [[file:config.org::*Org Noter][Org Noter:2]]
(add-hook! org-noter-doc-mode
  (evil-normal-state)
  )
;; Org Noter:2 ends here

;; [[file:config.org::*Org PDFTools][Org PDFTools:1]]
(use-package! org-pdftools
  :hook (org-load . org-pdftools-setup-link))
;; Org PDFTools:1 ends here

;; [[file:config.org::*Insert][Insert:1]]
(map! :leader
      (:prefix "i"
      "b" #'org-books-add-url
      )
)
;;adding a keymap for insert note in org-noter
;; (map!
;;  :ne "SPC i n" #'org-noter-insert-note
;; )
(map!
 :mode org-noter-doc-mode
 :ne "i" #'org-noter-insert-note
 )
;; Insert:1 ends here

;; [[file:config.org::*Projectile][Projectile:1]]
(map! :leader
      (:prefix "p"
       "l" #'projectile-replace
       )
)
;; Projectile:1 ends here

;; [[file:config.org::*Toggles][Toggles:1]]
(map! :leader
      (:prefix "t"
       "C" #'centered-window-mode)
)
;; Toggles:1 ends here

;; [[file:config.org::*Agenda][Agenda:1]]
(map! :leader
      (:prefix "d"
      :desc "Habits" "h" (lambda () (interactive) (find-file "~/org/habits.org"))
      :desc "Tasks" "t" (lambda () (interactive) (find-file "~/org/tasks.org"))
      "c" #'cfw:open-org-calendar
      )
)
;; Agenda:1 ends here

;; [[file:config.org::*Langtool][Langtool:1]]
(map! :leader
      (:prefix "l"
      "b" #'langtool-check
      "c" #'langtool-corrct-buffer
      "m" #'langtool-show-message-at-point
      "d" #'langtool-check-done
      "n" #'langtool-goto-next-eror
      "p" #'langtool-goto-previous-error
      )
)
;; Langtool:1 ends here

;; [[file:config.org::*Bibtex actions][Bibtex actions:1]]
(map! :leader
      (:prefix "r"
      "n" #'bibtex-actions-open-notes
      "p" #'bibtex-actions-open-pdf
      "o" #'bibtex-actions-open
      "c" #'bibtex-actions-insert-citation
      "b" #'bibtex-actions-insert-bibtex
      )
)
;; Bibtex actions:1 ends here

;; [[file:config.org::*Org-mode error][Org-mode error:1]]
(add-hook 'org-mode-hook (lambda () (electric-indent-local-mode -1)))
;; Org-mode error:1 ends here
