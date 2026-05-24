;;; a3madkour-publish-unpublish.el --- Unpublish flow + orchestrator (A.1.d) -*- lexical-binding: t; -*-

;;; Commentary:
;; Phase 3 sub-project A.1.d.  Implements the three-step unpublish
;; orchestrator + --check-orphans dry-run preview, closing parent spec
;; §12 A.1 item #7.
;;
;;   Step A — unpublish sweep: diff new live-set vs manifest, delete
;;            stale page bundles, mutate manifest entries.
;;   Step B — slug-shift sync: rename ~/org/notes/assets/page/<old>/ →
;;            <new>/ and bulk-rewrite source .org link references.
;;   Step C — re-link-check: WARN for live-note outgoing links resolving
;;            into the removed-this-publish set.
;;
;; Public entry points:
;;   `a3madkour-pub/finish-publish'    — orchestrator (commits to FS + manifest)
;;   `a3madkour-pub/check-orphans'     — thin alias for dry-run preview
;;   `a3madkour-pub/diff-published-set'      — pure diff helper
;;   `a3madkour-pub/walk-published-source-set' — standalone-mode driver
;;
;; See `docs/superpowers/specs/2026-05-24-phase-3-a1-d-unpublish-design.md'.
;;
;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-history)

(provide 'a3madkour-publish-unpublish)

;;; a3madkour-publish-unpublish.el ends here
