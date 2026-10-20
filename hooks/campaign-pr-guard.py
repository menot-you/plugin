#!/usr/bin/env python3
"""PreToolUse on Bash: one campaign, one pull request.

The rule is plugin/skills/plan/references/campaign-loop.md ("Shape: lanes, one
integration, one landing"); the pull request template carries its `Campaign:` line.
A `gh [options] pr create|new` invocation whose body's first `Campaign:` line names
`cap-<n>` is refused when another OPEN pull request of the same repository already
carries that line, and the refusal names it. `none`, another value, or no line passes.

The bounded scanner reads simple commands, quoting, comments, continuations and
redirections together. Only executable `gh … pr create|new` argv and literal inline
or regular-file bodies (`-b/--body`, `-F/--body-file`) are judged. Stdin (`-F -`),
nonregular files and unsupported shell syntax are reported as NOT CHECKED rather
than read, guessed or executed. A regular body file is read only when every earlier
command is a modeled cp/mv/tee or redirection whose
targets miss it, or one of a closed set that writes no file; any other earlier
command may have changed it, so its disk contents are not judged.
The copy/move model accepts only closed plain-file options, without link or
directory source topology. Repository-environment noninterference has a separate
closed positive grammar: literal cat/cp/mv/tee/git/gh/timeout executables, harmless
:/true/false/echo/test without assignments, printf with a literal format containing
only %% or %s directives (an optional --), single-operand cd (optional --),
unquoted fi/done, and `for <lowercase-name> in <words>`. Arguments may contain
globs/brace expansion or read-only $NAME/${NAME}; other parameter expansion is
unknown. Literal prefixes admit command [--/-p] (or inspection -v/-V), exec [--],
and env [--/-i/--ignore-environment/-u NAME/--unset NAME/--unset=NAME/-uNAME] with
plain NAME=VALUE operands. command/exec operands are executable names, not shell
assignments, and keywords are stripped only before assignments/executable prefixes.
An env process cannot invoke command/exec as shell builtins. Its supported external
printf preserves the parent's environment; a shell-named cd remains an unknown cwd
until its subshell scope restores it. Bare assignments,
unknown commands/builtins/wrappers, nonliteral executables, assigning expansion,
printf -v or %n and unsupported control/state syntax cannot preserve repository
state. Functions and shell evaluation are unsupported, never assumed external.
Assignments are recognized before quote removal: only an unquoted/unescaped LHS
is shell assignment syntax; RHS quoting is supported. Append/indexed values are
unresolved. Once repository state is unknown it stays unknown; a create can still
select independently with a literal --repo or current-command plain GH_REPO=.
Expansion effects precede the command; its execution effects affect later commands
only. This fail-open static helper assumes the named commands' native meanings;
it is not a shell parser or a security/authorization boundary.

Fail-open by owner decision (2026-10-10): a network fault must not block standalone
work. Whenever the check cannot be made (a body that is not a literal this hook can
read, GitHub unreadable or slower than LIMIT seconds, a search that may be
incomplete, a command that does not tokenize) the command is allowed with a
`campaign-pr-guard: NOT CHECKED` context, never in silence. It is a separate hook so
the safety table in bash-guards.sh never waits on the network.

A `gh … pr merge` of a pull request whose base is `public` is refused
(`release-guard: REFUSED`): the owner's merge of a release PR is the only act that
publishes. This check reads the base with one `gh pr view` and FAILS CLOSED: a
selector built by shell expansion, a command this scanner cannot read, or a base
that GitHub does not answer is refused too. Pushes to `public` and to the member
repositories are rows of bash-guards.tsv.

Two channels on refusal, as in red-first.sh: exit 2 with the reason on stderr,
and the JSON permissionDecision deny on stdout.
"""

from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
import time
from collections.abc import Iterator
from dataclasses import dataclass

LIMIT = 5  # aggregate seconds, leaving room inside the native 8/10 second budgets.
SEARCH_CAP = 100
FIRST_LINE = re.compile(r"(?m)^[ \t]*Campaign:[ \t]*(\S+)[ \t]*\r?$")
ASSIGN = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?(\+?=)")
PUNCTUATION = ";&|()<>\n"
OPERATOR = re.compile(
    r"&>>|&>|(?:[0-9]+)?(?:<<-|<<<|<<|>>|<>|[<>][&|]?)|&&|\|\||[;&|()\n]"
)
PREFIXES = {"{", "}", "!", "then", "do", "else", "elif", "if", "while", "until", "time"}
# gh pr create options that take a value: skipped when looking for `pr create`.
VALUED = set("tbFBHalmprRT")
VALUED_LONG = {
    "title", "body", "body-file", "base", "head", "assignee", "label",
    "milestone", "project", "reviewer", "repo", "template",
}  # fmt: skip
# Commands that write no file except through the redirections tracked beside them.
# The set is closed: any other executable, wrapper, interpreter or shell may, and
# so may every git and gh argv: Git runs configured hooks, filters and fsmonitor
# in it, and gh runs Git itself (status, push), a pager or a browser.
NON_WRITERS = {
    ":", "true", "false", "echo", "printf", "cat", "test",
    "cd", "pushd", "popd", "for", "done", "fi",
}  # fmt: skip
# Only these known external commands prove shell-environment noninterference.
# File effects remain independent: Git/GH callbacks are still unknown writers.
REPO_EXTERNALS = {"cat", "cp", "mv", "tee", "git", "gh", "timeout"}
REPO_HARMLESS = {":", "true", "false", "echo", "test"}
READ_ONLY_PARAMETER = re.compile(
    r"\$(?:[A-Za-z_][A-Za-z0-9_]*|\{[A-Za-z_][A-Za-z0-9_]*\})"
)


class Unchecked(Exception):
    """The check could not be made; the message says why."""


@dataclass
class Word:
    text: str
    literal: bool = True
    quoted: bool = False
    operator: bool = False
    assignment: tuple[str, str | None, str] | None = None
    repo_safe: bool = True


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
                if c == "$" and not READ_ONLY_PARAMETER.match(text, i):
                    # Only read-only named parameters have proven no assignment
                    # effect. Never infer what another expansion evaluates to.
                    word.repo_safe = False
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
                delimiter.repo_safe = delimiter.literal
            pending = []
    if pending:
        raise Unchecked("a heredoc has no body or exact closing delimiter")
    return result


def segments(
    parts: list[Word],
) -> Iterator[tuple[list[Word], Word | None, list[Word], list[Word]] | str]:
    """Argv, stdin, writes and all redirect expansions; parentheses scope cwd."""
    words: list[Word] = []
    writes: list[Word] = []
    expansions: list[Word] = []
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
            expansions.append(target)
            fd = word.text[: -len(op)] or ("0" if op.startswith("<") else "1")
            if fd == "0":
                stdin = target if op in ("<<", "<<-") else None
            if op in (">", ">>", ">|", "<>", "&>", "&>>") or (
                op == ">&"
                and not (target.literal and re.fullmatch(r"[0-9]+-?|-", target.text))
            ):
                writes.append(target)
            continue
        if words or expansions:
            yield words, stdin, writes, expansions
        words, stdin, writes, expansions = [], None, [], []
        if op in ("(", ")"):
            yield op
    if words or expansions:
        yield words, stdin, writes, expansions


def command_words(words: list[Word]) -> tuple[list[Word], dict[str, Word], bool]:
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
                repo_safe=first.repo_safe,
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
                    return [], env, external  # inspection, not execution
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
    return words, env, external


def gh_argv(words: list[Word]) -> tuple[dict[str, Word], list[str]] | None:
    """Options and command words of a `gh` argv, or None for another executable."""
    if not words:
        return None
    if not words[0].literal:
        raise Unchecked("the executable is named by shell expansion")
    if words[0].text.rsplit("/", 1)[-1] != "gh":
        return None
    opts: dict[str, Word] = {}
    pos: list[str] = []
    k, argv = 0, words[1:]
    while k < len(argv):
        token = argv[k]
        a = token.text
        if a.startswith("--"):
            name, eq, value = a[2:].partition("=")
            if any(c in name for c in "$`*?[]~"):
                raise Unchecked("a gh option name is built by shell expansion")
            if name in VALUED_LONG and not eq and k + 1 < len(argv):
                token, k = argv[k + 1], k + 1
                value = token.text
            opts[name] = Word(value, token.literal)
        elif a.startswith("-") and len(a) > 1:
            for index, letter in enumerate(a[1:], 2):
                if letter in VALUED:
                    value = a[index:]
                    if value.startswith("="):
                        value = value[1:]
                    elif not value and k + 1 < len(argv):
                        token, k = argv[k + 1], k + 1
                        value = token.text
                    opts[
                        {"R": "repo", "b": "body", "F": "body-file"}.get(letter, letter)
                    ] = Word(value, token.literal)
                    break
        else:
            if not token.literal:
                raise Unchecked("a gh command word is built by shell expansion")
            pos.append(a)
        k += 1
    return opts, pos


def gh_create(words: list[Word], env: dict[str, Word]) -> dict[str, Word] | None:
    """The options of a `gh … pr create|new` argv, or None for any other command."""
    parsed = gh_argv(words)
    if parsed is None or parsed[1][:2] not in (["pr", "create"], ["pr", "new"]):
        return None
    opts = parsed[0]
    repo = opts.pop("repo", None)
    if repo is not None and (repo.text or not repo.literal):
        opts["repo"] = repo
    elif "GH_REPO" in env:
        # gh falls back to GH_REPO: this command's own value, or the cwd's
        # repository when the command empties or unsets it.
        opts["repo"] = env["GH_REPO"]
    return opts


def file_path(cwd: str, path: str) -> str:
    return os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))


def non_writer(words: list[Word]) -> bool:
    """Whether this argv is in the closed set that writes no file of its own."""
    if not words[0].literal:
        return False
    return words[0].text.rsplit("/", 1)[-1] in NON_WRITERS


def repository_unchanged(
    words: list[Word], env: dict[str, Word], external: bool
) -> bool:
    """Prove noninterference only for the finite grammar in the module contract."""
    if any(not word.repo_safe for word in words) or any(
        not word.literal or not word.repo_safe for word in env.values()
    ):
        return False
    if not words:
        return not env  # bare assignments are shell state, not temporary argv env
    if not words[0].literal:
        return False
    first = words[0].text.rsplit("/", 1)[-1]
    if first in REPO_EXTERNALS:
        return True
    if env and not external:
        return False
    if first in REPO_HARMLESS:
        return True
    args = words[1:]
    if first == "printf":
        if args and args[0].literal and args[0].text == "--":
            args = args[1:]
        elif args and args[0].text.startswith("-"):
            return False  # separate/attached -v, or any other unmodeled option
        return bool(
            args and args[0].literal and re.fullmatch(r"(?:[^%]|%%|%s)*", args[0].text)
        )
    if first == "cd":
        if args and args[0].literal and args[0].text == "--":
            args = args[1:]
        # Directory resolution is owned by the cwd model. A read-only operand
        # can name an unknown cwd without assigning repository environment.
        return len(args) == 1
    if not words[0].quoted and words[0].text in ("fi", "done"):
        return not args
    return bool(
        not words[0].quoted
        and words[0].text == "for"
        and len(args) >= 2
        and args[0].literal
        and not args[0].quoted
        and re.fullmatch(r"[a-z_][a-z0-9_]*", args[0].text)
        and args[1].text == "in"
        and not args[1].quoted
    )


def writer_targets(words: list[Word], cwd: str) -> list[Word]:
    """Possible writes of an argv, without interpreting its input contents.

    cp/mv/tee name their targets and the closed non-writer set names none. Any
    other command may write any file: one unresolved target stands for that.
    """
    # timeout owns the options and duration before its executable. Peel only
    # this known wrapper; never search printed data for a possible writer.
    while words and words[0].text.rsplit("/", 1)[-1] == "timeout":
        i = 1
        while i < len(words) and words[i].text.startswith("-"):
            flag = words[i].text
            i += 1
            if flag == "--":
                break
            if flag in ("-s", "--signal", "-k", "--kill-after"):
                if i == len(words):
                    return [Word("", literal=False)]
                i += 1
            elif flag not in ("--foreground", "--preserve-status", "--verbose") and (
                not flag.startswith(("--signal=", "--kill-after=", "-s", "-k"))
            ):
                return [Word("", literal=False)]
        if any(not word.literal for word in words[: i + 1]):
            # Expansion may insert a different wrapper, executable or cwd.
            return [Word("", literal=False)]
        try:
            words, _, _ = command_words(words[i + 1 :])  # skip the duration too
        except Unchecked:
            return [Word("", literal=False)]
    if not words:
        return []
    executable = words[0].text.rsplit("/", 1)[-1]
    if executable not in ("cp", "mv", "tee"):
        # Absence from the writer model is no proof that nothing was written:
        # sed -i, interpreters, ln, other wrappers and nested shells all may.
        return [] if non_writer(words) else [Word("", literal=False)]
    operands: list[Word] = []
    directory = None
    options = True
    i = 1
    while i < len(words):
        word = words[i]
        i += 1
        if options and word.text == "--":
            options = False
        elif options and word.text.startswith("-") and word.text != "-":
            if executable != "tee":
                # A target option owns its attached value, including letters
                # that would otherwise name backup or directory modifiers.
                if word.text in ("-t", "--target-directory"):
                    if i == len(words):
                        return [Word("", literal=False)]
                    directory = words[i]
                    i += 1
                elif word.text.startswith(("--target-directory=", "-t")):
                    value = (
                        word.text.split("=", 1)[1]
                        if "=" in word.text
                        else word.text[2:]
                    )
                    directory = Word(value, word.literal)
                # Directory modifiers, sidecars and unmodeled long options
                # cannot use the simple basename destination model safely.
                elif not word.literal or (
                    not word.text.startswith("--")
                    and any(letter not in "finpvuL" for letter in word.text[1:])
                ):
                    # Only known plain-file options retain the destination model.
                    # Link/archive/recursive modes can create future aliases that
                    # neither realpath nor samefile can see before execution.
                    return [Word("", literal=False)]
                elif word.text.startswith("--") and word.text not in (
                    "--force", "--interactive",
                    "--no-clobber", "--remove-destination", "--verbose",
                    "--strip-trailing-slashes", "--dereference",
                ):  # fmt: skip
                    return [Word("", literal=False)]
        else:
            operands.append(word)
    if executable == "tee":
        return operands
    if directory is None:
        if len(operands) < 2:
            # One syntactic operand can expand into both source and target.
            # An incomplete literal argv writes nothing; expansion is unknown.
            return (
                [Word("", literal=False)]
                if any(not word.literal for word in operands)
                else []
            )
        directory = operands.pop()
        targets = (
            []
            if directory.literal and os.path.isdir(file_path(cwd, directory.text))
            else [directory]
        )
    else:
        targets = []
    if any(
        source.literal
        and (
            os.path.islink(os.path.join(cwd, source.text))
            or os.path.isdir(file_path(cwd, source.text))
        )
        for source in operands
    ):
        return [Word("", literal=False)]
    targets += [
        Word(
            os.path.join(directory.text, os.path.basename(source.text.rstrip("/"))),
            directory.literal and source.literal,
        )
        for source in operands
    ]
    if executable == "mv":
        targets += operands  # moving also invalidates a body at the source path
    return targets


def write_paths(targets: list[Word], cwd: str, moved: bool) -> tuple[set[str], bool]:
    """Canonical paths of possible writes, and whether any is unresolved."""
    paths: set[str] = set()
    unresolved = False
    for target in targets:
        if not target.literal or (
            moved and not os.path.isabs(os.path.expanduser(target.text))
        ):
            unresolved = True
        else:
            paths.add(file_path(cwd, target.text))
    return paths, unresolved


def same_file(left: str, right: str) -> bool:
    """Existing hard links share writes even when their canonical paths differ."""
    try:
        return os.path.samefile(left, right)
    except (FileNotFoundError, NotADirectoryError):
        return False
    except OSError:
        raise Unchecked(
            "a possible body-file write's file identity is unreadable"
        ) from None


def body_of(
    opts: dict[str, Word],
    cwd: str,
    _heredoc: Word | None,
    writes: set[str],
    uncertain_write: bool,
) -> str | None:
    if "body" in opts:
        if not opts["body"].literal:
            raise Unchecked("its --body is built by the shell, not a literal")
        return opts["body"].text
    source = opts.get("body-file")
    if source is None:
        return None
    if not source.literal:
        raise Unchecked("its body file is named by the shell, not a literal")
    path = source.text
    if path == "-":
        raise Unchecked("its body comes from stdin, not a regular file")
    resolved = file_path(cwd, path)
    if uncertain_write or any(
        resolved == target
        or resolved.startswith(target + os.sep)
        or same_file(resolved, target)
        for target in writes
    ):
        raise Unchecked(
            f"this command may change its body file {path} before gh reads it; disk contents are stale"
        )
    try:
        if not stat.S_ISREG(os.stat(resolved).st_mode):
            raise Unchecked(f"its body file {path} is not a regular file")
        with open(resolved, encoding="utf-8") as f:
            return f.read()
    except OSError as error:
        raise Unchecked(
            f"its body file {path} could not be read ({error.strerror})"
        ) from None


def open_with(cid: str, repo: str | None, cwd: str, deadline: float) -> str | None:
    """`#<number> <url>` of an open pull request whose Campaign line is cid, or None."""
    query = ["gh", "pr", "list", "--state", "open", "--limit", str(SEARCH_CAP),
             "--json", "number,url,body", "--search", f'"Campaign: {cid}" in:body']  # fmt: skip
    environ = None
    if repo:
        query += ["--repo", repo]
    elif repo == "":
        # The command cleared GH_REPO, so its gh asks the cwd's repository: never
        # let this lookup ask the one named by the hook's inherited GH_REPO.
        environ = {
            name: value for name, value in os.environ.items() if name != "GH_REPO"
        }
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise Unchecked(f"the command's aggregate {LIMIT} s lookup budget is exhausted")
    try:
        out = subprocess.run(
            query,
            cwd=cwd,
            env=environ,
            capture_output=True,
            text=True,
            timeout=remaining,
            check=True,
        ).stdout
        found = json.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError):
        raise Unchecked(
            f"reading GitHub failed or exhausted the command's aggregate {LIMIT} s budget"
        ) from None
    if not isinstance(found, list):
        raise Unchecked("GitHub's answer was not a list of pull requests")
    for pr in found:
        body = pr.get("body") if isinstance(pr, dict) else None
        m = FIRST_LINE.search(body) if isinstance(body, str) else None
        if m and m[1] == cid:
            return f"#{pr.get('number')} {pr.get('url')}"
    if len(found) >= SEARCH_CAP:
        raise Unchecked(
            f"GitHub's search returned its cap of {SEARCH_CAP}, so it may be incomplete"
        )
    return None


def decide(cmd: str, cwd: str) -> tuple[int, str]:
    deadline = time.monotonic() + LIMIT
    parts = tokens(cmd)
    notes: list[str] = []
    moved = False
    writes: set[str] = set()
    uncertain_write = False
    uncertain_repo = False
    scopes: list[tuple[str, bool]] = []
    for segment in segments(parts):
        if segment == "(":
            scopes.append((cwd, moved))
            continue
        if segment == ")":
            if not scopes:
                raise Unchecked("a subshell closes without an opening parenthesis")
            cwd, moved = scopes.pop()
            continue
        words, stdin, redirects, expansions = segment
        cid = "?"
        effects: tuple[set[str], bool] = (set(), False)
        repo_effect = True  # unknown until a supported command proves otherwise
        # Arguments and redirections expand before this command runs, including
        # assignments performed by parameter expansion in a harmless builtin.
        uncertain_repo = uncertain_repo or any(
            not word.repo_safe for word in words + expansions
        )
        try:
            try:
                words, env, external = command_words(words)
                repo_effect = not repository_unchanged(words, env, external)
            except Unchecked:
                # An unsupported execution prefix may hide a file writer too.
                # Its warning alone cannot justify reading a later stale body.
                uncertain_write = True
                raise
            finally:
                # Retain redirects even when an executable prefix is unsupported.
                # Resolve before cd; filesystem effects also survive subshells.
                # The shell opens redirects before the command runs, so they may
                # change its own body file. What the command runs may change only
                # later ones: gh reads its body file before it runs Git.
                paths, unresolved = write_paths(redirects, cwd, moved)
                writes |= paths
                uncertain_write = uncertain_write or unresolved
                effects = write_paths(writer_targets(words, cwd), cwd, moved)
            if not words:
                continue
            first = words[0].text
            if first in ("case", "function", "eval", "source", "."):
                raise Unchecked(
                    "the command uses unsupported shell control or evaluation syntax"
                )
            if first.rsplit("/", 1)[-1] in ("bash", "sh", "zsh"):
                raise Unchecked("a nested shell command cannot be read by this hook")
            if first in ("cd", "pushd", "popd"):
                args = words[1:]
                if args and args[0].text == "--":
                    args = args[1:]
                if first != "cd" or len(args) != 1 or not args[0].literal:
                    moved = True
                else:
                    cwd = os.path.join(cwd, args[0].text)
                continue
            opts = gh_create(words, env)
            if opts is None:
                # echo/printf arguments are printed data. For other commands,
                # unjudged gh argv may sit behind an executable wrapper. Reuse
                # the option-aware predicate; do not guess or execute wrappers.
                if first.rsplit("/", 1)[-1] not in ("echo", "printf"):
                    for index, word in enumerate(words[1:], 1):
                        if (
                            word.literal
                            and word.text.rsplit("/", 1)[-1] == "gh"
                            and gh_create(words[index:], {}) is not None
                        ):
                            raise Unchecked(
                                "a possible `gh pr create|new` invocation is behind "
                                "an unsupported executable wrapper"
                            )
                continue
            if moved:
                raise Unchecked(
                    "an earlier `cd` in this command moves to a directory the shell names"
                )
            repo = opts.get("repo")
            if uncertain_repo and repo is None:
                raise Unchecked(
                    "an earlier command may change the repository environment"
                )
            if repo is not None and not repo.literal:
                raise Unchecked("its repository is built by shell expansion")
            m = FIRST_LINE.search(
                body_of(opts, cwd, stdin, writes, uncertain_write) or ""
            )
            if not m or not re.fullmatch(r"cap-[0-9]+", m[1]):
                continue
            cid = m[1]
            pr = open_with(cid, repo.text if repo else None, cwd, deadline)
        except Unchecked as why:
            if words and words[0].text == "function" and not words[0].quoted:
                # Its later segments may be an unexecuted function body. Stop
                # scanning the definition rather than exposing gh-shaped data.
                raise
            notes.append(
                f"campaign-pr-guard: NOT CHECKED — {why}, so whether another open pull request "
                f"already carries this PR's Campaign line ({cid}) is unknown. Check "
                "`gh pr list --state open --search '\"Campaign: cap-<n>\" in:body'` first."
            )
            continue
        finally:
            # Once per command, whether judged, skipped or not checked.
            writes |= effects[0]
            uncertain_write = uncertain_write or effects[1]
            uncertain_repo = uncertain_repo or repo_effect
        if pr:
            return 2, (
                f"campaign-pr-guard: REFUSED — {pr} is already open "
                f"for Campaign: {cid}, and one campaign has one pull request. Push this work to "
                "that pull request's branch instead of opening another."
            )
    if scopes:
        raise Unchecked("a subshell has no closing parenthesis")
    return 0, " ".join(notes)


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
    cmd: str, depth: int = 0
) -> list[tuple[str | None, Word | None, bool]]:
    """Each merge in the command: its selector, repository, and changed context.

    A merge this hook cannot resolve raises Unchecked, so the caller refuses it.
    """
    if depth > 3:
        raise Unchecked("the shells nest too deep")
    found: list[tuple[str | None, Word | None, bool]] = []
    changed = False
    for segment in segments(tokens(cmd)):
        if isinstance(segment, str):
            continue
        words, env, _ = command_words(segment[0])
        while words and words[0].literal:
            name = words[0].text.rsplit("/", 1)[-1]
            if name in RUNNERS:
                words, inner, _ = command_words(runner_argv(words))
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
            found += [(sel, repo, moved or changed) for sel, repo, moved in nested]
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
        k = 0
        while k < len(argv):
            token, option = argv[k], argv[k].text
            if option.startswith("--"):
                key, eq, value = option[2:].partition("=")
                if key in MERGE_VALUED and not eq and k + 1 < len(argv):
                    k += 1
                    token, value = argv[k], argv[k].text
                if key == "repo":
                    repo = Word(value, token.literal)
            elif option.startswith("-") and len(option) > 1:
                for index, letter in enumerate(option[1:], 2):
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
            found.append((match[3], Word(f"{match[1]}/{match[2]}"), False))
            continue
        if [word.text for word in pos[:2]] != ["pr", "merge"]:
            continue
        if not all(word.literal for word in pos[:3]):
            raise Unchecked("the pull request is named by shell expansion")
        if repo is not None and not repo.literal:
            raise Unchecked("the repository is named by shell expansion")
        found.append((pos[2].text if len(pos) > 2 else None, repo, changed))
    return found


def merge_refusal(cmd: str, cwd: str) -> str:
    """A refusal for a merge into public, or the empty string."""
    deadline = time.monotonic() + LIMIT
    for selector, repo, changed in merge_targets(cmd):
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
    # gh must end a word (`highway` fails the hint); pr and create or new are whole words.
    # The left edge of gh stays open: the join glues `# prep\<newline>gh` to `prepgh`.
    # So `high ... pr ... new` can print the notice that base printed, never a refusal.
    if not all(
        re.search(word, hint) for word in (r"gh\b", r"\bpr\b", r"\b(create|new)\b")
    ):
        return 0
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) else None
    try:
        code, message = decide(cmd, cwd or os.getcwd())
    except (ValueError, Unchecked) as error:
        code, message = (
            0,
            (
                f"campaign-pr-guard: NOT CHECKED — the shell command could not be read ({error}), so a "
                "`gh pr create` in it was not judged."
            ),
        )
    if code == 2:
        sys.stderr.write(message + "\n")
        out = {"permissionDecision": "deny", "permissionDecisionReason": message}
    elif message:
        out = {"additionalContext": message}
    else:
        return 0
    sys.stdout.write(
        json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", **out}})
        + "\n"
    )
    return code


if __name__ == "__main__":
    sys.exit(main())
