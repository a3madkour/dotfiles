# Shared by compare-publish.sh and compare-features.sh; sourced, not run.
#
# Both scripts run two versions of the code in custom/lisp against a COPY of
# the notes and a COPY of the site, and compare the results.  The real notes
# ($A3_COMPARE_ORG, default ~/org) and site ($A3_COMPARE_SITE, default
# ~/Sync/Workspace/a3madkour.github.io) are only read.  HOME points into the
# copy while the code runs, so every "~/..." in publish-paths.el lands in the
# sandbox.  Both versions run at the same sandbox path ($BOX/run), one after
# the other, so absolute paths cannot differ between them.
#
# After `cmp_init OLD [NEW]':
#   OLD NEW            the two revisions ("WORKTREE" = the files on disk now)
#   BOX                the sandbox directory (kept; its path is printed)
#   ORG_REL SITE_REL   notes and site, relative to HOME
#   STRAIGHT           the real straight/ directory (linked into each run)
#   $BOX/pristine-home the inputs, never modified
#   $BOX/code-old, $BOX/code-new   lisp/ and publish-paths.el of each version

cmp_usage() {
  echo "usage: $(basename "$0") OLD [NEW]" >&2
  echo "  OLD, NEW: git revisions; NEW defaults to WORKTREE (the files on disk)." >&2
  exit 2
}

# The code of REV into DEST.
cmp_fetch_code() {
  local rev="$1" dest="$2"
  mkdir -p "$dest"
  if [ "$rev" = "WORKTREE" ]; then
    rsync -a --exclude '*.elc' --exclude '*.eln' "$CMP_CUSTOM_DIR/lisp" "$dest/"
    cp "$CMP_CUSTOM_DIR/publish-paths.el" "$dest/"
  else
    local tmp
    tmp="$(mktemp -d "$BOX/archive.XXXXXX")"
    if ! git -C "$CMP_REPO" archive "$rev" "$CMP_CUSTOM_REL/lisp" "$CMP_CUSTOM_REL/publish-paths.el" | tar -x -C "$tmp"; then
      echo "$(basename "$0"): cannot read the code at revision $rev" >&2
      exit 2
    fi
    mv "$tmp/$CMP_CUSTOM_REL/lisp" "$tmp/$CMP_CUSTOM_REL/publish-paths.el" "$dest/"
    rm -rf "$tmp"
  fi
}

cmp_init() {
  [ $# -ge 1 ] && [ $# -le 2 ] || cmp_usage
  OLD="$1"
  NEW="${2:-WORKTREE}"
  local me rev d
  me="$(basename "$0")"

  CMP_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CMP_CUSTOM_DIR="$(dirname "$CMP_TESTS_DIR")"
  CMP_REPO="$(git -C "$CMP_TESTS_DIR" rev-parse --show-toplevel)" || exit 2
  CMP_CUSTOM_REL="${CMP_CUSTOM_DIR#"$CMP_REPO"/}"
  for rev in "$OLD" "$NEW"; do
    [ "$rev" = "WORKTREE" ] || git -C "$CMP_REPO" rev-parse --verify -q "$rev^{commit}" >/dev/null \
      || { echo "$me: no such revision: $rev" >&2; exit 2; }
  done

  local real_home="$HOME"
  local org_src="${A3_COMPARE_ORG:-$real_home/org}"
  local site_src="${A3_COMPARE_SITE:-$real_home/Sync/Workspace/a3madkour.github.io}"
  STRAIGHT="$CMP_CUSTOM_DIR/straight"
  for d in "$org_src" "$site_src/data" "$STRAIGHT/repos"; do
    [ -d "$d" ] || { echo "$me: no directory $d" >&2; exit 2; }
  done
  for d in "$org_src" "$site_src"; do
    case "$d/" in "$real_home"/*) ;; *) echo "$me: $d is not under \$HOME" >&2; exit 2 ;; esac
  done
  ORG_REL="${org_src#"$real_home"/}"
  SITE_REL="${site_src#"$real_home"/}"

  BOX="$(mktemp -d "${TMPDIR:-/tmp}/${me%.sh}.XXXXXX")"
  echo "$me: sandbox $BOX"

  mkdir -p "$BOX/pristine-home/$(dirname "$ORG_REL")" "$BOX/pristine-home/$(dirname "$SITE_REL")"
  cp -a "$org_src" "$BOX/pristine-home/$ORG_REL"
  rsync -a --exclude public --exclude node_modules "$site_src/" "$BOX/pristine-home/$SITE_REL/"

  cmp_fetch_code "$OLD" "$BOX/code-old"
  cmp_fetch_code "$NEW" "$BOX/code-new"

  # The site's section contract.  A checkout without one gets the committed
  # test fixture, the same for both versions.
  if [ ! -f "$BOX/pristine-home/$SITE_REL/data/sections.json" ]; then
    echo "$me: NOTE the site has no data/sections.json; using the test fixture as the contract" >&2
    cp "$BOX/code-new/lisp/a3madkour-sections-fixture.json" \
       "$BOX/pristine-home/$SITE_REL/data/sections.json" || exit 2
  fi
}

# A fresh $BOX/run holding the inputs and version NAME (old|new) of the code.
cmp_begin_run() {
  local name="$1"
  RUN="$BOX/run"
  rm -rf "$RUN"
  mkdir -p "$RUN/logs"
  cp -a "$BOX/pristine-home" "$RUN/home"
  cp -a "$BOX/code-$name" "$RUN/custom"
  ln -s "$STRAIGHT" "$RUN/custom/straight"
}

# Park $BOX/run as $BOX/result-NAME.
cmp_end_run() {
  rm "$RUN/custom/straight"
  mv "$RUN" "$BOX/result-$1"
}

cmp_section() { printf '\n== %s\n' "$1"; }

# Compare the notes left behind by the two versions.  Sets cmp_status=1 when
# they differ.
cmp_compare_notes() {
  cmp_section "Notes afterwards"
  if diff -r "$BOX/result-old/home/$ORG_REL" "$BOX/result-new/home/$ORG_REL" >"$BOX/notes.diff"; then
    echo "identical"
  else
    cmp_status=1
    diff -rq "$BOX/result-old/home/$ORG_REL" "$BOX/result-new/home/$ORG_REL" | sed "s#$BOX/##g"
    echo "(full diff: $BOX/notes.diff)"
  fi
}

cmp_verdict() {
  printf '\n'
  if [ "$cmp_status" = 0 ]; then
    echo "$(basename "$0"): SAME — $OLD and $NEW behave identically here."
  else
    echo "$(basename "$0"): DIFFERENT — see above; results kept in $BOX"
  fi
  exit "$cmp_status"
}
