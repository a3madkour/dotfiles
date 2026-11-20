#!/usr/bin/env bash
# Publish a COPY of the notes into a COPY of the site with two versions of the
# publish code, and compare what each one wrote.
#
#   compare-publish.sh OLD [NEW]
#
# OLD and NEW are git revisions of this repo; NEW defaults to WORKTREE, which
# means the files as they are on disk now (uncommitted edits included).
#
#   compare-publish.sh main~3            # last three commits + local edits
#   compare-publish.sh 4bee187 main
#
# See compare-lib.sh for how the sandbox works; the real notes and site are
# only read.  compare-features.sh does the same for the non-publish commands.
#
# Steps run with each version: --check-orphans, --publish-living,
# --publish-deliberate for every published essay and poem, --sync-citations,
# then --publish-living and --check-orphans again.
#
# Exit status: 0 when exit codes, site output and notes are the same for both
# versions; 1 when anything differs (not necessarily a bug: an intended change
# to what gets published shows up here too); 2 on a usage or setup error.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/compare-lib.sh"
cmp_init "$@"

# Essays and poems to publish one by one: every published .org file under the
# folders the NEW paths file names, as paths relative to the sandbox HOME.
deliberate_targets() {
  local dirs d
  dirs="$(HOME="$BOX/pristine-home" emacs -Q --batch -l "$BOX/code-new/publish-paths.el" \
    --eval '(dolist (v (list (bound-and-true-p a3madkour-pub/essays-dir) (bound-and-true-p a3madkour-pub/poetry-dir))) (when (and (stringp v) (file-directory-p v)) (princ (directory-file-name (expand-file-name v))) (terpri)))' 2>/dev/null)"
  [ -n "$dirs" ] || return 0
  while IFS= read -r d; do
    grep -rlis --include='*.org' '^[ \t]*#+hugo_publish:[ \t]*t[ \t]*$' "$d" || true
  done <<<"$dirs" | sed "s#^$BOX/pristine-home/##" | sort
}
mapfile -t TARGETS < <(deliberate_targets)
echo "compare-publish: ${#TARGETS[@]} essays/poems to publish one by one"

step() {
  local label="$1"; shift
  ( cd "$RUN/home/$SITE_REL" &&
    HOME="$RUN/home" A3_PUB_SITE_DATA_DIR="$RUN/home/$SITE_REL/data" \
      timeout "${A3_COMPARE_STEP_TIMEOUT:-900}" bash "$RUN/custom/lisp/a3-pub.sh" "$@" \
      >"$RUN/logs/$label.out" 2>"$RUN/logs/$label.err" </dev/null )
  printf '%-44s exit=%s\n' "$label" "$?" >>"$RUN/logs/summary.txt"
}

run_version() {
  cmp_begin_run "$1"
  step 01-check-orphans --check-orphans
  step 02-living --publish-living
  local n=3 f
  for f in "${TARGETS[@]}"; do
    step "$(printf '%02d' "$n")-deliberate-$(basename "$f" .org)" --publish-deliberate "$RUN/home/$f"
    n=$((n + 1))
  done
  step "$(printf '%02d' "$n")-sync-citations" --sync-citations
  step "$(printf '%02d' $((n + 1)))-living-again" --publish-living
  step "$(printf '%02d' $((n + 2)))-check-orphans-again" --check-orphans
  cmp_end_run "$1"
}

echo "compare-publish: publishing with OLD ($OLD)"
run_version old
echo "compare-publish: publishing with NEW ($NEW)"
run_version new

cmp_status=0

cmp_section "Exit codes (old | new)"
paste -d'|' "$BOX/result-old/logs/summary.txt" \
            <(sed 's/^[^ ]* *//' "$BOX/result-new/logs/summary.txt")
if ! diff -q "$BOX/result-old/logs/summary.txt" "$BOX/result-new/logs/summary.txt" >/dev/null; then
  echo "DIFFERENT exit codes"; cmp_status=1
fi

cmp_section "Site output"
# The manifest stamps the time a URL was replaced; a hunk made only of those
# lines is not a difference.
if diff -r -x .git -I '^ *replaced_at:' \
     "$BOX/result-old/home/$SITE_REL" "$BOX/result-new/home/$SITE_REL" >"$BOX/site.diff"; then
  echo "identical"
else
  cmp_status=1
  diff -rq -x .git -I '^ *replaced_at:' \
    "$BOX/result-old/home/$SITE_REL" "$BOX/result-new/home/$SITE_REL" | sed "s#$BOX/##g"
  echo "(full diff: $BOX/site.diff)"
fi

cmp_compare_notes
if ! diff -rq "$BOX/pristine-home/$ORG_REL" "$BOX/result-new/home/$ORG_REL" >/dev/null; then
  echo "(NEW changed the notes it published from; see result-new/home/$ORG_REL)"
fi

cmp_section "Messages"
# Informational: compiler warnings, load lines and timings are dropped.
clean_log() { grep -v 'Warning:\|^Loading \|^$' "$1" | sed -E 's/\([0-9.]+s\)//'; }
messages_differ=0
for f in "$BOX"/result-old/logs/*.out "$BOX"/result-old/logs/*.err; do
  b="$(basename "$f")"
  if ! diff <(clean_log "$f") <(clean_log "$BOX/result-new/logs/$b" 2>/dev/null) >"$BOX/log-$b.diff"; then
    messages_differ=1
    echo "differs: $b"; sed 's/^/    /' "$BOX/log-$b.diff" | head -20
  else
    rm -f "$BOX/log-$b.diff"
  fi
done
[ "$messages_differ" = 0 ] && echo "identical"

cmp_verdict
