#!/usr/bin/env bash
# Run the full task-management test suite.
# Usage: ./tests/run.sh          # run everything
#        ./tests/run.sh PATTERN  # only tests whose name matches PATTERN (regex)

set -e
cd "$(dirname "$0")/.."

LOAD_ARGS=(-L tests)
for f in tests/test-helpers.el \
         tests/test-pure.el \
         tests/test-project-lifecycle.el \
         tests/test-tasks-scheduling.el \
         tests/test-inbox.el \
         tests/test-agenda-seasons.el \
         tests/test-helpers-extracted.el; do
  LOAD_ARGS+=(-l "$f")
done

if [[ -n "$1" ]]; then
  emacs --batch "${LOAD_ARGS[@]}" \
    --eval "(ert-run-tests-batch-and-exit \"$1\")"
else
  emacs --batch "${LOAD_ARGS[@]}" -f ert-run-tests-batch-and-exit
fi
