#!/usr/bin/env bash
# Run all ert tests for the a3madkour-publish library.
# Picks up every *-test.el in this directory.
#
# Usage:
#   ./run-tests.sh              # run all tests
#   ./run-tests.sh -v           # verbose (ert prints per-assertion notes)
set -euo pipefail

LISP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_args=()
for test_file in "$LISP_DIR"/*-test.el; do
  load_args+=("-l" "$test_file")
done

if [ ${#load_args[@]} -eq 0 ]; then
  echo "no *-test.el files found in $LISP_DIR" >&2
  exit 2
fi

exec emacs --batch \
  -L "$LISP_DIR" \
  -l ert \
  "${load_args[@]}" \
  -f ert-run-tests-batch-and-exit \
  "$@"
