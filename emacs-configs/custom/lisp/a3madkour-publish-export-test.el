;;; a3madkour-publish-export-test.el --- tests for -export.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the ox-hugo export wrapper.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-export)

(ert-deftest a3madkour-pub-export-test/export-file-returns-plist-shape ()
  "B.1 — `export-file' returns a plist with :body, :frontmatter, :warnings keys.
Verifies the spec-shaped return value contract only (not content correctness —
see `a3madkour-pub-export--real-export-roundtrip' for that)."
  (let* ((tmpdir (make-temp-file "b0-export-" t))
         (tmp (expand-file-name "shape-test.org" tmpdir)))
    (unwind-protect
        (progn
          ;; Minimal valid org file so ox-hugo doesn't error.
          (with-temp-file tmp
            (insert "#+title: Shape Test\n"
                    "#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " tmpdir "/site/\n"
                    "\nBody.\n"))
          (let ((result (a3madkour-pub-export/export-file tmp)))
            (should (plistp result))
            (should (memq :body result))
            (should (memq :frontmatter result))
            (should (memq :warnings result))
            ;; :body is always a string.
            (should (stringp (plist-get result :body)))
            ;; :frontmatter is nil or a proper alist (list of conses).
            (let ((fm (plist-get result :frontmatter)))
              (should (or (null fm) (and (listp fm) (consp (car fm))))))
            ;; :warnings is nil or a list of strings.
            (let ((warns (plist-get result :warnings)))
              (should (listp warns)))))
      (delete-directory tmpdir t))))

(ert-deftest a3madkour-pub-export--real-export-roundtrip ()
  "export-file invokes ox-hugo and returns non-empty :body + parsed :frontmatter."
  (let* ((tmpdir (make-temp-file "a3-pub-export-" t))
         (src (expand-file-name "example.org" tmpdir)))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert ":PROPERTIES:\n"
                    ":ID: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n"
                    ":END:\n"
                    "#+title: Example Note\n"
                    "#+filetags: :alpha:beta:\n"
                    "#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " tmpdir "/site/\n"
                    "\n"
                    "* The Heading\n"
                    "Body text with a [[https://example.com][link]].\n"))
          (let* ((result (a3madkour-pub-export/export-file src))
                 (body (plist-get result :body))
                 (fm (plist-get result :frontmatter)))
            (should (stringp body))
            (should (string-match-p "Body text with" body))
            ;; Frontmatter must NOT appear in body — :body is body only.
            (should-not (string-match-p "^---" body))
            (should-not (string-match-p "^\\+\\+\\+" body))
            (should (equal (alist-get 'title fm) "Example Note"))
            ;; tags may come through as a list of strings.
            (should (member "alpha" (alist-get 'tags fm)))
            (should (member "beta" (alist-get 'tags fm)))))
      (delete-directory tmpdir t))))

(ert-deftest a3madkour-pub-export--no-buffer-leak ()
  "export-file does not leak the source buffer or the *Org Hugo Export* buffer.
Note: buffer-only export does not validate HUGO_BASE_DIR — directory is a placeholder.

Uses a warm-up call on a first file before measuring, because org-mode lazily
creates its internal \" *Org parse*\" buffer on the very first export in a session.
That one-time allocation is org-mode's budget, not ours.  The assertion verifies
that a SECOND call on a NEW source file does not add any buffers."
  (let* ((tmpdir (make-temp-file "a3-pub-export-leak-" t))
         (src-warmup (expand-file-name "warmup.org" tmpdir))
         (src (expand-file-name "leak-test.org" tmpdir)))
    (unwind-protect
        (progn
          ;; Write both org files.
          (dolist (pair (list (cons src-warmup "aaaaaaaa-bbbb-cccc-dddd-000000000000")
                              (cons src "11111111-2222-3333-4444-555555555555")))
            (with-temp-file (car pair)
              (insert ":PROPERTIES:\n"
                      ":ID: " (cdr pair) "\n"
                      ":END:\n"
                      "#+title: Leak Test\n"
                      "#+HUGO_SECTION: garden\n"
                      "#+HUGO_BASE_DIR: " tmpdir "/site/\n"
                      "\n* Heading\nbody.\n")))
          ;; Warm-up: let org-mode allocate its one-time internal buffers.
          (a3madkour-pub-export/export-file src-warmup)
          ;; Now measure: a second call on a new source file must not grow the buffer list.
          (let ((before (length (buffer-list))))
            (a3madkour-pub-export/export-file src)
            (let ((after (length (buffer-list))))
              (should (= before after)))))
      (delete-directory tmpdir t))))

(provide 'a3madkour-publish-export-test)
;;; a3madkour-publish-export-test.el ends here
