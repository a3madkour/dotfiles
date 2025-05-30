;;; init.el --- Description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2022 Abdelrahman Madkour
;;
;; Author: Abdelrahman Madkour <a3madkour@gmail.com>
;; Maintainer: Abdelrahman Madkour <a3madkour@gmail.com>
;; Created: July 17, 2022
;; Modified: July 17, 2022
;; Version: 0.0.1
;; Keywords: abbrev bib c calendar comm convenience data docs emulations extensions faces files frames games hardware help hypermedia i18n internal languages lisp local maint mail matching mouse multimedia news outlines processes terminals tex tools unix vc wp
;; Homepage: https://github.com/a3madkour/init
;; Package-Requires: ((emacs "24.3"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:

(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name
		"straight/repos/straight.el/bootstrap.el"
		(or (bound-and-true-p straight-base-dir) user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer (url-retrieve-synchronously
						  "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
						  'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)
(setq straight-use-package-by-default t)
(setq straight-built-in-pseudo-packages
	  '(emacs nadvice python image-mode project flymake xref))
(use-package org)

(org-babel-load-file "~/emacs-configs/custom/config.org")
;; (use-package gcmh
;;   :diminish gcmh-mode
;;   :config
;;   (setq gcmh-idle-delay 5
;;         gcmh-high-cons-threshold (* 16 1024 1024))  ; 16mb
;;   (gcmh-mode 1))

;; (add-hook 'emacs-startup-hook
;;           (lambda ()
;;             (setq gc-cons-percentage 0.1))) ;; Default value for `gc-cons-percentage'

;; (add-hook 'emacs-startup-hook
;;           (lambda ()
;;             (message "Emacs ready in %s with %d garbage collections."
;;                      (format "%.2f seconds"
;;                              (float-time
;;                               (time-subtract after-init-time before-init-time)))
;;                      gcs-done)))


;; ;; When emacs asks for "yes" or "no", let "y" or "n" suffice
;; (setq use-short-answers t)

;; ;; Confirm to quit
;; (setq confirm-kill-emacs 'yes-or-no-p)

;; ;; Major mode of new buffers
;; (setq initial-major-mode 'org-mode)

;; ;; WINDOW -----------

;; ;; Don't resize the frames in steps; it looks weird, especially in tiling window
;; ;; managers, where it can leave unseemly gaps.
;; (setq frame-resize-pixelwise t)

;; ;; When opening a file (like double click) on Mac, use an existing frame
;; (setq ns-pop-up-frames nil)

;; ;; But do not resize windows pixelwise, this can cause crashes in some cases
;; ;; where we resize windows too quickly.
;; (setq window-resize-pixelwise nil)

;; ;; LINES -----------
;; (setq-default truncate-lines t)

;; (setq-default tab-width 4)
;; (use-package evil
;;   :init
;;   ;; (setq evil-want-keybinding t)
;;   (setq evil-want-fine-undo t)
;;   (setq evil-want-keybinding nil)
;;   (setq evil-want-Y-yank-to-eol t)
;;   (setq evil-want-integration t) ;; This is optional since it's already set to t by default.
;;   (setq evil-want-keybinding nil)
;;   :config

;;   (evil-set-initial-state 'dashboard-mode 'motion)
;;   (evil-set-initial-state 'debugger-mode 'motion)
;;   (evil-set-initial-state 'pdf-view-mode 'motion)
;;   (evil-set-initial-state 'bufler-list-mode 'emacs)
;;   (evil-set-initial-state 'inferior-python-mode 'emacs)
;;   (evil-set-initial-state 'term-mode 'emacs)

;;   ;; ----- Keybindings
;;   ;; I tried using evil-define-key for these. Didn't work.
;;   ;; (define-key evil-motion-state-map "/" 'swiper)
;;   (define-key evil-window-map "\C-q" 'evil-delete-buffer) ;; Maps C-w C-q to evil-delete-buffer (The first C-w puts you into evil-window-map)
;;   (define-key evil-window-map "\C-w" 'kill-this-buffer)
;;   (define-key evil-motion-state-map "\C-u" 'evil-scroll-up) 

;;   ;; ----- Setting cursor colors
;;   (setq evil-emacs-state-cursor    '("#649bce" box))
;;   (setq evil-normal-state-cursor   '("#ebcb8b" box))
;;   (setq evil-operator-state-cursor '("#ebcb8b" hollow))
;;   (setq evil-visual-state-cursor   '("#677691" box))
;;   (setq evil-insert-state-cursor   '("#eb998b" (bar . 2)))
;;   (setq evil-replace-state-cursor  '("#eb998b" hbar))
;;   (setq evil-motion-state-cursor   '("#ad8beb" box))

;;   (evil-mode 1))

;; (use-package evil-nerd-commenter
;;   :after evil
;;   :config
;;   )

;; (use-package evil-surround
;;   :after evil
;;   :defer 2
;;   :config
;;   (global-evil-surround-mode 1))

;; (use-package evil-collection
;;   :after evil
;;   :ensure t
;;   :config
;;   (evil-collection-init))

;; (use-package evil-easymotion)
;; (use-package evil-args)
;; (use-package evil-visualstar)
;; (use-package evil-quick-diff
;;   :straight (evil-quick-diff
;;   :type git
;;   :host github
;;   :repo "rgrinberg/evil-quick-diff"
;;   )
;;   :init
;;  (setq evil-quick-diff-key (kbd "zx"))
;;  (evil-quick-diff-install))
;; ;;(use-package evil-quick-diff
;;  ;;:init
;;  ;;(setq evil-quick-diff-key (kbd "zx"))
;;  ;;(evil-quick-diff-install))
;; (use-package exato :ensure t)
;; (use-package evil-vimish-fold)
;; (use-package evil-escape)
;; (use-package evil-numbers)
;; (use-package evil-exchange)
;; (use-package evil-lion
;;   :ensure t
;;   :config
;;   (evil-lion-mode))
;; (use-package evil-indent-plus)
;; (use-package evil-embrace)

;; (use-package evil-snipe
;;   :diminish evil-snipe-mode
;;   :diminish evil-snipe-local-mode
;;   :after evil
;;   :config
;;   (evil-snipe-mode +1))

;; (use-package vterm
;;   :ensure t
;;   :config
;; (push '("find-file-other-window" find-file-other-window) vterm-eval-cmds)
;; )

;; (add-hook 'vterm-mode-hook (lambda()
;; (goto-address-mode 1)))
  

;; (use-package undo-tree)
;; (global-undo-tree-mode)
;; (evil-set-undo-system 'undo-tree)

;; (use-package recentf
;;   :ensure nil
;;   :config
;;   (setq ;;recentf-auto-cleanup 'never
;;    ;; recentf-max-menu-items 0
;;    recentf-max-saved-items 200)
;;   ;; Show home folder path as a ~
;;   (setq recentf-filename-handlers  
;;         (append '(abbreviate-file-name) recentf-filename-handlers))
;;   (recentf-mode))

;; (require 'uniquify)
;; (setq uniquify-buffer-name-style 'forward)

;; (use-package which-key
;;   :diminish which-key-mode
;;   :init
;;   (which-key-mode)
;;   (which-key-setup-minibuffer)
;;   :config
;;   (setq which-key-idle-delay 0.3)
;;   (setq which-key-prefix-prefix "◉ ")
;;   (setq which-key-sort-order 'which-key-key-order-alpha
;;         which-key-min-display-lines 6
;;         which-key-max-display-columns nil))


;; (use-package general)


;; (general-define-key
;;  :states '(normal motion visual)
;;  :keymaps 'override
;;  :prefix "SPC"

;;  ;; Top level functions
;;  ;; "/" '(jib/rg :which-key "ripgrep")
;;  ;; ";" '(spacemacs/deft :which-key "deft")
;;  ":" '(project-find-file :which-key "p-find file")
;;  "." '(find-file :which-key "find file")
;;  "," '(consult-recent-file :which-key "recent files")
;;  "TAB" '(switch-to-prev-buffer :which-key "previous buffer")
;; ;; "SPC" '(consult-M-x :which-key "M-x")
;;  "q" '(save-buffers-kill-terminal :which-key "quit emacs")
;;  "r" '(jump-to-register :which-key "registers")
;;  "c" 'org-capture

;; ;; Buffers
;; "b" '(nil :which-key "buffer")
;; "bb" '(consult-buffer :which-key "switch buffers")
;; "bd" '(evil-delete-buffer :which-key "delete buffer")
;; "bs" '(switch-to-scratch-buffer :which-key "scratch buffer")
;; "bm" '(kill-other-buffers :which-key "kill other buffers")
;; "bi" '(ibuffer  :which-key "ibuffer")
;; "br" '(revert-buffer :which-key "revert buffer")

;; ;; Files
;; "f" '(nil :which-key "files")
;; "fb" '(consult-bookmark :which-key "bookmarks")
;; "ff" '(find-file :which-key "find file")
;; ;; "fn" '(spacemacs/new-empty-buffer :which-key "new file")
;; "fr" '(recentf :which-key "recent files")
;; "fR" '(rename-file :which-key "rename file")
;; "fs" '(save-buffer :which-key "save buffer")
;; "fS" '(evil-write-all :which-key "save all buffers")
;; "fo" '(reveal-in-osx-finder :which-key "reveal in finder")

;; ;; Help/emacs
;; "h" '(nil :which-key "help/emacs")

;; "hv" '(describe-variable :which-key "des. variable")
;; "hb" '(descbinds :which-key "des. bindings")
;; "hM" '(describe-mode :which-key "des. mode")
;; "hf" '(describe-function :which-key "des. func")
;; "hF" '(describe-face :which-key "des. face")
;; "hk" '(describe-key :which-key "des. key")

;; "hed" '((lambda () (interactive) (jump-to-register 67)) :which-key "edit dotfile")

;; "hm" '(nil :which-key "switch mode")
;; "hme" '(emacs-lisp-mode :which-key "elisp mode")
;; "hmo" '(org-mode :which-key "org mode")
;; "hmt" '(text-mode :which-key "text mode")

;; ;; Git
;; "gg" '(magit-status :which-key "magit status")

;; ;; Open
;; "ot" '(vterm-other-window :which-key "Open vterm in another window")
;; "oT" '(vterm :which-key "Open vterm in the same window")

;; ;; Toggles
;; "t" '(nil :which-key "toggles")
;; "tt" '(toggle-truncate-lines :which-key "truncate lines")
;; "tv" '(visual-line-mode :which-key "visual line mode")
;; "tn" '(display-line-numbers-mode :which-key "display line numbers")
;; "ta" '(mixed-pitch-mode :which-key "variable pitch mode")
;; "tc" '(visual-fill-column-mode :which-key "visual fill column mode")
;; "ty" '(consult-load-theme :which-key "load theme")
;; "tw" '(writeroom-mode :which-key "writeroom-mode")
;; "tR" '(read-only-mode :which-key "read only mode")
;; "tI" '(toggle-input-method :which-key "toggle input method")
;; "tr" '(display-fill-column-indicator-mode :which-key "fill column indicator")
;; "tm" '(hide-mode-line-mode :which-key "hide modeline mode")

;; ;;Search
;; "sb" '(consult-line :which-key "search buffer")
;; ;; Windows
;; "w" '(nil :which-key "window")
;; ;; "wm" '(jib/toggle-maximize-buffer :which-key "maximize buffer")
;; "wN" '(make-frame :which-key "make frame")
;; "wd" '(evil-window-delete :which-key "delete window")
;; "ws" '(split-window-vertically :which-key "split below")
;; "wv" '(split-window-horizontally :which-key "split right")
;; "wl" '(evil-window-right :which-key "evil-window-right")
;; "wh" '(evil-window-left :which-key "evil-window-left")
;; "wj" '(evil-window-down :which-key "evil-window-down")
;; "wk" '(evil-window-up :which-key "evil-window-up")
;; "wz" '(text-scale-adjust :which-key "text zoom")


;; ;;g commandsc-comment-operator :which-key "comment operator")
;; ) ;; End SPC prefix block

;; ;; All-mode keymaps
;; (general-def
;;   :keymaps 'override

;;   ;; Emacs --------
;;   ;;"M-x" 'consult-M-x
;;   "ß" 'evil-window-next ;; option-s
;;   "Í" 'other-frame ;; option-shift-s
;;   "C-S-B" 'consult-switch-buffer
;;   "∫" 'consult-switch-buffer ;; option-b

;;   ;; Remapping normal help features to use Consult version
;;   "C-h v" 'consult-describe-variable
;;   "C-h o" 'consult-describe-symbol
;;   "C-h f" 'consult-describe-function
;;   "C-h F" 'consult-describe-face

;;   ;; Editing ------
;;   "M-v" 'simpleclip-paste
;;   "M-V" 'evil-paste-after ;; shift-paste uses the internal clipboard
;;   "M-c" 'simpleclip-copy
;;   "M-u" 'capitalize-dwim ;; Default is upcase-dwim
;;   "M-U" 'upcase-dwim ;; M-S-u (switch upcase and capitalize)
;;   ;;"M-z" 'undo-fu-only-undo				
;;   ;;"M-S" 'undo-fu-only-redo

;;   ;; Utility ------
;;   "C-c c" 'org-capture
;;   "C-c a" 'org-agenda
;;   "C-s" 'swiper ;; Large files will use grep (faster)
;;   "s-\"" 'ispell-word ;; that's super-shift-'
;;   ;; "M-+" 'jib/calc-speaking-time
;;   "C-'" 'avy-goto-char-2

;;   "C-x C-b" 'bufler-list

;;   ;; super-number functions
;;   "s-1" 'mw-thesaurus-lookup-dwim
;;   "s-!" 'mw-thesaurus-lookup
;;   "s-2" 'ispell-buffer
;;   "s-3" 'revert-buffer
;;   ;; "s-4" '(lambda () (interactive) (consult-file-jump nil jib/dropbox))
;;   ;; "s-5" '(lambda () (interactive) (consult-rg nil jib/dropbox))
;;   "s-6" 'org-capture
;;   )

;; (general-def
;;  :keymaps 'emacs
;;   "C-w C-q" 'kill-this-buffer
;;  )


;; ;; Non-insert mode keymaps
;; (general-def
;;   :states '(normal visual motion)
;;   "u" 'undo
;;   "j" 'evil-next-visual-line ;; I prefer visual line navigation
;;   "k" 'evil-previous-visual-line ;; ""
;;   "|" '(lambda () (interactive) (org-agenda nil "k")) ;; Opens my n custom org-super-agenda view
;;   "C-|" '(lambda () (interactive) (org-agenda nil "j")) ;; Opens my m custom org-super-agenda view
;;  "gc" '(evilnc-comment-operator :which-key "commentator")
;;   )

;; ;; Insert keymaps
;; ;; Many of these are emulating standard Emacs bindings in Evil insert mode, such as C-a, or C-e.
;; (general-def
;;   :states '(insert)
;;   "C-a" 'evil-beginning-of-visual-line
;;   "C-e" 'evil-end-of-visual-line
;;   "C-S-a" 'evil-beginning-of-line
;;   "C-S-e" 'evil-end-of-line
;;   "C-n" 'evil-next-visual-line
;;   "C-p" 'evil-previous-visual-line
;;   )

;; (use-package hydra
;;   :defer t)

;; ;; This Hydra lets me swich between variable pitch fonts. It turns off mixed-pitch 
;; ;; WIP
;; (defhydra jb-hydra-variable-fonts (:pre (mixed-pitch-mode 0)
;;                                      :post (mixed-pitch-mode 1))
;;   ("t" (set-face-attribute 'variable-pitch nil :family "Times New Roman" :height 160) "Times New Roman")
;;   ("g" (set-face-attribute 'variable-pitch nil :family "EB Garamond" :height 160 :weight 'normal) "EB Garamond")
;;   ;; ("r" (set-face-attribute 'variable-pitch nil :font "Roboto" :weight 'medium :height 160) "Roboto")
;;   ("n" (set-face-attribute 'variable-pitch nil :slant 'normal :weight 'normal :height 160 :width 'normal :foundry "nil" :family "Nunito") "Nunito")
;;   )
;; ;; I think I need to initialize windresize to use its commands
;; ;;(windresize)
;; ;;(windresize-exit)

;; (use-package windresize)
;; ;;stolen from jakebox
;; ;; All-in-one window managment. Makes use of some custom functions,
;; ;; `ace-window' (for swapping), `windmove' (could probably be replaced
;; ;; by evil?) and `windresize'.
;; ;; inspired by https://github.com/jmercouris/configuration/blob/master/.emacs.d/hydra.el#L86
;; (defhydra a3madkour-hydra-window (:hint nil)
;;    "
;; Movement      ^Split^            ^Switch^        ^Resize^
;; ----------------------------------------------------------------
;; _M-<left>_  <   _/_ vertical      _b_uffer        _<left>_  <
;; _M-<right>_ >   _-_ horizontal    _f_ind file     _<down>_  ↓
;; _M-<up>_    ↑   _m_aximize        _s_wap          _<up>_    ↑
;; _M-<down>_  ↓   _c_lose           _[_backward     _<right>_ >
;; _q_uit          _e_qualize        _]_forward     ^
;; ^               ^               _K_ill         ^
;; ^               ^                  ^             ^
;; "
;;    ;; Movement
;;    ("M-<left>" windmove-left)
;;    ("M-<down>" windmove-down)
;;    ("M-<up>" windmove-up)
;;    ("M-<right>" windmove-right)

;;    ;; Split/manage
;;    ("-" split-window-vertically)
;;    ("/" split-window-horizontally)
;;    ("c" evil-window-delete)

;;    ("m" delete-other-windows)
;;    ("e" balance-windows)

;;    ;; Switch
;;    ("b" consult-switch-buffer)
;;    ("f" consult-find-file)
;;    ("P" project-find-file)
;;    ("s" ace-swap-window)
;;    ("[" previous-buffer)
;;    ("]" next-buffer)
;;    ("K" kill-this-buffer)

;;    ;; Resize
;;    ("<left>" windresize-left)
;;    ("<right>" windresize-right)
;;    ("<down>" windresize-down)
;;    ("<up>" windresize-up)


;;    ("q" nil))

;; (use-package company
;;   :diminish company-mode
;;   :general
;;   (general-define-key :keymaps 'company-active-map
;;                       "C-j" 'company-select-next
;;                       "C-k" 'company-select-previous)
;;   :init
;;   ;; These configurations come from Doom Emacs:
;;   (add-hook 'after-init-hook 'global-company-mode)
;;   (setq company-minimum-prefix-length 2
;;         company-tooltip-limit 14
;;         company-tooltip-align-annotations t
;;         company-require-match 'never
;;         company-global-modes '(not erc-mode message-mode help-mode gud-mode)
;;         company-frontends
;;         '(company-pseudo-tooltip-frontend  ; always show candidates in overlay tooltip
;;           company-echo-metadata-frontend)  ; show selected candidate docs in echo area
;;         company-backends '(company-capf company-files company-keywords)
;;         company-auto-complete nil
;;         company-auto-complete-chars nil
;;         company-dabbrev-other-buffers nil
;;         company-dabbrev-ignore-case nil
;;         company-dabbrev-downcase nil)

;;   :config
;;   (setq company-idle-delay 0.35)
;;   :custom-face
;;   (company-tooltip ((t (:family "Roboto Mono")))))


;; (use-package super-save
;;   :diminish super-save-mode
;;   :defer 2
;;   :config
;;   (setq super-save-auto-save-when-idle t
;;         super-save-idle-duration 5 ;; after 5 seconds of not typing autosave
;;         super-save-triggers ;; Functions after which buffers are saved (switching window, for example)
;;         '(evil-window-next evil-window-prev balance-windows other-window)
;;         super-save-max-buffer-size 10000000)
;;   (super-save-mode +1))

;; ;; After super-save autosaves, wait __ seconds and then clear the buffer. I don't like
;; ;; the save message just sitting in the echo area.
;; ;; (defun jib-clear-echo-area-timer ()
;; ;;   (run-at-time "2 sec" nil (lambda () (message " "))))

;; ;; (advice-add 'super-save-command :after 'jib-clear-echo-area-timer)

;; (use-package saveplace
;;   :init (setq save-place-limit 100)
;;   :config (save-place-mode))


;; (use-package yasnippet
;;   :diminish yas-minor-mode
;;   :defer 5
;;   :config
;;   ;; (setq yas-snippet-dirs (list (expand-file-name "snippets" jib/emacs-stuff)))
;;   (yas-global-mode 1)) ;; or M-x yas-reload-all if you've started YASnippet already.


;; ;; Silences the warning when running a snippet with backticks (runs a command in the snippet)
;; ;; I use backtick commands to get the date for org snippets
;; (require 'warnings)
;; (add-to-list 'warning-suppress-types '(yasnippet backquote-change)) 


;; (use-package mixed-pitch
;;   :defer t
;;   :config
;;   (setq mixed-pitch-set-height nil)
;;   (dolist (face '(org-date org-priority org-tag org-special-keyword)) ;; Some extra faces I like to be fixed-pitch
;;     (add-to-list 'mixed-pitch-fixed-pitch-faces face)))

;; ;; Disables showing system load in modeline, useless anyway
;; (setq display-time-default-load-average nil)

;; (line-number-mode)
;; (column-number-mode)
;; (display-time-mode -1)
;; (size-indication-mode 1)

;; (use-package hide-mode-line
;;   :commands (hide-mode-line-mode))

;; (use-package doom-modeline
;;   :config
;;   (doom-modeline-mode)
;;   (setq doom-modeline-buffer-file-name-style 'auto ;; Just show file name (no path)
;;         doom-modeline-enable-word-count t
;;         doom-modeline-buffer-encoding nil
;;         doom-modeline-icon t ;; Enable/disable all icons
;;         doom-modeline-modal-icon nil ;; Icon for Evil mode
;;         doom-modeline-major-mode-icon t
;;         doom-modeline-major-mode-color-icon nil
;;         doom-modeline-bar-width 3))

;; ;; Configure modeline text height based on the computer I'm on.
;; ;; These variables are used in the Themes section to ensure the modeline
;; ;; stays the right size no matter what theme I use.
;; ;; (if (eq jib/computer 'laptop)
;; ;;     (setq jib-doom-modeline-text-height 135) ;; If laptop
;; ;;   (setq jib-doom-modeline-text-height 140))  ;; If desktop

;; ;; (if (eq jib/computer 'laptop)
;; ;;     (setq doom-modeline-height 25) ;; If laptop
;; ;;   (setq doom-modeline-height 28))  ;; If desktop



;; (menu-bar-mode -1)
;; (scroll-bar-mode -1)
;; (setq display-line-numbers-type 'relative)
;; (global-display-line-numbers-mode)
;; (tool-bar-mode -1)


;; (frame-parameter nil 'left)
;; ;; Enable vertico
;; (use-package vertico
;;   :init
;;   (vertico-mode)

;;   ;; Different scroll margin
;;   ;; (setq vertico-scroll-margin 0)

;;   ;; Show more candidates
;;   ;; (setq vertico-count 20)

;;   ;; Grow and shrink the Vertico minibuffer
;;   ;; (setq vertico-resize t)

;;   ;; Optionally enable cycling for `vertico-next' and `vertico-previous'.
;;   ;; (setq vertico-cycle t)
;;   )

;; ;; Persist history over Emacs restarts. Vertico sorts by history position.
;; (use-package savehist
;;   :init
;;   (savehist-mode))

;; ;; A few more useful configurations...
;; (use-package emacs
;;   :init
;;   ;; Add prompt indicator to `completing-read-multiple'.
;;   ;; We display [CRM<separator>], e.g., [CRM,] if the separator is a comma.
;;   (defun crm-indicator (args)
;;     (cons (format "[CRM%s] %s"
;;                   (replace-regexp-in-string
;;                    "\\`\\[.*?]\\*\\|\\[.*?]\\*\\'" ""
;;                    crm-separator)
;;                   (car args))
;;           (cdr args)))
;;   (advice-add #'completing-read-multiple :filter-args #'crm-indicator)

;;   ;; Do not allow the cursor in the minibuffer prompt
;;   (setq minibuffer-prompt-properties
;;         '(read-only t cursor-intangible t face minibuffer-prompt))
;;   (add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)

;;   ;; Emacs 28: Hide commands in M-x which do not work in the current mode.
;;   ;; Vertico commands are hidden in normal buffers.
;;   ;; (setq read-extended-command-predicate
;;   ;;       #'command-completion-default-include-p)

;;   ;; Enable recursive minibuffers
;;   (setq enable-recursive-minibuffers t))


;; (use-package marginalia
;;   :ensure t
;;   :config
;;   (marginalia-mode))

;; ;; Example configuration for Consult
;; (use-package consult
;;   ;; Replace bindings. Lazily loaded due by `use-package'.
;;   :bind (;; C-c bindings (mode-specific-map)
;;          ("C-c h" . consult-history)
;;          ("C-c m" . consult-mode-command)
;;          ("C-c k" . consult-kmacro)
;;          ;; C-x bindings (ctl-x-map)
;;          ("C-x M-:" . consult-complex-command)     ;; orig. repeat-complex-command
;;          ("C-x b" . consult-buffer)                ;; orig. switch-to-buffer
;;          ("C-x 4 b" . consult-buffer-other-window) ;; orig. switch-to-buffer-other-window
;;          ("C-x 5 b" . consult-buffer-other-frame)  ;; orig. switch-to-buffer-other-frame
;;          ("C-x r b" . consult-bookmark)            ;; orig. bookmark-jump
;;          ("C-x p b" . consult-project-buffer)      ;; orig. project-switch-to-buffer
;;          ;; Custom M-# bindings for fast register access
;;          ("M-#" . consult-register-load)
;;          ("M-'" . consult-register-store)          ;; orig. abbrev-prefix-mark (unrelated)
;;          ("C-M-#" . consult-register)
;;          ;; Other custom bindings
;;          ("M-y" . consult-yank-pop)                ;; orig. yank-pop
;;          ("<help> a" . consult-apropos)            ;; orig. apropos-command
;;          ;; M-g bindings (goto-map)
;;          ("M-g e" . consult-compile-error)
;;          ("M-g f" . consult-flymake)               ;; Alternative: consult-flycheck
;;          ("M-g g" . consult-goto-line)             ;; orig. goto-line
;;          ("M-g M-g" . consult-goto-line)           ;; orig. goto-line
;;          ("M-g o" . consult-outline)               ;; Alternative: consult-org-heading
;;          ("M-g m" . consult-mark)
;;          ("M-g k" . consult-global-mark)
;;          ("M-g i" . consult-imenu)
;;          ("M-g I" . consult-imenu-multi)
;;          ;; M-s bindings (search-map)
;;          ("M-s d" . consult-find)
;;          ("M-s D" . consult-locate)
;;          ("M-s g" . consult-grep)
;;          ("M-s G" . consult-git-grep)
;;          ("M-s r" . consult-ripgrep)
;;          ("M-s l" . consult-line)
;;          ("M-s L" . consult-line-multi)
;;          ("M-s m" . consult-multi-occur)
;;          ("M-s k" . consult-keep-lines)
;;          ("M-s u" . consult-focus-lines)
;;          ;; Isearch integration
;;          ("M-s e" . consult-isearch-history)
;;          :map isearch-mode-map
;;          ("M-e" . consult-isearch-history)         ;; orig. isearch-edit-string
;;          ("M-s e" . consult-isearch-history)       ;; orig. isearch-edit-string
;;          ("M-s l" . consult-line)                  ;; needed by consult-line to detect isearch
;;          ("M-s L" . consult-line-multi)            ;; needed by consult-line to detect isearch
;;          ;; Minibuffer history
;;          :map minibuffer-local-map
;;          ("M-s" . consult-history)                 ;; orig. next-matching-history-element
;;          ("M-r" . consult-history))                ;; orig. previous-matching-history-element

;;   ;; Enable automatic preview at point in the *Completions* buffer. This is
;;   ;; relevant when you use the default completion UI.
;;   :hook (completion-list-mode . consult-preview-at-point-mode)

;;   ;; The :init configuration is always executed (Not lazy)
;;   :init

;;   ;; Optionally configure the register formatting. This improves the register
;;   ;; preview for `consult-register', `consult-register-load',
;;   ;; `consult-register-store' and the Emacs built-ins.
;;   (setq register-preview-delay 0.5
;;         register-preview-function #'consult-register-format)

;;   ;; Optionally tweak the register preview window.
;;   ;; This adds thin lines, sorting and hides the mode line of the window.
;;   (advice-add #'register-preview :override #'consult-register-window)

;;   ;; Use Consult to select xref locations with preview
;;   (setq xref-show-xrefs-function #'consult-xref
;;         xref-show-definitions-function #'consult-xref)

;;   ;; Configure other variables and modes in the :config section,
;;   ;; after lazily loading the package.
;;   :config

;;   ;; Optionally configure preview. The default value
;;   ;; is 'any, such that any key triggers the preview.
;;   ;; (setq consult-preview-key 'any)
;;   ;; (setq consult-preview-key (kbd "M-."))
;;   ;; (setq consult-preview-key (list (kbd "<S-down>") (kbd "<S-up>")))
;;   ;; For some commands and buffer sources it is useful to configure the
;;   ;; :preview-key on a per-command basis using the `consult-customize' macro.
;;   (consult-customize
;;    consult-theme
;;    :preview-key '(:debounce 0.2 any)
;;    consult-ripgrep consult-git-grep consult-grep
;;    consult-bookmark consult-recent-file consult-xref
;;    consult--source-bookmark consult--source-recent-file
;;    consult--source-project-recent-file
;;    :preview-key (kbd "M-."))

;;   ;; Optionally configure the narrowing key.
;;   ;; Both < and C-+ work reasonably well.
;;   (setq consult-narrow-key "<") ;; (kbd "C-+")

;;   ;; Optionally make narrowing help available in the minibuffer.
;;   ;; You may want to use `embark-prefix-help-command' or which-key instead.
;;   ;; (define-key consult-narrow-map (vconcat consult-narrow-key "?") #'consult-narrow-help)

;;   ;; By default `consult-project-function' uses `project-root' from project.el.
;;   ;; Optionally configure a different project root function.
;;   ;; There are multiple reasonable alternatives to chose from.
;;   ;;;; 1. project.el (the default)
;;   ;; (setq consult-project-function #'consult--default-project--function)
;;   ;;;; 2. projectile.el (projectile-project-root)
;;   ;; (autoload 'projectile-project-root "projectile")
;;   ;; (setq consult-project-function (lambda (_) (projectile-project-root)))
;;   ;;;; 3. vc.el (vc-root-dir)
;;   ;; (setq consult-project-function (lambda (_) (vc-root-dir)))
;;   ;;;; 4. locate-dominating-file
;;   ;; (setq consult-project-function (lambda (_) (locate-dominating-file "." ".git")))
;; )


;; (use-package projectile)

;; (use-package embark
;;   :ensure t

;;   :bind
;;   (("C-." . embark-act)         ;; pick some comfortable binding
;;    ("C-;" . embark-dwim)        ;; good alternative: M-.
;;    ("C-h B" . embark-bindings)) ;; alternative for `describe-bindings'

;;   :init

;;   ;; Optionally replace the key help with a completing-read interface
;;   (setq prefix-help-command #'embark-prefix-help-command)

;;   :config

;;   ;; Hide the mode line of the Embark live/completions buffers
;;   (add-to-list 'display-buffer-alist
;;                '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
;;                  nil
;;                  (window-parameters (mode-line-format . none)))))

;; ;; Consult users will also want the embark-consult package.
;; (use-package embark-consult
;;   :ensure t
;;   :after (embark consult)
;;   :demand t ; only necessary if you have the hook below
;;   ;; if you want to have consult previews as you move around an
;;   ;; auto-updating embark collect buffer
;;   :hook
;;   (embark-collect-mode . consult-preview-at-point-mode))

;; ;; Optionally use the `orderless' completion style.
;; (use-package orderless
;;   :init
;;   ;; Configure a custom style dispatcher (see the Consult wiki)
;;   ;; (setq orderless-style-dispatchers '(+orderless-dispatch)
;;   ;;       orderless-component-separator #'orderless-escapable-split-on-space)
;;   (setq completion-styles '(orderless basic)
;;         completion-category-defaults nil
;;         completion-category-overrides '((file (styles partial-completion)))))

;; ;;; For packaged versions which must use `require':
;; (use-package modus-themes
;;   :ensure
;;   :init
;;   ;; Add all your customizations prior to loading the themes
;;   (setq modus-themes-italic-constructs t
;;         modus-themes-bold-constructs nil
;;         modus-themes-region '(bg-only no-extend))

;;   ;; Load the theme files before enabling a theme
;;   (modus-themes-load-themes)
;;   :config
;;   ;; Load the theme of your choice:
;;   (modus-themes-load-vivendi) ;; OR (modus-themes-load-vivendi)
;;   :bind ("<f5>" . modus-themes-toggle))

;; (use-package smartparens
;;   :diminish smartparens-mode
;;   :defer 1
;;   :config
;;   ;; Load default smartparens rules for various languages
;;   (require 'smartparens-config)
;;   (setq sp-max-prefix-length 25)
;;   (setq sp-max-pair-length 4)
;;   (setq sp-highlight-pair-overlay nil
;;         sp-highlight-wrap-overlay nil
;;         sp-highlight-wrap-tag-overlay nil)

;;   (with-eval-after-load 'evil
;;     (setq sp-show-pair-from-inside t)
;;     (setq sp-cancel-autoskip-on-backward-movement nil)
;;     (setq sp-pair-overlay-keymap (make-sparse-keymap)))

;;   (let ((unless-list '(sp-point-before-word-p
;;                        sp-point-after-word-p
;;                        sp-point-before-same-p)))
;;     (sp-pair "'"  nil :unless unless-list)
;;     (sp-pair "\"" nil :unless unless-list))

;;   ;; In lisps ( should open a new form if before another parenthesis
;;   (sp-local-pair sp-lisp-modes "(" ")" :unless '(:rem sp-point-before-same-p))

;;   ;; Don't do square-bracket space-expansion where it doesn't make sense to
;;   (sp-local-pair '(emacs-lisp-mode org-mode markdown-mode gfm-mode)
;;                  "[" nil :post-handlers '(:rem ("| " "SPC")))


;;   (dolist (brace '("(" "{" "["))
;;     (sp-pair brace nil
;;              :post-handlers '(("||\n[i]" "RET") ("| " "SPC"))
;;              ;; Don't autopair opening braces if before a word character or
;;              ;; other opening brace. The rationale: it interferes with manual
;;              ;; balancing of braces, and is odd form to have s-exps with no
;;              ;; whitespace in between, e.g. ()()(). Insert whitespace if
;;              ;; genuinely want to start a new form in the middle of a word.
;;              :unless '(sp-point-before-word-p sp-point-before-same-p)))
;;   (smartparens-global-mode t))

;; ;; "Enable Flyspell mode, which highlights all misspelled words. "
;; (use-package flyspell
;;   :defer t
;;   :config

;;   (add-to-list 'ispell-skip-region-alist '("~" "~"))
;;   (add-to-list 'ispell-skip-region-alist '("=" "="))
;;   (add-to-list 'ispell-skip-region-alist '("^#\\+BEGIN_SRC" . "^#\\+END_SRC"))
;;   (add-to-list 'ispell-skip-region-alist '("^#\\+BEGIN_EXPORT" . "^#\\+END_EXPORT"))
;;   (add-to-list 'ispell-skip-region-alist '("^#\\+BEGIN_EXPORT" . "^#\\+END_EXPORT"))
;;   (add-to-list 'ispell-skip-region-alist '(":\\(PROPERTIES\\|LOGBOOK\\):" . ":END:"))

;;   (dolist (mode '(org-mode-hook
;;                   mu4e-compose-mode-hook))
;;     (add-hook mode (lambda () (flyspell-mode 1))))

;;   (setq ispell-extra-args '("--sug-mode=ultra"))

;;   (setq flyspell-issue-welcome-flag nil
;;         flyspell-issue-message-flag nil)

;;   :general ;; Switches correct word from middle click to right click
;;   (general-define-key :keymaps 'flyspell-mouse-map
;;                       "<mouse-3>" #'ispell-word
;;                       "<mouse-2>" nil)
;;   (general-define-key :keymaps 'evil-motion-state-map
;;                       "zz" #'ispell-word)
;;   )

;; (use-package flyspell-correct
;;   :after flyspell
;;   :bind (:map flyspell-mode-map ("C-;" . flyspell-correct-wrapper)))

;; (use-package evil-anzu :defer t)

;; (use-package org-super-agenda
;;   :after org
;;   :config
;;   (setq org-super-agenda-header-map nil) ;; takes over 'j'
;;   (setq org-super-agenda-header-prefix " ◦ ") ;; There are some unicode "THIN SPACE"s after the ◦
;;   (org-super-agenda-mode))

;; (use-package org-superstar
;;   :config
;;   (setq org-superstar-leading-bullet " ")
;;   (setq org-superstar-special-todo-items t) ;; Makes TODO header bullets into boxes
;;   (setq org-superstar-todo-bullet-alist '(("TODO" . 9744)
;;                                           ("INPROG-TODO" . 9744)
;;                                           ("HW" . 9744)
;;                                           ("STUDY" . 9744)
;;                                           ("SOMEDAY" . 9744)
;;                                           ("READ" . 9744)
;;                                           ("PROJ" . 9744)
;;                                           ("CONTACT" . 9744)
;;                                           ("DONE" . 9745)))
;;   :hook (org-mode . org-superstar-mode))

;; ;; Removes gap when you add a new heading
;; (setq org-blank-before-new-entry '((heading . nil) (plain-list-item . nil)))


;; (use-package evil-org
;;   :diminish evil-org-mode
;;   :after org
;;   :config
;;   (add-hook 'org-mode-hook 'evil-org-mode)
;;   (add-hook 'evil-org-mode-hook
;;             (lambda () (evil-org-set-key-theme))))

;; (require 'evil-org-agenda)
;; (evil-org-agenda-set-keys)

;; (setq org-modules '(org-habit))

;; (eval-after-load 'org
;;   '(org-load-modules-maybe t))

;; (use-package org-ql
;;   :general
;;   (general-define-key :keymaps 'org-ql-view-map
;;                       "q" 'kill-buffer-and-window)
;;   )

;; (general-def
;;   :states 'normal
;;   :keymaps 'org-mode-map
;;   "t" 'org-todo
;;   "<return>" 'org-open-at-point-global
;;   "K" 'org-shiftup

;;   "J" 'org-shiftdown
;;  "TAB" 'org-cycle
;;   )

;; (general-def
;;   :states 'insert
;;   :keymaps 'org-mode-map
;;   "C-o" 'evil-org-open-above)

;; (general-def
;;   :states '(normal insert emacs)
;;   :keymaps 'org-mode-map
;;   "M-[" 'org-metaleft
;;   "M-]" 'org-metaright
;;   "C-M-=" 'ap/org-count-words
;;   "s-r" 'org-refile
;;   "M-k" 'org-insert-link
;;   )

;; ;; Org-src - when editing an org source block
;; (general-def
;;   :prefix ","
;;   :states 'normal
;;   :keymaps 'org-src-mode-map
;;   "b" '(nil :which-key "org src")
;;   "bc" 'org-edit-src-abort
;;   "bb" 'org-edit-src-exit
;;   )

;; (general-define-key
;;  :prefix ","
;;  :states 'motion
;;  :keymaps '(org-mode-map) ;; Available in org mode, org agenda
;;  "" nil
;;  "A" '(org-archive-subtree-default :which-key "org-archive")
;;  "a" '(org-agenda :which-key "org agenda")
;;  "6" '(org-sort :which-key "sort")
;;  "c" '(org-capture :which-key "org-capture")
;;  "s" '(org-schedule :which-key "schedule")
;;  ;; "S" '(jib/org-schedule-tomorrow :which-key "schedule")
;;  "d" '(org-deadline :which-key "deadline")
;;  "g" '(counsel-org-goto :which-key "goto heading")
;;  "t" '(counsel-org-tag :which-key "set tags")
;;  "p" '(org-set-property :which-key "set property")
;;  ;; "r" '(jib/org-refile-this-file :which-key "refile in file")
;;  "e" '(org-export-dispatch :which-key "export org")
;;  "B" '(org-toggle-narrow-to-subtree :which-key "toggle narrow to subtree")
;;  ;; "v" '(jib/org-set-startup-visibility :which-key "startup visibility")
;;  "H" '(org-html-convert-region-to-html :which-key "convert region to html")

;;  "1" '(org-toggle-link-display :which-key "toggle link display")
;;  "2" '(org-toggle-inline-images :which-key "toggle images")

;;  ;; org-babel
;;  "b" '(nil :which-key "babel")
;;  "bt" '(org-babel-tangle :which-key "org-babel-tangle")
;;  "bb" '(org-edit-special :which-key "org-edit-special")
;;  "bc" '(org-edit-src-abort :which-key "org-edit-src-abort")
;;  "bk" '(org-babel-remove-result-one-or-many :which-key "org-babel-remove-result-one-or-many")

;;  "x" '(nil :which-key "text")
;;  ;; "xb" (spacemacs|org-emphasize spacemacs|org-bold ?*)
;;  ;; "xb" (spacemacs|org-emphasize spacemacs|org-bold ?*)
;;  ;; "xc" (spacemacs|org-emphasize spacemacs|org-code ?~)
;;  ;; "xi" (spacemacs|org-emphasize spacemacs|org-italic ?/)
;;  ;; "xs" (spacemacs|org-emphasize spacemacs|org-strike-through ?+)
;;  ;; "xu" (spacemacs|org-emphasize spacemacs|org-underline ?_)
;;  ;; "xv" (spacemacs|org-emphasize spacemacs|org-verbose ?~) ;; I realized that ~~ is the same and better than == (Github won't do ==)

;;  ;; insert
;;  "i" '(nil :which-key "insert")

;;  "it" '(nil :which-key "tables")
;;  "itt" '(org-table-create :which-key "create table")
;;  "itl" '(org-table-insert-hline :which-key "table hline")

;;  "il" '(org-insert-link :which-key "org-insert-link")
;;  "iL" '(counsel-org-link :which-key "counsel-org-link")

;;  "is" '(nil :which-key "insert stamp")
;;  "iss" '((lambda () (interactive) (call-interactively (org-time-stamp-inactive))) :which-key "org-time-stamp-inactive")
;;  "isS" '((lambda () (interactive) (call-interactively (org-time-stamp nil))) :which-key "org-time-stamp")

;;  ;; clocking
;;  "c" '(nil :which-key "clocking")
;;  "ci" '(org-clock-in :which-key "clock in")
;;  "co" '(org-clock-out :which-key "clock out")
;;  "cj" '(org-clock-goto :which-key "jump to clock")
;;  )


;; ;; Org-agenda
;; (general-define-key
;;  :prefix ","
;;  :states 'motion
;;  :keymaps '(org-agenda-mode-map) ;; Available in org mode, org agenda
;;  "" nil
;;  "a" '(org-agenda :which-key "org agenda")
;;  "c" '(org-capture :which-key "org-capture")
;;  "s" '(org-agenda-schedule :which-key "schedule")
;;  "d" '(org-agenda-deadline :which-key "deadline")
;;  "t" '(org-agenda-set-tags :which-key "set tags")
;;  ;; clocking
;;  "c" '(nil :which-key "clocking")
;;  "ci" '(org-agenda-clock-in :which-key "clock in")
;;  "co" '(org-agenda-clock-out :which-key "clock out")
;;  "cj" '(org-clock-goto :which-key "jump to clock")
;;  )

;; (evil-define-key 'motion org-agenda-mode-map
;;   (kbd "f") 'org-agenda-later
;;   (kbd "b") 'org-agenda-earlier)


;; (defun a3madkour/org-font-setup ()
;;   ;; (set-face-attribute 'org-document-title nil :height 1.1) ;; Bigger titles, smaller drawers
;;   (set-face-attribute 'org-checkbox-statistics-done nil :inherit 'org-done :foreground "green3") ;; Makes org done checkboxes green
;;   ;; (set-face-attribute 'org-drawer nil :inherit 'fixed-pitch :inherit 'shadow :height 0.6 :foreground nil) ;; Makes org-drawer way smaller
;;   ;; (set-face-attribute 'org-ellipsis nil :inherit 'shadow :height 0.8) ;; Makes org-ellipsis shadow (blends in better)
;;   (set-face-attribute 'org-scheduled-today nil :weight 'normal) ;; Removes bold from org-scheduled-today
;;   (set-face-attribute 'org-super-agenda-header nil :inherit 'org-agenda-structure :weight 'bold) ;; Bolds org-super-agenda headers
;;   (set-face-attribute 'org-scheduled-previously nil :background "red") ;; Bolds org-super-agenda headers

;;   ;; Here I set things that need it to be fixed-pitch, just in case the font I am using isn't monospace.
;;   ;; (dolist (face '(org-list-dt org-tag org-todo org-table org-checkbox org-priority org-date org-verbatim org-special-keyword))
;;   ;;   (set-face-attribute `,face nil :inherit 'fixed-pitch))

;;   ;; (dolist (face '(org-code org-verbatim org-meta-line))
;;   ;;   (set-face-attribute `,face nil :inherit 'shadow :inherit 'fixed-pitch))
;;   )


;; (defun a3madkour/org-setup ()
;;   (org-indent-mode) ;; Keeps org items like text under headings, lists, nicely indented
;;   (visual-line-mode 1) ;; Nice line wrapping

;;   (centered-cursor-mode)

;;   (smartparens-mode 0)

;;   ;; (setq header-line-format "") ;; Empty header line, basically adds a blank line on top

;; (setq
;;  org_notes "~/org/notes"
;;  zot_bib  "~/org/notes/library.bib"
;;  deft-directory org_notes
;;  ;; deft-strip-summary-regexp ":PROPERTIES:\n\\(.+\n\\)+:END:\n"
;;  org-cite-default-bibliography (list zot_bib)
;;  org-cite-csl-styles-dir "~/Zotero/styles"
;;  org-cite-global-bibliography (list zot_bib)
;;  ;; deft-use-filename-as-title 't
;;  ;; deft-recursive 't
;;  org-roam-directory org_notes

;;   )
;;   )


;;   (require 'org-tempo)
;;   (add-to-list 'org-structure-template-alist '("sh" . "src sh"))
;;   (add-to-list 'org-structure-template-alist '("el" . "src emacs-lisp"))
;;   (add-to-list 'org-structure-template-alist '("sc" . "src scheme"))
;;   (add-to-list 'org-structure-template-alist '("ts" . "src typescript"))
;;   (add-to-list 'org-structure-template-alist '("py" . "src python"))
;;   (add-to-list 'org-structure-template-alist '("yaml" . "src yaml"))
;;   (add-to-list 'org-structure-template-alist '("json" . "src json"))

;; (use-package magit :defer t)
;; (use-package magit-todos :defer t)
;; (use-package unfill :defer t)
;; (use-package burly :defer t)
;; (use-package ace-window :defer t)
;; (use-package org-real :defer t)
;; (use-package centered-cursor-mode :diminish centered-cursor-mode)
;; (use-package restart-emacs :defer t)
;; (use-package diminish)
;; (use-package reveal-in-osx-finder :commands (reveal-in-osx-finder))

;; (use-package bufler
;;   :general
;;   (:keymaps 'bufler-list-mode-map "Q" 'kill-this-buffer))

;; (use-package xwidget
;;   :general
;;   (general-define-key :states 'normal :keymaps 'xwidget-webkit-mode-map 
;;                       "j" 'xwidget-webkit-scroll-up-line
;;                       "k" 'xwidget-webkit-scroll-down-line
;;                       "gg" 'xwidget-webkit-scroll-top
;;                       "G" 'xwidget-webkit-scroll-bottom))

;; (use-package mw-thesaurus
;;   :defer t
;;   :config
;;   (add-hook 'mw-thesaurus-mode-hook (lambda () (define-key evil-normal-state-local-map (kbd "q") 'mw-thesaurus--quit))))

;; ;; (use-package ansi-term
;; ;;   :ensure nil
;; ;;   :general
;; ;;   (:keymaps 'term-mode-map
;; ;;             "<up>" 'term-previous-input
;; ;;             "<down>" 'term-next-input))

;; ;; https://github.com/oantolin/epithet
;; (use-package epithet
;;   :ensure nil
;;   :config
;;   (add-hook 'Info-selection-hook #'epithet-rename-buffer)
;;   (add-hook 'help-mode-hook #'epithet-rename-buffer))

;; ;; https://github.com/udyantw/most-used-words
;; (use-package most-used-words :ensure nil)
;; (defun a3madkour/deft-kill ()
;;   (kill-buffer "*Deft*"))

;; (defun a3madkour/deft-evil-fix ()
;;   (evil-insert-state)
;;   (centered-cursor-mode))

;; (use-package deft
;;   :config
;;   (setq deft-directory (concat a3madkour/dropbox "notes/")
;;         deft-extensions '("org" "txt")
;;         deft-recursive t
;;         deft-file-limit 40
;;         deft-use-filename-as-title t)

;;   (add-hook 'deft-open-file-hook 'a3madkour/deft-kill) ;; Once a file is opened, kill Deft
;;   (add-hook 'deft-mode-hook 'a3madkour/deft-evil-fix) ;; Goes into insert mode automaticlly in Deft

;;   ;; Removes :PROPERTIES: from descriptions
;;   (setq deft-strip-summary-regexp ":PROPERTIES:\n\\(.+\n\\)+:END:\n")
;;   :general

;;   (general-define-key :states 'normal :keymaps 'deft-mode-map
;;                       ;; 'q' kills Deft in normal mode
;;                       "q" 'kill-this-buffer)

;;   (general-define-key :states 'insert :keymaps 'deft-mode-map
;;                       "C-j" 'next-line
;;                       "C-k" 'previous-line)
;;   )
;; (use-package auctex ;; This is a weird one. Package is auctex but needs to be managed like this.
;;   :ensure nil
;;   :defer t
;;   :init
;;   (setq TeX-engine 'xetex ;; Use XeTeX
;;         latex-run-command "xetex")

;;   (setq TeX-parse-self t ; parse on load
;;         TeX-auto-save t  ; parse on save
;;         ;; Use directories in a hidden away folder for AUCTeX files.
;;         TeX-auto-local (concat user-emacs-directory "auctex/auto/")
;;         TeX-style-local (concat user-emacs-directory "auctex/style/")

;;         TeX-source-correlate-mode t
;;         TeX-source-correlate-method 'synctex

;;         TeX-show-compilation nil

;;         ;; Don't start the Emacs server when correlating sources.
;;         TeX-source-correlate-start-server nil

;;         ;; Automatically insert braces after sub/superscript in `LaTeX-math-mode'.
;;         TeX-electric-sub-and-superscript t
;;         ;; Just save, don't ask before each compilation.
;;         TeX-save-query nil)

;;   ;; To use pdfview with auctex:
;;   (setq TeX-view-program-selection '((output-pdf "PDF Tools"))
;;         TeX-view-program-list '(("PDF Tools" TeX-pdf-tools-sync-view))
;;         TeX-source-correlate-start-server t)
;;   :general
;;   (general-define-key
;;     :prefix ","
;;     :states 'normal
;;     :keymaps 'LaTeX-mode-map
;;     "" nil
;;     "a" '(TeX-command-run-all :which-key "TeX run all")
;;     "c" '(TeX-command-master :which-key "TeX-command-master")
;;     "c" '(TeX-command-master :which-key "TeX-command-master")
;;     "e" '(LaTeX-environment :which-key "Insert environment")
;;     "s" '(LaTeX-section :which-key "Insert section")
;;     "m" '(TeX-insert-macro :which-key "Insert macro")
;;     )

;;   )

;; (add-hook 'TeX-after-compilation-finished-functions #'TeX-revert-document-buffer) ;; Standard way

;; (use-package company-auctex
;;   :after auctex
;;   :init
;;   (add-to-list 'company-backends 'company-auctex)
;;   (company-auctex-init))


;; (use-package pdf-tools
;;   :defer t
;;   :mode  ("\\.pdf\\'" . pdf-view-mode)
;;   :config
;;   (pdf-loader-install)
;;   (push 'pdf-view-midnight-minor-mode pdf-tools-enabled-modes)
;;   (setq-default pdf-view-display-size 'fit-height)
;;   (setq pdf-view-continuous nil) ;; Makes it so scrolling down to the bottom/top of a page doesn't switch to the next page
;;   (setq pdf-view-midnight-colors '("#ffffff" . "#121212" )) ;; I use midnight mode as dark mode, dark mode doesn't seem to work
;;   :general
;;   (general-define-key :states 'motion :keymaps 'pdf-view-mode-map
;;                       "j" 'pdf-view-next-page
;;                       "k" 'pdf-view-previous-page

;;                       "C-j" 'pdf-view-next-line-or-next-page
;;                       "C-k" 'pdf-view-previous-line-or-previous-page

;;                       ;; Arrows for movement as well
;;                       (kbd "<down>") 'pdf-view-next-line-or-next-page
;;                       (kbd "<up>") 'pdf-view-previous-line-or-previous-page

;;                       (kbd "<down>") 'pdf-view-next-line-or-next-page
;;                       (kbd "<up>") 'pdf-view-previous-line-or-previous-page

;;                       (kbd "<left>") 'image-backward-hscroll
;;                       (kbd "<right>") 'image-forward-hscroll

;;                       "H" 'pdf-view-fit-height-to-window
;;                       "0" 'pdf-view-fit-height-to-window
;;                       "W" 'pdf-view-fit-width-to-window
;;                       "=" 'pdf-view-enlarge
;;                       "-" 'pdf-view-shrink

;;                       "q" 'quit-window
;;                       "Q" 'kill-this-buffer
;;                       "g" 'revert-buffer
;;                       )
;;   )

;; (use-package popper
;;   :bind (("C-`"   . popper-toggle-latest)
;;          ("M-`"   . popper-cycle)
;;          ("C-M-`" . popper-toggle-type))
;;   :init
;;   (setq popper-reference-buffers
;;         '("\\*Messages\\*"
;;           "Output\\*$"
;;           "\\*Warnings\\*"
;;           help-mode
;;           compilation-mode))
;;   (popper-mode +1))
;; (use-package rainbow-mode
;;   :defer t)

;; (use-package hl-todo
;;   :defer t
;;   :hook (prog-mode . hl-todo-mode)
;;   :config
;;   (setq hl-todo-keyword-faces
;;       '(("TODO"   . "#FF0000")
;;         ("FIXME"  . "#FF4500")
;;         ("DEBUG"  . "#A020F0")
;;         ("WIP"   . "#1E90FF"))))
;; (use-package lsp-mode
;;   :init
;;   ;; set prefix for lsp-command-keymap (few alternatives - "C-l", "C-c l")
;;   (setq lsp-keymap-prefix "C-c l")
;;   :hook (;; replace XXX-mode with concrete major-mode(e. g. python-mode)
;;          (XXX-mode . lsp)
;;          ;; if you want which-key integration
;;          (lsp-mode . lsp-enable-which-key-integration))
;;   :commands lsp)

;; ;; optionally
;; (use-package lsp-ui :commands lsp-ui-mode)
;; (use-package consult-lsp)
;; (use-package eglot)

;; ;; optionally if you want to use debugger
;; (use-package dap-mode)
;; ;; (use-package dap-LANGUAGE) to load the dap adapter for your language

;; ;; optional if you want which-key integration
;; (use-package which-key
;;     :config
;;     (which-key-mode))

;; (use-package rustic)
;; (setq rustic-lsp-server 'rls)
;; (setq rustic-analyzer-command '("~/.cargo/bin/rust-analyzer"))

;; (use-package academic-phrases)
;; (use-package fountain-mode)
;; (use-package rg)
;; (use-package dash-docs
;;   :config
;;   (setq dash-docs-docsets-path "~/.docsets")
;; (setq installed-langs (dash-docs-installed-docsets))
;; ;;figure out to convert spaces into underscores when installing the docs
;; (setq docset-langs '("Rust" "Emacs_Lisp" "JavaScript" "C" "Bash" "Vim" "SQLite" "PostgreSQL" "OpenGL_4" "OCaml" "LaTeX" "Docker" "C++" "HTML" "SVG" "CSS"  "Haskell" "React" "D3JS"))
;; (dolist (lang docset-langs)
;; (when (null (member lang installed-langs))
;;   (dash-docs-install-docset lang)
;; ))


;;   )
;; (use-package gdscript-mode
;;     :straight (gdscript-mode
;;                :type git
;;                :host github
;;                :repo "godotengine/emacs-gdscript-mode"))
;; (use-package doom-themes
;;   :ensure t
;;   :config
;;   ;; Global settings (defaults)
;;   (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
;;         doom-themes-enable-italic t) ; if nil, italics is universally disabled
;; ;; (load-theme 'doom-molokai t)			 ;

;;   ;; Enable flashing mode-line on errors
;;   (doom-themes-visual-bell-config)
;;   ;; Enable custom neotree theme (all-the-icons must be installed!)
;;   (doom-themes-neotree-config)
;;   ;; or for treemacs users

;;   (setq doom-themes-treemacs-theme "doom-atom") ; use "doom-colors" for less minimal icon theme
;;   (doom-themes-treemacs-config)
;;   ;; Corrects (and improves) org-mode's native fontification.
;;   (doom-themes-org-config))
;; ;; Org-super-agenda-mode itself is activated in the use-package block
;; ;; not working right now, from https://jblevins.org/log/dired-open
;; ;; (evil-define-key 'motion 'dired-mode-map "s-o" '(lambda () (interactive)
;; ;; 												  (let ((fn (dired-get-file-for-visit)))
;; ;; 													(start-process "default-app" nil "open" fn))))




;; (use-package ranger)

;; (ranger-override-dired-mode t)

;; (use-package eshell-git-prompt
;;   :config
;;   (eshell-git-prompt-use-theme 'powerline)
;; )

;; (use-package command-log-mode)

;; ;; (use-package nav-flash)
;; ;; (nav-flash-show)
;; ;; (add-hook 'better-jumper-post-jump-hook 'nav-flash-show nil t)
;; ;; (add-hook 'rtags-after-find-file-hook 'nav-flash-show nil t)
;; ;; (add-hook 'org-follow-link-hook 'nav-flash-show nil t)
;; ;; (add-hook 'imenu-after-jump-hook 'nav-flash-show nil t)
;; ;; (add-hook 'counsel-grep-post-action-hook 'nav-flash-show nil t)
;; ;; (add-hook 'dumb-jump-after-jump-hook 'nav-flash-show nil t)

;; (use-package pulsar
;;   :config
;;   (setq pulsar-pulse-functions
;;       ;; NOTE 2022-04-09: The commented out functions are from before
;;       ;; the introduction of `pulsar-pulse-on-window-change'.  Try that
;;       ;; instead.
;;       '(recenter-top-bottom
;;         move-to-window-line-top-bottom
;;         reposition-window
;;         ;; bookmark-jump
;;         ;; other-window
;;         ;; delete-window
;;         ;; delete-other-windows
;;         forward-page
;; 		consult-imenu
;;         backward-page
;;         scroll-up-command
;;         scroll-down-command
;;         ;; windmove-right
;;         ;; windmove-left
;;         ;; windmove-up
;;         ;; windmove-down
;;         ;; windmove-swap-states-right
;;         ;; windmove-swap-states-left
;;         ;; windmove-swap-states-up
;;         ;; windmove-swap-states-down
;;         ;; tab-new
;;         ;; tab-close
;;         ;; tab-next
;;         org-next-visible-heading
;;         org-previous-visible-heading
;;         org-forward-heading-same-level
;;         org-backward-heading-same-level
;;         outline-backward-same-level
;;         outline-forward-same-level
;;         outline-next-visible-heading
;;         outline-previous-visible-heading
;;         outline-up-heading))

;; (setq pulsar-pulse-on-window-change t)
;; (setq pulsar-pulse t)
;; (setq pulsar-delay 0.055)
;; (setq pulsar-iterations 10)
;; (setq pulsar-face 'pulsar-magenta)
;; (setq pulsar-highlight-face 'pulsar-yellow)

;; (pulsar-global-mode 1)
;;   )

;; ;;  (evil-define-key 'motion 'dired-mode-map "Q" 'kill-this-buffer)
;; (custom-set-variables
;;  ;; custom-set-variables was added by Custom.
;;  ;; If you edit it by hand, you could mess it up, so be careful.
;;  ;; Your init file should contain only one such instance.
;;  ;; If there is more than one, they won't work right.
;;  '(custom-safe-themes
;;    '("be84a2e5c70f991051d4aaf0f049fa11c172e5d784727e0b525565bb1533ec78" "b54376ec363568656d54578d28b95382854f62b74c32077821fdfd604268616a" "251ed7ecd97af314cd77b07359a09da12dcd97be35e3ab761d4a92d8d8cf9a71" "b99e334a4019a2caa71e1d6445fc346c6f074a05fcbb989800ecbe54474ae1b0" default)))
;; (custom-set-faces
;;  ;; custom-set-faces was added by Custom.
;;  ;; If you edit it by hand, you could mess it up, so be careful.
;;  ;; Your init file should contain only one such instance.
;;  ;; If there is more than one, they won't work right.
;;  '(company-tooltip ((t (:family "Roboto Mono")))))
