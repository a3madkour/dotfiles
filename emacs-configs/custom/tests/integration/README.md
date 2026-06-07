# Dotfiles publish-pipeline integration tests

End-to-end tests that exercise `a3-pub.sh --publish-deliberate` and
`a3-pub.sh --publish-living` against a temp `site/data/` dir.

## Setup

```sh
cd ~/dotfiles/emacs-configs/custom/tests/integration/
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/pytest
```

## Requirements

Tests skip when the host is missing one of:

- `emacs` (batch mode is used by `a3-pub.sh`)
- `git`
- `xelatex`, `biber`, `pandoc`, `rsvg-convert` (only for tests that
  trigger the D.2 multi-export path; non-D.2 tests don't need these).

The tests also need `~/org/essays/example-multi.org` to exist when
running D.2-exercising tests. Tests skip when the fixture is missing.

## Adding tests

- Use `pub_env` fixture for the standard A3_PUB_SITE_DATA_DIR env.
- Use `site_data_dir` for direct access to the temp data dir.
- Use `a3_pub_sh` for the absolute path to `a3-pub.sh`.
