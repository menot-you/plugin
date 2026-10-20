#!/usr/bin/env python3
"""nott-bash-guard v2 — with the two guards round 2 demanded.

G1: does not touch output the harness has ALREADY persisted (<persisted-output>), nor
    a tool_response carrying persistedOutputPath: the harness already elided with a
    handle, and rewriting over it can only make things worse.
G2: does not apply when the command is READING one of the guard's own logs, nor to
    discovery listings or commands that already filter at the source. Hiding
    discovered paths can turn an available input into an apparent blocker;
    filtering a recovered log again also prevents recovery.
"""

import hashlib
import json
import os
import pathlib
import re
import sys
import tempfile

BUDGET_FRAC = 0.02
HEAD_TOK, TAIL_TOK = 1500, 500  # above the floor the agent still sees >= 2,000 tokens
MAXLEN = 300  # a signal line outside the head and tail windows
FLOOR = 2000

STRONG = re.compile(
    r"""(
   \b(?:error|fatal|panic|traceback|exception)\b | \bFAILED\b | \bFAIL\b | ^E\s{2,}
 | \bassert(?:ion)?\s*(?:error|failed) | \b\d+\s+(?:passed|failed|error|skipped)
 | \b(?:refused|denied|permission\ denied|not\ found|no\ such\ file)\b
 | \bexit(?:\ code)?[=:\ ]\s*[1-9] | \b(?:GREEN|RED)\b
 | ^\s*[-+]{3}\s | ^@@ | \b(?:NERR|E\d{3,})[-_]?\d*\b
)""",
    re.IGNORECASE | re.VERBOSE,
)
NOISE = re.compile(
    r"""(
   ^\s*\++\s | ^\s*\[?\s*\d+%
 | ^\s*(?:Requirement|Collecting|Downloading|Installing|Building|Resolved|Prepared|Audited)\b
 | ^\s*\.{3,}\s*$
)""",
    re.VERBOSE,
)
USEFUL = re.compile(r"(\.(?:py|rs|sh|toml|md|json|ya?ml|txt):\d+|^\s*\$|=>|->)")

LOG_DIRNAME = "nott/bash-output"
# Discovery and explicit filtering return the signal the caller requested.
# Native client output limits still apply; this hook must not select paths away.
PRESERVE_OUTPUT = re.compile(
    r"^\s*(?:sudo\s+)?(?:ls|find|grep|rg|ag|head|tail|wc|jq|cut|awk|sed\s+-n|comm|diff)\b"
)


def score(l: str) -> int:
    if NOISE.search(l):
        return 0
    if STRONG.search(l):
        return 2
    if USEFUL.search(l):
        return 1
    return 0


def elide(text: str, log_path: str) -> str:
    raw = text.splitlines()
    n = len(raw)
    total = sum(len(l) for l in raw) // 4
    if total <= FLOOR:
        return "\n".join(raw)
    # The head and tail windows count characters, not lines, so the agent sees
    # HEAD_TOK + TAIL_TOK tokens even when one line is longer than a window.
    head: dict[int, int] = {}
    tail: dict[int, int] = {}
    chars = HEAD_TOK * 4
    for i in range(n):
        if chars <= 0:
            break
        head[i] = min(len(raw[i]), chars)
        chars -= len(raw[i])
    chars = TAIL_TOK * 4
    for i in range(n - 1, -1, -1):
        if chars <= 0:
            break
        tail[i] = min(len(raw[i]), chars)
        chars -= len(raw[i])

    def show(i: int) -> str:
        l = raw[i]
        window = i in head or i in tail
        h, t = (head.get(i, 0), tail.get(i, 0)) if window else (MAXLEN, 0)
        if h + t >= len(l):
            return l
        return l[:h] + f" […{len(l) - h - t}c] " + l[len(l) - t :]

    keep = set(head) | set(tail) | {i for i, l in enumerate(raw) if score(l) == 2}
    budget = max(30, int(total * BUDGET_FRAC))
    used = sum(len(show(i)) for i in keep) // 4
    for i, l in enumerate(raw):
        if i in keep or used >= budget:
            continue
        if score(l) == 1:
            keep.add(i)
            used += len(show(i)) // 4
    sel = sorted(keep)
    dropped = n - len(sel)
    if not dropped:
        return "\n".join(show(i) for i in range(n))
    return (
        f"[nott-bash-guard: {len(sel)}/{n} lines shown, {dropped} elided; "
        f"full output: {log_path}]\n" + "\n".join(show(i) for i in sel)
    )


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeError, OSError):
        return
    resp = payload.get("tool_response")
    if not isinstance(resp, dict):
        return

    # G1: o harness ja persistiu / ja elidiu.
    if resp.get("persistedOutputPath") or resp.get("rawOutputPath"):
        return
    out = resp.get("stdout") or ""
    if not isinstance(out, str):
        return
    if "<persisted-output>" in out[:200] or "nott-bash-guard:" in out[:200]:
        return

    cmd = (payload.get("tool_input") or {}).get("command", "") or ""
    # G2: cascade -- the command reads a guard log, or is already the filtering itself.
    if LOG_DIRNAME in cmd or ".nott/logs" in cmd:
        return
    first = cmd.strip().splitlines()[0] if cmd.strip() else ""
    if PRESERVE_OUTPUT.match(first):
        return

    if len(out) // 4 <= FLOOR:
        return  # 2,000-token floor: 93% of 30-day cuts lifted; 7% remain (measured 2026-10-19)

    # Host-owned state, isolated by session; never write diagnostics into the project.
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR")
    if not project_dir:
        return
    session = payload.get("session_id")
    if not isinstance(session, str) or not 1 <= len(session) <= 256:
        return
    state_home = os.environ.get("XDG_STATE_HOME")
    if not state_home:
        home = os.environ.get("HOME")
        if not home:
            return
        state_home = str(pathlib.Path(home) / ".local/state")
    state, project = pathlib.Path(state_home), pathlib.Path(project_dir)
    if not state.is_absolute() or not project.is_absolute():
        return
    temporary = None
    try:
        log_dir = state / LOG_DIRNAME / hashlib.sha256(session.encode()).hexdigest()
        log = log_dir / f"bash-{hashlib.sha256(out.encode()).hexdigest()}.log"
        if log_dir.resolve().is_relative_to(project.resolve()):
            return
        new = elide(out, str(log))
        if new != out and not new.startswith("[nott-bash-guard:"):
            new = f"[nott-bash-guard: output shortened; full output: {log}]\n" + new
        if len(new) >= len(out):
            return
        for directory in (state, state / "nott", state / LOG_DIRNAME, log_dir):
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            info = directory.stat()
            if directory.is_symlink() or info.st_uid != os.getuid():
                return
            # `state` and `state/nott` are SHARED roots: whatever ran first on the box
            # created them -- several NOTT hooks reach them with a plain `mkdir -p`, so
            # their mode is whatever umask was in force -- and this hook has no business
            # chmod-ing a directory it shares. Demanding 0o022 there refused the owner's
            # own machine (`nott:nott 775`, a group of one) and killed the guard in
            # silence: measured 2026-09-17, `bash-output/` had never been created. What
            # actually redirects this path is a symlink or a foreign owner, both refused
            # just above, or a world-writable root, still refused here. The two
            # directories this hook owns outright keep the strict mask, and the logs
            # themselves are 0600 -- that is where the content is protected.
            if directory in (state / LOG_DIRNAME, log_dir):
                mask = 0o077
            else:
                mask = 0o002
            if info.st_mode & mask:
                return
        if log.is_symlink():
            return
        if log.exists():
            if not log.is_file() or log.stat().st_mode & 0o077:
                return
            if log.stat().st_uid != os.getuid() or log.read_bytes() != out.encode():
                return
        else:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=log_dir, delete=False
            ) as stream:
                temporary = pathlib.Path(stream.name)
                stream.write(out)
            temporary.replace(log)
    except (OSError, ValueError):
        return
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass

    updated = dict(resp)
    updated["stdout"] = new
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "updatedToolOutput": updated,
                }
            }
        )
    )


if __name__ == "__main__":
    main()
