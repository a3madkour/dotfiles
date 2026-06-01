;;; a3madkour-publish-deliberate-test.el --- tests for -deliberate.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the publish-deliberate top-level command.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-deliberate)

(ert-deftest a3madkour-pub-delib-test/command-defined-and-interactive ()
  "B.0 — `a3-publish-deliberate' is defined and interactive."
  (should (fboundp 'a3-publish-deliberate))
  (should (commandp 'a3-publish-deliberate)))

(ert-deftest a3madkour-pub-delib-test/unknown-section-errors-clean ()
  "B.0 — given an org file with #+HUGO_SECTION: <known section>, but no
handler registered, signals `error' with a clear message identifying the
section.  This is B.0's expected behavior; B.1+ adds handlers.

Mirrors `a3madkour-pub-living-test/empty-handler-set-runs-lifecycle-clean'
in setting up `site-data-dir' + `org-notes-dir' + a seeded URL-history
manifest + an `org-roam-db-sync' stub so `begin-publish' succeeds and
control reaches the dispatch."
  (let* ((tmp-data (make-temp-file "b0-delib-" t))
         (tmp (expand-file-name "test.org" tmp-data)))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data)
              (a3madkour-pub/org-notes-dir tmp-data))
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes: []\n"))
          (with-temp-file tmp
            (insert "#+title: Test\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n:PROPERTIES:\n:ID: test-id-001\n:END:\n\nbody\n"))
          (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
            (let ((err-data (should-error (a3-publish-deliberate tmp))))
              (should (string-match-p "garden" (cadr err-data))))))
      (delete-directory tmp-data t))))

(ert-deftest a3madkour-pub-deliberate-test/essays-handler-registered ()
  "B.4 Task 9: 'essays is registered in the deliberate handler alist."
  (require 'a3madkour-publish-deliberate)
  (should (eq (cdr (assq 'essays a3madkour-pub-deliberate--handlers))
              'a3madkour-pub-essays/publish-essay-file)))

;; -- F Task 13: deliberate triggers cite emit-yaml --

(ert-deftest a3madkour-pub-deliberate-test/citations-emit-fires-after-finish ()
  "F Task 13: a3-publish-deliberate calls emit-yaml after finish-publish.
Stub begin-publish, finish-publish, resolve-file-or-id, note-section, and
emit-yaml; bind handlers to a no-op essays entry.  Assert call order:
finish-publish first, then emit-yaml."
  (let ((calls nil)
        (a3madkour-pub-deliberate--handlers
         (list (cons 'essays (lambda (_file) nil)))))
    (cl-letf (((symbol-function 'a3madkour-pub/begin-publish) (lambda () nil))
              ((symbol-function 'a3madkour-pub/finish-publish)
               (lambda (&rest _) (push 'finish calls)))
              ((symbol-function 'a3madkour-pub--resolve-file-or-id)
               (lambda (_) "/fake/file.org"))
              ((symbol-function 'a3madkour-pub/note-section)
               (lambda (_) "essays"))
              ((symbol-function 'a3madkour-pub-citations/emit-yaml)
               (lambda (&rest _) (push 'emit calls)))
              ((symbol-function 'require)
               (lambda (feat &rest _) (or (memq feat features) t))))
      (a3-publish-deliberate "/fake/file.org")
      (should (equal (reverse calls) '(finish emit))))))

(provide 'a3madkour-publish-deliberate-test)
;;; a3madkour-publish-deliberate-test.el ends here
