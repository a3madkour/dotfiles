#!/usr/bin/env bash
# Wrap `emacs --batch` with the straight.el bootstrap + a3madkour-publish
# already loaded.  Use for ad-hoc CLI invocations of the publish library
# from outside an interactive emacs session.
#
# Any arguments are passed through to emacs --batch AFTER the library is
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

# A.1.d: --check-orphans flag intercept.  Runs (begin-publish) + (check-orphans)
# in standalone mode (walks source tree), prints the dry-run plist, exits 0.
if [ "${1:-}" = "--check-orphans" ]; then
  shift
  SITE_DATA_DIR="$(a3_pub_resolve_site_data_dir)" || exit 1
  if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
    echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
    exit 2
  fi
  exec emacs --batch \
    --eval "(setq user-emacs-directory \"$CUSTOM_DIR/\")" \
    --eval "(setq straight-base-dir user-emacs-directory)" \
    -l "$STRAIGHT_BOOTSTRAP" \
    --eval "(straight-use-package 'org-roam)" \
    --eval "(straight-use-package 'yaml)" \
    --eval "(dolist (dir (directory-files (expand-file-name \"straight/build/\" user-emacs-directory) t \"^[^.]\")) (when (file-directory-p dir) (add-to-list 'load-path dir)))" \
    -L "$LISP_DIR" \
    -l a3madkour-publish \
    -l a3madkour-publish-rewrite \
    -l a3madkour-publish-assets \
    -l a3madkour-publish-unpublish \
    --eval "(setq a3madkour-pub/site-data-dir \"$SITE_DATA_DIR\")" \
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
if [ "${1:-}" = "--publish-living" ]; then
  shift
  if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
    echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
    exit 2
  fi
  SITE_DATA_DIR="$(a3_pub_resolve_site_data_dir)" || exit 1
  exec emacs --batch \
    --eval "(setq user-emacs-directory \"$CUSTOM_DIR/\")" \
    --eval "(setq straight-base-dir user-emacs-directory)" \
    -l "$STRAIGHT_BOOTSTRAP" \
    --eval "(straight-use-package 'org-roam)" \
    --eval "(straight-use-package 'yaml)" \
    --eval "(dolist (dir (directory-files (expand-file-name \"straight/build/\" user-emacs-directory) t \"^[^.]\")) (when (file-directory-p dir) (add-to-list 'load-path dir)))" \
    -L "$LISP_DIR" \
    -l a3madkour-publish \
    -l a3madkour-publish-rewrite \
    -l a3madkour-publish-assets \
    -l a3madkour-publish-unpublish \
    -l a3madkour-publish-export \
    -l a3madkour-publish-frontmatter \
    -l a3madkour-publish-living \
    -l a3madkour-publish-deliberate \
    -l a3madkour-publish-garden \
    --eval "(setq a3madkour-pub/site-data-dir \"$SITE_DATA_DIR\")" \
    --eval "(a3-publish-living)" \
    --eval "(kill-emacs 0)" \
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
  target_path="$1"
  shift
  if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
    echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
    exit 2
  fi
  SITE_DATA_DIR="$(a3_pub_resolve_site_data_dir)" || exit 1
  exec emacs --batch \
    --eval "(setq user-emacs-directory \"$CUSTOM_DIR/\")" \
    --eval "(setq straight-base-dir user-emacs-directory)" \
    -l "$STRAIGHT_BOOTSTRAP" \
    --eval "(straight-use-package 'org-roam)" \
    --eval "(straight-use-package 'yaml)" \
    --eval "(dolist (dir (directory-files (expand-file-name \"straight/build/\" user-emacs-directory) t \"^[^.]\")) (when (file-directory-p dir) (add-to-list 'load-path dir)))" \
    -L "$LISP_DIR" \
    -l a3madkour-publish \
    -l a3madkour-publish-rewrite \
    -l a3madkour-publish-assets \
    -l a3madkour-publish-unpublish \
    -l a3madkour-publish-export \
    -l a3madkour-publish-frontmatter \
    -l a3madkour-publish-living \
    -l a3madkour-publish-deliberate \
    -l a3madkour-publish-garden \
    --eval "(setq a3madkour-pub/site-data-dir \"$SITE_DATA_DIR\")" \
    --eval "(condition-case err
              (a3-publish-deliberate \"$target_path\")
              (error (princ (format \"ERROR: %s\\n\" (error-message-string err)))
                     (kill-emacs 1)))" \
    --eval "(kill-emacs 0)" \
    "$@"
fi

if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
  echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
  echo "a3-pub.sh: check that straight.el is installed under $CUSTOM_DIR/straight/" >&2
  exit 2
fi

exec emacs --batch \
  --eval "(setq user-emacs-directory \"$CUSTOM_DIR/\")" \
  --eval "(setq straight-base-dir user-emacs-directory)" \
  -l "$STRAIGHT_BOOTSTRAP" \
  --eval "(straight-use-package 'org-roam)" \
  --eval "(straight-use-package 'yaml)" \
  --eval "(dolist (dir (directory-files (expand-file-name \"straight/build/\" user-emacs-directory) t \"^[^.]\")) (when (file-directory-p dir) (add-to-list 'load-path dir)))" \
  -L "$LISP_DIR" \
  -l a3madkour-publish \
  -l a3madkour-publish-rewrite \
  -l a3madkour-publish-assets \
  -l a3madkour-publish-unpublish \
  -l a3madkour-publish-export \
  -l a3madkour-publish-frontmatter \
  -l a3madkour-publish-living \
  -l a3madkour-publish-deliberate \
  -l a3madkour-publish-garden \
  --eval "(message \"[a3-pub] ready (v%s)\" a3madkour-pub/version)" \
  "$@"
