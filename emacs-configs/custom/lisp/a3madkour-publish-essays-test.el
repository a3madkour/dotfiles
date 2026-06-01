;;; a3madkour-publish-essays-test.el --- ert tests for B.4 essays handler -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-essays)

;; -- B.4 Task 4: has_* body scanner --

(ert-deftest a3madkour-pub-essays-test/scan-sidenotes-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags
                  "lorem {{< sidenote >}}x{{< /sidenote >}} ipsum")
                 :has_sidenotes))))

(ert-deftest a3madkour-pub-essays-test/scan-sidenotes-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_sidenotes)))

(ert-deftest a3madkour-pub-essays-test/scan-citations-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see {{< cite \"k\" >}} here")
                 :has_citations))))

(ert-deftest a3madkour-pub-essays-test/scan-citations-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_citations)))

(ert-deftest a3madkour-pub-essays-test/scan-footnotes-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "lorem[^1] ipsum\n\n[^1]: note")
                 :has_footnotes))))

(ert-deftest a3madkour-pub-essays-test/scan-footnotes-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only no refs")
               :has_footnotes)))

(ert-deftest a3madkour-pub-essays-test/scan-math-shortcode ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags
                  "see {{< math >}}\\alpha{{< /math >}}")
                 :has_math))))

(ert-deftest a3madkour-pub-essays-test/scan-math-inline-delim ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see \\(\\alpha\\) here")
                 :has_math))))

(ert-deftest a3madkour-pub-essays-test/scan-math-display-delim ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see \\[\\alpha\\] here")
                 :has_math))))

(ert-deftest a3madkour-pub-essays-test/scan-math-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_math)))

(ert-deftest a3madkour-pub-essays-test/scan-widgets-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see {{< widget \"x\" >}}")
                 :has_widgets))))

(ert-deftest a3madkour-pub-essays-test/scan-widgets-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_widgets)))

(ert-deftest a3madkour-pub-essays-test/scan-video-sync-positive ()
  (should (eq t (plist-get
                 (a3madkour-pub-essays--scan-has-flags "see {{< video-sync \"x\" >}}")
                 :has_video_sync))))

(ert-deftest a3madkour-pub-essays-test/scan-video-sync-negative ()
  (should-not (plist-get
               (a3madkour-pub-essays--scan-has-flags "plain text only")
               :has_video_sync)))

;; -- B.4 Task 5: has_* override merge --

(ert-deftest a3madkour-pub-essays-test/merge-keyword-override-wins-false ()
  "Body has sidenote shortcode AND #+HUGO_HAS_SIDENOTES: nil → false."
  (let ((tmp (make-temp-file "essays-merge-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+HUGO_HAS_SIDENOTES: nil\n"))
          (let* ((scan '(:has_sidenotes t :has_citations nil
                         :has_footnotes nil :has_math nil
                         :has_widgets nil :has_video_sync nil))
                 (merged (a3madkour-pub-essays--merge-has-flags scan tmp)))
            (should (eq (plist-get merged :has_sidenotes) nil))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-essays-test/merge-keyword-override-wins-true ()
  "No body shortcode but #+HUGO_HAS_WIDGETS: t → true."
  (let ((tmp (make-temp-file "essays-merge-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+HUGO_HAS_WIDGETS: t\n"))
          (let* ((scan '(:has_sidenotes nil :has_citations nil
                         :has_footnotes nil :has_math nil
                         :has_widgets nil :has_video_sync nil))
                 (merged (a3madkour-pub-essays--merge-has-flags scan tmp)))
            (should (eq (plist-get merged :has_widgets) t))))
      (delete-file tmp))))

(ert-deftest a3madkour-pub-essays-test/merge-absent-keyword-uses-scan ()
  "No #+HUGO_HAS_* keywords → scan result wins."
  (let ((tmp (make-temp-file "essays-merge-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "#+title: x\n"))
          (let* ((scan '(:has_sidenotes t :has_citations nil
                         :has_footnotes t :has_math nil
                         :has_widgets nil :has_video_sync nil))
                 (merged (a3madkour-pub-essays--merge-has-flags scan tmp)))
            (should (eq (plist-get merged :has_sidenotes) t))
            (should (eq (plist-get merged :has_citations) nil))
            (should (eq (plist-get merged :has_footnotes) t))))
      (delete-file tmp))))

(provide 'a3madkour-publish-essays-test)

;;; a3madkour-publish-essays-test.el ends here
