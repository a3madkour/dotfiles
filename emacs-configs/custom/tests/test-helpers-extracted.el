;;; test-helpers-extracted.el --- Tests for refactor-extracted helpers  -*- lexical-binding: t; -*-

(require 'test-helpers)

(defmacro a3madkour-test/in-org-file (rel-path &rest body)
  (declare (indent 1) (debug t))
  `(with-current-buffer (find-file-noselect (a3madkour/org-file ,rel-path))
     (goto-char (point-min))
     ,@body))

;;; ---- a3madkour/-build-habit-repeater ----

(ert-deftest a3madkour-test/build-habit-repeater-daily ()
  (should (equal ".+1d" (a3madkour/-build-habit-repeater "daily" nil)))
  (should (equal ".+1d" (a3madkour/-build-habit-repeater "daily" ""))))

(ert-deftest a3madkour-test/build-habit-repeater-daily-with-flexibility ()
  (should (equal ".+1d/3d" (a3madkour/-build-habit-repeater "daily" "3"))))

(ert-deftest a3madkour-test/build-habit-repeater-every-2-days ()
  (should (equal ".+2d" (a3madkour/-build-habit-repeater "every 2 days" "")))
  (should (equal ".+2d/5d" (a3madkour/-build-habit-repeater "every 2 days" "5"))))

(ert-deftest a3madkour-test/build-habit-repeater-every-3-days ()
  (should (equal ".+3d" (a3madkour/-build-habit-repeater "every 3 days" nil)))
  (should (equal ".+3d/7d" (a3madkour/-build-habit-repeater "every 3 days" "7"))))

(ert-deftest a3madkour-test/build-habit-repeater-weekly-ignores-flexibility ()
  ;; flexibility is only meaningful for daily/every-N-days; non-daily frequencies
  ;; ignore it.
  (should (equal ".+1w" (a3madkour/-build-habit-repeater "weekly" "")))
  (should (equal ".+1w" (a3madkour/-build-habit-repeater "weekly" "5"))))

(ert-deftest a3madkour-test/build-habit-repeater-biweekly ()
  (should (equal ".+2w" (a3madkour/-build-habit-repeater "biweekly" nil))))

(ert-deftest a3madkour-test/build-habit-repeater-monthly ()
  (should (equal ".+1m" (a3madkour/-build-habit-repeater "monthly" nil))))

(ert-deftest a3madkour-test/build-habit-repeater-bad-flexibility-foot-gun ()
  ;; Documented foot-gun: string-to-number of "abc" → 0. Test pins current
  ;; behavior so we notice if validation is added later.
  (should (equal ".+1d/0d" (a3madkour/-build-habit-repeater "daily" "abc"))))

;;; ---- a3madkour/-project-heading-string ----

(ert-deftest a3madkour-test/project-heading-string-basic ()
  (let ((s (a3madkour/-project-heading-string
            "MyProject" "intellectual" "active" "Done thing" "Year goal" nil nil)))
    (should (string-match-p "^\\* MyProject :intellectual:active:project:" s))
    (should (string-match-p ":DONE_ENOUGH: Done thing" s))
    (should (string-match-p ":GOAL: Year goal" s))
    (should-not (string-match-p ":REPO:" s))
    (should-not (string-match-p "^\\*\\* TODO" s))))

(ert-deftest a3madkour-test/project-heading-string-empty-goal ()
  (let ((s (a3madkour/-project-heading-string
            "Foo" "career" "inactive" "ship" "" nil nil)))
    (should (string-match-p ":GOAL: exploratory" s))))

(ert-deftest a3madkour-test/project-heading-string-with-repo ()
  (let ((s (a3madkour/-project-heading-string
            "Foo" "career" "active" "ship" "g" "/tmp/repo-dir" nil)))
    (should (string-match-p ":REPO: /tmp/repo-dir" s))))

(ert-deftest a3madkour-test/project-heading-string-with-placeholder ()
  (let ((s (a3madkour/-project-heading-string
            "Foo" "career" "active" "ship" "g" nil t)))
    (should (string-match-p "^\\*\\* TODO" s))))

(ert-deftest a3madkour-test/project-heading-string-property-drawer-shape ()
  ;; Make sure the property drawer opens with :PROPERTIES: and closes with :END:
  ;; and that we don't accidentally double-emit anything.
  (let ((s (a3madkour/-project-heading-string
            "X" "a" "i" "d" "g" nil nil)))
    (should (= 1 (cl-count-if (lambda (line) (string= line ":PROPERTIES:"))
                              (split-string s "\n"))))
    (should (= 1 (cl-count-if (lambda (line) (string= line ":END:"))
                              (split-string s "\n"))))))

;;; ---- a3madkour/-archive-current-season ----

(ert-deftest a3madkour-test/archive-current-season-renames-and-sets-prop ()
  (a3madkour-test/in-buffer "\
* Current Season: Old                                                 :foo:
:PROPERTIES:
:START: [2025-12-01 Mon]
:END:   [2026-01-15 Thu]
:END:
"
    (should (eq t (a3madkour/-archive-current-season "Did stuff")))
    (goto-char (point-min))
    (let ((content (buffer-string)))
      (should (string-match-p "^\\* ARCHIVE Season: Old" content))
      (should (string-match-p ":ACCOMPLISHED: +Did stuff" content)))))

(ert-deftest a3madkour-test/archive-current-season-no-existing-returns-nil ()
  (a3madkour-test/in-buffer "* Some project                                    :project:active:\n"
    (should (null (a3madkour/-archive-current-season "anything")))
    ;; Buffer unchanged
    (should (string-match-p "^\\* Some project" (buffer-string)))
    (should-not (string-match-p "ARCHIVE" (buffer-string)))))

;;; ---- a3madkour/-insert-new-season ----

(ert-deftest a3madkour-test/insert-new-season-tags ()
  (a3madkour-test/in-buffer ""
    (a3madkour/-insert-new-season "Spring 2026" 6 '("foo" "bar"))
    (let ((content (buffer-string)))
      (should (string-match-p "^\\* Current Season: Spring 2026" content))
      (should (string-match-p ":foo:bar:" content))
      (should (string-match-p ":PROPERTIES:" content))
      (should (string-match-p ":START:" content))
      (should (string-match-p ":END:" content)))))

(ert-deftest a3madkour-test/insert-new-season-no-tags ()
  (a3madkour-test/in-buffer ""
    (a3madkour/-insert-new-season "Quiet" 4 nil)
    (let ((content (buffer-string)))
      (should (string-match-p "^\\* Current Season: Quiet" content))
      ;; The heading line itself must not have a tag block.
      (goto-char (point-min))
      (re-search-forward "^\\* Current Season: Quiet.*$")
      (should-not (string-match-p ":[a-z]+:" (match-string 0))))))

(ert-deftest a3madkour-test/insert-new-season-skips-file-header ()
  ;; The function skips lines starting with `#' and one blank line so the new
  ;; heading lands after any #+title: / #+filetags: file headers.
  (a3madkour-test/in-buffer "\
#+title: Projects

* Existing
"
    (a3madkour/-insert-new-season "Foo" 6 nil)
    (let ((lines (split-string (buffer-string) "\n")))
      ;; First non-empty line is still the #+title.
      (should (string-prefix-p "#+title:" (car lines)))
      ;; Existing heading still present.
      (should (cl-some (lambda (l) (string= l "* Existing")) lines))
      ;; New season heading present.
      (should (cl-some (lambda (l) (string-prefix-p "* Current Season: Foo" l))
                       lines)))))

(provide 'test-helpers-extracted)
;;; test-helpers-extracted.el ends here
