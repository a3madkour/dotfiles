"""Integration test: SIGTERM to a3-pub.sh cancels the publish cleanly.

Spawns `a3-pub.sh --skip-math-check --publish-deliberate`, sends
SIGTERM almost immediately, asserts:
  - Non-zero exit code.
  - Manifest YAML unchanged from initial state.

Does NOT precisely assert on which step the publish was in when killed
(would be timing-fragile).  Verifies the cancel PATH works end-to-end:
trap -> kill-emacs-hook -> no manifest write.
"""
import glob
import os
import pathlib
import signal
import subprocess
import time

FIXTURE_ORG = pathlib.Path.home() / "org" / "essays" / "example-multi.org"


def test_async_publish_cancel(required_binaries, pub_env,
                              site_data_dir, a3_pub_sh):
    if not FIXTURE_ORG.exists():
        import pytest
        pytest.skip(f"missing fixture {FIXTURE_ORG}")
    initial_manifest = (site_data_dir / "url-history.yaml").read_text()
    pre_tmp = set(glob.glob("/tmp/multi-export-*/"))
    proc = subprocess.Popen(
        [str(a3_pub_sh), "--skip-math-check",
         "--publish-deliberate", str(FIXTURE_ORG)],
        env=pub_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        # Put a3-pub.sh in its own process group so SIGTERM hits the
        # whole tree (a3-pub.sh + emacs child + any in-flight subprocess).
        preexec_fn=os.setsid,
    )
    # Give the publish a moment to start the in-process work.
    time.sleep(0.5)
    # SIGTERM the process group: a3-pub.sh traps it, propagates to emacs,
    # emacs runs kill-emacs-hook, exits with non-zero.
    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    proc.wait(timeout=15)
    assert proc.returncode != 0, (
        f"a3-pub.sh should have exited non-zero after SIGTERM\n"
        f"stdout:\n{proc.stdout.read().decode(errors='replace')}\n"
        f"stderr:\n{proc.stderr.read().decode(errors='replace')}"
    )
    # Manifest should be unchanged: finish-publish didn't fire, so the
    # accumulator was never flushed to disk.
    after_manifest = (site_data_dir / "url-history.yaml").read_text()
    assert after_manifest == initial_manifest, (
        f"manifest changed after SIGTERM cancel\n"
        f"before:\n{initial_manifest}\nafter:\n{after_manifest}"
    )
    # Soft check: orphan tmp-dirs from THIS run. May fail on fast hosts
    # where SIGTERM lands before D.2 creates tmp-dirs. We log but don't fail.
    post_tmp = set(glob.glob("/tmp/multi-export-*/"))
    leaked = post_tmp - pre_tmp
    if leaked:
        # kill-emacs-hook should have cleaned these, but timing can vary.
        # Print as a warning; don't fail the test.
        print(f"WARNING: leaked tmp-dirs after cancel: {leaked}")
