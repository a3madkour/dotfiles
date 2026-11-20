#!/usr/bin/env bash
# Wrap Emacs in batch mode with the straight.el bootstrap + a3madkour-publish
# already loaded.  Use for ad-hoc CLI invocations of the publish library
# from outside an interactive emacs session.
#
# Any arguments are passed through to Emacs AFTER the library is
# loaded — typically one or more --eval forms.
#
# Examples:
#   ./a3-pub.sh --eval '(message "%s" a3madkour-pub/version)'
#   ./a3-pub.sh --eval '(message "%s" (a3madkour-pub/published-p "/path/file.org"))'
#   ./a3-pub.sh --eval '(message "%s" (a3madkour-pub/note-url "/tmp/scratch.org"))'
#
# Bonus: prints "[a3-pub] ready" to stderr so you can tell setup completed
# before your --eval runs.
set -euo pipefail

LISP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_DIR="$(dirname "$LISP_DIR")"
STRAIGHT_BOOTSTRAP="$CUSTOM_DIR/straight/repos/straight.el/bootstrap.el"

# The author's folders come from config.org's "Publishing paths" block,
# tangled to publish-paths.el beside config.el.  A batch run never loads
# config.el, so every emacs below loads this file itself; the library names
# no folder of its own.  $A3_PUB_PATHS_FILE overrides the location (tests).
PATHS_FILE="${A3_PUB_PATHS_FILE:-$CUSTOM_DIR/publish-paths.el}"
if [ ! -f "$PATHS_FILE" ]; then
  echo "a3-pub.sh: no publish-paths.el at $PATHS_FILE" >&2
  echo "a3-pub.sh: it is tangled from config.org's Publishing paths block; start Emacs once (or tangle config.org) to write it." >&2
  exit 2
fi

# The custom directory reaches Emacs through the environment, read with
# `getenv', so a path holding a `"' or `\' cannot break (or inject into) the
# --eval that sets `user-emacs-directory'.
A3_PUB_CUSTOM_DIR="$CUSTOM_DIR"
export A3_PUB_CUSTOM_DIR

# Which publish modules each mode loads.  Some modules act when loaded, not
# only when called: multi-filter adds an org-export hook that rewrites
# `#+multi_export: t' documents, and with bib + citations loaded
# `begin-publish' parses the bibliography.  So a module is added to a mode on
# purpose, never just to make the lists uniform.  Each mode's list is a
# composition of these groups, in load (dependency) order.
A3_PUB_GROUP_CORE=(
  a3madkour-publish
  a3madkour-publish-registry
  a3madkour-publish-rewrite
  a3madkour-publish-assets
  a3madkour-publish-unpublish
)
A3_PUB_GROUP_HISTORY=(
  a3madkour-publish-history
)
A3_PUB_GROUP_SECTIONS=(
  a3madkour-publish-export
  a3madkour-publish-frontmatter
  a3madkour-sections
  a3madkour-publish-living
  a3madkour-publish-deliberate
  a3madkour-publish-garden
  a3madkour-publish-library
  a3madkour-library-items
  a3madkour-publish-library-notes
  a3madkour-publish-research
  a3madkour-recipe-lint
  a3madkour-publish-recipes
  a3madkour-works-lint
  a3madkour-publish-works
)
A3_PUB_GROUP_DELIBERATE=(
  a3madkour-publish-essays
  a3madkour-publish-poetry
)
A3_PUB_GROUP_CITATIONS=(
  a3madkour-publish-bib
  a3madkour-publish-citations
)
A3_PUB_GROUP_MULTI=(
  a3madkour-publish-multi-filter
  a3madkour-publish-multi-pdf
  a3madkour-publish-multi-word
  a3madkour-publish-multi
)
A3_PUB_MODULES_CHECK_ORPHANS=("${A3_PUB_GROUP_CORE[@]}")
A3_PUB_MODULES_LIVING=("${A3_PUB_GROUP_CORE[@]}" "${A3_PUB_GROUP_SECTIONS[@]}"
                       "${A3_PUB_GROUP_CITATIONS[@]}")
A3_PUB_MODULES_DELIBERATE=("${A3_PUB_GROUP_CORE[@]}" "${A3_PUB_GROUP_SECTIONS[@]}"
                           "${A3_PUB_GROUP_DELIBERATE[@]}" "${A3_PUB_GROUP_CITATIONS[@]}"
                           "${A3_PUB_GROUP_MULTI[@]}")
A3_PUB_MODULES_SYNC_CITATIONS=("${A3_PUB_GROUP_CORE[@]}" "${A3_PUB_GROUP_HISTORY[@]}"
                               "${A3_PUB_GROUP_CITATIONS[@]}")
# The pass-through (--eval) mode loads every group.
A3_PUB_MODULES_DEFAULT=("${A3_PUB_GROUP_CORE[@]}" "${A3_PUB_GROUP_HISTORY[@]}"
                        "${A3_PUB_GROUP_SECTIONS[@]}" "${A3_PUB_GROUP_DELIBERATE[@]}"
                        "${A3_PUB_GROUP_CITATIONS[@]}" "${A3_PUB_GROUP_MULTI[@]}")

# The one Emacs bootstrap: settings, straight.el, the straight build dirs on
# `load-path', the paths file, then the modules.  Usage:
#   a3_pub_emacs MODULE... -- MODE-ARG...
# Each MODULE is loaded with `-l' in order; the MODE-ARGs are appended after.
# It `exec's, so the script's exit status is Emacs's; --publish-deliberate
# runs it with `&', where the exec replaces that background subshell and `$!'
# is Emacs's pid.
#
# It sets `load-prefer-newer': the publish modules sit beside untracked .elc
# files, and `require' otherwise loads a stale .elc over an edited .el — a fix
# that is silently not what publishes (S1 row 4).
a3_pub_emacs() {
  local module_args=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    module_args+=(-l "$1")
    shift
  done
  if [ $# -eq 0 ] || [ "${#module_args[@]}" -eq 0 ]; then
    echo "a3-pub.sh: internal error: a3_pub_emacs needs MODULE... -- ARG..." >&2
    exit 2
  fi
  shift
  exec emacs --batch \
    --eval "(setq native-comp-enable-subr-trampolines nil)" \
    --eval "(setq load-prefer-newer t)" \
    --eval "(setq user-emacs-directory (file-name-as-directory (getenv \"A3_PUB_CUSTOM_DIR\")))" \
    --eval "(setq straight-base-dir user-emacs-directory)" \
    -l "$STRAIGHT_BOOTSTRAP" \
    --eval "(straight-use-package 'org-roam)" \
    --eval "(straight-use-package 'yaml)" \
    --eval "(dolist (dir (directory-files (expand-file-name \"straight/build/\" user-emacs-directory) t \"^[^.]\")) (when (file-directory-p dir) (add-to-list 'load-path dir)))" \
    -L "$LISP_DIR" \
    -l "$PATHS_FILE" \
    "${module_args[@]}" \
    "$@"
}

# Resolve the Hugo site `data/' directory used for url-history.yaml.
# Cascade:
#   1. Explicit override via $A3_PUB_SITE_DATA_DIR
#   2. Auto-detect via `git rev-parse --show-toplevel' from $PWD
#   3. Error out with a clear message
# Used by all three publish-side intercepts.
a3_pub_resolve_site_data_dir() {
  if [ -n "${A3_PUB_SITE_DATA_DIR:-}" ]; then
    if [ ! -d "$A3_PUB_SITE_DATA_DIR" ]; then
      echo "a3-pub.sh: A3_PUB_SITE_DATA_DIR=$A3_PUB_SITE_DATA_DIR does not exist." >&2
      return 1
    fi
    # Normalise trailing slash so callers can interpolate uniformly.
    printf '%s/\n' "${A3_PUB_SITE_DATA_DIR%/}"
    return 0
  fi
  local repo_root
  if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -d "$repo_root/data" ]; then
    printf '%s/data/\n' "$repo_root"
    return 0
  fi
  echo "a3-pub.sh: cannot resolve site data dir." >&2
  echo "  Set A3_PUB_SITE_DATA_DIR=/path/to/site/data/ OR cd into the site repo before running." >&2
  return 1
}

# C: --skip-math-check flag init.  Default is on (run the check); the flag
# (parsed below before any intercept) flips this to skip the check.
A3_PUB_SKIP_MATH_CHECK="${A3_PUB_SKIP_MATH_CHECK:-0}"

# Task 12: --skip-recipe-check flag init.  Default is on (run the recipe
# linter); the flag (parsed below before any intercept) flips this to skip
# it.  Unlike A3_PUB_SKIP_MATH_CHECK (a shell-side check), the recipe lint
# gate runs INSIDE the emacs batch subprocess, so this must be exported for
# the child process to read it via `getenv'.
A3_PUB_SKIP_RECIPE_CHECK="${A3_PUB_SKIP_RECIPE_CHECK:-0}"
export A3_PUB_SKIP_RECIPE_CHECK

# Slice A1: --skip-works-check flag init.  Default is on (run the works
# lint).  Like the recipe lint, this is an elisp-side check, so the value
# travels as an exported env var read by --eval, not as a shell branch.
: "${A3_PUB_SKIP_WORKS_CHECK:=}"
export A3_PUB_SKIP_WORKS_CHECK

# S1 rows 6-7: classify the .org files under each PATH (file or directory;
# `tools/' segments skipped, as the CLI does).  Prints one `LINT<TAB>file' or
# `WARN<TAB>file' line per published file (`#+HUGO_PUBLISH: t'):
#   LINT  declares `#+HUGO_HAS_MATH: t' — the only files the math check reads
#   WARN  no such declaration, but its text outside src/example blocks holds
#         a math marker — a matched \(...\) / \[...\] pair, \begin{, $$ or an
#         org-style $x$ — so the flag was probably forgotten
# Unpublished files and math look-alikes (a synced-poetry `\[mm:ss]' timecode
# has no closing `\]') print nothing.  Both keywords accept only `t' (any
# case), mirroring `a3madkour-pub-keywords/boolean-p'.
a3_pub_math_classify() {
  find "$@" -name '*.org' -not -path '*/tools/*' -print0 \
    | xargs -0 perl -0777 -ne '
        next unless /^[ \t]*#\+hugo_publish:[ \t]*t[ \t]*$/mi;
        if (/^[ \t]*#\+hugo_has_math:[ \t]*t[ \t]*$/mi) { print "LINT\t$ARGV\n"; next }
        (my $b = $_) =~ s/^[ \t]*#\+begin_(src|example)\b.*?^[ \t]*#\+end_\1\b//gmsi;
        print "WARN\t$ARGV\n"
          if $b =~ /\\\(.+?\\\)|\\\[.+?\\\]|\\begin\{|\$\$|(?<![\\\$\w])\$[^\s\$](?:[^\$\n]*[^\s\$])?\$(?![\w\$])/s;
      '
}

# C: invoke `org-math-lint check [--config <toml>] <file>...' against the
# published, math-declaring files under each PATH (see
# `a3_pub_math_classify').  Default-on; honored unless A3_PUB_SKIP_MATH_CHECK=1.
# The executable is $A3_PUB_MATH_LINT, else `org-math-lint' on PATH (a
# `uv tool install' of the org-math-lint repo).  The config is
# $ORG_MATH_LINT_CONFIG; without one the CLI looks for ./config.toml and
# falls back to defaults that report every unknown command as an error.
# Exits non-zero on validator failure or missing install (distinct exit
# codes so callers can tell them apart):
#   0  validation passed (or skipped via flag/env)
#   1  validator reported issues (stderr already detailed)
#   2  org-math-lint not found
a3_pub_check_math() {
  if [ "$A3_PUB_SKIP_MATH_CHECK" = "1" ]; then
    return 0
  fi
  local kind file lint_files=()
  while IFS="$(printf '\t')" read -r kind file; do
    if [ "$kind" = "LINT" ]; then
      lint_files+=("$file")
    else
      echo "a3-pub.sh: WARN $file looks like it has math but lacks #+HUGO_HAS_MATH: t — not math-checked." >&2
    fi
  done < <(a3_pub_math_classify "$@")
  if [ "${#lint_files[@]}" -eq 0 ]; then
    echo "a3-pub.sh: math check: no published file declares #+HUGO_HAS_MATH: t; nothing to lint." >&2
    return 0
  fi
  local ml_bin="${A3_PUB_MATH_LINT:-$(command -v org-math-lint || true)}"
  if [ -z "$ml_bin" ] || [ ! -x "$ml_bin" ]; then
    echo "a3-pub.sh: org-math-lint not found (tried ${A3_PUB_MATH_LINT:-PATH})." >&2
    echo "  Install: uv tool install --editable <org-math-lint clone>" >&2
    echo "  Or rerun with --skip-math-check (sets A3_PUB_SKIP_MATH_CHECK=1)." >&2
    return 2
  fi
  local ml_args=(check)
  if [ -n "${ORG_MATH_LINT_CONFIG:-}" ]; then
    ml_args+=(--config "$ORG_MATH_LINT_CONFIG")
  fi
  if ! "$ml_bin" "${ml_args[@]}" "${lint_files[@]}"; then
    echo "a3-pub.sh: math validation failed; publish aborted." >&2
    echo "  Fix the issues above, or rerun with --skip-math-check." >&2
    return 1
  fi
  return 0
}

# C: the configured notes folder (`a3madkour-pub/org-notes-dir' as the paths
# file sets it), expanded, without a trailing slash.  Read by a bare
# `emacs -Q' that loads only the paths file (plain setqs), so it needs no
# straight.el; only `a3_pub_check_math_in' calls it, and only when the math
# check runs.  Returns 2 when the paths file sets no notes folder.
a3_pub_notes_dir() {
  local dir
  dir="$(emacs -Q --batch -l "$PATHS_FILE" \
           --eval '(let ((d (bound-and-true-p a3madkour-pub/org-notes-dir))) (when (and (stringp d) (> (length d) 0)) (princ (directory-file-name (expand-file-name d)))))')" || dir=
  if [ -z "$dir" ]; then
    echo "a3-pub.sh: $PATHS_FILE sets no a3madkour-pub/org-notes-dir; cannot find the notes to math-check." >&2
    echo "  Set it in config.org's Publishing paths block, or rerun with --skip-math-check." >&2
    return 2
  fi
  printf '%s\n' "$dir"
}

# C: `a3_pub_check_math' over the configured notes folder (`notes') or its
# parent (`org').  Skipped, without reading the paths file, under
# A3_PUB_SKIP_MATH_CHECK=1.
a3_pub_check_math_in() {
  if [ "$A3_PUB_SKIP_MATH_CHECK" = "1" ]; then
    return 0
  fi
  local notes
  notes="$(a3_pub_notes_dir)" || return $?
  if [ "$1" = "org" ]; then
    a3_pub_check_math "$(dirname "$notes")"
  else
    a3_pub_check_math "$notes"
  fi
}

# C: parse --skip-math-check anywhere in the arg list.  Done as a
# pre-pass so the rest of the intercept logic (positional <path>
# arguments, --eval pass-throughs) is unaffected.
parsed_args=()
for a in "$@"; do
  case "$a" in
    --skip-math-check) A3_PUB_SKIP_MATH_CHECK=1 ;;
    --skip-recipe-check) A3_PUB_SKIP_RECIPE_CHECK=1 ;;
    --skip-works-check) A3_PUB_SKIP_WORKS_CHECK=1 ;;
    *) parsed_args+=("$a") ;;
  esac
done
if [ "${#parsed_args[@]}" -gt 0 ]; then
  set -- "${parsed_args[@]}"
else
  set --
fi

# A.1.d: --check-orphans flag intercept.  Runs (begin-publish) + (check-orphans)
# in standalone mode (walks source tree), prints the dry-run plist, exits 0.
if [ "${1:-}" = "--check-orphans" ]; then
  shift
  # P5.5: export the resolved dir so the emacs child reads it via `getenv'
  # rather than us splicing it raw into an --eval string literal (a path with
  # a `"' or `\' would otherwise break the elisp string / inject code).
  # Assign THEN export on separate lines: `export VAR="$(cmd)"' would mask the
  # command-substitution exit status behind the export builtin's own success.
  SITE_DATA_DIR="$(a3_pub_resolve_site_data_dir)" || exit 1
  export SITE_DATA_DIR
  if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
    echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
    exit 2
  fi
  a3_pub_emacs "${A3_PUB_MODULES_CHECK_ORPHANS[@]}" -- \
    --eval "(setq a3madkour-pub/site-data-dir (getenv \"SITE_DATA_DIR\"))" \
    --eval "(a3madkour-pub/begin-publish)" \
    --eval "(let ((result (a3madkour-pub/check-orphans)))
              (princ (format \"removed: %S\\n\" (plist-get result :removed)))
              (princ (format \"slug-shifted: %S\\n\" (plist-get result :slug-shifted)))
              (princ \"orphan-warnings:\\n\")
              (dolist (w (plist-get result :orphan-warnings))
                (princ (format \"  %s\\n\" w)))
              (kill-emacs 0))" \
    "$@"
fi

# B.0: --publish-living flag intercept.  Runs (a3-publish-living) under
# the same straight bootstrap as the default exec.  Same as `M-x
# a3-publish-living' from inside emacs.
#
# A3_PUB_SITE_DATA_DIR overrides the Hugo site `data/' directory used for
# the URL-history manifest; auto-detected via git rev-parse if unset.
# `begin-publish' calls `read-manifest' which signals user-error if
# `a3madkour-pub/site-data-dir' is nil, so the wrapper sets it before
# invoking publish-living (no interactive config is loaded under --batch).
#
# P5.5: the (a3-publish-living) call is wrapped in a `condition-case' that
# exits 1 on a thrown error (nil site-data-dir, walk failure, …), mirroring
# --publish-deliberate so a broken invocation no longer exits 0.  Note this
# catches only SYNCHRONOUS failures — a per-handler error is caught inside
# living.el and rolled into finish-publish's 'err status, which this batch
# wrapper does not observe (surfacing that would need finish-publish to
# communicate run status back to the shell — a deeper follow-up).
if [ "${1:-}" = "--publish-living" ]; then
  shift
  if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
    echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
    exit 2
  fi
  # P5.5: export the resolved dir so the emacs child reads it via `getenv'
  # rather than us splicing it raw into an --eval string literal (a path with
  # a `"' or `\' would otherwise break the elisp string / inject code).
  # Assign THEN export on separate lines: `export VAR="$(cmd)"' would mask the
  # command-substitution exit status behind the export builtin's own success.
  SITE_DATA_DIR="$(a3_pub_resolve_site_data_dir)" || exit 1
  export SITE_DATA_DIR
  # C: source-side math validation before invoking emacs.
  a3_pub_check_math_in notes || exit $?
  a3_pub_emacs "${A3_PUB_MODULES_LIVING[@]}" -- \
    --eval "(setq a3madkour-recipe-lint-enabled (not (equal (getenv \"A3_PUB_SKIP_RECIPE_CHECK\") \"1\")))" \
    --eval "(setq a3madkour-works-lint-enabled (not (equal (getenv \"A3_PUB_SKIP_WORKS_CHECK\") \"1\")))" \
    --eval "(setq a3madkour-pub/site-data-dir (getenv \"SITE_DATA_DIR\"))" \
    --eval "(when (getenv \"A3_PUB_BIB_PATH\") (setq a3madkour-pub-bib/library-path (getenv \"A3_PUB_BIB_PATH\")))" \
    --eval "(condition-case err
              (a3-publish-living)
              (error (princ (format \"ERROR: %s\\n\" (error-message-string err)))
                     (kill-emacs 1)))" \
    --eval "(kill-emacs (if (memq a3-pub-async/last-status '(:err :cancelled)) 1 0))" \
    "$@"
fi

# B.0: --publish-deliberate <path> flag intercept.  Runs
# (a3-publish-deliberate <path>) under the same straight bootstrap.
# Same as `M-x a3-publish-deliberate' from inside emacs.
#
# A3_PUB_SITE_DATA_DIR overrides the Hugo site `data/' directory used
# for the URL-history manifest; auto-detected via git rev-parse if unset
# (same cascade as --publish-living above).  `a3-publish-deliberate' also routes
# through `begin-publish' → `read-manifest', so `site-data-dir' must be
# set under --batch before the publish call.
if [ "${1:-}" = "--publish-deliberate" ]; then
  shift
  if [ $# -lt 1 ]; then
    echo "a3-pub.sh --publish-deliberate: missing required <path> argument" >&2
    exit 2
  fi
  # P5.5: export so the child reads it via `getenv' (see SITE_DATA_DIR note) —
  # a source path containing `"' or `\' must not break/inject the --eval form.
  export A3_PUB_TARGET_PATH="$1"
  shift
  if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
    echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
    exit 2
  fi
  # P5.5: export the resolved dir so the emacs child reads it via `getenv'
  # rather than us splicing it raw into an --eval string literal (a path with
  # a `"' or `\' would otherwise break the elisp string / inject code).
  # Assign THEN export on separate lines: `export VAR="$(cmd)"' would mask the
  # command-substitution exit status behind the export builtin's own success.
  SITE_DATA_DIR="$(a3_pub_resolve_site_data_dir)" || exit 1
  export SITE_DATA_DIR
  # C: source-side math validation on the target file alone (S1 row 6: its
  # parent dir dragged sibling drafts in).  An org-roam id instead of a path
  # falls back to every published, math-declaring file under ~/org.
  if [ -f "$A3_PUB_TARGET_PATH" ]; then
    a3_pub_check_math "$A3_PUB_TARGET_PATH" || exit $?
  else
    a3_pub_check_math_in org || exit $?
  fi
  # Task 26: propagate SIGTERM/SIGINT to the emacs child so its
  # `kill-emacs-hook' runs (a3-pub-async--on-kill cleans tmp-dirs).
  emacs_pid=
  trap 'if [ -n "$emacs_pid" ]; then kill -TERM "$emacs_pid" 2>/dev/null; fi' TERM INT
  a3_pub_emacs "${A3_PUB_MODULES_DELIBERATE[@]}" -- \
    --eval "(setq a3madkour-recipe-lint-enabled (not (equal (getenv \"A3_PUB_SKIP_RECIPE_CHECK\") \"1\")))" \
    --eval "(setq a3madkour-works-lint-enabled (not (equal (getenv \"A3_PUB_SKIP_WORKS_CHECK\") \"1\")))" \
    --eval "(setq a3madkour-pub/site-data-dir (getenv \"SITE_DATA_DIR\"))" \
    --eval "(when (getenv \"A3_PUB_BIB_PATH\") (setq a3madkour-pub-bib/library-path (getenv \"A3_PUB_BIB_PATH\")))" \
    --eval "(condition-case err
              (a3-publish-deliberate (getenv \"A3_PUB_TARGET_PATH\"))
              (error (princ (format \"ERROR: %s\\n\" (error-message-string err)))
                     (kill-emacs 1)))" \
    --eval "(kill-emacs (if (memq a3-pub-async/last-status '(:err :cancelled)) 1 0))" \
    "$@" &
  emacs_pid=$!
  wait "$emacs_pid"
  exit $?
fi

# F Task 15: --sync-citations flag intercept.  Refreshes library.bib via BBT
# JSON-RPC (best-effort) then re-resolves every cite-key in the published
# corpus and overwrites data/citations.yaml in replace mode.
if [ "${1:-}" = "--sync-citations" ]; then
  shift
  if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
    echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
    exit 2
  fi
  # P5.5: export the resolved dir so the emacs child reads it via `getenv'
  # rather than us splicing it raw into an --eval string literal (a path with
  # a `"' or `\' would otherwise break the elisp string / inject code).
  # Assign THEN export on separate lines: `export VAR="$(cmd)"' would mask the
  # command-substitution exit status behind the export builtin's own success.
  SITE_DATA_DIR="$(a3_pub_resolve_site_data_dir)" || exit 1
  export SITE_DATA_DIR
  # C: source-side math validation across all org dirs (sync walks the whole corpus).
  a3_pub_check_math_in org || exit $?
  a3_pub_emacs "${A3_PUB_MODULES_SYNC_CITATIONS[@]}" -- \
    --eval "(setq a3madkour-pub/site-data-dir (getenv \"SITE_DATA_DIR\"))" \
    --eval "(when (getenv \"A3_PUB_BIB_PATH\") (setq a3madkour-pub-bib/library-path (getenv \"A3_PUB_BIB_PATH\")))" \
    --eval "(a3madkour-pub/begin-publish)" \
    --eval "(a3-sync-citations)" \
    --eval "(a3madkour-pub/finish-publish)" \
    --eval "(kill-emacs 0)" \
    "$@"
fi

if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
  echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
  echo "a3-pub.sh: check that straight.el is installed under $CUSTOM_DIR/straight/" >&2
  exit 2
fi

a3_pub_emacs "${A3_PUB_MODULES_DEFAULT[@]}" -- \
  `# Both lint gates run INSIDE the emacs batch process, so each --skip-*` \
  `# flag has to be translated into a setq on EVERY path that can publish.` \
  `# The recipe line was missing here, which meant --skip-recipe-check did` \
  `# nothing at all on this default path -- the flag was parsed and exported` \
  `# and then never read.` \
  --eval "(setq a3madkour-recipe-lint-enabled (not (equal (getenv \"A3_PUB_SKIP_RECIPE_CHECK\") \"1\")))" \
  --eval "(setq a3madkour-works-lint-enabled (not (equal (getenv \"A3_PUB_SKIP_WORKS_CHECK\") \"1\")))" \
  --eval "(message \"[a3-pub] ready (v%s)\" a3madkour-pub/version)" \
  "$@"
