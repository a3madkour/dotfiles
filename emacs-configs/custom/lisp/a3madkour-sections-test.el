;;; a3madkour-sections-test.el --- tests for the section contract reader  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'a3madkour-sections)
(require 'a3madkour-sections-fixture)

(defun a3madkour-sections-test--err (fn)
  "Call FN; return the message of the error it signals, or nil."
  (condition-case err (progn (funcall fn) nil)
    (error (error-message-string err))))

;;; Fail closed

(ert-deftest a3madkour-sections--fails-closed-when-missing ()
  (a3madkour-sections-test--with-root nil
    (should (string-match-p "contract not found at .*data/sections\\.json"
                            (a3madkour-sections-test--err
                             #'a3madkour-sections/names)))))

(ert-deftest a3madkour-sections--fails-closed-when-malformed ()
  (a3madkour-sections-test--with-root "{ not json"
    (should (string-match-p "is not valid JSON"
                            (a3madkour-sections-test--err
                             #'a3madkour-sections/names)))))

(ert-deftest a3madkour-sections--fails-closed-on-wrong-version ()
  (a3madkour-sections-test--with-root
      "{\"version\": 2, \"sections\": {\"about\": {\"fields\": {\"title\": {\"type\": \"text\"}}}}}"
    (should (string-match-p "version 2, expected 1"
                            (a3madkour-sections-test--err
                             #'a3madkour-sections/names)))))

(ert-deftest a3madkour-sections--fails-closed-on-section-without-fields ()
  (a3madkour-sections-test--with-root
      "{\"version\": 1, \"sections\": {\"about\": {}}}"
    (should (string-match-p "section about in .* has no fields"
                            (a3madkour-sections-test--err
                             #'a3madkour-sections/names)))))

(ert-deftest a3madkour-sections--fails-closed-on-variants-on-a-non-field ()
  (a3madkour-sections-test--with-root
      "{\"version\": 1, \"sections\": {\"garden\": {\"fields\": {\"title\": {\"type\": \"text\"}}, \"variants\": {\"on\": \"media_type\", \"cases\": {}}}}}"
    (should (string-match-p "variants.on \"media_type\" is not a field"
                            (a3madkour-sections-test--err
                             #'a3madkour-sections/names)))))

(ert-deftest a3madkour-sections--variants-on-may-name-a-case-only-field ()
  "The real garden declares `media_type' only inside its cases."
  (a3madkour-sections-test--with-root
      "{\"version\": 1, \"sections\": {\"garden\": {\"fields\": {\"title\": {\"type\": \"text\"}}, \"variants\": {\"on\": \"media_type\", \"cases\": {\"concept\": {\"values\": [null], \"fields\": {}}, \"media\": {\"values\": [\"book\"], \"fields\": {\"media_type\": {\"type\": \"enum\", \"values\": [\"book\"]}}}}}}}}"
    (should (equal (a3madkour-sections/names) '("garden")))
    (should (equal (a3madkour-sections/variant-case "garden" "book") "media"))))

(ert-deftest a3madkour-sections--empty-fields-object-is-a-section ()
  "`\"fields\": {}' (the real `about') decodes to nil but is not missing."
  (a3madkour-sections-test--with-root
      "{\"version\": 1, \"sections\": {\"about\": {\"closed\": false, \"fields\": {}}}}"
    (should (equal (a3madkour-sections/names) '("about")))
    (should-not (a3madkour-sections/emitted-keys "about"))
    (should-not (a3madkour-sections/required-authored "about"))))

(ert-deftest a3madkour-sections--fails-closed-without-site-data-dir ()
  (let ((a3madkour-sections--cache nil)
        (a3madkour-sections-file nil)
        (a3madkour-pub/site-data-dir nil))
    (should (string-match-p "site-data-dir is not set"
                            (a3madkour-sections-test--err
                             #'a3madkour-sections/names)))))

(ert-deftest a3madkour-sections--unknown-section-signals ()
  (a3madkour-sections-test--with-root a3madkour-sections-test--json
    (should (string-match-p "unknown section \"works/bogus\""
                            (a3madkour-sections-test--err
                             (lambda () (a3madkour-sections/spec "works/bogus")))))))

;;; Resolution and cache

(ert-deftest a3madkour-sections--resolves-through-site-data-dir ()
  "`with-root' unbinds the session default, so this read went through
`a3madkour-pub/site-data-dir' → <root>/data/sections.json."
  (a3madkour-sections-test--with-root
      (a3madkour-sections-test/mutate "\"about\": {" "\"colophon\": {")
    (should (member "colophon" (a3madkour-sections/names)))
    (should-not (member "about" (a3madkour-sections/names)))))

(ert-deftest a3madkour-sections--override-file-wins ()
  (let ((f (make-temp-file "a3-sections-override" nil ".json")))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert (a3madkour-sections-test/mutate "\"about\": {" "\"colophon\": {")))
          (let ((a3madkour-sections--cache nil)
                (a3madkour-sections-file f))
            (should (member "colophon" (a3madkour-sections/names)))))
      (delete-file f))))

(ert-deftest a3madkour-sections--cache-notices-an-edited-file ()
  "Keyed on mtime, not path alone: async publish keeps one Emacs alive
across runs, so an edited contract must be re-read."
  (a3madkour-sections-test--with-root a3madkour-sections-test--json
    (should (member "playable" (a3madkour-sections/enum "works/games" "status")))
    (let ((root (file-name-directory
                 (directory-file-name a3madkour-pub/site-data-dir))))
      (a3madkour-sections-test/write
       root (a3madkour-sections-test/mutate "\"playable\"" "\"shippable\""))
      (set-file-times (expand-file-name "data/sections.json" root)
                      (time-add (current-time) 10))
      (should (member "shippable" (a3madkour-sections/enum "works/games" "status")))
      (should-not (member "playable" (a3madkour-sections/enum "works/games" "status"))))))

;;; Queries over the fixture

(ert-deftest a3madkour-sections--names-in-file-order ()
  (should (equal (a3madkour-sections/names)
                 '("essays" "garden" "research/themes" "research/questions"
                   "works/games" "works/music" "works/poetry"
                   "library/reading" "library/listening" "library/playing"
                   "library/watching" "streams" "recipes" "about"))))

(ert-deftest a3madkour-sections--fields-base-and-variant ()
  (let ((base (mapcar #'car (a3madkour-sections/fields "garden")))
        (media (mapcar #'car (a3madkour-sections/fields "garden" "media"))))
    ;; `media_type' is declared only inside the media/reference cases.
    (should-not (member "media_type" base))
    (should-not (member "status" base))
    (should (member "media_type" media))
    (should (member "status" media))
    (should (member "creator" media))
    (should (equal (cl-subseq media 0 (length base)) base)))
  (should (equal (alist-get 'type (cdr (assoc "status" (a3madkour-sections/fields "research/themes"))))
                 "enum"))
  (should-error (a3madkour-sections/fields "garden" "bogus-case")))

(ert-deftest a3madkour-sections--null-and-false-decode-to-nil ()
  "`\"values\": [null]' selects the concept case for an ABSENT field, and
`\"required\": false' is not required.  Under the json.el defaults these
decode to `:null' / `:false', both truthy."
  (should (equal (a3madkour-sections/variant-case "garden" nil) "concept"))
  (a3madkour-sections-test--with-root
      "{\"version\": 1, \"sections\": {\"about\": {\"fields\": {\"title\": {\"type\": \"text\", \"required\": true}, \"blurb\": {\"type\": \"text\", \"required\": false}}}}}"
    (should (equal (a3madkour-sections/required-authored "about") '("title")))))

(ert-deftest a3madkour-sections--variant-case-selection ()
  (should (equal (a3madkour-sections/variant-case "garden" "book") "media"))
  (should (equal (a3madkour-sections/variant-case "garden" "paper") "reference"))
  (should-not (a3madkour-sections/variant-case "research/themes" nil))
  (should-error (a3madkour-sections/variant-case "garden" "hologram")))

(ert-deftest a3madkour-sections--enum-lookup ()
  (should (equal (a3madkour-sections/enum "research/themes" "status")
                 '("active" "dormant" "answered")))
  (should (equal (a3madkour-sections/enum "works/music" "platform_embed.kind")
                 '("bandcamp" "soundcloud" "youtube")))
  ;; A variant-case field is found too, including one that no base field
  ;; of the section declares (garden's `media_type').
  (should (member "queued" (a3madkour-sections/enum "garden" "status")))
  (should (member "book" (a3madkour-sections/enum "garden" "media_type")))
  (should (equal (alist-get 'type (a3madkour-sections/field "garden" "media_type"))
                 "enum"))
  (should-error (a3madkour-sections/enum "research/themes" "description"))
  (should-error (a3madkour-sections/enum "research/themes" "no_such_field")))

(ert-deftest a3madkour-sections--emitted-keys-compose-base-and-every-case ()
  (let ((games (a3madkour-sections/emitted-keys "works/games"))
        (music (a3madkour-sections/emitted-keys "works/music"))
        (garden (a3madkour-sections/emitted-keys "garden")))
    (should (member "hero" games))
    (should (member "tile_size" games))
    (should (member "status" games))
    (should-not (member "format" games))
    (should (member "format" music))
    (should-not (member "status" music))
    (should (member "status" garden))
    (should (member "media_type" garden))
    (should (member "weight" garden))
    (should (member "original_url" garden))
    ;; `creator' is in two cases but emitted once.
    (should (= (length garden) (length (delete-dups (copy-sequence garden)))))))

(ert-deftest a3madkour-sections--required-authored-excludes-pipeline ()
  (should (equal (a3madkour-sections/required-authored "works/games")
                 '("status" "game_kind" "tagline" "year")))
  (should (equal (a3madkour-sections/required-authored "works/music")
                 '("format" "year"))))

;;; No load-time dependencies

(ert-deftest a3madkour-sections--loads-under-emacs-Q ()
  "The reader, and the frontmatter normalizer that requires it, load on a
bare `emacs -Q' — the leaf property `a3madkour-works-vocab' had."
  (let* ((dir (file-name-directory (locate-library "a3madkour-sections")))
         (emacs (expand-file-name invocation-name invocation-directory))
         (status (call-process emacs nil nil nil "-Q" "--batch"
                               "--eval" "(setq load-prefer-newer t)"
                               "-L" dir
                               "--eval" "(require 'a3madkour-sections)"
                               "--eval" "(require 'a3madkour-publish-frontmatter)")))
    (should (equal status 0))))

;;; Cross-repo: the REAL data/sections.json

(ert-deftest a3madkour-sections--real-contract-sections-match-fixture ()
  (a3madkour-sections-test--with-real-site
    (let ((real (sort (a3madkour-sections/names) #'string<)))
      (should (= (length real) 14))
      (let ((a3madkour-sections--cache nil)
            (a3madkour-sections-file a3madkour-sections-test--fixture-path))
        (should (equal real (sort (a3madkour-sections/names) #'string<)))))))

(ert-deftest a3madkour-sections--real-contract-answers-every-consumer ()
  "Every query the publish pipeline makes resolves against the real file."
  (a3madkour-sections-test--with-real-site
    (dolist (s (a3madkour-sections/names))
      ;; `about' declares an empty field set; every other section has some.
      (unless (equal s "about")
        (should (a3madkour-sections/emitted-keys s))
        (should (a3madkour-sections/fields s))))
    (should-not (a3madkour-sections/emitted-keys "about"))
    (dolist (q '(("research/themes" . "status") ("research/questions" . "status")
                 ("works/games" . "status") ("works/games" . "game_kind")
                 ("works/music" . "format") ("works/music" . "platform_embed.kind")))
      (should (a3madkour-sections/enum (car q) (cdr q))))
    (dolist (s '("library/reading" "library/listening"
                 "library/playing" "library/watching"))
      (should (a3madkour-sections/enum s "media_type"))
      (should (a3madkour-sections/enum s "status")))
    (should (equal (a3madkour-sections/variant-case "garden" nil) "concept"))
    (dolist (s '("works/games" "works/music"))
      (let ((ra (a3madkour-sections/required-authored s)))
        (should ra)
        (dolist (p '("title" "date" "lastmod" "draft"))
          (should-not (member p ra)))))
    (let ((themes (a3madkour-sections/emitted-keys "research/themes")))
      (should-not (member "theme" themes))
      (should-not (member "parent_question" themes)))
    (should (equal (alist-get 'to (a3madkour-sections/field
                                   "research/questions" "theme"))
                   "research/themes"))))

(ert-deftest a3madkour-sections--real-garden-selects-variants-on-a-case-only-field ()
  (a3madkour-sections-test--with-real-site
    (should (equal (a3madkour-sections/variant-case "garden" nil) "concept"))
    (should (equal (a3madkour-sections/variant-case "garden" "book") "media"))
    (should (equal (a3madkour-sections/variant-case "garden" "paper") "reference"))
    (should (member "book" (a3madkour-sections/enum "garden" "media_type")))
    (should-not (assoc "media_type" (a3madkour-sections/fields "garden")))
    (should (assoc "media_type" (a3madkour-sections/fields "garden" "media")))))

(ert-deftest a3madkour-sections--real-library-extras-variant-fields-resolve ()
  "`extras' carries object-level variants; its case-only sub-fields resolve."
  (a3madkour-sections-test--with-real-site
    (should (a3madkour-sections/field "library/reading" "extras.cover_file"))
    (should (a3madkour-sections/field "library/reading" "extras.isbn"))
    (should (a3madkour-sections/field "library/watching" "extras.tmdb_id"))
    (should-error (a3madkour-sections/field "library/reading" "extras.nope"))))

(ert-deftest a3madkour-sections--real-null-and-false-decode-to-nil ()
  (a3madkour-sections-test--with-real-site
    (should-not (alist-get 'closed (a3madkour-sections/spec "about")))
    (should-not (alist-get 'required
                           (a3madkour-sections/field "works/games" "summary")))))

(provide 'a3madkour-sections-test)

;;; a3madkour-sections-test.el ends here
