;;; a3madkour-publish.el --- Org → Hugo publish pipeline (sub-project A) -*- lexical-binding: t; -*-

;; Author: Abdelrahman Madkour <a3madkour@gmail.com>
;; Version: 0.1.0-bootstrap
;; Package-Requires: ((emacs "30.2"))
;; Keywords: org, hugo, publish

;;; Commentary:

;; Phase 3 sub-project A: access control + link semantics for the
;; org → Hugo publish pipeline driving https://a3madkour.github.io/.
;;
;; This is the bootstrap shell.  A.1.{a..d} implement keyword parsing,
;; slug derivation, URL-history, link rewriting, asset handling, and
;; the unpublish flow.  Consumed by sub-project B (the per-section
;; publisher) via the function surface documented in the design spec at
;; docs/superpowers/specs/2026-05-20-phase-3-access-control-link-semantics-design.md
;; (in the site repo).

;;; Code:

(defgroup a3madkour-pub nil
  "Org → Hugo publish pipeline (sub-project A: access control + link semantics)."
  :group 'org
  :prefix "a3madkour-pub/")

(defconst a3madkour-pub/version "0.1.0-bootstrap"
  "Current version of the publish library.")

(provide 'a3madkour-publish)

;;; a3madkour-publish.el ends here
