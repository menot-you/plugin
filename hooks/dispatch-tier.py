#!/usr/bin/env python3
"""PreToolUse on Agent: a dispatch that names no model runs on the filled tier.

The rule is plugin/skills/workflow/SKILL.md (<!-- nott:workflow:model-tier -->) and its table
references/model-tiers.md. Which tier a unit's class allows is the dispatcher's judgment;
this hook only makes sure that a tier is set.

A dispatch with no model is never refused. A hook cannot know a unit's class, so the
hook fills `model` with "opus", the tier the table keeps for design, concurrency, security,
persistence, protocol and trust units, through `updatedInput`, and tells the model in
`additionalContext` that Haiku must be named explicitly. Claude Code 2.1.304 applies a PreToolUse `updatedInput` to every tool,
the Agent tool included, after it validates the new input against the tool's schema (read from
the shipped binary, 2026-10-20). The output carries no permissionDecision: the fill approves
nothing on the user's behalf.

A fork is exempt: the Agent tool states that a fork "always runs on your model — a `model`
override is ignored", so a model field on it would record nothing. Workflow `agent()` calls are
built at run time and no hook sees them (plugin/evals/native/BLOCKED.md).

Unreadable input admits: this is a choice check, not a trust boundary.
"""

from __future__ import annotations

import json
import sys


def decide(payload: dict[str, object]) -> int:
    data = payload.get("tool_input")
    if payload.get("tool_name") != "Agent" or not isinstance(data, dict):
        return 0
    if data.get("subagent_type") == "fork":
        return 0
    model = data.get("model")
    if isinstance(model, str) and model.strip():
        return 0
    context = (
        'dispatch-tier: this Agent dispatch named no model, so it runs on model: "opus". Name '
        'model: "haiku" explicitly only for a unit that qualifies for it; the workflow route\'s '
        "model-tiers table says which, its overrides included."
    )
    output = {
        "hookEventName": "PreToolUse",
        "updatedInput": {**data, "model": "opus"},
        "additionalContext": context,
    }
    sys.stdout.write(json.dumps({"hookSpecificOutput": output}) + "\n")
    return 0


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
    except ValueError:
        return 0
    return decide(payload) if isinstance(payload, dict) else 0


if __name__ == "__main__":
    sys.exit(main())
