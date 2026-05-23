;;; a3madkour-publish-rewrite-test.el --- Tests for link rewriting -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-rewrite)

;;; Heading-anchor slugifier — Goldmark `github` algorithm.

(ert-deftest a3madkour-pub-rewrite-test/anchor-basic-ascii ()
  (should (equal (a3madkour-pub--heading-anchor "Hello World") "hello-world")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-lowercase ()
  (should (equal (a3madkour-pub--heading-anchor "FOO BAR") "foo-bar")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-preserves-accents ()
  "Goldmark preserves unicode letters; `café' must not fold to `cafe'."
  (should (equal (a3madkour-pub--heading-anchor "Café") "café")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-preserves-cjk ()
  "CJK characters classify as Lo (other letter) and are preserved verbatim."
  (should (equal (a3madkour-pub--heading-anchor "日本語タイトル") "日本語タイトル")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-strips-punctuation ()
  (should (equal (a3madkour-pub--heading-anchor "Hello, World!") "hello-world")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-strips-parens ()
  (should (equal (a3madkour-pub--heading-anchor "Foo (Bar)") "foo-bar")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-keeps-hyphen-and-underscore ()
  (should (equal (a3madkour-pub--heading-anchor "foo-bar_baz") "foo-bar_baz")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-keeps-digits ()
  (should (equal (a3madkour-pub--heading-anchor "Section 2.3") "section-23")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-contiguous-spaces ()
  "No hyphen-collapse: two spaces become two hyphens."
  (should (equal (a3madkour-pub--heading-anchor "a  b") "a--b")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-leading-trailing-spaces ()
  "Hugo's github-style trims leading/trailing whitespace BEFORE the per-rune loop."
  (should (equal (a3madkour-pub--heading-anchor " hi ") "hi")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-empty ()
  "Hugo's github-style returns 'heading' as fallback when the filtered result is empty."
  (should (equal (a3madkour-pub--heading-anchor "") "heading")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-punctuation-only-fallback ()
  "Heading with no alphanumeric/space/hyphen/underscore chars falls back to 'heading'."
  (should (equal (a3madkour-pub--heading-anchor "!!!") "heading")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-hyphens-preserved ()
  "An all-hyphens heading stays all hyphens (buffer non-empty, no fallback)."
  (should (equal (a3madkour-pub--heading-anchor "---") "---")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-drops-letter-numbers ()
  "Hugo's unicode.IsDigit is strictly Nd (decimal) — Nl (Roman numerals) and No (½, ²) dropped."
  (should (equal (a3madkour-pub--heading-anchor "Chapter Ⅳ") "chapter-"))
  (should (equal (a3madkour-pub--heading-anchor "½ off") "-off")))

(ert-deftest a3madkour-pub-rewrite-test/anchor-uppercase-underscore ()
  "Underscores survive lowercasing (ASCII _ is unchanged by ToLower, but the path runs through it)."
  (should (equal (a3madkour-pub--heading-anchor "FOO_BAR") "foo_bar")))

;; -- rewrite-link: external URL pass-through --

(ert-deftest a3madkour-pub-rewrite-test/external-https ()
  (let ((result (a3madkour-pub/rewrite-link
                 "[[https://example.com][Example]]" "src-id")))
    (should (equal (plist-get result :html)
                   "<a href=\"https://example.com\">Example</a>"))
    (should-not (plist-get result :warnings))))

(ert-deftest a3madkour-pub-rewrite-test/external-http ()
  (let ((result (a3madkour-pub/rewrite-link
                 "[[http://example.com][text]]" "src-id")))
    (should (equal (plist-get result :html)
                   "<a href=\"http://example.com\">text</a>"))))

(ert-deftest a3madkour-pub-rewrite-test/external-mailto ()
  (let ((result (a3madkour-pub/rewrite-link
                 "[[mailto:foo@example.com][Email me]]" "src-id")))
    (should (equal (plist-get result :html)
                   "<a href=\"mailto:foo@example.com\">Email me</a>"))))

(ert-deftest a3madkour-pub-rewrite-test/external-tel ()
  (let ((result (a3madkour-pub/rewrite-link
                 "[[tel:+15551234567][Call]]" "src-id")))
    (should (equal (plist-get result :html)
                   "<a href=\"tel:+15551234567\">Call</a>"))))

(ert-deftest a3madkour-pub-rewrite-test/external-other-scheme ()
  "Unrecognized URL schemes pass through unchanged."
  (let ((result (a3madkour-pub/rewrite-link
                 "[[ftp://files.example.com][download]]" "src-id")))
    (should (equal (plist-get result :html)
                   "<a href=\"ftp://files.example.com\">download</a>"))))

;; -- rewrite-link: id-links --

(defmacro a3madkour-pub-rewrite-test--with-stubbed (state-alist &rest body)
  "Run BODY with `note-metadata` stubbed to return entries from STATE-ALIST.
STATE-ALIST maps file-or-id strings to plist values."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'a3madkour-pub/note-metadata)
              (lambda (file-or-id)
                (cdr (assoc file-or-id ',state-alist))))
             ((symbol-function 'a3madkour-pub--resolve-file-or-id)
              (lambda (foi) foi))  ; identity — let stub handle dispatch
             ((symbol-function 'a3madkour-pub/published-p)
              (lambda (foi)
                (plist-get (cdr (assoc foi ',state-alist)) :state)))
             ((symbol-function 'a3madkour-pub/note-url)
              (lambda (foi)
                (let ((md (cdr (assoc foi ',state-alist))))
                  (when md
                    (format "/%s/%s/"
                            (plist-get md :section)
                            (plist-get md :slug)))))))
     ,@body))

(ert-deftest a3madkour-pub-rewrite-test/id-link-live ()
  "Live target → <a href> with section/slug; no warnings."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("target-id" :state live :section "garden" :slug "foo")
    ("source-id" :state live :section "garden" :slug "bar"))
   (let ((result (a3madkour-pub/rewrite-link
                  "[[id:target-id][Hello]]" "source-id")))
     (should (equal (plist-get result :html)
                    "<a href=\"/garden/foo/\">Hello</a>"))
     (should-not (plist-get result :warnings)))))

(ert-deftest a3madkour-pub-rewrite-test/id-link-draft-from-live ()
  "Draft target, source is live → :html with WARN."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("target-id" :state draft :section "essays" :slug "draftpost")
    ("source-id" :state live  :section "garden" :slug "live"))
   (let ((result (a3madkour-pub/rewrite-link
                  "[[id:target-id][text]]" "source-id")))
     (should (equal (plist-get result :html)
                    "<a href=\"/essays/draftpost/\">text</a>"))
     (should (= 1 (length (plist-get result :warnings))))
     (should (string-match-p "draft" (car (plist-get result :warnings)))))))

(ert-deftest a3madkour-pub-rewrite-test/id-link-draft-from-draft ()
  "Draft target, source is also draft → :html, NO warning (both unship together)."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("target-id" :state draft :section "essays" :slug "tgt")
    ("source-id" :state draft :section "garden" :slug "src"))
   (let ((result (a3madkour-pub/rewrite-link
                  "[[id:target-id][text]]" "source-id")))
     (should (equal (plist-get result :html)
                    "<a href=\"/essays/tgt/\">text</a>"))
     (should-not (plist-get result :warnings)))))

(ert-deftest a3madkour-pub-rewrite-test/id-link-private ()
  "Target unpublished (private) → :inert with WARN."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("source-id" :state live :section "garden" :slug "src"))
   ;; No entry for "target-id" → published-p returns nil → private
   (let ((result (a3madkour-pub/rewrite-link
                  "[[id:target-id][Some text]]" "source-id")))
     (should (equal (plist-get result :inert) "Some text"))
     (should (= 1 (length (plist-get result :warnings))))
     (should (string-match-p "private\\|unpublished\\|unknown"
                             (car (plist-get result :warnings)))))))

(ert-deftest a3madkour-pub-rewrite-test/id-link-without-display-text ()
  "Link [[id:UUID]] (no text) uses the resolved URL as text (org's default behavior)."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("target-id" :state live :section "garden" :slug "foo")
    ("source-id" :state live :section "garden" :slug "src"))
   ;; When the parsed link has no [text], path doubles as text — but here
   ;; the path is `id:target-id`, which is meaningless to display. Pick a
   ;; sensible default: use the resolved URL as text.
   (let ((result (a3madkour-pub/rewrite-link "[[id:target-id]]" "source-id")))
     (should (equal (plist-get result :html)
                    "<a href=\"/garden/foo/\">/garden/foo/</a>")))))

(ert-deftest a3madkour-pub-rewrite-test/id-link-with-heading-suffix ()
  "[[id:UUID::*Heading]] resolves to /section/slug/#goldmark-slug."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("target-id" :state live :section "garden" :slug "foo")
    ("source-id" :state live :section "garden" :slug "src"))
   (let ((result (a3madkour-pub/rewrite-link
                  "[[id:target-id::*Hello World][Section link]]" "source-id")))
     (should (equal (plist-get result :html)
                    "<a href=\"/garden/foo/#hello-world\">Section link</a>"))
     (should-not (plist-get result :warnings)))))

;; -- rewrite-link: heading anchors --

(ert-deftest a3madkour-pub-rewrite-test/anchor-link-live-heading-exists ()
  "Live target + heading exists in target file → :html with anchor; no WARN."
  (let ((tgt-file (make-temp-file "a3pub-tgt-" nil ".org"
                                  "#+title: Target
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
* Introduction
* Section Two
")))
    (unwind-protect
        (a3madkour-pub-rewrite-test--with-stubbed
         (("target-id" :state live :section "garden" :slug "target")
          ("source-id" :state live :section "garden" :slug "src"))
         (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                    (lambda (id) (and (equal id "target-id") tgt-file))))
           (let ((result (a3madkour-pub/rewrite-link
                          "[[id:target-id::*Section Two][Read more]]" "source-id")))
             (should (equal (plist-get result :html)
                            "<a href=\"/garden/target/#section-two\">Read more</a>"))
             (should-not (plist-get result :warnings)))))
      (delete-file tgt-file))))

(ert-deftest a3madkour-pub-rewrite-test/anchor-link-heading-missing ()
  "Live target + heading missing → :html with anchor + WARN."
  (let ((tgt-file (make-temp-file "a3pub-tgt-" nil ".org"
                                  "#+title: Target
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
* Only Section
")))
    (unwind-protect
        (a3madkour-pub-rewrite-test--with-stubbed
         (("target-id" :state live :section "garden" :slug "target")
          ("source-id" :state live :section "garden" :slug "src"))
         (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                    (lambda (id) (and (equal id "target-id") tgt-file))))
           (let ((result (a3madkour-pub/rewrite-link
                          "[[id:target-id::*Missing Heading][text]]" "source-id")))
             (should (equal (plist-get result :html)
                            "<a href=\"/garden/target/#missing-heading\">text</a>"))
             (should (= 1 (length (plist-get result :warnings))))
             (should (string-match-p "heading.*not found"
                                     (car (plist-get result :warnings)))))))
      (delete-file tgt-file))))

(ert-deftest a3madkour-pub-rewrite-test/anchor-link-private-target ()
  "Private target with heading suffix → :inert + WARN (anchor lost)."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("source-id" :state live :section "garden" :slug "src"))
   (let ((result (a3madkour-pub/rewrite-link
                  "[[id:no-such-target::*Section][text]]" "source-id")))
     (should (equal (plist-get result :inert) "text"))
     (should (= 1 (length (plist-get result :warnings)))))))

(ert-deftest a3madkour-pub-rewrite-test/anchor-link-heading-with-decorations ()
  "Heading existence check tolerates TODO/priority/tags decorations."
  (let ((tgt-file (make-temp-file "a3pub-tgt-" nil ".org"
                                  "#+title: Decorated
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
* TODO [#A] Tagged Heading :research:org:
")))
    (unwind-protect
        (a3madkour-pub-rewrite-test--with-stubbed
         (("target-id" :state live :section "garden" :slug "decorated")
          ("source-id" :state live :section "garden" :slug "src"))
         (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                    (lambda (id) (and (equal id "target-id") tgt-file))))
           (let ((result (a3madkour-pub/rewrite-link
                          "[[id:target-id::*Tagged Heading][text]]" "source-id")))
             (should (equal (plist-get result :html)
                            "<a href=\"/garden/decorated/#tagged-heading\">text</a>"))
             (should-not (plist-get result :warnings)))))
      (delete-file tgt-file))))

(ert-deftest a3madkour-pub-rewrite-test/anchor-link-heading-case-sensitive ()
  "Heading existence check is case-sensitive: 'Foo' must not match '* foo'."
  (let ((tgt-file (make-temp-file "a3pub-tgt-" nil ".org"
                                  "#+title: Mixed Case
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
* lowercase heading
")))
    (unwind-protect
        (a3madkour-pub-rewrite-test--with-stubbed
         (("target-id" :state live :section "garden" :slug "mixed")
          ("source-id" :state live :section "garden" :slug "src"))
         (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                    (lambda (id) (and (equal id "target-id") tgt-file))))
           (let ((result (a3madkour-pub/rewrite-link
                          "[[id:target-id::*Lowercase Heading][text]]" "source-id")))
             ;; Querying 'Lowercase Heading' (Title Case) should NOT match
             ;; the actual '* lowercase heading' — WARN expected.
             (should (= 1 (length (plist-get result :warnings))))
             (should (string-match-p "heading.*not found"
                                     (car (plist-get result :warnings)))))))
      (delete-file tgt-file))))

;; -- rewrite-link: file-link auto-convert --

(ert-deftest a3madkour-pub-rewrite-test/file-link-with-id ()
  "file-link to a target with :ID: → resolves to id-link semantics."
  (let ((tgt (make-temp-file "a3pub-file-tgt-" nil ".org"
                             "#+title: Target
#+HUGO_PUBLISH: t
#+HUGO_SECTION: garden
:PROPERTIES:
:ID: deadbeef-dead-beef-dead-beefdeadbeef
:END:
")))
    (unwind-protect
        (a3madkour-pub-rewrite-test--with-stubbed
         (("deadbeef-dead-beef-dead-beefdeadbeef"
           :state live :section "garden" :slug "target")
          ("source-id" :state live :section "garden" :slug "src"))
         (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                    (lambda (id)
                      (and (equal id "deadbeef-dead-beef-dead-beefdeadbeef") tgt)))
                   ((symbol-function 'a3madkour-pub--file-top-level-id)
                    (lambda (f)
                      (and (equal f tgt) "deadbeef-dead-beef-dead-beefdeadbeef"))))
           (let ((result (a3madkour-pub/rewrite-link
                          (format "[[file:%s][text]]" tgt) "source-id")))
             (should (equal (plist-get result :html)
                            "<a href=\"/garden/target/\">text</a>")))))
      (delete-file tgt))))

(ert-deftest a3madkour-pub-rewrite-test/file-link-without-id ()
  "file-link to target lacking :ID: → :inert + WARN."
  (let ((tgt (make-temp-file "a3pub-file-tgt-noid-" nil ".org"
                             "#+title: Plain target\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub--file-top-level-id)
                   (lambda (f) (and (equal f tgt) nil))))
          (let ((result (a3madkour-pub/rewrite-link
                         (format "[[file:%s][text]]" tgt) "source-id")))
            (should (equal (plist-get result :inert) "text"))
            (should (string-match-p ":ID:" (car (plist-get result :warnings))))))
      (delete-file tgt))))

(ert-deftest a3madkour-pub-rewrite-test/file-link-subtree-id-not-returned ()
  "`--file-top-level-id' must NOT return subtree-level IDs.
File-link to a file lacking a file-level :ID: drawer (but containing
a subtree :ID:) must return nil from `--file-top-level-id', causing
the file-link rewrite to emit :inert + WARN."
  (let ((tgt (make-temp-file "a3pub-file-subtree-" nil ".org"
                             "#+title: Headless target
* Section
:PROPERTIES:
:ID: subtree-uuid-here-not-file-level
:END:
")))
    (unwind-protect
        (let ((result (a3madkour-pub/rewrite-link
                       (format "[[file:%s][text]]" tgt) "source-id")))
          (should (equal (plist-get result :inert) "text"))
          (should (string-match-p ":ID:" (car (plist-get result :warnings)))))
      (delete-file tgt))))

(ert-deftest a3madkour-pub-rewrite-test/file-link-relative-path-uses-source-dir ()
  "Relative paths in [[file:foo.org]] resolve against the source note's directory.
Stubs --id-to-file to map source-id to a temp file in a known directory,
then asserts that a relative target path resolves via that directory."
  (let* ((tmp-dir (make-temp-file "a3pub-reldir-" t))
         (source-file (expand-file-name "src.org" tmp-dir))
         (target-file (expand-file-name "tgt.org" tmp-dir)))
    (unwind-protect
        (progn
          ;; Write the target file with a file-level :ID:.
          (with-temp-file target-file
            (insert "#+title: Target\n#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n"
                    ":PROPERTIES:\n:ID: deadbeef-dead-beef-dead-beefdeadbeef\n:END:\n"))
          ;; Source file just needs to exist (its content doesn't matter — we stub --id-to-file).
          (with-temp-file source-file (insert ""))
          (a3madkour-pub-rewrite-test--with-stubbed
           (("deadbeef-dead-beef-dead-beefdeadbeef"
             :state live :section "garden" :slug "target")
            ("source-id" :state live :section "garden" :slug "src"))
           (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                      (lambda (id)
                        (cond
                         ((equal id "source-id") source-file)
                         ((equal id "deadbeef-dead-beef-dead-beefdeadbeef") target-file)
                         (t nil)))))
             (let ((result (a3madkour-pub/rewrite-link
                            "[[file:tgt.org][text]]" "source-id")))
               (should (equal (plist-get result :html)
                              "<a href=\"/garden/target/\">text</a>"))))))
      (delete-directory tmp-dir t))))

;; -- rewrite-link: custom typed links --

(ert-deftest a3madkour-pub-rewrite-test/typed-link-supports-live-target ()
  "[[supports:UUID][text]] → <a class=\"link-supports\" href=\"...\">text</a>"
  (a3madkour-pub-rewrite-test--with-stubbed
   (("tgt" :state live :section "garden" :slug "ev")
    ("source-id" :state live :section "garden" :slug "src"))
   (let ((result (a3madkour-pub/rewrite-link
                  "[[supports:tgt][evidence]]" "source-id")))
     (should (equal (plist-get result :html)
                    "<a class=\"link-supports\" href=\"/garden/ev/\">evidence</a>")))))

(ert-deftest a3madkour-pub-rewrite-test/typed-link-contradicts ()
  (a3madkour-pub-rewrite-test--with-stubbed
   (("tgt" :state live :section "garden" :slug "x")
    ("source-id" :state live :section "garden" :slug "src"))
   (let ((result (a3madkour-pub/rewrite-link
                  "[[contradicts:tgt][counterexample]]" "source-id")))
     (should (equal (plist-get result :html)
                    "<a class=\"link-contradicts\" href=\"/garden/x/\">counterexample</a>")))))

(ert-deftest a3madkour-pub-rewrite-test/typed-link-class-on-inert ()
  "Plan narrowing: class is emitted ONLY on rendered anchors; inert variants
have no anchor, hence no class.  Spec sentence \"Class always emitted regardless
of target state\" refers to the anchor's class — and inert variants don't have
one.  Spec wording amendment is deferred to Task 19."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("source-id" :state live :section "garden" :slug "src"))
   (let ((result (a3madkour-pub/rewrite-link
                  "[[supports:no-such-target][text]]" "source-id")))
     (should (equal (plist-get result :inert) "text")))))

(ert-deftest a3madkour-pub-rewrite-test/typed-link-respects-defcustom ()
  "Adding a new type to the defcustom makes it recognized; otherwise pass-through."
  (let ((a3madkour-pub-typed-link-types
         '("supports" "contradicts" "extends" "example-of" "causes" "cites")))
    (a3madkour-pub-rewrite-test--with-stubbed
     (("tgt" :state live :section "garden" :slug "y")
      ("source-id" :state live :section "garden" :slug "src"))
     (let ((result (a3madkour-pub/rewrite-link
                    "[[cites:tgt][reference]]" "source-id")))
       (should (equal (plist-get result :html)
                      "<a class=\"link-cites\" href=\"/garden/y/\">reference</a>"))))))

;; -- rewrite-link: asset-shaped link stubs --

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-relative ()
  "[[./assets/page/foo/x.png]] → :pending-asset + WARN."
  (let ((result (a3madkour-pub/rewrite-link
                 "[[./assets/page/foo/diagram.png]]" "source-id")))
    (should (equal (plist-get result :pending-asset)
                   "[[./assets/page/foo/diagram.png]]"))
    (should (= 1 (length (plist-get result :warnings))))
    (should (string-match-p "asset" (car (plist-get result :warnings))))
    (should (string-match-p "A.1.c" (car (plist-get result :warnings))))))

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-relative-shared ()
  (let ((result (a3madkour-pub/rewrite-link
                 "[[./assets/shared/common.svg]]" "source-id")))
    (should (plist-get result :pending-asset))))

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-absolute ()
  "Absolute path outside canonical root also returns :pending-asset."
  (let ((result (a3madkour-pub/rewrite-link
                 "[[/home/user/some/path/screenshot.jpg]]" "source-id")))
    (should (plist-get result :pending-asset))))

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-tilde ()
  "Tilde-paths to canonical root also detected."
  (let ((result (a3madkour-pub/rewrite-link
                 "[[~/org/notes/assets/page/foo/x.png]]" "source-id")))
    (should (plist-get result :pending-asset))))

(provide 'a3madkour-publish-rewrite-test)

;;; a3madkour-publish-rewrite-test.el ends here
