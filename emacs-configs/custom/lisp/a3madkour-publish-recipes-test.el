;;; a3madkour-publish-recipes-test.el --- tests for recipes handler  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-recipes)

(defun a3madkour-pub-recipes-test--parse (org-text)
  "Parse ORG-TEXT and return its element AST."
  (with-temp-buffer (insert org-text) (org-mode) (org-element-parse-buffer)))

(ert-deftest a3madkour-pub-recipes--module-loads ()
  "Smoke: module loadable and exposes the entry point."
  (should (fboundp 'a3madkour-pub-recipes/publish-recipe-file)))
