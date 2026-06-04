;;; a3madkour-publish-multi-filter-test.el --- Tests for multi-export filter -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-multi-filter)

(ert-deftest a3madkour-pub-multi-filter/detects-opt-in-keyword ()
  "Buffer with `#+multi_export: t` is recognized as multi-export."
  (with-temp-buffer
    (insert "#+title: Demo\n#+multi_export: t\n\n* Heading\n")
    (org-mode)
    (should (a3madkour-pub-multi-filter--doc-p))))

(ert-deftest a3madkour-pub-multi-filter/rejects-missing-keyword ()
  "Buffer without `#+multi_export:` is not multi-export."
  (with-temp-buffer
    (insert "#+title: Demo\n\n* Heading\n")
    (org-mode)
    (should-not (a3madkour-pub-multi-filter--doc-p))))

(ert-deftest a3madkour-pub-multi-filter/rejects-falsy-value ()
  "Buffer with `#+multi_export: nil` (or any non-t value) is not multi-export."
  (with-temp-buffer
    (insert "#+multi_export: nil\n")
    (org-mode)
    (should-not (a3madkour-pub-multi-filter--doc-p))))

(defun a3madkour-pub-multi-filter--test--collect-headings (backend buffer-text)
  "Apply filter for BACKEND on BUFFER-TEXT, return remaining top-level headings."
  (with-temp-buffer
    (insert buffer-text)
    (org-mode)
    (a3madkour-pub-multi-filter--apply-visibility backend)
    (let (headings)
      (org-map-entries (lambda () (push (org-get-heading t t t t) headings)) "LEVEL=1")
      (nreverse headings))))

(defconst a3madkour-pub-multi-filter--test--tagged-doc
  "#+multi_export: t

* Universal
* Web only                                          :WEB_ONLY:
* Paper only                                        :PAPER_ONLY:
* PDF skipped                                       :NOEXPORT_PDF:
* Web skipped                                       :NOEXPORT_WEB:
* Word skipped                                      :NOEXPORT_WORD:
")

(ert-deftest a3madkour-pub-multi-filter/visibility-hugo ()
  "Hugo/md backend drops NOEXPORT_WEB and PAPER_ONLY."
  (let ((kept (a3madkour-pub-multi-filter--test--collect-headings
               'hugo a3madkour-pub-multi-filter--test--tagged-doc)))
    (should (member "Universal" kept))
    (should (member "Web only" kept))
    (should (member "PDF skipped" kept))
    (should (member "Word skipped" kept))
    (should-not (member "Paper only" kept))
    (should-not (member "Web skipped" kept))))

(ert-deftest a3madkour-pub-multi-filter/visibility-latex ()
  "LaTeX backend drops NOEXPORT_PDF and WEB_ONLY."
  (let ((kept (a3madkour-pub-multi-filter--test--collect-headings
               'latex a3madkour-pub-multi-filter--test--tagged-doc)))
    (should (member "Universal" kept))
    (should (member "Paper only" kept))
    (should (member "Web skipped" kept))
    (should (member "Word skipped" kept))
    (should-not (member "Web only" kept))
    (should-not (member "PDF skipped" kept))))

(ert-deftest a3madkour-pub-multi-filter/visibility-pandoc ()
  "Pandoc (word) backend drops NOEXPORT_WORD, WEB_ONLY, and PAPER_ONLY."
  (let ((kept (a3madkour-pub-multi-filter--test--collect-headings
               'pandoc a3madkour-pub-multi-filter--test--tagged-doc)))
    (should (member "Universal" kept))
    (should (member "PDF skipped" kept))
    (should (member "Web skipped" kept))
    (should-not (member "Web only" kept))
    (should-not (member "Paper only" kept))
    (should-not (member "Word skipped" kept))))

(defconst a3madkour-pub-multi-filter--test--nested-doc
  "#+multi_export: t

* Section :PAPER_ONLY:
** Child (no local tag)
** Another child :WEB_ONLY:
* After
"
  "Doc with a `:PAPER_ONLY:' parent that has un-tagged + WEB_ONLY-tagged children.
The hugo backend drops PAPER_ONLY; LOCAL=t means only the parent is a direct
tag-bearer so `org-cut-subtree' removes the whole subtree in one cut.")

(ert-deftest a3madkour-pub-multi-filter/visibility-nested-parent-cut ()
  "Cutting a :PAPER_ONLY: parent for hugo backend removes the whole subtree
in one cut (LOCAL=t semantics); only `Section' and `After' are evaluated as
direct tag-bearers."
  (let ((kept (a3madkour-pub-multi-filter--test--collect-headings
               'hugo a3madkour-pub-multi-filter--test--nested-doc)))
    ;; Section and its descendants gone; After remains.
    (should (member "After" kept))
    (should-not (member "Section" kept))
    (should-not (member "Child (no local tag)" kept))
    (should-not (member "Another child" kept))))

(ert-deftest a3madkour-pub-multi-filter/all-visibility-tags-covers-known ()
  "Union of skip-rule values includes every known visibility tag once."
  (let ((tags (a3madkour-pub-multi-filter--all-visibility-tags)))
    (dolist (expected '("WEB_ONLY" "PAPER_ONLY"
                        "NOEXPORT_WEB" "NOEXPORT_PDF" "NOEXPORT_WORD"))
      (should (member expected tags)))
    (should (= (length tags) (length (cl-remove-duplicates tags :test #'equal))))))

(ert-deftest a3madkour-pub-multi-filter/strip-visibility-tags-clears-vis ()
  "Strip removes our D.2 tags from kept headlines without touching unrelated tags."
  (with-temp-buffer
    (insert "* Universal\n"
            "* Kept :NOEXPORT_WORD:draft:\n"
            "* Plain\n")
    (org-mode)
    (a3madkour-pub-multi-filter--strip-visibility-tags)
    (goto-char (point-min))
    (re-search-forward "^\\* Kept")
    (should (equal (org-get-tags nil t) '("draft")))
    (goto-char (point-min))
    (re-search-forward "^\\* Universal")
    (should (equal (org-get-tags nil t) nil))))

(ert-deftest a3madkour-pub-multi-filter/strip-visibility-tags-noop-when-clean ()
  "Strip is a no-op when no headline carries a visibility tag."
  (with-temp-buffer
    (insert "* One\n* Two :keep:\n")
    (org-mode)
    (let ((before (buffer-string)))
      (a3madkour-pub-multi-filter--strip-visibility-tags)
      (should (string= before (buffer-string))))))

(ert-deftest a3madkour-pub-multi-filter/strip-visibility-tags-only-vis-drops-block ()
  "When the only tag is a visibility tag, the whole `:TAG:' block is removed
along with the leading whitespace separator."
  (with-temp-buffer
    (insert "* Plain :NOEXPORT_PDF:\n")
    (org-mode)
    (a3madkour-pub-multi-filter--strip-visibility-tags)
    (should (string= "* Plain\n" (buffer-string)))))

(ert-deftest a3madkour-pub-multi-filter/strip-visibility-tags-multiple-vis ()
  "Two adjacent visibility tags are both removed, leaving non-vis tags intact."
  (with-temp-buffer
    (insert "* H :WEB_ONLY:PAPER_ONLY:keep:\n")
    (org-mode)
    (a3madkour-pub-multi-filter--strip-visibility-tags)
    (goto-char (point-min))
    (re-search-forward "^\\* H")
    (should (equal (org-get-tags nil t) '("keep")))))

(ert-deftest a3madkour-pub-multi-filter/vocab-latex-injects-attrs ()
  "attr_shortcode on a D.1 block emits attr_latex + name for LaTeX backend."
  (with-temp-buffer
    (insert "#+multi_export: t\n\n"
            "#+attr_shortcode: :title \"Intermediate Value\" :id thm-ivt\n"
            "#+begin_theorem\nFoo.\n#+end_theorem\n")
    (org-mode)
    (a3madkour-pub-multi-filter--translate-vocab 'latex)
    (let ((text (buffer-string)))
      (should (string-match-p "#\\+attr_latex: :options \\[Intermediate Value\\]" text))
      (should (string-match-p "#\\+name: thm-ivt" text)))))

(ert-deftest a3madkour-pub-multi-filter/vocab-pandoc-injects-attrs ()
  "attr_shortcode on a D.1 block emits attr_html for pandoc backend."
  (with-temp-buffer
    (insert "#+attr_shortcode: :title \"Intermediate Value\" :id thm-ivt\n"
            "#+begin_theorem\nFoo.\n#+end_theorem\n")
    (org-mode)
    (a3madkour-pub-multi-filter--translate-vocab 'pandoc)
    (let ((text (buffer-string)))
      (should (string-match-p "#\\+attr_html: :class theorem :id thm-ivt :data-title \"Intermediate Value\"" text)))))

(ert-deftest a3madkour-pub-multi-filter/vocab-skips-unknown-kinds ()
  "Non-D.1 special blocks are untouched."
  (with-temp-buffer
    (insert "#+attr_shortcode: :title T :id x\n"
            "#+begin_quote\nq\n#+end_quote\n")
    (org-mode)
    (let ((before (buffer-string)))
      (a3madkour-pub-multi-filter--translate-vocab 'latex)
      (should (string= before (buffer-string))))))

(ert-deftest a3madkour-pub-multi-filter/crossref-latex ()
  "[[#thm-ivt][text]] org link rewrites to @@latex:\\hyperref export snippet."
  (with-temp-buffer
    (insert "See [[#thm-ivt][Theorem 1]] for details.\n")
    (org-mode)
    (a3madkour-pub-multi-filter--rewrite-crossrefs 'latex)
    (should (string-match-p "@@latex:\\\\hyperref\\[thm-ivt\\]{Theorem 1}@@"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-multi-filter/crossref-pandoc-untouched ()
  "Pandoc handles [[#id]] natively; rewrite is a no-op."
  (with-temp-buffer
    (insert "See [[#thm-ivt][Theorem 1]] for details.\n")
    (org-mode)
    (let ((before (buffer-string)))
      (a3madkour-pub-multi-filter--rewrite-crossrefs 'pandoc)
      (should (string= before (buffer-string))))))

(provide 'a3madkour-publish-multi-filter-test)
;;; a3madkour-publish-multi-filter-test.el ends here
