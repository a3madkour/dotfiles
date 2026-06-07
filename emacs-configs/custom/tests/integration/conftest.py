"""Shared fixtures for dotfiles publish-pipeline integration tests.

These tests exercise the real a3-pub.sh entry point against a host that
has Emacs, xelatex, pandoc, biber, rsvg-convert, and git installed.
Tests skip (rather than fail) when those binaries are absent.
"""
import os
import pathlib
import shutil
import subprocess
import pytest

A3_PUB_SH = pathlib.Path(__file__).parent.parent.parent / "lisp" / "a3-pub.sh"


def _have(cmd):
    return shutil.which(cmd) is not None


@pytest.fixture(scope="session")
def required_binaries():
    """Skip all integration tests when host is missing required binaries."""
    missing = [c for c in ("emacs", "git") if not _have(c)]
    if missing:
        pytest.skip(f"missing required binaries: {missing}")


@pytest.fixture
def site_data_dir(tmp_path):
    """A temp site/data/ dir seeded with empty url-history.yaml."""
    d = tmp_path / "data"
    d.mkdir()
    (d / "url-history.yaml").write_text("notes: []\n")
    return d


@pytest.fixture
def pub_env(site_data_dir):
    """Environment for invoking a3-pub.sh — A3_PUB_SITE_DATA_DIR set."""
    env = os.environ.copy()
    env["A3_PUB_SITE_DATA_DIR"] = str(site_data_dir)
    return env


@pytest.fixture
def a3_pub_sh():
    """Absolute path to a3-pub.sh."""
    return A3_PUB_SH
