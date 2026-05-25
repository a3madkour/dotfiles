#!/usr/bin/env bash
# Run all ert tests for the a3madkour-publish library.
# Picks up every *-test.el in this directory.
#
# Usage:
#   ./run-tests.sh              # run all tests
#   ./run-tests.sh -v           # verbose (ert prints per-assertion notes)
set -euo pipefail

LISP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_DIR="$(dirname "$LISP_DIR")"
STRAIGHT_BOOTSTRAP="$CUSTOM_DIR/straight/repos/straight.el/bootstrap.el"

load_args=()
for test_file in "$LISP_DIR"/*-test.el; do
  load_args+=("-l" "$test_file")
done

if [ ${#load_args[@]} -eq 0 ]; then
  echo "no *-test.el files found in $LISP_DIR" >&2
  exit 2
fi

# Bootstrap straight.el AND add every straight-managed package's build dir
# to load-path, so any package the user has installed via straight (yaml.el
# for the publish library, etc.) is loadable in this batch session.
exec emacs --batch \
  --eval "(setq user-emacs-directory \"$CUSTOM_DIR/\")" \
  --eval "(setq straight-base-dir user-emacs-directory)" \
  -l "$STRAIGHT_BOOTSTRAP" \
  --eval "(straight-use-package 'org-roam)" \
  --eval "(straight-use-package 'yaml)" \
  --eval "(dolist (dir (directory-files (expand-file-name \"straight/build/\" user-emacs-directory) t \"^[^.]\")) (when (file-directory-p dir) (add-to-list 'load-path dir)))" \
  -L "$LISP_DIR" \
  -l ert \
  "${load_args[@]}" \
  -f ert-run-tests-batch-and-exit \
  "$@"
