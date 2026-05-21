;;; a3madkour-publish-history-test.el --- Tests for URL-history manifest -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'a3madkour-publish-history)

(defun a3madkour-pub-history-test--with-tmp-data-dir (thunk)
  "Create a tmp dir; let-bind `a3madkour-pub/site-data-dir' to it; call THUNK."
  (let ((tmp-dir (file-name-as-directory (make-temp-file "a3-pub-data-" t))))
    (unwind-protect
        (let ((a3madkour-pub/site-data-dir tmp-dir))
          (funcall thunk tmp-dir))
      (delete-directory tmp-dir t))))

(ert-deftest a3madkour-pub-history-test/site-data-dir-required ()
  "Manifest path requires `a3madkour-pub/site-data-dir' to be set."
  (let ((a3madkour-pub/site-data-dir nil))
    (should-error (a3madkour-pub-history--manifest-path) :type 'user-error)))

(ert-deftest a3madkour-pub-history-test/manifest-path-resolves ()
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (tmp-dir)
     (should (equal (expand-file-name "url-history.yaml" tmp-dir)
                    (a3madkour-pub-history--manifest-path))))))

(ert-deftest a3madkour-pub-history-test/read-empty-manifest ()
  "Reading a missing-or-empty manifest returns the empty shape `((notes . []))'."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (let ((m (a3madkour-pub-history/read-manifest)))
       (should (vectorp (alist-get 'notes m)))
       (should (= 0 (length (alist-get 'notes m))))))))

(ert-deftest a3madkour-pub-history-test/write-then-read-round-trip ()
  "Round-trip: write a manifest with one note → read back → matches."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (let ((manifest
            '((notes . [((id . "abc-123")
                         (current_url . "/garden/foo/")
                         (history . [])
                         (state . "live"))]))))
       (a3madkour-pub-history/write-manifest manifest)
       (let* ((readback (a3madkour-pub-history/read-manifest))
              (notes (alist-get 'notes readback))
              (note (aref notes 0)))
         (should (= 1 (length notes)))
         (should (equal "abc-123" (alist-get 'id note)))
         (should (equal "/garden/foo/" (alist-get 'current_url note)))
         (should (equal "live" (alist-get 'state note))))))))

(ert-deftest a3madkour-pub-history-test/read-returns-empty-when-file-missing ()
  "If url-history.yaml doesn't exist yet, read returns the empty shape — no error."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (tmp-dir)
     (should-not (file-exists-p (expand-file-name "url-history.yaml" tmp-dir)))
     (let ((m (a3madkour-pub-history/read-manifest)))
       (should (= 0 (length (alist-get 'notes m))))))))

(ert-deftest a3madkour-pub-history-test/record-new-note ()
  "Recording a publish for a not-yet-seen ID creates an entry with empty history."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (let* ((m (a3madkour-pub-history/read-manifest))
            (notes (alist-get 'notes m))
            (note (aref notes 0)))
       (should (= 1 (length notes)))
       (should (equal "abc-123" (alist-get 'id note)))
       (should (equal "/garden/foo/" (alist-get 'current_url note)))
       (should (equal "live" (alist-get 'state note)))
       (let ((hist (alist-get 'history note)))
         (should (or (null hist) (= 0 (length hist)))))))))

(ert-deftest a3madkour-pub-history-test/record-url-change-appends-history ()
  "Recording with a different URL appends the prior URL to history."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo-renamed/" 'live)
     (let* ((m (a3madkour-pub-history/read-manifest))
            (note (aref (alist-get 'notes m) 0))
            (hist (alist-get 'history note)))
       (should (equal "/garden/foo-renamed/" (alist-get 'current_url note)))
       (should (= 1 (length hist)))
       (let ((entry (aref hist 0)))
         (should (equal "/garden/foo/" (alist-get 'url entry)))
         (should (stringp (alist-get 'replaced_at entry)))
         (should (member (alist-get 'reason entry)
                         '("title_change" "slug_override" "section_change"))))))))

(ert-deftest a3madkour-pub-history-test/record-no-change-no-op ()
  "Recording the same URL/state twice does not append history."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (let* ((note (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
            (hist (alist-get 'history note)))
       (should (or (null hist) (= 0 (length hist))))))))

(ert-deftest a3madkour-pub-history-test/record-section-change ()
  "Section change → reason='section_change'."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/essays/foo/" 'live)
     (let* ((note (aref (alist-get 'notes (a3madkour-pub-history/read-manifest)) 0))
            (entry (aref (alist-get 'history note) 0)))
       (should (equal "section_change" (alist-get 'reason entry)))))))

(ert-deftest a3madkour-pub-history-test/aliases-for-empty ()
  "New note → no aliases."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (should (null (a3madkour-pub-history/aliases-for "abc-123"))))))

(ert-deftest a3madkour-pub-history-test/aliases-for-after-rename ()
  "After a URL change → the prior URL is in aliases-for."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo/" 'live)
     (a3madkour-pub-history/record-publish "abc-123" "/garden/foo-v2/" 'live)
     (should (equal '("/garden/foo/")
                    (a3madkour-pub-history/aliases-for "abc-123"))))))

(ert-deftest a3madkour-pub-history-test/aliases-for-unknown-id ()
  "Unknown ID returns nil, not an error."
  (a3madkour-pub-history-test--with-tmp-data-dir
   (lambda (_)
     (should (null (a3madkour-pub-history/aliases-for "no-such-id"))))))

(provide 'a3madkour-publish-history-test)

;;; a3madkour-publish-history-test.el ends here
