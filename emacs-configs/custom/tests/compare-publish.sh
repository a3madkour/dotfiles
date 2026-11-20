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
# The real notes ($A3_COMPARE_ORG, default ~/org) and site ($A3_COMPARE_SITE,
# default ~/Sync/Workspace/a3madkour.github.io) are only read.  Each run gets
# a fresh copy of both under one sandbox directory, and HOME points into that
# copy while a3-pub.sh runs, so every "~/..." in publish-paths.el lands in the
# sandbox.  Both versions run at the same sandbox path, one after the other,
# so absolute paths cannot differ between them.
#
# Steps run with each version: --check-orphans, --publish-living,
# --publish-deliberate for every published essay and poem, --sync-citations,
# then --publish-living and --check-orphans again.
#
# Exit status: 0 when exit codes, site output and notes are the same for both
# versions; 1 when anything differs (not necessarily a bug: an intended change
# to what gets published shows up here too); 2 on a usage or setup error.
# The sandbox is kept, and its path printed, so the differences can be read.
set -uo pipefail

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
OLD="$1"
NEW="${2:-WORKTREE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_DIR="$(dirname "$SCRIPT_DIR")"
REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || exit 2
CUSTOM_REL="${CUSTOM_DIR#"$REPO"/}"
for rev in "$OLD" "$NEW"; do
  [ "$rev" = "WORKTREE" ] || git -C "$REPO" rev-parse --verify -q "$rev^{commit}" >/dev/null \
    || { echo "compare-publish: no such revision: $rev" >&2; exit 2; }
done
REAL_HOME="$HOME"
ORG_SRC="${A3_COMPARE_ORG:-$REAL_HOME/org}"
SITE_SRC="${A3_COMPARE_SITE:-$REAL_HOME/Sync/Workspace/a3madkour.github.io}"
STRAIGHT="$CUSTOM_DIR/straight"

for d in "$ORG_SRC" "$SITE_SRC/data" "$STRAIGHT/repos"; do
  [ -d "$d" ] || { echo "compare-publish: no directory $d" >&2; exit 2; }
done
case "$ORG_SRC/" in "$REAL_HOME"/*) ;; *) echo "compare-publish: $ORG_SRC is not under \$HOME" >&2; exit 2 ;; esac
case "$SITE_SRC/" in "$REAL_HOME"/*) ;; *) echo "compare-publish: $SITE_SRC is not under \$HOME" >&2; exit 2 ;; esac
ORG_REL="${ORG_SRC#"$REAL_HOME"/}"
SITE_REL="${SITE_SRC#"$REAL_HOME"/}"

BOX="$(mktemp -d "${TMPDIR:-/tmp}/compare-publish.XXXXXX")"
echo "compare-publish: sandbox $BOX"

# --- inputs -----------------------------------------------------------------

mkdir -p "$BOX/pristine-home/$(dirname "$ORG_REL")" "$BOX/pristine-home/$(dirname "$SITE_REL")"
cp -a "$ORG_SRC" "$BOX/pristine-home/$ORG_REL"
rsync -a --exclude public --exclude node_modules "$SITE_SRC/" "$BOX/pristine-home/$SITE_REL/"

# The publish code of REV ("WORKTREE" = the files on disk) into DEST.
fetch_code() {
  local rev="$1" dest="$2"
  mkdir -p "$dest"
  if [ "$rev" = "WORKTREE" ]; then
    rsync -a --exclude '*.elc' --exclude '*.eln' "$CUSTOM_DIR/lisp" "$dest/"
    cp "$CUSTOM_DIR/publish-paths.el" "$dest/"
  else
    local tmp
    tmp="$(mktemp -d "$BOX/archive.XXXXXX")"
    if ! git -C "$REPO" archive "$rev" "$CUSTOM_REL/lisp" "$CUSTOM_REL/publish-paths.el" | tar -x -C "$tmp"; then
      echo "compare-publish: cannot read the publish code at revision $rev" >&2
      exit 2
    fi
    mv "$tmp/$CUSTOM_REL/lisp" "$tmp/$CUSTOM_REL/publish-paths.el" "$dest/"
    rm -rf "$tmp"
  fi
}
fetch_code "$OLD" "$BOX/code-old"
fetch_code "$NEW" "$BOX/code-new"

# The site's section contract.  A checkout without one gets the committed
# test fixture, the same for both versions.
if [ ! -f "$BOX/pristine-home/$SITE_REL/data/sections.json" ]; then
  echo "compare-publish: NOTE the site has no data/sections.json; using the test fixture as the contract" >&2
  cp "$BOX/code-new/lisp/a3madkour-sections-fixture.json" \
     "$BOX/pristine-home/$SITE_REL/data/sections.json" || exit 2
fi

# Essays and poems to publish one by one: every published .org file under the
# folders the NEW paths file names, as paths relative to the sandbox HOME.
deliberate_targets() {
  local dirs
  dirs="$(HOME="$BOX/pristine-home" emacs -Q --batch -l "$BOX/code-new/publish-paths.el" \
    --eval '(dolist (v (list (bound-and-true-p a3madkour-pub/essays-dir) (bound-and-true-p a3madkour-pub/poetry-dir))) (when (and (stringp v) (file-directory-p v)) (princ (directory-file-name (expand-file-name v))) (terpri)))' 2>/dev/null)"
  [ -n "$dirs" ] || return 0
  local d
  while IFS= read -r d; do
    grep -rlis --include='*.org' '^[ \t]*#+hugo_publish:[ \t]*t[ \t]*$' "$d" || true
  done <<<"$dirs" | sed "s#^$BOX/pristine-home/##" | sort
}
mapfile -t TARGETS < <(deliberate_targets)
echo "compare-publish: ${#TARGETS[@]} essays/poems to publish one by one"

# --- one publish run ----------------------------------------------------------

run_version() {
  local name="$1"
  local run="$BOX/run"
  rm -rf "$run"
  mkdir -p "$run"
  cp -a "$BOX/pristine-home" "$run/home"
  cp -a "$BOX/code-$name" "$run/custom"
  ln -s "$STRAIGHT" "$run/custom/straight"
  local pub="$run/custom/lisp/a3-pub.sh" log="$run/logs"
  mkdir -p "$log"

  step() {
    local label="$1"; shift
    ( cd "$run/home/$SITE_REL" &&
      HOME="$run/home" A3_PUB_SITE_DATA_DIR="$run/home/$SITE_REL/data" \
        timeout "${A3_COMPARE_STEP_TIMEOUT:-900}" bash "$pub" "$@" \
        >"$log/$label.out" 2>"$log/$label.err" </dev/null )
    printf '%-44s exit=%s\n' "$label" "$?" >>"$log/summary.txt"
  }

  step 01-check-orphans --check-orphans
  step 02-living --publish-living
  local n=3 f
  for f in "${TARGETS[@]}"; do
    step "$(printf '%02d' "$n")-deliberate-$(basename "$f" .org)" --publish-deliberate "$run/home/$f"
    n=$((n + 1))
  done
  step "$(printf '%02d' "$n")-sync-citations" --sync-citations
  step "$(printf '%02d' $((n + 1)))-living-again" --publish-living
  step "$(printf '%02d' $((n + 2)))-check-orphans-again" --check-orphans

  rm "$run/custom/straight"
  mv "$run" "$BOX/result-$name"
}

echo "compare-publish: publishing with OLD ($OLD)"
run_version old
echo "compare-publish: publishing with NEW ($NEW)"
run_version new

# --- compare ------------------------------------------------------------------

status=0
section() { printf '\n== %s\n' "$1"; }

section "Exit codes (old | new)"
paste -d'|' "$BOX/result-old/logs/summary.txt" \
            <(sed 's/^[^ ]* *//' "$BOX/result-new/logs/summary.txt")
if ! diff -q "$BOX/result-old/logs/summary.txt" "$BOX/result-new/logs/summary.txt" >/dev/null; then
  echo "DIFFERENT exit codes"; status=1
fi

section "Site output"
# The manifest stamps the time a URL was replaced; a hunk made only of those
# lines is not a difference.
if diff -r -x .git -I '^ *replaced_at:' \
     "$BOX/result-old/home/$SITE_REL" "$BOX/result-new/home/$SITE_REL" >"$BOX/site.diff"; then
  echo "identical"
else
  status=1
  diff -rq -x .git -I '^ *replaced_at:' \
    "$BOX/result-old/home/$SITE_REL" "$BOX/result-new/home/$SITE_REL" | sed "s#$BOX/##g"
  echo "(full diff: $BOX/site.diff)"
fi

section "Notes after publishing"
if diff -rq "$BOX/result-old/home/$ORG_REL" "$BOX/result-new/home/$ORG_REL" >"$BOX/notes.diff"; then
  echo "identical"
else
  status=1; sed "s#$BOX/##g" "$BOX/notes.diff"
fi
if ! diff -rq "$BOX/pristine-home/$ORG_REL" "$BOX/result-new/home/$ORG_REL" >/dev/null; then
  echo "(NEW changed the notes it published from; see result-new/home/$ORG_REL)"
fi

section "Messages"
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

printf '\n'
if [ "$status" = 0 ]; then
  echo "compare-publish: SAME — $OLD and $NEW published identical output."
else
  echo "compare-publish: DIFFERENT — see above; results kept in $BOX"
fi
exit "$status"
