;;; a3madkour-publish-library.el --- library shelf rendering + shelf-file refusal  -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared pieces of the library shelves (`data/{reading,listening,
;; playing,watching}.yaml').  The shelves are collected from shared item
;; notes by `a3madkour-publish-library-notes', which renders each row with
;; `a3madkour-pub-library--render-row'; `a3madkour-library-items' reads
;; the per-medium extras table through `a3madkour-pub-library/extras-for'.
;;
;; A shelf file (`#+HUGO_SECTION: library/...', the old one org file ->
;; one shelf form) is refused: the registry's four `library/*' entries
;; point at `a3madkour-pub-library/refuse-shelf-file'.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish)
(require 'a3madkour-publish-registry)
(require 'a3madkour-sections)

(defun a3madkour-pub-library/sections ()
  "The library section strings (e.g. \"library/reading\"), from the registry."
  (a3madkour-pub-registry/sections-for-handler
   'a3madkour-pub-library/refuse-shelf-file))

(defun a3madkour-pub-library/extras-for (medium)
  "Return the per-medium extras spec for MEDIUM, or nil if unknown.

Each element is (DRAWER-KEY YAML-KEY COERCION-OR-NIL).  Public wrapper
over `a3madkour-pub-library--extras-by-media' for sibling modules."
  (cdr (assoc medium a3madkour-pub-library--extras-by-media)))

(defconst a3madkour-pub-library--extras-by-media
  '(("book"
     ("ISBN" :isbn nil) ("PROGRESS_PCT" :progress_pct int)
     ("PROGRESS_LABEL" :progress_label nil)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("album"
     ("MBID" :musicbrainz_release_group nil)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("track"
     ("MBID" :musicbrainz_release_group nil)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("game"
     ("IGDB_ID" :igdb_id int) ("HOURS_PLAYED" :hours_played int)
     ("PLATFORM" :platform nil)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("film"
     ("RUNTIME_MIN" :runtime_min int) ("TMDB_ID" :tmdb_id int)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil))
    ("series"
     ("EPISODE_COUNT" :episode_count int) ("CURRENT_EPISODE" :current_episode int)
     ("CURRENT_SEASON" :current_season int) ("TMDB_ID" :tmdb_id int)
     ("COVER_FILE" :cover_file nil) ("COVER_URL" :cover_url nil)))
  "Per-medium extras drawer prop → yaml key + coercion.
Matches `tools/check_library_fixtures.py:ALLOWED_EXTRAS' exactly.")

(defconst a3madkour-pub-library--yaml-key-order
  '(:slug :title :creator :year :media_type :status
    :started :finished :last_modified :note_slug :canonical_url
    :spoiler_level :cite_key :preview :tags :extras)
  "Deterministic key order within each yaml row.
Matches the shape of existing fixtures under data/*.yaml.")

(defun a3madkour-pub-library--yaml-single-quote (val)
  "Wrap VAL in YAML single-quoted style, doubling embedded `''.
Single-quoted YAML: the only escape is `'' → `'''."
  (concat "'" (replace-regexp-in-string "'" "''" val) "'"))

(defconst a3madkour-pub-library--non-string-scalar-re
  (concat "\\`\\(?:\\'"
          "\\|[+-]?\\(?:[0-9][0-9_]*\\(?:\\.[0-9_]*\\)?\\|\\.[0-9]+\\)"
          "\\(?:[eE][+-]?[0-9]+\\)?"
          "\\|0[xXoO][0-9a-fA-F_]+"
          "\\|[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}"
          "\\|~\\|[.][iI][nN][fF]\\|[.][nN][aA][nN]"
          "\\|\\(?:true\\|false\\|null\\|yes\\|no\\|on\\|off\\)"
          "\\)\\'")
  "Plain strings that YAML or `parse_scalar' read as a non-string.
Empty, numbers, dates, booleans and null spellings.  Matched
case-insensitively by `--reads-as-non-string-p'.")

(defun a3madkour-pub-library--reads-as-non-string-p (val)
  "Non-nil when plain VAL would be read back as a non-string."
  (let ((case-fold-search t))
    (string-match-p a3madkour-pub-library--non-string-scalar-re val)))

(defun a3madkour-pub-library--field-type (section path)
  "Contract type string of field PATH in library SECTION.
Signals when PATH is not in the contract (the emitter writes only
contract keys, so that is a bug)."
  (alist-get 'type (a3madkour-sections/field section path)))

(defun a3madkour-pub-library--render-scalar (val &optional type)
  "Render a scalar VAL for inclusion in YAML.

TYPE is the contract type of the field.  A string of type text, ref
or enum that YAML would read as a non-string (number, date, boolean,
null, empty) is single-quoted.  With no TYPE the output is unchanged.

Strings that contain YAML-sensitive characters (`:' `#'), look like URLs,
or begin with any YAML indicator character (`[' `]' `{' `}' `>' `|' `*'
`&' `!' `%' `@' `` ` `` `\"' `'' `?' `,' `-') are emitted in YAML
single-quoted style (`'...''), with embedded `'' doubled. Dates
(YYYY-MM-DD) and plain strings emit unquoted; nil/t/numbers handle their
natural types."
  (cond
   ((null val) "null")
   ((eq val t) "true")
   ((numberp val) (number-to-string val))
   ((stringp val)
    (cond
     ((and (member type '("text" "ref" "enum"))
           (a3madkour-pub-library--reads-as-non-string-p val))
      (a3madkour-pub-library--yaml-single-quote val))
     ;; YYYY-MM-DD: emit unquoted so PyYAML loads as datetime.date.
     ((string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$" val) val)
     ;; URLs: single-quote (escape embedded `'').
     ((string-prefix-p "http" val)
      (a3madkour-pub-library--yaml-single-quote val))
     ;; YAML-sensitive chars: single-quote (escape embedded `'').
     ((string-match-p "[:#]" val)
      (a3madkour-pub-library--yaml-single-quote val))
     ;; Leading YAML indicator would confuse the parser into reading a
     ;; flow collection, anchor/alias, block scalar, tag, directive, or
     ;; quoted scalar; force single-quoted output. `]' is placed first
     ;; inside the class so it is taken as a literal.
     ((string-match-p "\\`[][{}>|*&!%@`\"'?,-]" val)
      (a3madkour-pub-library--yaml-single-quote val))
     (t val)))
   (t (a3madkour-pub-library--yaml-single-quote (format "%S" val)))))

(defun a3madkour-pub-library--render-tags (tags)
  "Render a list of tag strings as a YAML flow-sequence."
  (concat "[" (mapconcat #'identity tags ", ") "]"))

(defun a3madkour-pub-library--render-extras (extras indent &optional section)
  "Render an EXTRAS plist as a nested YAML block at INDENT (a string).
SECTION, when given, supplies each value's contract type."
  (let ((lines '()))
    ;; Render in plist-iteration order (matches insertion order from
    ;; the per-medium extras table — already deterministic).
    (cl-loop for (k v) on extras by #'cddr
             for name = (substring (symbol-name k) 1)
             do (push (format "%s%s: %s" indent name
                              (a3madkour-pub-library--render-scalar
                              v (and section
                                     (a3madkour-pub-library--field-type
                                      section (concat "extras." name)))))
                      lines))
    (mapconcat #'identity (nreverse lines) "\n")))

(defun a3madkour-pub-library--render-row (row &optional section)
  "Render one ROW plist as a YAML list item (`  - key: value' style).
SECTION, when given, supplies each value's contract type."
  (let ((lines '())
        (first t))
    (dolist (key a3madkour-pub-library--yaml-key-order)
      (when (plist-member row key)
        (let* ((val (plist-get row key))
               (name (substring (symbol-name key) 1))
               (prefix (if first "  - " "    "))
               (line
                (cond
                 ((eq key :tags)
                  (format "%s%s: %s" prefix name
                          (a3madkour-pub-library--render-tags val)))
                 ((eq key :extras)
                  (format "%s%s:\n%s" prefix name
                          (a3madkour-pub-library--render-extras val "      " section)))
                 (t
                  (format "%s%s: %s" prefix name
                          (a3madkour-pub-library--render-scalar
                           val (and section
                                    (a3madkour-pub-library--field-type
                                     section name))))))))
          (push line lines)
          (setq first nil))))
    (mapconcat #'identity (nreverse lines) "\n")))

(cl-defun a3madkour-pub-library/refuse-shelf-file (file run &key on-done)
  "Refuse library shelf FILE: shelves are collected from item notes.
The registry's handler for every `library/*' section.  Logs the fix to
RUN (when given) and reports \='err via ON-DONE; writes nothing.  The
shelves themselves are built by `a3madkour-pub-library-notes/build-shelves'."
  (let ((msg (format "%s: library shelves are built from item notes; remove #+HUGO_SECTION: %s (see a3-library-add)"
                     file
                     (or (ignore-errors (a3madkour-pub/note-section file))
                         "library/…"))))
    (message "a3madkour-pub-library: %s" msg)
    (when run
      (a3-pub-async/log-step run "library-shelf-file" :err :err-snippet msg))
    (when on-done (funcall on-done 'err))))

(provide 'a3madkour-publish-library)

;;; a3madkour-publish-library.el ends here
