;;; a3madkour-publish-author-test.el --- tests for -author.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the publish-author interactive helpers (Tier 5.2).
;;; Code:

(require 'ert)
(require 'a3madkour-publish-author)

(ert-deftest a3madkour-pub-author-test/skeleton-loaded ()
  "The author module loads and its provide marker is registered."
  (should (featurep 'a3madkour-publish-author)))

;; -- a3-publish-status --

(ert-deftest a3madkour-pub-author-test/status-no-header ()
  "status: HUGO_PUBLISH absent → \"no HUGO_PUBLISH header\"."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n\n* Heading\n")
    (should (string= (a3-publish-status) "no HUGO_PUBLISH header"))))

(ert-deftest a3madkour-pub-author-test/status-nil ()
  "status: HUGO_PUBLISH: nil → private."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: nil\n#+title: Test\n")
    (should (string= (a3-publish-status) "private (HUGO_PUBLISH: nil)"))))

(ert-deftest a3madkour-pub-author-test/status-marked-valid-section ()
  "status: HUGO_PUBLISH: t + valid HUGO_SECTION → marked."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+title: Test\n")
    (should (string= (a3-publish-status) "marked for publish (garden)"))))

(ert-deftest a3madkour-pub-author-test/status-marked-invalid-section ()
  "status: HUGO_PUBLISH: t + invalid HUGO_SECTION → flagged."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: bogus-section\n#+title: Test\n")
    (should (string-match-p "invalid" (a3-publish-status)))
    (should (string-match-p "bogus-section" (a3-publish-status)))))

(ert-deftest a3madkour-pub-author-test/status-refuses-non-org-mode ()
  "status: non-org-mode buffer → user-error."
  (with-temp-buffer
    (text-mode)
    (insert "plain text")
    (should-error (a3-publish-status) :type 'user-error)))

;; -- a3-publish-mark --

(ert-deftest a3madkour-pub-author-test/mark-inserts-both-keywords-when-absent ()
  "mark: empty preamble → inserts #+HUGO_PUBLISH: t + #+HUGO_SECTION: <pick>."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n\n* Heading\n")
    (a3-publish-mark "essays")
    (should (string-match-p "^#\\+HUGO_PUBLISH:[[:space:]]+t$"
                            (buffer-string)))
    (should (string-match-p "^#\\+HUGO_SECTION:[[:space:]]+essays$"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/mark-updates-section-in-place-when-present ()
  "mark: existing HUGO_SECTION → updated in place (cross-section guard skipped
when caller passes the same answer to y-or-n-p)."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+title: Test\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) t)))
      (a3-publish-mark "essays"))
    (should (string-match-p "^#\\+HUGO_SECTION:[[:space:]]+essays$"
                            (buffer-string)))
    (should-not (string-match-p "^#\\+HUGO_SECTION:[[:space:]]+garden$"
                                (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/mark-cross-section-confirm-accepted ()
  "mark: cross-section y-or-n-p → t edits proceed, returns picked section."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) t)))
      (should (equal (a3-publish-mark "essays") "essays")))))

(ert-deftest a3madkour-pub-author-test/mark-cross-section-confirm-declined-aborts ()
  "mark: cross-section y-or-n-p → nil aborts; neither keyword is changed."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n")
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) nil)))
        (should (null (a3-publish-mark "essays"))))
      (should (string= (buffer-string) before)))))

(ert-deftest a3madkour-pub-author-test/mark-refuses-non-org-mode ()
  "mark: non-org-mode buffer → user-error."
  (with-temp-buffer
    (text-mode)
    (should-error (a3-publish-mark "essays") :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/mark-refuses-read-only ()
  "mark: read-only buffer → user-error."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n")
    (read-only-mode 1)
    (should-error (a3-publish-mark "essays") :type 'user-error)))

;; -- a3-publish-unmark --

(ert-deftest a3madkour-pub-author-test/unmark-flips-t-to-nil ()
  "unmark: HUGO_PUBLISH: t → nil; returns t."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n")
    (should (eq (a3-publish-unmark) t))
    (should (string-match-p "^#\\+HUGO_PUBLISH:[[:space:]]+nil$"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/unmark-inserts-nil-when-absent ()
  "unmark: HUGO_PUBLISH missing → inserts `#+HUGO_PUBLISH: nil`; returns t."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n")
    (should (eq (a3-publish-unmark) t))
    (should (string-match-p "^#\\+HUGO_PUBLISH:[[:space:]]+nil$"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/unmark-already-nil-no-op ()
  "unmark: HUGO_PUBLISH already nil → returns nil, buffer unchanged."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: nil\n#+title: Test\n")
    (let ((before (buffer-string)))
      (should (null (a3-publish-unmark)))
      (should (string= (buffer-string) before)))))

(ert-deftest a3madkour-pub-author-test/unmark-refuses-non-org-mode ()
  "unmark: non-org-mode buffer → user-error."
  (with-temp-buffer
    (text-mode)
    (should-error (a3-publish-unmark) :type 'user-error)))

;; -- a3-library-insert-extras --

(defmacro a3-pub-author-test--with-library-buffer (section &rest body)
  "Run BODY in a temp org buffer set up as a library file for SECTION."
  (declare (indent 1))
  `(with-temp-buffer
     (org-mode)
     (insert (format "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: %s\n#+title: Test\n\n"
                     ,section))
     ,@body))

(ert-deftest a3madkour-pub-author-test/insert-extras-bare-heading-inserts-all ()
  "insert-extras: bare heading (no drawer) → full extras for the section's medium."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (insert "* Pride and Prejudice\n")
    (goto-char (point-max))
    (search-backward "Pride")
    (a3-library-insert-extras)
    (let ((buf (buffer-string)))
      ;; Book extras include ISBN, PROGRESS_PCT, PROGRESS_LABEL, COVER_FILE, COVER_URL.
      (should (string-match-p ":ISBN:" buf))
      (should (string-match-p ":COVER_FILE:" buf)))))

(ert-deftest a3madkour-pub-author-test/insert-extras-partial-drawer-add-missing-only ()
  "insert-extras: drawer has some extras → y-or-n-p → t inserts only the missing keys."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (insert "* Pride and Prejudice\n:PROPERTIES:\n:ISBN: 1234567890\n:END:\n")
    (search-backward "Pride")
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) t)))
      (a3-library-insert-extras))
    (let ((buf (buffer-string)))
      ;; ISBN was already there; new keys appended.
      (should (string-match-p ":COVER_FILE:" buf))
      ;; ISBN appears exactly once (no duplicate).
      (should (= 1 (cl-count-if (lambda (l) (string-match-p ":ISBN:" l))
                                (split-string buf "\n")))))))

(ert-deftest a3madkour-pub-author-test/insert-extras-refuses-outside-heading ()
  "insert-extras: point not under any heading → user-error."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (goto-char (point-max))
    (should-error (a3-library-insert-extras) :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/insert-extras-refuses-non-library-section ()
  "insert-extras: section not in library config → user-error."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_SECTION: garden\n* Heading\n")
    (search-backward "Heading")
    (should-error (a3-library-insert-extras) :type 'user-error)))

;; -- a3-library-insert-item --

(ert-deftest a3madkour-pub-author-test/insert-item-happy-reading ()
  "insert-item: library/reading defaults to book; status prompt; full drawer inserted."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_p coll &rest _) (car coll))))
      (a3-library-insert-item))
    (let ((buf (buffer-string)))
      (should (string-match-p "^\\* TITLE" buf))
      (should (string-match-p ":CREATOR:" buf))
      (should (string-match-p ":STATUS: finished" buf))
      (should (string-match-p ":LAST_MODIFIED:" buf))
      ;; Book extras keys
      (should (string-match-p ":ISBN:" buf))
      (should (string-match-p ":COVER_FILE:" buf)))))

(ert-deftest a3madkour-pub-author-test/insert-item-listening-prompts-medium ()
  "insert-item: library/listening allows album+track → prompts for medium."
  (a3-pub-author-test--with-library-buffer "library/listening"
    (let ((calls nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt coll &rest _)
                   (push prompt calls)
                   (car coll))))
        (a3-library-insert-item))
      ;; Two completing-read calls: medium first, then status.
      (should (= (length calls) 2)))))

(ert-deftest a3madkour-pub-author-test/insert-item-playing-skips-medium-prompt ()
  "insert-item: library/playing has single medium (game) → only status prompt."
  (a3-pub-author-test--with-library-buffer "library/playing"
    (let ((calls nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt coll &rest _)
                   (push prompt calls)
                   (car coll))))
        (a3-library-insert-item))
      ;; One call (status); medium prompt skipped.
      (should (= (length calls) 1)))))

(ert-deftest a3madkour-pub-author-test/insert-item-refuses-non-library-section ()
  "insert-item: non-library section → user-error."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_SECTION: garden\n")
    (should-error (a3-library-insert-item) :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/insert-item-appends-after-existing ()
  "insert-item: existing heading is preserved; new heading appended."
  (a3-pub-author-test--with-library-buffer "library/reading"
    (insert "* Existing Book\n:PROPERTIES:\n:CREATOR: Old Author\n:END:\n")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_p coll &rest _) (car coll))))
      (a3-library-insert-item))
    (let ((buf (buffer-string)))
      (should (string-match-p "Existing Book" buf))
      (should (string-match-p "^\\* TITLE" buf))
      ;; Existing entry comes before the new one.
      (should (< (string-match "Existing Book" buf)
                 (string-match "^\\* TITLE" buf))))))

;; -- a3-publish-jump-to-source --

(defun a3-pub-author-test--stub-manifest (entries)
  "Build a manifest with ENTRIES (each (id url state))."
  `((notes . ,(vconcat
               (mapcar (lambda (e)
                         `((id . ,(nth 0 e))
                           (current_url . ,(nth 1 e))
                           (history . [])
                           (state . ,(nth 2 e))))
                       entries)))))

(ert-deftest a3madkour-pub-author-test/jump-auto-detect-happy ()
  "jump-to-source: buffer in content/<section>/<slug>/index.md → manifest hit → find-file."
  (let ((find-file-target nil))
    (cl-letf (((symbol-function 'buffer-file-name)
               (lambda (&optional _) "/site/content/essays/foo/index.md"))
              ((symbol-function 'a3madkour-pub-history/read-manifest)
               (lambda () (a3-pub-author-test--stub-manifest
                           '(("id-foo" "/essays/foo/" "live")))))
              ((symbol-function 'a3madkour-pub--id-to-file)
               (lambda (id) (when (equal id "id-foo") "/notes/foo.org")))
              ((symbol-function 'find-file)
               (lambda (path) (setq find-file-target path))))
      (a3-publish-jump-to-source))
    (should (equal find-file-target "/notes/foo.org"))))

(ert-deftest a3madkour-pub-author-test/jump-auto-detect-url-miss-user-errors ()
  "jump-to-source: URL not in manifest → user-error."
  (cl-letf (((symbol-function 'buffer-file-name)
             (lambda (&optional _) "/site/content/essays/missing/index.md"))
            ((symbol-function 'a3madkour-pub-history/read-manifest)
             (lambda () (a3-pub-author-test--stub-manifest
                         '(("id-foo" "/essays/foo/" "live"))))))
    (should-error (a3-publish-jump-to-source) :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/jump-fallback-completing-read ()
  "jump-to-source: buffer not in content/ → completing-read over manifest."
  (let ((find-file-target nil))
    (cl-letf (((symbol-function 'buffer-file-name)
               (lambda (&optional _) "/notes/scratch.org"))
              ((symbol-function 'a3madkour-pub-history/read-manifest)
               (lambda () (a3-pub-author-test--stub-manifest
                           '(("id-foo" "/essays/foo/" "live")))))
              ((symbol-function 'a3madkour-pub/note-metadata)
               (lambda (_f) '(:title "Foo")))
              ((symbol-function 'completing-read)
               (lambda (_p coll &rest _) (car coll)))
              ((symbol-function 'a3madkour-pub--id-to-file)
               (lambda (_id) "/notes/foo.org"))
              ((symbol-function 'find-file)
               (lambda (path) (setq find-file-target path))))
      (a3-publish-jump-to-source))
    (should (equal find-file-target "/notes/foo.org"))))

(ert-deftest a3madkour-pub-author-test/jump-empty-manifest-user-errors ()
  "jump-to-source: empty manifest → user-error."
  (cl-letf (((symbol-function 'buffer-file-name)
             (lambda (&optional _) "/notes/scratch.org"))
            ((symbol-function 'a3madkour-pub-history/read-manifest)
             (lambda () '((notes . [])))))
    (should-error (a3-publish-jump-to-source) :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/jump-id-to-file-nil-user-errors ()
  "jump-to-source: --id-to-file returns nil → user-error."
  (cl-letf (((symbol-function 'buffer-file-name)
             (lambda (&optional _) "/site/content/essays/foo/index.md"))
            ((symbol-function 'a3madkour-pub-history/read-manifest)
             (lambda () (a3-pub-author-test--stub-manifest
                         '(("id-foo" "/essays/foo/" "live")))))
            ((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil)))
    (should-error (a3-publish-jump-to-source) :type 'user-error)))

(provide 'a3madkour-publish-author-test)
;;; a3madkour-publish-author-test.el ends here
