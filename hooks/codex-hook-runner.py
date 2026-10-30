#!/usr/bin/env -S python3 -B
"""Bind documented Codex shell/apply_patch payloads to NOTT hooks.

Source: https://learn.chatgpt.com/docs/hooks. Hooks cover only participating
local tools; a requested denial is not proof that a native host enforced it.
"""

import json
import os
import signal
import subprocess
import sys
from collections.abc import Mapping
from pathlib import Path

HOOKS = Path(__file__).resolve().parent
# The signals that stop the runner: each unwinds through hook()'s cleanup.
STOPS = {signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT}
# PreToolUse on a shell name, in Claude's order (hooks/hooks.json): first deny
# wins. Each reads {tool_name:"Bash", tool_input:{command}} and answers with
# the hookSpecificOutput deny + exit 2 that Codex documents, so nothing here
# translates.
SHELL_GUARDS = (
    "pynott-branch-lock.sh",
    # secret-in-argv, owned-process and trunk: one process, rows in bash-guards.tsv.
    "bash-guards.sh",
    # two-misses reads session_id, which Codex documents in every payload
    # (codex-view-smoke.sh feeds it). Its ledger fills at post-edit, below.
    "two-misses.sh",
    # Only the owner merges into public: reads GitHub, bounded inside the hook,
    # and fails closed, so Codex's runner carries its refusal.
    "release-guard.py",
)
# The names the PostToolUse matcher admits that are NOT a write by their own
# name: codex gives the freestanding apply_patch tool to first-party models only,
# so every other model writes by piping a patch into `apply_patch` from the shell
# tool, and the same names carry `cat`.
SHELL_TOOLS = {"Bash", "exec_command", "shell_command"}
# apply_patch's own success report, verbatim from the aggregatedOutput of
# campaign-af-20260913/release2/scenario-out/cases/2901ba89.../turn-000/
# stdout.ndjson frame 93. It is the tool's word that a write landed, not a guess
# from the command text: the refused attempt in the same turn says
# "apply_patch verification failed" and is no edit at all.
APPLY_PATCH_WROTE = "Success. Updated the following files:"


def wrote(payload: Mapping[str, object]) -> bool:
    """Did this completed tool call write anything? Never guessed from a name.

    A shell name at PostToolUse arrives for a listing exactly as it arrives for a
    patch, and the advisory claims an edit COMPLETED — so the shell route has to
    show its work. apply_patch's success report is that showing.

    ponytail: this recognizes apply_patch through the shell, the route every
    non-first-party model takes. A bare `printf > file` is a write this hook
    cannot certify: nothing in the payload distinguishes it from `echo x >
    /dev/null`, and a redirection-sniffing regex would fire on the second. When
    that write must reach the advisory, the upgrade is an effect observation
    (a filesystem or `git status` delta), never a longer pattern list.
    """
    if payload.get("tool_name") not in SHELL_TOOLS:
        return True
    response = payload.get("tool_response")
    # Documented as "the tool output" without a fixed shape, so read it as text
    # whichever shape it takes; an absent one is silence, never a refusal.
    if not isinstance(response, str):
        response = json.dumps(response)
    return APPLY_PATCH_WROTE in response


def unreaped(child: subprocess.Popen[str]) -> bool:
    """Whether the hook's pid is still ours, so its group can be signalled.

    waitid(WNOWAIT) asks without reaping, and ECHILD means already reaped, even when
    a signal landed between waitpid() and the returncode it would set. macOS has
    waitid only from Python 3.13; before that, returncode is the best answer.
    """
    if not hasattr(os, "waitid"):
        return child.returncode is None
    try:
        os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    except ChildProcessError:
        return False
    return True


def hook(
    name: str,
    payload: Mapping[str, object],
    forward: bool = True,
    env: Mapping[str, str] | None = None,
    timeout: float = 8,
) -> subprocess.CompletedProcess[str]:
    """Run one Claude-shaped hook; forward its channels; return the process.

    Past its timeout, or when the runner itself is interrupted, the hook's whole
    process group dies, not the shell alone: its children kept writing state after
    the kill, and the caller's throwaway directory then failed to clean up
    (`Directory not empty`, Rail N 2026-10-02). The group is the hook's own, so a
    signal sent to the runner's group no longer reaches it: SIGINT, SIGTERM, SIGHUP
    and SIGQUIT are turned into an exit at the bottom of this file. SIGINT included,
    since a KeyboardInterrupt lets communicate() reap the hook first. Those signals
    stay blocked from before the fork until the cleanup below is armed, so one
    landing in between is delivered inside it; the hook gets the runner's own mask
    back before it execs. A SIGKILL to the runner cannot be caught and orphans the
    hook. A hook that has already exited and been reaped is not signalled: its pid
    may name nobody's group by then, and descendants it left running are those of
    any hook that exits, which the runner never kills.
    """
    if name == "voice.sh" and (HOOKS.parent / ".nott-public.json").is_file():
        return subprocess.CompletedProcess([name], 0, "", "")
    mask = signal.pthread_sigmask(signal.SIG_BLOCK, STOPS)
    try:
        child = subprocess.Popen(
            args=[str(HOOKS / name)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            start_new_session=True,
            # The runner is single-threaded: preexec_fn is safe here.
            preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, mask),  # noqa: PLW1509
        )
    except BaseException:
        signal.pthread_sigmask(signal.SIG_SETMASK, mask)
        raise
    with child:
        try:
            signal.pthread_sigmask(signal.SIG_SETMASK, mask)
            stdout, stderr = child.communicate(json.dumps(payload), timeout=timeout)
        except BaseException:
            if unreaped(child):
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except OSError:
                    pass
            # wait(), not communicate(): a member that left the group keeps the
            # pipes open, and their output is discarded anyway.
            child.wait()
            raise
    proc = subprocess.CompletedProcess(child.args, child.returncode, stdout, stderr)
    if forward:
        sys.stdout.write(proc.stdout)
        sys.stderr.write(proc.stderr)
    return proc


def advisory_of(proc: subprocess.CompletedProcess[str]) -> str | None:
    """The additionalContext a silent-by-contract hook printed, or None."""
    if not proc.stdout.strip():
        return None
    try:
        context = json.loads(proc.stdout)["hookSpecificOutput"]["additionalContext"]
    except (ValueError, KeyError, TypeError):
        return None
    return context if isinstance(context, str) and context else None


def command_of(payload: Mapping[str, object]) -> tuple[dict[str, object], str]:
    args = payload.get("tool_input")
    if not isinstance(args, dict):
        raise TypeError("shell tool_input is missing")
    command = args.get("cmd", args.get("command"))
    if not isinstance(command, str) or not command:
        raise ValueError("shell command is missing")
    return args, command


def main() -> int:
    action = sys.argv[1] if len(sys.argv) == 2 else ""
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            raise TypeError("native hook payload must be an object")
        if action in {"session-state-pre", "session-state-post"}:
            hook(
                "session-state.sh",
                dict(
                    payload,
                    hook_event_name="PreToolUse"
                    if action == "session-state-pre"
                    else "PostToolUse",
                ),
                env={**os.environ, "NOTT_HOOK_CLIENT": "codex"},
            )
            return 0
        if action == "pre-shell":
            args, command = command_of(payload)
            cwd = args.get("workdir") or payload.get("cwd")
            if not isinstance(cwd, str) or not cwd:
                raise ValueError("shell working directory is missing")
            mapped = dict(
                payload,
                hook_event_name="PreToolUse",
                tool_name="Bash",
                tool_input={"command": command},
                cwd=cwd,
            )
            for guard in SHELL_GUARDS:
                code = hook(guard, mapped).returncode
                if code:
                    return code
            return 0
        if action == "post-edit":
            advisories = []
            if payload.get("tool_name") in SHELL_TOOLS:
                # two-misses' ledger and secret-in-output's chain advisory.
                # Codex runs PostToolUse after a non-zero Bash exit too
                # (measured 2026-09-14, #444), so a failed run and a chain cut
                # by an exit-3 gate both land here without a PostToolUseFailure
                # event. Both hooks are silent by contract; their channels are
                # not forwarded ahead of the single advisory JSON.
                try:
                    _, command = command_of(payload)
                except (ValueError, TypeError):
                    command = ""
                if command:
                    response = payload.get("tool_response")
                    mapped = dict(
                        payload,
                        hook_event_name="PostToolUse",
                        tool_name="Bash",
                        tool_input={"command": command},
                        # Codex documents the output without a fixed shape;
                        # flattened, the hook reads it whichever keys it has.
                        tool_response=response
                        if isinstance(response, str)
                        else json.dumps(response),
                    )
                    # two-misses counts a FAIL only when the flattened output
                    # text carries `"exit_code": N` (N != 0) or an "Exit code N"
                    # line; Codex documents the output without a fixed shape,
                    # so whether a real Codex response carries the exit code
                    # is NOT measured here — a shape without it makes the deny
                    # unreachable and the hook silent, never wrong.
                    hook("two-misses.sh", mapped, forward=False)
                    advice = advisory_of(
                        hook("secret-in-output.sh", mapped, forward=False)
                    )
                    if advice:
                        advisories.append(advice)
            if wrote(payload):
                advisories.append(
                    "Codex edit completed. This hook has no independently resolved list of edited paths and did not pass a law contract; inspect changed paths and run the applicable contract when law or its guards changed."
                )
            if advisories:
                print(
                    json.dumps(
                        {
                            "hookSpecificOutput": {
                                "hookEventName": "PostToolUse",
                                "additionalContext": " ".join(advisories),
                            }
                        }
                    )
                )
            return 0
        if action == "stop":
            # Codex's Stop payload is Claude-shaped (last_assistant_message,
            # stop_hook_active, transcript_path); nmemory-capture-gate.py blocks
            # an uncaptured owner correction, and final-state.sh's voice check
            # advises on pt-PT (NOTT_HOOK_CLIENT keeps it off the state line).
            # A check that cannot judge never blocks: it allows and says why.
            stop_payload = dict(payload, hook_event_name="Stop")
            hook(
                "session-state.sh",
                stop_payload,
                env={**os.environ, "NOTT_HOOK_CLIENT": "codex"},
            )
            try:
                # At most ONE continuation per turn end: the capture gate is the only
                # check here that blocks, and its one reason names the whole capture.
                # Codex marks each later Stop with stop_hook_active, and a block there
                # re-fired Stop without end (2026-10-22).
                if (
                    payload.get("stop_hook_active") is not True
                    and hook("nmemory-capture-gate.py", stop_payload).stdout.strip()
                ):
                    return 0
            except (OSError, subprocess.TimeoutExpired) as error:
                print(
                    f"NOTT Codex stop: nmemory-capture-gate.py did not judge: {error}",
                    file=sys.stderr,
                )
            try:
                hook(
                    "final-state.sh",
                    stop_payload,
                    env={**os.environ, "NOTT_HOOK_CLIENT": "codex"},
                )
            except (OSError, subprocess.TimeoutExpired) as error:
                print(
                    f"NOTT Codex stop: final-state.sh did not judge: {error}",
                    file=sys.stderr,
                )
            return 0
        raise ValueError("unknown Codex hook action")
    except (ValueError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"NOTT Codex hook refused: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    for stop in STOPS:
        # A signal the runner was started ignoring (nohup, a background job) stays ignored.
        if signal.getsignal(stop) is not signal.SIG_IGN:
            signal.signal(stop, lambda signum, _frame: sys.exit(128 + signum))
    sys.exit(main())
