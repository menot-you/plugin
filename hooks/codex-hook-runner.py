#!/usr/bin/env python3
"""Bind documented Codex shell/apply_patch payloads to NOTT hooks.

Source: https://learn.chatgpt.com/docs/hooks. Hooks cover only participating
local tools; a requested denial is not proof that a native host enforced it.
"""

import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from collections.abc import Mapping
from pathlib import Path

HOOKS = Path(__file__).resolve().parent
# The signals that stop the runner: each unwinds through hook()'s cleanup.
STOPS = {signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT}
# PreToolUse on a shell name, in Claude's order (hooks/hooks.json): first deny
# wins. Each reads {tool_name:"Bash", tool_input:{command}} and answers with
# the hookSpecificOutput deny + exit 2 that Codex documents, so nothing here
# translates. A `tool_name: "apply_patch"` payload carries the PATCH TEXT as
# its command and is not a shell line: only red-first reads it.
SHELL_GUARDS = (
    "pynott-branch-lock.sh",
    # secret-in-argv, owned-process and trunk: one process, rows in bash-guards.tsv.
    "bash-guards.sh",
    # two-misses reads session_id, which Codex documents in every payload
    # (codex-view-smoke.sh feeds it). Its ledger fills at post-edit, below.
    "two-misses.sh",
    # One campaign, one PR: reads GitHub, bounded inside the hook; Codex's runner
    # carries its refusal, not its NOT CHECKED context (README client matrix).
    "campaign-pr-guard.py",
)
# apply_patch's file headers, whichever route carried the patch: a heredoc into
# the shell tool, the freestanding tool, or the printf spelling the archived
# campaign recorded (test_package_plugin.py SHELL_WRITE), where every header
# sits mid-line inside a quoted argument. A Delete is not a product edit.
PATCH_FILE = re.compile(
    r"""(?:^|['"])\*\*\* (?:Add|Update) File: ([^'"\n]+?)\s*(?:$|['"])""",
    re.MULTILINE,
)
# ...and a SHELL line carries a patch only when one of its COMMANDS is apply_patch
# (review 2026-10-01, twice: the reviewer's read-only Python heredocs quoting patch
# headers and `apply_patch <<EOF` examples were denied). Words a command may lead with.
COMMAND_PREFIXES = {"{", "}", "!", "then", "do", "else", "elif", "if", "while", "time"}
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
SHELLS = {"bash", "sh", "zsh"}
# Wrappers that run the next word as the command, and their options taking a value
# (`env -u NAME`/`--unset NAME`, `env -C DIR`/`--chdir DIR`, `exec -a NAME`); for a
# shell, `-o`/`-O` take one. A `--name=value` word carries its own value.
WRAPPERS = {"exec", "command", "env"}
VALUED = {"-u", "--unset", "-C", "--chdir", "-a", "-o", "+o", "-O", "+O"}


def options_skipped(words: list[str]) -> tuple[list[str], list[str]]:
    """Split leading option words (with their values) from the operands after them."""
    flags: list[str] = []
    while words and words[0][:1] in "-+" and len(words[0]) > 1 and words[0] != "--":
        flags.append(words[0])
        words = words[2:] if words[0] in VALUED else words[1:]
    if words[:1] == ["--"]:
        words = words[1:]
    return flags, words


def invokes_apply_patch(text: str, depth: int = 0) -> bool:
    """Does any simple command of this shell text run apply_patch?

    Read by command words, not substrings: commands split at `; | & ( )` and
    newlines outside quotes; quotes are removed from words; a heredoc body is
    data and is skipped whoever reads it; `#` starts a comment. A command
    invokes apply_patch when its first word (after `{`, `then`, `NAME=value`,
    `exec`/`command`/`env` and their options), stripped of its directory, is
    `apply_patch`, or when it is `bash|sh|zsh` with `-c` among its leading
    options (and no `-n`) whose command string does, read once.

    ponytail: no `$(...)` nesting, `case` arms or aliases; an invocation hidden
    there is not judged — red-first is a nag, so that costs a missed nag.
    """
    words: list[str] = []
    word: str | None = None
    heredocs: list[tuple[str, bool]] = []
    found = False

    def command_ends() -> None:
        nonlocal found, words
        rest = words
        while rest and (rest[0] in COMMAND_PREFIXES or ASSIGNMENT.match(rest[0])):
            rest = rest[1:]
        while rest and rest[0] in WRAPPERS:
            rest = options_skipped(rest[1:])[1]
            while rest and ASSIGNMENT.match(rest[0]):
                rest = rest[1:]
        if rest:
            name = rest[0].rsplit("/", 1)[-1]
            if name == "apply_patch":
                found = True
            elif name in SHELLS and depth == 0:
                # Only `-c` among the LEADING options makes the first operand the
                # command string, and `-n` (syntax only) runs nothing.
                flags, operands = options_skipped(rest[1:])
                # Letters SET in a `-` cluster; `+n` unsets -n and `--x` is long.
                letters = "".join(
                    f[1:] for f in flags if f[:1] == "-" and not f.startswith("--")
                )
                if "c" in letters and "n" not in letters and operands:
                    found = invokes_apply_patch(operands[0], 1)
        words = []

    i, n = 0, len(text)
    while i < n and not found:
        c = text[i]
        if c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            word = (word or "") + text[i + 1 : j]
            i = j + 1
        elif c == '"':
            j, chunk = i + 1, []
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n and text[j + 1] in '"\\$`':
                    j += 1
                chunk.append(text[j])
                j += 1
            word = (word or "") + "".join(chunk)
            i = j + 1
        elif c == "\\" and i + 1 < n:
            # A backslash-newline is a line continuation, not a word.
            if text[i + 1] != "\n":
                word = (word or "") + text[i + 1]
            i += 2
        elif c == "#" and word is None:
            i = text.find("\n", i)
            i = n if i < 0 else i
        elif c in " \t":
            if word is not None:
                words.append(word)
                word = None
            i += 1
        elif text.startswith("<<", i) and not text.startswith("<<<", i):
            if word is not None:
                words.append(word)
                word = None
            i += 2
            dash = text.startswith("-", i)
            i += dash
            while i < n and text[i] in " \t":
                i += 1
            j = i
            while j < n and text[j] not in " \t\n;|&()<>":
                j += 1
            heredocs.append((text[i:j].replace("'", "").replace('"', ""), dash))
            i = j
        elif c in ";|&()\n":
            if word is not None:
                words.append(word)
                word = None
            command_ends()
            i += 1
            if c == "\n":
                # Every heredoc opened on that line: its body is data, skip it.
                for delimiter, dash in heredocs:
                    while i < n:
                        j = text.find("\n", i)
                        j = n if j < 0 else j
                        line = text[i:j]
                        i = j + 1
                        if (line.lstrip("\t") if dash else line) == delimiter:
                            break
                heredocs = []
        else:
            word = (word or "") + c
            i += 1
    if word is not None:
        words.append(word)
    if not found:
        command_ends()
    return found


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
# The packaged runner has 10 s per call (plugin/scripts/plugin/package.py, "timeout": 10).
# red-first's whole stage for one patch — probes and real calls — shares ONE deadline
# inside it; past that deadline red-first fails OPEN, as its own header says.
# Accepted residual (review 2026-10-01): under sustained load a slow but honest
# denial can be lost this way.
RED_FIRST_BUDGET_S = 8.0
# Ordering a patch's paths may spend at most this much of that deadline on probes.
# ponytail: a patch whose first test path lies past the budget keeps its order and
# the product ahead of it is denied — a nag, never a pass; raise it if that is measured.
PROBE_BUDGET_S = 3.0


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
    the kill, and the probe's throwaway directory then failed to clean up
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


def opens_red_first(payload: Mapping[str, object], deadline: float) -> bool:
    """Would red-first count this write as a test? Asked of red-first itself.

    It runs against throwaway state, so the probe neither opens the session's
    gate nor spends one of its three refusals; red-first stays the only owner of
    the product/test split. A probe past the deadline answers no.
    """
    state = tempfile.mkdtemp()
    try:
        hook(
            "red-first.sh",
            payload,
            forward=False,
            env={**os.environ, "XDG_STATE_HOME": state},
            timeout=max(deadline - time.monotonic(), 0.05),
        )
        return any(Path(state).rglob("tested"))
    except subprocess.TimeoutExpired:
        return False
    finally:
        # A throwaway directory that will not clean up is no reason to refuse the call.
        shutil.rmtree(state, ignore_errors=True)


def red_first_open(payload: Mapping[str, object]) -> bool:
    """Has this session already recorded its RED? red-first then passes every write.

    The record's location is red-first.sh's own (`$state/tested`, its line 46).
    """
    sid = re.sub(r"[^a-zA-Z0-9-]", "", str(payload.get("session_id") or ""))
    root = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    return bool(sid) and (Path(root) / "nott/red-first" / sid / "tested").exists()


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
            if payload.get("tool_name") != "apply_patch":
                for guard in SHELL_GUARDS:
                    code = hook(guard, mapped).returncode
                    if code:
                        return code
            # red-first decides per edited path; it owns the product/test split.
            # One patch carrying the product and its failing check is how Codex
            # writes (2026-10-01), so the patch's first test path is judged first,
            # whatever order the headers came in. One accepted test opens the gate
            # for the rest, so probing stops there, and an open gate ends the walk.
            freestanding = payload.get("tool_name") == "apply_patch"
            patched = freestanding or invokes_apply_patch(command)
            writes = [
                dict(mapped, tool_name="Write", tool_input={"file_path": path})
                for path in (PATCH_FILE.findall(command) if patched else [])
            ]
            started = time.monotonic()
            deadline = started + RED_FIRST_BUDGET_S
            if len(writes) > 1 and not red_first_open(mapped):
                probe_deadline = min(deadline, started + PROBE_BUDGET_S)
                for index, write in enumerate(writes):
                    if time.monotonic() >= probe_deadline:
                        break
                    if opens_red_first(write, probe_deadline):
                        writes.insert(0, writes.pop(index))
                        break
            for write in writes:
                remaining = deadline - time.monotonic()
                if red_first_open(mapped) or remaining <= 0:
                    break
                try:
                    code = hook("red-first.sh", write, timeout=remaining).returncode
                except subprocess.TimeoutExpired:
                    break
                if code:
                    return code
            return 0
        if action == "post-edit":
            advisories = []
            if payload.get("tool_name") in SHELL_TOOLS:
                # red-first's `tested` record and secret-in-output's chain
                # advisory. Codex runs PostToolUse after a non-zero Bash exit
                # too (measured 2026-09-14, #444), so a RED run and a chain cut
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
                    hook("red-first.sh", mapped, forward=False)
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
                if hook("nmemory-capture-gate.py", stop_payload).stdout.strip():
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
