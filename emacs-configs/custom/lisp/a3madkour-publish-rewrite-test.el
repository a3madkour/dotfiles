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

;; -- rewrite-link: asset-shaped link dispatch (A.1.c) --
;; These tests exercise that asset-shaped links route through rewrite-asset-link.
;; All fixtures use non-existent files → rewrite-asset-link's :missing → :inert.
;; note-slug + --id-to-file are stubbed (real impls require org-roam DB + readable files).

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-relative ()
  "[[./assets/page/foo/diagram.png]] → :inert (missing); no :pending-asset."
  (cl-letf (((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil))
            ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
    (let ((result (a3madkour-pub/rewrite-link
                   "[[./assets/page/foo/diagram.png]]" "source-id")))
      (should (plist-get result :inert))
      (should-not (plist-get result :pending-asset)))))

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-relative-shared ()
  "[[./assets/shared/common.svg]] → :inert (missing); no :pending-asset."
  (cl-letf (((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil))
            ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
    (let ((result (a3madkour-pub/rewrite-link
                   "[[./assets/shared/common.svg]]" "source-id")))
      (should (plist-get result :inert))
      (should-not (plist-get result :pending-asset)))))

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-absolute ()
  "Absolute path to non-existent file → :inert (missing); no :pending-asset."
  (cl-letf (((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil))
            ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
    (let ((result (a3madkour-pub/rewrite-link
                   "[[/home/user/some/path/screenshot.jpg]]" "source-id")))
      (should (plist-get result :inert))
      (should-not (plist-get result :pending-asset)))))

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-tilde ()
  "Tilde-path to non-existent file → :inert (missing); no :pending-asset."
  (cl-letf (((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil))
            ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
    (let ((result (a3madkour-pub/rewrite-link
                   "[[~/org/notes/assets/page/foo/x.png]]" "source-id")))
      (should (plist-get result :inert))
      (should-not (plist-get result :pending-asset)))))

;; -- --html-escape helper --

(ert-deftest a3madkour-pub-rewrite-test/html-escape-ampersand ()
  "& → &amp;."
  (should (equal (a3madkour-pub--html-escape "a & b") "a &amp; b")))

(ert-deftest a3madkour-pub-rewrite-test/html-escape-angle-brackets ()
  "< and > escape."
  (should (equal (a3madkour-pub--html-escape "<x>") "&lt;x&gt;")))

(ert-deftest a3madkour-pub-rewrite-test/html-escape-double-quote ()
  "\" → &quot;."
  (should (equal (a3madkour-pub--html-escape "say \"hi\"")
                 "say &quot;hi&quot;")))

(ert-deftest a3madkour-pub-rewrite-test/html-escape-apostrophe ()
  "' → &#39;."
  (should (equal (a3madkour-pub--html-escape "it's") "it&#39;s")))

(ert-deftest a3madkour-pub-rewrite-test/html-escape-all-five ()
  "All five characters in a combined input escape correctly — ampersand-first
order prevents the `&' inside emitted entities (e.g., `&lt;') from being
double-encoded to `&amp;lt;'."
  (should (equal (a3madkour-pub--html-escape "<a href=\"&\">'</a>")
                 "&lt;a href=&quot;&amp;&quot;&gt;&#39;&lt;/a&gt;")))

(ert-deftest a3madkour-pub-rewrite-test/html-escape-empty ()
  "Empty string passes through."
  (should (equal (a3madkour-pub--html-escape "") "")))

(ert-deftest a3madkour-pub-rewrite-test/html-escape-nil-coerces-to-empty ()
  "nil input → empty string (defensive; some callers pass nil through)."
  (should (equal (a3madkour-pub--html-escape nil) "")))

;; -- id-link emit escape retrofit --

(ert-deftest a3madkour-pub-rewrite-test/id-link-display-text-escaped ()
  "Display text containing < > & gets escaped in the rendered anchor."
  (cl-letf (((symbol-function 'a3madkour-pub/published-p)
             (lambda (_) 'live))
            ((symbol-function 'a3madkour-pub/note-url)
             (lambda (_) "/garden/x/")))
    (let* ((uuid "00000000-0000-0000-0000-000000000001")
           (link (format "[[id:%s][a < b & c > d]]" uuid))
           (result (a3madkour-pub/rewrite-link link "src")))
      (should (equal (plist-get result :html)
                     "<a href=\"/garden/x/\">a &lt; b &amp; c &gt; d</a>")))))

(ert-deftest a3madkour-pub-rewrite-test/id-link-href-with-quote-escaped ()
  "Resolved URL containing \" (pathological) gets &quot; in href context."
  (cl-letf (((symbol-function 'a3madkour-pub/published-p)
             (lambda (_) 'live))
            ((symbol-function 'a3madkour-pub/note-url)
             (lambda (_) "/garden/odd\"slug/")))
    (let* ((uuid "00000000-0000-0000-0000-000000000002")
           (link (format "[[id:%s][text]]" uuid))
           (result (a3madkour-pub/rewrite-link link "src")))
      (should (string-match-p "href=\"/garden/odd&quot;slug/\""
                              (plist-get result :html))))))

;; -- typed-link emit (class inheritance from id-link) --

(ert-deftest a3madkour-pub-rewrite-test/typed-link-display-text-escaped ()
  "Class injection MUST preserve the escape applied by id-link's emit."
  (cl-letf (((symbol-function 'a3madkour-pub/published-p)
             (lambda (_) 'live))
            ((symbol-function 'a3madkour-pub/note-url)
             (lambda (_) "/garden/y/")))
    (let* ((uuid "00000000-0000-0000-0000-000000000003")
           (link (format "[[supports:%s][a < b]]" uuid))
           (result (a3madkour-pub/rewrite-link link "src")))
      (should (equal (plist-get result :html)
                     "<a class=\"link-supports\" href=\"/garden/y/\">a &lt; b</a>")))))

;; -- external link emit escape retrofit --

(ert-deftest a3madkour-pub-rewrite-test/external-link-display-text-escaped ()
  "External link display text with < > & escapes properly."
  (let ((result (a3madkour-pub/rewrite-link
                 "[[https://example.com/x][a & b]]" "src")))
    (should (equal (plist-get result :html)
                   "<a href=\"https://example.com/x\">a &amp; b</a>"))))

(ert-deftest a3madkour-pub-rewrite-test/external-link-href-with-amp-escaped ()
  "URL with & in querystring escapes to &amp; in href."
  (let ((result (a3madkour-pub/rewrite-link
                 "[[https://example.com/?a=1&b=2][text]]" "src")))
    (should (equal (plist-get result :html)
                   "<a href=\"https://example.com/?a=1&amp;b=2\">text</a>"))))

;; -- rewrite-link asset-branch integration --

(ert-deftest a3madkour-pub-rewrite-test/asset-dispatch-page ()
  "Asset-shaped link dispatches to rewrite-asset-link (no :pending-asset)."
  (let* ((root (make-temp-file "a3-pub-disp-" t))
         (a3madkour-pub-canonical-asset-root root))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "page/foo" root) t)
          (with-temp-file (expand-file-name "page/foo/x.png" root) (insert "d"))
          (cl-letf (((symbol-function 'a3madkour-pub--id-to-file)
                     (lambda (_) nil))
                    ((symbol-function 'a3madkour-pub/note-slug)
                     (lambda (_) "foo")))
            (let* ((link (format "[[%s][alt]]"
                                  (expand-file-name "page/foo/x.png" root)))
                   (result (a3madkour-pub/rewrite-link link "src")))
              (should (plist-get result :html))
              (should-not (plist-get result :pending-asset)))))
      (delete-directory root t))))

(ert-deftest a3madkour-pub-rewrite-test/asset-dispatch-missing ()
  "Missing file routed to rewrite-asset-link's :inert path."
  (let* ((root (make-temp-file "a3-pub-dispm-" t))
         (a3madkour-pub-canonical-asset-root root))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil))
                  ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
          (let* ((link (format "[[%s/page/foo/missing.png]]" root))
                 (result (a3madkour-pub/rewrite-link link "src")))
            (should (plist-get result :inert))
            (should-not (plist-get result :pending-asset))))
      (delete-directory root t))))

(ert-deftest a3madkour-pub-rewrite-test/pending-asset-shape-removed ()
  "After A.1.c integration, no return path produces :pending-asset."
  ;; Walk through several asset shapes; none should return :pending-asset.
  (let* ((root (make-temp-file "a3-pub-noprev-" t))
         (a3madkour-pub-canonical-asset-root root))
    (unwind-protect
        (cl-letf (((symbol-function 'a3madkour-pub--id-to-file) (lambda (_) nil))
                  ((symbol-function 'a3madkour-pub/note-slug) (lambda (_) "foo")))
          (dolist (link '("[[./assets/page/foo/x.png]]"
                           "[[./assets/shared/y.svg]]"
                           "[[/tmp/somewhere/z.pdf]]"))
            (let ((result (a3madkour-pub/rewrite-link link "src")))
              (should-not (plist-get result :pending-asset)))))
      (delete-directory root t))))

;; -- rewrite-buffer-links --

(ert-deftest a3madkour-pub-rewrite-test/buffer-links-resolved-id ()
  "Resolved id-link in buffer → replaced by @@html:<a href>@@ export snippet."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("target-id" :state live :section "garden" :slug "foo")
    ("source-id" :state live :section "garden" :slug "src"))
   (with-temp-buffer
     (insert "prefix [[id:target-id][text]] suffix")
     (a3madkour-pub-rewrite/rewrite-buffer-links "source-id")
     (should (equal (buffer-string)
                    "prefix @@html:<a href=\"/garden/foo/\">text</a>@@ suffix")))))

(ert-deftest a3madkour-pub-rewrite-test/buffer-links-unresolved-id-inert ()
  "Unresolved id-link in buffer → replaced by inert plain text + warning."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("source-id" :state live :section "garden" :slug "src"))
   ;; No entry for "unknown-id" → published-p returns nil → :inert.
   (with-temp-buffer
     (insert "alpha [[id:unknown-id][missing]] omega")
     (let ((warnings (a3madkour-pub-rewrite/rewrite-buffer-links "source-id")))
       (should (equal (buffer-string) "alpha missing omega"))
       (should (= 1 (length warnings)))
       (should (string-match-p "private\\|unpublished\\|unknown" (car warnings)))))))

(ert-deftest a3madkour-pub-rewrite-test/buffer-links-multiple-on-one-line ()
  "Three links on one line all rewrite correctly (covers the MAP case).
The unresolved [[id:missing]] case also confirms the warnings list
accumulates across multiple per-link rewrites in one scan."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("t1" :state live :section "garden" :slug "one")
    ("t2" :state live :section "garden" :slug "two")
    ("source-id" :state live :section "garden" :slug "src"))
   (with-temp-buffer
     (insert "see [[id:t1][One]] and [[id:t2][Two]] and [[id:missing][Three]] end")
     (let ((warnings (a3madkour-pub-rewrite/rewrite-buffer-links "source-id")))
       (should (equal (buffer-string)
                      (concat "see "
                              "@@html:<a href=\"/garden/one/\">One</a>@@"
                              " and "
                              "@@html:<a href=\"/garden/two/\">Two</a>@@"
                              " and Three end")))
       (should (= 1 (length warnings)))))))

(ert-deftest a3madkour-pub-rewrite-test/buffer-links-external-url-untouched ()
  "External URL `[[https://...]]' passes through unchanged (ox-hugo handles it)."
  (with-temp-buffer
    ;; No `with-stubbed' here: the external-URL branch of `rewrite-link'
    ;; fires before any note-metadata / published-p lookup, so no stub is
    ;; needed.  rewrite-buffer-links should also short-circuit external
    ;; schemes via its own scheme-guard before invoking rewrite-link.
    (insert "see [[https://example.com][Example]] for details")
    (let ((warnings (a3madkour-pub-rewrite/rewrite-buffer-links "source-id")))
      (should (equal (buffer-string)
                     "see [[https://example.com][Example]] for details"))
      (should-not warnings))))

(ert-deftest a3madkour-pub-rewrite-test/buffer-links-asset-untouched ()
  "Asset-shaped link `[[./assets/...]]' passes through unchanged."
  (with-temp-buffer
    ;; No `with-stubbed' here: asset-shaped links are skipped by
    ;; rewrite-buffer-links' scheme-guard before rewrite-link is called.
    (insert "fig: [[./assets/page/foo/x.png]]")
    (let ((warnings (a3madkour-pub-rewrite/rewrite-buffer-links "source-id")))
      (should (equal (buffer-string)
                     "fig: [[./assets/page/foo/x.png]]"))
      (should-not warnings))))

(ert-deftest a3madkour-pub-rewrite-test/buffer-links-typed-link-class ()
  "[[supports:UUID][text]] resolved → @@html:<a class=\"link-supports\">@@ snippet."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("tgt" :state live :section "garden" :slug "ev")
    ("source-id" :state live :section "garden" :slug "src"))
   (with-temp-buffer
     (insert "[[supports:tgt][evidence]]")
     (a3madkour-pub-rewrite/rewrite-buffer-links "source-id")
     (should (equal (buffer-string)
                    "@@html:<a class=\"link-supports\" href=\"/garden/ev/\">evidence</a>@@")))))

(ert-deftest a3madkour-pub-rewrite-test/buffer-links-file-link ()
  "[[file:target.org][text]] dispatches via `file' scheme arm — recursing
into id-link semantics after resolving the target's top-level :ID:.

The buffer scanner's only contribution for `file:' is the dispatch guard
in the `when' clause; this test pins that the `file' arm is wired (a typo
or omitted-arm regression would leave the link untouched)."
  ;; Stub --file-top-level-id so we don't need a real .org file on disk.
  (cl-letf (((symbol-function 'a3madkour-pub--file-top-level-id)
             (lambda (_file) "target-id"))
            ((symbol-function 'a3madkour-pub--id-to-file)
             (lambda (_id) nil)))  ; no heading-suffix in this test → unused
    (a3madkour-pub-rewrite-test--with-stubbed
     (("target-id" :state live :section "garden" :slug "foo")
      ("source-id" :state live :section "garden" :slug "src"))
     (with-temp-buffer
       (insert "see [[file:target.org][Target]] for context")
       (a3madkour-pub-rewrite/rewrite-buffer-links "source-id")
       (should (equal (buffer-string)
                      "see @@html:<a href=\"/garden/foo/\">Target</a>@@ for context"))))))

(ert-deftest a3madkour-pub-rewrite-test/buffer-links-id-without-display-text ()
  "[[id:UUID]] (no text) → @@html:<a href>@@ snippet; URL as display text; no warnings."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("target-id" :state live :section "garden" :slug "foo")
    ("source-id" :state live :section "garden" :slug "src"))
   (with-temp-buffer
     (insert "see [[id:target-id]] for context")
     (let ((warnings (a3madkour-pub-rewrite/rewrite-buffer-links "source-id")))
       (should (equal (buffer-string)
                      "see @@html:<a href=\"/garden/foo/\">/garden/foo/</a>@@ for context"))
       (should-not warnings)))))

;; -- rewrite-to-tmp-file: shared per-handler pre-export wrapper --

(ert-deftest a3madkour-pub-rewrite-test/rewrite-to-tmp-file-happy-path ()
  "Returns a tmp .org path; file contains rewritten @@html:@@ snippet."
  (a3madkour-pub-rewrite-test--with-stubbed
   (("target-id" :state live :section "garden" :slug "foo")
    ("source-id" :state live :section "garden" :slug "src"))
   (let ((src (make-temp-file "rewrite-tmp-src-" nil ".org"))
         tmp)
     (unwind-protect
         (progn
           (with-temp-file src
             (insert "see [[id:target-id]] for context\n"))
           (setq tmp (a3madkour-pub-rewrite/rewrite-to-tmp-file src "source-id"))
           (should (stringp tmp))
           (should (file-exists-p tmp))
           (should (string-suffix-p ".org" tmp))
           (with-temp-buffer
             (insert-file-contents tmp)
             (should (string-match-p
                      "@@html:<a href=\"/garden/foo/\">/garden/foo/</a>@@"
                      (buffer-string)))))
       (when (and tmp (file-exists-p tmp)) (delete-file tmp))
       (when (file-exists-p src) (delete-file src))))))

(ert-deftest a3madkour-pub-rewrite-test/rewrite-to-tmp-file-log-tag-custom ()
  "Custom LOG-TAG appears bracketed in the warning message."
  ;; Force the rewriter to emit a warning by pointing at an unresolved id;
  ;; we don't care about the file contents — only the message format.
  (a3madkour-pub-rewrite-test--with-stubbed
   (("source-id" :state live :section "garden" :slug "src"))
   (let ((src (make-temp-file "rewrite-tmp-src-" nil ".org"))
         tmp captured)
     (unwind-protect
         (progn
           (with-temp-file src
             (insert "see [[id:missing-id]] for context\n"))
           (cl-letf (((symbol-function 'message)
                      (lambda (fmt &rest args)
                        (push (apply #'format fmt args) captured))))
             (setq tmp (a3madkour-pub-rewrite/rewrite-to-tmp-file
                        src "source-id" "a3-pub-essays")))
           (should (cl-some (lambda (m) (string-match-p "\\[a3-pub-essays\\] rewrite WARN" m))
                            captured)))
       (when (and tmp (file-exists-p tmp)) (delete-file tmp))
       (when (file-exists-p src) (delete-file src))))))

(ert-deftest a3madkour-pub-rewrite-test/rewrite-to-tmp-file-cleans-up-on-signal ()
  "If the rewriter signals, the tmp file is deleted before re-raising."
  (let ((src (make-temp-file "rewrite-tmp-src-" nil ".org"))
        (tmps-before (directory-files temporary-file-directory t "\\`a3-pub-pre-export-")))
    (unwind-protect
        (progn
          (with-temp-file src (insert "irrelevant\n"))
          (cl-letf (((symbol-function 'a3madkour-pub-rewrite/rewrite-buffer-links)
                     (lambda (&rest _) (error "boom"))))
            (should-error
             (a3madkour-pub-rewrite/rewrite-to-tmp-file src "source-id")))
          (let ((tmps-after (directory-files temporary-file-directory t "\\`a3-pub-pre-export-")))
            (should (equal (length tmps-before) (length tmps-after)))))
      (when (file-exists-p src) (delete-file src)))))

(provide 'a3madkour-publish-rewrite-test)

;;; a3madkour-publish-rewrite-test.el ends here
