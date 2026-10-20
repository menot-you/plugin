#!/usr/bin/env python3
"""AGY native envelopes. PostToolUse feedback is deferred to PreInvocation.

PostToolUse supplies no guaranteed tool arguments and accepts only {}. Feedback
is advisory, session-scoped and transient; it is never evidence of enforcement.
Native contract: antigravity-cli/builtin/skills/agy-customizations/docs/hooks.md.
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from collections.abc import Mapping
from pathlib import Path

HOOKS = Path(__file__).resolve().parent
LIMIT = 65536
# The Stop check, named here so the packager reads which script `stop` runs.
# final-state.sh judges the voice only, under NOTT_HOOK_CLIENT (hook() sets it).
STOP_CHECKS = ("final-state.sh",)


class Refusal(ValueError):
    pass


class GateFailure(Exception):
    def __init__(self, code: int, diagnostics: str) -> None:
        super().__init__(code)
        self.code = code
        self.diagnostics = diagnostics


def string(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise Refusal(f"{field} must be a nonempty string")
    return value


def queue_path(payload: Mapping[str, object]) -> Path:
    session = string(payload.get("conversationId"), "conversationId")
    state = (
        Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        / "nott/agy-feedback"
    )
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    if state.is_symlink() or state.stat().st_uid != os.getuid():
        raise Refusal("feedback directory is not owned by this user")
    path = state / (hashlib.sha256(session.encode()).hexdigest() + ".json")
    if path.is_symlink() or path.exists() and path.stat().st_size > LIMIT:
        raise Refusal("feedback record is linked or oversized")
    return path


def hook(name: str, payload: Mapping[str, object]) -> str:
    if name == "voice.sh" and (HOOKS.parent / ".nott-public.json").is_file():
        return ""
    process = subprocess.run(
        check=False,
        args=[str(HOOKS / name)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=8,
        # final-state.sh reads it: AGY has no Claude statusline, so only the voice is judged.
        env={**os.environ, "NOTT_HOOK_CLIENT": "agy"},
    )
    if process.returncode:
        raise Refusal(
            f"{name} exited {process.returncode}: {process.stderr.strip()[:2000]}"
        )
    return process.stdout[:LIMIT].strip()


def advisory(stdout: str) -> str:
    """What an exit-0 hook SAID, which its exit code never carries.

    law-contract.sh hands its RED back as exit 0 plus a PostToolUse envelope on stdout
    (law-contract.sh:89-93) — advisory by design, so that it blocks acceptance without
    blocking the edit. Reading only the return code dropped that content on the floor.
    """
    text = stdout[:LIMIT].strip()
    if not text:
        return ""
    try:
        envelope = json.loads(text)
    except json.JSONDecodeError:
        return text
    if not isinstance(envelope, dict):
        return text
    context = envelope.get("hookSpecificOutput", {})
    context = context.get("additionalContext") if isinstance(context, dict) else None
    return context.strip() if isinstance(context, str) else ""


def enqueue(payload: Mapping[str, object], message: str) -> dict[str, object]:
    # Native hooks run sequentially. Deduplicate bounded notices while retaining
    # both write and command feedback until this session's next invocation.
    path = queue_path(payload)
    messages = json.loads(path.read_text())["messages"] if path.exists() else []
    if not isinstance(messages, list) or not all(
        isinstance(item, str) for item in messages
    ):
        raise Refusal("feedback messages must be strings")
    if message not in messages:
        messages.append(message)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        json.dump({"messages": messages}, output)
        temporary = Path(output.name)
    temporary.replace(path)
    return {}


def last_final(transcript: Path) -> str | None:
    """The turn's final text: the last MODEL PLANNER_RESPONSE with content.

    AGY's Stop payload carries no final message, only `transcriptPath`, which is
    complete when Stop fires (measured 2026-09-25). Planner steps between tool
    calls carry null content, so the last NON-EMPTY one is the reply.
    """
    text = None
    with transcript.open(encoding="utf-8") as lines:
        for line in lines:
            try:
                step = json.loads(line)
            except json.JSONDecodeError:
                continue
            content = step.get("content") if isinstance(step, dict) else None
            if (
                step.get("source") == "MODEL"
                and step.get("type") == "PLANNER_RESPONSE"
                and isinstance(content, str)
                and content.strip()
            ):
                text = content
    return text


def stop(payload: Mapping[str, object], check: str) -> dict[str, object]:
    """Judge the final reply's voice; block at most once in a row per conversation.

    AGY re-enters the loop on {"decision":"continue"} with a NEW executionNum and
    no stop_hook_active, so the guard is a per-conversation toggle: a marker
    means the previous Stop blocked, and this one allows and clears it. Every
    failure allows and says why on stderr: a missing check never blocks a reply.
    """
    try:
        return judge_stop(payload, check)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        # Refusal, JSONDecodeError and UnicodeDecodeError are ValueErrors.
        print(f"NOTT AGY stop: {check} did not judge: {error}", file=sys.stderr)
        return {}


def judge_stop(payload: Mapping[str, object], check: str) -> dict[str, object]:
    session = string(payload.get("conversationId"), "conversationId")
    runtime = Path(
        os.environ.get("XDG_RUNTIME_DIR")
        or os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))
    )
    markers = runtime / "nott/agy-stop"
    markers.mkdir(mode=0o700, parents=True, exist_ok=True)
    marker = markers / hashlib.sha256(session.encode()).hexdigest()
    if marker.is_symlink() or marker.exists():
        marker.unlink()
        return {}
    transcript = Path(string(payload.get("transcriptPath"), "transcriptPath"))
    final = last_final(transcript) if transcript.exists() else None
    if final is None:
        print(
            "NOTT AGY stop: no final message in the transcript; not judged",
            file=sys.stderr,
        )
        return {}
    verdict = hook(
        check,
        {
            "hook_event_name": "Stop",
            "session_id": session,
            "stop_hook_active": False,
            "last_assistant_message": final,
        },
    )
    if not verdict:
        return {}
    decision = json.loads(verdict)
    if not isinstance(decision, dict):
        raise Refusal(f"verdict is not an object: {verdict[:200]}")
    if decision.get("decision") != "block":
        return {}
    reason = string(decision.get("reason"), "reason")
    marker.touch(mode=0o600)
    return {"decision": "continue", "reason": reason}


def run(action: str, payload: object) -> dict[str, object]:
    if not isinstance(payload, dict):
        raise Refusal("hook input must be an object")
    if action == "pre-tool-run-command":
        call = payload.get("toolCall")
        if (
            not isinstance(call, dict)
            or call.get("name") != "run_command"
            or not isinstance(call.get("args"), dict)
        ):
            raise Refusal("toolCall must name run_command with args")
        args = call["args"]
        command = string(args.get("CommandLine"), "CommandLine")
        paths = payload.get("workspacePaths", [])
        cwd = args.get("Cwd") or (
            paths[0] if isinstance(paths, list) and paths else None
        )
        string(cwd, "Cwd or workspacePaths[0]")
        # Claude's PreToolUse Bash guards in hooks/hooks.json order; the first
        # deny wins. A deny is exit 2 + its reason on stderr, which hook() turns
        # into a Refusal and main() into {"decision":"deny","reason"}.
        # red-first is NOT here: its `tested` record needs the command text at
        # PostToolUse, and AGY's PostToolUse carries {stepIdx, error} only, so
        # its deny would call a tested session untested. Declared in the packager.
        for guard in (
            "pynott-branch-lock.sh",
            "bash-guards.sh",
            # Its refusal reaches AGY; an allow answers {"decision":"allow"} and
            # drops the NOT CHECKED context (README client matrix).
            "campaign-pr-guard.py",
        ):
            hook(
                guard,
                {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd},
            )
        return {"decision": "allow"}
    if action == "post-tool-write":
        call = payload.get("toolCall")
        target = (
            call.get("args", {}).get("TargetFile") if isinstance(call, dict) else None
        )
        gate = HOOKS / "law-contract.sh"
        if isinstance(target, str) and target.strip():
            # The host identified the edited file: run the law gate and keep its
            # exit code and diagnostics (origin/main be5f8425) instead of feedback.
            # A missing gate raises OSError: refused, exit 2 (origin/main 7f860965).
            process = subprocess.run(
                check=False,
                args=[str(gate)],
                input=json.dumps(
                    {"tool_name": "Write", "tool_input": {"file_path": target}}
                ),
                capture_output=True,
                text=True,
                timeout=8,
            )
            if process.returncode:
                raise GateFailure(process.returncode, process.stdout + process.stderr)
            # A write ALWAYS delivers a write advisory: the gate's own words when it
            # spoke, and the bare fact that it ran when it did not. Returning {} on a
            # silent gate left agy/write-advisory-delivered unmeetable by any write the
            # host identified — the obligation names the delivery, not the gate's mood.
            # PostToolUse takes no feedback natively, so it rides the queue the next
            # pre-invocation drains.
            spoken = advisory(process.stdout)
            message = f"AGY write completed. The law contract ran on {target}."
            return enqueue(payload, f"{message} {spoken}" if spoken else message)
    if action in {"post-tool-write", "post-tool-run-command"}:
        if action == "post-tool-write":
            message = "AGY write completed. The native PostToolUse payload does not identify the edited file; this hook did not run or pass a law contract. Inspect the actual changed paths and run the applicable contract when law or its guards changed."
        else:
            message = "AGY command completed. PostToolUse does not supply stdout or command arguments; this hook did not validate or rewrite the output. Judge the tool's recorded result and observed effects."
        if payload.get("error"):
            message += " The host reported a tool error; inspect the recorded tool result before continuing."
        return enqueue(payload, message)
    if action == "stop":
        return stop(payload, *STOP_CHECKS)
    if action == "pre-invocation":
        path = queue_path(payload)
        invocation = payload.get("invocationNum")
        if (
            not isinstance(invocation, int)
            or isinstance(invocation, bool)
            or invocation < 0
        ):
            raise Refusal("invocationNum must be a nonnegative integer")
        messages = []
        if invocation <= 1:
            messages.append(
                "NOTT native AGY session: use registered nMEMORY context and ingest capabilities with the observed project. Hook feedback is advisory data, not authorization or proof of a completed act."
            )
            child = hook("nspawn-child-directives.sh", {})
            if child:
                messages.append(child)
        try:
            with path.open() as source:
                feedback = json.load(source)
        except FileNotFoundError:
            pass
        else:
            feedback_messages = feedback.get("messages")
            if not isinstance(feedback_messages, list):
                raise Refusal("feedback.messages must be a list")
            messages.extend(
                string(item, "feedback.messages[]") for item in feedback_messages
            )
            path.unlink()
        return {"injectSteps": [{"ephemeralMessage": message} for message in messages]}
    raise Refusal(f"unknown native action: {action}")


def main() -> int:
    action = sys.argv[1] if len(sys.argv) == 2 else ""
    try:
        raw = sys.stdin.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise Refusal("native hook input exceeds limit")
        result = run(action, json.loads(raw))
    except GateFailure as failure:
        sys.stderr.write(failure.diagnostics)
        print("{}")
        return failure.code if failure.code > 0 else 128 - failure.code
    except (Refusal, json.JSONDecodeError, OSError, subprocess.TimeoutExpired) as error:
        reason = f"NOTT AGY hook refused: {error}"
        print(reason, file=sys.stderr)
        if action == "pre-tool-run-command":
            print(json.dumps({"decision": "deny", "reason": reason}))
            return 0
        print("{}")
        return 2
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
