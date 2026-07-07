;;; a3madkour-publish-multi-backend.el --- Shared D.2 multi-target export backend scaffold -*- lexical-binding: t; -*-

;;; Commentary:

;; P3.3 dedup.  The D.2 PDF (`a3madkour-publish-multi-pdf') and Word
;; (`a3madkour-publish-multi-word') backends were near-identical copies that
;; differed only in string literals / command lists.  This module hosts the
;; pieces they genuinely share:
;;
;;   - `a3madkour-pub-multi-backend/probe-tools'      — missing-command probe.
;;   - `a3madkour-pub-multi-backend/convert-svgs-fan' — barrier SVG fan-out,
;;     parameterized on the rsvg-convert command, the format-specific args
;;     ("-f pdf" vs "-f png -d 192"), and the process :name prefix.
;;   - `a3madkour-pub-multi-backend/log-line'         — one-line log emitter,
;;     parameterized on the backend label.
;;   - `a3madkour-pub-multi-backend/run-scaffold'     — the outer /run skeleton
;;     (work-dir + figures-dir computation, SVG (src dst) pair building, tmp-dir
;;     registration, optional pre-fan setup, the SVG conversion fan + `svgs'
;;     log-step) with the backend-specific compile+place step injected as a
;;     closure.
;;
;; The per-backend modules keep thin wrappers over these so the divergent
;; surface (xelatex chain vs pandoc/docx step, PDF's `:svg-source-file' seam
;; and cls-copy/ox-latex pre-fan, Word's post-fan filter serialization) stays
;; in place — the shared module owns only the identical infrastructure.

;;; Code:

(require 'cl-lib)
(require 'a3madkour-publish-async)

(defun a3madkour-pub-multi-backend/probe-tools (commands)
  "Return the subset of COMMANDS not resolvable via `executable-find', in order.
Returns nil when every command resolves."
  (let (missing)
    (dolist (cmd commands)
      (unless (executable-find cmd)
        (push cmd missing)))
    (nreverse missing)))

(cl-defun a3madkour-pub-multi-backend/convert-svgs-fan
    (pairs command fmt-args &key name-prefix on-done)
  "PAIRS is a list of (SRC DST).  Fan out one async run-process per pair.
Each spawn runs COMMAND with FMT-ARGS spliced ahead of `SRC -o DST', so the
effective argv is `COMMAND FMT-ARGS... SRC -o DST'.  FMT-ARGS carries the
format-specific flags (e.g. \\='(\"-f\" \"pdf\") or \\='(\"-f\" \"png\" \"-d\" \"192\")).
Each process is named `NAME-PREFIX-<basename>'.  ON-DONE fires (with the list
of exit codes) when all complete; an empty PAIRS fires ON-DONE immediately."
  (let ((n (length pairs)))
    (if (zerop n)
        (when on-done (funcall on-done nil))
      (let ((report (a3-pub-async/barrier n :on-all-done on-done)))
        (dolist (pair pairs)
          (let ((src (car pair)) (dst (cadr pair)))
            (make-directory (file-name-directory dst) t)
            (a3-pub-async/run-process
             command
             (append fmt-args (list src "-o" dst))
             :name (format "%s-%s" (or name-prefix "rsvg") (file-name-base src))
             :on-done (lambda (rc _tail) (funcall report rc)))))))))

(defun a3madkour-pub-multi-backend/log-line (buf label successp path elapsed err-snippet)
  "Append a single summary log line to BUF for a backend labelled LABEL.
SUCCESSP is t for the ✓ form / nil for ✗.  PATH is the target path on success.
ELAPSED is seconds (float).  ERR-SNIPPET is a stderr tail inlined on failure.
LABEL is left-padded to align the `→' column across backends."
  (with-current-buffer buf
    (goto-char (point-max))
    (if successp
        (insert (format "  [✓] %-7s→ %s   (%.1fs)\n" label path elapsed))
      (insert (format "  [✗] %-7s→ exit %.1fs\n" label elapsed))
      (when err-snippet
        (insert (format "              %s\n" err-snippet))))))

(cl-defun a3madkour-pub-multi-backend/run-scaffold
    (slug &key run svg-source svg-list-fn svg-ext svg-fan-fn
          svgs-step pre-fan compile)
  "Shared outer /run skeleton for the D.2 PDF and Word backends.

Computes the per-slug work dir under `temporary-file-directory' plus its
`figures/' subdir, lists SVG figures by calling SVG-LIST-FN on SVG-SOURCE and
maps each to `<base>.SVG-EXT' under the figures dir, creates the figures dir,
registers the work dir on RUN's tmp-dirs for cleanup, runs the optional
PRE-FAN closure (called with WORK-DIR — the PDF backend uses it to copy the
class file + run the ox-latex export + relocate the produced .tex), then fans
the SVG conversions via SVG-FAN-FN.  When all conversions finish it logs a
SVGS-STEP step (detail `N files') and invokes COMPILE.

SVG-LIST-FN and SVG-FAN-FN are passed as function values (typically the
per-backend `--list-svg-figures' / `--convert-svgs-fan' symbols) so callers'
`cl-letf' stubs keep intercepting.  COMPILE is called with
 (WORK-DIR FIG-DIR SVG-PAIRS) and owns the backend-specific compile + place +
result-report step."
  (let* ((work-dir (expand-file-name (format "multi-export-%s/" slug)
                                     temporary-file-directory))
         (fig-dir (expand-file-name "figures/" work-dir))
         (svgs (funcall svg-list-fn svg-source))
         (svg-pairs (mapcar (lambda (svg)
                              (list svg (expand-file-name
                                         (concat (file-name-base svg) "." svg-ext)
                                         fig-dir)))
                            svgs)))
    (make-directory fig-dir t)
    (when run (push work-dir (a3-pub-async-run-tmp-dirs run)))
    (when pre-fan (funcall pre-fan work-dir))
    (funcall svg-fan-fn
             svg-pairs
             :on-done
             (lambda (_svg-rcs)
               (when run
                 (a3-pub-async/log-step run svgs-step :ok
                                        :detail (format "%d files" (length svg-pairs))))
               (funcall compile work-dir fig-dir svg-pairs)))))

(provide 'a3madkour-publish-multi-backend)
;;; a3madkour-publish-multi-backend.el ends here
