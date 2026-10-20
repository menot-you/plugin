#!/usr/bin/env python3
"""PreToolUse on the nMEMORY tools: only the main session calls them.

An inherited session gets memory only from the brief of
its parent. It reports facts to the parent, and the parent captures them. This hook
denies each nMEMORY MCP tool call of an inherited session:

- a subagent of the Agent tool or a workflow agent: the payload has agent_id.
  Claude Code 2.1.304 documents agent_id in its hook input schema: "Present only
  when the hook fires from within a subagent ... Absent for the main thread, even
  in --agent sessions." agent_type alone is the main thread of an --agent session.
- an nSPAWN child or a workflow run: NOTT_NSPAWN_RUN_ID is in the environment
  (mcps/nspawn/nspawn/child.py RUN_ID_ENV). nMEMORY refuses these on its own too.

An app node is a main session: `nspawn route start` starts its adapter without
the run marker (mcps/nspawn/nspawn/route.py route_start), and its own tool calls
have no agent_id. A guard fails closed: a payload that the hook cannot read, or
any other error, denies the call.
"""

from __future__ import annotations

import json
import os
import sys

REASON = (
    "nMEMORY refused: an inherited session (a subagent, an nSPAWN child or a "
    "workflow agent) has no nMEMORY. Use the memory in "
    "your brief. If you need more, ask your parent. Report each fact, decision and "
    "blocker to your parent: the parent captures it."
)
UNREAD = "nMEMORY refused: the hook could not read the tool call as a JSON object."
FAILED = "nMEMORY refused: the hook failed, so it cannot tell the main session apart."


def refusal(raw: bytes) -> str | None:
    """The reason to deny the call, or None to let it run."""
    try:
        payload = json.loads(raw)
    except ValueError:
        return UNREAD
    if not isinstance(payload, dict):
        return UNREAD
    inherited = os.environ.get("NOTT_NSPAWN_RUN_ID") or payload.get("agent_id")
    return REASON if inherited else None


def main() -> int:
    try:
        reason = refusal(sys.stdin.buffer.read())
    except Exception:  # noqa: BLE001 — a guard fails closed
        reason = FAILED
    if reason is None:
        return 0
    # Two channels: `defaultMode: bypassPermissions` skips the JSON permission
    # decision (measured 2026-08-29, pynott-branch-lock.sh). Exit 2 with the reason
    # on stderr is the block; the JSON is courtesy.
    sys.stderr.write(reason + "\n")
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    return 2


sys.exit(main())
