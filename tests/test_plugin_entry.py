"""`plugin/scripts/plugin.py <verb>` is the packager's and the installer's one entry.

The script canon reads `<folder>/<noun>.<ext> <verb>` and has no aliases: the two
scripts it replaces are gone, their modules under `scripts/plugin/` are not entry
points of their own, and a call without a known verb is a usage error.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
ENTRY = SCRIPTS / "plugin.py"


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(ENTRY), *args],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )


@pytest.mark.parametrize("args", [(), ("--verify", "/nonexistent"), ("package",)])
def test_a_call_without_a_known_verb_is_a_usage_error(args: tuple[str, ...]) -> None:
    done = run(*args)
    assert done.returncode == 2, done.stderr
    assert done.stdout == ""
    assert "usage: plugin.py" in done.stderr


def test_show_prints_the_client_matrix() -> None:
    done = run("show")
    assert done.returncode == 0, done.stderr
    assert done.stdout.startswith("| client | hook script |")


@pytest.mark.parametrize("verb", ["verify", "admit"])
def test_a_missing_bundle_is_a_refusal(verb: str, tmp_path: Path) -> None:
    done = run(verb, str(tmp_path / "absent"))
    assert done.returncode == 2, done.stderr
    assert "PACKAGE REFUSED" in done.stderr


def test_rollback_without_its_receipt_is_a_usage_error() -> None:
    done = run("rollback")
    assert done.returncode == 2
    assert "receipt" in done.stderr


@pytest.mark.parametrize("retired", ["package-plugin.py", "install-plugin.py"])
def test_the_retired_scripts_have_no_alias(retired: str) -> None:
    assert not (SCRIPTS / retired).exists()


@pytest.mark.parametrize("module", ["package.py", "install.py"])
def test_the_modules_are_not_entry_points(module: str) -> None:
    text = (SCRIPTS / "plugin" / module).read_text()
    assert 'if __name__ == "__main__"' not in text
    assert not text.startswith("#!")
