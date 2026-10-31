;;; a3madkour-publish-author-test.el --- tests for -author.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the publish-author interactive helpers (Tier 5.2).
;;; Code:

(require 'ert)
(require 'ob-core)
(require 'a3madkour-publish-author)
(require 'a3madkour-sections-fixture)
(require 'a3madkour-publish-research)
(require 'a3madkour-publish-async)

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
    (insert "#+title: Test\n#+filetags: :t:\n#+HUGO_SUMMARY: S\n\n* Heading\n")
    (a3-publish-mark "essays")
    (should (string-match-p "^#\\+HUGO_PUBLISH:[[:space:]]+t$"
                            (buffer-string)))
    (should (string-match-p "^#\\+HUGO_SECTION:[[:space:]]+essays$"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/mark-gives-a-file-without-id-one ()
  "An essay is a plain org file, not an org-roam note, so nothing gave it an
:ID:; the publish history keys every page by it.  Mark adds a file-level
ID in a drawer that is the first element, ahead of the keywords."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n#+filetags: :t:\n#+HUGO_SUMMARY: S\n\n* Heading\n")
    (a3-publish-mark "essays")
    (should (string-match-p "\\`:PROPERTIES:\n:ID: [-[:xdigit:]]\\{36\\}\n:END:\n#\\+"
                            (buffer-string)))
    (should (eq (org-element-type (org-element-at-point (point-min))) 'property-drawer))
    (let ((id (org-entry-get (point-min) "ID")))
      (should id)
      ;; Marking again keeps the same ID.
      (a3-publish-mark "essays")
      (should (equal (org-entry-get (point-min) "ID") id))
      (should (= 1 (how-many "^:ID:" (point-min) (point-max)))))))

(ert-deftest a3madkour-pub-author-test/mark-keeps-file-property-drawer-first ()
  "S1 row 10: an org-roam note opens with its file-level :PROPERTIES: drawer.
Org only reads that drawer as the file's properties when it is the first
element, so inserting the keywords above it demoted it to a plain drawer —
ox-hugo then printed :ID: into the page body and org-roam lost the note's
ID.  The keywords must land after :END:."
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:ID:       abc-123\n:END:\n#+title: Test\n\n* Heading\n")
    (a3-publish-mark "garden")
    (should (string-prefix-p ":PROPERTIES:\n:ID:       abc-123\n:END:\n"
                             (buffer-string)))
    (should (string-match-p "^#\\+HUGO_PUBLISH:[[:space:]]+t$" (buffer-string)))
    (should (string-match-p "^#\\+HUGO_SECTION:[[:space:]]+garden$" (buffer-string)))
    (should (eq (org-element-type
                 (org-element-at-point (point-min)))
                'property-drawer))
    (should (equal (org-entry-get (point-min) "ID") "abc-123"))))

(ert-deftest a3madkour-pub-author-test/mark-repairs-drawer-displaced-by-old-mark ()
  "S1 row 10: a note an earlier `a3-publish-mark' left with its keywords above
the property drawer is repaired by marking it again — the drawer moves back
to the top, keywords and body are kept, nothing is duplicated."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_SECTION: garden\n#+HUGO_PUBLISH: t\n"
            ":PROPERTIES:\n:ID:       abc-123\n:END:\n#+title: Test\n\n* Heading\nBody.\n")
    (a3-publish-mark "garden")
    (should (equal (buffer-string)
                   (concat ":PROPERTIES:\n:ID:       abc-123\n:END:\n"
                           "#+HUGO_SECTION: garden\n#+HUGO_PUBLISH: t\n"
                           "#+title: Test\n\n* Heading\nBody.\n")))
    (should (equal (org-entry-get (point-min) "ID") "abc-123"))))

(ert-deftest a3madkour-pub-author-test/mark-leaves-heading-drawer-alone ()
  "A drawer that belongs to a heading is not a file drawer: no keyword-only
run precedes it, so the repair must not hoist it."
  (with-temp-buffer
    (org-mode)
    (insert "#+title: Test\n\n* Heading\n:PROPERTIES:\n:ID:       h-1\n:END:\n")
    (a3-publish-mark "garden")
    (should (string-match-p "^\\* Heading\n:PROPERTIES:\n:ID:       h-1\n:END:"
                            (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/mark-updates-section-in-place-when-present ()
  "mark: existing HUGO_SECTION → updated in place (cross-section guard skipped
when caller passes the same answer to y-or-n-p)."
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+title: Test\n#+filetags: :t:\n#+HUGO_SUMMARY: S\n")
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
    (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n#+HUGO_SUMMARY: S\n"
            "#+title: T\n#+filetags: :t:\n")
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

;; -- Section registry Task 7: custom front matter helpers --

(ert-deftest a3madkour-pub-author-test/cfm-segments-split-like-ox-hugo ()
  (should (equal (a3madkour-pub-author--cfm-segments ":status active :weight 10")
                 '(("status" . ":status active") ("weight" . ":weight 10"))))
  (should (equal (a3madkour-pub-author--cfm-segments ":tagline \"a :b c\" :year 2026")
                 '(("tagline" . ":tagline \"a :b c\"") ("year" . ":year 2026"))))
  (should (null (a3madkour-pub-author--cfm-segments "   "))))

(ert-deftest a3madkour-pub-author-test/cfm-keys-span-every-line ()
  (with-temp-buffer
    (org-mode)
    (insert "#+title: T\n"
            "#+HUGO_CUSTOM_FRONT_MATTER: :status active :weight 10\n"
            "#+hugo_custom_front_matter: :theme t-1\n")
    (should (equal (a3madkour-pub-author--cfm-keys) '("status" "weight" "theme")))
    (should (a3madkour-pub-author--field-present-p "weight"))
    (should-not (a3madkour-pub-author--field-present-p "description"))
    (should (equal (a3madkour-pub-author--cfm-get "theme") "t-1"))
    (should (equal (a3madkour-pub-author--cfm-get "weight") "10"))
    (should-not (a3madkour-pub-author--cfm-get "media_type"))))

(ert-deftest a3madkour-pub-author-test/field-present-reads-dedicated-keywords ()
  (with-temp-buffer
    (org-mode)
    (insert "#+title: T\n#+HUGO_DESCRIPTION: D\n#+HUGO_SUMMARY:\n")
    (should (a3madkour-pub-author--field-present-p "title"))
    (should (a3madkour-pub-author--field-present-p "description"))
    ;; Present with no value counts as absent: mark fills it.
    (should-not (a3madkour-pub-author--field-present-p "summary"))))

(ert-deftest a3madkour-pub-author-test/upsert-cfm-key-replaces-one-segment ()
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_SECTION: research/themes\n"
            "#+HUGO_CUSTOM_FRONT_MATTER: :status active :weight 10\n")
    (a3madkour-pub-author--upsert-cfm-key "weight" "20")
    (should (equal (buffer-string)
                   (concat "#+HUGO_SECTION: research/themes\n"
                           "#+HUGO_CUSTOM_FRONT_MATTER: :status active :weight 20\n")))))

(ert-deftest a3madkour-pub-author-test/upsert-cfm-key-appends-after-last-cfm-line ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:ID: x-1\n:END:\n"
            "#+HUGO_SECTION: research/themes\n"
            "#+HUGO_CUSTOM_FRONT_MATTER: :status active\n"
            "#+title: T\n\nBody\n")
    (a3madkour-pub-author--upsert-cfm-key "weight" "10")
    (should (equal (buffer-string)
                   (concat ":PROPERTIES:\n:ID: x-1\n:END:\n"
                           "#+HUGO_SECTION: research/themes\n"
                           "#+HUGO_CUSTOM_FRONT_MATTER: :status active\n"
                           "#+HUGO_CUSTOM_FRONT_MATTER: :weight 10\n"
                           "#+title: T\n\nBody\n")))))

(ert-deftest a3madkour-pub-author-test/upsert-cfm-key-first-line-goes-after-section ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:ID: x-1\n:END:\n#+HUGO_SECTION: garden\n#+title: T\n")
    (a3madkour-pub-author--upsert-cfm-key "year" "2026")
    (should (equal (buffer-string)
                   (concat ":PROPERTIES:\n:ID: x-1\n:END:\n#+HUGO_SECTION: garden\n"
                           "#+HUGO_CUSTOM_FRONT_MATTER: :year 2026\n#+title: T\n")))))

(ert-deftest a3madkour-pub-author-test/upsert-cfm-key-keeps-drawer-first ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:ID:       abc-123\n:END:\n#+title: T\n")
    (a3madkour-pub-author--upsert-cfm-key "year" "2026")
    (should (string-prefix-p ":PROPERTIES:\n:ID:       abc-123\n:END:\n#+HUGO_CUSTOM_FRONT_MATTER: :year 2026\n"
                             (buffer-string)))
    (should (equal (org-entry-get (point-min) "ID") "abc-123"))))

(ert-deftest a3madkour-pub-author-test/remove-cfm-key-keeps-neighbours ()
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_CUSTOM_FRONT_MATTER: :status active :topic_map a b\n"
            "#+HUGO_CUSTOM_FRONT_MATTER: :topic_map c\n"
            "#+title: T\n")
    (a3madkour-pub-author--remove-cfm-key "topic_map")
    (should (equal (buffer-string)
                   "#+HUGO_CUSTOM_FRONT_MATTER: :status active\n#+title: T\n"))))

(ert-deftest a3madkour-pub-author-test/remove-field-handles-keyword-fields ()
  (with-temp-buffer
    (org-mode)
    (insert "#+title: T\n#+HUGO_SUMMARY: S\n#+HUGO_CUSTOM_FRONT_MATTER: :weight 10\n")
    (a3madkour-pub-author--remove-field "summary")
    (a3madkour-pub-author--remove-field "weight")
    (should (equal (buffer-string) "#+title: T\n"))))

(ert-deftest a3madkour-pub-author-test/cfm-value-round-trips-through-ox-hugo-parser ()
  "Text is quoted so ox-hugo's parser returns it verbatim: spaces, a
` :' that would otherwise start a new key, a colon, and digits that
`org-babel-read' would turn into a number."
  (dolist (v '("plain" "two words" "A: colon" "x :y z" "2026"))
    (let ((parsed (org-babel-parse-header-arguments
                   (format ":k %s" (a3madkour-pub-author--cfm-value "text" v)))))
      (should (equal (cdr (assq :k parsed)) v))))
  (should (equal (a3madkour-pub-author--cfm-value "int" 40) "40"))
  (should (equal (a3madkour-pub-author--cfm-value "bool" t) "true"))
  (should (equal (a3madkour-pub-author--cfm-value "bool" nil) "false"))
  (should (equal (a3madkour-pub-author--cfm-value "enum" "active") "\"active\""))
  (should (equal (a3madkour-pub-author--cfm-value "date" "2026-10-20") "2026-10-20"))
  (should (equal (a3madkour-pub-author--cfm-value "list" '("a" "b")) "a b"))
  ;; A refs list is ONE quoted string; the section normalizers split it.
  (should (equal (a3madkour-pub-author--cfm-value "refs" '("a" "b")) "\"a b\"")))

(ert-deftest a3madkour-pub-author-test/write-field-routes-keyword-vs-cfm ()
  (with-temp-buffer
    (org-mode)
    (insert "#+HUGO_SECTION: research/themes\n#+title: T\n")
    (a3madkour-pub-author--write-field "description" "text" "A \"quoted\" line.")
    (a3madkour-pub-author--write-field "status" "enum" "active")
    (should (string-match-p "^#\\+HUGO_DESCRIPTION: A \"quoted\" line\\.$" (buffer-string)))
    (should (string-match-p "^#\\+HUGO_CUSTOM_FRONT_MATTER: :status \"active\"$" (buffer-string)))))

;; -- Section registry Tasks 8-9: prompt stubs over a temp site --

(defmacro a3madkour-pub-author-test--with-site (&rest body)
  "Run BODY in an org temp buffer over a temp site root carrying the
sections fixture (resolved through `a3madkour-pub/site-data-dir').
`a3madkour-pub/org-notes-dir' is an empty notes dir under that root, so
mark never reads the real ~/org/notes; `--note' writes into it."
  (declare (indent 0))
  `(a3madkour-sections-test--with-root a3madkour-sections-test--json
     (let ((a3madkour-pub/org-notes-dir
            (file-name-as-directory (expand-file-name "notes" root))))
       (make-directory a3madkour-pub/org-notes-dir t)
       (with-temp-buffer (org-mode) ,@body))))

(defun a3madkour-pub-author-test--note (name &rest lines)
  "Write org note NAME.org under the notes dir, one LINES element per line."
  (with-temp-file (expand-file-name (concat name ".org") a3madkour-pub/org-notes-dir)
    (dolist (l lines) (insert l "\n"))))

(defun a3madkour-pub-author-test--page (section slug &rest kv)
  "Publish a stub content/SECTION/SLUG/index.md with frontmatter KV.
KV alternates key and already-rendered YAML value strings."
  (let ((dir (expand-file-name (format "content/%s/%s" section slug)
                               (a3madkour-pub-yaml/site-root))))
    (make-directory dir t)
    (with-temp-file (expand-file-name "index.md" dir)
      (insert "---\n")
      (while kv (insert (format "%s: %s\n" (pop kv) (pop kv))))
      (insert "---\nBody\n"))))

(defvar vertico-preselect)

(defun a3madkour-pub-author-test--prompt-preselected-p ()
  "Non-nil when Vertico would preselect the input line."
  (and (boundp 'vertico-preselect) (eq vertico-preselect 'prompt)))

(defmacro a3madkour-pub-author-test--answering (answers &rest body)
  "Run BODY with every prompt answered from ANSWERS, or the test fails.
ANSWERS is an alist (REGEXP . ANSWER) matched against the prompt text.
ANSWER is returned as-is, except: a function is called; for
`completing-read' the keyword `:default' returns the DEF argument and
`:first' the first candidate; for `completing-read-multiple' `:first'
returns a one-element list.  `:ret' is Vertico's RET on untouched input:
the empty answer when `vertico-preselect' is `prompt', else a candidate."
  (declare (indent 1))
  `(let ((answers ,answers))
     (cl-flet ((answer (prompt)
                 (let ((hit (cl-find-if (lambda (a) (string-match-p (car a) prompt))
                                        answers)))
                   (unless hit (ert-fail (list "unexpected prompt" prompt)))
                   (let ((v (cdr hit)))
                     (if (functionp v) (funcall v) v)))))
       (cl-letf (((symbol-function 'completing-read)
                  (lambda (prompt coll &optional _p _r _i _h def &rest _)
                    (let ((v (answer prompt)))
                      (cond ((eq v :default) def)
                            ((eq v :first) (car coll))
                            ((eq v :ret) (if (a3madkour-pub-author-test--prompt-preselected-p)
                                             "" (car coll)))
                            (t v)))))
                 ((symbol-function 'completing-read-multiple)
                  (lambda (prompt coll &rest _)
                    (let ((v (answer prompt)))
                      (cond ((eq v :first) (list (car coll)))
                            ((eq v :ret) (unless (a3madkour-pub-author-test--prompt-preselected-p)
                                           (list (car coll))))
                            (t v)))))
                 ((symbol-function 'read-string)
                  (lambda (prompt &rest _) (answer prompt)))
                 ((symbol-function 'y-or-n-p)
                  (lambda (prompt) (answer prompt))))
         ,@body))))

(ert-deftest a3madkour-pub-author-test/published-targets-read-bundle-titles ()
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--page "research/themes" "beta" "title" "\"Beta \\\"B\\\"\"")
    (a3madkour-pub-author-test--page "research/themes" "alpha" "title" "Alpha")
    (a3madkour-pub-author-test--page "research/themes" "untitled")
    (with-temp-file (expand-file-name "content/research/themes/_index.md"
                                      (a3madkour-pub-yaml/site-root))
      (insert "---\ntitle: Section\n---\n"))
    (should (equal (a3madkour-pub-author--published-targets "research/themes")
                   '(("alpha" . "Alpha") ("beta" . "Beta \"B\"")
                     ("untitled" . "untitled"))))
    (should-not (a3madkour-pub-author--published-targets "streams"))))

(ert-deftest a3madkour-pub-author-test/targets-include-marked-unpublished-notes ()
  "A note marked live for the section counts before its first publish, so
a question marked in the same session as its theme can pick that theme.
Drafts, unmarked notes and other sections do not; a marked note whose
bundle exists is listed once."
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--page "research/themes" "alpha" "title" "\"Alpha\"")
    (a3madkour-pub-author-test--note "new" "#+title: New theme"
                                     "#+HUGO_PUBLISH: t" "#+HUGO_SECTION: research/themes")
    (a3madkour-pub-author-test--note "alpha" "#+title: Alpha"
                                     "#+HUGO_PUBLISH: t" "#+HUGO_SECTION: research/themes")
    (a3madkour-pub-author-test--note "drafty" "#+title: Drafty"
                                     "#+HUGO_PUBLISH: t" "#+HUGO_SECTION: research/themes"
                                     "#+HUGO_DRAFT: t")
    (a3madkour-pub-author-test--note "private" "#+title: Private"
                                     "#+HUGO_SECTION: research/themes")
    (a3madkour-pub-author-test--note "garden" "#+title: G"
                                     "#+HUGO_PUBLISH: t" "#+HUGO_SECTION: garden")
    (a3madkour-pub-author-test--note "broken" "#+HUGO_PUBLISH: t")
    (should (equal (a3madkour-pub-author--published-targets "research/themes")
                   '(("alpha" . "Alpha") ("new-theme" . "New theme"))))))

(ert-deftest a3madkour-pub-author-test/targets-exclude-the-buffer-being-marked ()
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--note "self" "#+title: Self"
                                     "#+HUGO_PUBLISH: t" "#+HUGO_SECTION: research/questions")
    (insert-file-contents (expand-file-name "self.org" a3madkour-pub/org-notes-dir))
    (setq buffer-file-name (expand-file-name "self.org" a3madkour-pub/org-notes-dir))
    (unwind-protect
        (should-not (a3madkour-pub-author--published-targets "research/questions"))
      (set-buffer-modified-p nil)
      (setq buffer-file-name nil))))

(ert-deftest a3madkour-pub-author-test/next-weight-counts-marked-unpublished-notes ()
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--page "research/themes" "a" "weight" "10")
    (a3madkour-pub-author-test--note "new" "#+title: New theme"
                                     "#+HUGO_PUBLISH: t" "#+HUGO_SECTION: research/themes"
                                     "#+HUGO_CUSTOM_FRONT_MATTER: :weight 50")
    (should (= (a3madkour-pub-author--next-weight "research/themes") 60))))

(ert-deftest a3madkour-pub-author-test/next-weight-is-max-plus-ten ()
  (a3madkour-pub-author-test--with-site
    (should (= (a3madkour-pub-author--next-weight "research/themes") 10))
    (a3madkour-pub-author-test--page "research/themes" "a" "weight" "10")
    (a3madkour-pub-author-test--page "research/themes" "b" "weight" "30")
    (a3madkour-pub-author-test--page "research/themes" "c" "weight" "\"x\"")
    (should (= (a3madkour-pub-author--next-weight "research/themes") 40))))

(ert-deftest a3madkour-pub-author-test/fields-to-fill-per-section ()
  (a3madkour-pub-author-test--with-site
    (insert "#+title: T\n")
    ;; No #+filetags: a required tags field (source filetags) is asked for.
    (should (equal (mapcar #'car (a3madkour-pub-author--fields-to-fill "research/themes"))
                   '("tags" "description" "status" "weight")))
    (should (equal (mapcar #'car (a3madkour-pub-author--fields-to-fill "research/questions"))
                   '("description" "status" "theme" "supporting_notes" "started")))
    (should-not (a3madkour-pub-author--fields-to-fill "garden"))
    (should (equal (mapcar #'car (a3madkour-pub-author--fields-to-fill "essays"))
                   '("summary" "tags")))
    (should-not (a3madkour-pub-author--fields-to-fill "library/reading"))
    (should (equal (mapcar #'car (a3madkour-pub-author--fields-to-fill "recipes"))
                   '("summary")))
    (insert "#+HUGO_CUSTOM_FRONT_MATTER: :status dormant :media_type book\n")
    (should (equal (mapcar #'car (a3madkour-pub-author--fields-to-fill "research/themes"))
                   '("tags" "description" "weight")))
    ;; A garden media_type/status/creator is a drawer field: the custom
    ;; front matter value selects the case but does not satisfy the field.
    (should (equal (mapcar #'car (a3madkour-pub-author--fields-to-fill "garden"))
                   '("media_type" "status" "creator")))))

(ert-deftest a3madkour-pub-author-test/fields-to-fill-bad-variant-is-user-error ()
  (a3madkour-pub-author-test--with-site
    (insert "#+HUGO_CUSTOM_FRONT_MATTER: :media_type hologram\n")
    (should-error (a3madkour-pub-author--fields-to-fill "garden") :type 'user-error)))

(ert-deftest a3madkour-pub-author-test/ask-by-type ()
  (a3madkour-pub-author-test--with-site
    (let ((ints '("abc" "7")) (texts '("" "has \"quote\"" "ok text")))
      (a3madkour-pub-author-test--answering
          (list (cons " status: " :default)
                (cons " weight" (lambda () (pop ints)))
                (cons " tagline: " (lambda () (pop texts)))
                (cons " summary (optional): " ""))
        (should (equal (a3madkour-pub-author--ask
                        "research/themes" "status"
                        (a3madkour-sections/field "research/themes" "status"))
                       "active"))
        (should (equal (a3madkour-pub-author--ask
                        "research/questions" "weight" '((type . "int") (required . t)))
                       7))
        (should (equal (a3madkour-pub-author--ask
                        "works/games" "tagline" '((type . "text") (required . t)))
                       "ok text"))
        (should (eq (a3madkour-pub-author--ask
                     "research/themes" "summary" '((type . "text")))
                    'skip))
        (should (equal (a3madkour-pub-author--ask
                        "research/questions" "started"
                        (a3madkour-sections/field "research/questions" "started"))
                       (format-time-string "%Y-%m-%d")))))))

(ert-deftest a3madkour-pub-author-test/ask-ref-without-targets ()
  (a3madkour-pub-author-test--with-site
    (let ((err (should-error (a3madkour-pub-author--ask
                              "research/questions" "theme"
                              (a3madkour-sections/field "research/questions" "theme"))
                             :type 'user-error)))
      (should (string-match-p "publish a research/themes page first"
                              (error-message-string err))))
    (should (eq (a3madkour-pub-author--ask
                 "research/questions" "supporting_notes"
                 (a3madkour-sections/field "research/questions" "supporting_notes"))
                'skip))))

(ert-deftest a3madkour-pub-author-test/optional-pick-ret-on-untouched-input-skips ()
  "Under Vertico, RET on an untouched optional pick-list skips the field.
Vertico preselects the first candidate by default and RET submits it under
require-match, so optional pick-lists must preselect the empty input.
A required pick-list and an enum with a default keep Vertico's default."
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--question-site)
    (let ((vertico-preselect 'directory))
      (a3madkour-pub-author-test--answering
          '((" supporting_notes (optional): " . :ret)
            (" related (optional): " . :ret)
            (" mood (optional): " . :ret)
            (" status: " . :ret)
            (" theme: " . :ret))
        (should (eq (a3madkour-pub-author--ask
                     "research/questions" "supporting_notes"
                     (a3madkour-sections/field "research/questions" "supporting_notes"))
                    'skip))
        (should (eq (a3madkour-pub-author--ask
                     "research/questions" "related"
                     '((type . "ref") (to . "garden")))
                    'skip))
        (should (eq (a3madkour-pub-author--ask
                     "research/questions" "mood"
                     '((type . "enum") (values . ("calm" "tense"))))
                    'skip))
        (should (equal (a3madkour-pub-author--ask
                        "research/questions" "theme"
                        (a3madkour-sections/field "research/questions" "theme"))
                       "procedural-narrative"))
        (should (stringp (a3madkour-pub-author--ask
                          "research/themes" "status"
                          (a3madkour-sections/field "research/themes" "status"))))
        (should (eq vertico-preselect 'directory))))))

(ert-deftest a3madkour-pub-author-test/fields-to-fill-blank-selector-is-concept ()
  (a3madkour-pub-author-test--with-site
    (insert "#+HUGO_CUSTOM_FRONT_MATTER: :media_type \"\"\n")
    (let ((blank (mapcar #'car (a3madkour-pub-author--fields-to-fill "garden"))))
      (erase-buffer)
      (should (equal blank (mapcar #'car (a3madkour-pub-author--fields-to-fill "garden")))))))

;; -- Section registry Task 9: the a3-publish-mark fill-in --

(ert-deftest a3madkour-pub-author-test/mark-theme-fills-status-description-weight ()
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--page "research/themes" "alpha" "title" "\"Alpha\"" "weight" "10")
    (a3madkour-pub-author-test--page "research/themes" "beta" "title" "\"Beta\"" "weight" "30")
    (insert "#+title: New theme\n#+filetags: :t:\n\nBody\n")
    (a3madkour-pub-author-test--answering
        '((" description: " . "What the theme asks.")
          (" status: " . :default))
      (should (equal (a3-publish-mark "research/themes") "research/themes")))
    (let ((s (buffer-string)))
      (should (string-match-p "^#\\+HUGO_PUBLISH: t$" s))
      (should (string-match-p "^#\\+HUGO_SECTION: research/themes$" s))
      (should (string-match-p "^#\\+HUGO_DESCRIPTION: What the theme asks\\.$" s))
      (should (string-match-p "^#\\+HUGO_CUSTOM_FRONT_MATTER: :status \"active\"$" s))
      (should (string-match-p "^#\\+HUGO_CUSTOM_FRONT_MATTER: :weight 40$" s)))))

(ert-deftest a3madkour-pub-author-test/mark-asks-tags-when-filetags-are-only-editorial ()
  "Required `tags' (source filetags) is prompted for when every filetag is
editorial, since the pipeline strips them and drops the key; the answer is
appended to `#+filetags:', keeping the editorial tags.  A malformed org tag
re-prompts."
  (a3madkour-pub-author-test--with-site
    (insert "#+title: New theme\n#+filetags: :TODO:\n\nBody\n")
    (let ((tag-answers '("bad-tag" "bayes pcg")))
      (a3madkour-pub-author-test--answering
          (list (cons " description: " "D.")
                (cons " status: " :default)
                (cons " tags: " (lambda () (pop tag-answers))))
        (a3-publish-mark "research/themes")))
    (should (string-match-p "^#\\+filetags: :TODO:bayes:pcg:$" (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/mark-creates-filetags-when-absent ()
  (a3madkour-pub-author-test--with-site
    (insert "#+title: New theme\n\nBody\n")
    (a3madkour-pub-author-test--answering
        '((" description: " . "D.") (" status: " . :default) (" tags: " . "pcg"))
      (a3-publish-mark "research/themes"))
    (should (string-match-p "^#\\+filetags: :pcg:$" (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/mark-skips-tags-when-a-real-filetag-exists ()
  "A non-editorial filetag satisfies the source: no tags prompt (an
unexpected prompt fails the test), and an optional tags field never asks."
  (a3madkour-pub-author-test--with-site
    (insert "#+title: New theme\n#+filetags: :TODO:pcg:\n")
    (a3madkour-pub-author-test--answering
        '((" description: " . "D.") (" status: " . :default))
      (a3-publish-mark "research/themes"))
    (should (string-match-p "^#\\+filetags: :TODO:pcg:$" (buffer-string)))
    (should-not (assoc "tags" (a3madkour-pub-author--fields-to-fill "research/questions")))))

(ert-deftest a3madkour-pub-author-test/mark-asks-title-when-missing ()
  (a3madkour-pub-author-test--with-site
    (insert "#+filetags: :pcg:\n\nBody\n")
    (a3madkour-pub-author-test--answering
        '((" title: " . "A theme") (" description: " . "D.") (" status: " . :default))
      (a3-publish-mark "research/themes"))
    (should (string-match-p "^#\\+TITLE: A theme$" (buffer-string)))))

(defun a3madkour-pub-author-test--question-site ()
  "Publish one theme and two garden notes under the current site root."
  (a3madkour-pub-author-test--page "research/themes" "procedural-narrative"
                                   "title" "\"Procedural narrative\"")
  (a3madkour-pub-author-test--page "garden" "note-a" "title" "\"Note A\"")
  (a3madkour-pub-author-test--page "garden" "note-b" "title" "\"Note B\""))

(defconst a3madkour-pub-author-test--question-answers
  '((" description: " . "Does it hold?")
    (" status: " . :default)
    (" theme: " . "Procedural narrative (procedural-narrative)")
    (" supporting_notes (optional): " . ("Note A (note-a)" "Note B (note-b)"))))

(ert-deftest a3madkour-pub-author-test/mark-question-picks-theme-from-published-set ()
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--question-site)
    (insert "#+title: New question\n")
    (a3madkour-pub-author-test--answering a3madkour-pub-author-test--question-answers
      (a3-publish-mark "research/questions"))
    (let ((s (buffer-string)))
      (should (string-match-p "^#\\+HUGO_CUSTOM_FRONT_MATTER: :theme \"procedural-narrative\"$" s))
            (should (string-match-p "^#\\+HUGO_CUSTOM_FRONT_MATTER: :supporting_notes \"note-a note-b\"$" s))
      (should (string-match-p (format "^#\\+HUGO_CUSTOM_FRONT_MATTER: :started %s$"
                                      (format-time-string "%Y-%m-%d"))
                              s))
      (should (string-match-p "^#\\+HUGO_CUSTOM_FRONT_MATTER: :status \"active\"$" s)))))

(ert-deftest a3madkour-pub-author-test/mark-second-run-asks-nothing ()
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--question-site)
    (insert "#+title: New question\n")
    (a3madkour-pub-author-test--answering a3madkour-pub-author-test--question-answers
      (a3-publish-mark "research/questions"))
    (let ((after-first (buffer-string)))
      (a3madkour-pub-author-test--answering nil
        (a3-publish-mark "research/questions"))
      (should (equal (buffer-string) after-first)))))

(ert-deftest a3madkour-pub-author-test/mark-never-overwrites-a-present-field ()
  (a3madkour-pub-author-test--with-site
    (insert "#+title: T\n#+filetags: :t:\n#+HUGO_DESCRIPTION: Kept.\n"
            "#+HUGO_CUSTOM_FRONT_MATTER: :status dormant\n")
    (a3madkour-pub-author-test--answering nil
      (a3-publish-mark "research/themes"))
    (let ((s (buffer-string)))
      (should (string-match-p "^#\\+HUGO_DESCRIPTION: Kept\\.$" s))
      (should (string-match-p ":status dormant" s))
      (should-not (string-match-p ":status active" s))
      (should (string-match-p "^#\\+HUGO_CUSTOM_FRONT_MATTER: :weight 10$" s)))))

(ert-deftest a3madkour-pub-author-test/mark-quit-mid-way-changes-nothing ()
  "C-g at the third prompt, after two were answered: nothing is written,
not even #+HUGO_PUBLISH."
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--question-site)
    (insert "#+title: New question\n")
    (let ((before (buffer-string)))
      (a3madkour-pub-author-test--answering
          (list (cons " description: " "Does it hold?")
                (cons " status: " :default)
                (cons " theme: " (lambda () (signal 'quit nil))))
        ;; Not `should-error': it catches only `error' conditions, and
        ;; `quit' is not one (verified: it escapes `should-error').
        (should (eq (condition-case nil
                        (progn (a3-publish-mark "research/questions") 'returned)
                      (quit 'quit))
                    'quit)))
      (should (equal (buffer-string) before)))))

(ert-deftest a3madkour-pub-author-test/mark-required-ref-without-targets-errors ()
  (a3madkour-pub-author-test--with-site
    (insert "#+title: New question\n")
    (let ((before (buffer-string)))
      (a3madkour-pub-author-test--answering
          '((" description: " . "Q?") (" status: " . :default))
        (let ((err (should-error (a3-publish-mark "research/questions")
                                 :type 'user-error)))
          (should (string-match-p "publish a research/themes page first"
                                  (error-message-string err)))))
      (should (equal (buffer-string) before)))))

(ert-deftest a3madkour-pub-author-test/mark-fill-keeps-drawer-first ()
  (a3madkour-pub-author-test--with-site
    (insert ":PROPERTIES:\n:ID:       abc-123\n:END:\n#+title: T\n#+filetags: :t:\n")
    (a3madkour-pub-author-test--answering
        '((" description: " . "D.") (" status: " . :default))
      (a3-publish-mark "research/themes"))
    (should (string-prefix-p ":PROPERTIES:\n:ID:       abc-123\n:END:\n" (buffer-string)))
    (should (eq (org-element-type (org-element-at-point (point-min))) 'property-drawer))
    (should (equal (org-entry-get (point-min) "ID") "abc-123"))))

(ert-deftest a3madkour-pub-author-test/mark-section-change-offers-removal ()
  (dolist (accept '(t nil))
    (a3madkour-pub-author-test--with-site
      (insert "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n"
              "#+HUGO_CUSTOM_FRONT_MATTER: :year 2026 :topic_map a b\n#+title: T\n"
              "#+filetags: :t:\n")
      (a3madkour-pub-author-test--answering
          (list (cons "\\`Move from" t)
                (cons "\\`Remove fields not in research/themes (year, topic_map)" accept)
                (cons " description: " "D.")
                (cons " status: " :default))
        (a3-publish-mark "research/themes"))
      (let ((s (buffer-string)))
        (should (string-match-p ":status \"active\"" s))
        (if accept
            (progn (should-not (string-match-p "topic_map" s))
                   (should-not (string-match-p ":year" s)))
          (should (string-match-p ":year 2026 :topic_map a b" s)))))))

(ert-deftest a3madkour-pub-author-test/mark-garden-media-variant-asks-its-fields ()
  (a3madkour-pub-author-test--with-site
    (insert ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:END:\n#+title: A book\n")
    (a3madkour-pub-author-test--answering
        '((" status: " . "finished") (" creator: " . "Example Author"))
      (a3-publish-mark "garden"))
    (should (equal (org-entry-get (point-min) "LIBRARY_STATUS") "finished"))
    (should (equal (org-entry-get (point-min) "LIBRARY_CREATOR") "Example Author"))))

(ert-deftest a3madkour-pub-author-test/mark-refuses-item-note-outside-garden ()
  "A library item note marks only into garden: any other section would
publish the whole note.  The refusal comes before any prompt or write."
  (dolist (sec '("essays" "library/reading" "research/themes"))
    (a3madkour-pub-author-test--with-site
      (insert ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:END:\n#+title: A book\n"
              "#+HUGO_SECTION: garden\n")
      (let ((before (buffer-string)))
        (a3madkour-pub-author-test--answering nil
          (let ((err (should-error (a3-publish-mark sec) :type 'user-error)))
            (should (string-match-p "library item notes publish only to garden"
                                    (error-message-string err)))))
        (should (equal (buffer-string) before))))))

(ert-deftest a3madkour-pub-author-test/mark-library-and-structured ()
  (a3madkour-pub-author-test--with-site
    (insert "#+title: Shelf\n")
    (a3madkour-pub-author-test--answering nil
      (a3-publish-mark "library/reading"))
    (should (string-match-p "^#\\+HUGO_SECTION: library/reading$" (buffer-string))))
  ;; The real contract derives every recipe structure; the by-hand message
  ;; path is exercised by making `sources' a hand-filled structured field.
  (a3madkour-sections-test--with-root
      (a3madkour-sections-test/mutate
       "\"sources\": {\"type\": \"structured\", \"required\": true, \"from\": \"pipeline\"}"
       "\"sources\": {\"type\": \"structured\", \"required\": true}")
    (with-temp-buffer
      (org-mode)
      (insert "#+title: Soup\n")
      (let (said)
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args) (push (apply #'format fmt args) said))))
          (a3madkour-pub-author-test--answering '((" summary: " . "A soup."))
            (a3-publish-mark "recipes")))
        (should (cl-some (lambda (m) (string-match-p "needs sources " m))
                         said))))))

(ert-deftest a3madkour-pub-author-test/mark-errors-on-missing-contract ()
  (a3madkour-sections-test--with-root nil
    (with-temp-buffer
      (org-mode)
      (insert "#+title: T\n")
      (let ((err (should-error (a3-publish-mark "garden") :type 'user-error)))
        (should (string-match-p "contract not found at" (error-message-string err))))
      (should (equal (buffer-string) "#+title: T\n")))))

(ert-deftest a3madkour-pub-author-test/mark-output-publishes-through-ox-hugo ()
  "End to end: what mark writes for a question reaches the bundle with
`theme' as a string and `supporting_notes' as a YAML list."
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--question-site)
    (let* ((root (a3madkour-pub-yaml/site-root))
           (notes-dir (make-temp-file "a3-mark-e2e-notes" t))
           (src (expand-file-name "marked-question.org" notes-dir)))
      (unwind-protect
          (progn
            (make-directory (expand-file-name "content/research/questions" root) t)
            (with-temp-file (expand-file-name "data/url-history.yaml" root)
              (insert "notes: []\n"))
            (insert ":PROPERTIES:\n:ID: 44444444-aaaa-bbbb-cccc-dddddddddddd\n"
                    ":LAST_MODIFIED: 2026-05-30\n:END:\n"
                    "#+title: Marked question\n#+HUGO_BASE_DIR: " root "\n\nBody.\n")
            (a3madkour-pub-author-test--answering a3madkour-pub-author-test--question-answers
              (a3-publish-mark "research/questions"))
            (write-region (point-min) (point-max) src)
            (let ((a3madkour-pub/org-notes-dir notes-dir) (status nil))
              (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
                (a3madkour-pub/begin-publish)
                (a3madkour-pub-research/publish-research-file
                 src (make-a3-pub-async-run) :on-done (lambda (s) (setq status s)))
                (a3madkour-pub/finish-publish))
              (should (eq status 'ok)))
            (let ((md (with-temp-buffer
                        (insert-file-contents
                         (expand-file-name
                          "content/research/questions/marked-question/index.md" root))
                        (buffer-string))))
              (should (string-match-p "^theme: \"procedural-narrative\"$" md))
              (should (string-match-p "^supporting_notes: \\[\"note-a\", \"note-b\"\\]$" md))
              (should (string-match-p "^description: \"Does it hold\\?\"$" md))
              (should (string-match-p "^status: \"active\"$" md))))
        (delete-directory notes-dir t)))))

(ert-deftest a3madkour-pub-author-test/fields-to-fill-real-contract ()
  "Pin what mark asks for against the REAL data/sections.json, per section."
  (a3madkour-sections-test--with-real-site
    ;; Each buffer has a #+title but no #+filetags, so a required tags
    ;; field (source filetags) is asked for too.
    (let ((expect '(("research/themes" "tags" "description" "status" "weight")
                    ("research/questions" "description" "status" "theme"
                     "supporting_notes" "started")
                    ("works/games" "status" "game_kind" "tagline" "year")
                    ("works/music" "format" "year")
                    ("works/poetry") ("garden") ("about")
                    ("streams" "platforms" "category" "archive_status")
                    ("library/reading") ("library/listening")
                    ("library/playing") ("library/watching")
                    ("essays" "summary" "tags") ("recipes" "summary"))))
      (dolist (e expect)
        (with-temp-buffer
          (org-mode)
          (insert "#+title: T\n")
          (should (equal (list (car e)
                               (mapcar #'car (a3madkour-pub-author--fields-to-fill (car e))))
                         (list (car e) (cdr e))))))
      (with-temp-buffer
        (org-mode)
        (insert ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:END:\n#+title: T\n")
        (should (equal (mapcar #'car (a3madkour-pub-author--fields-to-fill "garden"))
                       '("status" "creator")))))))

(ert-deftest a3madkour-pub-author-test/published-targets-skip-drafts ()
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--page "research/themes" "live" "title" "Live" "draft" "false")
    (a3madkour-pub-author-test--page "research/themes" "wip" "title" "Wip" "draft" "true")
    (should (equal (a3madkour-pub-author--published-targets "research/themes")
                   '(("live" . "Live"))))))

(ert-deftest a3madkour-pub-author-test/required-ref-with-only-draft-target-errors ()
  (a3madkour-pub-author-test--with-site
    (a3madkour-pub-author-test--page "research/themes" "wip" "title" "Wip" "draft" "true")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) (ert-fail "a draft was offered as a target"))))
      (let ((err (should-error (a3madkour-pub-author--ask
                                "research/questions" "theme"
                                (a3madkour-sections/field "research/questions" "theme"))
                               :type 'user-error)))
        (should (string-match-p "publish a research/themes page first"
                                (error-message-string err)))))))

(ert-deftest a3madkour-pub-author-test/cfm-value-quotes-ref-and-enum ()
  (should (equal (a3madkour-pub-author--cfm-value "ref" "1984") "\"1984\""))
  (should (equal (a3madkour-pub-author--cfm-value "refs" '("a" "b")) "\"a b\""))
  (should (equal (a3madkour-pub-author--cfm-value "enum" "active") "\"active\"")))

(ert-deftest a3madkour-pub-author-test/numeric-slug-ref-round-trips-as-string ()
  (with-temp-buffer
    (org-mode)
    (a3madkour-pub-author--write-field "theme" "ref" "1984")
    (should (stringp (cdr (assq :theme (org-babel-parse-header-arguments
                                        ":theme \"1984\"" t)))))
    (should (equal (a3madkour-pub-author--cfm-get "theme") "1984"))
    (should (equal (cdr (assq :theme (org-babel-parse-header-arguments
                                      (nth 2 (car (a3madkour-pub-author--cfm-lines))) t)))
                   "1984"))))

(ert-deftest a3madkour-pub-author-test/ask-refuses-backslash ()
  (a3madkour-pub-author-test--with-site
    (let ((texts '("a\\b" "ok")) said)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) said))))
        (a3madkour-pub-author-test--answering
            (list (cons " tagline: " (lambda () (pop texts))))
          (should (equal (a3madkour-pub-author--ask
                          "works/games" "tagline" '((type . "text") (required . t)))
                         "ok"))))
      (should (cl-some (lambda (m) (string-match-p "backslash cannot be written" m))
                       said)))))

(provide 'a3madkour-publish-author-test)
;;; a3madkour-publish-author-test.el ends here

;; -- drawer-sourced fields (LIBRARY_* file properties) --

(ert-deftest a3madkour-pub-author-test/drawer-property-names ()
  (should (equal (a3madkour-pub-author--drawer-property "media_type") "LIBRARY_MEDIA_TYPE"))
  (should (equal (a3madkour-pub-author--drawer-property "creator") "LIBRARY_CREATOR")))

(ert-deftest a3madkour-pub-author-test/drawer-get-reads-only-a-first-element-drawer ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:ID: x\n:LIBRARY_STATUS: reading\n:LIBRARY_CREATOR:   \n:END:\n#+title: T\n")
    (should (equal (a3madkour-pub-author--drawer-get "status") "reading"))
    (should-not (a3madkour-pub-author--drawer-get "creator"))
    (should-not (a3madkour-pub-author--drawer-get "started")))
  (with-temp-buffer
    (org-mode)
    (insert "#+title: T\n:PROPERTIES:\n:LIBRARY_STATUS: reading\n:END:\n")
    (should-not (a3madkour-pub-author--drawer-get "status"))))

(ert-deftest a3madkour-pub-author-test/drawer-source-satisfied-by-file-property ()
  (a3madkour-pub-author-test--with-site
    (insert ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:LIBRARY_STATUS: reading\n:END:\n#+title: T\n")
    (should (equal (mapcar #'car (a3madkour-pub-author--fields-to-fill "garden"))
                   '("creator")))))

(ert-deftest a3madkour-pub-author-test/drawer-selector-picks-media-case ()
  (a3madkour-pub-author-test--with-site
    (insert ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: game\n:END:\n#+title: T\n"
            "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n")
    (let ((file (make-temp-file "drawer-sel" nil ".org" (buffer-string))))
      (unwind-protect
          (should (equal (a3madkour-pub-author/missing-required file "garden")
                         '("status" "creator")))
        (delete-file file)))
    (let ((status (assoc "status" (a3madkour-pub-author--fields-to-fill "garden"))))
      (should (member "playing" (alist-get 'values (cdr status))))
      (should-not (member "reading" (alist-get 'values (cdr status)))))))

(ert-deftest a3madkour-pub-author-test/drawer-field-written-to-file-drawer ()
  (a3madkour-pub-author-test--with-site
    (insert ":PROPERTIES:\n:LIBRARY_MEDIA_TYPE: book\n:END:\n#+title: T\n")
    (a3madkour-pub-author-test--answering
        '(("garden status" . "reading") ("garden creator" . "Ann Author"))
      (a3-publish-mark "garden"))
    (should (equal (org-entry-get (point-min) "LIBRARY_STATUS") "reading"))
    (should (equal (org-entry-get (point-min) "LIBRARY_CREATOR") "Ann Author"))
    (should-not (string-match-p "HUGO_CUSTOM_FRONT_MATTER:.*\\(status\\|creator\\)"
                                (buffer-string)))))

(ert-deftest a3madkour-pub-author-test/drawer-written-into-existing-ref-drawer ()
  (a3madkour-pub-author-test--with-site
    (insert ":PROPERTIES:\n:ID: r-1\n:ROAM_REFS: https://example.org\n:END:\n#+title: T\n")
    (a3madkour-pub-author--write-field "status" "enum" "reading" "drawer")
    (should (string-prefix-p ":PROPERTIES:\n:ID: r-1\n:ROAM_REFS: https://example.org\n"
                             (buffer-string)))
    (should (equal (org-entry-get (point-min) "ID") "r-1"))
    (should (equal (org-entry-get (point-min) "LIBRARY_STATUS") "reading"))
    ;; A second write replaces in place rather than duplicating.
    (a3madkour-pub-author--write-field "status" "enum" "finished" "drawer")
    (should (equal (org-entry-get (point-min) "LIBRARY_STATUS") "finished"))
    (should (= 1 (how-many "LIBRARY_STATUS" (point-min) (point-max))))))

(ert-deftest a3madkour-pub-author-test/drawer-created-first-when-buffer-starts-with-keywords ()
  (a3madkour-pub-author-test--with-site
    (insert "#+title: T\n#+HUGO_PUBLISH: t\n")
    (a3madkour-pub-author--write-field "creator" "text" "Ann" "drawer")
    (should (string-prefix-p ":PROPERTIES:\n:LIBRARY_CREATOR: Ann\n:END:\n#+title: T\n"
                             (buffer-string)))
    (should (equal (org-entry-get (point-min) "LIBRARY_CREATOR") "Ann"))))
