#!/usr/bin/env -S python3 -B
"""Send recognized reviews to a counted door before the tool can run."""

from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

REVIEWERS = frozenset(
    {
        "security-reviewer",
        "ux-reviewer",
        "ui-reviewer",
        "python-reviewer",
        "swift-reviewer",
        "pr-test-analyzer",
        "silent-failure-hunter",
        "plan-reviewer",
        "adversarial",
        "qa",
    }
)
CANDIDATE = re.compile(r"^Candidate:", re.MULTILINE)
INLINE = re.compile(
    r"\bCandidate:\s*(?:[^\s@]+@)?(?:[0-9a-fA-F]{64}|[0-9a-fA-F]{40})(?![0-9a-fA-F])"
)
DOOR = "Use nspawn_review_start with subject and candidate, or a new unnamed Agent reviewer with one Candidate: <subject>@<40 or 64 hex> line."


def parser() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "review_cap_dispatch", Path(__file__).with_name("dispatch-tier.py")
    )
    if spec is None or spec.loader is None:
        raise ImportError("dispatch-tier.py has no loader")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def context(message: str) -> int:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "additionalContext": "review-cap: " + message,
                }
            }
        )
    )
    return 0


def refuse(message: str) -> int:
    reason = "review-cap: REFUSED — " + message + " " + DOOR
    print(reason, file=sys.stderr)
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    return 2


def strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [part for item in value.values() for part in strings(item)]
    if isinstance(value, list):
        return [part for item in value for part in strings(item)]
    return []


def recognized(text: str) -> bool:
    return CANDIDATE.search(text) is not None or INLINE.search(text) is not None


def reviewer(kind: Any, module: ModuleType) -> bool:
    return isinstance(kind, str) and (
        kind.rsplit(":", 1)[-1] in REVIEWERS or bool(module.reviewer(kind))
    )


def count(prompt: str) -> int:
    apps = os.environ.get("NOTT_MCP_APPS_DIR")
    binary = (
        str(Path(apps) / "nspawn/current/bin/nspawn")
        if apps
        else shutil.which("nspawn")
    )
    if binary is None or not os.access(binary, os.X_OK):
        return context(
            "NOT COUNTED: nSPAWN is absent. Install nSPAWN with review admit before the next review."
        )
    lines = "".join(
        line + "\n"
        for line in prompt.splitlines()
        if line.startswith(("Candidate:", "Spec revision:"))
    )
    try:
        result = subprocess.run(
            [binary, "review", "admit", "--stdin"],
            input=lines,
            text=True,
            capture_output=True,
            timeout=5,
            check=False,
        )
    except FileNotFoundError:
        return context(
            "NOT COUNTED: nSPAWN is absent. Install nSPAWN with review admit before the next review."
        )
    except (OSError, subprocess.TimeoutExpired, UnicodeError):
        return refuse(
            "nSPAWN admission failed or exceeded 5 s. Check the store and executable, then retry the same head."
        )
    if result.returncode != 0:
        reason = result.stderr.strip()
        if result.returncode == 2 and reason.splitlines()[:1] == [
            "unknown command: nspawn review admit"
        ]:
            return context(
                "NOT COUNTED: this nSPAWN has no review admit. Install a release with that verb."
            )
        if result.returncode == 2 and reason.startswith("ReviewCandidateInvalid:"):
            return refuse(reason)
        return refuse(
            "nSPAWN could not count this head. Check its store and retry the same head."
        )
    try:
        answer = json.loads(result.stdout)
    except ValueError:
        return refuse(
            "nSPAWN returned malformed admission JSON. Check its release and retry."
        )
    if (
        not isinstance(answer, dict)
        or not isinstance(answer.get("subject"), str)
        or re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", str(answer.get("candidate")))
        is None
        or type(answer.get("budget")) is not int
        or answer["budget"] < 1
        or type(answer.get("heads")) is not int
        or answer["heads"] < 1
        or type(answer.get("counted")) is not bool
    ):
        return refuse(
            "nSPAWN returned a malformed admission answer. Check its release and retry."
        )
    return context(f"{answer['subject']} head {answer['heads']}")


def workflow(data: dict[str, Any], cwd: Any, module: ModuleType) -> int:
    try:
        src = module.script_of(data, cwd)
        found, dynamic = module.calls(src, allow_interpolation=False)
    except (module.Unreadable, RecursionError) as error:
        return context(f"NOT CHECKED: {error}. Start review rounds at a counted door.")
    for _, prompt, opts in found:
        if reviewer(opts.get("agentType"), module) or recognized(prompt):
            return refuse("A Workflow agent() call cannot start a review round.")
    # calls() returns an empty prompt for a dynamic expression. Mark that case,
    # including an empty literal, rather than claim that its content was checked.
    if dynamic or any(
        opts.get("agentType") is None or not prompt for _, prompt, opts in found
    ):
        return context(
            "NOT CHECKED: an agent() type, prompt or options are built at run time. Start review rounds at a counted door."
        )
    return 0


def decide(payload: dict[str, Any]) -> int:
    data = payload.get("tool_input")
    if not isinstance(data, dict):
        return context(
            "NOT COUNTED: hook input could not be read. Check the client hook binding."
        )
    tool = payload.get("tool_name", "")
    module = parser()
    if tool == "Workflow":
        return workflow(data, payload.get("cwd"), module)
    if tool in ("Agent", "Task"):
        prompt = data.get("prompt")
        kind = data.get("subagent_type")
        is_review = reviewer(kind, module)
        signal = any(recognized(value) for value in strings(data))
        if is_review:
            if "name" in data:
                return refuse(
                    "A reader reads one head; start each round as a new reader without name."
                )
            if isinstance(prompt, str) and re.search(
                r"^Compiled:", prompt, re.MULTILINE
            ):
                return refuse("A compile round needs nspawn_review_start.")
            return count(prompt if isinstance(prompt, str) else "")
        if signal:
            return refuse(
                "A Candidate: token cannot enter an uncounted Agent or Task door, named or unnamed."
            )
        return 0
    if isinstance(tool, str) and tool.endswith("__nspawn_review_start"):
        if not data.get("subject") or not data.get("candidate"):
            return refuse("nspawn_review_start requires subject and candidate.")
        return 0
    if (
        isinstance(tool, str)
        and tool.endswith("__nspawn_run_start")
        and reviewer(data.get("agent"), module)
    ):
        return refuse(
            "A reviewer cannot use nspawn_run_start, including a continuation."
        )
    if any(recognized(value) for value in strings(data)):
        return refuse(
            "This door cannot send a review head, including an inline Candidate: token."
        )
    return 0


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, UnicodeError):
        return context(
            "NOT COUNTED: hook input could not be read. Check the client hook binding."
        )
    if not isinstance(payload, dict):
        return context(
            "NOT COUNTED: hook input is not an object. Check the client hook binding."
        )
    return decide(payload)


if __name__ == "__main__":
    sys.exit(main())
