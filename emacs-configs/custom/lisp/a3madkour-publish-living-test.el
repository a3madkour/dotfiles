;;; a3madkour-publish-living-test.el --- tests for -living.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the publish-living top-level command.
;;; Code:

(require 'ert)
(require 'a3madkour-publish-living)
(require 'a3madkour-sections-fixture)
;; Loaded so the P4.1 end-to-end idempotency test drives a real living-section handler (the registry names it; this makes it fboundp).
(require 'a3madkour-publish-garden)

(ert-deftest a3madkour-pub-living-test/command-defined-and-interactive ()
  "B.0 — `a3-publish-living' is defined and interactive."
  (should (fboundp 'a3-publish-living))
  (should (commandp 'a3-publish-living)))

(ert-deftest a3madkour-pub-living-test/empty-handler-set-runs-lifecycle-clean ()
  "B.0 — with no per-section handlers registered, running publish-living
walks the (empty) handler set, calls begin/finish, and exits cleanly.
No commits to the manifest; snapshot is cleared at end."
  (let ((tmp-data (make-temp-file "b0-living-" t)))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-data)
              (a3madkour-pub/org-notes-dir tmp-data))
          (with-temp-file (expand-file-name "url-history.yaml" tmp-data)
            (insert "notes: []\n"))
          (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
            (a3-publish-living))
          ;; Snapshot cleared at end of finish-publish.
          (should-not a3madkour-pub--manifest-snapshot)
          ;; Accumulator empty (no record-publish calls happened).
          (should (zerop (hash-table-count a3madkour-pub--publish-run-accumulator))))
      (delete-directory tmp-data t))))

(ert-deftest a3madkour-pub-living-test/garden-handler-registered ()
  "The registry names garden's living handler (slash-form string key)."
  (should (eq (a3madkour-pub-registry/handler "garden" 'living)
              'a3madkour-pub-garden/publish-garden-file)))

(ert-deftest a3madkour-pub-living-test/library-handlers-registered ()
  "All four library sections are living, on `publish-library-file'."
  (dolist (section '("library/reading" "library/listening"
                     "library/playing" "library/watching"))
    (should (eq (a3madkour-pub-registry/handler section 'living)
                'a3madkour-pub-library/publish-library-file))))

(ert-deftest a3madkour-pub-living-test/walk-section-dispatches-on-string-key ()
  "B.1 regression — walk-section compares the section STRING key
directly to `note-section''s STRING value.  Pre-Task-11 used symbol
keys + `symbol-name' bridge which silently no-op'd on slash-form
sections (`library/reading' would intern to `library/reading' which
is not what `note-section' returns).

Post Task 14: the garden handler natively accepts the
`(file run &key on-done)' signature, so no shim is needed."
  (require 'a3madkour-publish-garden)
  (require 'a3madkour-publish-async)
  (let* ((notes-dir (make-temp-file "living-dispatch-" t))
         (site-dir  (make-temp-file "living-dispatch-site-" t))
         (src       (expand-file-name "dispatch-note.org" notes-dir)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "data" site-dir))
          (make-directory (expand-file-name "content/garden" site-dir) t)
          (with-temp-file src
            (insert ":PROPERTIES:\n"
                    ":ID: cccccccc-dddd-eeee-ffff-000000000000\n"
                    ":END:\n"
                    "#+title: Dispatch Note\n"
                    "#+HUGO_PUBLISH: t\n"
                    "#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " site-dir "/\n"
                    "* Body\nDispatch test body.\n"))
          (with-temp-file (expand-file-name "data/url-history.yaml" site-dir)
            (insert "notes: []\n"))
          (let ((a3madkour-pub/site-data-dir (file-name-as-directory
                                              (expand-file-name "data" site-dir)))
                (a3madkour-pub/org-notes-dir notes-dir))
            (cl-letf (((symbol-function 'org-roam-db-sync) (lambda () nil)))
              (let ((a3-pub-async--in-flight-run nil))
                (with-a3-pub-async-sync
                 (a3-publish-living)))))
          (should (file-exists-p
                   (expand-file-name "content/garden/dispatch-note/index.md"
                                     site-dir))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

(ert-deftest a3madkour-pub-living-test/research-handlers-registered ()
  "Both research sections are living, on `publish-research-file'."
  (dolist (section '("research/themes" "research/questions"))
    (should (eq (a3madkour-pub-registry/handler section 'living)
                'a3madkour-pub-research/publish-research-file))))

(require 'a3madkour-publish-async)

(ert-deftest a3madkour-pub-living-test/async-barrier-finishes-once ()
  "Living walks N notes, barrier waits for all on-done before finish-publish."
  (let ((finish-count 0))
    (cl-letf*
        (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil))
         ((symbol-function 'a3madkour-pub/finish-publish)
          (lambda (&rest _) (cl-incf finish-count)))
         ;; Stub the collector to return 3 fake triples.
         ((symbol-function 'a3madkour-pub-living--collect-triples)
          (lambda ()
            (list (list "garden" "/a.org" 'fake-garden-h)
                  (list "garden" "/b.org" 'fake-garden-h)
                  (list "library/reading" "/c.org" 'fake-library-h))))
         ((symbol-function 'fake-garden-h)
          (lambda (_file _run &rest rest)
            (funcall (plist-get rest :on-done) 'ok)))
         ((symbol-function 'fake-library-h)
          (lambda (_file _run &rest rest)
            (funcall (plist-get rest :on-done) 'ok))))
      (let ((a3-pub-async--in-flight-run nil))
        (with-a3-pub-async-sync
         (a3-publish-living))))
    (should (= 1 finish-count))))

(ert-deftest a3madkour-pub-living-test/async-empty-set-finishes-clean ()
  "When no notes match any section, finish-publish still fires once."
  (let ((finish-count 0))
    (cl-letf*
        (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil))
         ((symbol-function 'a3madkour-pub/finish-publish)
          (lambda (&rest _) (cl-incf finish-count)))
         ((symbol-function 'a3madkour-pub-citations/emit-yaml) (lambda (&rest _) nil))
         ((symbol-function 'a3madkour-pub-living--collect-triples) (lambda () nil)))
      (let ((a3-pub-async--in-flight-run nil))
        (with-a3-pub-async-sync
         (a3-publish-living))))
    (should (= 1 finish-count))))

;; -- P4.2: error-aggregation roll-up (living barrier) --

(defmacro a3-pub-living-test--capture-finish-status (status-var &rest body)
  "Run BODY with `a3-pub-async/finish-publish' stubbed to capture its `:status'
keyword into STATUS-VAR (a place set via `setq').  Also stubs begin-publish to a
no-op and neutralizes the in-flight guard, matching the sibling barrier tests."
  (declare (indent 1))
  `(cl-letf* (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil))
              ((symbol-function 'a3-pub-async/finish-publish)
               (lambda (_run &rest kw) (setq ,status-var (plist-get kw :status)))))
     (let ((a3-pub-async--in-flight-run nil))
       (with-a3-pub-async-sync ,@body))))

(ert-deftest a3madkour-pub-living-test/error-aggregation-one-on-done-err-rolls-up ()
  "If any handler reports `err' via its on-done callback, the barrier's status
roll-up resolves to `err' even when the other handlers report `ok' (P4.2).  A
partial-failure living run must NOT finish as `ok' (which would let the sweep
reap off an incomplete accumulator)."
  (let ((captured 'unset))
    (a3-pub-living-test--capture-finish-status captured
      (cl-letf (((symbol-function 'a3madkour-pub-living--collect-triples)
                 (lambda ()
                   (list (list "garden" "/a.org" 'ok-h)
                         (list "garden" "/b.org" 'err-h)
                         (list "garden" "/c.org" 'ok-h))))
                ((symbol-function 'ok-h)
                 (lambda (_f _r &rest rest) (funcall (plist-get rest :on-done) 'ok)))
                ((symbol-function 'err-h)
                 (lambda (_f _r &rest rest) (funcall (plist-get rest :on-done) 'err))))
        (a3-publish-living)))
    (should (eq captured 'err))))

(ert-deftest a3madkour-pub-living-test/error-aggregation-handler-throw-rolls-up ()
  "A handler that SIGNALS (throws before/without calling on-done) is caught by
the dispatch `condition-case', which reports `err' to the barrier — so the run
rolls up to `err', not `ok' (P4.2)."
  (let ((captured 'unset))
    (a3-pub-living-test--capture-finish-status captured
      (cl-letf (((symbol-function 'a3madkour-pub-living--collect-triples)
                 (lambda ()
                   (list (list "garden" "/a.org" 'ok-h)
                         (list "garden" "/b.org" 'throw-h))))
                ((symbol-function 'ok-h)
                 (lambda (_f _r &rest rest) (funcall (plist-get rest :on-done) 'ok)))
                ((symbol-function 'throw-h)
                 (lambda (&rest _) (error "handler blew up"))))
        (a3-publish-living)))
    (should (eq captured 'err))))

(ert-deftest a3madkour-pub-living-test/error-aggregation-all-ok-rolls-up-ok ()
  "Contrast to the err cases: when every handler reports `ok', the roll-up is
`ok' (P4.2)."
  (let ((captured 'unset))
    (a3-pub-living-test--capture-finish-status captured
      (cl-letf (((symbol-function 'a3madkour-pub-living--collect-triples)
                 (lambda ()
                   (list (list "garden" "/a.org" 'ok-h)
                         (list "garden" "/b.org" 'ok-h))))
                ((symbol-function 'ok-h)
                 (lambda (_f _r &rest rest) (funcall (plist-get rest :on-done) 'ok))))
        (a3-publish-living)))
    (should (eq captured 'ok))))

;; -- P4.1: living-publish idempotency contract (spec §11), end-to-end --

(ert-deftest a3madkour-pub-living-test/idempotent-through-orchestrator ()
  "The living-publish idempotency contract (living.el commentary / design §11):
running `a3-publish-living' twice over an unchanged source tree emits a
BYTE-IDENTICAL content bundle.  Drives the real orchestrator (walk → dispatch →
barrier → finish-publish), not a handler in isolation, so it guards the wiring —
including the P2.14 last_modified reuse that keeps the frontmatter from churning
even when the filesystem mtime advances between runs (never-committed note)."
  (let* ((notes-dir (make-temp-file "a3-pub-living-idem-notes-" t))
         (site-dir  (make-temp-file "a3-pub-living-idem-site-" t))
         (data-dir  (file-name-as-directory (expand-file-name "data" site-dir)))
         (src       (expand-file-name "note.org" notes-dir))
         (bundle    (expand-file-name "content/garden/idem-note/index.md" site-dir))
         ;; fs-mtime advances every read → proves the recorded date is reused.
         (fs-dates  '("2026-02-02" "2026-08-08")))
    (unwind-protect
        (progn
          (make-directory data-dir t)
          (make-directory (expand-file-name "content/garden" site-dir) t)
          (with-temp-file (expand-file-name "url-history.yaml" data-dir)
            (insert "notes: []\n"))
          (with-temp-file src
            (insert ":PROPERTIES:\n:ID: dddddddd-eeee-ffff-0000-111111111111\n:END:\n"
                    "#+title: Idem Note\n#+filetags: :alpha:\n"
                    "#+HUGO_PUBLISH: t\n#+HUGO_SECTION: garden\n"
                    "#+HUGO_BASE_DIR: " site-dir "\n"
                    "Body prose.\n"))
          (let ((a3madkour-pub/site-data-dir data-dir)
                (a3madkour-pub/org-notes-dir notes-dir)
                (a3-pub-async--in-flight-run nil))
            (cl-letf (((symbol-function 'org-roam-db-sync) #'ignore)
                      ;; Step C recheck resolves live-note sources via org-roam;
                      ;; point it at our single note so it needs no DB.
                      ((symbol-function 'org-roam-id-find)
                       (lambda (_id &optional _) (cons src 1)))
                      ;; citations flush on ok is out of scope for this test.
                      ((symbol-function 'a3madkour-pub-citations/emit-yaml) #'ignore)
                      ;; never-committed → git-mtime empty; fs-mtime advances.
                      ((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
                       (lambda (_) nil))
                      ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
                       (lambda (_) (or (pop fs-dates) "2027-01-01"))))
              (with-a3-pub-async-sync (a3-publish-living))
              (should (file-exists-p bundle))
              (let ((first (with-temp-buffer
                             (insert-file-contents bundle) (buffer-string))))
                (with-a3-pub-async-sync (a3-publish-living))
                (let ((second (with-temp-buffer
                                (insert-file-contents bundle) (buffer-string))))
                  ;; Whole-file byte equality — no field churns across runs.
                  (should (equal first second))
                  ;; And specifically the first-recorded date survived.
                  (should (string-match-p "last_modified: 2026-02-02" second))
                  (should-not (string-match-p "2026-08-08" second)))))))
      (delete-directory notes-dir t)
      (delete-directory site-dir t))))

;; -- Task 10: walk the notes tree once, not once per registered handler --

(ert-deftest a3madkour-pub-living--collect-walks-tree-once ()
  "With N registered handlers the tree must be walked once, not N times."
  (let* ((dir (make-temp-file "a3-living-walk" t))
         (calls 0))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "a.org" dir)
            (insert "#+TITLE: A\n#+HUGO_SECTION: garden\n#+HUGO_PUBLISH: t\n"))
          (let ((a3madkour-pub/org-notes-dir dir))
            (cl-letf* ((orig (symbol-function 'directory-files-recursively))
                       ((symbol-function 'directory-files-recursively)
                        (lambda (&rest args)
                          (setq calls (1+ calls))
                          (apply orig args))))
              (a3madkour-pub-living--collect-triples))
            (should (equal calls 1))))
      (delete-directory dir t))))

(ert-deftest a3madkour-pub-living--collect-yields-one-triple-per-match ()
  (let* ((dir (make-temp-file "a3-living-walk" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "a.org" dir)
            (insert "#+TITLE: A\n#+HUGO_SECTION: garden\n#+HUGO_PUBLISH: t\n"))
          (let ((a3madkour-pub/org-notes-dir dir))
            (let ((triples (a3madkour-pub-living--collect-triples)))
              (should (equal (length triples) 1))
              (should (equal (car (car triples)) "garden")))))
      (delete-directory dir t))))

;; -- Section registry: dispatch follows the registry, loudly --

(ert-deftest a3madkour-pub-living--collect-follows-registry-modes ()
  "Only `:mode living' sections yield triples; deliberate (essays) and
handler-less (streams) sections are skipped."
  (let ((dir (make-temp-file "a3-living-modes" t)))
    (unwind-protect
        (progn
          (dolist (spec '(("g.org" . "garden") ("e.org" . "essays")
                          ("s.org" . "streams")))
            (with-temp-file (expand-file-name (car spec) dir)
              (insert (format "#+TITLE: %s\n#+HUGO_SECTION: %s\n#+HUGO_PUBLISH: t\n"
                              (car spec) (cdr spec)))))
          (let ((a3madkour-pub/org-notes-dir dir))
            (a3madkour-pub--reset-metadata-cache)
            (let ((triples (a3madkour-pub-living--collect-triples)))
              (should (equal (mapcar #'car triples) '("garden")))
              (should (eq (nth 2 (car triples))
                          'a3madkour-pub-garden/publish-garden-file)))))
      (delete-directory dir t))))

(ert-deftest a3madkour-pub-living-test/unloaded-handler-is-a-loud-per-file-error ()
  "A registered handler that is not `fboundp' reports `err' for its file
and logs a `handler-missing' step naming the function; the other files
still run.  Intended behaviour change: before the registry the section
was silently skipped, so its pages looked removed (S1 row 9)."
  (let ((captured 'unset) (logged nil) (other-ran nil))
    (a3-pub-living-test--capture-finish-status captured
      (cl-letf (((symbol-function 'a3madkour-pub-living--collect-triples)
                 (lambda ()
                   (list (list "garden" "/a.org" 'a3madkour-pub-living-test--no-such-handler)
                         (list "garden" "/b.org" 'ok-h))))
                ((symbol-function 'ok-h)
                 (lambda (_f _r &rest rest)
                   (setq other-ran t)
                   (funcall (plist-get rest :on-done) 'ok)))
                ((symbol-function 'a3-pub-async/log-step)
                 (lambda (_run label status &rest kw)
                   (push (list label status (plist-get kw :err-snippet)) logged))))
        (a3-publish-living)))
    (should (eq captured 'err))
    (should other-ran)
    (should (cl-some (lambda (l)
                       (and (equal (nth 0 l) "handler-missing")
                            (eq (nth 1 l) :err)
                            (string-match-p "a3madkour-pub-living-test--no-such-handler"
                                            (nth 2 l))))
                     logged))))

(defun a3-pub-living-test--theme (dir filetags)
  "Write a research theme note under DIR tagged FILETAGS; return its path.
Every required authored field is present, so only the tags can be missing."
  (let ((f (expand-file-name "theme.org" dir)))
    (with-temp-file f
      (insert ":PROPERTIES:\n:ID: 3e650e6f-0000-0000-0000-000000000000\n:END:\n"
              "#+title: A Theme\n"
              "#+HUGO_SECTION: research/themes\n"
              "#+HUGO_PUBLISH: t\n"
              "#+HUGO_DESCRIPTION: one line\n"
              "#+HUGO_CUSTOM_FRONT_MATTER: :status \"active\"\n"
              "#+HUGO_CUSTOM_FRONT_MATTER: :weight 10\n"
              "#+filetags: " filetags "\n"))
    f))

(defmacro a3-pub-living-test--gate (filetags &rest body)
  "Run `a3-publish-living' over one theme note tagged FILETAGS.
Binds `ran' (the handler was called), `logged' ((LABEL STATUS SNIPPET) ...)
and `captured' (the finish status) for BODY."
  (declare (indent 1))
  `(let ((dir (make-temp-file "living-gate-" t))
         (captured 'unset) (logged nil) (ran nil))
     (unwind-protect
         (let ((file (a3-pub-living-test--theme dir ,filetags)))
           (a3-pub-living-test--capture-finish-status captured
             (cl-letf (((symbol-function 'a3madkour-pub-living--collect-triples)
                        (lambda () (list (list "research/themes" file 'ok-h))))
                       ((symbol-function 'ok-h)
                        (lambda (_f _r &rest rest)
                          (setq ran t)
                          (funcall (plist-get rest :on-done) 'ok)))
                       ((symbol-function 'a3-pub-async/log-step)
                        (lambda (_run label status &rest kw)
                          (push (list label status (plist-get kw :err-snippet))
                                logged))))
               (a3-publish-living)))
           ,@body)
       (delete-directory dir t))))

(ert-deftest a3madkour-pub-living-test/note-missing-required-field-is-not-published ()
  "A note whose contract lacks a required field mark would ask for is not
handed to its handler: the file reports `err', and a `contract' step names
the field and `a3-publish-mark'.  S1 row 24: a theme tagged only `:TODO:'
was published without `tags', and only CI's fixture linter noticed."
  (a3-pub-living-test--gate ":TODO:"
    (should-not ran)
    (should (eq captured 'err))
    (should (cl-some (lambda (l)
                       (and (equal (nth 0 l) "contract")
                            (eq (nth 1 l) :err)
                            (string-match-p "\\btags\\b" (nth 2 l))
                            (string-match-p "a3-publish-mark" (nth 2 l))))
                     logged))))

(ert-deftest a3madkour-pub-living-test/note-meeting-contract-is-published ()
  "Contrast: the same theme with a real tag reaches its handler, and the
run finishes `ok'."
  (a3-pub-living-test--gate ":TODO:pcg:"
    (should ran)
    (should (eq captured 'ok))
    (should-not (assoc "contract" logged))))

(provide 'a3madkour-publish-living-test)
;;; a3madkour-publish-living-test.el ends here
