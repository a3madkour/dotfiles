;;; a3madkour-publish-essays.el --- B.4 essays per-file publish handler  -*- lexical-binding: t; -*-

;;; Commentary:

;; B.4: essays per-file publish handler (first publish-deliberate slice).
;; Pipeline mirrors B.1/B.3 (pre-export-rewrite → export → normalize →
;; asset-copy → write-if-different → record-publish), with a novel
;; post-export markdown body scan for the 6 `has_*' frontmatter flags.
;;
;; Registered into `a3madkour-pub-deliberate--handlers' (see Task 9) as
;;   (essays . a3madkour-pub-essays/publish-essay-file)

;;; Code:

(require 'a3madkour-publish)
(require 'a3madkour-publish-export)
(require 'a3madkour-publish-frontmatter)
(require 'a3madkour-publish-rewrite)
(require 'a3madkour-publish-assets)
(require 'a3madkour-publish-history)

;; Task 4: has_* body scanner.

(defun a3madkour-pub-essays--scan-has-flags (body)
  "Return a plist of 6 has_* booleans derived from substring scan of BODY
\(post-export markdown).

Patterns (all case-sensitive; shortcodes match the trailing space):
  :has_sidenotes  <- `{{< sidenote '
  :has_citations  <- `{{< cite '
  :has_footnotes  <- `[^N]' markdown footnote reference
  :has_math       <- `{{< math ' OR raw KaTeX delim `\\(' OR `\\['
  :has_widgets    <- `{{< widget '
  :has_video_sync <- `{{< video-sync '

Each value is `t' on a positive match or `nil' on no match.  Callers
merge with per-keyword `#+HUGO_HAS_<X>:' overrides (see Task 5)."
  (list :has_sidenotes  (and (string-match-p "{{< sidenote "   body) t)
        :has_citations  (and (string-match-p "{{< cite "        body) t)
        :has_footnotes  (and (string-match-p "\\[\\^[^]]+\\]"  body) t)
        :has_math       (and (or (string-match-p "{{< math "    body)
                                 (string-match-p "\\\\("        body)
                                 (string-match-p "\\\\\\["      body)) t)
        :has_widgets    (and (string-match-p "{{< widget "      body) t)
        :has_video_sync (and (string-match-p "{{< video-sync "  body) t)))

(provide 'a3madkour-publish-essays)

;;; a3madkour-publish-essays.el ends here
