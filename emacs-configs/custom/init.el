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
