#!/usr/bin/env -S python3 -B
"""SubagentStop: record the real effort of each subagent.

The owner must be able to see that a plugin agent runs at the effort of its
class, not at the session's max. Claude Code's SubagentStop payload carries
session_id, agent_id, agent_type and effort.level; this hook appends them, with
whether CLAUDE_CODE_EFFORT_LEVEL is set and its level, as one JSON line to
${XDG_STATE_HOME:-$HOME/.local/state}/nott/subagent-record.jsonl.

The file is an audit log that no module queries. The hook reads only its stdin
payload and its environment, never a transcript path. It prints nothing and
exits 0 on every failure, so it can never hold a subagent's stop.
Python 3.9-clean: the system python of a host may be that old.
"""

import datetime
import json
import os
import sys

#: The most characters a recorded string keeps.
FIELD_LIMIT = 128


def text(value):
    """A payload or environment string, cut at FIELD_LIMIT; None for any other value."""
    return value[:FIELD_LIMIT] if isinstance(value, str) else None


def record(payload):
    effort = payload.get("effort")
    level = effort.get("level") if isinstance(effort, dict) else None
    env_level = os.environ.get("CLAUDE_CODE_EFFORT_LEVEL")
    now = datetime.datetime.now(datetime.timezone.utc)  # noqa: UP017 - datetime.UTC needs 3.11, node views run 3.9.
    return {
        "time": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "session_id": text(payload.get("session_id")),
        "agent_id": text(payload.get("agent_id")),
        "agent_type": text(payload.get("agent_type")),
        "effort_level": text(level),
        "env_effort_set": env_level is not None,
        "env_effort_level": text(env_level),
    }


def log_path():
    """The XDG state directory; a relative XDG_STATE_HOME is ignored, as the spec says."""
    base = os.environ.get("XDG_STATE_HOME")
    if not base or not os.path.isabs(base):
        base = os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "nott", "subagent-record.jsonl")


def main():
    try:
        payload = json.loads(sys.stdin.read())
        if not isinstance(payload, dict):
            return
        line = json.dumps(record(payload), sort_keys=True) + "\n"
        path = log_path()
        os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
        flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(path, flags, 0o600)
        try:
            os.write(fd, line.encode("utf-8"))
        finally:
            os.close(fd)
    except Exception:  # noqa: BLE001, S110 - an audit log never fails the stop.
        pass


if __name__ == "__main__":
    main()
    sys.exit(0)
