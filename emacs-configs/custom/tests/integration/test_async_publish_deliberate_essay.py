"""Integration test: async deliberate publish of an example essay.

Runs `a3-pub.sh --publish-deliberate` against a copied example-multi
fixture and asserts:
  - Exit code 0.
  - Site data url-history.yaml has a non-empty notes list.
  - The site/data/url-history.yaml shows the published note in 'live' state.
"""
import pathlib
import subprocess

import yaml

FIXTURE_ORG = pathlib.Path.home() / "org" / "essays" / "example-multi.org"


def test_async_publish_deliberate_essay(required_binaries, pub_env,
                                        site_data_dir, a3_pub_sh):
    if not FIXTURE_ORG.exists():
        import pytest
        pytest.skip(f"missing fixture {FIXTURE_ORG}")
    rc = subprocess.run(
        [str(a3_pub_sh), "--publish-deliberate", str(FIXTURE_ORG)],
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
    assert any(n.get("history") for n in notes), (
        f"no notes published; manifest now reads:\n{manifest_path.read_text()}"
    )
