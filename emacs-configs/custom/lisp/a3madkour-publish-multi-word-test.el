;;; a3madkour-publish-multi-word-test.el --- Tests for Word backend -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-publish-multi-word)

(ert-deftest a3madkour-pub-multi-word/defcustoms-defined ()
  (should (boundp 'a3madkour-pub-multi-pandoc-command)))

(ert-deftest a3madkour-pub-multi-word/probe-tools-pandoc ()
  (cl-letf (((symbol-function 'executable-find)
             (lambda (cmd) (unless (string= cmd "pandoc") "/usr/bin/x"))))
    (should (member "pandoc" (a3madkour-pub-multi-word--probe-tools)))))

(ert-deftest a3madkour-pub-multi-word/svg-to-png-builds-command ()
  (let (captured)
    (cl-letf (((symbol-function 'make-directory) (lambda (&rest _) nil))
              ((symbol-function 'call-process)
               (lambda (cmd _ _ _ &rest args) (push (cons cmd args) captured) 0)))
      (a3madkour-pub-multi-word--convert-svg "/src/a.svg" "/dst/a.png")
      (let ((args (cdr (car captured))))
        (should (member "-f" args))
        (should (member "png" args))
        (should (member "-d" args))
        (should (member "192" args))))))

(ert-deftest a3madkour-pub-multi-word/pandoc-command-assembled ()
  "Pandoc command includes reference-doc, lua-filter, citeproc, bibliography."
  (let (captured)
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd _ _ _ &rest args) (push (cons cmd args) captured) 0)))
      (a3madkour-pub-multi-word--invoke-pandoc
       "/tmp/x/in.org" "/out/x.docx"
       "/site/tools/templates/reference.docx"
       "/site/tools/templates/d2-blocks.lua"
       "/bib/library.bib")
      (let ((args (cdr (car captured))))
        (should (member "--reference-doc=/site/tools/templates/reference.docx" args))
        (should (member "--lua-filter=/site/tools/templates/d2-blocks.lua" args))
        (should (member "--citeproc" args))
        (should (member "--bibliography=/bib/library.bib" args))))))

(provide 'a3madkour-publish-multi-word-test)
;;; a3madkour-publish-multi-word-test.el ends here
