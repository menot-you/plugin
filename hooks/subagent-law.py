#!/usr/bin/env -S python3 -B
"""SubagentStart: give every subagent the subagent law.

The main law reaches the main thread only: the SessionStart hook and
--append-system-prompt-file do not reach a subagent's request. Claude Code 2.1.304 runs SubagentStart hooks for each
Agent tool subagent of any type and adds each hook's
hookSpecificOutput.additionalContext to that subagent's context. The text
stays small and holds only what a delegated worker needs.

The subagent law has one home: the body of plugin/agents/worker.md (U1). This
hook keeps only its header line. It reads worker.md at each call and keeps no
copy of the rules.

A sector agent (agent_type "nott:<sector>") also gets the team lessons of its
sector: the file ~/.nott/agents/<sector>.md, which the nMEMORY daemon writes. The hook reads it from disk and never calls nMEMORY. An unreadable
file adds one RULES STALE line. A missing file adds that line only when
~/.nott/rules.state is older than 10 minutes or names write errors.
"""

import json
import re
import sys
import time
from pathlib import Path

HEADER = (
    "[NOTT plugin · SubagentStart hook subagent-law.py — the subagent law, "
    "in force for this subagent]"
)
WORKER = Path(__file__).resolve().parents[1] / "agents" / "worker.md"


def law() -> str:
    """The header line, then the body of worker.md, read fresh at each call. A
    missing, unreadable or frontmatter-less file warns, like an unreadable lessons
    file does, instead of silently shipping the header alone."""
    try:
        text = WORKER.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return (
            HEADER
            + f"\n\nWORKER STALE: {WORKER} is unreadable. This subagent gets no rules.\n"
        )
    parts = text.split("---\n", 2)
    body = parts[2] if len(parts) == 3 and parts[0] == "" else ""
    if not body.strip():
        return (
            HEADER
            + f"\n\nWORKER STALE: {WORKER} has no frontmatter body. This subagent gets no rules.\n"
        )
    return HEADER + "\n\n" + body.strip() + "\n"


#: The bytes the lessons part may add to the law (subagent-law-contract checks it).
LESSONS_CEILING = 6144
CUT = "\n[lessons cut at the 6144-byte limit]\n"


#: The same pattern as SECTOR_NAME in the rule generator (rules.py).
SECTOR_NAME = r"[a-z0-9][a-z0-9-]*"


def writer_trouble() -> str | None:
    """Why the rule writer looks unhealthy, from ~/.nott/rules.state, or None. No
    state file means no writer on this host: that is not trouble."""
    path = Path.home() / ".nott" / "rules.state"
    try:
        age = time.time() - path.stat().st_mtime
        errors = json.loads(path.read_text("utf-8")).get("errors") or []
    except FileNotFoundError:
        return None
    except (OSError, ValueError, AttributeError):
        return f"{path} cannot be read"
    if age > 600:
        return f"{path} last checked {int(age // 60)} min ago"
    if errors:
        return str(errors[0])
    return None


def sector_lessons(payload: str) -> str:
    """The lessons file of the subagent's sector, "" when there is none, or one
    warning line when the file exists but cannot be read."""
    try:
        kind = json.loads(payload).get("agent_type", "")
    except (ValueError, AttributeError):
        return ""
    match = re.fullmatch(
        rf"nott:({SECTOR_NAME})", kind if isinstance(kind, str) else ""
    )
    if match is None:
        return ""
    path = Path.home() / ".nott" / "agents" / f"{match.group(1)}.md"
    try:
        text = path.read_text("utf-8")
    except FileNotFoundError:
        stale = writer_trouble()
        return "" if stale is None else f"\nRULES STALE: {path} is missing; {stale}.\n"
    except (OSError, UnicodeDecodeError):
        return f"\nRULES STALE: {path} is unreadable; the nMEMORY daemon may be down.\n"
    head = f"\n[Team lessons of this sector, from ~/.nott/agents/{match.group(1)}.md]\n"
    part = head + text
    if len(part.encode("utf-8")) > LESSONS_CEILING:
        room = LESSONS_CEILING - len(CUT.encode("utf-8"))
        part = part.encode("utf-8")[:room].decode("utf-8", errors="ignore") + CUT
    return part


try:
    PAYLOAD = sys.stdin.read()
except (OSError, UnicodeDecodeError):
    PAYLOAD = ""

json.dump(
    {
        "hookSpecificOutput": {
            "hookEventName": "SubagentStart",
            "additionalContext": law() + sector_lessons(PAYLOAD),
        }
    },
    sys.stdout,
)
