;;; a3madkour-recipe-lint.el --- recipe pre-publish linter  -*- lexical-binding: t; -*-
;;; Code:
(defvar a3madkour-recipe-lint-enabled t
  "When nil, the recipes handler skips the lint gate (--skip-recipe-check).")
(defun a3madkour-recipe-lint/lint-file (_file)
  "Stub — real rules land in Task 9.  Returns nil (no errors)."
  nil)
(provide 'a3madkour-recipe-lint)
;;; a3madkour-recipe-lint.el ends here
