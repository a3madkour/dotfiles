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

(provide 'a3madkour-publish-research-test)

;;; a3madkour-publish-research-test.el ends here
