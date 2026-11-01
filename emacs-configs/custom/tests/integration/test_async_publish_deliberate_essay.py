"""Integration test: async deliberate publish of an example essay.

Runs `a3-pub.sh --skip-math-check --publish-deliberate` against an inline
fixture and asserts:
  - Exit code 0.
  - Site data url-history.yaml has a non-empty notes list.
  - The site/data/url-history.yaml shows the published note in 'live' state.

`--skip-math-check` keeps the test focused on the publish pipeline — the
math validator has its own dedicated tests under tools/check_math.py.
"""
import subprocess

import yaml

FIXTURE_ORG = """:PROPERTIES:
:ID:       a3-pub-integration-essay
:END:
#+title: Example Integration Essay
#+date: 2026-11-01
#+HUGO_PUBLISH: t
#+HUGO_SECTION: essays
#+HUGO_SUMMARY: Lorem ipsum.

Lorem ipsum dolor sit amet.
"""


def test_async_publish_deliberate_essay(required_binaries, pub_env,
                                        site_data_dir, a3_pub_sh, tmp_path):
    source = tmp_path / "example-integration-essay.org"
    source.write_text(FIXTURE_ORG)
    rc = subprocess.run(
        [str(a3_pub_sh), "--skip-math-check", "--publish-deliberate", str(source)],
        env=pub_env, capture_output=True, text=True, timeout=300,
    )
    assert rc.returncode == 0, (
        f"a3-pub.sh exited {rc.returncode}\n"
        f"stdout:\n{rc.stdout}\n"
        f"stderr:\n{rc.stderr}"
    )
    manifest_path = site_data_dir / "url-history.yaml"
    manifest = yaml.safe_load(manifest_path.read_text())
    notes = manifest.get("notes") or []
    # A first publish records the note with state='live' + url + history=[]
    # (no PRIOR url). Assert the note is present in live state — the
    # async lifecycle did fire `record-publish`.
    assert any(n.get("state") == "live" for n in notes), (
        f"no live notes after publish; manifest now reads:\n{manifest_path.read_text()}"
    )
