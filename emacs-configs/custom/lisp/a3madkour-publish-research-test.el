;;; a3madkour-publish-research-test.el --- tests for research handler  -*- lexical-binding: t; -*-

(require 'ert)
(require 'a3madkour-publish-research)

(ert-deftest a3madkour-pub-research--module-loads ()
  "Smoke: module loadable and exposes publish-research-file."
  (should (fboundp 'a3madkour-pub-research/publish-research-file)))

;;; Task 7 — parse-outputs-table tests

(defun a3madkour-pub-research-test--parse-buffer (org-text)
  "Helper: parse ORG-TEXT and return the full element AST."
  (with-temp-buffer
    (insert org-text)
    (org-mode)
    (org-element-parse-buffer)))

(ert-deftest a3madkour-pub-research--parse-outputs-table-happy ()
  "Well-formed outputs table parses to a plist list, row order preserved."
  (let* ((ast (a3madkour-pub-research-test--parse-buffer "
* Outputs                                                  :outputs:
| kind  | title                | url                          | year |
|-------+----------------------+------------------------------+------|
| paper | Save States as Edits | https://example.com/paper    | 2024 |
| talk  | Save States as Edits | https://example.com/talk     | 2024 |
| code  | save-replay-tool     | https://github.com/example/x | 2024 |
"))
         (outputs (a3madkour-pub-research--parse-outputs-table ast "/tmp/x.org")))
    (should (= 3 (length outputs)))
    (should (equal (plist-get (nth 0 outputs) :kind) "paper"))
    (should (equal (plist-get (nth 0 outputs) :title) "Save States as Edits"))
    (should (equal (plist-get (nth 0 outputs) :url) "https://example.com/paper"))
    (should (equal (plist-get (nth 0 outputs) :year) 2024))
    (should (equal (plist-get (nth 1 outputs) :kind) "talk"))
    (should (equal (plist-get (nth 2 outputs) :kind) "code"))))

(ert-deftest a3madkour-pub-research--parse-outputs-table-no-heading ()
  "No * Outputs heading → nil."
  (let ((ast (a3madkour-pub-research-test--parse-buffer "* Some other heading\nbody.\n")))
    (should-not (a3madkour-pub-research--parse-outputs-table ast "/tmp/x.org"))))

(ert-deftest a3madkour-pub-research--parse-outputs-table-empty-heading ()
  "* Outputs heading with no table → nil + WARN."
  (let* ((ast (a3madkour-pub-research-test--parse-buffer "* Outputs\nNo table.\n"))
         (warnings '())
         (result (cl-letf (((symbol-function 'message)
                            (lambda (fmt &rest args)
                              (push (apply #'format fmt args) warnings))))
                   (a3madkour-pub-research--parse-outputs-table ast "/tmp/x.org"))))
    (should-not result)
    (should (seq-some (lambda (m) (string-match-p "outputs heading.*no table" m)) warnings))))

(ert-deftest a3madkour-pub-research--parse-outputs-table-missing-column ()
  "Header missing required column → WARN + nil."
  (let* ((ast (a3madkour-pub-research-test--parse-buffer "
* Outputs
| kind  | title                | url                          |
|-------+----------------------+------------------------------|
| paper | Save States as Edits | https://example.com/paper    |
"))
         (warnings '())
         (result (cl-letf (((symbol-function 'message)
                            (lambda (fmt &rest args)
                              (push (apply #'format fmt args) warnings))))
                   (a3madkour-pub-research--parse-outputs-table ast "/tmp/x.org"))))
    (should-not result)
    (should (seq-some (lambda (m) (string-match-p "missing.*year" m)) warnings))))

(ert-deftest a3madkour-pub-research--parse-outputs-table-unknown-kind-skipped ()
  "Unknown kind row → WARN + skipped; rest of table parsed."
  (let* ((ast (a3madkour-pub-research-test--parse-buffer "
* Outputs
| kind     | title  | url                  | year |
|----------+--------+----------------------+------|
| paper    | Real   | https://example.com  | 2024 |
| dataset  | Bogus  | https://other.com    | 2025 |
| code     | Tool   | https://gh.com       | 2024 |
"))
         (warnings '())
         (outputs (cl-letf (((symbol-function 'message)
                             (lambda (fmt &rest args)
                               (push (apply #'format fmt args) warnings))))
                    (a3madkour-pub-research--parse-outputs-table ast "/tmp/x.org"))))
    (should (= 2 (length outputs)))
    (should (equal (plist-get (nth 0 outputs) :kind) "paper"))
    (should (equal (plist-get (nth 1 outputs) :kind) "code"))
    (should (seq-some (lambda (m) (string-match-p "kind=dataset.*skip" m)) warnings))))

(ert-deftest a3madkour-pub-research--parse-outputs-table-year-octal-safe ()
  "Year string '08' must coerce to int 8 without octal trap."
  (let* ((ast (a3madkour-pub-research-test--parse-buffer "
* Outputs
| kind  | title  | url                  | year |
|-------+--------+----------------------+------|
| paper | Real   | https://example.com  | 08   |
"))
         (outputs (a3madkour-pub-research--parse-outputs-table ast "/tmp/x.org")))
    (should (equal (plist-get (nth 0 outputs) :year) 8))))

(ert-deftest a3madkour-pub-research--parse-outputs-table-case-insensitive-heading ()
  "* outputs and * OUTPUTS both match (raw-value compared case-insensitively)."
  (dolist (heading '("outputs" "OUTPUTS" "OutPuts"))
    (let* ((ast (a3madkour-pub-research-test--parse-buffer
                 (format "
* %s
| kind  | title  | url                  | year |
|-------+--------+----------------------+------|
| paper | Real   | https://example.com  | 2024 |
" heading)))
           (outputs (a3madkour-pub-research--parse-outputs-table ast "/tmp/x.org")))
      (should (= 1 (length outputs))))))

;;; Task 8 — strip-outputs-subtree tests

(ert-deftest a3madkour-pub-research--strip-outputs-subtree-happy ()
  "Outputs heading + everything until next same-level heading or EOF is removed."
  (let* ((src "* Intro
Body before.

* Outputs                                                  :outputs:
| kind  | title  | url                  | year |
|-------+--------+----------------------+------|
| paper | Foo    | https://example.com  | 2024 |

* After
Body after.
")
         (result (a3madkour-pub-research--strip-outputs-subtree src)))
    (should (string-match-p "Body before" result))
    (should (string-match-p "Body after" result))
    (should-not (string-match-p "^\\* Outputs" result))
    (should-not (string-match-p "kind " result))))

(ert-deftest a3madkour-pub-research--strip-outputs-subtree-trailing ()
  "Outputs subtree at end-of-file: stripped to EOF."
  (let* ((src "* Intro
Body before.

* Outputs
| kind  | title | url                 | year |
|-------+-------+---------------------+------|
| paper | Foo   | https://example.com | 2024 |
")
         (result (a3madkour-pub-research--strip-outputs-subtree src)))
    (should (string-match-p "Body before" result))
    (should-not (string-match-p "^\\* Outputs" result))))

(ert-deftest a3madkour-pub-research--strip-outputs-subtree-no-outputs ()
  "No * Outputs heading → buffer unchanged."
  (let* ((src "* Intro\nBody.\n* Another\nMore.\n")
         (result (a3madkour-pub-research--strip-outputs-subtree src)))
    (should (string= src result))))

(ert-deftest a3madkour-pub-research--strip-outputs-subtree-case-insensitive ()
  "Lowercased * outputs heading also stripped."
  (let* ((src "* Intro\nBody.\n\n* outputs\n| k | t | u | y |\n|---+---+---+---|\n| paper | F | https://x | 2024 |\n")
         (result (a3madkour-pub-research--strip-outputs-subtree src)))
    (should-not (string-match-p "^\\* outputs" result))))

;;; Task 9 — render helpers

(ert-deftest a3madkour-pub-research--render-yaml-value-string ()
  "Strings are quoted; date strings are unquoted."
  (should (string= "\"hello\""
                   (a3madkour-pub-research--render-yaml-value "hello")))
  (should (string= "2026-05-30"
                   (a3madkour-pub-research--render-yaml-value "2026-05-30"))))

(ert-deftest a3madkour-pub-research--render-yaml-value-list ()
  "Lists of strings render as [\"a\", \"b\"]."
  (should (string= "[\"tag1\", \"tag2\"]"
                   (a3madkour-pub-research--render-yaml-value '("tag1" "tag2")))))

(ert-deftest a3madkour-pub-research--render-outputs-yaml-single-row ()
  "Single output row renders as a block sequence item."
  (let ((outputs (list (list :kind "paper" :title "Test Paper"
                             :url "https://example.com" :year 2024))))
    (let ((rendered (a3madkour-pub-research--render-outputs-yaml outputs)))
      (should (string-match-p "kind: paper" rendered))
      (should (string-match-p "title: \"Test Paper\"" rendered))
      (should (string-match-p "url: \"https://example.com\"" rendered))
      (should (string-match-p "year: 2024" rendered)))))

(ert-deftest a3madkour-pub-research--render-frontmatter-no-outputs ()
  "Frontmatter without outputs renders as standard YAML block."
  (let ((rendered (a3madkour-pub-research--render-frontmatter
                   '((title . "My Theme") (status . "active") (weight . 10)))))
    (should (string-prefix-p "---\n" rendered))
    (should (string-match-p "title: \"My Theme\"" rendered))
    (should (string-match-p "status: \"active\"" rendered))
    (should (string-match-p "weight: 10" rendered))
    (should (string-suffix-p "---\n" rendered))))

(ert-deftest a3madkour-pub-research--render-frontmatter-with-outputs ()
  "Frontmatter with outputs renders block-sequence YAML for outputs key."
  (let* ((outputs (list (list :kind "paper" :title "A Paper"
                              :url "https://x.com" :year 2024)))
         (rendered (a3madkour-pub-research--render-frontmatter
                    `((title . "Q") (outputs . ,outputs)))))
    (should (string-match-p "outputs:" rendered))
    (should (string-match-p "  - { kind: paper" rendered))))

(ert-deftest a3madkour-pub-research--section-to-normalize-sym ()
  "Section string to normalize symbol conversion."
  (should (eq 'research-themes
              (a3madkour-pub-research--section-to-normalize-sym "research/themes")))
  (should (eq 'research-questions
              (a3madkour-pub-research--section-to-normalize-sym "research/questions"))))

(ert-deftest a3madkour-pub-research--inject-outputs-non-nil ()
  "inject-outputs sets outputs key when outputs is non-nil."
  (let* ((alist '((title . "T") (status . "active")))
         (outputs (list (list :kind "paper" :title "P" :url "u" :year 2024)))
         (result (a3madkour-pub-research--inject-outputs alist outputs)))
    (should (equal outputs (alist-get 'outputs result)))))

(ert-deftest a3madkour-pub-research--inject-outputs-nil ()
  "inject-outputs removes outputs key when outputs is nil."
  (let* ((alist '((title . "T") (outputs . ((x . 1)))))
         (result (a3madkour-pub-research--inject-outputs alist nil)))
    (should (null (alist-get 'outputs result)))))

;;; Task 9 — end-to-end tests

(ert-deftest a3madkour-pub-research--publish-theme-end-to-end ()
  "publish-research-file emits a theme bundle with the right frontmatter."
  (let* ((notes-dir (make-temp-file "a3-pub-research-notes-" t))
         (site-dir  (make-temp-file "a3-pub-research-site-" t))
         (src (expand-file-name "research-themes-example.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir) t)
          (make-directory (expand-file-name "content/research/themes" site-dir) t)
          (with-temp-file (expand-file-name "data/url-history.yaml" site-dir)
            (insert "notes: []\n"))
          (with-temp-file src
            (insert ":PROPERTIES:\n"
                    ":ID: 11111111-aaaa-bbbb-cccc-dddddddddddd\n"
                    ":LAST_MODIFIED: 2026-05-30\n"
                    ":END:\n"
                    "#+title: Example theme\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: research/themes\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "#+HUGO_DESCRIPTION: A short description.\n"
                    "#+HUGO_CUSTOM_FRONT_MATTER: :status active\n"
                    "#+HUGO_CUSTOM_FRONT_MATTER: :weight 10\n"
                    "#+filetags: :research:test:\n"
                    "\nBody paragraph for the theme.\n"))
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-research/publish-research-file src)
              (a3madkour-pub/finish-publish)))
          (let ((out (expand-file-name
                      "content/research/themes/example-theme/index.md" site-dir)))
            (should (file-exists-p out))
            (with-temp-buffer
              (insert-file-contents out)
              (let ((body (buffer-string)))
                (should (string-match-p "title:" body))
                (should (string-match-p "Example theme" body))
                (should (string-match-p "description:" body))
                (should (string-match-p "A short description" body))
                (should (string-match-p "status:" body))
                (should (string-match-p "active" body))
                (should (string-match-p "Body paragraph for the theme" body))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(ert-deftest a3madkour-pub-research--publish-question-with-outputs-end-to-end ()
  "publish-research-file emits a question bundle with outputs list, body stripped."
  (let* ((notes-dir (make-temp-file "a3-pub-research-notes-" t))
         (site-dir  (make-temp-file "a3-pub-research-site-" t))
         (src (expand-file-name "research-questions-example.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir) t)
          (make-directory (expand-file-name "content/research/questions" site-dir) t)
          (with-temp-file (expand-file-name "data/url-history.yaml" site-dir)
            (insert "notes: []\n"))
          (with-temp-file src
            (insert ":PROPERTIES:\n"
                    ":ID: 22222222-aaaa-bbbb-cccc-dddddddddddd\n"
                    ":LAST_MODIFIED: 2026-05-30\n"
                    ":END:\n"
                    "#+title: Example question\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: research/questions\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "#+HUGO_DESCRIPTION: An active question.\n"
                    "#+HUGO_CUSTOM_FRONT_MATTER: :theme procedural-narrative\n"
                    "#+HUGO_CUSTOM_FRONT_MATTER: :status active\n"
                    "\n* Intro\nBody paragraph for the question.\n\n"
                    "* Outputs\n"
                    "| kind  | title  | url                  | year |\n"
                    "|-------+--------+----------------------+------|\n"
                    "| paper | Test   | https://example.com  | 2024 |\n"))
          (let ((a3madkour-pub/site-data-dir
                 (file-name-as-directory (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore))
              (a3madkour-pub/begin-publish)
              (a3madkour-pub-research/publish-research-file src)
              (a3madkour-pub/finish-publish)))
          (let ((out (expand-file-name
                      "content/research/questions/example-question/index.md" site-dir)))
            (should (file-exists-p out))
            (with-temp-buffer
              (insert-file-contents out)
              (let ((body (buffer-string)))
                (should (string-match-p "title:" body))
                (should (string-match-p "Example question" body))
                (should (string-match-p "description:" body))
                (should (string-match-p "An active question" body))
                (should (string-match-p "outputs:" body))
                (should (string-match-p "kind: paper" body))
                (should (string-match-p "https://example.com" body))
                (should (string-match-p "2024" body))
                (should (string-match-p "Body paragraph for the question" body))
                ;; Outputs heading + table stripped from markdown body.
                (should-not (string-match-p "^## Outputs" body))
                (should-not (string-match-p "| kind " body))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(provide 'a3madkour-publish-research-test)

;;; a3madkour-publish-research-test.el ends here
