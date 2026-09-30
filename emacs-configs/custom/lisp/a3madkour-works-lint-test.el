;;; a3madkour-works-lint-test.el --- tests for works pre-publish lint  -*- lexical-binding: t; -*-
(require 'ert)
(require 'a3madkour-works-lint)
;; `a3madkour-works-vocab-test--json' — the one vocabulary fixture, shared so
;; the works test files do not each carry their own literal copy.
(require 'a3madkour-works-vocab-fixture)

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
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (should (member "playable" (a3madkour-works-lint/vocab "game_statuses")))
    (should (member "jam" (a3madkour-works-lint/vocab "game_kinds")))))

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
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (should-error (a3madkour-works-lint/vocab "not_a_real_key"))))

;;; lint-file rule tests

(defun a3madkour-works-lint-test--file (text)
  "Write TEXT to a temp .org file and return its path."
  (let ((f (make-temp-file "a3-works-lint" nil ".org")))
    (with-temp-file f (insert text)) f))

(defvaralias 'a3madkour-works-lint-test--vocab
  'a3madkour-works-vocab-test--json
  "The shared vocabulary fixture, which now also carries the emitted-field
sets the frontmatter normalizer reads.  Aliased rather than re-written here:
a second literal would be a second thing to keep in step.")

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

;; Defect 1 (task-12 E2E): these asset-existence fixtures used to author the
;; note ID as a `#+ID:' KEYWORD, which is not a convention this codebase uses
;; anywhere.  The lint read that keyword, so the tests certified a reader that
;; false-failed every real (drawer-authored) file.  All ID-bearing fixtures
;; below now author the file-level `:PROPERTIES: :ID: ... :END:' drawer, the
;; form the design spec and every handler actually use.

;; Fix round 1: `rejects-bool-in-games-hero' above passes even with rule 3's
;; games branch disabled, because rule 4 independently emits a "hero entry
;; ... not found" message for the same non-existent asset "t" — both
;; messages contain the bare word "hero". Isolate rule 3 by making a real
;; file literally named "t" on disk (so rule 4 stays silent) and assert on
;; rule 3's distinct substring instead of the shared word.
(ert-deftest a3madkour-works-lint--rejects-bool-in-games-hero-isolated ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let* ((slug (make-temp-name "a3wl"))
           (f (a3madkour-works-lint-test--file (format ":PROPERTIES:
:ID:       %s
:END:
#+TITLE: G
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam :year 2026 :tagline T :hero t
" slug)))
           (asset-dir (expand-file-name (format "assets/%s/" slug)
                                        (file-name-directory f))))
      (unwind-protect
          (progn
            (make-directory asset-dir t)
            (with-temp-file (expand-file-name "t" asset-dir) (insert "x"))
            (let ((errs (a3madkour-works-lint/lint-file f)))
              (should (cl-some (lambda (e)
                                 (string-match-p
                                  "must be a filename for works/games" e))
                               errs))))
        (delete-directory (expand-file-name (format "assets/%s" slug)
                                            (file-name-directory f))
                           t)
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
            ;; Rule 5's distinct wording.  The bare word "space" is too loose:
            ;; hero/cover's own message carries it too.
            (should (cl-some (lambda (e)
                               (string-match-p "has a space inside a filename" e))
                             errs)))
        (delete-file f)))))

;; Defect 2 (task-12 E2E): rule 5's old form asked only whether the value
;; held a space AND ended in an extension, which is true of every legitimate
;; multi-entry `screenshots' list -- including the design spec's own example.
;; Two-screenshot games were unpublishable.  Both files exist on disk here and
;; the ID drawer resolves, so a correct rule 5 has nothing to say.
(ert-deftest a3madkour-works-lint--accepts-multi-screenshot-list ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let* ((slug (make-temp-name "a3wl"))
           (f (a3madkour-works-lint-test--file (format ":PROPERTIES:
:ID:       %s
:END:
#+TITLE: G
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam :year 2026 :tagline T
#+HUGO_CUSTOM_FRONT_MATTER: :screenshots \"shot-1.png shot-2.png\"
" slug)))
           (asset-dir (expand-file-name (format "assets/%s/" slug)
                                        (file-name-directory f))))
      (unwind-protect
          (progn
            (make-directory asset-dir t)
            (dolist (n '("shot-1.png" "shot-2.png"))
              (with-temp-file (expand-file-name n asset-dir) (insert "x")))
            (let ((errs (a3madkour-works-lint/lint-file f)))
              (should-not (cl-some (lambda (e) (string-match-p "space" e)) errs))
              (should (null errs))))
        (delete-directory (expand-file-name (format "assets/%s" slug)
                                            (file-name-directory f))
                          t)
        (delete-file f)))))

;; Supplementary — the six brief tests never exercise the on-disk
;; asset-existence check directly (the space test only trips it as a
;; side effect on both halves of the split). The handler drops a
;; broken asset key silently, so this rule is the only place an author
;; ever hears about a missing file; pin it directly in both directions.
(ert-deftest a3madkour-works-lint--rejects-missing-asset-file ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let* ((slug (make-temp-name "a3wl"))
           (f (a3madkour-works-lint-test--file (format ":PROPERTIES:
:ID:       %s
:END:
#+TITLE: G
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
           (f (a3madkour-works-lint-test--file (format ":PROPERTIES:
:ID:       %s
:END:
#+TITLE: G
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

(ert-deftest a3madkour-works-lint--reads-id-from-property-drawer ()
  "The asset directory resolves from the file-level :ID: DRAWER.

Defect 1: the lint read a `#+ID:' keyword, so for a file authored the
documented way the id came back nil, the asset dir collapsed to
`<dir>/assets/', and every present asset was reported missing.  This file
declares the drawer only -- no `#+ID:' keyword anywhere -- and its one
declared asset genuinely exists, so a correct reader finds it."
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let* ((slug (make-temp-name "a3wl"))
           (f (a3madkour-works-lint-test--file (format ":PROPERTIES:
:ID:       %s
:END:
#+TITLE: G
#+HUGO_SECTION: works/games
#+HUGO_CUSTOM_FRONT_MATTER: :status playable :game_kind jam :year 2026 :tagline T
#+HUGO_CUSTOM_FRONT_MATTER: :hero hero.png
" slug)))
           (asset-dir (expand-file-name (format "assets/%s/" slug)
                                        (file-name-directory f))))
      (unwind-protect
          (progn
            (make-directory asset-dir t)
            (with-temp-file (expand-file-name "hero.png" asset-dir) (insert "x"))
            (let ((errs (a3madkour-works-lint/lint-file f)))
              ;; Assert on rule 4's distinct wording, not merely on emptiness:
              ;; a future unrelated rule going quiet must not be able to make
              ;; this test pass for the wrong reason.
              (should-not (cl-some (lambda (e) (string-match-p "hero entry" e)) errs))
              (should (null errs))))
        (delete-directory (expand-file-name (format "assets/%s" slug)
                                            (file-name-directory f))
                          t)
        (delete-file f)))))

;;; lyrics_poem <-> set_to_music symmetry (Task 9)
;;
;; The brief's Step 1 test bodies do not wrap these in
;; `a3madkour-works-lint-test--with-vocab', relying on the real
;; `a3madkour-pub-yaml/site-root' to resolve `data/works-vocab.json' (rule 2,
;; the `format' enum check, runs before the new symmetry rule and needs the
;; vocab file regardless of what the symmetry rule tests).  That works when
;; poking the function from a live Emacs pointed at the real site checkout,
;; but `run-tests.sh' never sets `a3madkour-pub/site-data-dir', so
;; `a3madkour-pub-yaml/site-root' signals `wrong-type-argument' before rule 5
;; is ever reached.  Wrapped here in the same vocab mock every other
;; `lint-file' test in this buffer already uses.

(ert-deftest a3madkour-works-lint--requires-reciprocal-set-to-music ()
  "A music item claiming a poem must find set_to_music in that poem's org."
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let* ((dir (make-temp-file "a3-works-sym" t))
           (poem (expand-file-name "tessellations.org" dir))
           (music (a3madkour-works-lint-test--file
                   (format "#+TITLE: M
#+HUGO_SECTION: works/music
#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026 :lyrics_poem tessellations
"))))
      (unwind-protect
          (progn
            (with-temp-file poem (insert "#+TITLE: Tessellations\n#+HUGO_SECTION: works/poetry\n"))
            (let ((a3madkour-pub/poetry-dir dir))
              (let ((errs (a3madkour-works-lint/lint-file music)))
                (should (cl-some (lambda (e) (string-match-p "set_to_music" e)) errs)))))
        (delete-file music) (delete-directory dir t)))))

(ert-deftest a3madkour-works-lint--accepts-reciprocal-set-to-music ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let* ((dir (make-temp-file "a3-works-sym" t))
           (poem (expand-file-name "tessellations.org" dir))
           (music (a3madkour-works-lint-test--file "#+TITLE: M
#+HUGO_SECTION: works/music
#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026 :lyrics_poem tessellations
")))
      (unwind-protect
          (progn
            (with-temp-file poem
              (insert "#+TITLE: Tessellations
#+HUGO_SECTION: works/poetry
#+HUGO_CUSTOM_FRONT_MATTER: :set_to_music m
"))
            (let ((a3madkour-pub/poetry-dir dir))
              (should-not (cl-some (lambda (e) (string-match-p "set_to_music" e))
                                   (a3madkour-works-lint/lint-file music)))))
        (delete-file music) (delete-directory dir t)))))

(ert-deftest a3madkour-works-lint--missing-poem-file-is-an-error ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((music (a3madkour-works-lint-test--file "#+TITLE: M
#+HUGO_SECTION: works/music
#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026 :lyrics_poem nonexistent
")))
      (unwind-protect
          (let ((a3madkour-pub/poetry-dir (make-temp-file "a3-empty" t)))
            (should (cl-some (lambda (e) (string-match-p "nonexistent" e))
                             (a3madkour-works-lint/lint-file music))))
        (delete-file music)))))

;;; platform_embed authoring exception (Defect 6)

(defun a3madkour-works-lint-test--music-file (cfm)
  "Temp works/music org file whose second CFM line is CFM."
  (a3madkour-works-lint-test--file
   (format "#+TITLE: M
#+HUGO_SECTION: works/music
#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026
#+HUGO_CUSTOM_FRONT_MATTER: %s
" cfm)))

(ert-deftest a3madkour-works-lint--platform-kind-needs-url ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--music-file ":platform_kind bandcamp")))
      (unwind-protect
          (should (cl-some (lambda (e)
                             (string-match-p "needs a matching :platform_url" e))
                           (a3madkour-works-lint/lint-file f)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--platform-url-needs-kind ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--music-file
              ":platform_url \"https://example.com/x\"")))
      (unwind-protect
          (should (cl-some (lambda (e)
                             (string-match-p "needs a matching :platform_kind" e))
                           (a3madkour-works-lint/lint-file f)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--rejects-unknown-platform-kind ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--music-file
              ":platform_kind spotify :platform_url \"https://example.com/x\"")))
      (unwind-protect
          ;; ":platform_kind=" is rule 6's own wording; the bare word
          ;; "platform_kind" also appears in the both-or-neither messages.
          (should (cl-some (lambda (e) (string-match-p ":platform_kind=" e))
                           (a3madkour-works-lint/lint-file f)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--rejects-direct-platform-embed ()
  "The nested form is unreachable through ox-hugo, so authoring it is an error."
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--music-file
              ":platform_embed \"{ kind: bandcamp, url: x }\"")))
      (unwind-protect
          ;; The REMEDY is the distinct half.  "cannot be authored directly" is
          ;; now shared with the `tracks' branch of the same rule, so asserting
          ;; on it would pin neither key.
          (should (cl-some (lambda (e)
                             (string-match-p ":platform_kind \\+ :platform_url" e))
                           (a3madkour-works-lint/lint-file f)))
        (delete-file f)))))

;; Fix round 2 — `tracks' is the only other map-valued works field, and it had
;; the identical hole: it is in `--works-music-keys' so a hand-authored
;; `:tracks "One 3:14"' survives the allowed-key filter as a string, is not
;; overwritten (the handler's `when-let' on `--parse-tracks' is nil with no
;; table), and is then `:omit'-ed by the render key-hook -- dropped with no
;; error at any layer, exactly the D6 failure mode.  Design spec §3.3 makes
;; that a general rule; this is what enforces it for the second member of the
;; class.
(ert-deftest a3madkour-works-lint--rejects-direct-tracks ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--music-file ":tracks \"Lorem One 3:14\"")))
      (unwind-protect
          (should (cl-some (lambda (e)
                             (string-match-p "#\\+NAME: tracks" e))
                           (a3madkour-works-lint/lint-file f)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--accepts-tracks-as-a-named-table ()
  "The org-table form is the supported one and must not trip rule 6."
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--file "#+TITLE: M
#+HUGO_SECTION: works/music
#+HUGO_CUSTOM_FRONT_MATTER: :format album :year 2026

#+NAME: tracks
| title     | duration |
|-----------+----------|
| Lorem One | 3:14     |
")))
      (unwind-protect
          (let ((errs (a3madkour-works-lint/lint-file f)))
            (should-not (cl-some (lambda (e) (string-match-p "tracks" e)) errs))
            (should (null errs)))
        (delete-file f)))))

(ert-deftest a3madkour-works-lint--accepts-both-platform-keys ()
  (a3madkour-works-lint-test--with-vocab a3madkour-works-lint-test--vocab
    (let ((f (a3madkour-works-lint-test--music-file
              ":platform_kind bandcamp :platform_url \"https://example.com/x\"")))
      (unwind-protect
          (let ((errs (a3madkour-works-lint/lint-file f)))
            (should-not (cl-some (lambda (e) (string-match-p "platform" e)) errs))
            (should (null errs)))
        (delete-file f)))))

(provide 'a3madkour-works-lint-test)
;;; a3madkour-works-lint-test.el ends here
