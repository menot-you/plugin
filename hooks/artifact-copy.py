#!/usr/bin/env python3
"""PostToolUse on Artifact (Claude Code only): keep a copy of each published page.

Owner order (2026-10-20): the hook copies each artifact that a session publishes
to `~/.nott/artifacts/<basename>` on the host that runs the session. A second copy
goes to `remote` in `~/.nott/artifacts.toml` when that setting exists
(`templates/nott/artifacts.toml` is the example): `host:dir`, sent with scp.

The binding is async, so the copy never holds the turn. The hook writes nothing
to stdout or stderr and exits 0 on every failure: a copy that failed is not a
reason to stop the session. Only Claude Code has the Artifact tool, so no other
client view projects this hook.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# The host part of `remote`: an ssh alias or user@host. A leading "-" would be an option.
HOST = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.@-]*")
SSH_OPTIONS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]


def published_file(payload: object) -> Path | None:
    """The regular file that an Artifact publish names, else None."""
    if not isinstance(payload, dict) or payload.get("tool_name") != "Artifact":
        return None
    data = payload.get("tool_input")
    if not isinstance(data, dict) or data.get("action", "publish") != "publish":
        return None
    name = data.get("file_path")
    if not isinstance(name, str) or not name:
        return None
    path = Path(name)
    # A relative path would resolve against this hook's cwd, and scp reads "x:y" as a host.
    return path if path.is_absolute() and path.is_file() else None


def copy_local(source: Path, home: Path) -> None:
    folder = home / ".nott" / "artifacts"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=folder, prefix=".copy.")
    try:
        with os.fdopen(fd, "wb") as target, source.open("rb") as origin:
            shutil.copyfileobj(origin, target)
        os.replace(temporary, folder / source.name)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def remote_setting(home: Path) -> tuple[str, str] | None:
    """`remote = "host:dir"` from ~/.nott/artifacts.toml, else None."""
    try:
        import tomllib  # Python 3.11 and later. Without it, only the local copy runs.

        document = tomllib.loads((home / ".nott" / "artifacts.toml").read_text())
    except (ImportError, OSError, ValueError):
        return None
    value = document.get("remote")
    if not isinstance(value, str) or ":" not in value:
        return None
    host, folder = value.split(":", 1)
    # A relative folder starts in the remote home. The remote shell does not expand "~".
    folder = folder.removeprefix("~/")
    if not HOST.fullmatch(host) or not folder or folder.startswith("-"):
        return None
    return host, folder


def copy_remote(source: Path, host: str, folder: str) -> None:
    quiet = {
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
    }
    made = subprocess.run(
        ["ssh", *SSH_OPTIONS, host, "mkdir -p -m 700 -- " + shlex.quote(folder)],
        check=False,
        timeout=25,
        **quiet,
    )
    if made.returncode != 0:
        return
    subprocess.run(
        [
            "scp",
            "-q",
            *SSH_OPTIONS,
            "--",
            str(source),
            # The folder only: legacy scp gives the remote path to a shell, and the
            # file name comes from the model. scp takes the remote name from the source.
            f"{host}:{folder.rstrip('/')}/",
        ],
        check=False,
        timeout=25,
        **quiet,
    )


def main() -> None:
    source = published_file(json.loads(sys.stdin.read()))
    if source is None:
        return
    home = Path.home()
    try:
        copy_local(source, home)
    except OSError:
        pass  # The remote copy does not depend on the local one.
    target = remote_setting(home)
    if target is not None:
        copy_remote(source, *target)


if __name__ == "__main__":
    try:
        main()
    except BaseException:  # noqa: BLE001, S110 - the hook must exit 0 on every failure.
        pass
    sys.exit(0)
