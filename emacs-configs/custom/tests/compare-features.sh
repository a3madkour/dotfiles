#!/usr/bin/env bash
# Run the non-publish commands (grocery list, ingredient registry, recipes,
# recipe import, recipe and works linters, library items) with two versions of
# the code against a COPY of the notes, and compare what each one returned,
# said and wrote.
#
#   compare-features.sh OLD [NEW]
#
# OLD and NEW are git revisions of this repo; NEW defaults to WORKTREE, which
# means the files as they are on disk now (uncommitted edits included).
#
# What is exercised is in compare-features-probe.el (the copy on disk is used
# for both versions).  See compare-lib.sh for how the sandbox works; the real
# notes and site are only read.  compare-publish.sh does the same for
# publishing.
#
# Exit status: 0 when both versions gave the same answers and left the same
# notes; 1 when anything differs (an intended behaviour change shows up here
# too); 2 on a usage or setup error.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/compare-lib.sh"
cmp_init "$@"
PROBE="$CMP_TESTS_DIR/compare-features-probe.el"
[ -f "$PROBE" ] || { echo "compare-features: no $PROBE" >&2; exit 2; }

# The same bootstrap as lisp/run-tests.sh, then the paths file and the probe.
run_version() {
  cmp_begin_run "$1"
  ( cd "$RUN/home" &&
    HOME="$RUN/home" \
    A3_COMPARE_CUSTOM_DIR="$RUN/custom" \
    A3_COMPARE_SITE_DATA_DIR="$RUN/home/$SITE_REL/data/" \
    A3_COMPARE_OUT="$RUN/logs/probe.txt" \
    timeout "${A3_COMPARE_STEP_TIMEOUT:-900}" emacs --batch \
      --eval "(setq native-comp-enable-subr-trampolines nil)" \
      --eval "(setq load-prefer-newer t)" \
      --eval "(setq user-emacs-directory (file-name-as-directory (getenv \"A3_COMPARE_CUSTOM_DIR\")))" \
      --eval "(setq straight-base-dir user-emacs-directory)" \
      -l "$RUN/custom/straight/repos/straight.el/bootstrap.el" \
      --eval "(straight-use-package 'org-roam)" \
      --eval "(straight-use-package 'yaml)" \
      --eval "(dolist (dir (directory-files (expand-file-name \"straight/build/\" user-emacs-directory) t \"^[^.]\")) (when (file-directory-p dir) (add-to-list 'load-path dir)))" \
      -L "$RUN/custom/lisp" \
      -l "$RUN/custom/publish-paths.el" \
      --eval "(setq a3madkour-pub/site-data-dir (getenv \"A3_COMPARE_SITE_DATA_DIR\"))" \
      -l "$PROBE" \
      >"$RUN/logs/emacs.out" 2>"$RUN/logs/emacs.err" </dev/null )
  echo "exit=$?" >"$RUN/logs/exit.txt"
  cmp_end_run "$1"
}

echo "compare-features: running with OLD ($OLD)"
run_version old
echo "compare-features: running with NEW ($NEW)"
run_version new

cmp_status=0

cmp_section "Probe"
for v in old new; do
  out="$BOX/result-$v/logs/probe.txt"
  if [ ! -s "$out" ]; then
    echo "$v: the probe wrote nothing ($(cat "$BOX/result-$v/logs/exit.txt")); see $BOX/result-$v/logs/emacs.err"
    cmp_status=1
  else
    printf '%s: %s, %s steps, %s raised an error\n' "$v" "$(cat "$BOX/result-$v/logs/exit.txt")" \
      "$(grep -c '^== ' "$out")" "$(grep -c '^(ERROR' "$out")"
  fi
done

cmp_section "Answers and messages"
if diff -u "$BOX/result-old/logs/probe.txt" "$BOX/result-new/logs/probe.txt" >"$BOX/probe.diff" 2>&1; then
  echo "identical"
else
  cmp_status=1
  # Name the steps that differ, then show the start of the diff.
  diff --old-line-format='' --new-line-format='' --unchanged-line-format='' \
       --changed-group-format='%dF
' --old-group-format='%dF
' --new-group-format='%dF
' "$BOX/result-old/logs/probe.txt" "$BOX/result-new/logs/probe.txt" 2>/dev/null \
    | while read -r line; do
        awk -v n="$line" 'NR<=n && /^== /{s=$0} END{print s}' "$BOX/result-old/logs/probe.txt"
      done | sort -u | sed 's/^== /differs in step: /'
  head -60 "$BOX/probe.diff" | sed 's/^/    /'
  echo "(full diff: $BOX/probe.diff)"
fi

cmp_compare_notes
cmp_verdict
