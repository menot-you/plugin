"""Activate owned configuration. Restore it without replacing unrelated settings.

Private activation keeps its existing instruction path.
Public activation uses the native registry and an owned memory bootstrap.
"""

import argparse
import hashlib
import importlib.util
import json
import os
import re
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Literal, Never, NotRequired, TypedDict, TypeGuard


class ClaudeSettings(TypedDict, total=False):
    env: dict[str, object]


class ClaudeEnvRecord(TypedDict):
    kind: Literal["claude-env"]
    path: str
    before: dict[str, object]
    after: dict[str, object]
    env_present: bool
    file_present: bool
    restored: NotRequired[bool]


class McpConfig(TypedDict, total=False):
    mcpServers: dict[str, dict[str, object]]


class AgyMcpRecord(TypedDict):
    kind: Literal["agy-mcp"]
    root: str
    link_before: str | None
    link_after: str
    file_present: bool
    servers_field_present: bool
    before_hashes: dict[str, str | None]
    after_hashes: dict[str, str | None]
    backup: str
    backup_sha256: str


class InstructionRecord(TypedDict):
    kind: Literal["instruction"]
    path: str
    before: str | None
    after: str
    separator: str
    field_present: bool
    file_present: bool
    restore_identity: NotRequired[list[bool | str | None]]


class LinkRecord(TypedDict):
    kind: Literal["link"]
    path: str
    before: str | None
    after: str


class NativeRecord(TypedDict):
    kind: Literal["native"]
    root: str
    runtime: str
    bootstrap: str
    market: str
    view: str
    view_files: dict[str, dict[str, str | bool]]
    surfaces: list[dict[str, Any]]
    separator: NotRequired[str]
    client: NotRequired[str]
    version: NotRequired[str]
    bootstrap_hooks: NotRequired[str | None]


type ActivationRecord = (
    InstructionRecord | ClaudeEnvRecord | LinkRecord | AgyMcpRecord | NativeRecord
)


class ActivationReceipt(TypedDict):
    schema: int
    client: str
    records: list[ActivationRecord]
    state: NotRequired[str]
    # Public metadata is retained verbatim; rollback only consumes typed fields.
    bundle: NotRequired[object]
    digest: NotRequired[object]
    view: NotRequired[object]
    runtime_observed: NotRequired[object]
    native_registration: NotRequired[object]
    receipt_path: NotRequired[str]
    transaction: NotRequired[str]
    reused_unowned: NotRequired[object]
    mcp_shadow: NotRequired[object]
    readiness: NotRequired[dict[str, str]]
    memory: NotRequired[dict[str, str]]


class AgyBackup(TypedDict):
    schema: int
    before: dict[str, dict[str, object] | None]
    after: dict[str, dict[str, object] | None]
    ownership_before: dict[str, object] | None


class AgyOwnership(TypedDict):
    schema: int
    client: str
    config_root: str
    receipt: str
    receipt_sha256: str
    transaction: str
    owned: dict[str, str]


import tomllib

BEGIN = "<!-- NOTT:BEGIN -->"
END = "<!-- NOTT:END -->"
BLOCK = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.DOTALL)
UNMARKED_LAW = re.compile(r'# \*\*NOTT\*\* System Prompt|<NOTT version="')
CLAUDE_ENV: dict[str, object] = {
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
    "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS": "1",
}
# What this installer's AGY transaction actually buys, measured 2026-09-13 with
# agy 1.2.2 in disposable homes. TWO things must hold before `agy plugin list`
# reports the plugin, and this installer writes only one of them:
#   * the `plugins/<name>` path -- a SYMLINK is honoured, so re-pointing it
#     upgrades the plugin in place;
#   * an `import_manifest.json` entry, written ONLY by `agy plugin install` and
#     PRUNED by the client the moment the path is missing.
# On a virgin root the installer alone leaves "No imported plugins."; on a root
# imported once, its symlink is the upgrade. Do NOT then run `agy plugin
# install`: it replaces the symlink with a real directory, after which this
# installer refuses both activation and rollback ("unmanaged object").
AGY_REGISTRATION = (
    "global-mcp and the plugins/<name> path; AGY lists the plugin only while its "
    "import_manifest.json entry survives, which `agy plugin install` writes once "
    "and this installer never does"
)
spec = importlib.util.spec_from_file_location(
    "package_plugin", Path(__file__).with_name("package.py")
)
if spec is None or spec.loader is None:
    raise ImportError("cannot load required package.py module")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
Refusal = package.Refusal


def file_identity(path: Path) -> tuple[bool, str | None]:
    if path.is_symlink():
        raise Refusal(f"linked configuration requires explicit migration: {path}")
    if not path.exists():
        return False, None
    if not path.is_file() or path.stat().st_size > 2_097_152:
        raise Refusal(f"configuration is not a bounded regular file: {path}")
    return True, hashlib.sha256(path.read_bytes()).hexdigest()


def atomic(
    path: Path, content: str, *, expected: tuple[bool, str | None] | None = None
) -> None:
    if path.is_symlink():
        raise Refusal(f"refusing to replace a linked configuration file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", dir=path.parent, delete=False
        ) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        temporary.chmod(mode)
        if expected is not None and file_identity(path) != expected:
            raise Refusal(f"shared configuration changed before replacement: {path}")
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def block(text: str) -> str | None:
    matches = BLOCK.findall(text)
    if (
        len(matches) > 1
        or text.count(BEGIN) != len(matches)
        or text.count(END) != len(matches)
    ):
        raise Refusal("ambiguous or unclosed NOTT managed instruction block")
    return matches[0] if matches else None


def replace_block(text: str, before: str | None, after: str | None) -> str:
    if block(text) != before:
        raise Refusal(
            "NOTT instruction block changed since activation; no rollback overwrite"
        )
    if before is not None:
        return text.replace(before, after or "", 1)
    return text + ("\n\n" if text else "") + (after or "")


def read_instruction(path: Path, client: str) -> tuple[str, str]:
    if path.is_symlink():
        raise Refusal(f"linked configuration requires explicit owner migration: {path}")
    raw = path.read_text() if path.exists() else ""
    if client != "codex":
        return raw, raw
    config = tomllib.loads(raw)
    value = config.get("developer_instructions", "")
    if not isinstance(value, str):
        raise Refusal("Codex developer_instructions is not a string")
    return raw, value


def encode_instruction(
    raw: str, value: str | None, *, remove_inserted_line: bool = False
) -> str:
    """Replace only the top-level TOML string, retaining every foreign byte."""
    parsed = tomllib.loads(raw)
    if "developer_instructions" not in parsed:
        if value is None:
            return raw
        return (
            "developer_instructions = "
            + json.dumps(value, ensure_ascii=False).replace("\x7f", "\\u007f")
            + "\n"
            + raw
        )
    expected = dict(parsed)
    del expected["developer_instructions"]
    for start in re.finditer(
        r"""(?m)^[ \t]*(?:developer_instructions|"(?:[^"\\\r\n]|\\.)*"|'[^'\r\n]*')[ \t]*=""",
        raw,
    ):
        # TOML parses complete string values, including multiline literals. Compare
        # parsed remainder to avoid selecting the same key inside a foreign table.
        for end in re.finditer(r"\n|\Z", raw[start.start() :]):
            stop = start.start() + end.end()
            fragment = raw[start.start() : stop]
            try:
                item = tomllib.loads(fragment)
                remaining = tomllib.loads(raw[: start.start()] + raw[stop:])
            except tomllib.TOMLDecodeError:
                continue
            if (
                item == {"developer_instructions": parsed["developer_instructions"]}
                and remaining == expected
            ):
                value_start = fragment.index("=") + 1
                while fragment[value_start].isspace():
                    value_start += 1
                delimiters = ('"""', "'''", '"', "'")
                delimiter = next(
                    mark
                    for mark in delimiters
                    if fragment.startswith(mark, value_start)
                )
                # Four/five trailing quotes include content before the terminator;
                # examine overlapping candidates and let TOML identify the value.
                for closing in re.finditer(
                    "(?=" + re.escape(delimiter) + ")",
                    fragment[value_start + len(delimiter) :],
                ):
                    value_end = value_start + 2 * len(delimiter) + closing.start()
                    try:
                        if tomllib.loads(fragment[:value_end]) != item:
                            continue
                    except tomllib.TOMLDecodeError:
                        continue
                    replacement = (
                        ""
                        if value is None
                        else fragment[:value_start]
                        + json.dumps(value, ensure_ascii=False).replace(
                            "\x7f", "\\u007f"
                        )
                    )
                    suffix = fragment[value_end:]
                    if value is None and remove_inserted_line and suffix == "\n":
                        suffix = ""
                    return raw[: start.start()] + replacement + suffix + raw[stop:]
    raise Refusal(
        "cannot isolate top-level developer_instructions without changing other TOML"
    )


def save_receipt(path: Path, receipt: object) -> None:
    atomic(path, json.dumps(receipt, indent=2) + "\n")


def safe_owned_path(root: Path, relative: str, *, link: bool = False) -> Path:
    if Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise Refusal("NOTT configuration path escapes its declared root")
    path = root / relative
    current = root
    for part in Path(relative).parts:
        current = current / part
        if current.is_symlink() and not (link and current == path):
            raise Refusal(
                f"linked NOTT configuration requires explicit migration: {current}"
            )
    return path


@contextmanager
def agy_lock(root: Path, relative: str = ".nott-plugin-install.lock") -> Iterator[None]:
    """Serialize this installer's transactions; foreign writers are checked by CAS."""
    import fcntl

    path = safe_owned_path(root, relative)
    root.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise Refusal(f"NOTT installation lock is not a regular file: {path}")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal(
                f"another NOTT configuration transaction is active: {root}"
            ) from error
        yield
    finally:
        os.close(descriptor)


def read_json(path: Path) -> dict[str, object] | None:
    if path.is_symlink():
        raise Refusal(f"linked configuration requires explicit migration: {path}")
    if not path.exists():
        return None
    if not path.is_file() or path.stat().st_size > 2_097_152:
        raise Refusal(f"configuration is not a bounded regular file: {path}")
    value: object = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise Refusal(f"configuration must be an object: {path}")
    return value


def is_ownership(value: object) -> TypeGuard[AgyOwnership]:
    if not isinstance(value, dict):
        return False
    owned = value.get("owned")
    return (
        type(value.get("schema")) is int
        and all(
            isinstance(value.get(key), str)
            for key in (
                "client",
                "config_root",
                "receipt",
                "receipt_sha256",
                "transaction",
            )
        )
        and isinstance(owned, dict)
        and all(isinstance(k, str) and isinstance(v, str) for k, v in owned.items())
    )


def is_agy_backup(value: object) -> TypeGuard[AgyBackup]:
    if (
        not isinstance(value, dict)
        or type(value.get("schema")) is not int
        or value.get("schema") != 1
    ):
        return False
    for key in ("before", "after"):
        registrations = value.get(key)
        if not isinstance(registrations, dict) or any(
            not isinstance(name, str)
            or (server is not None and not isinstance(server, dict))
            for name, server in registrations.items()
        ):
            return False
    return "ownership_before" in value and (
        value["ownership_before"] is None or isinstance(value["ownership_before"], dict)
    )


def is_activation_receipt(value: object) -> TypeGuard[ActivationReceipt]:
    if (
        not isinstance(value, dict)
        or type(value.get("schema")) is not int
        or value.get("schema") != 1
        or value.get("client") not in package.CLIENTS
    ):
        return False
    check_receipt_records(value.get("records"))
    if any(record["kind"] == "native" for record in value["records"]) and (
        len(value["records"]) != 1
        or value["client"] not in {"claude", "codex"}
        or value["records"][0].get("client", "codex") != value["client"]
    ):
        raise Refusal("native activation requires one matching client transaction")
    if any(record["kind"] == "agy-mcp" for record in value["records"]) and (
        value["client"] != "agy" or len(value["records"]) != 1
    ):
        raise Refusal("AGY activation requires exactly one MCP receipt record")
    return all(
        name not in value or isinstance(value[name], str)
        for name in ("state", "transaction", "receipt_path")
    )


def claude_settings_snapshot(
    path: Path,
) -> tuple[ClaudeSettings, tuple[bool, str | None]]:
    present, _ = file_identity(path)
    raw = path.read_bytes() if present else b"{}"
    document: ClaudeSettings = json.loads(raw)
    if not isinstance(document, dict) or not isinstance(document.get("env", {}), dict):
        raise Refusal(f"Claude settings and env must be objects: {path}")
    return document, (present, hashlib.sha256(raw).hexdigest() if present else None)


def claude_env_values(document: ClaudeSettings) -> dict[str, object]:
    env = document.get("env", {})
    return {name: env[name] for name in CLAUDE_ENV if name in env}


def check_claude_env(
    path: Path, document: ClaudeSettings, expected: Mapping[str, object]
) -> None:
    actual = claude_env_values(document)
    for name in CLAUDE_ENV:
        if (name in actual) != (name in expected) or actual.get(name) != expected.get(
            name
        ):
            raise Refusal(f"Claude setting changed concurrently: {path}; key={name}")


def write_claude_env(
    record: ClaudeEnvRecord, *, rollback: bool = False, recovering: bool = False
) -> None:
    path = Path(record["path"])
    document, snapshot = claude_settings_snapshot(path)
    expected = record["after"] if rollback else record["before"]
    desired = record["before"] if rollback else record["after"]
    if rollback and (
        record.get("restored") or recovering and claude_env_values(document) == desired
    ):
        expected = desired
    check_claude_env(path, document, expected)
    if claude_env_values(document) == desired:
        return
    env = document.setdefault("env", {})
    for name in CLAUDE_ENV:
        env.pop(name, None)
    env.update(desired)
    if rollback and not env and not record["env_present"]:
        del document["env"]
    if rollback and not document and not record["file_present"]:
        if file_identity(path) != snapshot:
            raise Refusal(f"shared configuration changed before removal: {path}")
        path.unlink(missing_ok=True)
    else:
        atomic(
            path,
            json.dumps(document, indent=2, ensure_ascii=False) + "\n",
            expected=snapshot,
        )


def mcp_snapshot(path: Path) -> tuple[McpConfig, tuple[bool, str | None]]:
    if path.is_symlink():
        raise Refusal(f"linked configuration requires explicit migration: {path}")
    if not path.exists():
        return {"mcpServers": {}}, (False, None)
    if not path.is_file() or path.stat().st_size > 2_097_152:
        raise Refusal(f"configuration is not a bounded regular file: {path}")
    raw = path.read_bytes()
    value: McpConfig = json.loads(raw)
    if (
        not isinstance(value, dict)
        or not isinstance(value.get("mcpServers", {}), dict)
        or any(
            not isinstance(name, str) or not isinstance(server, dict)
            for name, server in value.get("mcpServers", {}).items()
        )
    ):
        raise Refusal(f"mcpServers must map names to registration objects: {path}")
    return value, (True, hashlib.sha256(raw).hexdigest())


def mcp_document(path: Path) -> McpConfig:
    return mcp_snapshot(path)[0]


def native_agy_server(value: object) -> dict[str, object]:
    """Documented empty defaults plus measured AGY treatment of Codex metadata.

    Native sentinel probes on AGY binary a8793092fbe6eea0... showed env_vars absent,
    selected and empty all inherit both sentinels; documented env still overrides.
    Never read or expand a named credential into the configuration or receipt.
    """
    if not isinstance(value, dict):
        raise Refusal("MCP registration is not an object")
    value = dict(value)
    if "env_vars" in value:
        if not isinstance(value["env_vars"], list) or any(
            not isinstance(name, str) for name in value["env_vars"]
        ):
            raise Refusal("Codex env_vars metadata is malformed")
        del value["env_vars"]
    if (
        value.get("type") == "stdio"
        and isinstance(value.get("command"), str)
        and "serverUrl" not in value
    ):
        del value["type"]
    for key, default in (
        ("args", []),
        ("env", {}),
        ("headers", {}),
        ("disabledTools", []),
        ("disabled", False),
    ):
        if key in value and type(value[key]) is type(default) and value[key] == default:
            del value[key]
    return value


def value_hash(value: object) -> str | None:
    if value is None:
        return None
    result: str = package.digest(value)
    return result


def link_value(path: Path) -> str | None:
    if path.is_symlink():
        return os.readlink(path)
    if path.exists():
        raise Refusal(f"AGY NOTT registration is an unmanaged object: {path}")
    return None


def set_link(path: Path, expected: str | None, target: str | None, nonce: str) -> None:
    if link_value(path) != expected:
        raise Refusal(f"AGY NOTT registration changed concurrently: {path}")
    if target == expected:
        return
    if target is None:
        path.unlink()
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(".nott-" + nonce)
    if temporary.exists() or temporary.is_symlink():
        raise Refusal(f"stale activation link requires reconciliation: {temporary}")
    temporary.symlink_to(target)
    try:
        temporary.replace(path)
    except OSError:
        if temporary.is_symlink() and os.readlink(temporary) == target:
            temporary.unlink()
        raise


def receipt_identity(receipt: Mapping[str, object]) -> str:
    result: str = package.digest(
        {key: value for key, value in receipt.items() if key != "state"}
    )
    return result


def ownership_for(receipt: ActivationReceipt) -> AgyOwnership:
    record = receipt["records"][0]
    if record["kind"] != "agy-mcp":
        raise Refusal("AGY activation requires an MCP receipt record")
    return {
        "schema": 1,
        "client": "agy",
        "config_root": record["root"],
        "receipt": receipt["receipt_path"],
        "receipt_sha256": receipt_identity(receipt),
        "transaction": receipt["transaction"],
        "owned": {
            name: digest
            for name, digest in record["after_hashes"].items()
            if digest is not None
        },
    }


def active_ownership(root: Path) -> AgyOwnership | None:
    path = safe_owned_path(root, ".nott-mcp-ownership.json")
    owned = read_json(path)
    if owned is None:
        return None
    if (
        not is_ownership(owned)
        or owned.get("schema") != 1
        or owned.get("client") != "agy"
        or owned.get("config_root") != str(root)
    ):
        raise Refusal(f"unknown NOTT MCP ownership metadata: {path}")
    previous = read_json(Path(owned["receipt"]))
    if (
        not is_activation_receipt(previous)
        or previous.get("state") != "configured"
        or ownership_for(previous) != owned
    ):
        raise Refusal(f"NOTT MCP ownership does not match its active receipt: {path}")
    return owned


def conflict(path: Path, name: str, expected: str | None, actual: str | None) -> Never:
    raise Refusal(
        f"MCP registration conflict: {path}; key={name}; expected_sha256={expected or 'absent'}; observed_sha256={actual or 'absent'}"
    )


def write_mcp_delta(
    root: Path,
    expected: Mapping[str, str | None],
    replacement: Mapping[str, dict[str, object] | None],
    *,
    remove_empty: bool = False,
    remove_servers: bool = False,
) -> None:
    """Read current shared state at the write boundary; change only declared keys."""
    path = safe_owned_path(root, "mcp_config.json")
    current, snapshot = mcp_snapshot(path)
    servers = current.setdefault("mcpServers", {})
    for name, expected_hash in expected.items():
        actual = value_hash(servers.get(name))
        if actual != expected_hash:
            conflict(path, name, expected_hash, actual)
    if all(value_hash(value) == expected[name] for name, value in replacement.items()):
        return
    for name, value in replacement.items():
        if value is None:
            servers.pop(name, None)
        else:
            servers[name] = value
    if not servers and remove_servers:
        del current["mcpServers"]
    if remove_empty and current in ({}, {"mcpServers": {}}):
        if file_identity(path) != snapshot:
            raise Refusal(f"shared configuration changed before removal: {path}")
        if path.exists():
            path.unlink()
    else:
        atomic(
            path,
            json.dumps(current, indent=2, ensure_ascii=False) + "\n",
            expected=snapshot,
        )


def install_agy(
    view: Path, root: Path, receipt_path: Path, receipt: ActivationReceipt
) -> None:
    config = safe_owned_path(root, "mcp_config.json")
    registry = safe_owned_path(root, ".nott-mcp-ownership.json")
    link = safe_owned_path(root, "plugins/nott", link=True)
    if receipt_path.resolve() in {config, registry, link}:
        raise Refusal("activation receipt collides with managed configuration")
    previous_link = link_value(link)
    document = mcp_document(config)
    current = document.get("mcpServers", {})
    prior = active_ownership(root)
    owned = prior["owned"] if prior else {}
    if prior:
        previous_receipt = read_json(Path(prior["receipt"]))
        if not is_activation_receipt(previous_receipt):
            raise Refusal("NOTT ownership has no valid activation receipt")
        previous_record = previous_receipt["records"][0]
        if previous_record["kind"] != "agy-mcp":
            raise Refusal("NOTT ownership has no MCP activation record")
        if previous_link != previous_record["link_after"]:
            raise Refusal(
                "NOTT registration no longer matches the active MCP ownership"
            )
    desired_document, desired_identity = mcp_snapshot(view / "mcp_config.json")
    if not desired_identity[0]:
        raise Refusal("AGY bundle MCP configuration is missing")
    desired = {
        name: native_agy_server(server)
        for name, server in desired_document["mcpServers"].items()
    }
    for name, expected in owned.items():
        if value_hash(current.get(name)) != expected:
            conflict(config, name, expected, value_hash(current.get(name)))
    reused = {}
    for name, definition in desired.items():
        if name in current and name not in owned:
            if native_agy_server(current[name]) != definition:
                conflict(
                    config, name, value_hash(definition), value_hash(current[name])
                )
            reused[name] = value_hash(current[name])
    keys = sorted(set(owned) | (set(desired) - set(reused)))
    before = {name: current.get(name) for name in keys}
    after = {name: desired.get(name) for name in keys}
    nonce = secrets.token_hex(16)
    backup_path = safe_owned_path(root, ".nott-mcp-backups/" + nonce + ".json")
    backup = {"schema": 1, "before": before, "after": after, "ownership_before": prior}
    # Credential-bearing entry values stay in a private configuration backup,
    # never in the public receipt, registry, stdout or refusal message.
    backup_path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    atomic(backup_path, json.dumps(backup, indent=2, ensure_ascii=False) + "\n")
    backup_path.chmod(0o600)
    receipt.update(
        {
            "transaction": nonce,
            "receipt_path": str(receipt_path),
            "reused_unowned": reused,
            "native_registration": AGY_REGISTRATION,
            "mcp_shadow": "plugin declarations were equivalent at activation; global entries are effective",
        }
    )
    record: AgyMcpRecord = {
        "kind": "agy-mcp",
        "root": str(root),
        "link_before": previous_link,
        "link_after": str(view),
        "file_present": config.exists(),
        "servers_field_present": "mcpServers" in document,
        "before_hashes": {name: value_hash(value) for name, value in before.items()},
        "after_hashes": {name: value_hash(value) for name, value in after.items()},
        "backup": str(backup_path),
        "backup_sha256": package.digest(backup),
    }
    receipt["records"] = [record]
    save_receipt(receipt_path, receipt)
    write_mcp_delta(root, record["before_hashes"], after)
    set_link(link, previous_link, str(view), nonce)
    atomic(registry, json.dumps(ownership_for(receipt), indent=2) + "\n")


def rollback_agy(receipt_path: Path, receipt: ActivationReceipt) -> ActivationReceipt:
    if len(receipt.get("records", [])) != 1:
        raise Refusal("AGY activation has ambiguous records")
    record = receipt["records"][0]
    if record["kind"] != "agy-mcp":
        raise Refusal("AGY activation requires an MCP receipt record")
    root = Path(record["root"])
    if root.is_symlink() or not root.is_absolute() or root.resolve() != root:
        raise Refusal("AGY activation root changed or is not absolute")
    config = safe_owned_path(root, "mcp_config.json")
    registry = safe_owned_path(root, ".nott-mcp-ownership.json")
    link = safe_owned_path(root, "plugins/nott", link=True)
    if not isinstance(receipt.get("transaction"), str) or not re.fullmatch(
        r"[0-9a-f]{32}", receipt["transaction"]
    ):
        raise Refusal("AGY transaction identity is malformed")
    backup_path = safe_owned_path(
        root, ".nott-mcp-backups/" + receipt["transaction"] + ".json"
    )
    if str(backup_path) != record["backup"]:
        raise Refusal("AGY rollback backup is outside its owned configuration path")
    backup = read_json(backup_path)
    if not is_agy_backup(backup) or package.digest(backup) != record["backup_sha256"]:
        raise Refusal("AGY private rollback configuration changed")
    for registrations, hashes in (
        (backup["before"], record["before_hashes"]),
        (backup["after"], record["after_hashes"]),
    ):
        if {name: value_hash(value) for name, value in registrations.items()} != hashes:
            raise Refusal(
                "AGY rollback metadata differs from its private configuration"
            )
    current_owner = read_json(registry)
    after_owner, before_owner = ownership_for(receipt), backup["ownership_before"]
    if receipt.get("state") == "rolled-back":
        if current_owner == after_owner:
            raise Refusal("rolled-back receipt contradicts the active registration")
        return receipt
    recovering = receipt.get("state") in {"prepared", "rolling-back"}
    if current_owner != after_owner and not (
        recovering and current_owner == before_owner
    ):
        raise Refusal("a different NOTT activation owns the current MCP registrations")
    current = mcp_document(config).get("mcpServers", {})
    expected = {}
    for name, after_hash in record["after_hashes"].items():
        actual = value_hash(current.get(name))
        if actual != after_hash and not (
            recovering and actual == record["before_hashes"][name]
        ):
            conflict(config, name, after_hash, actual)
        expected[name] = actual
    current_link = link_value(link)
    if current_link != record["link_after"] and not (
        recovering and current_link == record["link_before"]
    ):
        raise Refusal("AGY registration changed after activation; preserve it")
    # Preflight every owned surface before restoring any of them.
    receipt["state"] = "rolling-back"
    save_receipt(receipt_path, receipt)
    write_mcp_delta(
        root,
        expected,
        backup["before"],
        remove_empty=not record["file_present"],
        remove_servers=not record["servers_field_present"],
    )
    set_link(
        link, current_link, record["link_before"], receipt["transaction"] + "-rollback"
    )
    if read_json(registry) not in (current_owner, before_owner):
        raise Refusal("NOTT ownership changed during rollback")
    if before_owner is None:
        if registry.exists():
            registry.unlink()
    else:
        atomic(registry, json.dumps(before_owner, indent=2) + "\n")
    receipt["state"] = "rolled-back"
    save_receipt(receipt_path, receipt)
    return receipt


def owned_input(path: Path, *, private: bool = False) -> Path:
    if not path.is_absolute() or path.is_symlink() or path.resolve() != path:
        raise Refusal("activation input must use an absolute path without links")
    metadata = path.stat()
    if metadata.st_uid != os.geteuid() or metadata.st_mode & (
        0o077 if private else 0o022
    ):
        raise Refusal("activation input has unsafe ownership or permissions")
    return path


def memory_binding(
    receipt_path: Path, client: str, *, edited_paths: frozenset[Path] = frozenset()
) -> dict[str, str]:
    """Check U1's owned receipt before using its project launcher."""
    owned_input(receipt_path, private=True)
    document = read_json(receipt_path)
    if document is None or document.get("schema") != 1:
        raise Refusal("memory bootstrap receipt is unsupported")
    root = Path(str(document.get("root", "")))
    owned_input(root)
    if receipt_path != root / ".nott/nmemory/bootstrap.json":
        raise Refusal("memory bootstrap receipt is outside its project")
    report = document.get("report")
    if (
        not isinstance(report, dict)
        or report.get("root") != str(root)
        or report.get("client") != client
    ):
        raise Refusal("memory bootstrap project or client differs")
    probe, system1 = report.get("probe"), report.get("system1")
    if (
        not isinstance(probe, dict)
        or probe.get("mcp") is not True
        or not isinstance(system1, dict)
    ):
        raise Refusal("memory bootstrap has no successful consumer probe")
    mode = system1.get("mode")
    if mode not in {"lexical", "local", "native"} or (
        mode != "lexical" and probe.get("system1") is not True
    ):
        raise Refusal("memory bootstrap processing mode is not ready")
    launcher = root / ".nott/nmemory/runtime.py"
    config = root / ".nott/nmemory/memory.toml"
    if report.get("launcher") != str(launcher):
        raise Refusal("memory bootstrap launcher differs from its project")
    python, project = report.get("python"), report.get("project_id")
    if (
        not isinstance(python, str)
        or not Path(python).is_absolute()
        or not isinstance(project, str)
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", project)
    ):
        raise Refusal("memory bootstrap interpreter or project is invalid")
    records = document.get("files")
    if not isinstance(records, list) or not records:
        raise Refusal("memory bootstrap has no owned file hashes")
    allowed = {
        launcher,
        config,
        root / ".nott/nmemory/.gitignore",
        root / ".mcp.json",
        root / ".claude/settings.json",
        root / ".codex/config.toml",
    }
    seen = set()
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("path"), str):
            raise Refusal("memory bootstrap file record is invalid")
        path = Path(record["path"])
        if path not in allowed or path in seen:
            raise Refusal("memory bootstrap file is outside its owned paths")
        owned_input(path)
        if path not in edited_paths and hashlib.sha256(
            path.read_bytes()
        ).hexdigest() != record.get("after"):
            if path not in {root / ".mcp.json", root / ".codex/config.toml"}:
                raise Refusal("memory bootstrap file changed after its probe")
            from nmemory.commands.project import codex_restore, mcp_restore
            from nmemory.config import ConfigError

            try:
                if path == root / ".mcp.json":
                    mcp_restore(record, report, path.read_bytes())
                else:
                    codex_restore(record, report, path.read_bytes())
            except ConfigError:
                raise Refusal("memory bootstrap file changed after its probe") from None
        seen.add(path)
    if not {launcher, config} <= seen:
        raise Refusal("memory bootstrap lacks its launcher or config hash")
    for path in (root / ".nott", root / ".nott/nmemory", Path(python).parent.parent):
        owned_input(path)
    if not Path(python).is_file() or not os.access(python, os.X_OK):
        raise Refusal("memory bootstrap interpreter is unavailable")
    return {
        "root": str(root),
        "project": project,
        "launcher": str(launcher),
        "python": python,
        "config": str(config),
        "mode": str(mode),
    }


def table(raw: str, header: str) -> str | None:
    tomllib.loads(raw)
    matches = list(re.finditer(r"(?m)^\[[^\r\n]+\][ \t]*(?:#[^\n]*)?(?:\n|$)", raw))
    for index, match in enumerate(matches):
        if match.group().strip() == header:
            end = matches[index + 1].start() if index + 1 < len(matches) else len(raw)
            span = raw[match.start() : end]
            return re.sub(
                r"(?:\r?\n[ \t]*(?:#[^\r\n]*)?)+\Z",
                "\n" if span.endswith("\n") else "",
                span,
            )
    return None


def replace_table(raw: str, header: str, before: str | None, after: str | None) -> str:
    """Change one owned table. Preserve all other TOML bytes."""
    if table(raw, header) != before:
        raise Refusal("native configuration table changed after activation")
    if before is not None:
        if after is None and ("\n\n" + before in raw or raw.startswith("\n" + before)):
            result = raw.replace("\n" + before, "", 1)
        else:
            result = raw.replace(before, after or "", 1)
    elif after is not None and not raw.endswith("\n\n") and not after.startswith("\n"):
        result = raw + "\n" + after
    else:
        result = raw + (after or "")
    tomllib.loads(result)
    return result


def native_call(client: str, root: Path, *args: str) -> dict[str, Any]:
    executable = shutil.which(client)
    if executable is None:
        raise Refusal(f"native registration requires the installed {client} CLI")
    environment = {
        "HOME": str(safe_owned_path(root, ".nott-home")),
        "PATH": os.defpath,
        "TMPDIR": str(root / ".nott-tmp"),
        "CODEX_HOME" if client == "codex" else "CLAUDE_CONFIG_DIR": str(root),
        "DISABLE_AUTOUPDATER": "1",
    }
    for name in ("HOME", "TMPDIR"):
        Path(environment[name]).mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        done = subprocess.run(
            [executable, "plugin", *args],
            env=environment,
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        raise OSError(
            "native registration timed out. Inspect its local state"
        ) from None
    if done.returncode:
        raise Refusal(
            f"native {client} operation failed. Check its local plugin registration"
        )
    if client == "claude" and args[0] != "list":
        return {}
    try:
        result = json.loads(done.stdout)
    except ValueError:
        raise Refusal(f"native {client} operation returned no JSON readback") from None
    if client == "claude" and isinstance(result, list):
        return {"installed": result}
    if not isinstance(result, dict):
        raise Refusal(f"native {client} readback is not an object")
    return result


def native_cache(root: Path, client: str, market: str, version: str) -> Path:
    # Claude keeps the manifest version but replaces plus signs in cache paths.
    directory = version.replace("+", "-") if client == "claude" else version
    return safe_owned_path(root, "plugins/cache/" + market + "/nott/" + directory)


def native_readback(client: str, root: Path, market: str, version: str) -> None:
    result = native_call(client, root, "list", "--json")
    if client == "codex":
        items = result.get("installed", [])
        if not isinstance(items, list) or not any(
            isinstance(item, dict)
            and item.get("pluginId") == "nott@" + market
            and item.get("installed") is True
            and item.get("enabled") is True
            and item.get("version") == version
            for item in items
        ):
            raise Refusal("native Codex readback did not confirm the enabled plugin")
    else:
        items = result.get("installed", [])
        if not isinstance(items, list) or not any(
            isinstance(item, dict)
            and item.get("id") == "nott@" + market
            and item.get("enabled") is True
            and item.get("scope") == "user"
            and item.get("version") == version
            and item.get("installPath")
            == str(native_cache(root, client, market, version))
            for item in items
        ):
            raise Refusal("native Claude readback did not confirm the enabled plugin")


def surface(record: NativeRecord, path: Path, header: str, after: str | None) -> None:
    expected = file_identity(path)
    raw = path.read_text() if expected[0] else ""
    before = table(raw, header)
    record["surfaces"].append(
        {
            "path": str(path),
            "header": header,
            "before": before,
            "after": after,
            "file_present": expected[0],
        }
    )


def bind_view(
    view: Path, runtime: Path, memory: dict[str, str], *, client: str = "codex"
) -> None:
    if client not in {"codex", "claude"}:
        raise Refusal("native activation client is unsupported")
    for path in view.rglob("*"):
        if path.is_symlink():
            target = path.resolve(strict=True)
            if not target.is_relative_to(view) or not target.is_file():
                raise Refusal("native activation link escapes its view")
            content, mode = path.read_bytes(), path.stat().st_mode
            path.unlink()
            path.write_bytes(content)
            path.chmod(stat.S_IMODE(mode))
    config = json.loads((view / ".mcp.json").read_text())
    for name, server in config["mcpServers"].items():
        if name not in {"nmemory", "nspawn", "nbrowser"}:
            raise Refusal("public activation has an unsupported MCP runtime")
        server["command"] = str(runtime / "bin" / name)
        if name == "nmemory":
            server["command"] = memory["python"]
            server["args"] = [
                "-I",
                memory["launcher"],
                "mcp",
                "serve",
                "--project",
                memory["project"],
            ]
    package.validate_mcp(config)
    for name in (".mcp.json", "mcp_config.json"):
        package.write_json(view / name, config)
    environment = {
        "PATH": str(runtime / "bin") + os.pathsep + os.defpath,
        "NOTT_NMEMORY_BIN": memory["launcher"],
        "NOTT_NMEMORY_PYTHON": memory["python"],
        "NOTT_NMEMORY_PROJECT": memory["project"],
    }
    hooks_path = view / "hooks/hooks.json"
    hooks = json.loads(hooks_path.read_text())
    prefix = (
        "env "
        + shlex.join([name + "=" + value for name, value in environment.items()])
        + " "
    )
    bootstrap_owned = (
        ("nmemory-session.sh", "nmemory-recall.py", "nmemory-capture-gate.py")
        if client == "claude"
        else ()
    )
    for event, groups in list(hooks["hooks"].items()):
        kept_groups = []
        for group in groups:
            kept_hooks = []
            for hook in group["hooks"]:
                if any(name in hook["command"] for name in bootstrap_owned):
                    continue
                hook["command"] = prefix + hook["command"]
                kept_hooks.append(hook)
            if kept_hooks:
                group["hooks"] = kept_hooks
                kept_groups.append(group)
        if kept_groups:
            hooks["hooks"][event] = kept_groups
        else:
            del hooks["hooks"][event]
    package.write_json(hooks_path, hooks)


def prepare_native_view(
    source: Path,
    destination: Path,
    runtime: Path,
    memory: dict[str, str],
    market: str,
    version: str,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".prepare-", dir=destination.parent
    ) as scratch:
        prepared = Path(scratch) / "marketplace"
        shutil.copytree(source, prepared / "plugin", symlinks=True)
        bind_view(prepared / "plugin", runtime, memory, client=source.name)
        package.write_json(
            prepared / ".claude-plugin/marketplace.json",
            {
                "name": market,
                "owner": {"name": "NOTT"},
                "plugins": [{"name": "nott", "source": "./plugin", "version": version}],
            },
        )
        prepared.rename(destination)


def native_value(item: dict[str, Any], client: str) -> Any:
    path = Path(item["path"])
    if client == "codex":
        return table(path.read_text() if path.exists() else "", item["header"])
    document: Any = read_json(path) or {}
    container = item["header"]
    if container:
        document = document.get(container, {})
    if not isinstance(document, dict):
        raise Refusal("native Claude registration container must be an object")
    return document.get(item["key"])


def claude_surfaces(root: Path, market: str) -> list[tuple[Path, str, str]]:
    ident = "nott@" + market
    return [
        (root / "settings.json", "enabledPlugins", ident),
        (root / "settings.json", "extraKnownMarketplaces", market),
        (root / "plugins/installed_plugins.json", "plugins", ident),
        (root / "plugins/known_marketplaces.json", "", market),
    ]


def public_claude_install(
    bundle: Path,
    root: Path,
    receipt_path: Path,
    runtime: Path,
    bootstrap: Path,
    memory: dict[str, str],
    manifest: dict[str, Any],
) -> ActivationReceipt:
    """Use the full native plugin. Do not change nSPAWN's skills-only admission."""
    instructions = safe_owned_path(root, "CLAUDE.md")
    text = instructions.read_text() if instructions.exists() else ""
    if block(text) is not None or UNMARKED_LAW.search(text):
        raise Refusal("restore the previous NOTT instruction block before activation")
    settings = read_json(safe_owned_path(root, "settings.json")) or {}
    enabled = settings.get("enabledPlugins", {})
    if not isinstance(enabled, dict):
        raise Refusal("native Claude enabledPlugins must be an object")
    if any(
        name.startswith("nott@") and value is True for name, value in enabled.items()
    ):
        raise Refusal("another native NOTT plugin is enabled")
    identity = package.digest(
        {"bundle": manifest["digest"], "memory": memory, "runtime": str(runtime)}
    )
    market = "nott-public-" + identity[:16]
    destination = safe_owned_path(root, ".nott-plugin/" + identity)
    if destination.exists():
        raise Refusal("restore the existing activation directory before installation")
    record: NativeRecord = {
        "kind": "native",
        "client": "claude",
        "root": str(root),
        "version": manifest["version"],
        "bootstrap_hooks": value_hash(settings.get("hooks")),
        "runtime": str(runtime),
        "bootstrap": str(bootstrap),
        "market": market,
        "view": str(destination / "plugin"),
        "view_files": {},
        "surfaces": [],
    }
    for path, header, key in claude_surfaces(root, market):
        safe_owned_path(root, str(path.relative_to(root)))
        document = read_json(path) or {}
        item = {
            "path": str(path),
            "header": header,
            "key": key,
            "before": None,
            "after": None,
            "file_present": path.exists(),
            "field_present": header in document,
        }
        container = document.get(header, {}) if header else document
        if not isinstance(container, dict) or key in container:
            raise Refusal(
                "the selected native Claude registration already exists or is invalid"
            )
        record["surfaces"].append(item)
    if receipt_path in {Path(item["path"]) for item in record["surfaces"]} | {
        bootstrap
    } or receipt_path.is_relative_to(destination):
        raise Refusal("activation receipt collides with managed configuration")
    receipt: ActivationReceipt = {
        "schema": 1,
        "client": "claude",
        "bundle": str(bundle.resolve()),
        "digest": manifest["digest"],
        "state": "prepared",
        "native_registration": "required",
        "runtime_observed": False,
        "memory": memory,
        "records": [record],
        "readiness": {
            "native_login": "unverified",
            "native_hooks": "trust_required",
            "mcp_catalog": "unverified",
            "browser": "required_if_used",
        },
    }
    save_receipt(receipt_path, receipt)
    try:
        prepare_native_view(
            bundle.resolve() / "clients/claude",
            destination,
            runtime,
            memory,
            market,
            manifest["version"],
        )
        record["view_files"] = package.inventory(destination / "plugin")
        save_receipt(receipt_path, receipt)
        native_call("claude", root, "marketplace", "add", str(destination))
        native_call("claude", root, "install", "nott@" + market, "--scope", "user")
        native_readback("claude", root, market, manifest["version"])
        cache = native_cache(root, "claude", market, manifest["version"])
        if package.inventory(cache) != record["view_files"]:
            raise Refusal("native plugin cache differs from the bound activation view")
        receipt["state"] = "configured"
        receipt["native_registration"] = "configured"
    finally:
        for item in record["surfaces"]:
            item["after"] = native_value(item, "claude")
        save_receipt(receipt_path, receipt)
    return receipt


def public_install(
    bundle: Path,
    client: str,
    root: Path,
    receipt_path: Path,
    runtime_root: Path,
    bootstrap_receipt: Path,
) -> ActivationReceipt:
    manifest = package.admit_current(bundle)
    root, runtime = root.absolute(), runtime_root.absolute()
    if (
        not receipt_path.is_absolute()
        or receipt_path.parent.resolve() != receipt_path.parent
    ):
        raise Refusal(
            "activation receipt parent must use an absolute path without links"
        )
    if client not in {"codex", "claude"}:
        raise Refusal(
            f"public {client} activation requires a proved native full-plugin registration path"
        )
    if receipt_path.exists():
        prior = read_json(receipt_path)
        if (
            not is_activation_receipt(prior)
            or len(prior["records"]) != 1
            or prior["records"][0]["kind"] != "native"
        ):
            raise Refusal("public activation receipt belongs to another operation")
        previous = prior["records"][0]
        owned_input(receipt_path, private=True)
        memory = validate_native(previous)
        if (
            prior.get("digest") != manifest["digest"]
            or prior.get("client") != client
            or previous["root"] != str(root)
            or previous["runtime"] != str(runtime)
            or previous["bootstrap"] != str(bootstrap_receipt)
            or prior.get("memory") != memory
            or prior.get("state") not in {"configured", "rolled-back"}
        ):
            raise Refusal(
                "public activation differs. Restore its receipt before changing inputs"
            )
        restored = prior.get("state") == "rolled-back"
        for item in previous["surfaces"]:
            if native_value(item, client) != item["before" if restored else "after"]:
                raise Refusal("public activation configuration changed")
        view = Path(previous["view"])
        cache = native_cache(root, client, previous["market"], manifest["version"])
        if restored:
            if view.exists() or cache.exists():
                raise Refusal("native rollback left an activation view or cache")
            listed = native_call(client, root, "list", "--json").get("installed", [])
            key = "pluginId" if client == "codex" else "id"
            if any(item.get(key) == "nott@" + previous["market"] for item in listed):
                raise Refusal("native rollback still lists the plugin")
        else:
            native_readback(client, root, previous["market"], manifest["version"])
            if package.inventory(view) != previous["view_files"]:
                raise Refusal("public activation view changed")
            if package.inventory(cache) != previous["view_files"]:
                raise Refusal("native plugin cache changed")
            return prior
    memory = memory_binding(bootstrap_receipt, client)
    owned_input(runtime)
    if Path(memory["python"]).parent.parent != runtime:
        raise Refusal("memory bootstrap interpreter differs from the selected runtime")
    for name in ("nmemory", "nspawn", "nbrowser"):
        path = runtime / "bin" / name
        owned_input(path)
        if not path.is_file() or not os.access(path, os.X_OK):
            raise Refusal(f"public runtime executable is unavailable: {name}")
    if shutil.which(client) is None:
        raise Refusal(f"native registration requires the installed {client} CLI")
    if root.exists():
        owned_input(root)
    else:
        root.mkdir(parents=True, mode=0o700)
        owned_input(root)
    if client == "claude":
        return public_claude_install(
            bundle, root, receipt_path, runtime, bootstrap_receipt, memory, manifest
        )
    config = safe_owned_path(root, "config.toml")
    _, instructions = read_instruction(config, client)
    if block(instructions) is not None or UNMARKED_LAW.search(instructions):
        raise Refusal(
            "public activation requires restoration of the previous NOTT instruction block"
        )
    raw = config.read_text() if config.exists() else ""
    data = tomllib.loads(raw)
    if any(
        key.startswith("nott@") and value.get("enabled") is True
        for key, value in data.get("plugins", {}).items()
    ):
        raise Refusal("another native NOTT plugin is enabled")
    identity = package.digest(
        {"bundle": manifest["digest"], "memory": memory, "runtime": str(runtime)}
    )
    market = "nott-public-" + identity[:16]
    destination = safe_owned_path(root, ".nott-plugin/" + identity)
    if destination.exists():
        raise Refusal(
            "public activation directory already exists. Restore its receipt first"
        )
    source_view = bundle.resolve() / "clients" / client
    record: NativeRecord = {
        "kind": "native",
        "root": str(root),
        "runtime": str(runtime),
        "bootstrap": str(bootstrap_receipt),
        "market": market,
        "view": str(destination / "plugin"),
        "view_files": {},
        "surfaces": [],
        "separator": "",
    }
    receipt: ActivationReceipt = {
        "schema": 1,
        "client": client,
        "bundle": str(bundle.resolve()),
        "digest": manifest["digest"],
        "state": "prepared",
        "native_registration": "required",
        "runtime_observed": False,
        "memory": memory,
        "readiness": {
            "native_login": "unverified",
            "native_hooks": "trust_required",
            "mcp_catalog": "unverified",
            "browser": "required_if_used",
        },
        "records": [record],
    }
    project_config = Path(memory["root"]) / ".codex/config.toml"
    surface(record, project_config, "[mcp_servers.nmemory]", None)
    for header in (f"[marketplaces.{market}]", f'[plugins."nott@{market}"]'):
        surface(record, config, header, None)
        if record["surfaces"][-1]["before"] is not None:
            raise Refusal("the selected native registration already exists")
    if receipt_path in {
        config,
        project_config,
        bootstrap_receipt,
    } or receipt_path.is_relative_to(destination):
        raise Refusal("activation receipt collides with managed configuration")
    save_receipt(receipt_path, receipt)
    native_base = raw
    try:
        prepare_native_view(
            source_view, destination, runtime, memory, market, manifest["version"]
        )
        record["view_files"] = package.inventory(destination / "plugin")
        save_receipt(receipt_path, receipt)
        item = record["surfaces"][0]
        path = Path(item["path"])
        if item["before"] is not None:
            atomic(
                path,
                replace_table(path.read_text(), item["header"], item["before"], None),
                expected=file_identity(path),
            )
        native_base = config.read_text() if config.exists() else ""
        native_call(client, root, "marketplace", "add", str(destination), "--json")
        native_call(client, root, "add", "nott@" + market, "--json")
        native_readback(client, root, market, manifest["version"])
        cache = native_cache(root, client, market, manifest["version"])
        if package.inventory(cache) != record["view_files"]:
            raise Refusal("native plugin cache differs from the bound activation view")
        receipt["state"] = "configured"
        receipt["native_registration"] = "configured"
    finally:
        # A native call can write before failure. Retain its actual state for rollback.
        for item in record["surfaces"][1:]:
            item["after"] = table(
                config.read_text() if config.exists() else "", item["header"]
            )
        remaining = config.read_text() if config.exists() else ""
        for item in reversed(record["surfaces"][1:]):
            remaining = replace_table(
                remaining, item["header"], item["after"], item["before"]
            )
        if (
            remaining.startswith(native_base)
            and not remaining[len(native_base) :].strip()
        ):
            record["separator"] = remaining[len(native_base) :]
        save_receipt(receipt_path, receipt)
    return receipt


def validate_native(record: NativeRecord) -> dict[str, str]:
    root = owned_input(Path(record["root"]))
    client = record.get("client", "codex")
    if client not in {"codex", "claude"}:
        raise Refusal("native activation client is unsupported")
    if record.get("separator", "").strip():
        raise Refusal("native activation separator is invalid")
    bootstrap = owned_input(Path(record["bootstrap"]), private=True)
    document = read_json(bootstrap)
    if document is None or not isinstance(document.get("root"), str):
        raise Refusal("native activation has no owned bootstrap project")
    project = owned_input(Path(str(document["root"])))
    if bootstrap != project / ".nott/nmemory/bootstrap.json":
        raise Refusal("native activation bootstrap is outside its project")
    memory = memory_binding(
        bootstrap,
        client,
        edited_paths=frozenset({project / ".codex/config.toml"})
        if client == "codex"
        else frozenset({root / "settings.json"}),
    )
    if Path(memory["python"]).parent.parent != Path(record["runtime"]):
        raise Refusal("native activation runtime differs from its bootstrap")
    if re.fullmatch(r"nott-public-[0-9a-f]{16}", record["market"]) is None:
        raise Refusal("native activation marketplace is invalid")
    view = Path(record["view"])
    if (
        view.name != "plugin"
        or view.parent.parent != root / ".nott-plugin"
        or re.fullmatch(r"[0-9a-f]{64}", view.parent.name) is None
    ):
        raise Refusal("native activation view is outside its owned directory")
    safe_owned_path(root, str(view.relative_to(root)))
    expected = [
        (project / ".codex/config.toml", "[mcp_servers.nmemory]"),
        (root / "config.toml", f"[marketplaces.{record['market']}]"),
        (root / "config.toml", f'[plugins."nott@{record["market"]}"]'),
    ]
    if client == "claude":
        settings = read_json(safe_owned_path(root, "settings.json")) or {}
        if value_hash(settings.get("hooks")) != record.get("bootstrap_hooks"):
            raise Refusal("native Claude bootstrap hooks changed after activation")
        expected = [
            (path, header)
            for path, header, _ in claude_surfaces(root, record["market"])
        ]
        version = record.get("version", "")
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+\+sha\.[0-9a-f]{64}", version):
            raise Refusal("native Claude version is invalid")
        cache = native_cache(root, client, record["market"], version)
        if cache.exists() and package.inventory(cache) != record["view_files"]:
            raise Refusal("native Claude cache changed after activation")
    if len(record["surfaces"]) != len(expected):
        raise Refusal("native activation has an invalid configuration scope")
    for item, (path, header) in zip(record["surfaces"], expected, strict=True):
        if (
            not isinstance(item, dict)
            or item.get("path") != str(path)
            or item.get("header") != header
            or type(item.get("file_present")) is not bool
        ):
            raise Refusal("native activation record is outside its owned configuration")
        safe_owned_path(
            project if path.is_relative_to(project) else root,
            str(path.relative_to(project if path.is_relative_to(project) else root)),
        )
        if client == "claude":
            index = record["surfaces"].index(item)
            if (
                item.get("key") != claude_surfaces(root, record["market"])[index][2]
                or type(item.get("field_present")) is not bool
            ):
                raise Refusal("native Claude record is outside its owned configuration")
            if item.get("before") is not None:
                raise Refusal(
                    "native Claude registration was not absent before activation"
                )
            after = item.get("after")
            if index == 0 and after is not None and type(after) is not bool:
                raise Refusal("native Claude enable flag is invalid")
            if (
                index == 2
                and after is not None
                and (
                    not isinstance(after, list)
                    or not after
                    or any(
                        not isinstance(entry, dict)
                        or entry.get("scope") != "user"
                        or entry.get("version") != record["version"]
                        or entry.get("installPath") != str(cache)
                        for entry in after
                    )
                )
            ):
                raise Refusal("native Claude cache record is outside its owned path")
            if (
                index == 3
                and after is not None
                and (
                    not isinstance(after, dict)
                    or after.get("installLocation")
                    not in {
                        str(view.parent),
                        str(root / "plugins/marketplaces" / record["market"]),
                    }
                )
            ):
                raise Refusal("native Claude marketplace is outside its owned path")
            continue
        for field in ("before", "after"):
            value = item.get(field)
            if value is not None and (
                not isinstance(value, str) or table(value, header) != value
            ):
                raise Refusal("native activation table is invalid")
    if view.exists():
        owned_input(view)
        if package.inventory(view) != record["view_files"]:
            raise Refusal("native activation view changed")
        entries = {item.name for item in view.parent.iterdir()}
        if entries != {"plugin", ".claude-plugin"}:
            raise Refusal("native activation directory contains unrelated files")
        marketplace = read_json(view.parent / ".claude-plugin/marketplace.json")
        if marketplace is None or marketplace.get("name") != record["market"]:
            raise Refusal("native activation marketplace changed")
    return memory


def rollback_native(
    receipt_path: Path, receipt: ActivationReceipt, record: NativeRecord
) -> ActivationReceipt:
    validate_native(record)
    if receipt.get("state") == "rolled-back":
        return receipt
    if record.get("client") == "claude":
        return rollback_claude_native(receipt_path, receipt, record)
    root = Path(record["root"])
    owned_input(root)
    for item in record["surfaces"]:
        path = Path(item["path"])
        raw = path.read_text() if path.exists() else ""
        current = table(raw, item["header"])
        if current != item["after"] and not (
            receipt.get("state") in {"prepared", "rolling-back"}
            and current == item["before"]
        ):
            raise Refusal(
                "native configuration changed. Preserve the current configuration"
            )
    view = Path(record["view"])
    if view.exists() and package.inventory(view) != record["view_files"]:
        raise Refusal("native activation view changed. Preserve it")
    if shutil.which(receipt["client"]) is None:
        raise Refusal("native rollback requires its installed client CLI")
    receipt["state"] = "rolling-back"
    save_receipt(receipt_path, receipt)
    for item in reversed(record["surfaces"]):
        path = Path(item["path"])
        expected = file_identity(path)
        raw = path.read_text() if expected[0] else ""
        current = table(raw, item["header"])
        if current == item["before"]:
            continue
        updated = replace_table(raw, item["header"], item["after"], item["before"])
        if (
            item is record["surfaces"][1]
            and record.get("separator")
            and item["after"] is not None
        ):
            separator = record["separator"]
            owned = separator + item["after"]
            if owned not in raw:
                raise Refusal("native activation separator changed")
            updated = raw.replace(owned, item["before"] or "", 1)
        if not updated.strip() and not item["file_present"]:
            path.unlink(missing_ok=True)
        else:
            atomic(path, updated, expected=expected)
    # Native remove also removes the owned cached copy.
    cache = root / "plugins/cache" / record["market"] / "nott"
    if cache.exists():
        native_call(
            receipt["client"], root, "remove", "nott@" + record["market"], "--json"
        )
    remaining = native_call(receipt["client"], root, "list", "--json")
    if any(
        item.get("pluginId") == "nott@" + record["market"]
        for item in remaining.get("installed", [])
    ):
        raise Refusal("native rollback readback still lists the plugin")
    if view.exists():
        shutil.rmtree(view.parent)
    receipt["state"] = "rolled-back"
    receipt["native_registration"] = "removed"
    save_receipt(receipt_path, receipt)
    return receipt


def rollback_claude_native(
    receipt_path: Path, receipt: ActivationReceipt, record: NativeRecord
) -> ActivationReceipt:
    """Remove only this native registration. Keep concurrent foreign settings."""
    root = Path(record["root"])
    for item in record["surfaces"]:
        current = native_value(item, "claude")
        if current != item["after"] and not (
            receipt.get("state") == "rolling-back" and current is None
        ):
            raise Refusal("native Claude configuration changed after activation")
    if shutil.which("claude") is None:
        raise Refusal("native rollback requires its installed Claude CLI")
    receipt["state"] = "rolling-back"
    save_receipt(receipt_path, receipt)
    registry = record["surfaces"][2]
    if native_value(registry, "claude") is not None:
        native_call(
            "claude", root, "uninstall", "nott@" + record["market"], "--scope", "user"
        )
    if native_value(record["surfaces"][3], "claude") is not None:
        native_call("claude", root, "marketplace", "remove", record["market"])
    remaining = native_call("claude", root, "list", "--json")
    if any(
        item.get("id") == "nott@" + record["market"]
        for item in remaining.get("installed", [])
    ):
        raise Refusal("native rollback readback still lists the plugin")
    cache = native_cache(root, "claude", record["market"], record["version"])
    if cache.exists():
        files = package.inventory(cache)
        if ".orphaned_at" in files:
            marker = owned_input(cache / ".orphaned_at")
            if re.fullmatch(r"[0-9]+", marker.read_text()) is None:
                raise Refusal("native Claude cache marker is invalid")
            del files[".orphaned_at"]
        if files != record["view_files"]:
            raise Refusal("native Claude cache changed during rollback")
        shutil.rmtree(cache)
    for item in record["surfaces"]:
        path = Path(item["path"])
        snapshot = file_identity(path)
        document = read_json(path)
        if document is None:
            continue
        container = (
            document.setdefault(item["header"], {}) if item["header"] else document
        )
        if not isinstance(container, dict):
            raise Refusal("native Claude registration container must be an object")
        if container.get(item["key"]) not in (None, item["after"]):
            raise Refusal("native Claude configuration changed during rollback")
        container.pop(item["key"], None)
        if item["header"] and not container and not item["field_present"]:
            document.pop(item["header"], None)
        empty = not document or document == {"version": 2}
        if empty and not item["file_present"]:
            if file_identity(path) != snapshot:
                raise Refusal("native Claude configuration changed before removal")
            path.unlink()
        else:
            atomic(
                path,
                json.dumps(document, indent=2, ensure_ascii=False) + "\n",
                expected=snapshot,
            )
    view = Path(record["view"])
    if view.exists():
        shutil.rmtree(view.parent)
    receipt["state"] = "rolled-back"
    receipt["native_registration"] = "removed"
    save_receipt(receipt_path, receipt)
    return receipt


def install(
    bundle: Path,
    client: str,
    root: Path,
    receipt_path: Path,
    previous_law: Path | None = None,
    runtime_root: Path | None = None,
    bootstrap_receipt: Path | None = None,
) -> ActivationReceipt:
    if (bundle / ".nott-public.json").exists() and (
        runtime_root is None or bootstrap_receipt is None
    ):
        raise Refusal(
            "public activation requires --runtime-root and --memory-bootstrap"
        )
    if runtime_root is not None or bootstrap_receipt is not None:
        if previous_law is not None:
            raise Refusal(
                "public activation cannot use --previous-law. Restore the previous installation first"
            )
        if runtime_root is None or bootstrap_receipt is None:
            raise Refusal(
                "public activation requires runtime-root and memory-bootstrap"
            )
        if root.exists():
            owned_input(root)
        owned_input(bootstrap_receipt, private=True)
        with agy_lock(root), agy_lock(bootstrap_receipt.parent, "bootstrap.lock"):
            return public_install(
                bundle, client, root, receipt_path, runtime_root, bootstrap_receipt
            )
    manifest = package.admit_current(bundle)
    if root.is_symlink():
        raise Refusal(f"linked config root requires explicit migration: {root}")
    root = root.resolve()
    receipt_path = receipt_path.absolute()
    if receipt_path.exists():
        raise Refusal(
            "activation receipt already exists; use a new receipt or rollback"
        )
    view = bundle.resolve() / "clients" / client
    law = (view / "NOTT.md").read_text()
    owned = (
        BEGIN + "\nBundle: " + manifest["digest"] + "\n\n" + law.rstrip() + "\n" + END
    )
    receipt: ActivationReceipt = {
        "schema": 1,
        "client": client,
        "bundle": str(bundle.resolve()),
        "digest": manifest["digest"],
        "view": str(view),
        "state": "prepared",
        "runtime_observed": False,
        "native_registration": AGY_REGISTRATION if client == "agy" else "required",
        "records": [],
    }
    if client == "agy":
        with agy_lock(root):
            install_agy(view, root, receipt_path, receipt)
            receipt["state"] = "configured"
            save_receipt(receipt_path, receipt)
        return receipt
    else:
        path = root / ("config.toml" if client == "codex" else "CLAUDE.md")
        expected = file_identity(path)
        raw, text = read_instruction(path, client)
        previous = block(text)
        if previous_law is not None:
            legacy = previous_law.read_text()
            # An idempotent caller passes whatever law it found deployed. After
            # the first install that IS our own marked block, and treating it as
            # a failed migration broke every second run: measured 2026-09-14 on
            # `./install.sh`. A redundant previous law is not a migration; only
            # bytes that disagree with the deployed block are an error. The three
            # refusals below were one message, and reading it taught the operator
            # nothing about which condition had fired.
            if previous is not None:
                if legacy.strip() != previous.strip():
                    raise Refusal(
                        "the supplied previous law differs from the NOTT law already "
                        "installed; pass the deployed block or omit --previous-law"
                    )
                previous_law = None
            elif not UNMARKED_LAW.match(legacy):
                raise Refusal(
                    "--previous-law must BEGIN with a NOTT law marker "
                    '(`# **NOTT** System Prompt` or `<NOTT version="`); '
                    "a fragment of one is not a migration source"
                )
            elif text.count(legacy) != 1:
                raise Refusal(
                    f"the supplied previous law appears {text.count(legacy)} times "
                    "in the deployed instruction; migration needs exactly one"
                )
        if previous_law is not None:
            legacy = previous_law.read_text()
            remainder = text.replace(legacy, "", 1)
            if UNMARKED_LAW.search(remainder):
                raise Refusal("another unmarked NOTT law remains outside the migration")
            previous = legacy
            updated = text.replace(legacy, owned, 1)
        else:
            if previous is None and UNMARKED_LAW.search(text):
                raise Refusal(
                    "unmarked NOTT law requires --previous-law with its exact approved bytes"
                )
            updated = replace_block(text, previous, owned)
        receipt["records"].append(
            {
                "kind": "instruction",
                "path": str(path),
                "before": previous,
                "after": owned,
                "separator": "\n\n" if text and previous is None else "",
                "field_present": client != "codex"
                or "developer_instructions" in tomllib.loads(raw),
                "file_present": expected[0],
            }
        )
        if client == "claude":
            settings = safe_owned_path(root, "settings.json")
            if receipt_path.resolve() in {path, settings}:
                raise Refusal("activation receipt collides with managed configuration")
            document, settings_identity = claude_settings_snapshot(settings)
            env_record: ClaudeEnvRecord = {
                "kind": "claude-env",
                "path": str(settings),
                "before": claude_env_values(document),
                "after": CLAUDE_ENV,
                "env_present": "env" in document,
                "file_present": settings_identity[0],
            }
            receipt["records"].append(env_record)
        save_receipt(receipt_path, receipt)
        atomic(
            path,
            encode_instruction(raw, updated) if client == "codex" else updated,
            expected=expected,
        )
        if client == "claude":
            write_claude_env(env_record)
    receipt["state"] = "configured"
    save_receipt(receipt_path, receipt)
    return receipt


def check_receipt_records(value: object) -> None:
    if (
        not isinstance(value, list)
        or not value
        or any(
            not isinstance(record, dict)
            or record.get("kind")
            not in ("instruction", "claude-env", "link", "agy-mcp", "native")
            for record in value
        )
    ):
        raise Refusal("activation receipt records must contain known record objects")
    schemas: dict[str, dict[str, tuple[type, ...]]] = {
        "native": {
            "root": (str,),
            "runtime": (str,),
            "bootstrap": (str,),
            "market": (str,),
            "view": (str,),
            "view_files": (dict,),
            "surfaces": (list,),
        },
        "instruction": {
            "path": (str,),
            "before": (str, type(None)),
            "after": (str,),
            "separator": (str,),
            "field_present": (bool,),
            "file_present": (bool,),
        },
        "claude-env": {
            "path": (str,),
            "before": (dict,),
            "after": (dict,),
            "env_present": (bool,),
            "file_present": (bool,),
        },
        "link": {"path": (str,), "before": (str, type(None)), "after": (str,)},
        "agy-mcp": {
            "root": (str,),
            "link_before": (str, type(None)),
            "link_after": (str,),
            "file_present": (bool,),
            "servers_field_present": (bool,),
            "before_hashes": (dict,),
            "after_hashes": (dict,),
            "backup": (str,),
            "backup_sha256": (str,),
        },
    }
    for record in value:
        if record["kind"] == "native":
            for field, types in {
                "separator": (str,),
                "client": (str,),
                "version": (str,),
                "bootstrap_hooks": (str, type(None)),
            }.items():
                if field in record and type(record[field]) not in types:
                    raise Refusal(f"native activation has an invalid {field} field")
        fields = schemas[record["kind"]]
        for field, types in fields.items():
            if field not in record or type(record[field]) not in types:
                raise Refusal(f"activation receipt records have invalid field: {field}")
        if record["kind"] == "agy-mcp":
            for field in ("before_hashes", "after_hashes"):
                if any(
                    not isinstance(name, str)
                    or (
                        digest is not None
                        and (
                            not isinstance(digest, str)
                            or re.fullmatch(r"[0-9a-f]{64}", digest) is None
                        )
                    )
                    for name, digest in record[field].items()
                ):
                    raise Refusal(f"activation receipt records have invalid {field}")
        if "restored" in record and type(record["restored"]) is not bool:
            raise Refusal("activation receipt records have invalid restored flag")
        if "restore_identity" in record:
            identity = record["restore_identity"]
            if (
                not isinstance(identity, list)
                or len(identity) != 2
                or type(identity[0]) is not bool
                or (
                    identity[0]
                    and (
                        not isinstance(identity[1], str)
                        or re.fullmatch(r"[0-9a-f]{64}", identity[1]) is None
                    )
                )
                or (not identity[0] and identity[1] is not None)
            ):
                raise Refusal(
                    "activation receipt records have invalid restore_identity"
                )


def rollback(receipt_path: Path) -> ActivationReceipt:
    receipt = read_json(receipt_path)
    if not is_activation_receipt(receipt):
        raise Refusal("unknown activation receipt")
    # Admission requires an AGY MCP receipt to contain exactly one record.
    first_record = receipt["records"][0]
    if first_record["kind"] == "native":
        owned_input(receipt_path, private=True)
        validate_native(first_record)
        if len(receipt["records"]) != 1:
            raise Refusal("native activation requires one transaction record")
        with (
            agy_lock(Path(first_record["root"])),
            agy_lock(Path(first_record["bootstrap"]).parent, "bootstrap.lock"),
        ):
            return rollback_native(receipt_path, receipt, first_record)
    if first_record["kind"] == "agy-mcp":
        root = Path(first_record["root"])
        if not root.is_absolute() or root.resolve() != root:
            raise Refusal("AGY rollback root is not canonical")
        with agy_lock(root):
            latest = read_json(receipt_path)
            if not is_activation_receipt(latest) or receipt_identity(
                latest
            ) != receipt_identity(receipt):
                raise Refusal(
                    "AGY activation receipt changed while acquiring ownership"
                )
            return rollback_agy(receipt_path, latest)
    if receipt.get("state") == "rolled-back":
        return receipt
    if receipt["client"] == "claude":
        # A newer law also owns the active defaults. Refuse an older rollback
        # before restoring settings, including when the settings values coincide.
        for record in receipt["records"]:
            if record["kind"] == "instruction":
                path = Path(record["path"])
                instruction_identity = file_identity(path)
                if record.get("restore_identity") == list(instruction_identity):
                    continue
                _, text = read_instruction(path, "claude")
                replace_block(text, record["after"], record["before"])
                if file_identity(path) != instruction_identity:
                    raise Refusal(
                        f"shared configuration changed before rollback: {path}"
                    )
    # Refuse a same-key edit before rolling back any surface. Foreign settings
    # are reread and retained at the atomic write boundary.
    for record in receipt["records"]:
        if record["kind"] == "claude-env":
            document, _ = claude_settings_snapshot(Path(record["path"]))
            expected_env = (
                record["before"] if record.get("restored") else record["after"]
            )
            if (
                receipt.get("state") in {"prepared", "rolling-back"}
                and claude_env_values(document) == record["before"]
            ):
                expected_env = record["before"]
            check_claude_env(Path(record["path"]), document, expected_env)
    if receipt["client"] == "claude":
        receipt["state"] = "rolling-back"
        save_receipt(receipt_path, receipt)
    for record in reversed(receipt["records"]):
        if record["kind"] == "agy-mcp" or record["kind"] == "native":
            raise Refusal("unknown receipt record")
        path = Path(record["path"])
        if record["kind"] == "claude-env":
            write_claude_env(record, rollback=True, recovering=True)
            record["restored"] = True
            save_receipt(receipt_path, receipt)
        elif record["kind"] == "link":
            if not path.is_symlink() or os.readlink(path) != record["after"]:
                raise Refusal("AGY registration changed after activation; preserve it")
            if record["before"] is None:
                path.unlink()
            else:
                temporary = path.with_name(".nott-rollback")
                temporary.symlink_to(record["before"])
                temporary.replace(path)
        elif record["kind"] == "instruction":
            expected = file_identity(path)
            if record.get("restore_identity") == list(expected):
                continue
            raw, text = read_instruction(path, receipt["client"])
            updated = replace_block(text, record["after"], record["before"])
            if record["before"] is None and record["separator"]:
                updated = text.replace(record["separator"] + record["after"], "", 1)
            if receipt["client"] == "codex":
                updated = encode_instruction(
                    raw,
                    None if not updated and not record["field_present"] else updated,
                    remove_inserted_line=not record["field_present"],
                )
            remove = not updated and not record["file_present"]
            record["restore_identity"] = (
                [False, None]
                if remove
                else [True, hashlib.sha256(updated.encode()).hexdigest()]
            )
            save_receipt(receipt_path, receipt)
            if remove:
                if file_identity(path) != expected:
                    raise Refusal(
                        f"shared configuration changed before removal: {path}"
                    )
                path.unlink()
            else:
                atomic(path, updated, expected=expected)
        else:
            raise Refusal("unknown receipt record")
    receipt["state"] = "rolled-back"
    save_receipt(receipt_path, receipt)
    return receipt


def main(argv: list[str] | None = None) -> int:
    """The installer's verbs of `plugin/scripts/plugin.py`: install, rollback."""
    parser = argparse.ArgumentParser(prog="plugin.py", description=__doc__)
    verbs = parser.add_subparsers(dest="verb")
    install_verb = verbs.add_parser("install", help="activate a bundle for one client")
    install_verb.add_argument("--bundle", type=Path)
    install_verb.add_argument("--client", choices=package.CLIENTS)
    install_verb.add_argument("--config-root", type=Path)
    install_verb.add_argument("--receipt", type=Path)
    install_verb.add_argument("--previous-law", type=Path)
    install_verb.add_argument("--runtime-root", type=Path)
    install_verb.add_argument("--memory-bootstrap", dest="bootstrap_receipt", type=Path)
    verbs.add_parser("rollback", help="undo one activation").add_argument(
        "receipt", type=Path
    )
    try:
        args = parser.parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 2
    try:
        if args.verb == "rollback":
            result = rollback(args.receipt.absolute())
        elif args.verb == "install":
            if not all((args.bundle, args.client, args.config_root, args.receipt)):
                raise Refusal(
                    "activation requires bundle, client, config-root and receipt"
                )
            result = install(
                args.bundle,
                args.client,
                args.config_root.absolute(),
                args.receipt.absolute(),
                args.previous_law,
                args.runtime_root,
                args.bootstrap_receipt,
            )
        else:
            parser.print_usage(sys.stderr)
            return 2
        print(
            json.dumps(
                {key: value for key, value in result.items() if key != "records"}
            )
        )
        return 0
    except (Refusal, ValueError, KeyError, TypeError) as error:
        print(f"INSTALL REFUSED: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"INSTALL OPERATIONAL: {error}", file=sys.stderr)
        return 1
