;;; a3madkour-publish-library-notes-test.el --- tests for -library-notes.el  -*- lexical-binding: t; -*-
;;; Commentary:
;;; ert tests for the library collector: shelves built from shared item notes.
;;; Code:

(require 'ert)
(require 'a3madkour-sections-fixture)
(require 'a3madkour-publish-library-notes)

(defvar a3madkour-pub-library-notes-test--site nil
  "The temp site root of the running `--with-site' body.")

(defmacro a3madkour-pub-library-notes-test--with-site (&rest body)
  "Run BODY against a temp site (data/ + content/garden/) and notes dir.
Binds `a3madkour-pub/site-data-dir' and `a3madkour-pub/org-notes-dir',
resets the metadata cache, and stubs git/fs mtimes to a fixed date."
  (declare (indent 0))
  `(let* ((site (make-temp-file "lib-notes-site-" t))
          (notes (make-temp-file "lib-notes-notes-" t))
          (a3madkour-pub-library-notes-test--site site)
          (a3madkour-pub/site-data-dir
           (file-name-as-directory (expand-file-name "data" site)))
          (a3madkour-pub/org-notes-dir notes))
     (unwind-protect
         (progn
           (make-directory a3madkour-pub/site-data-dir t)
           (make-directory (expand-file-name "content/garden" site) t)
           (with-temp-file (expand-file-name "url-history.yaml"
                                             a3madkour-pub/site-data-dir)
             (insert "notes: []\n"))
           (a3madkour-pub--reset-metadata-cache)
           (cl-letf (((symbol-function 'a3madkour-pub-history/git-mtime-of-file)
                      (lambda (_) nil))
                     ((symbol-function 'a3madkour-pub-history/filesystem-mtime-of-file)
                      (lambda (_) "2026-01-02")))
             ,@body))
       (delete-directory site t)
       (delete-directory notes t))))

(cl-defun a3madkour-pub-library-notes-test--note
    (name &key (media "book") (status "reading") (title name) refs
          (bundle t) (publish t) extra-drawer
          (creator "Example Author") (year "2001") (started "2026-01-01") finished)
  "Write an item note NAME.org; return its path.
With BUNDLE, also write its garden bundle `content/garden/<slug>/index.md'."
  (let ((file (expand-file-name (concat name ".org") a3madkour-pub/org-notes-dir)))
    (with-temp-file file
      (insert ":PROPERTIES:\n:ID: " (md5 name) "\n"
              ":LIBRARY_MEDIA_TYPE: " media "\n"
              (if status (concat ":LIBRARY_STATUS: " status "\n") "")
              (if creator (concat ":LIBRARY_CREATOR: " creator "\n") "")
              (if year (concat ":LIBRARY_YEAR: " year "\n") "")
              (if started (concat ":LIBRARY_STARTED: " started "\n") "")
              (if finished (concat ":LIBRARY_FINISHED: " finished "\n") "")
              (or extra-drawer "")
              (if refs (concat ":ROAM_REFS: " refs "\n") "")
              ":END:\n"
              "#+title: " title "\n"
              "#+filetags: :Ref:PcgTheory:\n"
              "#+HUGO_SECTION: garden\n"
              (if publish "#+HUGO_PUBLISH: t\n" "")
              "\n* Private\nSECRET\n\n* Notes :site:\nLorem ipsum dolor. Sit amet.\n"))
    (when bundle
      (let ((dir (expand-file-name
                  (format "content/garden/%s/" (a3madkour-pub/note-slug file))
                  a3madkour-pub-library-notes-test--site)))
        (make-directory dir t)
        (with-temp-file (expand-file-name "index.md" dir) (insert "---\n---\n"))))
    file))

(defun a3madkour-pub-library-notes-test--shelf (name)
  "Contents of the temp site's data/NAME."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name a3madkour-pub/site-data-dir))
    (buffer-string)))

(ert-deftest a3madkour-pub-library-notes-test/collector/row-shape ()
  (a3madkour-pub-library-notes-test--with-site
    (let ((f (a3madkour-pub-library-notes-test--note
              "example-book-one" :title "Example Book One"
              :extra-drawer ":LIBRARY_PROGRESS_PCT: 40\n")))
      (should (equal (a3madkour-pub-library-notes/row f)
                     '(:slug "example-book-one" :note_slug "example-book-one"
                       :title "Example Book One" :creator "Example Author"
                       :year 2001 :media_type "book" :status "reading"
                       :started "2026-01-01" :last_modified "2026-01-02"
                       :preview "Lorem ipsum dolor."
                       :tags ("pcg-theory")
                       :extras (:progress_pct 40)))))))

(ert-deftest a3madkour-pub-library-notes-test/collector/last-modified-prefers-history ()
  "The date Task 5's garden publish recorded wins over the cascade."
  (a3madkour-pub-library-notes-test--with-site
    (let ((f (a3madkour-pub-library-notes-test--note "example-book-one")))
      (cl-letf (((symbol-function 'a3madkour-pub-history/recorded-last-modified)
                 (lambda (id url)
                   (and (equal id (md5 "example-book-one"))
                        (equal url "/garden/example-book-one/")
                        "2025-05-05"))))
        (should (equal (plist-get (a3madkour-pub-library-notes/row f)
                                  :last_modified)
                       "2025-05-05"))))))

(ert-deftest a3madkour-pub-library-notes-test/collector/skips-note-without-bundle ()
  (a3madkour-pub-library-notes-test--with-site
    (let ((f (a3madkour-pub-library-notes-test--note "example-book-one" :bundle nil)))
      (should-not (a3madkour-pub-library-notes/row f))
      (a3madkour-pub-library-notes/build-shelves (list f))
      (should-not (string-match-p "example-book-one"
                                  (a3madkour-pub-library-notes-test--shelf
                                   "reading.yaml"))))))

(ert-deftest a3madkour-pub-library-notes-test/collector/rows-span-many-notes ()
  "Two book notes land in one reading.yaml, ordered by slug; other shelves
are written empty."
  (a3madkour-pub-library-notes-test--with-site
    (let* ((b (a3madkour-pub-library-notes-test--note "example-book-two"))
           (a (a3madkour-pub-library-notes-test--note "example-book-one"))
           (written (a3madkour-pub-library-notes/build-shelves (list b a)))
           (yaml (a3madkour-pub-library-notes-test--shelf "reading.yaml")))
      (should (= 4 (length written)))
      (should (string-prefix-p
               "# Generated by a3madkour-publish-library-notes from shared item notes.\n# Manual edits will be overwritten on next publish-living run.\nitems:\n  - slug: example-book-one\n"
               yaml))
      (should (< (string-match "slug: example-book-one" yaml)
                 (string-match "slug: example-book-two" yaml)))
      (should (string-suffix-p "items: []\n"
                               (a3madkour-pub-library-notes-test--shelf
                                "playing.yaml"))))))

(ert-deftest a3madkour-pub-library-notes-test/collector/routes-by-media-type ()
  "A game note goes to playing.yaml.  Typed by the REAL site contract: the
fixture contract's playing shelf carries no `started'."
  (a3madkour-pub-library-notes-test--with-site
    (let ((a3madkour-sections--cache nil)
          (a3madkour-sections-file
           (expand-file-name "data/sections.json"
                             (a3madkour-sections-test--real-site-root)))
          (g (a3madkour-pub-library-notes-test--note
              "example-game-one" :media "game" :status "playing")))
      (a3madkour-pub-library-notes/build-shelves (list g))
      (should (string-match-p "slug: example-game-one"
                              (a3madkour-pub-library-notes-test--shelf "playing.yaml")))
      (should (string-suffix-p "items: []\n"
                               (a3madkour-pub-library-notes-test--shelf "reading.yaml"))))))

(ert-deftest a3madkour-pub-library-notes-test/collector/last-item-unshared-empties-shelf ()
  (a3madkour-pub-library-notes-test--with-site
    (let ((f (a3madkour-pub-library-notes-test--note "example-book-one")))
      (a3madkour-pub-library-notes/build-shelves (list f))
      (should (string-match-p "slug: example-book-one"
                              (a3madkour-pub-library-notes-test--shelf "reading.yaml")))
      (a3madkour-pub-library-notes/build-shelves nil)
      (should (string-suffix-p "\nitems: []\n"
                               (a3madkour-pub-library-notes-test--shelf "reading.yaml"))))))

(ert-deftest a3madkour-pub-library-notes-test/collector/idempotent ()
  (a3madkour-pub-library-notes-test--with-site
    (let* ((f (a3madkour-pub-library-notes-test--note "example-book-one"))
           (paths (a3madkour-pub-library-notes/build-shelves (list f))))
      ;; Backdate every shelf so a rewrite would be visible in its mtime.
      (dolist (p paths) (set-file-times p '(0 0)))
      (let ((before (mapcar (lambda (p) (file-attribute-modification-time
                                         (file-attributes p)))
                            paths)))
        (a3madkour-pub-library-notes/build-shelves (list f))
        (should (equal before
                       (mapcar (lambda (p) (file-attribute-modification-time
                                            (file-attributes p)))
                               paths)))))))

(ert-deftest a3madkour-pub-library-notes-test/collector/cite-key-only-when-known ()
  (a3madkour-pub-library-notes-test--with-site
    (with-temp-file (expand-file-name "citations.yaml" a3madkour-pub/site-data-dir)
      (insert "citations:\n  example-source-1:\n    year: 2020\n"))
    (let ((known (a3madkour-pub-library-notes-test--note
                  "example-book-one" :refs "@example-source-1 @example-source-9"))
          (unknown (a3madkour-pub-library-notes-test--note
                    "example-book-two" :refs "@example-source-9"))
          (url (a3madkour-pub-library-notes-test--note
                "example-book-three" :refs "https://example.invalid/@example-source-1")))
      (should (equal (plist-get (a3madkour-pub-library-notes/row known) :cite_key)
                     "example-source-1"))
      (should-not (plist-member (a3madkour-pub-library-notes/row unknown) :cite_key))
      (should-not (plist-member (a3madkour-pub-library-notes/row url) :cite_key)))))

(ert-deftest a3madkour-pub-library-notes-test/collector/preview-omitted-when-nil ()
  (a3madkour-pub-library-notes-test--with-site
    (let ((f (a3madkour-pub-library-notes-test--note "example-book-one")))
      (cl-letf (((symbol-function 'a3madkour-library/preview) (lambda (_) nil)))
        (should-not (plist-member (a3madkour-pub-library-notes/row f) :preview))))))

;; -- The shelf contract: a row the site would reject is never written --

(defmacro a3madkour-pub-library-notes-test--rejects (problem &rest note-args)
  "Assert the note made from NOTE-ARGS gets no row, warning PROBLEM (a regexp)."
  `(a3madkour-pub-library-notes-test--with-site
     (let* ((f (a3madkour-pub-library-notes-test--note "example-book-one" ,@note-args))
            (warned nil))
       (cl-letf* ((orig (symbol-function 'a3madkour-pub/warn))
                  ((symbol-function 'a3madkour-pub/warn)
                   (lambda (module file fmt &rest args)
                     (push (apply #'format fmt args) warned)
                     (apply orig module file fmt args))))
         (should-not (a3madkour-pub-library-notes/row f)))
       (should (cl-some (lambda (w) (string-match-p ,problem w)) warned)))))

(ert-deftest a3madkour-pub-library-notes-test/contract/missing-status ()
  (a3madkour-pub-library-notes-test--rejects
   "missing required LIBRARY_STATUS" :status nil))

(ert-deftest a3madkour-pub-library-notes-test/contract/status-not-on-shelf ()
  (a3madkour-pub-library-notes-test--rejects
   "LIBRARY_STATUS \"playing\" is not one of" :status "playing")
  (a3madkour-pub-library-notes-test--rejects
   "LIBRARY_STATUS \"redaing\" is not one of" :status "redaing"))

(ert-deftest a3madkour-pub-library-notes-test/contract/missing-creator ()
  (a3madkour-pub-library-notes-test--rejects
   "missing required LIBRARY_CREATOR" :creator nil))

(ert-deftest a3madkour-pub-library-notes-test/contract/missing-year ()
  (a3madkour-pub-library-notes-test--rejects
   "missing required LIBRARY_YEAR" :year nil))

(ert-deftest a3madkour-pub-library-notes-test/contract/non-numeric-year ()
  (a3madkour-pub-library-notes-test--rejects
   "LIBRARY_YEAR \"c. 2001\" is not a number" :year "c. 2001"))

(ert-deftest a3madkour-pub-library-notes-test/contract/finished-needs-date ()
  (a3madkour-pub-library-notes-test--rejects
   "status finished needs LIBRARY_FINISHED" :status "finished"))

(ert-deftest a3madkour-pub-library-notes-test/contract/finished-with-date-is-valid ()
  (a3madkour-pub-library-notes-test--with-site
    (let ((f (a3madkour-pub-library-notes-test--note
              "example-book-one" :status "finished" :finished "2026-02-03")))
      (should (equal (plist-get (a3madkour-pub-library-notes/row f) :finished)
                     "2026-02-03")))))

(ert-deftest a3madkour-pub-library-notes-test/contract/date-shape ()
  (a3madkour-pub-library-notes-test--rejects
   "LIBRARY_STARTED \"2026-1-1\" is not YYYY-MM-DD" :started "2026-1-1")
  (a3madkour-pub-library-notes-test--rejects
   "LIBRARY_FINISHED \"2026-02-03T10:00\" is not YYYY-MM-DD"
   :status "finished" :finished "2026-02-03T10:00"))

(ert-deftest a3madkour-pub-library-notes-test/contract/every-problem-named ()
  "One warning names every problem of the note."
  (a3madkour-pub-library-notes-test--rejects
   "missing required LIBRARY_CREATOR.*missing required LIBRARY_YEAR"
   :creator nil :year nil))

(ert-deftest a3madkour-pub-library-notes-test/contract/valid-row-written-beside-invalid ()
  "An invalid note is left off its shelf and the collector signals, but
only after writing the shelves from the valid rows."
  (a3madkour-pub-library-notes-test--with-site
    (let ((good (a3madkour-pub-library-notes-test--note "example-book-one"))
          (bad (a3madkour-pub-library-notes-test--note
                "example-book-two" :status nil)))
      (let ((err (should-error
                  (a3madkour-pub-library-notes/build-shelves (list good bad)))))
        (should (string-match-p (regexp-quote bad) (error-message-string err)))
        (should (string-match-p "missing required LIBRARY_STATUS"
                                (error-message-string err))))
      (let ((yaml (a3madkour-pub-library-notes-test--shelf "reading.yaml")))
        (should (string-match-p "slug: example-book-one" yaml))
        (should-not (string-match-p "example-book-two" yaml)))
      (should (file-exists-p (expand-file-name "watching.yaml"
                                               a3madkour-pub/site-data-dir))))))

(provide 'a3madkour-publish-library-notes-test)
;;; a3madkour-publish-library-notes-test.el ends here
