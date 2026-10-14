#!/usr/bin/env bash
# Run the full task-management test suite.
# Usage: ./tests/run.sh          # run everything
#        ./tests/run.sh PATTERN  # only tests whose name matches PATTERN (regex)

set -e
cd "$(dirname "$0")/.."

# boox-core.el is tangled from config.org. A stale .elc silently shadows it,
# because `require' prefers byte-code even when it is older than the source.
rm -f boox-core.elc

LOAD_ARGS=(-L tests -L .)

# --batch skips early-init.el, which is where the macOS native-comp target
# lives (see "Native-compilation macOS target" in config.org). Without it,
# tests that stub a primitive with cl-letf need a native trampoline, and
# libgccjit's guessed -mmacosx-version-min=18.0 makes clang refuse to build it.
if [[ "$(uname)" == Darwin ]]; then
  LOAD_ARGS=(--eval '(setq native-comp-driver-options (quote ("-Wl,-w" "-mmacosx-version-min=26.0")))'
             "${LOAD_ARGS[@]}")
fi

for f in tests/test-helpers.el \
         tests/test-pure.el \
         tests/test-project-lifecycle.el \
         tests/test-tasks-scheduling.el \
         tests/test-inbox.el \
         tests/test-agenda-seasons.el \
         tests/test-helpers-extracted.el \
         tests/boox-tests.el \
         tests/test-lsp-plists.el; do
  LOAD_ARGS+=(-l "$f")
done

if [[ -n "$1" ]]; then
  emacs --batch "${LOAD_ARGS[@]}" \
    --eval "(ert-run-tests-batch-and-exit \"$1\")"
else
  emacs --batch "${LOAD_ARGS[@]}" -f ert-run-tests-batch-and-exit
fi
