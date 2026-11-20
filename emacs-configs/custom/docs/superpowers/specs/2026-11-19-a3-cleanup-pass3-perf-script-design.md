# a3 cleanup — pass 3 (manifest reads and the publish script)

Date: 2026-11-19
Status: approved in conversation (owner: "go ahead")
Roadmap: `2026-11-19-a3-cleanup-pass1-bugs-design.md` (pass 3 of 4)

## Why

Measured on the owner's machine: parsing the current `url-history.yaml`
(2.7KB, 19 notes) with yaml.el takes about 0.1 s, and a publish run parses it
at least three times per published note (`record-publish`,
`recorded-last-modified`, `aliases-for`). That is about 6 s per living run
today and grows with the square of the site. Separately, `a3-pub.sh` carries
five copies of a ~40-line `emacs --batch` invocation whose module lists have
drifted apart.

## Goals

- A publish run parses the manifest once, however many notes it publishes.
- `a3-pub.sh` builds its Emacs command in one place; every mode loads the
  same module list.
- The math check reads its folders from the configured paths.
- No directory path is spliced into Lisp source text by the script.

## Non-goals

- "Read each source file once per handler" (in the roadmap) is dropped:
  measured, an org buffer setup costs about 11 ms and a file read far less,
  so it would save about a second per run for a wide change.
- No renames (pass 4). No change to what a publish writes.

## Anti-goals

- Losing a manifest record in a crash that would not lose it today.
- A stale manifest being used after the file changed on disk (git pull,
  Syncthing, a hand edit).
- Any change to the start-of-run snapshot that `diff-published-set` relies on.

## Approaches considered (manifest)

- **A. Cache the parsed manifest, keyed on the file's path, modification time
  and size; keep writing on every change (chosen).** Every reader benefits,
  durability is exactly as today, and the cache invalidates itself when the
  file changes, with no tie to the run lifecycle.
- **B. A working copy owned by the run, written once at `finish-publish`.**
  Slightly faster, but a crash mid-run leaves published pages with no
  manifest record, and an aborted run leaves a stale copy behind.
- **C. Replace yaml.el parsing with a hand-written reader.** Removes the
  cost at its source but adds a parser to maintain.

In conversation this was described as "a working copy for the run, still
written on every change". Approach A delivers that outcome with a safer
mechanism (self-invalidating, not lifecycle-bound); the difference is called
out to the owner at hand-back.

## Design: manifest cache

- `a3madkour-pub-history/read-manifest` keeps its name, arguments and return
  shape. Internally it holds one cached parse together with the path,
  modification time (full resolution) and size it was read from. A call
  re-parses only when any of those differ from the file now.
- It returns a deep copy (lists and vectors) of the cached value, so a caller
  that mutates what it gets (as `record-publish` does) cannot corrupt the
  cache.
- `a3madkour-pub-history/write-manifest` updates the cache to the manifest it
  just wrote and the new file's attributes, so the next read does not parse.
- A missing or empty file is the empty manifest, as today, and is not cached.
- `a3madkour-pub--manifest-snapshot` and
  `read-manifest-snapshot-or-disk` are untouched.

## Design: script

- One shell function builds the common argument list (the five settings
  `--eval`s, the straight bootstrap, the two `straight-use-package` calls,
  the build-dir load-path loop, `-L`, the paths file). Each mode supplies
  only its own trailing arguments.
- One module list (the union of what the five modes load today) used by
  every mode.
- The custom directory reaches Emacs through an exported environment
  variable read with `getenv`, like the site data directory already does.
- The math check takes its roots from the configured notes folder and its
  parent as resolved from the paths file, not `$HOME/org/notes` and
  `$HOME/org`.
- Exit codes, messages, flags, environment variables and the order of the
  mode-specific `--eval`s do not change.

## Verification

- Manifest: tests count parses (a publish of several notes parses once), and
  cover an external change to the file, a caller mutating its copy, and a
  write followed by a read.
- Script: a fake `emacs` first on `PATH` records the arguments each mode
  passes. The record is taken before and after the refactor; the only
  differences allowed are the unified module list, the custom directory
  arriving through the environment, and argument order within the common
  block being made uniform. Permanent tests pin the invariants.

## Constraints

- Same test rules as before: ERT, temp directories, no real org-roam
  database, `~/org` or site checkout. 17 `sections.json` failures are the
  baseline.
- Work in a worktree, one commit per task, a review after each.

## Done when

- A test shows one parse for a multi-note run.
- `a3-pub.sh` contains one `emacs --batch` bootstrap block.
- The suite passes at the baseline.
