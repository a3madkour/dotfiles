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

if [ ! -f "$STRAIGHT_BOOTSTRAP" ]; then
  echo "a3-pub.sh: cannot find straight bootstrap at $STRAIGHT_BOOTSTRAP" >&2
  echo "a3-pub.sh: check that straight.el is installed under $CUSTOM_DIR/straight/" >&2
  exit 2
fi

exec emacs --batch \
  --eval "(setq user-emacs-directory \"$CUSTOM_DIR/\")" \
  --eval "(setq straight-base-dir user-emacs-directory)" \
  -l "$STRAIGHT_BOOTSTRAP" \
  --eval "(dolist (dir (directory-files (expand-file-name \"straight/build/\" user-emacs-directory) t \"^[^.]\")) (when (file-directory-p dir) (add-to-list 'load-path dir)))" \
  -L "$LISP_DIR" \
  -l a3madkour-publish \
  --eval "(message \"[a3-pub] ready (v%s)\" a3madkour-pub/version)" \
  "$@"
