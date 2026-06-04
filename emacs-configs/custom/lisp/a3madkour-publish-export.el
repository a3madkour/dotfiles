;;; a3madkour-publish-export.el --- ox-hugo wrapper -*- lexical-binding: t; -*-

;;; Commentary:

;; Shared ox-hugo export wrapper for sub-project B's per-section
;; publishers.  Exposes a single entry point `export-file' that invokes
;; ox-hugo on a single source `.org' file and returns a structured plist:
;;
;;   (:body MARKDOWN-STRING :frontmatter ALIST :warnings (STRING ...))
;;
;; :body        — markdown body with NO frontmatter delimiters or contents.
;; :frontmatter — alist with SYMBOL keys (e.g. `(title . "X")
;;                `(tags . ("a" "b"))') as ox-hugo emits them, parsed from
;;                the YAML ox-hugo produces.
;; :warnings    — list of strings (empty for now; ox-hugo will surface
;;                warnings in later slices).
;;
;; Implementation forces YAML frontmatter by let-binding
;; `org-hugo-front-matter-format' to "yaml" around the export call, so
;; this never perturbs the user's interactive ox-hugo configuration.
;; Export is buffer-only (org-hugo-export-as-md); this function does NOT
;; write to disk — that is the caller's responsibility per spec §10.

;;; Code:

(require 'ox-hugo)
(require 'yaml)

;; D.1: enable 12 AMS-style block kinds as paired Hugo shortcodes.
;; #+begin_<kind> blocks emit as {{< <kind> >}}…{{< /<kind> >}} markdown
;; instead of the default <div class="<kind>">…</div>.
;; Title + cross-ref ID come via #+attr_shortcode: :title <name> :id <slug>
;; on a header line above the block (positional args are dropped in the
;; paired-shortcode path; see spec §3.2).
(setq org-hugo-paired-shortcodes
      "theorem lemma corollary proposition definition proof remark example note claim conjecture axiom")

(setq org-hugo-special-block-type-properties
      '(("theorem"     :trim-pre t :trim-post t)
        ("lemma"       :trim-pre t :trim-post t)
        ("corollary"   :trim-pre t :trim-post t)
        ("proposition" :trim-pre t :trim-post t)
        ("definition"  :trim-pre t :trim-post t)
        ("proof"       :trim-pre t :trim-post t)
        ("remark"      :trim-pre t :trim-post t)
        ("example"     :trim-pre t :trim-post t)
        ("note"        :trim-pre t :trim-post t)
        ("claim"       :trim-pre t :trim-post t)
        ("conjecture"  :trim-pre t :trim-post t)
        ("axiom"       :trim-pre t :trim-post t)))

(defun a3madkour-pub-export--frontmatter-string-to-alist (yaml-str file)
  "Parse YAML-STR (the YAML frontmatter ox-hugo emitted) into a symbol-keyed alist.
yaml.el with `:object-type \\='alist' already returns symbol-keyed alists.
YAML sequences (arrays) are returned as vectors; we convert them to lists so
callers see uniform list values for multi-valued fields like `tags'.
FILE is the source org path, used only to provide context in parse-error messages."
  (condition-case err
      (yaml-parse-string yaml-str
                         :object-type 'alist
                         :sequence-type 'list
                         :null-object nil
                         :false-object nil)
    (error
     (signal (car err)
             (list (format "a3madkour-pub-export: parsing frontmatter for %s: %s"
                           file (cadr err)))))))

(defun a3madkour-pub-export--split-frontmatter (text)
  "Split TEXT (raw ox-hugo output) into (FM-STRING . BODY-STRING).
FM-STRING is the YAML between the two `---' delimiters (without the delimiter
lines). BODY-STRING is everything after the closing delimiter, with leading
newlines trimmed.  Returns (\"\" . TEXT) when no frontmatter delimiters are
found."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (if (looking-at "^---\n")
        (let ((fm-start (match-end 0)))
          ;; Advance past the opening delimiter before searching for the closing one.
          (goto-char fm-start)
          (if (re-search-forward "^---\n" nil t)
              (cons (buffer-substring-no-properties fm-start (match-beginning 0))
                    (string-trim-left
                     (buffer-substring-no-properties (point) (point-max))))
            ;; Opening delimiter found but no closing delimiter — treat whole thing as body.
            (cons "" text)))
      ;; No frontmatter delimiters found.
      (cons "" text))))

(defun a3madkour-pub-export/export-file (file)
  "Export FILE (an absolute `.org' path) via ox-hugo.

Returns a plist:
  :body         MARKDOWN-STRING — the post-export markdown body (no frontmatter)
  :frontmatter  ALIST — keys are symbols (e.g. `title' `tags'), values are
                strings/lists/booleans as ox-hugo emits them
  :warnings     LIST OF STRINGS — non-fatal issues raised during export

Forces YAML frontmatter format via let-bound `org-hugo-front-matter-format'.
Uses `org-hugo-export-as-md' (buffer-emit variant) so no files are written to
disk — writing is the caller's responsibility per spec §10.

`org-export-show-temporary-export-buffer' defaults to t; ox-hugo would
pop *Org Hugo Export* into a new window during interactive runs even
though we read+kill it immediately.  Let-bind nil to suppress the
window-flash during publish."
  (let* ((org-hugo-front-matter-format "yaml")
         (org-export-show-temporary-export-buffer nil)
         (warnings nil)
         ;; Detect whether FILE is already open so we only kill what we create.
         (existing-buf (find-buffer-visiting file))
         (src-buf (or existing-buf (find-file-noselect file)))
         raw-output)
    (unwind-protect
        (progn
          ;; Run ox-hugo export; it writes into "*Org Hugo Export*".
          (with-current-buffer src-buf
            (let ((inhibit-message t))
              (org-hugo-export-as-md nil nil nil)))
          ;; Capture and discard the export output buffer.
          (let ((export-buf (get-buffer "*Org Hugo Export*")))
            (unless export-buf
              (error "a3madkour-pub-export: ox-hugo did not produce *Org Hugo Export* buffer"))
            (setq raw-output (with-current-buffer export-buf (buffer-string)))
            (kill-buffer export-buf)))
      ;; Cleanup: kill the source buffer only if we opened it.
      (unless existing-buf
        (when (buffer-live-p src-buf)
          (with-current-buffer src-buf
            (set-buffer-modified-p nil))  ; defensive — never write back
          (kill-buffer src-buf))))
    (let* ((parts (a3madkour-pub-export--split-frontmatter raw-output))
           (fm-string (car parts))
           (body (cdr parts))
           (frontmatter (if (string-empty-p fm-string)
                            nil
                          (a3madkour-pub-export--frontmatter-string-to-alist fm-string file))))
      (list :body body
            :frontmatter frontmatter
            :warnings warnings))))

(provide 'a3madkour-publish-export)

;;; a3madkour-publish-export.el ends here
