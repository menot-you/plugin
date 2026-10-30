#!/usr/bin/env -S python3 -B
"""PreToolUse on Bash: only the owner merges a release pull request into `public`.

A `gh … pr merge` of a pull request whose base is `public` is refused
(`release-guard: REFUSED`): the owner's merge of a release PR is the only act that
publishes. The hook reads the base with one `gh pr view` and FAILS CLOSED: a
selector built by shell expansion, a command this scanner cannot read, a merge
behind a shell, wrapper or interpreter whose argv it cannot resolve, or a base
that GitHub does not answer within LIMIT seconds is refused too. `gh api` calls
that can merge or move a branch are judged the same way. Pushes to `public` and to
the member repositories are rows of bash-guards.tsv. It is a separate hook so the
safety table in bash-guards.sh never waits on the network.

The bounded scanner reads simple commands, quoting, comments, continuations,
heredocs and redirections together, and strips executable prefixes (command, exec,
env) and known runners (timeout, nohup, nice, …). It assumes the named commands'
native meanings; it is not a shell parser.

Two channels on refusal: exit 2 with the reason on stderr,
and the JSON permissionDecision deny on stdout.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from collections.abc import Iterator
from dataclasses import dataclass

LIMIT = 5  # aggregate seconds, leaving room inside the native 8/10 second budgets.
STATE_SET = re.compile(
    r"""[ \t]*~/\.nott/bin/state\.sh[ \t]set[ \t](?:'[^'\r\n]*'|"[^"$`\\!\r\n]*")[ \t]*"""
)
ASSIGN = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?(\+?=)")
PUNCTUATION = ";&|()<>\n"
OPERATOR = re.compile(
    r"&>>|&>|(?:[0-9]+)?(?:<<-|<<<|<<|>>|<>|[<>][&|]?)|&&|\|\||[;&|()\n]"
)
PREFIXES = {"{", "}", "!", "then", "do", "else", "elif", "if", "while", "until", "time"}


class Unchecked(Exception):
    """The check could not be made; the message says why."""


@dataclass
class Word:
    text: str
    literal: bool = True
    quoted: bool = False
    operator: bool = False
    assignment: tuple[str, str | None, str] | None = None


def word_at(text: str, i: int) -> tuple[Word, int]:
    """Quote removal without evaluating any shell expansion."""
    word = Word("")
    start = i
    quote = ""
    while i < len(text):
        c = text[i]
        if not quote and (c in " \t\r" or c in PUNCTUATION):
            break
        if c == quote:
            quote = ""
        elif c in "'\"" and not quote:
            quote = c
            word.quoted = True
        elif c == "\\" and quote != "'":
            if i + 1 == len(text):
                raise Unchecked("the command ends with an unfinished escape")
            nxt = text[i + 1]
            if not quote or nxt in '$`"\\\n':
                i += 1
                if nxt != "\n":
                    word.quoted = True
                    word.text += nxt
            else:
                word.text += c
        else:
            if quote != "'":
                if c == "`" or text.startswith(("$(", "$'", '$"'), i):
                    raise Unchecked(
                        "the command uses shell substitution this hook cannot read"
                    )
                if c == "$" or (not quote and c in "*?[]~{"):
                    word.literal = False
            word.text += c
        i += 1
    if quote:
        raise Unchecked("the command has an unbalanced quote")
    if assignment := ASSIGN.match(text[start:i].replace("\\\n", "")):
        word.assignment = assignment.groups()
    return word, i


def tokens(text: str) -> list[Word]:
    """Keep operators distinct from quoted text; bind heredocs at their newline."""
    result: list[Word] = []
    pending: list[tuple[Word, bool]] = []
    i = 0
    while i < len(text):
        if text.startswith("\\\n", i):
            i += 2
            continue
        if text[i] in " \t\r":
            i += 1
            continue
        if text[i] == "#":
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        m = OPERATOR.match(text, i)
        if not m:
            word, i = word_at(text, i)
            result.append(word)
            continue
        op = m[0]
        if op == "(" and result and not result[-1].operator:
            raise Unchecked(
                "function, array or process substitution syntax is unsupported"
            )
        result.append(Word(op, operator=True))
        i = m.end()
        if op.lstrip("0123456789") in ("<<", "<<-"):
            while i < len(text) and text[i] in " \t":
                i += 1
            delimiter, i = word_at(text, i)
            result.append(delimiter)
            pending.append((delimiter, op.endswith("-")))
        if op == "\n":
            for delimiter, dash in pending:
                body: list[str] = []
                while i < len(text):
                    end = text.find("\n", i)
                    end = len(text) if end < 0 else end
                    line = text[i:end]
                    i = min(end + 1, len(text))
                    line = line.lstrip("\t") if dash else line
                    if line == delimiter.text:
                        break
                    body.append(line)
                else:
                    raise Unchecked("a heredoc has no exact closing delimiter")
                value = "\n".join(body)
                delimiter.literal = delimiter.quoted or not re.search(
                    r"(?<!\\)(?:\\\\)*[$`]|\\\n", value
                )
                if not delimiter.quoted and re.search(
                    r"(?<!\\)(?:\\\\)*(?:\$\(|`)", value
                ):
                    raise Unchecked("an unquoted heredoc contains shell substitution")
                delimiter.text = value
            pending = []
    if pending:
        raise Unchecked("a heredoc has no body or exact closing delimiter")
    return result


def segments(
    parts: list[Word],
) -> Iterator[tuple[list[Word], Word | None] | str]:
    """Argv and heredoc stdin of each simple command; parentheses yield themselves."""
    words: list[Word] = []
    stdin = None
    i = 0
    while i < len(parts):
        word = parts[i]
        i += 1
        if not word.operator:
            words.append(word)
            continue
        op = word.text.lstrip("0123456789")
        if op.startswith(("<", ">")) or op in ("&>", "&>>"):
            if i == len(parts) or parts[i].operator:
                raise Unchecked("a redirection has no literal target")
            target = parts[i]
            i += 1
            fd = word.text[: -len(op)] or ("0" if op.startswith("<") else "1")
            if fd == "0":
                stdin = target if op in ("<<", "<<-") else None
            continue
        if words:
            yield words, stdin
        words, stdin = [], None
        if op in ("(", ")"):
            yield op
    if words:
        yield words, stdin


def command_words(words: list[Word]) -> tuple[list[Word], dict[str, Word]]:
    """Strip executable prefixes, retaining literal environment assignments."""
    env: dict[str, Word] = {}
    assignment_mode = "shell"
    prefixes = True
    external = False
    while words:
        first = words[0]
        if prefixes and not first.quoted and first.text in PREFIXES:
            words = words[1:]
        elif assignment_mode != "none" and (
            assignment := (
                first.assignment
                if assignment_mode == "shell"
                else match.groups()
                if (match := ASSIGN.match(first.text))
                else None
            )
        ):
            name, subscript, operator = assignment
            if assignment_mode == "env" and (subscript is not None or operator != "="):
                raise Unchecked("an env assignment uses unsupported syntax")
            # Append and indexed assignment depend on prior shell state. Retain
            # the variable identity, but never treat their RHS as its final value.
            env[name] = Word(
                first.text[len(name) + 1 :]
                if operator == "=" and subscript is None
                else "",
                first.literal and subscript is None and operator == "=",
            )
            words = words[1:]
            prefixes = False
        elif first.literal and first.text.rsplit("/", 1)[-1] in (
            "command",
            "exec",
            "env",
        ):
            wrapper = first.text.rsplit("/", 1)[-1]
            if external and wrapper in ("command", "exec"):
                raise Unchecked("an env process cannot execute a shell builtin wrapper")
            external = external or wrapper == "env"
            prefixes = False
            assignment_mode = "env" if wrapper == "env" else "none"
            words = words[1:]
            while words and words[0].text.startswith("-"):
                option = words.pop(0)
                if not option.literal:
                    raise Unchecked(
                        "a command wrapper option is built by shell expansion"
                    )
                flag = option.text
                if wrapper == "command" and flag in ("-v", "-V"):
                    return [], env  # inspection, not execution
                if wrapper == "env":
                    # An unset name is recorded empty, as gh reads an empty GH_REPO,
                    # so it can override the GH_REPO this hook itself inherited.
                    if flag in ("-i", "--ignore-environment"):
                        env.clear()
                        env["GH_REPO"] = Word("")
                        continue
                    if flag in ("-u", "--unset"):
                        if not words or not words[0].literal:
                            raise Unchecked("an env unset option has no literal name")
                        env[words.pop(0).text] = Word("")
                        continue
                    if flag.startswith(("--unset=", "-u")):
                        name = flag.split("=", 1)[1] if "=" in flag else flag[2:]
                        env[name] = Word("")
                        continue
                if flag != "--" and not (wrapper == "command" and flag == "-p"):
                    raise Unchecked("a command wrapper has unsupported options")
                if flag == "--":
                    break
        else:
            break
    return words, env


# gh pr merge options that take a value. Every other option is a flag.
MERGE_VALUED = {
    "body",
    "body-file",
    "subject",
    "author-email",
    "match-head-commit",
    "repo",
}
MERGE_VALUED_SHORT = {
    "b": "body",
    "F": "body-file",
    "t": "subject",
    "A": "author-email",
    "R": "repo",
}
RELEASE_REFUSAL = (
    "release-guard: REFUSED — {why} Only the owner merges a release PR into public. "
    "His merge starts the release workflow, which publishes the members."
)


# Wrappers that run their argv after their own options. `timeout` takes a duration.
RUNNERS = {"timeout", "nohup", "nice", "stdbuf", "setsid", "time", "caffeinate"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
# Interpreters and builders of commands this hook cannot read argv from.
OPAQUE = {
    "xargs",
    "eval",
    "source",
    ".",
    "python",
    "python3",
    "node",
    "perl",
    "ruby",
    "parallel",
    "watch",
}
MERGE_API = re.compile(r"/?repos/([\w.-]+)/([\w.-]+)/pulls/([0-9]+)/merge")


def runner_argv(words: list[Word]) -> list[Word]:
    """The argv a wrapper runs: its own options and a timeout's duration removed."""
    name = words[0].text.rsplit("/", 1)[-1]
    rest = words[1:]
    while rest and rest[0].text.startswith("-"):
        option = rest.pop(0).text
        if (
            name in ("nice", "stdbuf")
            and option in ("-n", "-i", "-o", "-e")
            and rest
            or name == "timeout"
            and option in ("-s", "-k", "--signal", "--kill-after")
            and rest
        ):
            rest.pop(0)
        if option == "--":
            break
    if name == "timeout":
        if not rest:
            raise Unchecked("timeout has no command")
        rest.pop(0)
    return rest


API_VALUED = {"X", "f", "F", "H", "q", "t", "p"}
API_VALUED_LONG = {
    "method", "field", "raw-field", "header", "input", "jq", "template",
    "hostname", "cache", "preview",
}  # fmt: skip


def api_endpoint(argv: list[Word]) -> Word | None:
    """The endpoint of a `gh api` argv: its first operand after `api`."""
    rest = argv[[w.text for w in argv].index("api") + 1 :]
    k = 0
    while k < len(rest):
        text = rest[k].text
        if text.startswith("--"):
            if text[2:] in API_VALUED_LONG:
                k += 1
        elif text.startswith("-") and len(text) > 1:
            if text[1:] in API_VALUED:
                k += 1
        else:
            return rest[k]
        k += 1
    return None


def merge_targets(
    cmd: str, depth: int = 0, *, original_cmd: str | None = None
) -> list[tuple[str | None, Word | None, bool, str | None]]:
    """Each merge in the command: its selector, repository, and changed context.

    A merge this hook cannot resolve raises Unchecked, so the caller refuses it.
    """
    # Test the command as received, not the Bash guard's transformed scan text.
    # Only the whole command qualifies; nested shells keep the original scan.
    if depth == 0 and STATE_SET.fullmatch(
        cmd if original_cmd is None else original_cmd
    ):
        return []
    if depth > 3:
        raise Unchecked("the shells nest too deep")
    found: list[tuple[str | None, Word | None, bool, str | None]] = []
    changed = False
    for segment in segments(tokens(cmd)):
        if isinstance(segment, str):
            continue
        words, env = command_words(segment[0])
        while words and words[0].literal:
            name = words[0].text.rsplit("/", 1)[-1]
            if name in RUNNERS:
                words, inner = command_words(runner_argv(words))
                env.update(inner)
            else:
                break
        text = " ".join(word.text for word in segment[0])
        if segment[1] is not None:
            text += " " + segment[1].text
        if not words:
            if any(word.assignment for word in segment[0]):
                changed = True
            continue
        name = words[0].text.rsplit("/", 1)[-1]
        if not words[0].literal:
            if "merge" in text.lower():
                raise Unchecked("the executable is named by shell expansion")
            continue
        if name in ("cd", "pushd", "popd", "export", "unset") or (
            name == "git" and {"switch", "checkout"} & {w.text for w in words}
        ):
            changed = True
            continue
        if name in SHELLS:
            script = next(
                (
                    words[k + 1]
                    for k, word in enumerate(words[1:-1], 1)
                    if re.fullmatch(r"-[a-z]*c[a-z]*", word.text)
                ),
                None,
            )
            if script is None:
                if "merge" in text.lower():
                    raise Unchecked("a shell runs a script this hook cannot read")
                continue
            if not script.literal and "merge" in script.text.lower():
                raise Unchecked("a shell script is built by shell expansion")
            nested = merge_targets(script.text, depth + 1)
            found += [
                (sel, repo, moved or changed, pin) for sel, repo, moved, pin in nested
            ]
            continue
        if name in OPAQUE:
            if re.search(r"gh\b", text) and "merge" in text.lower():
                raise Unchecked(f"{name} runs a merge whose argv this hook cannot read")
            continue
        if name != "gh":
            continue
        repo = env.get("GH_REPO")
        pos: list[Word] = []
        argv = words[1:]
        help_requested = False
        pin: str | None = None
        k = 0
        while k < len(argv):
            token, option = argv[k], argv[k].text
            if option.startswith("--"):
                if option == "--help":
                    help_requested = True
                key, eq, value = option[2:].partition("=")
                if key in MERGE_VALUED and not eq and k + 1 < len(argv):
                    k += 1
                    token, value = argv[k], argv[k].text
                if key == "repo":
                    repo = Word(value, token.literal)
                if key == "match-head-commit":
                    if not token.literal:
                        raise Unchecked("the merge pin is named by shell expansion")
                    if pin is not None:
                        raise Unchecked("the merge has more than one head pin")
                    pin = value
            elif option.startswith("-") and len(option) > 1:
                for index, letter in enumerate(option[1:], 2):
                    if letter == "h":
                        help_requested = True
                    if letter in MERGE_VALUED_SHORT:
                        value = option[index:].removeprefix("=")
                        if not value and k + 1 < len(argv):
                            k += 1
                            token, value = argv[k], argv[k].text
                        if letter == "R":
                            repo = Word(value, token.literal)
                        break
            else:
                pos.append(token)
            k += 1
        if pos and pos[0].text == "api":
            if "merge" not in text.lower() and "refs/heads/public" not in text:
                continue
            endpoint = api_endpoint(argv)
            match = (
                MERGE_API.fullmatch(endpoint.text)
                if endpoint is not None and endpoint.literal
                else None
            )
            if match is None:
                raise Unchecked("a gh api call can merge or move a branch")
            found.append((match[3], Word(f"{match[1]}/{match[2]}"), False, None))
            continue
        if [word.text for word in pos[:2]] != ["pr", "merge"]:
            continue
        if help_requested:
            continue
        if not all(word.literal for word in pos[:3]):
            raise Unchecked("the pull request is named by shell expansion")
        if repo is not None and not repo.literal:
            raise Unchecked("the repository is named by shell expansion")
        found.append((pos[2].text if len(pos) > 2 else None, repo, changed, pin))
    return found


def merge_refusal(cmd: str, cwd: str) -> str:
    """A refusal for a merge into public, or the empty string."""
    deadline = time.monotonic() + LIMIT
    for selector, repo, changed, _pin in merge_targets(cmd):
        named = repo is not None and bool(repo.text)
        url = selector is not None and selector.startswith("https://")
        if changed and not (named or url):
            # The directory or branch can differ from the merge's own: ask GitHub
            # about the pull request itself, never about the session context.
            raise Unchecked("the command changes directory or branch before the merge")
        if changed and selector is None:
            raise Unchecked(
                "the command changes branch before a merge with no selector"
            )
        query = ["gh", "pr", "view", *([selector] if selector else [])]
        query += ["--json", "baseRefName", "--jq", ".baseRefName"]
        environ = None
        if repo is not None and repo.text:
            query += ["--repo", repo.text]
        elif repo is not None:
            environ = {k: v for k, v in os.environ.items() if k != "GH_REPO"}
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise Unchecked(f"the {LIMIT} s lookup budget is exhausted")
        try:
            base = subprocess.run(
                query,
                cwd=cwd,
                env=environ,
                capture_output=True,
                text=True,
                timeout=remaining,
                check=True,
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            raise Unchecked(
                "GitHub did not answer the base of the pull request"
            ) from None
        if base == "public":
            return RELEASE_REFUSAL.format(why="this pull request merges into public.")
        if not base:
            raise Unchecked("GitHub returned no base for the pull request")
    return ""


def main() -> int:
    # The Bash guard uses the same scanner without a GitHub lookup.
    if sys.argv[1:] in (
        ["--merge-evidence-targets"],
        ["--merge-evidence-targets-from-hook"],
    ):
        try:
            cmd = sys.stdin.read()
            original_cmd = None
            if sys.argv[1] == "--merge-evidence-targets-from-hook":
                payload_text, cmd = cmd.split("\0", 1)
                original_cmd = json.loads(payload_text)["tool_input"]["command"]
                if not isinstance(original_cmd, str):
                    return 1
            targets = merge_targets(cmd, original_cmd=original_cmd)
        except (KeyError, TypeError, ValueError, Unchecked):
            return 1
        json.dump(
            [
                (number, repo.text if repo else None, changed, pin)
                for number, repo, changed, pin in targets
            ],
            sys.stdout,
        )
        return 0
    try:
        payload = json.loads(sys.stdin.read())
    except ValueError:
        return 0
    if not isinstance(payload, dict) or payload.get("tool_name") != "Bash":
        return 0
    tool_input = payload.get("tool_input")
    cmd = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(cmd, str):
        return 0
    # A cheap candidate hint only. Quote removal and line joining here must not
    # exclude argv the scanner will recognize; hints never supply a decision.
    hint = cmd.replace("\\\n", "").translate(str.maketrans("", "", "\\'\""))
    # Any gh call with a merge in it: wrappers, shells, xargs and the API spell it
    # differently, and each one the parser cannot resolve is refused.
    if re.search(r"gh\b", hint) and (
        "merge" in hint.lower() or "refs/heads/public" in hint
    ):
        cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) else None
        try:
            refusal = merge_refusal(cmd, cwd or os.getcwd())
        except (ValueError, Unchecked) as error:
            refusal = RELEASE_REFUSAL.format(
                why=f"the base of a gh pr merge could not be read ({error}). Name the PR by a literal number."
            )
        if refusal:
            sys.stderr.write(refusal + "\n")
            decision = {
                "permissionDecision": "deny",
                "permissionDecisionReason": refusal,
            }
            sys.stdout.write(
                json.dumps(
                    {"hookSpecificOutput": {"hookEventName": "PreToolUse", **decision}}
                )
                + "\n"
            )
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
