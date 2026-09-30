;;; a3madkour-works-lint-test.el --- tests for works pre-publish lint  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-works-lint)

(defmacro a3madkour-works-lint-test--with-vocab (json &rest body)
  "Run BODY with a temp site root whose data/works-vocab.json holds JSON.
When JSON is nil, no vocabulary file is written."
  (declare (indent 1))
  `(let* ((a3madkour-works-lint--vocab-cache nil)
          (root (make-temp-file "a3-works-vocab" t)))
     (unwind-protect
         (progn
           (when ,json
             (make-directory (expand-file-name "data" root) t)
             (with-temp-file (expand-file-name "data/works-vocab.json" root)
               (insert ,json)))
           (cl-letf (((symbol-function 'a3madkour-pub-yaml/site-root)
                      (lambda () root)))
             ,@body))
       (delete-directory root t))))

(ert-deftest a3madkour-works-lint--vocab-reads-file ()
  (a3madkour-works-lint-test--with-vocab
      "{\"game_statuses\":[\"playable\"],\"game_kinds\":[\"jam\"],\"music_formats\":[\"album\"],\"platform_kinds\":[\"bandcamp\"]}"
    (should (equal (a3madkour-works-lint/vocab "game_statuses") '("playable")))
    (should (equal (a3madkour-works-lint/vocab "game_kinds") '("jam")))))

(ert-deftest a3madkour-works-lint--vocab-fails-closed-when-missing ()
  (a3madkour-works-lint-test--with-vocab nil
    (should-error (a3madkour-works-lint/vocab "game_statuses"))))

(ert-deftest a3madkour-works-lint--vocab-fails-closed-when-malformed ()
  (a3madkour-works-lint-test--with-vocab "{ not json"
    (should-error (a3madkour-works-lint/vocab "game_statuses"))))

(ert-deftest a3madkour-works-lint--vocab-fails-closed-on-missing-key ()
  (a3madkour-works-lint-test--with-vocab "{\"game_statuses\":[\"playable\"]}"
    (should-error (a3madkour-works-lint/vocab "game_kinds"))))

(ert-deftest a3madkour-works-lint--vocab-fails-closed-on-unknown-key ()
  (a3madkour-works-lint-test--with-vocab
      "{\"game_statuses\":[\"playable\"],\"game_kinds\":[\"jam\"],\"music_formats\":[\"album\"],\"platform_kinds\":[\"bandcamp\"]}"
    (should-error (a3madkour-works-lint/vocab "not_a_real_key"))))

(provide 'a3madkour-works-lint-test)
;;; a3madkour-works-lint-test.el ends here
