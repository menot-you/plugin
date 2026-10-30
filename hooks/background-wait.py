#!/usr/bin/env -S python3 -B
"""Keep an eligible actor with its own live shell or Monitor until it has a result.

Only stdin and this actor's private ledger supply judgment. Launch-result
fields remain inherited schema assumptions. The separate write-only audit lets
an installed consumer compare those assumptions without reading a transcript.
Unknown protocol or unavailable state passes visibly; PostToolUse never blocks.
Python 3.9 is the oldest supported hook interpreter.
"""

import contextlib
import fcntl
import hashlib
import json
import math
import os
import re
import stat
import sys
import time

INPUT_LIMIT = 4 * 1024 * 1024
LEDGER_LIMIT = 256 * 1024
LINE_LIMIT = 4096
REFUSAL_LIMIT = 12
LOCK_BUDGET = 4
IDENTIFIER = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
LIVE = {"running", "pending"}
ENDED = {"completed", "failed", "killed"}


class StateError(Exception):
    """The state cannot supply a safe judgment."""


def identifier(value):
    return isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None


def clean(value):
    if not isinstance(value, str):
        return ""
    return "".join(c for c in value if c.isalnum() or c in " .,_:-/")[:60]


def shape(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, str):
        return "string"
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    return "number"


def field(obj, key, value_kind=None):
    present = isinstance(obj, dict) and key in obj
    value = obj.get(key) if present else None
    result = {"present": present, "type": shape(value) if present else "absent"}
    if value_kind == "id" and identifier(value):
        result["value"] = value
    elif value_kind == "text" and isinstance(value, str):
        result["value"] = clean(value)
    elif (
        value_kind == "scalar"
        and type(value) in (int, float, bool)
        and (not isinstance(value, float) or abs(value) < 1e15)
    ):
        result["value"] = value
    return result


def response(payload):
    result = payload.get("tool_response")
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except (ValueError, RecursionError):
            return None
    return result if isinstance(result, dict) else None


def member_types(value):
    if not isinstance(value, dict):
        return {}
    result = {}
    for key, item in value.items():
        if len(result) == 12:
            break
        if isinstance(key, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,39}", key):
            result[key] = shape(item)
    return result


def audit_fields(payload):
    fields = {}
    for key in (
        "agent_id",
        "tool_name",
        "tool_response",
        "tool_input",
        "background_tasks",
        "stop_hook_active",
    ):
        fields[key] = field(payload, key)
    fields["tool_name"] = field(payload, "tool_name", "id")
    result = response(payload)
    fields["tool_response"]["members"] = member_types(result)
    for key, kind in (
        ("backgroundTaskId", "id"),
        ("taskId", "id"),
        ("timedOutAfterMs", "scalar"),
    ):
        fields[key] = field(result, key, kind)
    tool_input = payload.get("tool_input")
    for key in ("run_in_background", "timeout"):
        fields[key] = field(tool_input, key, "scalar")
    tasks = payload.get("background_tasks")
    if isinstance(tasks, list):
        fields["background_tasks"]["count"] = len(tasks)
        fields["background_tasks"]["items"] = [
            dict(
                {
                    key: field(task, key, "text" if key == "description" else "id")
                    for key in ("id", "type", "status", "description")
                },
                members=member_types(task),
            )
            if isinstance(task, dict)
            else {"type": shape(task)}
            for task in tasks[:5]
        ]
    return fields


@contextlib.contextmanager
def private_file(base, family, component, create, deadline=None, audit=False):
    """Open each directory without following links, then lock a private file."""
    fd = None
    directory = None
    if deadline is None:
        deadline = time.monotonic() + LOCK_BUDGET
    try:
        if not base or not os.path.isabs(base):
            raise StateError("state directory is unavailable")
        directory = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
        parts = [p for p in base.split("/") if p] + ["nott", family]
        for index, part in enumerate(parts):
            if part in (".", ".."):
                raise StateError("state path is not confined")
            try:
                next_dir = os.open(
                    part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory
                )
            except FileNotFoundError:
                if not create:
                    yield None
                    return
                try:
                    os.mkdir(part, 0o700, dir_fd=directory)
                except FileExistsError:
                    # Another hook won the race; reopen and apply the same checks.
                    pass
                next_dir = os.open(
                    part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory
                )
            os.close(directory)
            directory = next_dir
            if index == len(parts) - 1:
                info = os.fstat(directory)
                if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
                    raise StateError("state directory is not private")
        mode = os.O_WRONLY if audit else os.O_RDWR
        flags = mode | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK
        if create:
            flags |= os.O_CREAT
        try:
            fd = os.open(component + ".jsonl", flags, 0o600, dir_fd=directory)
        except FileNotFoundError:
            yield None
            return
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
        ):
            raise StateError("state file is not private")
        if stat.S_IMODE(info.st_mode) != 0o600:
            raise StateError("state file mode is not private")
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise StateError("state lock wait timed out") from None
                time.sleep(min(0.01, remaining))
        yield fd
    except OSError as exc:
        raise StateError("state is unreadable or unwritable") from exc
    finally:
        if fd is not None:
            os.close(fd)
        if directory is not None:
            os.close(directory)


def record(kind, sid, actor, **extra):
    return dict(kind=kind, session_id=sid, actor=actor, time=time.time(), **extra)


def valid_record(row, sid, actor):
    if (
        not isinstance(row, dict)
        or row.get("session_id") != sid
        or row.get("actor") != actor
    ):
        return False
    stamp = row.get("time")
    try:
        if type(stamp) not in (int, float) or not math.isfinite(stamp):
            return False
    except OverflowError:
        return False
    kind = row.get("kind")
    if kind == "launch":
        return identifier(row.get("task")) and row.get("how") in (
            "background",
            "timeout",
            "monitor",
        )
    if kind in ("refused", "released"):
        return isinstance(row.get("ids"), list) and all(
            identifier(task) for task in row["ids"]
        )
    return kind in ("unknown", "return", "passed")


def window(fd, sid, actor):
    if fd is None:
        return [], False
    if os.fstat(fd).st_size >= LEDGER_LIMIT:
        raise StateError("ledger is full")
    os.lseek(fd, 0, os.SEEK_SET)
    data = os.read(fd, LEDGER_LIMIT)
    records = []
    uncertain = not data
    for line in data.splitlines(keepends=True):
        try:
            row = json.loads(line) if line.endswith(b"\n") else None
        except (ValueError, UnicodeError, RecursionError):
            row = None
        if not valid_record(row, sid, actor):
            uncertain = True
        elif row["kind"] == "passed":
            records = []
            uncertain = False
        else:
            records.append(row)
            uncertain = uncertain or row["kind"] == "unknown"
    return records, uncertain


def append(fd, row, audit=False):
    data = (
        json.dumps(
            row, ensure_ascii=True, separators=(",", ":"), allow_nan=False
        ).encode()
        + b"\n"
    )
    size = os.fstat(fd).st_size
    # Preserve a torn actor line as uncertainty, without joining the next record.
    if not audit and size and os.pread(fd, 1, size - 1) != b"\n":
        data = b"\n" + data
    if len(data) >= LINE_LIMIT:
        raise StateError("state record is too large")
    if size + len(data) >= LEDGER_LIMIT:
        raise StateError("ledger is full")
    if os.write(fd, data) != len(data):
        raise StateError("state write is incomplete")


def actor_for(payload, sid):
    event = payload.get("hook_event_name")
    child = os.environ.get("NOTT_NSPAWN_SESSION_ID") == sid
    actor = payload.get("agent_id")
    if event == "Stop":
        return "main" if child else None
    if event not in ("PostToolUse", "SubagentStop"):
        return None
    if identifier(actor):
        return "agent:main" if actor == "main" else actor
    if "agent_id" not in payload and child and event == "PostToolUse":
        return "main"
    return None


def launch_record(payload, sid, actor):
    tool = payload.get("tool_name")
    if tool == "StructuredOutput":
        return record("return", sid, actor), None
    if tool not in ("Bash", "Monitor"):
        return None, "unknown tool shape"
    result = response(payload)
    tool_input = payload.get("tool_input")
    if result is None or not isinstance(tool_input, dict):
        return None, "unknown launch result shape"
    key = "backgroundTaskId" if tool == "Bash" else "taskId"
    task = result.get(key)
    timeout = result.get("timedOutAfterMs")
    if task is None:
        if (
            tool == "Bash"
            and tool_input.get("run_in_background") is not True
            and timeout is None
            and isinstance(result.get("stdout"), str)
        ):
            return None, None
        return None, "launch result has no task id or known foreground shape"
    if not identifier(task):
        return None, "unknown launch id shape"
    if timeout is not None and (type(timeout) is not int or timeout < 0):
        return None, "unknown timeout shape"
    how = (
        "monitor"
        if tool == "Monitor"
        else "timeout"
        if timeout is not None
        else "background"
    )
    return record("launch", sid, actor, task=task, how=how), None


def refusal_reason(actor, tasks, launches):
    lines = []
    for task in tasks[:5]:
        kind = "Monitor" if launches[task["id"]]["how"] == "monitor" else "shell"
        lines.append(
            "- {} ({}: {})".format(task["id"], kind, clean(task.get("description")))
        )
    start = "background-wait: Do not end your turn yet. Background work that you started still runs:\n"
    start += "\n".join(lines) + "\n"
    if actor == "main":
        remedy = (
            "This run ends with your turn, and then this work stops. Your final text needs its result.\n"
            "Do these steps. Then write your final text.\n"
            "1. Run the command again in the foreground, in one Bash call with timeout 600000.\n"
            "2. If Bash refuses the call or you cannot wait: write BLOCKED with the id in your final text."
        )
    else:
        remedy = (
            "When your turn ends, this work stops or its result cannot reach you. Your report needs its result.\n"
            "Do these steps. Then write your final report.\n"
            "1. A server, a tail -f or a Monitor does not end by itself. Stop it: call TaskStop with its id.\n"
            "2. For a job, wait in the foreground. Use one Bash call with timeout 600000 and a counted loop:\n"
            "   for i in $(seq 1 110); do grep -q '<last line>' '<output file>' && break; sleep 5; done\n"
            "   If the loop ends and the job still runs, run the loop again. Then read the file with Read.\n"
            "3. If the output has no end line: call TaskStop with its id. Start the command again with "
            '"; echo EXIT=$?" at its end. Wait for EXIT= in the same way.\n'
            "4. If you cannot wait: call TaskStop with its id. Then report BLOCKED with the id."
        )
    while len((start + remedy).encode("utf-8")) >= 1500 and len(lines) > 1:
        lines.pop()
        start = "background-wait: Do not end your turn yet. Background work that you started still runs:\n"
        start += "\n".join(lines) + "\n"
    return start + remedy, [task["id"] for task in tasks[: len(lines)]]


def judge(payload, actor, records, uncertain, exists):
    launches = {r["task"]: r for r in records if r["kind"] == "launch"}
    tasks = payload.get("background_tasks")
    if not isinstance(tasks, list):
        cause = (
            "background task list is missing or unreadable"
            if records or uncertain
            else None
        )
        return "unjudged" if cause else "passed", cause, list(launches), None
    own = []
    observed = {}
    other_live_or_unknown = False
    malformed = False
    self_id = (
        payload.get("agent_id")
        if payload["hook_event_name"] == "SubagentStop"
        else None
    )
    for task in tasks:
        if isinstance(task, dict) and self_id is not None and task.get("id") == self_id:
            continue
        if (
            not isinstance(task, dict)
            or not identifier(task.get("id"))
            or "status" not in task
        ):
            malformed = True
            continue
        observed[task["id"]] = None
        status = task["status"]
        live = isinstance(status, str) and status in LIVE
        known = isinstance(status, str) and status in LIVE | ENDED
        other_live_or_unknown = other_live_or_unknown or live or not known
        if task["id"] in launches:
            own.append((task, live, known))
    if malformed and (launches or uncertain):
        return "unjudged", "background task entry is unreadable", list(launches), None
    live = [task for task, running, _ in own if running]
    ids = list(dict.fromkeys(task["id"] for task in live))
    if live:
        if any(r["kind"] == "return" for r in records):
            return "unjudged", "StructuredOutput replacement is unmeasured", ids, None
        if sum(r["kind"] == "refused" for r in records) >= REFUSAL_LIMIT:
            return "released", "12 refusals in this actor window", ids, {"ids": ids}
        reason, named = refusal_reason(actor, live, launches)
        return "refused", reason, named, {"ids": named}
    if any(not known for _, _, known in own):
        return (
            "unjudged",
            "own task has an unknown status",
            [task["id"] for task, _, _ in own],
            None,
        )
    if uncertain and other_live_or_unknown:
        return (
            "unjudged",
            "actor window has unresolved launch or record uncertainty",
            list(observed),
            None,
        )
    return "passed", None, [], {} if exists else None


def notice(event, actor, ids, cause):
    work = ", ".join(ids[:5]) or "unavailable"
    if event == "PostToolUse":
        text = f"background-wait: could not record this launch for {actor} (task ids: {work}): {cause}."
    else:
        text = f"background-wait: could not judge the stop of {actor} (task ids: {work}): {cause}. The lock did not hold this stop."
    return {"systemMessage": text}


def write_audit(base, sid, actor, payload, judgment, cause, pending, deadline):
    audit = {
        "event": payload["hook_event_name"],
        "session_id": sid,
        "actor": actor,
        "fields": audit_fields(payload),
        "judgment": judgment,
        "cause": cause,
        "write_pending": pending,
    }
    tasks = audit["fields"]["background_tasks"]
    items = tasks.get("items", [])
    while (
        items and len(json.dumps(audit, ensure_ascii=True).encode()) >= LINE_LIMIT - 64
    ):
        items.pop()
    if "count" in tasks:
        tasks["omitted"] = tasks["count"] - len(items)
    component = hashlib.sha256(sid.encode("utf-8")).hexdigest()
    with private_file(
        base, "background-wait-audit", component, True, deadline, audit=True
    ) as fd:
        append(fd, audit, audit=True)


def process(payload, sid, actor):
    event = payload["hook_event_name"]
    base = os.environ.get("XDG_STATE_HOME")
    if not base or not os.path.isabs(base):
        home = os.environ.get("HOME")
        base = os.path.join(home, ".local", "state") if home else None
    component = hashlib.sha256(
        json.dumps([sid, actor], separators=(",", ":")).encode()
    ).hexdigest()
    row = None
    cause = None
    judgment = "observed"
    ids = []
    if event == "PostToolUse":
        row, cause = launch_record(payload, sid, actor)
        if cause:
            row = record("unknown", sid, actor)
        if row is not None:
            judgment = row["kind"]
            if row["kind"] == "launch":
                ids = [row["task"]]
    deadline = time.monotonic() + LOCK_BUDGET
    attempted_audit = False
    audited = False
    output = notice(event, actor, ids, cause) if cause else {}
    try:
        ledger = (
            contextlib.nullcontext(None)
            if event == "PostToolUse" and row is None
            else private_file(
                base, "background-wait", component, row is not None, deadline
            )
        )
        with ledger as fd:
            if event == "PostToolUse":
                if row is not None:
                    append(fd, row)
            else:
                records, uncertain = window(fd, sid, actor)
                judgment, cause, ids, extra = judge(
                    payload, actor, records, uncertain, fd is not None
                )
                if judgment == "refused":
                    output = {"decision": "block", "reason": cause}
                    cause = None
                elif judgment == "released":
                    output = {
                        "systemMessage": f"background-wait: released {actor} with live work {', '.join(ids[:5])}: {cause}."
                    }
                elif judgment == "unjudged":
                    output = notice(event, actor, ids, cause)
                row = (
                    record(judgment, sid, actor, **extra) if extra is not None else None
                )
            # Audit the requested judgment before a stop write can retire its window.
            # write_pending distinguishes a request from committed/native evidence.
            attempted_audit = True
            write_audit(
                base,
                sid,
                actor,
                payload,
                judgment,
                cause,
                event != "PostToolUse" and row is not None,
                deadline,
            )
            audited = True
            if event != "PostToolUse" and row is not None:
                append(fd, row)
    except StateError as exc:
        cause = str(exc)
        if attempted_audit:
            cause = (
                "stop write failed: " if audited else "audit write failed: "
            ) + cause
        output = notice(event, actor, ids, cause)
        if not attempted_audit:
            try:
                write_audit(
                    base, sid, actor, payload, "unjudged", cause, False, deadline
                )
            except StateError:
                output = notice(
                    event, actor, ids, cause + "; audit evidence is missing"
                )
    return output


def main():
    try:
        raw = sys.stdin.buffer.read(INPUT_LIMIT + 1)
        if len(raw) > INPUT_LIMIT:
            return
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            return
        sid = payload.get("session_id")
        if (
            not isinstance(sid, str)
            or not 1 <= len(sid) <= 128
            or not re.search(r"[A-Za-z0-9-]", sid)
        ):
            return
        actor = actor_for(payload, sid)
        if actor is None:
            return
        output = process(payload, sid, actor)
        if output:
            print(json.dumps(output, ensure_ascii=True, allow_nan=False))
    except (ValueError, UnicodeError, RecursionError, OSError):
        # Invalid stdin and broken output pipes never change the tool's exit.
        return


if __name__ == "__main__":
    main()
    sys.exit(0)
