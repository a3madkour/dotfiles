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

;;; lint-file rule tests

(defun a3madkour-works-lint-test--file (text)
  "Write TEXT to a temp .org file and return its path."
  (let ((f (make-temp-file "a3-works-lint" nil ".org")))
    (with-temp-file f (insert text)) f))

(defconst a3madkour-works-lint-test--vocab
  "{\"game_statuses\":[\"playable\",\"in-progress\",\"archived\"],
    \"game_kinds\":[\"full-release\",\"jam\",\"research-prototype\",\"experiment\"],
    \"music_formats\":[\"album\",\"track\",\"experiment\",\"live\"],
    \"platform_kinds\":[\"bandcamp\",\"soundcloud\",\"youtube\"]}")

(ert-deftest a3madkour-works-lint--rejects-unknown-status ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--file "#+TITLE: G
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playible :game_kind jam :year 2026 :tagline T
")))
      (unwind-protect
          (let ((errs (a3madkour-works-lint/lint-file f)))
            (should (cl-some (lambda (e) (string-match-p "status" e)) errs)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--rejects-missing-required-key ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--file "#+TITLE: G
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :year 2026 :tagline T
")))
      (unwind-protect
          (let ((errs (a3madkour-works-lint/lint-file f)))
            (should (cl-some (lambda (e) (string-match-p "game_kind" e)) errs)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--rejects-filename-in-music-hero ()
  "hero is a bool for music and a filename for games."
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--file "#+TITLE: M
#+HUGO_SECTION: works/music
#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026 :hero cover.png
")))
      (unwind-protect
          (let ((errs (a3madkour-works-lint/lint-file f)))
            (should (cl-some (lambda (e) (string-match-p "hero" e)) errs)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--rejects-bool-in-games-hero ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--file "#+TITLE: G
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam :year 2026 :tagline T :hero t
")))
      (unwind-protect
          (let ((errs (a3madkour-works-lint/lint-file f)))
            (should (cl-some (lambda (e) (string-match-p "hero" e)) errs)))
        (delete-file f)))))

;; Review Focus #2 — a space inside a screenshot filename silently becomes
;; two broken names under whitespace splitting.
(ert-deftest a3madkour-works-lint--rejects-space-in-asset-filename ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--file "#+TITLE: G
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam :year 2026 :tagline T
#+HUGO_CUSTOM_FRONT_MATTER: :screenshots \"my shot.png\"
")))
      (unwind-protect
          (let ((errs (a3madkour-works-lint/lint-file f)))
            (should (cl-some (lambda (e) (string-match-p "space" e)) errs)))
        (delete-file f)))))

;; Supplementary — the six brief tests never exercise the on-disk
;; asset-existence check directly (the space test only trips it as a
;; side effect on both halves of the split). The handler drops a
;; broken asset key silently, so this rule is the only place an author
;; ever hears about a missing file; pin it directly in both directions.
(ert-deftest a3madkour-works-lint--rejects-missing-asset-file ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let* ((slug (make-temp-name "a3wl"))
           (f (a3madkour-works-lint-test--file (format "#+TITLE: G
#+ID: %s
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam :year 2026 :tagline T :hero cover.png
" slug))))
      (unwind-protect
          (let ((errs (a3madkour-works-lint/lint-file f)))
            (should (cl-some (lambda (e) (string-match-p "not found" e)) errs)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--accepts-existing-asset-file ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let* ((slug (make-temp-name "a3wl"))
           (f (a3madkour-works-lint-test--file (format "#+TITLE: G
#+ID: %s
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam :year 2026 :tagline T :hero cover.png
" slug)))
           (asset-dir (expand-file-name (format "assets/%s/" slug)
                                        (file-name-directory f))))
      (unwind-protect
          (progn
            (make-directory asset-dir t)
            (with-temp-file (expand-file-name "cover.png" asset-dir) (insert "x"))
            (should (null (a3madkour-works-lint/lint-file f))))
        (delete-directory (expand-file-name (format "assets/%s" slug)
                                            (file-name-directory f))
                           t)
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--clean-file-has-no-errors ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--file "#+TITLE: G
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam :year 2026 :tagline T
")))
      (unwind-protect
          (should (null (a3madkour-works-lint/lint-file f)))
        (delete-file f)))))

(provide 'a3madkour-works-lint-test)
;;; a3madkour-works-lint-test.el ends here
