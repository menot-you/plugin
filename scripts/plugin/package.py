"""Build or verify content-addressed, self-contained NOTT client views (D18)."""

import argparse
import ast
import hashlib
import importlib.util
import io
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
from collections.abc import Collection, Iterable, Mapping, Sequence
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import Any, NotRequired, TypedDict


def _renamed_table() -> ModuleType:
    """The renamed-variable table of the plugin scripts, in `scripts/env/`. The module loads by path,
    and a bare `import renamed` would take whichever table another loader put first on
    the import path (the hooks have one too), so it is loaded from its file."""
    path = Path(__file__).resolve().parent.parent / "env/renamed.py"
    spec = importlib.util.spec_from_file_location("nott_plugin_scripts_renamed", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_RENAMED = _renamed_table()
RENAMED = _RENAMED.RENAMED
RenamedVariableError = _RENAMED.RenamedVariableError
env = _RENAMED.env


class ClientAction(TypedDict):
    event: str
    matcher: NotRequired[str]
    proof: dict[str, str]


class ClientView(TypedDict):
    verbatim: set[str] | None
    runner: str | None
    actions: dict[str, ClientAction]
    not_projected: dict[str, dict[str, str]]
    excluded: NotRequired[dict[str, str]]


class BundleManifest(TypedDict):
    schema: int
    version: str
    source_digest: str
    digest: str
    components: dict[str, str]
    files: dict[str, dict[str, str | bool]]


class RuntimeBinding(TypedDict):
    repository: str
    purpose: str
    packager_sha256: str
    source: NotRequired[dict[str, str] | None]
    transforms: NotRequired[list[dict[str, str]]]
    source_commit: NotRequired[str]


IDENTITY = ".nott-bundle.json"
EXCLUDE = {"evals", ".DS_Store", "__pycache__", ".pytest_cache", ".ruff_cache"}
CLIENTS = ("claude", "codex", "agy")
NODE_CLIENTS = ("claude-node", "codex-node")
NODE_GUARDS = {
    "pynott-branch-lock.sh",
    "bash-guards.sh",
    "law-contract.sh",
    "secret-in-output.sh",
    # Its voice check; the node view runs it as NOTT_HOOK_CLIENT=node (no state line).
    "final-state.sh",
    # The app's Claude nodes carry the dispatch-model rule too.
    "dispatch-tier.py",
    # An app node is a NOTT session: its subagents get the subagent law.
    "subagent-law.py",
    "nmemory-main-only.py",
}
NATIVE = (".codex-plugin/plugin.json", ".claude-plugin/plugin.json", "plugin.json")
# Native AGY observation: a rule is truncated after 24,000 UTF-8 bytes.
MAX_RULE_BYTES = 24000
# Native Codex observation: codex-cli 0.154.0 caps a hook's timeout PER EVENT and
# warns when it clamps one — "clamping SessionEnd hook timeout to 3s in
# /plugin/clients/codex". A declaration above the cap buys that warning and a hook
# that runs with the capped value anyway, so the Codex view declares what the
# client will honour. Claude honours hooks.json verbatim and keeps its own value.
#
# HONEST LIMIT: 3 is an OBSERVED behaviour of codex-cli 0.154.0, read from its own
# warning string — not a documented contract. What falsifies it: a codex version
# whose warning names another number, or names another event. Re-measure from the
# warning and change the data here; nothing below reads the number directly.
CODEX_TIMEOUT_CEILINGS = {"SessionEnd": 3}
# THE CLIENT VIEWS, DECLARED. One structure per client that build() consumes and
# `plugin.py show` renders; the README block between the nott:client-matrix
# markers is generated from it (plugin/tests/client-matrix-contract.sh).
#
# `verbatim`: source events (hooks/hooks.json) the view carries unchanged; None
#   means every event, matchers included (Claude honours the declaration as is).
# `actions`: runner actions the view binds instead, each with the SOURCE event it
#   re-expresses, the matcher the view declares (Codex; AGY's come from the root
#   hooks.json) and `proof`: hook script -> the smoke cell that feeds the built
#   runner one deny/advisory payload and one allow payload. A script the action
#   runs without a cell is `unproven` in the matrix and never `ok` in the smoke.
#   WHICH scripts an action runs is not declared here: runner_actions() reads it
#   from the runner's own source, so a guard added to codex-hook-runner.py
#   SHELL_GUARDS appears in the matrix by itself.
# `excluded`: hook script -> reason, for a script this client must NOT run even
#   on an event it carries verbatim; build() drops it from the view and the
#   matrix renders it `not projected` with that reason.
# `not_projected`: the reason a source binding is absent, keyed by event, then
#   matcher, then hook script. A binding with no route and no reason renders as
#   `undeclared` — the matrix never drops a hook in silence (measured 2026-09-14:
#   Stop and PostToolUseFailure arrived with final-state, chained-after-finding
#   and red-first, and the Codex view dropped them with nothing saying so).
# The SessionStart notice drain takes an nSPAWN notice AT MOST ONCE. Only a
# Claude Code session is a notice caller (it owns CLAUDE_CODE_MESSAGING_SOCKET),
# so a drain in any other client would consume the notice the project's next
# Claude session is owed, into a conversation that never dispatched the run.
NOTICE_DRAIN_EXCLUSION = (
    "the nSPAWN notice drain is at-most-once and only a Claude Code session is a "
    "notice caller; draining here would take the notice the project's next "
    "Claude session is owed"
)
SHELL_MATCHER = "Bash|exec_command|shell_command"
CLIENT_VIEWS: dict[str, ClientView] = {
    "claude": {
        "verbatim": None,
        "runner": None,
        "actions": {},
        "not_projected": {"events": {}, "matchers": {}, "hooks": {}},
    },
    "codex": {
        # The filter ADMITS UserPromptSubmit; the view carries it only when the
        # source declares one. fanout-reminder.sh rides it verbatim: its completion
        # reminder stays silent here, because it speaks only on a Claude <task-notification>
        # or an nSPAWN supervisor notice and Codex delivers neither as a prompt; its
        # owner-list reminder reads only the prompt. Handlers fail open on every field they are not
        # given, so a Codex payload without transcript_path or compact_summary
        # is silence, never an error. SessionEnd lands at the 3 s clamp.
        "verbatim": {
            "SessionStart",
            "UserPromptSubmit",
            "SessionEnd",
            "PreCompact",
            "PostCompact",
        },
        "runner": "codex-hook-runner.py",
        "excluded": {
            "nspawn-notices.sh": NOTICE_DRAIN_EXCLUSION,
            "system1-suggest.py": "its catalog is the Claude agent types under "
            "~/.claude and the routes as Claude names them; a Codex session "
            "has neither that Agent tool nor those names",
            "nmemory-act.py": "its act is a Claude dispatch tool on PostToolUse, "
            "which Codex runs only through runner actions, so a turn start or a "
            "compaction here would have no act to reach",
            "nmemory-main-only.py": "it denies a Claude subagent by the agent_id "
            "of a Claude payload. On Codex only an nSPAWN child is covered: "
            "nMEMORY refuses it by NOTT_NSPAWN_RUN_ID, which nSPAWN forwards. "
            "A Codex multi_agent sub-agent is not covered",
        },
        "actions": {
            "session-state-pre": {
                "event": "PreToolUse",
                "matcher": ".*",
                "proof": {"session-state.sh": "session-state"},
            },
            "session-state-post": {
                "event": "PostToolUse",
                "matcher": ".*",
                "proof": {"session-state.sh": "session-state"},
            },
            # Freestanding apply_patch reports tool_name "apply_patch" with the
            # patch in tool_input.command (Codex hooks docs). The guards skip
            # that payload (patch text is not a shell line); red-first reads its
            # `*** Add|Update File:` headers. First deny wins, deny JSON + exit 2.
            "pre-shell": {
                "event": "PreToolUse",
                "matcher": SHELL_MATCHER + "|apply_patch",
                "proof": {
                    "bash-guards.sh": "bash-guards",
                    "red-first.sh": "red-first",
                    "two-misses.sh": "two-misses",
                },
            },
            # BOTH tool events carry the SAME shell names: codex offers the
            # freestanding apply_patch tool to first-party models only, so every
            # other model writes by piping a patch into `apply_patch` from the
            # shell tool, and `Edit|Write|apply_patch` alone saw 0/3 writes over
            # campaign-af-20260913/release2. A name cannot tell a write from a
            # read (`cat` is the same tool), so post-edit decides BY PAYLOAD
            # whether anything was written; the chain and write advisories join
            # in ONE additionalContext. Codex runs PostToolUse after a non-zero
            # exit too (measured 2026-09-14, #444). It runs no contract.
            # Codex 0.157 runs Stop at turn end and re-prompts on decision:block,
            # with stop_hook_active on the next Stop (measured 2026-09-25). The
            # voice check (final-state.sh as NOTT_HOOK_CLIENT=codex, no state line:
            # Codex has no statusline) and the capture gate ride it.
            "stop": {
                "event": "Stop",
                "proof": {
                    "session-state.sh": "session-state",
                    "final-state.sh": "voice",
                    "nmemory-capture-gate.py": "capture-gate",
                },
            },
            "post-edit": {
                "event": "PostToolUse",
                "matcher": "Edit|Write|apply_patch|" + SHELL_MATCHER,
                "proof": {
                    "red-first.sh": "red-first-tested",
                    "two-misses.sh": "two-misses",
                    "secret-in-output.sh": "secret-output",
                },
            },
        },
        "not_projected": {
            "events": {
                "Notification": "The Codex view has no native permission notification binding. Waiting tools use PreToolUse.",
                "SubagentStart": "Codex has no subagent events; the subagent law "
                "reaches Claude subagents only",
                "SubagentStop": "Codex has no subagent events; session-state.sh's "
                "dead[] record hangs on SubagentStop",
                "TeammateIdle": "Codex has no teams and no TeammateIdle event",
                "StopFailure": "Codex has no StopFailure event; a dead session "
                "is not announced there",
                "PostToolUseFailure": "Codex has no such event. Both Claude "
                "handlers (secret-in-output's chain advisory, red-first's "
                "`tested` record) ride post-edit on PostToolUse, which Codex "
                "runs after a non-zero Bash exit too (measured 2026-09-14, #444)",
            },
            "matchers": {
                "ExitPlanMode": "Codex has no ExitPlanMode tool, so neither half "
                "of the plan gate has an event to hang on",
            },
            "hooks": {
                "law-contract.sh": "Claude runs it on PostToolUse "
                "Write|Edit|MultiEdit; the Codex post-edit advisory names the "
                "contract and does not run it",
                "nmemory-anchor-queue.sh": "enqueues the EDITED path from a "
                "Claude Write|Edit payload (tool_input.file_path); Codex writes "
                "by piping a patch into apply_patch from the shell tool, so "
                "post-edit sees patch text, not a path, and has no "
                "codex-hook-runner.py action for it",
                "bash-guard.py": "reads a Claude payload shape and has no "
                "codex-hook-runner.py action; Codex serves the event, the "
                "handler is not projected",
                "nspawn-pairing.sh": "reads a Claude payload shape and has no "
                "codex-hook-runner.py action; Codex serves the event, the "
                "handler is not projected",
                "dispatch-tier.py": "binds the Claude Agent and Workflow tools, "
                "which Codex does not have",
                "artifact-copy.py": "binds the Claude Artifact tool, "
                "which Codex does not have",
            },
        },
    },
    "agy": {
        # rules/AGENTS.md (a link to the law) and the root hooks.json, every
        # entry routed through agy-hook-runner.py, which answers
        # {"decision":"deny","reason"} on exit 0. Nothing from hooks/hooks.json
        # is projected as a binding; matchers are the root hooks.json's.
        "verbatim": set(),
        "runner": "agy-hook-runner.py",
        "excluded": {"nspawn-notices.sh": NOTICE_DRAIN_EXCLUSION},
        "actions": {
            "pre-tool-run-command": {
                "event": "PreToolUse",
                "proof": {
                    "bash-guards.sh": "bash-guards",
                },
            },
            "post-tool-write": {
                "event": "PostToolUse",
                "proof": {"law-contract.sh": "law-contract"},
            },
            "post-tool-run-command": {"event": "PostToolUse", "proof": {}},
            # AGY's native Stop (hooks.md "Stop Contract"): decision:continue
            # re-enters the loop; measured 2026-09-25. Voice only, as on Codex.
            "stop": {
                "event": "Stop",
                "proof": {"final-state.sh": "voice"},
            },
            "pre-invocation": {
                "event": "SessionStart",
                "proof": {"nspawn-child-directives.sh": "child-directives"},
            },
        },
        "not_projected": {
            "events": {
                event: "AGY's hooks.md offers PreInvocation, PreToolUse, "
                f"PostToolUse, PostInvocation and Stop; there is no {event}"
                for event in (
                    "SessionEnd",
                    "PreCompact",
                    "PostCompact",
                    "SubagentStart",
                    "SubagentStop",
                    "TeammateIdle",
                    "StopFailure",
                )
            }
            | {
                "Notification": "AGY has no native permission notification in this view",
                "PostToolUseFailure": "AGY has no such event; its PostToolUse "
                "payload carries {stepIdx, error} and post-tool-run-command "
                "names the error in its advisory",
            },
            "matchers": {
                "ExitPlanMode": "AGY has no ExitPlanMode tool, so neither half "
                "of the plan gate has an event to hang on",
            },
            "hooks": {
                "red-first.sh": "both halves: its `tested` record needs the "
                "command text after the run, and AGY's PostToolUse payload is "
                "{stepIdx, error, ...common} (agy-customizations docs/hooks.md), "
                "so the deny half would call a tested session untested",
                "nmemory-anchor-queue.sh": "enqueues the EDITED path from a "
                "Claude Write|Edit payload (tool_input.file_path); AGY's "
                "PostToolUse payload is {stepIdx, error, ...common} with no "
                "path, so there is nothing to enqueue",
                "bash-guard.py": "reads a Claude payload shape (tool_response) "
                "that AGY's PostToolUse does not carry",
                "nspawn-pairing.sh": "reads a Claude MCP tool payload; AGY has "
                "no agy-hook-runner.py action for it",
                "dispatch-tier.py": "binds the Claude Agent and Workflow tools, "
                "which AGY does not have",
                "artifact-copy.py": "binds the Claude Artifact tool, "
                "which AGY does not have",
                "two-misses.sh": "its ledger fills from the command text after "
                "the run, which AGY's PostToolUse payload lacks, so its "
                "PreToolUse deny would never fire",
                "secret-in-output.sh": "no output text in AGY's PostToolUse payload",
                "nmemory-session.sh": "reads a Claude SessionStart payload "
                "(source, transcript_path); pre-invocation injects its own "
                "nMEMORY directive on the first invocation instead",
                "nmemory-recall.py": "AGY has no UserPromptSubmit, the only "
                "event the recall rides",
                "nmemory-main-only.py": "it denies a Claude subagent by the "
                "agent_id of a Claude payload; AGY has no subagent events. nMEMORY "
                "refuses an AGY nSPAWN child when its MCP server inherits "
                "NOTT_NSPAWN_RUN_ID (not measured)",
                "nmemory-act.py": "AGY's PostToolUse payload is {stepIdx, error, "
                "...common}, with no tool name or input, so no act can be matched",
                "law-session.sh": "AGY reads the law from rules/AGENTS.md "
                "(a link to NOTT.md) at startup; injecting it "
                "again at pre-invocation would double it",
                "system1-suggest.py": "AGY has no UserPromptSubmit, the only "
                "event the suggestion rides",
                "fanout-reminder.sh": "AGY has no UserPromptSubmit, and a "
                "worker's completion never reaches it as a Claude "
                "<task-notification> or nSPAWN supervisor notice",
                "session-state.sh": "surface of the Claude statusline; AGY has "
                "no statusline and no subagent events, so a phase file would "
                "have no reader",
                "final-state.sh": "AGY has no UserPromptSubmit to carry the voice "
                "advice, and its stop action runs this script for the voice check "
                "alone (NOTT_HOOK_CLIENT=agy): AGY has no statusline for a state line",
                "nmemory-capture-gate.py": "reads the current turn's Claude "
                "transcript JSONL (tool_use and tool_result blocks for "
                "nmemory_capsule_ingest). This view does not supply that "
                "transcript protocol",
            },
        },
    },
}
# Event-keyed absences of the Codex view; the view test refuses any absence
# that is not listed here.
CODEX_NOT_PROJECTED = CLIENT_VIEWS["codex"]["not_projected"]["events"]
HOOK_SCRIPT = re.compile(r"[\w-]+\.(?:sh|py)")


class Refusal(ValueError):
    """The artifact or registration is not admissible."""


def encoded(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: object) -> str:
    return hashlib.sha256(encoded(value)).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def inventory(
    root: Path, exclude: Collection[str] = ()
) -> dict[str, dict[str, str | bool]]:
    files: dict[str, dict[str, str | bool]] = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if relative == IDENTITY or any(
            part in exclude for part in Path(relative).parts
        ):
            continue
        if path.is_symlink():
            try:
                path.resolve(strict=True).relative_to(root.resolve())
            except (ValueError, OSError, RuntimeError) as error:
                raise Refusal(f"escaping or broken link: {relative}") from error
            files[relative] = {"link": os.readlink(path)}
        elif path.is_file():
            files[relative] = {
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "executable": bool(path.stat().st_mode & 0o111),
            }
        elif not path.is_dir():
            raise Refusal(f"not a regular package resource: {relative}")
    return files


def components(files: Mapping[str, Mapping[str, str | bool]]) -> dict[str, str]:
    return {
        "law": digest(
            {
                key: value
                for key, value in files.items()
                if key == "NOTT.md" or key.startswith("rules/")
            }
        ),
        "skills": digest(
            {key: value for key, value in files.items() if key.startswith("skills/")}
        ),
        "mcp": digest({key: files[key] for key in (".mcp.json", "mcp_config.json")}),
        "hooks": digest(
            {
                key: value
                for key, value in files.items()
                if key.startswith("hooks/")
                or key == "hooks.json"
                or key.startswith("clients/")
                and "/hooks" in key
            }
        ),
    }


def view_directories(root: Path) -> list[Path]:
    return [
        root,
        *(root / "clients" / client for client in CLIENTS),
        *(
            root / "clients" / client
            for client in NODE_CLIENTS
            if (root / "clients" / client).is_dir()
        ),
    ]


def version_inventory(
    root: Path, files: Mapping[str, Mapping[str, str | bool]], base: str
) -> dict[str, dict[str, str | bool]]:
    """Break the version/hash cycle using one canonical placeholder value."""
    normalized = {name: dict(entry) for name, entry in files.items()}
    for directory in view_directories(root):
        for native in NATIVE:
            path = directory / native
            declaration = json.loads(path.read_text())
            declaration["version"] = base + "+sha.pending"
            content = (
                json.dumps(declaration, indent=2, sort_keys=True) + "\n"
            ).encode()
            normalized[path.relative_to(root).as_posix()]["sha256"] = hashlib.sha256(
                content
            ).hexdigest()
    return normalized


def validate_law(root: Path) -> None:
    data = (root / "NOTT.md").read_bytes()
    if not data.strip() or len(data) > MAX_RULE_BYTES:
        raise Refusal(f"native law must contain 1..{MAX_RULE_BYTES} bytes")


def verify(root: Path) -> BundleManifest:
    root = root.resolve(strict=True)
    manifest: BundleManifest = json.loads((root / IDENTITY).read_text())
    files = inventory(root)
    if (
        type(manifest.get("schema")) is not int
        or manifest.get("schema") != 1
        or manifest.get("files") != files
        or manifest.get("digest") != digest(files)
        or manifest.get("components") != components(files)
    ):
        raise Refusal("bundle content does not match its recorded identity")
    for client in CLIENTS:
        if not (root / "clients" / client / "skills").is_dir():
            raise Refusal(f"client view missing: {client}")
        for directory in (root, root / "clients" / client):
            for native in NATIVE:
                content = (directory / native).read_text()
                declaration = json.loads(content)
                if (
                    declaration.get("version") != manifest.get("version")
                    or declaration.get("name") != "nott"
                ):
                    raise Refusal("native identity differs from bundle identity")
                if content != json.dumps(declaration, indent=2, sort_keys=True) + "\n":
                    raise Refusal("native identity is not in canonical generated form")
    for client in NODE_CLIENTS:
        directory = root / "clients" / client
        if not directory.exists():
            continue
        for native in NATIVE:
            declaration = json.loads((directory / native).read_text())
            if (
                declaration.get("name") != "nott"
                or declaration.get("version") != manifest["version"]
            ):
                raise Refusal("node identity differs from bundle identity")
    if not manifest["version"].endswith("+sha." + manifest["source_digest"]):
        raise Refusal("version is not bound to source identity")
    if manifest["source_digest"] != digest(
        version_inventory(root, files, manifest["version"].split("+")[0])
    ):
        raise Refusal("different content cannot retain the recorded version")
    runtime: RuntimeBinding = json.loads((root / ".nott-runtime.json").read_text())
    if not isinstance(runtime, dict) or runtime.get("purpose") not in (
        "current",
        "historical-evaluation",
    ):
        raise Refusal("unknown bundle purpose")
    fields = {"repository", "purpose", "packager_sha256"}
    if runtime["purpose"] == "historical-evaluation":
        fields |= {"source", "transforms"}
    if "source_commit" in runtime:
        if runtime["repository"] != "." or not re.fullmatch(
            r"[0-9a-f]{40}", runtime["source_commit"]
        ):
            raise Refusal("public source identity requires an exact commit")
        fields.add("source_commit")
    if set(runtime) != fields:
        raise Refusal("runtime metadata does not match its declared purpose")
    for client in CLIENTS:
        if (
            json.loads((root / "clients" / client / ".nott-runtime.json").read_text())
            != runtime
        ):
            raise Refusal("client purpose or runtime binding differs")
    if runtime["purpose"] == "historical-evaluation":
        verify_historical(root, runtime)
    return manifest


def hook_resources(command: object) -> list[str]:
    """The confined native resources a hook command names, in argv order."""
    if not isinstance(command, str):
        raise Refusal("native hook command must be a string")
    try:
        tokens = shlex.split(command)
    except ValueError as error:
        raise Refusal("malformed native hook command") from error
    targets = [
        token.removeprefix("${CLAUDE_PLUGIN_ROOT}/")
        for token in tokens
        if token.startswith(("${CLAUDE_PLUGIN_ROOT}/hooks/", "hooks/"))
    ]
    if not targets or any(".." in Path(path).parts for path in targets):
        raise Refusal("hook command has no confined native resource")
    return targets


def hook_handlers(declarations: Iterable[object]) -> set[str]:
    """Every confined resource that a command of these hook declarations names."""
    handlers = set()
    pending = list(declarations)
    while pending:
        node = pending.pop()
        if isinstance(node, dict):
            if node.get("type") == "command":
                handlers.update(hook_resources(node.get("command")))
            pending.extend(node.values())
        elif isinstance(node, list):
            pending.extend(node)
    return handlers


def admit_current(root: Path) -> BundleManifest:
    root = root.resolve(strict=True)
    manifest = verify(root)
    runtime = json.loads((root / ".nott-runtime.json").read_text())
    if runtime["purpose"] != "current":
        raise Refusal(
            "bundle purpose is not current; historical evaluation is not current admission"
        )
    # Every client receives the same complete hook inventory. Resolve the union
    # from its actual native declarations, including generated Codex commands.
    handlers = hook_handlers(
        json.loads(declaration.read_text())
        for declaration in (
            root / "hooks.json",
            root / "hooks/hooks.json",
            root / "clients/claude/hooks/hooks.json",
            root / "clients/codex/hooks/hooks.json",
            root / "clients/agy/hooks.json",
        )
    )
    for directory in view_directories(root):
        validate_law(directory)
        for handler in sorted(handlers):
            if not (directory / handler).is_file():
                raise Refusal(f"current native hook handler is absent: {handler}")
            # A host or a runner starts the hook by its path: without the bit,
            # every run fails with "Permission denied" (measured 2026-10-17).
            if not (directory / handler).stat().st_mode & 0o111:
                raise Refusal(
                    f"current native hook handler is not executable: {handler}"
                )
    return manifest


# The hook declarations of the source tree. A local edit of one is merged, not kept.
HOOK_DECLARATIONS = ("plugin/hooks/hooks.json", "plugin/hooks.json")
# The commit of the last delivery into a checkout: the base of the next delivery. A
# ref under refs/worktree/ belongs to one worktree, so a delivery into a linked
# worktree of the live repository does not move the base of the live checkout.
DELIVERED_REF = "refs/worktree/nott/plugin-delivered"


class GitFailed(OSError):
    """Git ran and exited non-zero: operational, unless the input caused it."""


def checkout_git(checkout: Path, *args: str) -> bytes:
    """Run git in a delivery checkout. A failure is operational and keeps git's words."""
    try:
        result = subprocess.run(
            ["git", "--no-replace-objects", "-C", str(checkout), *args],
            capture_output=True,
            check=False,
            timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise OSError(f"git {args[0]} did not run in {checkout}: {error}") from error
    if result.returncode:
        raise GitFailed(
            f"git {' '.join(args)} failed in {checkout}: "
            + result.stderr.decode(errors="replace").strip()
        )
    return result.stdout


def tree_files(checkout: Path, commit: str) -> dict[str, dict[str, str]]:
    """The mode and blob of each file under plugin/ in `commit`."""
    files = {}
    for record in checkout_git(
        checkout, "ls-tree", "-r", "-z", commit, "--", "plugin"
    ).split(b"\0"):
        if record:
            meta, name = record.split(b"\t", 1)
            mode, _, blob = meta.decode().split()
            files[os.fsdecode(name)] = {"mode": mode, "blob": blob}
    return files


def unique_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    """A JSON object hook: a key that comes twice is refused, not overwritten."""
    keys = [key for key, _ in pairs]
    twice = sorted({key for key in keys if keys.count(key) > 1})
    if twice:
        raise Refusal("these keys come twice: " + ", ".join(twice))
    return dict(pairs)


def present(path: Path, entry: Mapping[str, str]) -> dict[str, str] | None:
    """The blob identity of the file or link at `path`, or None when nothing is there."""
    return blob_identity(path, entry) if path.is_symlink() or path.exists() else None


def merge_edit(name: str, local: bytes, base: bytes, delivered: bytes) -> bytes:
    """The `git merge-file` of a local edit and the commit's version of `name`."""
    with tempfile.TemporaryDirectory(prefix="nott-deliver-") as scratch:
        sides = [Path(scratch) / side for side in ("local", "base", "commit")]
        for side, data in zip(sides, (local, base, delivered), strict=True):
            side.write_bytes(data)
        try:
            merged = subprocess.run(
                ["git", "merge-file", "--stdout", *map(str, sides)],
                capture_output=True,
                check=False,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise OSError(f"git merge-file did not run for {name}: {error}") from error
    # An exit from 1 to 127 counts the conflicts. 255 is an error.
    if not 0 <= merged.returncode <= 127:
        raise OSError(
            f"git merge-file failed for {name}: "
            + merged.stderr.decode(errors="replace").strip()
        )
    if merged.returncode:
        raise Refusal(
            f"the local edit of {name} and the commit change the same lines "
            f"(conflicts: {merged.returncode}), so nothing was written"
        )
    try:
        json.loads(merged.stdout, object_pairs_hook=unique_keys)
    except (json.JSONDecodeError, Refusal) as error:
        raise Refusal(
            f"the merge of {name} is not valid JSON ({error}), so nothing was written"
        ) from error
    return merged.stdout


def deliver(
    commit: str, checkout: Path, bases: Sequence[str] = ()
) -> dict[str, object]:
    """Write the plugin/ of `commit` over the plugin/ of `checkout`: bytes and modes.

    The live plugin is the tree of a checkout, not a bundle, and other agents work
    in it. A byte copy (`git show <commit>:<path> > <path>`) does not keep the mode:
    on 2026-10-17 it left two hooks without their execute bit. This writes only the
    files that differ from the commit in bytes or execute bit:

    - The base of each file is its version at DELIVERED_REF, the commit of the last
      delivery into the checkout. Without the ref, the bases are the commits that
      the operator names in `bases`. While the ref is there, `bases` is refused.
    - A file with the bytes of a base version, or absent in a base and in the
      checkout, has no local edit: it gets the version of the commit. So does a
      file with the bytes of the commit and another mode.
    - Other bytes are a local edit. A hook declaration with a local edit gets a
      three-way merge of the edit, the version of the first base and the commit.
      Another file with a local edit is kept and listed, and the delivery refuses
      when the commit changes it. Without a base, a local edit refuses the
      delivery. A file that a base has and the commit does not is kept and listed.
    - Before it writes, it refuses (exit 2) a file or link where the commit has a
      directory, a directory where the commit has a file, a merge conflict, and a
      hook that the result names but cannot run.
    - It extracts `git archive` into `.nott/deliver/` of the checkout, on the file
      system of plugin/, and compares each extracted file with the commit. It
      copies each file that it replaces to a backup there. Then `os.replace` moves
      each new file into place, so a reader gets the old file or the new file,
      never a part. The hook declarations move last.
    - It reads back each written file, then it moves DELIVERED_REF to the commit.
      On a failure it puts every file back and exits 1. A killed run leaves each
      file whole, and a second run completes it.
    """
    checkout = checkout.resolve(strict=True)
    try:
        top = checkout_git(checkout, "rev-parse", "--show-toplevel").decode().strip()
    except GitFailed as error:
        raise Refusal(f"{checkout} is not a Git checkout: {error}") from error
    if Path(top).resolve() != checkout:
        raise Refusal(f"{checkout} is not the top level of its Git checkout")

    def resolve(name: str) -> str:
        return (
            checkout_git(
                checkout,
                "rev-parse",
                "--verify",
                "--end-of-options",
                name + "^{commit}",
            )
            .decode()
            .strip()
        )

    try:
        commit = resolve(commit)
    except GitFailed as error:
        raise Refusal(f"{commit} is not a commit in {checkout}: {error}") from error
    declared = tree_files(checkout, commit)
    if not declared:
        raise Refusal(f"{commit} has no plugin/")
    previous = (
        checkout_git(checkout, "for-each-ref", "--format=%(objectname)", DELIVERED_REF)
        .decode()
        .strip()
    )
    if previous and bases:
        raise Refusal(
            f"{DELIVERED_REF} names {previous}, the last delivery into {checkout}. "
            "The base of each file is its version there, so --base is refused"
        )
    named: list[str] = []
    for base in [previous] if previous else bases:
        try:
            sha = resolve(base)
        except GitFailed as error:
            source = DELIVERED_REF if previous else "--base"
            raise Refusal(
                f"{source} names {base}, which is not a commit in {checkout}: {error}"
            ) from error
        if sha not in named:
            named.append(sha)
    versions = {base: tree_files(checkout, base) for base in named}

    def version(name: str, base: str) -> str | None:
        """The blob of `name` in `base`, or None when the base does not have it."""
        entry = versions[base].get(name)
        return entry["blob"] if entry else None

    def declaration(name: str, data: bytes) -> object:
        try:
            return json.loads(data)
        except json.JSONDecodeError as error:
            raise Refusal(f"{name} is not JSON: {error}") from error

    def committed(name: str) -> bytes:
        return checkout_git(checkout, "cat-file", "blob", declared[name]["blob"])

    unrunnable = sorted(
        handler
        for handler in hook_handlers(
            declaration(f"{commit}:{name}", committed(name))
            for name in HOOK_DECLARATIONS
            if name in declared
        )
        if declared.get("plugin/" + handler, {}).get("mode") != "100755"
    )
    if unrunnable:
        raise Refusal(
            f"{commit} does not declare these hook handlers as executable files: "
            + ", ".join(unrunnable)
        )
    # To make a directory, a write deletes a file or link in its place, and a
    # link takes the write outside plugin/.
    blocked = set()
    for name in declared:
        if (checkout / name).is_dir() and not (checkout / name).is_symlink():
            blocked.add(name)
        for parent in PurePosixPath(name).parents[:-1]:
            folder = checkout / parent
            if folder.is_symlink() or (folder.exists() and not folder.is_dir()):
                blocked.add(parent.as_posix())
    if blocked:
        raise Refusal(
            "these paths are a file or link where the commit has a directory, or a "
            "directory where it has a file, so nothing was written: "
            + ", ".join(sorted(blocked))
        )
    seen: dict[str, dict[str, str] | None] = {}
    write: list[str] = []
    merged: dict[str, bytes] = {}
    kept: list[str] = []
    # The version that each written or merged file had: a base, or the commit.
    matched: dict[str, str] = {}
    unknown: list[str] = []
    changed: list[str] = []
    for name, entry in sorted(declared.items()):
        have = seen[name] = present(checkout / name, entry)
        if have == entry:
            continue
        blob = have["blob"] if have else None
        found = (
            commit
            if blob == entry["blob"]
            else next((base for base in named if version(name, base) == blob), None)
        )
        if found:
            write.append(name)
            matched[name] = found
        elif not named:
            unknown.append(name)
        elif name in HOOK_DECLARATIONS and have and have["mode"] != "120000":
            local = (checkout / name).read_bytes()
            start = version(name, named[0])
            merged[name] = merge_edit(
                name,
                local,
                checkout_git(checkout, "cat-file", "blob", start) if start else b"",
                committed(name),
            )
            matched[name] = named[0]
            if merged[name] != local:
                write.append(name)
        else:
            kept.append(name)
            if version(name, named[0]) != entry["blob"]:
                changed.append(name)
    if unknown:
        raise Refusal(
            f"{checkout} has no {DELIVERED_REF}, and these files differ from "
            f"{commit}: {', '.join(unknown)}. Nothing was written: name the commits "
            "that the files of the checkout came from with --base"
        )
    if changed:
        raise Refusal(
            "these files have a local edit, and the commit changes them: "
            + ", ".join(changed)
            + ". Nothing was written: merge each file by hand, then deliver again"
        )
    removed = sorted(
        name
        for name in {name for files in versions.values() for name in files}
        - declared.keys()
        if (checkout / name).is_symlink() or (checkout / name).is_file()
    )
    runs = checkout / ".nott/deliver"
    runs.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix=commit[:12] + "-", dir=runs))
    stage, backup = run / "stage", run / "backup"
    try:
        if write:
            # Pinned to the committed bytes, as in install.sh: core.autocrlf=true
            # writes CRLF.
            archive = checkout_git(
                checkout,
                *("-c", "core.autocrlf=false", "-c", "core.eol=lf"),
                *("archive", commit, "plugin"),
            )
            try:
                with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
                    bundle.extractall(stage, filter="tar")
            except tarfile.TarError as error:
                raise OSError(
                    f"the archive of {commit} did not extract: {error}"
                ) from error
            for name, data in merged.items():
                (stage / name).write_bytes(data)
            differ = sorted(
                name
                for name in write
                if name not in merged
                and present(stage / name, declared[name]) != declared[name]
            )
            if differ:
                raise OSError(
                    f"git archive did not give the bytes and modes of {commit} for "
                    "these files (an export or eol attribute changes them), so "
                    "nothing was written: " + ", ".join(differ)
                )

        def final(name: str) -> Path:
            return stage / name if name in write else checkout / name

        broken = []
        for handler in sorted(
            hook_handlers(
                declaration(name, final(name).read_bytes())
                for name in HOOK_DECLARATIONS
                if name in declared
            )
        ):
            path = final("plugin/" + handler)
            if not (path.is_file() and os.access(path, os.X_OK)):
                broken.append(handler)
        if broken:
            raise Refusal(
                "after the delivery these hook handlers would not run, so nothing "
                "was written: " + ", ".join(broken)
            )
        # What each written file must read back as: the commit's identity, or the
        # merge for a hook declaration.
        intended = {
            name: present(stage / name, entry) if name in merged else entry
            for name, entry in declared.items()
            if name in write
        }
        replaced: list[str] = []
        made: list[Path] = []
        try:
            # The hook declarations move last, so no reader gets one that names a
            # hook that is not in place yet.
            for name in sorted(
                write, key=lambda path: (path in HOOK_DECLARATIONS, path)
            ):
                target = checkout / name
                for parent in reversed(PurePosixPath(name).parents[:-1]):
                    if not (checkout / parent).exists():
                        (checkout / parent).mkdir()
                        made.append(checkout / parent)
                if seen[name] is not None:
                    saved = backup / name
                    saved.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(target, saved, follow_symlinks=False)
                    if present(saved, declared[name]) != seen[name]:
                        raise OSError(f"{name} changed while the delivery ran")
                elif target.is_symlink() or target.exists():
                    raise OSError(f"{name} appeared while the delivery ran")
                # Listed before the move, so an interruption after the move
                # still puts the file back.
                replaced.append(name)
                os.replace(stage / name, target)
            landed = sorted(
                name
                for name in write
                if present(checkout / name, declared[name]) != intended[name]
            )
            if landed:
                raise OSError(
                    "after the write these files differ from the delivery: "
                    + ", ".join(landed)
                )
            # The record of this delivery: the base of the next one. The old value
            # makes a concurrent delivery fail here.
            checkout_git(checkout, "update-ref", DELIVERED_REF, commit, previous)
        except BaseException as error:
            try:
                for name in reversed(replaced):
                    if seen[name] is None:
                        (checkout / name).unlink(missing_ok=True)
                    else:
                        os.replace(backup / name, checkout / name)
                for folder in reversed(made):
                    folder.rmdir()
            except OSError as failure:
                raise OSError(
                    f"the delivery of {commit} failed ({error}), and putting the "
                    f"files back failed too ({failure}): the replaced files are in "
                    f"{backup}"
                ) from error
            shutil.rmtree(backup, ignore_errors=True)
            if isinstance(error, OSError):
                raise OSError(
                    f"the delivery of {commit} failed, and every file was restored: "
                    f"{error}"
                ) from error
            raise
    finally:
        # The stage always goes. The run directory stays only to hold a backup.
        shutil.rmtree(stage if backup.exists() else run, ignore_errors=True)
    return {
        "commit": commit,
        "files": len(declared),
        "bases": named,
        "written": sorted(write),
        "matched": dict(sorted(matched.items())),
        "merged": sorted(merged),
        "kept": kept,
        "removed": removed,
        "backup": str(backup) if backup.exists() else None,
    }


def validate_mcp(config: object) -> None:
    if (
        not isinstance(config, dict)
        or set(config) != {"mcpServers"}
        or not isinstance(config["mcpServers"], dict)
        or not config["mcpServers"]
    ):
        raise Refusal("MCP config must contain a nonempty mcpServers object")
    for name, server in config["mcpServers"].items():
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", name):
            raise Refusal(f"invalid MCP name: {name}")
        if not isinstance(server, dict):
            raise Refusal(f"MCP {name}: registration must be an object")
        if server.get("type", "stdio") not in ("stdio", "http"):
            raise Refusal(f"MCP {name}: unsupported transport: {server.get('type')}")
        if server.get("type") == "http":
            validate_http_mcp(name, server)
            continue
        command = server.get("command")
        if not isinstance(command, str) or not command or not shutil.which(command):
            raise Refusal(f"MCP {name}: executable is absent: {command}")
        args = server.get("args", [])
        if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
            raise Refusal(f"MCP {name}: args must be strings")
        if "${CLAUDE_PLUGIN_ROOT}" in json.dumps(server):
            raise Refusal(f"MCP {name}: unresolved plugin-root binding")


# A remote endpoint is reached over TLS (or loopback), and its credential only ever
# arrives by `${VAR}` expansion: a header value is an optional `Bearer` plus
# references, so a literal token in the committed file is refused.
# No userinfo, query or fragment: a credential never rides in the URL, and the
# host is the whole authority, so `127.0.0.1:x@evil` is not loopback.
HTTP_URL = re.compile(
    r"(?:https://[A-Za-z0-9.-]+|http://127\.0\.0\.1)(?::[0-9]+)?(?:/[A-Za-z0-9._~/-]*)?"
)
HTTP_KEYS = frozenset({"type", "url", "headers"})
URL_VAR = re.compile(r"\$\{[A-Z_][A-Z0-9_]*(?::-(?P<default>[^}]*))?\}")
ENV_REF = re.compile(r"\$\{[A-Z_][A-Z0-9_]*\}")


def endpoint_allowed(url: str) -> bool:
    if match := URL_VAR.fullmatch(url):
        return match["default"] is None or bool(HTTP_URL.fullmatch(match["default"]))
    return bool(HTTP_URL.fullmatch(url))


def validate_http_mcp(name: str, server: dict[str, object]) -> None:
    if "command" in server or "args" in server:
        raise Refusal(f"MCP {name}: an http entry takes no command or args")
    if unknown := sorted(set(server) - HTTP_KEYS):
        raise Refusal(f"MCP {name}: unsupported http key: {', '.join(unknown)}")
    url = server.get("url")
    if not isinstance(url, str) or not endpoint_allowed(url):
        raise Refusal(
            f"MCP {name}: url must be https, loopback or a ${{VAR}} expression"
        )
    headers = server.get("headers", {})
    if not isinstance(headers, dict):
        raise Refusal(f"MCP {name}: headers must be an object")
    for key, value in headers.items():
        if (
            not isinstance(value, str)
            or not ENV_REF.search(value)
            or not re.fullmatch(r"(?:Bearer )?", ENV_REF.sub("", value))
        ):
            raise Refusal(f"MCP {name}: header {key} must carry its value by ${{VAR}}")
    if "${CLAUDE_PLUGIN_ROOT}" in json.dumps(server):
        raise Refusal(f"MCP {name}: unresolved plugin-root binding")


#: How the committed `.mcp.json` names a workspace member of the plugin's repository.
RUNTIME_PREFIX = "${CLAUDE_PLUGIN_ROOT}/../"
#: The member a runtime root must hold when the MCP config names none: the harness
#: CLI, the mark of a runtime root this packager can bind.
ROOT_MEMBER = "apps/cli"


def runtime_members(config: object) -> list[str]:
    """The workspace members the MCP registrations run from, as the source names them.

    The source is the authority, not a constant here: a historical build replays
    whatever member its own commit named (the body, or the pre-split harness member
    before it). Each one must be a relative path that stays inside the runtime root.
    A config that names none answers the harness CLI, the mark of a runtime root this
    packager can bind.
    """
    if not isinstance(config, dict) or not isinstance(config.get("mcpServers"), dict):
        raise Refusal("MCP config must contain a nonempty mcpServers object")
    members: set[str] = set()
    for server in config["mcpServers"].values():
        args = server.get("args", []) if isinstance(server, dict) else []
        for arg in args if isinstance(args, list) else []:
            if isinstance(arg, str) and arg.startswith(RUNTIME_PREFIX):
                member = arg.removeprefix(RUNTIME_PREFIX)
                parts = PurePosixPath(member).parts
                if not parts or member.startswith("/") or ".." in parts:
                    raise Refusal(f"MCP runtime member escapes the runtime root: {arg}")
                members.add(member)
    return sorted(members) or [ROOT_MEMBER]


# Each hook derives its repository root from its own location; a bundle installed
# elsewhere must instead bind that root to the runtime root, so the whole derivation
# chain is pinned VERBATIM (every accepted historical shape) and replaced as one unit.
# Any other shape is drift that a human inspects before packaging, never a regex hit.
BINDINGS = {
    "pynott-branch-lock.sh": (
        (
            'TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)',
            (
                'plugin_root=${NOTT_NSPAWN_PLUGIN_ROOT-$(dirname "${BASH_SOURCE[0]}")/..}\n'
                '[ -d "$plugin_root" ] || deny "REFUSED — the selected plugin source is unavailable."\n'
                'TREE=$(cd -- "$plugin_root/.." && pwd -P)'
            ),
        ),
        "TREE=",
    ),
    "law-contract.sh": (
        ('loaded_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)',),
        "loaded_root=",
    ),
}


def bound_hook(name: str, data: bytes, runtime_root: Path) -> bytes:
    forms, prefix = BINDINGS[name]
    text = data.decode()
    present = [form for form in forms if text.count(form) == 1]
    if len(present) != 1 or any(
        text.count(form) for form in forms if form != present[0]
    ):
        raise Refusal(f"runtime binding changed in {name}; inspect before packaging")
    return text.replace(present[0], prefix + shlex.quote(str(runtime_root))).encode()


def git(repository: Path, *args: str) -> bytes:
    try:
        result = subprocess.run(
            ["git", "--no-replace-objects", "-C", str(repository), *args],
            capture_output=True,
            check=False,
            timeout=30,
        )
    except subprocess.TimeoutExpired as error:
        raise Refusal("historical Git provenance read timed out") from error
    if result.returncode:
        raise Refusal("historical Git commit/tree is unavailable or invalid")
    return result.stdout


def commit_time(repository: Path, commit: str, cure: str | None = None) -> int:
    """The committer time of `commit` in the checkout at `repository`."""
    cure = cure or (
        f"the bundle version is the packaged commit's committer time and {repository} "
        "is not a Git checkout with it; package from the top level of a git "
        "checkout of the commit"
    )
    try:
        top = git(repository, "rev-parse", "--show-toplevel").decode().strip()
        # An enclosing repository is not the export's history.
        if Path(top).resolve() != repository.resolve():
            raise Refusal(cure)
        return int(git(repository, "show", "-s", "--format=%ct", commit))
    except Refusal as error:
        raise Refusal(cure) from error


def git_source(
    repository: Path, commit: str, relative: str
) -> tuple[dict[str, str], dict[str, dict[str, str]]]:
    if (
        not re.fullmatch(r"[a-f0-9]{40}|[a-f0-9]{64}", commit)
        or not relative
        or Path(relative).is_absolute()
        or ".." in Path(relative).parts
    ):
        raise Refusal("invalid historical commit/path provenance")
    if git(repository, "rev-parse", commit + "^{commit}").decode().strip() != commit:
        raise Refusal("historical source identity is not an exact commit")
    tree = git(repository, "rev-parse", commit + ":" + relative).decode().strip()
    entries = {}
    for line in git(repository, "ls-tree", "-r", "-z", commit, "--", relative).split(
        b"\0"
    ):
        if not line:
            continue
        meta, name = line.decode().split("\t", 1)
        mode, kind, oid = meta.split()
        if not name.startswith(relative + "/"):
            raise Refusal("historical source path is not a tracked directory")
        name = name[len(relative) + 1 :]
        if name == IDENTITY or any(part in EXCLUDE for part in Path(name).parts):
            continue
        if kind != "blob" or mode not in {"100644", "100755", "120000"}:
            raise Refusal("historical source contains unsupported Git resources")
        entries[name] = {"mode": mode, "blob": oid}
    if not entries:
        raise Refusal("historical source tree is empty")
    return {
        "commit": commit,
        "tree": tree,
        "path": relative,
        "inventory_sha256": digest(entries),
    }, entries


def blob_identity(path: Path, wanted: Mapping[str, str]) -> dict[str, str]:
    if path.is_symlink():
        data, mode = os.fsencode(os.readlink(path)), "120000"
    elif path.is_file():
        data = path.read_bytes()
        mode = "100755" if path.stat().st_mode & 0o111 else "100644"
    else:
        raise Refusal("historical source resource is absent")
    algorithm = hashlib.sha1 if len(wanted["blob"]) == 40 else hashlib.sha256
    return {
        "mode": mode,
        "blob": algorithm(
            b"blob " + str(len(data)).encode() + b"\0" + data
        ).hexdigest(),
    }


def historical_source(source: Path, runtime_root: Path) -> dict[str, str]:
    repository = Path(
        git(source, "rev-parse", "--show-toplevel").decode().strip()
    ).resolve()
    relative = source.relative_to(repository).as_posix()
    if relative == "." or git(
        repository, "status", "--porcelain=v1", "--untracked-files=all"
    ):
        raise Refusal("historical build requires a clean Git source subdirectory")
    commit = git(repository, "rev-parse", "HEAD^{commit}").decode().strip()
    metadata, entries = git_source(repository, commit, relative)
    if set(inventory(source, EXCLUDE)) != set(entries) or any(
        blob_identity(source / name, entry) != entry for name, entry in entries.items()
    ):
        raise Refusal("historical source bytes differ from the exact Git tree")
    # The frozen artifact can outlive its source worktree. Verification reads the
    # recorded objects from the existing runtime repository, never its live HEAD.
    available, _ = git_source(runtime_root, commit, relative)
    if available != metadata:
        raise Refusal("runtime repository differs from historical source provenance")
    return metadata


def source_surface(name: str) -> bool:
    return name in {"NOTT.md", "hooks.json"} or name.startswith(("skills/", "hooks/"))


def verify_historical(root: Path, runtime: RuntimeBinding) -> None:
    metadata = runtime.get("source")
    if not isinstance(metadata, dict) or set(metadata) != {
        "commit",
        "tree",
        "path",
        "inventory_sha256",
    }:
        raise Refusal("historical commit provenance is missing")
    repository = Path(runtime["repository"])
    observed, entries = git_source(repository, metadata["commit"], metadata["path"])
    if observed != metadata:
        raise Refusal("historical commit/tree provenance differs")
    transforms = []
    expected_data = {}
    for name in BINDINGS:
        relative = "hooks/" + name
        original = git(repository, "cat-file", "blob", entries[relative]["blob"])
        bound = bound_hook(name, original, repository)
        expected_data[relative] = bound
        transforms.append(
            {
                "path": relative,
                "source_sha256": hashlib.sha256(original).hexdigest(),
                "bundle_sha256": hashlib.sha256(bound).hexdigest(),
                "kind": "repository-binding",
            }
        )
    if runtime.get("transforms") != transforms:
        raise Refusal("historical runtime transforms differ from their source")
    for client in (None, *CLIENTS):
        directory = root if client is None else root / "clients" / client
        selected = {
            name: entry
            for name, entry in entries.items()
            if source_surface(name)
            and not (client == "agy" and name == "hooks/hooks.json")
            and not (client in {"claude", "codex"} and name == "hooks.json")
        }
        if {name for name in inventory(directory) if source_surface(name)} != set(
            selected
        ):
            raise Refusal("historical source-owned surface inventory differs")
        for name, entry in selected.items():
            target = directory / name
            if name in expected_data:
                if (
                    target.is_symlink()
                    or target.read_bytes() != expected_data[name]
                    or bool(target.stat().st_mode & 0o111)
                    != (entry["mode"] == "100755")
                ):
                    raise Refusal("historical hook runtime binding differs")
            elif blob_identity(target, entry) != entry:
                raise Refusal(
                    "historical law, skills or hooks differ from the recorded commit"
                )


def runner_actions(runner: Path) -> dict[object, set[str]]:
    """Which hook scripts each runner action runs, read from the runner's source.

    An `if action == "x":` (or `action in {...}`) block owns every hook filename
    written in it, plus the names of any module-level tuple it references
    (codex-hook-runner.py SHELL_GUARDS). Nothing here is hand-listed.
    """
    tree = ast.parse(runner.read_text())
    tuples = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(
            node.value, (ast.Tuple, ast.List)
        ):
            if not isinstance(node.targets[0], ast.Name):
                continue
            try:
                tuples[node.targets[0].id] = ast.literal_eval(node.value)
            except AttributeError, ValueError:
                continue
    actions: dict[object, set[str]] = {}
    for action_node in ast.walk(tree):
        test = action_node.test if isinstance(action_node, ast.If) else None
        if not (
            isinstance(test, ast.Compare)
            and isinstance(test.left, ast.Name)
            and test.left.id == "action"
        ):
            continue
        right = test.comparators[0]
        names = (
            [right.value]
            if isinstance(right, ast.Constant)
            else [elt.value for elt in getattr(right, "elts", [])]
        )
        scripts = set()
        for sub in ast.walk(action_node):
            if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
                if HOOK_SCRIPT.fullmatch(sub.value):
                    scripts.add(sub.value)
            elif isinstance(sub, ast.Name) and sub.id in tuples:
                scripts.update(s for s in tuples[sub.id] if HOOK_SCRIPT.fullmatch(s))
        for name in names:
            actions.setdefault(name, set()).update(scripts)
    return actions


def hook_script(command: object) -> str:
    """The first admitted native resource a hook command runs."""
    return Path(hook_resources(command)[0]).name


def without_scripts(
    groups: list[dict[str, Any]], scripts: Collection[str]
) -> list[dict[str, Any]]:
    """`groups` minus every hook whose command names one of `scripts`; emptied
    groups go. A name test, not a parse: a view must build from any command."""
    kept = []
    for group in groups:
        hooks = [
            h
            for h in group["hooks"]
            if not any(name in str(h.get("command", "")) for name in scripts)
        ]
        if hooks:
            kept.append({**group, "hooks": hooks})
    return kept


def refuse_bound_exclusions(source: Path) -> None:
    """A view's runner must not run a script the view excludes: the matrix and
    the built view would say `not projected` while the runner runs it."""
    for client, view in CLIENT_VIEWS.items():
        excluded = view.get("excluded", {})
        runner = source / "hooks" / view["runner"] if view["runner"] else None
        if not excluded or runner is None or not runner.is_file():
            continue
        bound = sorted(
            {
                script
                for scripts in runner_actions(runner).values()
                for script in scripts
            }
            & set(excluded)
        )
        if bound:
            raise Refusal(
                f"{client}: {runner.name} binds {', '.join(bound)}, which the "
                f"{client} view excludes"
            )


def matrix(source: Path) -> list[tuple[str, str, str, str, str, str]]:
    """Rows (client, hook, event, route, proof, reason) derived from hooks/hooks.json
    and the runner bindings, one row per source binding per client."""
    refuse_bound_exclusions(source)
    hooks = json.loads((source / "hooks/hooks.json").read_text())["hooks"]
    rows = []
    for client in CLIENTS:
        view = CLIENT_VIEWS[client]
        runs = (
            runner_actions(source / "hooks" / view["runner"]) if view["runner"] else {}
        )
        absent = view["not_projected"]
        for event, groups in hooks.items():
            for group in groups:
                matcher = group.get("matcher", "")
                for hook in group["hooks"]:
                    # The hook script is the first argv token that names one,
                    # so `python3 ".../hooks/x.py"` renders x.py, not python3.
                    script = hook_script(hook.get("command"))
                    route, proof, reason = "not projected", "", ""
                    excluded = view.get("excluded", {})
                    if script in excluded:
                        reason = excluded[script]
                    elif view["verbatim"] is None or event in view["verbatim"]:
                        route, proof = "verbatim", "unproven"
                    else:
                        for action, binding in view["actions"].items():
                            if binding["event"] == event and script in runs.get(
                                action, ()
                            ):
                                route = f"{client} {action}"
                                proof = binding["proof"].get(script, "unproven")
                                break
                    if route == "not projected" and not reason:
                        reason = (
                            absent["events"].get(event)
                            or absent["matchers"].get(matcher)
                            or absent["hooks"].get(script)
                            or "undeclared"
                        )
                    rows.append((client, script, event, route, proof, reason))
    return rows


def render_matrix(rows: list[tuple[str, str, str, str, str, str]]) -> str:
    lines = [
        "| client | hook script | event | route | proof | not loaded because |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |")
    return "\n".join(lines) + "\n"


def node_runner(source: str) -> str:
    """Project existing native payload/guard logic; remove campaign admission only."""
    tree = ast.parse(source)
    projected = False

    class Projection(ast.NodeTransformer):
        def visit_Assign(self, node: ast.Assign) -> ast.AST:
            if any(
                isinstance(target, ast.Name) and target.id == "SHELL_GUARDS"
                for target in node.targets
            ):
                guards = ast.literal_eval(node.value)
                node.value = ast.Tuple(
                    elts=[
                        ast.Constant(value=name)
                        for name in guards
                        if name in NODE_GUARDS
                    ],
                    ctx=ast.Load(),
                )
            return self.generic_visit(node)

        def visit_If(self, node: ast.If) -> ast.AST:
            nonlocal projected
            if (
                isinstance(node.test, ast.Compare)
                and isinstance(node.test.left, ast.Name)
                and node.test.left.id == "action"
                and isinstance(node.test.comparators[0], ast.Constant)
                and node.test.comparators[0].value == "pre-shell"
            ):
                for index, statement in enumerate(node.body):
                    if isinstance(statement, ast.Assign) and any(
                        isinstance(target, ast.Name) and target.id == "freestanding"
                        for target in statement.targets
                    ):
                        node.body = [
                            *node.body[:index],
                            ast.Return(value=ast.Constant(value=0)),
                        ]
                        projected = True
                        break
            return self.generic_visit(node)

        def visit_Expr(self, node: ast.Expr) -> ast.AST | None:
            call = node.value
            if (
                isinstance(call, ast.Call)
                and isinstance(call.func, ast.Name)
                and call.func.id == "hook"
                and call.args
                and isinstance(call.args[0], ast.Constant)
                and call.args[0].value in {"red-first.sh", "two-misses.sh"}
            ):
                return None
            return self.generic_visit(node)

    tree = Projection().visit(tree)
    if not projected:
        raise Refusal("Codex node projection cannot identify native shell admission")
    ast.fix_missing_locations(tree)
    compile(tree, "codex-node-hook-runner.py", "exec")
    return ast.unparse(tree) + "\n"


def build(
    source: Path,
    output: Path,
    runtime_root: Path,
    historical: bool = False,
    source_commit: str | None = None,
) -> BundleManifest:
    source = source.resolve(strict=True)
    public = (source / ".nott-public.json").is_file()
    if public and json.loads((source / ".nott-public.json").read_text()) != {
        "schema": 1
    }:
        raise Refusal("public plugin profile is unsupported")
    if public and historical:
        raise Refusal("public source cannot use a private historical runtime")
    if (
        public
        and source_commit is not None
        and not re.fullmatch(r"[0-9a-f]{40}", source_commit)
    ):
        raise Refusal("public source identity requires an exact commit")
    runtime_root = runtime_root.resolve(strict=True)
    if public:
        for name in ("nmemory", "nspawn", "nbrowser"):
            selected = runtime_root / "bin" / name
            if not selected.is_file() or not os.access(selected, os.X_OK):
                raise Refusal(f"public runtime does not supply executable {name}")
    output = output.absolute()
    if output == source or source in output.parents:
        raise Refusal("bundle output must be outside the source plugin")
    # Inspect links before copytree follows any of them; exclude eval data entirely.
    for path in source.rglob("*"):
        if any(part in EXCLUDE for part in path.relative_to(source).parts):
            continue
        if path.is_symlink():
            try:
                path.resolve(strict=True).relative_to(source)
            except (ValueError, OSError, RuntimeError) as error:
                raise Refusal(
                    f"source link escapes plugin: {path.relative_to(source)}"
                ) from error
    for required in (
        "NOTT.md",
        ".codex-plugin/plugin.json",
        ".claude-plugin/plugin.json",
        "hooks/hooks.json",
        "hooks.json",
        ".mcp.json",
    ):
        if not (source / required).is_file():
            raise Refusal(f"required plugin resource missing: {required}")
    try:
        members = runtime_members(json.loads((source / ".mcp.json").read_text()))
    except (ValueError, OSError) as error:
        raise Refusal(f"plugin MCP config is unreadable: {error}") from error
    for member in [] if public else members:
        if not (runtime_root / member / "pyproject.toml").is_file():
            raise Refusal(f"runtime-root does not contain {member}/pyproject.toml")
    refuse_bound_exclusions(source)
    source_runtime = source / ".nott-runtime.json"
    if (
        not historical
        and source_runtime.exists()
        and json.loads(source_runtime.read_text()).get("purpose")
        == "historical-evaluation"
    ):
        raise Refusal("historical evaluation bundle cannot be rebuilt as current")
    provenance = historical_source(source, runtime_root) if historical else None
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".nott-build-", dir=output.parent
    ) as scratch:
        stage = Path(scratch) / "bundle"
        shutil.copytree(
            source,
            stage,
            symlinks=True,
            ignore=shutil.ignore_patterns(
                *EXCLUDE, IDENTITY, *(("packages", ".git") if public else ())
            ),
        )
        config = json.loads((stage / ".mcp.json").read_text())
        # `${NOTT_MCP_DIR}` is resolved here for the same reason the plugin root
        # is: `validate_mcp` demands a command that actually exists, and the
        # committed file must not name one machine. The default matches
        # tools/mcp.sh. A public build uses installed executable names.
        if public:
            mcps_dir = ""
        else:
            mcps_dir = env("NOTT_MCP_DIR") or (str(pathlib.Path.home() / ".nott/mcps"))
        for server in config["mcpServers"].values():
            if isinstance(server.get("command"), str):
                server["command"] = server["command"].replace(
                    "${NOTT_MCP_DIR}", mcps_dir
                )
        for server in config["mcpServers"].values():
            if server.get("type") == "http":
                continue
            server["args"] = [
                str(runtime_root / arg.removeprefix(RUNTIME_PREFIX))
                if arg.startswith(RUNTIME_PREFIX)
                else arg
                for arg in server.get("args", [])
            ]
        if public:
            if any(
                server.get("command") != name
                or name not in {"nmemory", "nspawn", "nbrowser"}
                for name, server in config["mcpServers"].items()
            ):
                raise Refusal("public MCP commands must name their runtime packages")
            validate_mcp(
                {
                    "mcpServers": {
                        name: {**server, "command": str(runtime_root / "bin" / name)}
                        for name, server in config["mcpServers"].items()
                    }
                }
            )
        else:
            validate_mcp(config)
        write_json(stage / ".mcp.json", config)
        write_json(stage / "mcp_config.json", config)
        runtime: RuntimeBinding = {
            "repository": "." if public else str(runtime_root),
            "purpose": "historical-evaluation" if historical else "current",
            "packager_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        }
        if public and source_commit is not None:
            runtime["source_commit"] = source_commit
        if historical:
            runtime["source"] = provenance
            runtime["transforms"] = []
        for name in {} if public else BINDINGS:
            target = stage / "hooks" / name
            original = target.read_bytes()
            bound = bound_hook(name, original, runtime_root)
            target.write_bytes(bound)
            if historical:
                runtime["transforms"].append(
                    {
                        "path": "hooks/" + name,
                        "source_sha256": hashlib.sha256(original).hexdigest(),
                        "bundle_sha256": hashlib.sha256(bound).hexdigest(),
                        "kind": "repository-binding",
                    }
                )
        write_json(stage / ".nott-runtime.json", runtime)
        # Copies are generated from one semantic source. Native installers cache one
        # view, so links to a parent bundle would break after installation.
        for client in CLIENTS:
            view = stage / "clients" / client
            view.mkdir(parents=True)
            for name in (
                "skills",
                "scripts",
                "tests",
                "rules",
                "NOTT.md",
                ".mcp.json",
                "mcp_config.json",
                ".nott-runtime.json",
                ".claude-plugin",
                ".codex-plugin",
                "plugin.json",
                # The Claude manifest declares ./types/index.d.ts; absent, the
                # runtime loader reports a load failure.
                *(("types",) if (stage / "types").is_dir() else ()),
                *((".nott-public.json",) if public else ()),
            ):
                if (stage / name).is_dir():
                    shutil.copytree(stage / name, view / name, symlinks=True)
                else:
                    shutil.copy2(stage / name, view / name)
            if client == "claude" and (stage / "agents").is_dir():
                # Claude Code loads plugin agents from agents/; the other clients have
                # none, and a historical source older than the agents has no folder.
                # The MIT notice of the vendored agents ships with every copy of them.
                # A historical source from #1305 to #1662 has vendor/ecc.json but no notice.
                if not historical and not (stage / "vendor/ECC-LICENSE.txt").is_file():
                    raise Refusal(
                        "vendor/ECC-LICENSE.txt is missing. The vendored agents need "
                        "their license notice."
                    )
                shutil.copytree(stage / "agents", view / "agents", symlinks=True)
                if (stage / "vendor").is_dir():
                    shutil.copytree(stage / "vendor", view / "vendor", symlinks=True)
            if client != "claude":
                # Codex and AGY run on the stdio host; their loaders are unproven
                # for the http shape, so their views carry stdio entries only.
                stdio = {
                    "mcpServers": {
                        name: server
                        for name, server in config["mcpServers"].items()
                        if server.get("type") != "http" and name != "nott-node"
                    }
                }
                write_json(view / ".mcp.json", stdio)
                write_json(view / "mcp_config.json", stdio)
            (view / "hooks").mkdir()
            for path in (stage / "hooks").iterdir():
                if path.name != "hooks.json":
                    shutil.copy2(path, view / "hooks" / path.name)
            view_spec = CLIENT_VIEWS[client]
            if client == "agy":
                # The AGY view: rules/AGENTS.md and the root hooks.json, every
                # entry routed through agy-hook-runner.py. Declared in
                # CLIENT_VIEWS["agy"]; plugin/tests/agy-view-smoke.sh proves it.
                shutil.copy2(stage / "hooks.json", view / "hooks.json")
            elif historical:
                shutil.copy2(stage / "hooks/hooks.json", view / "hooks/hooks.json")
            else:
                hooks = json.loads((stage / "hooks/hooks.json").read_text())
                if view_spec["verbatim"] is not None:
                    # The Codex view: the law byte-identical, the verbatim events
                    # and one synthesized runner binding per action, all declared
                    # in CLIENT_VIEWS["codex"]; plugin/tests/codex-view-smoke.sh
                    # feeds the built runner each deny and its allow control.
                    excluded = view_spec.get("excluded", {})
                    hooks = {
                        "hooks": {
                            name: kept
                            for name, groups in hooks["hooks"].items()
                            if name in view_spec["verbatim"]
                            and (kept := without_scripts(groups, excluded))
                        }
                    }
                    for action, binding in view_spec["actions"].items():
                        runner = view_spec["runner"]
                        if runner is None:
                            raise Refusal(f"{client} actions require a runner")
                        hooks["hooks"].setdefault(binding["event"], []).append(
                            {
                                # Stop takes no matcher.
                                **(
                                    {"matcher": binding["matcher"]}
                                    if "matcher" in binding
                                    else {}
                                ),
                                "hooks": [
                                    {
                                        "type": "command",
                                        "command": 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/'
                                        + runner
                                        + '" '
                                        + action,
                                        "timeout": 10,
                                    }
                                ],
                            }
                        )
                    for groups in hooks["hooks"].values():
                        for group in groups:
                            for hook in group["hooks"]:
                                if (
                                    hook_script(hook.get("command"))
                                    == "session-state.sh"
                                ):
                                    hook["command"] = (
                                        "NOTT_HOOK_CLIENT=codex " + hook["command"]
                                    )
                    # Declare only what the client honours (CODEX_TIMEOUT_CEILINGS).
                    for event, groups in hooks["hooks"].items():
                        ceiling = CODEX_TIMEOUT_CEILINGS.get(event)
                        if ceiling is None:
                            continue
                        for group in groups:
                            for hook in group["hooks"]:
                                if hook.get("timeout", 600) > ceiling:
                                    hook["timeout"] = ceiling
                write_json(view / "hooks/hooks.json", hooks)
        if not historical:
            for client in ("claude", "codex"):
                view = stage / "clients" / (client + "-node")
                shutil.copytree(stage / "clients" / client, view, symlinks=True)
                stdio = {
                    "mcpServers": {
                        name: server
                        for name, server in config["mcpServers"].items()
                        if server.get("type") != "http" and name != "nott-node"
                    }
                }
                write_json(view / ".mcp.json", stdio)
                write_json(view / "mcp_config.json", stdio)
                if client == "claude":
                    hooks = json.loads((view / "hooks/hooks.json").read_text())
                    omitted = {
                        hook_script(hook.get("command"))
                        for groups in hooks["hooks"].values()
                        for group in groups
                        for hook in group["hooks"]
                    } - NODE_GUARDS
                    hooks = {
                        "hooks": {
                            event: kept
                            for event, groups in hooks["hooks"].items()
                            # final-state.sh also binds UserPromptSubmit; a node has none.
                            if event != "UserPromptSubmit"
                            and (kept := without_scripts(groups, omitted))
                        }
                    }
                    # final-state.sh judges the voice alone here: a node has no statusline.
                    for groups in hooks["hooks"].values():
                        for group in groups:
                            for hook in group["hooks"]:
                                if hook_script(hook.get("command")) == "final-state.sh":
                                    hook["command"] = (
                                        "NOTT_HOOK_CLIENT=node " + hook["command"]
                                    )
                    write_json(view / "hooks/hooks.json", hooks)
                else:
                    hooks = json.loads((view / "hooks/hooks.json").read_text())
                    hooks["hooks"] = {
                        event: groups
                        for event, groups in hooks["hooks"].items()
                        if event in {"PreToolUse", "PostToolUse", "Stop"}
                    }
                    write_json(view / "hooks/hooks.json", hooks)
                    runner_path = view / "hooks/codex-hook-runner.py"
                    runner_path.write_text(node_runner(runner_path.read_text()))
                    (view / ".agents").mkdir()
                    (view / ".agents/skills").symlink_to("../skills")
        # One identity, three client shapes. Only the Codex view carried a version,
        # so the other two inherited whatever it happened to say — a silent pick, and
        # the three could name different products without anything noticing.
        identities = {
            native: {
                field: json.loads((stage / native).read_text()).get(field)
                for field in ("name", "version", "description")
            }
            for native in NATIVE
        }
        base = identities[".codex-plugin/plugin.json"]
        if base["name"] != "nott":
            raise Refusal("the native plugin name must be nott")
        if not isinstance(base["version"], str) or not base["version"]:
            raise Refusal("the native plugin must declare a version")
        for native, identity in identities.items():
            if identity != base:
                raise Refusal(f"{native} differs from the declared identity")
        # Codex keeps every cached version and loads the highest-sorting one, so the
        # patch is the packaged commit's committer time: a later release, a squash
        # merge or a rebase onto main included, sorts above every earlier one by
        # name and by semver, and a shallow clone still knows it. Source content,
        # compiler bytes and explicit runtime bindings determine the digest, kept
        # as build metadata.
        # ponytail: the order is guaranteed along main's merge history only; a
        # branch build must never be installed into a shared cache. Two commits in
        # the same second fall back to the digest, and a skewed clock can invert
        # the order. The name order holds while the time has 10 digits (until 2286).
        # The time is the packaged commit's. The runtime root only decides where
        # the hooks point; a runtime checkout that never moves would stamp every
        # release with its own time. A historical build names its commit, and so
        # does an export (`--source-commit`, the commit it was archived from); the
        # runtime root holds both. Otherwise the source sits at the top of its
        # checkout and the commit is that checkout's HEAD.
        if public:
            base_version = base["version"].split("+")[0]
        elif provenance:
            patch = commit_time(runtime_root, provenance["commit"])
        elif source_commit is not None:
            patch = commit_time(
                runtime_root,
                source_commit + "^{commit}",
                f"--source-commit {source_commit} is not a commit the runtime root "
                f"{runtime_root} holds; pass the commit the source was exported from",
            )
        else:
            patch = commit_time(source.parent, "HEAD")
        if not public:
            base_version = base["version"].split("+")[0].rsplit(".", 1)[0] + f".{patch}"
        content_identity = digest(
            version_inventory(stage, inventory(stage), base_version)
        )
        version = base_version + "+sha." + content_identity
        for directory in view_directories(stage):
            for manifest_path in NATIVE:
                path = directory / manifest_path
                manifest = json.loads(path.read_text())
                if manifest.get("name") != "nott":
                    raise Refusal(f"invalid native plugin name in {manifest_path}")
                manifest["version"] = version
                write_json(path, manifest)
        files = inventory(stage)
        bundle_manifest: BundleManifest = {
            "schema": 1,
            "version": version,
            "source_digest": content_identity,
            "digest": digest(files),
            "components": components(files),
            "files": files,
        }
        write_json(stage / IDENTITY, bundle_manifest)
        (verify if historical else admit_current)(stage)
        if historical and historical_source(source, runtime_root) != provenance:
            raise Refusal("historical source changed during packaging")
        if output.exists():
            previous = verify(output)
            if previous != bundle_manifest:
                raise Refusal(
                    "destination already binds different bytes; choose a new bundle destination"
                )
        else:
            stage.rename(output)
        (verify if historical else admit_current)(output)
        return bundle_manifest


def main(argv: list[str] | None = None) -> int:
    """The packager's verbs of `plugin/scripts/plugin.py`: build, verify, admit, show
    and deliver."""
    parser = argparse.ArgumentParser(prog="plugin.py", description=__doc__)
    verbs = parser.add_subparsers(dest="verb")
    build_verb = verbs.add_parser("build", help="build a content-addressed bundle")
    build_verb.add_argument("--source", type=Path)
    build_verb.add_argument("--output", type=Path)
    build_verb.add_argument("--runtime-root", type=Path)
    build_verb.add_argument("--historical", action="store_true")
    build_verb.add_argument(
        "--source-commit", help="the commit an exported --source was archived from"
    )
    verbs.add_parser("verify", help="verify a bundle's bytes").add_argument(
        "bundle", type=Path
    )
    verbs.add_parser("admit", help="admit a bundle as the current law").add_argument(
        "bundle", type=Path
    )
    verbs.add_parser("show", help="print the client matrix").add_argument(
        "--source", type=Path
    )
    deliver_verb = verbs.add_parser(
        "deliver",
        help="write the plugin/ of a commit into a checkout; keep its local edits",
    )
    deliver_verb.add_argument("commit")
    deliver_verb.add_argument("checkout", type=Path)
    deliver_verb.add_argument(
        "--base",
        action="append",
        default=[],
        help=f"a commit that the files of a checkout without {DELIVERED_REF} came "
        "from. Repeat it for each commit",
    )
    try:
        args = parser.parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    try:
        if args.verb == "show":
            source = args.source or Path(__file__).resolve().parents[2]
            sys.stdout.write(render_matrix(matrix(source)))
            return 0
        if args.verb == "deliver":
            print(json.dumps(deliver(args.commit, args.checkout, args.base)))
            return 0
        if args.verb == "verify":
            result = verify(args.bundle)
        elif args.verb == "admit":
            result = admit_current(args.bundle)
        elif args.verb == "build":
            if not all((args.source, args.output, args.runtime_root)):
                raise Refusal("build requires --source, --output and --runtime-root")
            result = build(
                args.source,
                args.output,
                args.runtime_root,
                historical=args.historical,
                source_commit=args.source_commit,
            )
        else:
            parser.print_usage(sys.stderr)
            return 2
        print(
            json.dumps(
                {
                    "version": result["version"],
                    "digest": result["digest"],
                    "components": result["components"],
                }
            )
        )
        return 0
    except (
        Refusal,
        RenamedVariableError,
        json.JSONDecodeError,
        KeyError,
        TypeError,
        FileNotFoundError,
    ) as error:
        print(f"PACKAGE REFUSED: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"PACKAGE OPERATIONAL: {error}", file=sys.stderr)
        return 1
