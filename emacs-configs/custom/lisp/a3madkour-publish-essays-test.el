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

(provide 'a3madkour-publish-essays-test)

;;; a3madkour-publish-essays-test.el ends here
