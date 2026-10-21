#!/usr/bin/env python3
"""PreToolUse on Agent and Workflow: each dispatch runs on the tier of its execution class.

The rule is plugin/skills/workflow/SKILL.md (<!-- nott:workflow:model-tier -->). The tier of
each class comes from the table in references/model-tiers.md, which this hook reads at each
call; it keeps no copy of it.

The class comes from a deterministic reader of the brief, never from System1: the classifier's
key is not available to a hook, and one network call on each dispatch adds to each turn.
- A read-only reviewer subagent type, or a review brief, is `review`.
- A security, concurrency, persistence, protocol or trust unit is `judgment`: it is never
  moved to Haiku, whatever its other markers say. A named Haiku model on such a brief gets a
  context line, not a rewrite: a subject word alone is too weak to move a unit up.
- A contract marker (rerun, report each command with its exit, read back, smoke, sweep,
  probe, watcher, mechanical edit) is `mechanical_fanout`. When a judgment marker (fix,
  diagnose, implement, design, approve and the like) or an edit verb (write, add, change and
  the like, unless the brief says "mechanical edit") is also present, the class is ambiguous.
- A sentence that starts with a prohibition ("Never read credentials", "Do not edit") is a
  rule of the brief, not its subject, and is not read for markers.

Agent: a dispatch whose named model does not fit its class is rewritten through
`updatedInput` and told why in `additionalContext`. Nothing is refused. Claude Code 2.1.304 applies a PreToolUse
`updatedInput` to the Agent tool after it validates the new input. The output carries no
permissionDecision: the rewrite approves nothing on the user's behalf. A brief with a
`Tier reason:` line keeps its model. A sonnet review reader keeps sonnet: the pipeline's stage
table names it. A fork is exempt: it runs on its parent's model.

Workflow: the PreToolUse input carries the script (`script`, or a file at `scriptPath`). The
hook reads each `agent()` call whose options are an object literal. A call whose label or
phase names a mechanical stage, or whose agentType is a reviewer, must use its class's tier.
Rewriting JavaScript is fragile, so a mismatch denies the Workflow call before launch, with
one line per call and the fix. A call with a `tierReason` option keeps its model. Options
built at run time are not judged. A script this reader cannot parse, and a saved workflow
called by name, are admitted with a note.

Unreadable input admits: this is a choice check, not a trust boundary.
"""

from __future__ import annotations

import json
import os
import re
import stat
import sys
from pathlib import Path

TABLE = (
    Path(__file__).resolve().parents[1] / "skills/workflow/references/model-tiers.md"
)
SCRIPT_LIMIT = 1_000_000

TIER_REASON = re.compile(r"^[ \t]*Tier reason:", re.MULTILINE)
REVIEWER = re.compile(r"[\w-]*(review\w*|analy[sz]er|hunter|auditor)|qa", re.IGNORECASE)
REVIEW_TEXT = re.compile(r"\bFIX-FIRST\b|\breview the (pasted )?diff\b", re.IGNORECASE)
KEEP_OPUS = re.compile(
    r"\b(secur\w*|credential\w*|secrets?|authenticat\w*|authoriz\w*|concurren\w*|deadlock\w*"
    r"|race condition\w*|persist\w*|sqlite|database\w*|migrat\w*|transaction\w*"
    r"|protocol\w*|trust\w*)\b",
    re.IGNORECASE,
)
MECHANICAL = re.compile(
    r"\bre-?run\w*\b|\bsmoke\w*\b|\bsweep\w*\b|\bprobe\w*\b|\bwatcher\b|\bwatch (the|for|until)\b"
    r"|\bread(s|ing)? ?back\b|\breport each (command|check)\b[^.\n]{0,40}\bexit\b"
    r"|\bmechanical (edit|change|rename|unit)s?\b",
    re.IGNORECASE,
)
STAGE = re.compile(
    r"\b(evidence|ship|shipping|install\w*|smoke\w*|probe\w*|sweep\w*|watch\w*)\b",
    re.IGNORECASE,
)
JUDGMENT = re.compile(
    r"\b(implement\w*|fix|fixes|fixed|fixing|debug\w*|diagnos\w*|design\w*|plan|plans|planning"
    r"|decid\w*|decision\w*|refactor\w*|investigat\w*|root cause|architect\w*|review\w*"
    r"|judge\w*|verif\w*|integrat\w*|audit\w*|execut\w*|build\w*|approv\w*|cure\w*"
    r"|port|porting|ported|resolv\w*|conflict\w*|push|pushes|pushing|move|moves|measur\w*"
    r"|compar\w*|answer\w*|explain\w*|assess\w*|evaluat\w*)\b",
    re.IGNORECASE,
)
EDIT = re.compile(
    r"\b(write|writes|writing|rewrit\w*|make|makes|making|add|adds|adding|change|changes"
    r"|update\w*|remov\w*|creat\w*"
    r"|edit\w*|replac\w*|renam\w*|modif\w*|delet\w*)\b",
    re.IGNORECASE,
)
# A judgment or edit word names the task only where a task verb stands: at the start of a
# sentence or a clause. "Fix X", "then add a test" and ", diagnose it" count; "the build",
# "audit-parent" and "the review" do not (measured on 1028 recorded Agent dispatches).
TASK = (
    r"(?:^|[,;(]|\b(?:and|then|to|also|you|must|please|or|first|next)\b)[ \t*\-\d.)]*"
)
JUDGMENT_TASK = re.compile(TASK + JUDGMENT.pattern, re.IGNORECASE | re.MULTILINE)
EDIT_TASK = re.compile(TASK + EDIT.pattern, re.IGNORECASE | re.MULTILINE)
# A test written first is an implementer's unit, wherever the brief says so.
RED_FIRST = re.compile(r"\b(RED[- ](?:first|before))\b", re.IGNORECASE)
DECLARED = re.compile(r"\bmechanical (edit|change|rename|unit)s?\b", re.IGNORECASE)
# The subjects a prohibition sentence can name without being the standing credential rule.
KEEP_OPUS_STRICT = re.compile(
    r"\b(secur\w*|concurren\w*|deadlock\w*|race condition\w*|persist\w*|migrat\w*"
    r"|transaction\w*|protocol\w*)\b",
    re.IGNORECASE,
)
# A sentence that starts with a prohibition is a rule of the brief, not its subject.
PROHIBITION = re.compile(
    r"^[\W\d]*(never|do not|don't|does not|must not|no|not|nothing)\b", re.IGNORECASE
)
ESCAPE = 'To keep a named model, put a "Tier reason:" line in the brief.'


def tiers() -> dict[str, str] | None:
    """The class-to-model rows of the model-tiers table, or None when it cannot be read."""
    try:
        text = TABLE.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    table: dict[str, str] = {}
    for line in text.splitlines():
        cells = line.split("|")
        if len(cells) < 4 or not line.startswith("|"):
            continue
        models = re.findall(r"`([a-z]+)`", cells[2])
        for klass in re.findall(r"`([a-z_]+)`", cells[1]):
            if models:
                table[klass] = models[0]
    needed = ("mechanical_fanout", "review", "judgment")
    return table if all(name in table for name in needed) else None


def family(model: str) -> str:
    lowered = model.lower()
    return next(
        (name for name in ("haiku", "sonnet", "opus") if name in lowered), lowered
    )


def mismatch(current: str | None, required: str, table: dict[str, str]) -> bool:
    """Only the mechanical tier is exact; a judgment class refuses only that tier (the stage
    table names sonnet for some readers)."""
    light = table["mechanical_fanout"]
    if required == light:
        return current is None or family(current) != light
    return current is not None and family(current) == light


def affirmative(text: str) -> str:
    """The sentences of text that do not start with a prohibition ("Never print a secret" is
    a rule of the brief, not a security unit; "refresh() must not deadlock" stays)."""
    sentences = re.split(r"(?<=[.!?;:])\s+|\n+", text)
    return "\n".join(part for part in sentences if not PROHIBITION.search(part))


def reviewer(kind: str) -> tuple[str, str] | None:
    # The last segment of "plugin:name", bounded: a type name is short.
    if kind and REVIEWER.fullmatch(kind.rsplit(":", 1)[-1][:80]):
        return "review", f"subagent type {json.dumps(kind[:80])}"
    return None


def subject(text: str) -> tuple[str, str] | None:
    """A security, concurrency, persistence, protocol or trust subject of the brief."""
    keep = KEEP_OPUS.search(affirmative(text)) or KEEP_OPUS_STRICT.search(text)
    return ("judgment", f'"{keep.group(0)}"') if keep else None


def emit(output: dict[str, object]) -> int:
    sys.stdout.write(json.dumps({"hookSpecificOutput": output}) + "\n")
    return 0


def context(text: str, update: dict[str, object] | None = None) -> int:
    output: dict[str, object] = {
        "hookEventName": "PreToolUse",
        "additionalContext": text,
    }
    if update is not None:
        output["updatedInput"] = update
    return emit(output)


# --- Agent ---------------------------------------------------------------------------------


def agent_class(data: dict[str, object]) -> tuple[str, str]:
    """(class, signal); class "" is unclassified and "ambiguous" has two signals."""
    kind = data.get("subagent_type")
    brief = " ".join(str(data.get(key) or "") for key in ("description", "prompt"))
    text = affirmative(brief)
    found = reviewer(kind if isinstance(kind, str) else "")
    if found:
        return found
    # A review brief is review before its subject is read: a security review stays a review.
    review = REVIEW_TEXT.search(text)
    if review:
        return "review", f'"{review.group(0)}"'
    found = subject(brief)
    if found:
        return found
    mechanical = MECHANICAL.search(text)
    judgment = JUDGMENT_TASK.search(text) or RED_FIRST.search(text)
    if mechanical and not judgment and not DECLARED.search(text):
        judgment = EDIT_TASK.search(text)
    if mechanical and judgment:
        return "ambiguous", f'"{mechanical.group(0)}" and "{judgment.group(1)}"'
    if mechanical:
        return "mechanical_fanout", f'"{mechanical.group(0)}"'
    return "", ""


def fill(data: dict[str, object], note: str = "") -> int:
    text = (
        'dispatch-tier: this Agent dispatch named no model, so it runs on model: "opus". Name '
        'model: "haiku" explicitly only for a unit that qualifies for it; the workflow route\'s '
        "model-tiers table says which, its overrides included." + note
    )
    return context(text, {**data, "model": "opus"})


def decide_agent(data: dict[str, object]) -> int:
    if data.get("subagent_type") == "fork":
        return 0
    raw = data.get("model")
    model = raw.strip() if isinstance(raw, str) and raw.strip() else None
    if TIER_REASON.search(str(data.get("prompt") or "")):
        return fill(data) if model is None else 0
    klass, signal = agent_class(data)
    if not klass:
        return fill(data) if model is None else 0
    table = tiers()
    if table is None:
        note = " The tier table (model-tiers) could not be read, so no class check ran."
        if model is None:
            return fill(data, note)
        return context("dispatch-tier:" + note)
    if klass == "ambiguous":
        named = model or "opus"
        text = (
            f"dispatch-tier: this brief has a mechanical and a judgment signal ({signal}), so "
            f'its class is ambiguous and it keeps model: "{named}". Split it into a mechanical '
            "unit and a judgment unit when they are independent."
        )
        return context(text, {**data, "model": "opus"} if model is None else None)
    required = table.get(klass)
    if required is None or not mismatch(model, required, table):
        return fill(data) if model is None else 0
    if klass == "judgment" and model is not None:
        # A subject word alone never moves a unit up: on 1027 recorded dispatches it moved 11
        # Haiku units up and most were readbacks or sweeps that only named a stack.
        return context(
            f"dispatch-tier: this brief names a subject ({signal}) that the model-tiers table "
            f'keeps on opus, and it runs on model: "{model}". Check that it is a unit with a '
            'precise contract and an oracle. Put a "Tier reason:" line in the brief to record '
            "why it keeps this model."
        )
    was = f'it was "{model}"' if model else "it named no model"
    text = (
        f"dispatch-tier: this Agent dispatch reads as class {klass} (signal: {signal}), so it "
        f'runs on model: "{required}"; {was}. The workflow route\'s model-tiers table maps the '
        f"class to its tier. {ESCAPE}"
    )
    return context(text, {**data, "model": required})


# --- Workflow ------------------------------------------------------------------------------


class Unreadable(Exception):
    """The script is outside what this reader parses."""


Token = tuple[str, str, int]
# The keywords after which a `/` starts a regular expression, not a division.
REGEX_AFTER = {"return", "typeof", "case", "do", "else", "in", "of", "new", "delete"}
REGEX_AFTER |= {"void", "throw", "instanceof", "yield", "await"}


def lex(src: str, start: int, line: int, nested: bool) -> tuple[list[Token], int, int]:
    """Tokens of src from start. A nested call stops at the `}` that closes a `${`."""
    out: list[Token] = []
    i, n, depth = start, len(src), 0
    while i < n:
        c = src[i]
        if c == "\n":
            line, i = line + 1, i + 1
        elif c.isspace():
            i += 1
        elif src.startswith("//", i):
            end = src.find("\n", i)
            i = n if end < 0 else end
        elif src.startswith("/*", i):
            end = src.find("*/", i + 2)
            if end < 0:
                raise Unreadable("a comment is not closed")
            line, i = line + src.count("\n", i, end), end + 2
        elif c in "'\"":
            value: list[str] = []
            j = i + 1
            while True:
                if j >= n or src[j] == "\n":
                    raise Unreadable(f"a string on line {line} is not closed")
                if src[j] == "\\":
                    line += src[j + 1 : j + 2] == "\n"
                    value.append(src[j + 1 : j + 2])
                    j += 2
                elif src[j] == c:
                    break
                else:
                    value.append(src[j])
                    j += 1
            out.append(("str", "".join(value), line))
            i = j + 1
        elif c == "`":
            first = line
            parts: list[str] = []
            kind, j = "tpl", i + 1
            while True:
                if j >= n:
                    raise Unreadable(f"a template on line {first} is not closed")
                if src[j] == "\\":
                    line += src[j + 1 : j + 2] == "\n"
                    parts.append(src[j + 1 : j + 2])
                    j += 2
                elif src[j] == "`":
                    break
                elif src.startswith("${", j):
                    kind = "tplx"
                    _, j, line = lex(src, j + 2, line, True)
                else:
                    line += src[j] == "\n"
                    parts.append(src[j])
                    j += 1
            out.append((kind, "".join(parts), first))
            i = j + 1
        elif c == "/" and regex_may_start(out):
            j, klass = i + 1, False
            while j < n and src[j] != "\n":
                if src[j] == "\\":
                    j += 1
                elif klass:
                    klass = src[j] != "]"
                elif src[j] == "[":
                    klass = True
                elif src[j] == "/":
                    break
                j += 1
            if j < n and src[j] == "/":
                j += 1
                while j < n and (src[j].isalnum() or src[j] == "_"):
                    j += 1
                out.append(("re", "", line))
                i = j
            else:
                out.append(("p", c, line))
                i += 1
        elif c.isalpha() or c in "_$":
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] in "_$"):
                j += 1
            out.append(("id", src[i:j], line))
            i = j
        elif c.isdigit():
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] in "._"):
                j += 1
            out.append(("num", src[i:j], line))
            i = j
        elif src.startswith("...", i):
            out.append(("p", "...", line))
            i += 3
        else:
            if nested and c == "}" and depth == 0:
                return out, i + 1, line
            depth += {"{": 1, "}": -1}.get(c, 0)
            out.append(("p", c, line))
            i += 1
    if nested:
        raise Unreadable("a template expression is not closed")
    return out, i, line


def regex_may_start(out: list[Token]) -> bool:
    if not out:
        return True
    kind, text, _ = out[-1]
    if kind == "p":
        return text not in (")", "]")
    return kind == "id" and text in REGEX_AFTER


Span = tuple[int, int]
CLOSE = {"(": ")", "[": "]", "{": "}"}


def brackets(tokens: list[Token]) -> dict[int, int]:
    """The index of the closer of each opener, in one pass."""
    pairs: dict[int, int] = {}
    stack: list[int] = []
    for index, (kind, text, line) in enumerate(tokens):
        if kind != "p":
            continue
        if text in CLOSE:
            stack.append(index)
        elif text in ")]}":
            if not stack or CLOSE[tokens[stack[-1]][1]] != text:
                raise Unreadable(f"a bracket on line {line} does not match")
            pairs[stack.pop()] = index
    if stack:
        raise Unreadable(f"a bracket on line {tokens[stack[-1]][2]} is not closed")
    return pairs


def split(tokens: list[Token], pairs: dict[int, int], opener: int) -> list[Span]:
    """The top-level comma parts between an opener and its closer. Each nested bracket is
    stepped over through `pairs`, so each token is visited once per call it is a part of."""
    parts: list[Span] = []
    first = index = opener + 1
    end = pairs[opener]
    while index < end:
        if index in pairs:
            index = pairs[index] + 1
            continue
        if tokens[index][:2] == ("p", ","):
            parts.append((first, index))
            first = index + 1
        index += 1
    parts.append((first, end))
    return [part for part in parts if part[0] < part[1]]


def literal(tokens: list[Token], part: Span) -> str | None:
    kind, text, _ = tokens[part[0]]
    if part[1] - part[0] == 1 and kind in ("str", "tpl", "tplx"):
        return text
    return None


def options(
    tokens: list[Token], pairs: dict[int, int], part: Span
) -> dict[str, str | None] | None:
    """The literal options of an agent() call; None when they are built at run time."""
    first, end = part
    if tokens[first][:2] != ("p", "{") or pairs[first] != end - 1:
        return None
    found: dict[str, str | None] = {}
    for start, stop in split(tokens, pairs, first):
        if (
            stop - start < 3
            or tokens[start][0] not in ("id", "str")
            or tokens[start + 1][:2] != ("p", ":")
        ):
            return None
        key, value = tokens[start][1], (start + 2, stop)
        found[key] = literal(tokens, value)
        if key == "model" and (
            stop - start != 3 or tokens[start + 2][0] not in ("str", "tpl")
        ):
            return None
    return found


def calls(src: str) -> tuple[list[tuple[int, str, dict[str, str | None]]], int]:
    """(line, prompt, options) of each agent() call with literal options, and the count of
    calls whose options are built at run time."""
    tokens, _, _ = lex(src, 0, 1, False)
    pairs = brackets(tokens)
    found: list[tuple[int, str, dict[str, str | None]]] = []
    dynamic = 0
    for index, (kind, text, line) in enumerate(tokens):
        following = tokens[index + 1][:2] if index + 1 < len(tokens) else ("", "")
        if kind != "id" or text != "agent" or following != ("p", "("):
            continue
        before = tokens[index - 1][:2] if index else ("", "")
        if before in (("p", "."), ("id", "function")):
            continue
        args = split(tokens, pairs, index + 1)
        prompt = (literal(tokens, args[0]) or "") if args else ""
        if len(args) < 2:
            found.append((line, prompt, {}))
            continue
        opts = options(tokens, pairs, args[1])
        if opts is None:
            dynamic += 1
        else:
            found.append((line, prompt, opts))
    return found, dynamic


def stage_class(prompt: str, opts: dict[str, str | None]) -> tuple[str, str] | None:
    label, phase = opts.get("label") or "", opts.get("phase") or ""
    found = reviewer(opts.get("agentType") or "")
    if found:
        return found
    stage = STAGE.search(f"{label} {phase}")
    if not stage or JUDGMENT.search(f"{label} {phase}"):
        return None
    # A security, concurrency, persistence, protocol or trust subject in the label, phase or
    # prompt keeps the dispatcher's model. A subject word never forces Opus on a stage: that
    # would deny Haiku sweeps, as it moved recorded Haiku sweeps up on the Agent path.
    if subject(f"{label} {phase}\n{prompt}"):
        return None
    return "mechanical_fanout", f'"{stage.group(0)}"'


def script_of(data: dict[str, object], cwd: object) -> str:
    script = data.get("script")
    if isinstance(script, str):
        if len(script) > SCRIPT_LIMIT:
            raise Unreadable("the script is over 1 MB")
        return script
    raw = data.get("scriptPath")
    if not isinstance(raw, str) or not raw:
        name = data.get("name")
        if isinstance(name, str) and name:
            # shortcut: a saved workflow's file is not read, until its registry path is measured.
            raise Unreadable(
                "a saved workflow called by name; pass its script or scriptPath"
            )
        return ""
    path = Path(raw)
    if not path.is_absolute() and isinstance(cwd, str):
        path = Path(cwd) / path
    try:
        # A FIFO or a device must not hang the hook or see an open: check before and after.
        if not stat.S_ISREG(os.stat(path).st_mode):
            raise Unreadable("scriptPath is not a regular file")
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NONBLOCK), "rb") as handle:
            if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
                raise Unreadable("scriptPath is not a regular file")
            content = handle.read(SCRIPT_LIMIT + 1)
    except OSError as error:
        raise Unreadable(f"scriptPath cannot be read ({error.strerror})") from error
    except ValueError as error:  # a NUL byte or a lone surrogate in the path
        raise Unreadable("scriptPath is not a valid path") from error
    if len(content) > SCRIPT_LIMIT:
        raise Unreadable("the script is over 1 MB")
    try:
        return content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise Unreadable("the script is not UTF-8") from error


def not_checked(why: str) -> int:
    return context(
        f"dispatch-tier: the agent() calls of this Workflow script were not checked against "
        f"the model-tiers table: {why}. Each call must still name the tier of its class."
    )


def decide_workflow(data: dict[str, object], cwd: object) -> int:
    try:
        src = script_of(data, cwd)
        found, dynamic = calls(src) if src else ([], 0)
    except Unreadable as error:
        return not_checked(str(error))
    except RecursionError:
        return not_checked("its templates nest too deep")
    rows: list[str] = []
    table: dict[str, str] | None = None
    for line, prompt, opts in found:
        if "tierReason" in opts:
            continue
        klass = stage_class(prompt, opts)
        if klass is None:
            continue
        table = table or tiers()
        if table is None:
            return not_checked("the tier table (model-tiers) could not be read")
        required = table[klass[0]]
        model = opts.get("model")
        if mismatch(model, required, table):
            current = (
                json.dumps(model) if model else "none (each agent() call names one)"
            )
            label = json.dumps(opts.get("label") or opts.get("phase") or "")
            rows.append(
                f"- line {line}, label {label}: model {current}, required {json.dumps(required)}"
                f" (class {klass[0]}, signal {klass[1]})"
            )
    note = (
        f" {dynamic} agent() call(s) build their options at run time, so their tier was not "
        "checked."
        if dynamic
        else ""
    )
    if rows:
        reason = (
            "dispatch-tier: DENIED before launch. These agent() calls do not use the tier of "
            "their execution class (the workflow route's model-tiers table):\n"
            + "\n".join(rows)
            + "\nFix: set each call's model to the required tier and run the Workflow again. "
            "To keep a named model, add tierReason: '<why>' to that call's options."
            + note
        )
        return emit(
            {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        )
    return context("dispatch-tier:" + note) if note else 0


def decide(payload: dict[str, object]) -> int:
    data = payload.get("tool_input")
    if not isinstance(data, dict):
        return 0
    if payload.get("tool_name") == "Agent":
        return decide_agent(data)
    if payload.get("tool_name") == "Workflow":
        return decide_workflow(data, payload.get("cwd"))
    return 0


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
    except ValueError:
        return 0
    return decide(payload) if isinstance(payload, dict) else 0


if __name__ == "__main__":
    sys.exit(main())
