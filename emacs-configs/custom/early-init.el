;; [[file:config.org::*Early Init][Early Init:1]]
(setq gc-cons-percentage 0.6)
(setq native-comp-async-report-warnings-errors 'silent) ;; native-comp warning
(setq byte-compile-warnings '(not free-vars unresolved noruntime lexical make-local))

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
;; Early Init:1 ends here
