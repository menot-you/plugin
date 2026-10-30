#!/usr/bin/env -S python3 -B
"""UserPromptSubmit: one spool line for each owner prompt, for the node host's requests view.

ONLY WHERE THE HOST READS IT. The hook writes in an interactive Claude Code session
(`CLAUDE_CODE_ENTRYPOINT=cli`) that owns a messaging socket, outside an nSPAWN run. Everywhere
else it is silent. The owner gate is `owner_prompt` of system1-suggest.py, as
nmemory-recall.py applies it: a subagent, an nSPAWN child, a `-p` run and a message the client
delivers for someone else (a notification, a cross-session, teammate or agent message) open no
entry. The idle-handoff prompt of idle-handoff.ts opens none either.

THE PLACE. `$XDG_RUNTIME_DIR/nott/requests/`, outside the node unit's runtime directory
(`nott-node`), which systemd deletes at each restart. The hook creates it and its parent
(mode 700) when they are missing, and never writes through a link.

THE LINE. One JSON line appended to `<session_id>.prompts.jsonl` (mode 600, a regular file,
never through a link): plugin/schema/prompt-spool.v1.json. `prompt_id` is the payload's own
id. A whole prompt `aceito N`, `N. aceito` or `accept N` writes an `accept` line with that
number. The text is the first 300 characters, or `<withheld>` when the secret scrubber of
system1-suggest.py finds a credential or fails. Like system1-suggest.py, the hook redacts
nothing.

THE LINE COMES FIRST. The payload is read before the gate module loads, and the line is
written as soon as its fields are known: nothing slow runs after it. The one deadline (4 s of
the 5 s entry) fires once; when it strikes the scrubber, the text is withheld and the line is
still written in the second that is left.

A LINE THAT IS NOT WRITTEN IS SEEN. When the hook owes a prompt a line and cannot write it, it
prints why, so the agent can tell the owner, and leaves the session's spool in place, empty
when it is new, if it can. `state.sh judge` looks for the line with the prompt_id of each owner
prompt that session-state.sh kept, and paints `prompt not recorded` red for a prompt with no
line, also when this hook could leave no spool in the requests directory. The hook always
exits 0.

WHAT THE AGENT SEES. A prompt line prints `NOTT: prompt <prompt_id> recorded. Set its
expectation with nott_prompt_set.` An accept line prints nothing.
"""

from __future__ import annotations

import contextlib
import importlib.util
import json
import os
import re
import signal
import stat
import sys
import time
from pathlib import Path
from types import ModuleType

HERE = Path(__file__).resolve().parent
#: The read, the gate load and the scrub, inside the 5 s hook entry; Python start is not in it.
DEADLINE = 4.0
TEXT_LIMIT = 300
WITHHELD = "<withheld>"
SAFE_ID = re.compile(r"[A-Za-z0-9_-]{1,128}")
#: The whole prompt only (owner, live plan): `aceito N`, `N. aceito`, `accept N`.
ACCEPT = re.compile(
    r"\s*(?:(?:aceito|accept)\s+#?([1-9][0-9]{0,5})|#?([1-9][0-9]{0,5})\.\s*aceito)\s*",
    re.IGNORECASE,
)
#: idle-handoff.ts `handoffPrompt`: its first line, and its last line with the nonce.
HANDOFF_FIRST = "The session has been idle and the prompt cache is about to expire."
HANDOFF_LAST = re.compile(r"HANDOFF-DONE [0-9a-f-]{36}")
RECORDED = "NOTT: prompt {} recorded. Set its expectation with nott_prompt_set."
NOT_RECORDED = "NOTT: this prompt was not recorded: {}."


class Unrecorded(Exception):
    """An owner prompt that is owed a spool line and does not get one."""


class Deadline(BaseException):
    """Not an `Exception`: no handler below the boundary swallows the alarm."""


def _expire(_signum: int, _frame: object) -> None:
    raise Deadline


def _load(name: str, filename: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    if spec is None or spec.loader is None:
        raise ImportError(filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def kind_of(prompt: str) -> tuple[str, int | None] | None:
    """`("accept", N)`, `("prompt", None)`, or None for the idle-handoff prompt."""
    lines = prompt.strip().split("\n")
    if lines[0] == HANDOFF_FIRST and HANDOFF_LAST.fullmatch(lines[-1]):
        return None
    accepted = ACCEPT.fullmatch(prompt)
    if accepted:
        return "accept", int(accepted.group(1) or accepted.group(2))
    return "prompt", None


def text_of(prompt: str, suggest: ModuleType) -> str:
    """The first TEXT_LIMIT characters, or WITHHELD. The scan has the margin of
    system1-suggest.py, for a credential that crosses the cut."""
    scanned = prompt[: TEXT_LIMIT + suggest.SCAN_MARGIN]
    try:
        credential = suggest.scrubbed(scanned) != scanned or any(
            pattern.search(scanned)
            for pattern in (suggest.WORDS, suggest.TOKEN, suggest.BASIC, suggest.GITHUB)
        )
    except Exception:  # noqa: BLE001 — a scrubber that fails withholds the text (live plan)
        credential = True
    except (
        Deadline
    ):  # out of time is a scrubber that failed: the text goes, the line stays
        credential = True
    return WITHHELD if credential else prompt[:TEXT_LIMIT]


def directory(requests: Path) -> None:
    """The requests directory and its parent, created mode 700 when missing; a link or
    anything else that is not a directory there is refused."""
    for path in (requests.parent, requests):
        try:
            os.mkdir(path, 0o700)
            os.chmod(path, 0o700, follow_symlinks=False)
        except FileExistsError:
            pass
        if not stat.S_ISDIR(os.lstat(path).st_mode):
            raise Unrecorded(f"{path.name} is not a directory")


def append(path: Path, line: bytes) -> None:
    """One whole line at the end of the spool: never through a link, never to a file
    that is not regular, and always mode 600."""
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK
    fd = os.open(path, flags | os.O_CLOEXEC, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise Unrecorded("the spool is not a regular file")
        os.fchmod(fd, 0o600)
        written = os.write(fd, line)
    finally:
        os.close(fd)
    if written != len(line):
        raise Unrecorded("the spool took part of the line")


def payload_of(raw: str) -> dict[str, object]:
    try:
        payload = json.loads(raw)
    except ValueError as error:
        raise Unrecorded("the payload is not JSON") from error
    if not isinstance(payload, dict) or not isinstance(payload.get("prompt"), str):
        raise Unrecorded("the payload carries no prompt")
    return payload


def spool_of(payload: dict[str, object], requests: Path) -> Path | None:
    """The session's spool, or None when the session_id is not a safe file name."""
    session = payload.get("session_id")
    if not isinstance(session, str) or not SAFE_ID.fullmatch(session):
        return None
    return requests / f"{session}.prompts.jsonl"


def mark(spool: Path) -> None:
    """The spool left in place, empty when it is new, for the judge of state.sh: a prompt
    that got no line is then a session the judge sees. Nothing more can be done for it."""
    with contextlib.suppress(OSError, Unrecorded):
        directory(spool.parent)
        append(spool, b"")


def capture(
    payload: dict[str, object], suggest: ModuleType, socket: str, requests: Path
) -> str:
    """The line for the agent ("" for none); raises Unrecorded for a line it owes."""
    if not suggest.owner_prompt(payload):
        return ""
    prompt = str(payload["prompt"])
    kind = kind_of(prompt)
    if kind is None:
        return ""
    session, prompt_id = payload.get("session_id"), payload.get("prompt_id")
    spool = spool_of(payload, requests)
    if spool is None:
        raise Unrecorded("the session_id is not a safe file name")
    if not isinstance(prompt_id, str) or not SAFE_ID.fullmatch(prompt_id):
        raise Unrecorded("the payload carries no usable prompt_id")
    cwd = payload.get("cwd")
    record = {
        "v": 1,
        "kind": kind[0],
        "session_id": session,
        "socket": socket,
        "cwd": cwd if isinstance(cwd, str) and cwd.startswith("/") else os.getcwd(),
        "prompt_id": prompt_id,
        "at": time.time_ns() // 1_000_000,
        "text": text_of(prompt, suggest),
        "number": kind[1],
    }
    line = json.dumps(record, separators=(",", ":")) + "\n"
    try:
        directory(requests)
        append(spool, line.encode())
    except OSError as error:
        raise Unrecorded(f"the spool write failed ({error.strerror})") from error
    return RECORDED.format(prompt_id) if kind[0] == "prompt" else ""


def main() -> str:
    socket = os.environ.get("CLAUDE_CODE_MESSAGING_SOCKET") or ""
    runtime = os.environ.get("XDG_RUNTIME_DIR") or ""
    requests = Path(runtime, "nott", "requests")
    if (
        os.environ.get("CLAUDE_CODE_ENTRYPOINT") != "cli"
        or not socket
        or not runtime.startswith("/")
    ):
        return ""
    # Past the gates a prompt may be owed a line, so a failure is said, never swallowed, and
    # the spool of a session it names is left for the judge.
    signal.signal(signal.SIGALRM, _expire)
    signal.setitimer(signal.ITIMER_REAL, DEADLINE)
    spool: Path | None = None
    try:
        payload = payload_of(sys.stdin.read())
        spool = spool_of(payload, requests)
        try:
            suggest = _load("nott_hooks_system1_suggest", "system1-suggest.py")
        except Exception as error:  # noqa: BLE001 — reported to the agent below
            raise Unrecorded(
                f"system1-suggest.py did not load ({type(error).__name__})"
            ) from error
        return capture(payload, suggest, socket, requests)
    except Unrecorded as error:
        said = NOT_RECORDED.format(error)
    except Deadline:
        said = NOT_RECORDED.format("the hook ran out of time")
    except Exception as error:  # noqa: BLE001 — reported to the agent, never swallowed
        said = NOT_RECORDED.format(f"the hook failed ({type(error).__name__})")
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    if spool is not None:
        mark(spool)
    return said


if __name__ == "__main__":
    try:
        out = main()
    except BaseException:  # noqa: BLE001 — the process boundary of a hook that never blocks
        out = ""
    with contextlib.suppress(BaseException):
        if out:
            sys.stdout.write(out + "\n")
            sys.stdout.flush()
    os._exit(0)
