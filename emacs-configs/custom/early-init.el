;; [[file:config.org::*Early Init][Early Init:1]]
;; Ensure Emacs loads the most recent byte-compiled files.
(setq load-prefer-newer t)

;; Make Emacs Native-compile .elc files asynchronously by setting
;; `native-comp-jit-compilation' to t.
(setq native-comp-jit-compilation t)
(setq native-comp-deferred-compilation native-comp-jit-compilation)  ; Deprecated
(setq gc-cons-percentage 0.6)
(setq gc-cons-threshold most-positive-fixnum)
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq native-comp-async-report-warnings-errors 'silent) ;; native-comp warning (setq byte-compile-warnings '(not free-vars unresolved noruntime lexical make-local))

(setq idle-update-delay 1.0)
;; Disabling bidi (bidirectional editing stuff)
(setq-default bidi-display-reordering 'left-to-right
			  bidi-paragraph-direction 'left-to-right)
;; (setq bidi-inhibit-bpa t)  ; emacs 27 only - disables bidirectional parenthesis
;;
(setq-default cursor-in-non-selected-windows nil)
(setq highlight-nonselected-windows nil)
(setq fast-but-imprecise-scrolling t)
(setq inhibit-compacting-font-caches t)

;; Window configuration
(setq frame-inhibit-implied-resize t) ;; Supposed to hasten startup

(setq default-file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)
;;return file-name-hanlder-alist to default after loading
(add-hook 'emacs-startup-hook
	      (lambda ()
					(setq file-name-handler-alist default-file-name-handler-alist)))
;; Early Init:1 ends here
