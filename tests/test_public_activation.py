"""Check public activation inputs without a login or a shared account."""

import base64
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path
from types import ModuleType

import pytest

PLUGIN = Path(__file__).resolve().parents[1]


@pytest.fixture
def installer() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "public_activation", PLUGIN / "scripts/plugin/install.py"
    )
    assert spec is not None and spec.loader is not None
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


@pytest.fixture
def bootstrap(tmp_path: Path) -> Path:
    root = tmp_path / "project"
    owned = root / ".nott/nmemory"
    owned.mkdir(parents=True, mode=0o700)
    launcher = owned / "runtime.py"
    launcher.write_text("print('fixture')\n")
    launcher.chmod(0o700)
    config = owned / "memory.toml"
    config.write_text("")
    config.chmod(0o600)
    project_config = root / ".codex/config.toml"
    project_config.parent.mkdir()
    before_toml = b'model = "existing"\n'
    python_bin = os.path.abspath(os.sys.executable)
    project_config.write_text(
        before_toml.decode()
        + "\n[mcp_servers.nmemory]\ncommand = "
        + json.dumps(python_bin)
        + "\nargs = "
        + json.dumps(["-I", str(launcher), "mcp", "serve", "--project", "example"])
        + "\n"
    )
    project_config.chmod(0o600)
    receipt = owned / "bootstrap.json"
    report = {
        "root": str(root),
        "client": "codex",
        "project_id": "example",
        "launcher": str(launcher),
        "python": python_bin,
        "system1": {"mode": "lexical", "ready": False},
        "probe": {"mcp": True, "system1": False},
    }
    receipt.write_text(
        json.dumps(
            {
                "schema": 1,
                "root": str(root),
                "report": report,
                "files": [
                    {
                        "path": str(p),
                        "before": base64.b64encode(
                            before_toml if p == project_config else b""
                        ).decode(),
                        "after": hashlib.sha256(p.read_bytes()).hexdigest(),
                    }
                    for p in (launcher, config, project_config)
                ],
            }
        )
    )
    receipt.chmod(0o600)
    return receipt


def test_binding_uses_the_owned_project_launcher(
    installer: ModuleType, bootstrap: Path
) -> None:
    binding = installer.memory_binding(bootstrap, "codex")
    assert binding["project"] == "example"
    assert binding["launcher"] == str(bootstrap.with_name("runtime.py"))
    assert binding["mode"] == "lexical"


@pytest.mark.parametrize("change", ["existing", "addition", "field"])
def test_binding_accepts_later_foreign_mcp_changes(
    installer: ModuleType, claude_project: Path, change: str
) -> None:
    binding = installer.memory_binding(claude_project, "claude")
    document = json.loads(claude_project.read_text())
    target = Path(document["root"]) / ".mcp.json"
    config = json.loads(target.read_text())
    if change == "field":
        config["foreign"] = {"keep": True}
    else:
        name = "keep" if change == "existing" else "later"
        config["mcpServers"][name] = {"command": "changed"}
    current = json.dumps(config) + "\n"
    target.write_text(current)
    receipt = claude_project.read_bytes()
    assert installer.memory_binding(claude_project, "claude") == binding
    assert target.read_text() == current
    assert claude_project.read_bytes() == receipt


@pytest.mark.parametrize(
    "defect", ["command", "args", "remove", "extra", "link", "mode", "before", "after"]
)
def test_binding_refuses_changed_owned_mcp_input(
    installer: ModuleType, claude_project: Path, defect: str
) -> None:
    document = json.loads(claude_project.read_text())
    target = Path(document["root"]) / ".mcp.json"
    config = json.loads(target.read_text())
    config["mcpServers"]["keep"] = {"command": "changed"}
    if defect == "remove":
        del config["mcpServers"]["nmemory"]
    elif defect in {"command", "args", "extra"}:
        config["mcpServers"]["nmemory"][defect] = "changed"
    target.write_text(json.dumps(config))
    if defect == "link":
        saved = target.with_name("foreign.json")
        target.rename(saved)
        target.symlink_to(saved)
    elif defect == "mode":
        target.chmod(0o666)
    elif defect in {"before", "after"}:
        record = document["files"][-1]
        record[defect] = "invalid"
        claude_project.write_text(json.dumps(document))
    with pytest.raises(installer.Refusal):
        installer.memory_binding(claude_project, "claude")


@pytest.mark.parametrize("defect", ["hash", "mode", "link", "root", "client", "probe"])
def test_binding_refuses_unverified_input(
    installer: ModuleType, bootstrap: Path, defect: str
) -> None:
    if defect == "hash":
        bootstrap.with_name("runtime.py").write_text("print('changed')\n")
    elif defect == "mode":
        bootstrap.chmod(0o644)
    elif defect == "link":
        content = bootstrap.read_bytes()
        other = bootstrap.with_name("other.json")
        other.write_bytes(content)
        bootstrap.unlink()
        bootstrap.symlink_to(other)
    else:
        data = json.loads(bootstrap.read_text())
        if defect == "root":
            data["root"] = str(bootstrap.parent)
        elif defect == "client":
            data["report"]["client"] = "claude"
        else:
            data["report"]["probe"]["mcp"] = False
        bootstrap.write_text(json.dumps(data))
    with pytest.raises(installer.Refusal):
        installer.memory_binding(bootstrap, "codex")


def test_native_table_restore_preserves_foreign_tables(installer: ModuleType) -> None:
    raw = 'model = "example"\n\n[foreign]\nvalue = 1\n'
    header = '[plugins."nott@public"]'
    installed = installer.replace_table(
        raw, header, None, header + "\nenabled = true\n"
    )
    changed = installed.replace("value = 1", "value = 2")
    restored = installer.replace_table(
        changed, header, header + "\nenabled = true\n", None
    )
    assert restored == raw.replace("value = 1", "value = 2")
    with pytest.raises(installer.Refusal):
        installer.replace_table(
            installed.replace("true", "false"),
            header,
            header + "\nenabled = true\n",
            None,
        )


def test_native_rollback_refuses_paths_outside_its_owned_configuration(
    installer: ModuleType, tmp_path: Path, bootstrap: Path
) -> None:
    victim = tmp_path / "foreign.toml"
    content = "[foreign]\nvalue = 1\n"
    victim.write_text(content)
    record = {
        "kind": "native",
        "root": str(tmp_path),
        "runtime": str(tmp_path),
        "bootstrap": str(bootstrap),
        "market": "nott-public-" + "a" * 16,
        "view": str(tmp_path / (".nott-plugin/" + "a" * 64 + "/plugin")),
        "view_files": {},
        "surfaces": [
            {
                "path": str(victim),
                "header": "[foreign]",
                "before": None,
                "after": content,
                "file_present": False,
            }
        ],
    }
    receipt = {
        "schema": 1,
        "client": "codex",
        "records": [record],
        "state": "configured",
    }
    with pytest.raises(installer.Refusal):
        installer.rollback_native(tmp_path / "activation.json", receipt, record)
    assert victim.exists()
    assert victim.read_text() == content


def test_native_binding_materializes_confined_links(
    installer: ModuleType, tmp_path: Path
) -> None:
    view = tmp_path / "view"
    (view / "hooks").mkdir(parents=True)
    (view / "rules").mkdir()
    (view / "NOTT.md").write_text("Public law.\n")
    (view / "rules/AGENTS.md").symlink_to("../NOTT.md")
    (view / ".mcp.json").write_text(json.dumps({"mcpServers": {}}))
    (view / "hooks/hooks.json").write_text('{"hooks": {}}')
    with pytest.MonkeyPatch.context() as monkeypatch:
        monkeypatch.setattr(installer.package, "validate_mcp", lambda config: None)
        installer.bind_view(
            view,
            tmp_path,
            {"launcher": "fixture", "python": "fixture", "project": "example"},
        )
    assert not (view / "rules/AGENTS.md").is_symlink()
    assert (view / "rules/AGENTS.md").read_text() == "Public law.\n"


@pytest.mark.parametrize("fault", [None, "marketplace", "add"])
def test_native_codex_registration_and_restore(
    installer: ModuleType,
    bootstrap: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    fault: str | None,
) -> None:
    """Use the real native registry. The bootstrap probe remains a fixture."""

    if shutil.which("codex") is None:
        pytest.skip("The native Codex CLI is unavailable.")
    runtime = Path(os.path.abspath(os.sys.executable)).parent.parent
    if not all(
        (runtime / "bin" / name).is_file() for name in ("nmemory", "nspawn", "nbrowser")
    ):
        pytest.skip("The selected runtime packages are unavailable.")
    source = tmp_path / "source"
    shutil.copytree(
        PLUGIN,
        source,
        symlinks=True,
        ignore=shutil.ignore_patterns(
            "__pycache__", ".pytest_cache", ".ruff_cache", "evals"
        ),
    )
    (source / ".nott-public.json").write_text('{"schema": 1}')
    config = {
        "mcpServers": {
            name: {"command": name, "args": ["mcp", "serve"]}
            for name in ("nmemory", "nspawn", "nbrowser")
        }
    }
    for name in (".mcp.json", "mcp_config.json"):
        (source / name).write_text(json.dumps(config))
    monkeypatch.setenv(
        "PATH", str(runtime / "bin") + os.pathsep + os.environ.get("PATH", os.defpath)
    )
    bundle = tmp_path / "bundle"
    manifest = installer.package.build(source, bundle, runtime, source_commit="a" * 40)
    assert (
        json.loads((bundle / ".nott-runtime.json").read_text())["source_commit"]
        == "a" * 40
    )
    client = tmp_path / "client"
    client.mkdir()
    path = client / "config.toml"
    original = 'model = "example"\n\n[foreign]\nvalue = 1\n'
    path.write_text(original)
    receipt = tmp_path / "activation.json"
    if fault is not None:
        native = installer.native_call

        def fail_after_write(client_name, config_root, *args):
            result = native(client_name, config_root, *args)
            if args[0] == fault:
                raise installer.Refusal("The native reply is unavailable.")
            return result

        monkeypatch.setattr(installer, "native_call", fail_after_write)
        with pytest.raises(installer.Refusal):
            installer.install(
                bundle,
                "codex",
                client,
                receipt,
                runtime_root=runtime,
                bootstrap_receipt=bootstrap,
            )
        monkeypatch.setattr(installer, "native_call", native)
        assert installer.rollback(receipt)["state"] == "rolled-back"
        assert path.read_text() == original
        return
    project_toml = bootstrap.parents[2] / ".codex/config.toml"
    expected_project_toml = project_toml.read_text()
    result = installer.install(
        bundle,
        "codex",
        client,
        receipt,
        runtime_root=runtime,
        bootstrap_receipt=bootstrap,
    )
    assert result["native_registration"] == "configured"
    assert result["runtime_observed"] is False
    assert result["digest"] == manifest["digest"]
    appended = '\n# Team search\n[mcp_servers.later]\ncommand = "later"\n'
    path.write_text(path.read_text().replace("value = 1", "value = 2") + appended)
    assert (
        installer.install(
            bundle,
            "codex",
            client,
            receipt,
            runtime_root=runtime,
            bootstrap_receipt=bootstrap,
        )
        == result
    )
    launcher = bootstrap.with_name("runtime.py")
    previous = launcher.read_bytes()
    launcher.write_text("print('changed')\n")
    with pytest.raises(installer.Refusal):
        installer.install(
            bundle,
            "codex",
            client,
            receipt,
            runtime_root=runtime,
            bootstrap_receipt=bootstrap,
        )
    launcher.write_bytes(previous)
    restored = installer.rollback(receipt)
    assert restored["state"] == "rolled-back"
    assert path.read_text() == original.replace("value = 1", "value = 2") + appended
    assert project_toml.read_text() == expected_project_toml
    project_toml.write_text(project_toml.read_text() + appended)
    assert installer.memory_binding(bootstrap, "codex")["project"] == "example"
    assert installer.rollback(receipt)["state"] == "rolled-back"


def test_public_builder_uses_the_selected_runtime_without_path(
    installer: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:

    runtime = Path(os.path.abspath(os.sys.executable)).parent.parent
    if not all(
        (runtime / "bin" / name).is_file() for name in ("nmemory", "nspawn", "nbrowser")
    ):
        pytest.skip("The selected runtime packages are unavailable.")
    source = tmp_path / "source"
    shutil.copytree(
        PLUGIN,
        source,
        symlinks=True,
        ignore=shutil.ignore_patterns(
            "__pycache__", ".pytest_cache", ".ruff_cache", "evals"
        ),
    )
    (source / ".nott-public.json").write_text('{"schema": 1}')
    for name in (".mcp.json", "mcp_config.json"):
        (source / name).write_text(
            json.dumps(
                {
                    "mcpServers": {
                        key: {"command": key, "args": ["mcp", "serve"]}
                        for key in ("nmemory", "nspawn", "nbrowser")
                    }
                }
            )
        )
    monkeypatch.setenv("PATH", os.defpath)
    bundle = tmp_path / "bundle"
    installer.package.build(source, bundle, runtime, source_commit="a" * 40)
    assert str(runtime) not in (bundle / ".nott-runtime.json").read_text()
    assert str(runtime) not in (bundle / ".mcp.json").read_text()


def test_public_activation_does_not_ignore_previous_law(
    installer: ModuleType,
    bootstrap: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(installer, "public_install", lambda *args: {"schema": 1})
    with pytest.raises(installer.Refusal, match="previous-law"):
        installer.install(
            tmp_path / "bundle",
            "codex",
            tmp_path / "client",
            tmp_path / "activation.json",
            previous_law=tmp_path / "old-law",
            runtime_root=tmp_path,
            bootstrap_receipt=bootstrap,
        )


@pytest.mark.parametrize(
    "defect", ["separator", "client", "version", "bootstrap_hooks"]
)
def test_native_receipt_refuses_invalid_optional_fields(
    installer: ModuleType, defect: str
) -> None:
    record = {
        "kind": "native",
        "root": "fixture",
        "runtime": "fixture",
        "bootstrap": "fixture",
        "market": "fixture",
        "view": "fixture",
        "view_files": {},
        "surfaces": [],
    }
    receipt = {"schema": 1, "client": "codex", "records": [record]}
    if defect == "separator":
        record["separator"] = 3
    elif defect == "client":
        receipt["client"] = "claude"
    else:
        record[defect] = 3
    with pytest.raises(installer.Refusal):
        installer.is_activation_receipt(receipt)


@pytest.mark.parametrize("defect", [None, "hash", "link", "duplicate"])
def test_binding_checks_the_owned_ignore_record(
    installer: ModuleType, bootstrap: Path, defect: str | None
) -> None:
    ignore = bootstrap.with_name(".gitignore")
    ignore.write_text("*\n!.gitignore\n")
    ignore.chmod(0o600)
    document = json.loads(bootstrap.read_text())
    record = {
        "path": str(ignore),
        "after": hashlib.sha256(ignore.read_bytes()).hexdigest(),
    }
    document["files"].append(record)
    if defect == "hash":
        ignore.write_text("changed\n")
    elif defect == "link":
        ignore.unlink()
        ignore.symlink_to(bootstrap.with_name("memory.toml"))
    elif defect == "duplicate":
        document["files"].append(record)
    bootstrap.write_text(json.dumps(document))
    if defect is None:
        assert installer.memory_binding(bootstrap, "codex")["project"] == "example"
    else:
        with pytest.raises(installer.Refusal):
            installer.memory_binding(bootstrap, "codex")


def test_public_bundle_excludes_workspace_sources(
    installer: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:

    source = tmp_path / "source"
    shutil.copytree(
        PLUGIN,
        source,
        ignore=shutil.ignore_patterns("__pycache__", ".pytest_cache", "evals"),
    )
    (source / ".nott-public.json").write_text('{"schema": 1}')
    package = source / "packages/nspawn"
    package.mkdir(parents=True, exist_ok=True)
    (package / "unused.py").write_text("VALUE = 42\n")
    (source / "source-manifest.json").write_text('{"schema": 1, "files": {}}')
    runtime = tmp_path / "env"
    (runtime / "bin").mkdir(parents=True)
    for name in ("nmemory", "nspawn", "nbrowser"):
        executable = runtime / "bin" / name
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o700)
    for name in (".mcp.json", "mcp_config.json"):
        (source / name).write_text(
            json.dumps(
                {
                    "mcpServers": {
                        key: {"command": key, "args": ["mcp", "serve"]}
                        for key in ("nmemory", "nspawn", "nbrowser")
                    }
                }
            )
        )
    bundle = tmp_path / "bundle"
    installer.package.build(source, bundle, runtime, source_commit="a" * 40)
    assert not (bundle / "packages").exists()
    assert (bundle / "source-manifest.json").is_file()


@pytest.fixture
def public_bundle(installer: ModuleType, tmp_path: Path) -> tuple[Path, Path]:
    """Build a public profile from synthetic MCP configuration and source copies."""
    runtime = Path(os.path.abspath(os.sys.executable)).parent.parent
    source = tmp_path / "public-source"
    shutil.copytree(
        PLUGIN,
        source,
        symlinks=True,
        ignore=shutil.ignore_patterns(
            "__pycache__", ".pytest_cache", ".ruff_cache", "evals"
        ),
    )
    (source / ".nott-public.json").write_text('{"schema": 1}')
    for filename in (".mcp.json", "mcp_config.json"):
        (source / filename).write_text(
            json.dumps(
                {
                    "mcpServers": {
                        name: {"command": name, "args": ["mcp", "serve"]}
                        for name in ("nmemory", "nspawn", "nbrowser")
                    }
                }
            )
        )
    bundle = tmp_path / "public-bundle"
    installer.package.build(source, bundle, runtime, source_commit="a" * 40)
    return bundle, runtime


def test_public_bundle_cannot_use_private_instruction_activation(
    installer: ModuleType,
    public_bundle: tuple[Path, Path],
    tmp_path: Path,
) -> None:
    bundle, _ = public_bundle
    with pytest.raises(installer.Refusal, match="memory-bootstrap"):
        installer.install(
            bundle, "claude", tmp_path / "client", tmp_path / "activation.json"
        )


def test_native_cli_uses_a_private_home(
    installer: ModuleType,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = tmp_path / "client"
    root.mkdir(mode=0o700)
    executable = tmp_path / "claude"
    executable.write_text(
        "#!/usr/bin/python3\n"
        "import os\nfrom pathlib import Path\n"
        "assert Path(os.environ['HOME']).is_relative_to(Path(os.environ['CLAUDE_CONFIG_DIR']))\n"
        "print('[]')\n"
    )
    executable.chmod(0o700)
    monkeypatch.setattr(installer.shutil, "which", lambda name: str(executable))
    assert installer.native_call("claude", root, "list", "--json") == {"installed": []}


@pytest.mark.parametrize(
    "fault",
    [
        None,
        "marketplace",
        "install",
        "cache-change",
        "settings-change",
        "hooks-change",
        "linked-cache",
        "bootstrap-restore",
        "foreign-mcp-change",
    ],
)
def test_public_claude_transaction_preserves_foreign_configuration(
    installer: ModuleType,
    public_bundle: tuple[Path, Path],
    claude_project: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    fault: str | None,
) -> None:
    """Check registry recovery with a fixture. This does not prove the native CLI."""
    bundle, runtime = public_bundle
    bootstrap = claude_project
    document = json.loads(bootstrap.read_text())
    project_mcp = Path(document["root"]) / ".mcp.json"
    root = Path(document["root"]) / ".claude"
    root.mkdir(mode=0o700)
    settings = root / "settings.json"
    original_settings = {
        "model": "example",
        "label": "\u03bb",
        "enabledPlugins": {"other@foreign": True},
        "hooks": {
            "SessionStart": [
                {
                    "hooks": [
                        {
                            "type": "command",
                            "command": str(bootstrap.with_name("runtime.py"))
                            + " --hook nmemory-session.sh",
                        }
                    ]
                }
            ]
        },
    }
    settings.write_text(
        json.dumps(original_settings, indent=2, ensure_ascii=False) + "\n"
    )
    document["files"].append(
        {
            "path": str(settings),
            "after": hashlib.sha256(settings.read_bytes()).hexdigest(),
        }
    )
    bootstrap.write_text(json.dumps(document))
    registry = root / "plugins/installed_plugins.json"
    known = root / "plugins/known_marketplaces.json"
    registry.parent.mkdir()
    foreign_registry = {
        "version": 2,
        "plugins": {
            "other@foreign": [
                {
                    "scope": "user",
                    "installPath": str(tmp_path / "foreign"),
                    "version": "1.0.0",
                }
            ]
        },
    }
    foreign_known = {"foreign": {"installLocation": str(tmp_path / "foreign")}}
    registry.write_text(json.dumps(foreign_registry))
    known.write_text(json.dumps(foreign_known))
    receipt = tmp_path / "activation.json"
    calls: list[tuple[str, ...]] = []

    def native(client: str, config_root: Path, *args: str):
        assert client == "claude" and config_root == root
        calls.append(args)
        registry = root / "plugins/installed_plugins.json"
        known = root / "plugins/known_marketplaces.json"
        if args[:2] == ("marketplace", "add"):
            catalog = Path(args[2])
            market = json.loads(
                (catalog / ".claude-plugin/marketplace.json").read_text()
            )["name"]
            known.parent.mkdir(exist_ok=True)
            data = json.loads(known.read_text())
            data[market] = {
                "source": {"source": "directory", "path": str(catalog)},
                "installLocation": str(catalog),
            }
            known.write_text(json.dumps(data))
        elif args[0] == "install":
            ident = args[1]
            market = ident.split("@")[1]
            catalog = Path(json.loads(known.read_text())[market]["installLocation"])
            source = catalog / "plugin"
            version = json.loads((source / ".claude-plugin/plugin.json").read_text())[
                "version"
            ]
            cache = root / "plugins/cache" / market / "nott" / version.replace("+", "-")
            shutil.copytree(source, cache)
            data = json.loads(registry.read_text())
            data["plugins"][ident] = [
                {"scope": "user", "installPath": str(cache), "version": version}
            ]
            registry.write_text(json.dumps(data))
            data = json.loads(settings.read_text())
            data["enabledPlugins"][ident] = True
            settings.write_text(json.dumps(data))
        elif args[0] == "uninstall":
            ident = args[1]
            data = json.loads(registry.read_text())
            entries = data["plugins"].pop(ident, [])
            for entry in entries:
                (Path(entry["installPath"]) / ".orphaned_at").write_text(
                    "1792329876734"
                )
            registry.write_text(json.dumps(data))
            data = json.loads(settings.read_text())
            data["enabledPlugins"].pop(ident, None)
            settings.write_text(json.dumps(data))
        elif args[:2] == ("marketplace", "remove"):
            data = json.loads(known.read_text())
            data.pop(args[2], None)
            known.write_text(json.dumps(data))
        if args[0] == fault:
            raise installer.Refusal("The native reply is unavailable.")
        if args[0] == "list":
            data = (
                json.loads(registry.read_text())
                if registry.exists()
                else {"plugins": {}}
            )
            enabled = json.loads(settings.read_text())["enabledPlugins"]
            return {
                "installed": [
                    {"id": ident, **entries[0], "enabled": enabled.get(ident, False)}
                    for ident, entries in data["plugins"].items()
                ]
            }
        return {}

    monkeypatch.setattr(installer, "native_call", native)
    monkeypatch.setattr(installer.shutil, "which", lambda name: "/fixture/" + name)
    interrupted = fault in {"marketplace", "install"}
    if interrupted:
        with pytest.raises(installer.Refusal, match="reply"):
            installer.install(
                bundle,
                "claude",
                root,
                receipt,
                runtime_root=runtime,
                bootstrap_receipt=bootstrap,
            )
        fault = None
    else:
        result = installer.install(
            bundle,
            "claude",
            root,
            receipt,
            runtime_root=runtime,
            bootstrap_receipt=bootstrap,
        )
        assert result["native_registration"] == "configured"
        assert result["runtime_observed"] is False
        assert not (root / "CLAUDE.md").exists()
        view = Path(result["records"][0]["view"])
        view_hooks = json.loads((view / "hooks/hooks.json").read_text())["hooks"]
        for groups in view_hooks.values():
            for group in groups:
                for hook in group["hooks"]:
                    assert not any(
                        name in hook["command"]
                        for name in (
                            "nmemory-session.sh",
                            "nmemory-recall.py",
                            "nmemory-capture-gate.py",
                        )
                    )
        assert (view / ".mcp.json").read_bytes() == (
            view / "mcp_config.json"
        ).read_bytes()
        servers = json.loads((view / ".mcp.json").read_text())["mcpServers"]
        assert all(
            servers[name]["command"] == str(runtime / "bin" / name)
            for name in ("nspawn", "nbrowser")
        )
        memory = json.loads((view / ".mcp.json").read_text())["mcpServers"]["nmemory"]
        assert memory["command"] == document["report"]["python"]
        assert Path(memory["command"]).parent.parent == runtime
        assert memory["args"] == [
            "-I",
            str(bootstrap.with_name("runtime.py")),
            "mcp",
            "serve",
            "--project",
            "example",
        ]
        data = json.loads(settings.read_text())
        if fault != "bootstrap-restore":
            data["model"] = "changed"
        settings.write_text(json.dumps(data))
        if fault == "foreign-mcp-change":
            changed_mcp = json.loads(project_mcp.read_text())
            changed_mcp["mcpServers"]["keep"] = {"command": "changed"}
            project_mcp.write_text(json.dumps(changed_mcp))
        assert (
            installer.install(
                bundle,
                "claude",
                root,
                receipt,
                runtime_root=runtime,
                bootstrap_receipt=bootstrap,
            )
            == result
        )
        previous = bootstrap.with_name("runtime.py").read_bytes()
        bootstrap.with_name("runtime.py").write_text("print('changed')\n")
        with pytest.raises(installer.Refusal):
            installer.install(
                bundle,
                "claude",
                root,
                receipt,
                runtime_root=runtime,
                bootstrap_receipt=bootstrap,
            )
        bootstrap.with_name("runtime.py").write_bytes(previous)
        if fault in {"settings-change", "hooks-change"}:
            changed = json.loads(settings.read_text())
            if fault == "settings-change":
                ident = next(
                    name
                    for name in changed["enabledPlugins"]
                    if name.startswith("nott@")
                )
                changed["enabledPlugins"][ident] = False
            else:
                changed["hooks"] = {}
            settings.write_text(json.dumps(changed))
            with pytest.raises(installer.Refusal, match="changed"):
                installer.rollback(receipt)
            settings.write_text(json.dumps(data))
        elif fault in {"cache-change", "linked-cache"}:
            record = result["records"][0]
            version = json.loads((view / ".claude-plugin/plugin.json").read_text())[
                "version"
            ]
            cache = (
                root
                / "plugins/cache"
                / record["market"]
                / "nott"
                / version.replace("+", "-")
            )
            if fault == "cache-change":
                target = cache / "NOTT.md"
                before = target.read_bytes()
                target.write_text("Changed cache.\n")
                with pytest.raises(installer.Refusal, match="cache"):
                    installer.rollback(receipt)
                target.write_bytes(before)
            else:
                saved = tmp_path / "moved-cache"
                cache.rename(saved)
                cache.symlink_to(saved, target_is_directory=True)
                with pytest.raises(installer.Refusal):
                    installer.rollback(receipt)
                cache.unlink()
                saved.rename(cache)
    preserved_mcp = project_mcp.read_bytes()
    assert installer.rollback(receipt)["state"] == "rolled-back"
    assert installer.rollback(receipt)["state"] == "rolled-back"
    assert project_mcp.read_bytes() == preserved_mcp
    assert json.loads(settings.read_text()) == {
        **original_settings,
        "model": "example"
        if interrupted or fault == "bootstrap-restore"
        else "changed",
    }
    assert json.loads(registry.read_text()) == foreign_registry
    assert json.loads(known.read_text()) == foreign_known
    if interrupted or fault == "bootstrap-restore":
        assert (
            hashlib.sha256(settings.read_bytes()).hexdigest()
            == document["files"][-1]["after"]
        )
    if not interrupted:
        # A new bootstrap probe records the settings that rollback preserved.
        document["files"][-1]["after"] = hashlib.sha256(
            settings.read_bytes()
        ).hexdigest()
        bootstrap.write_text(json.dumps(document))
        assert (
            installer.install(
                bundle,
                "claude",
                root,
                receipt,
                runtime_root=runtime,
                bootstrap_receipt=bootstrap,
            )["native_registration"]
            == "configured"
        )
        assert installer.rollback(receipt)["state"] == "rolled-back"


def test_native_timeout_does_not_disclose_process_arguments(
    installer: ModuleType,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = tmp_path / "client"
    root.mkdir(mode=0o700)
    monkeypatch.setattr(installer.shutil, "which", lambda name: "/fixture/claude")

    def timeout(*args, **kwargs):
        raise subprocess.TimeoutExpired(["fixture-private-argument"], 120)

    monkeypatch.setattr(installer.subprocess, "run", timeout)
    with pytest.raises(OSError, match="timed out") as error:
        installer.native_call("claude", root, "list", "--json")
    assert "fixture-private-argument" not in str(error.value)


@pytest.mark.parametrize("fault", [None, "marketplace", "install"])
def test_native_claude_registration_and_restore(
    installer: ModuleType,
    public_bundle: tuple[Path, Path],
    claude_project: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    fault: str | None,
) -> None:
    """Use the native registry without login. Keep the MCP probe as a fixture."""
    if shutil.which("claude") is None:
        pytest.skip(
            "The native Claude CLI is unavailable. The integrator must run this check."
        )
    bundle, runtime = public_bundle
    bootstrap = claude_project
    document = json.loads(bootstrap.read_text())
    root = Path(document["root"]) / ".claude"
    root.mkdir(mode=0o700)
    settings = root / "settings.json"
    original = {"model": "example", "enabledPlugins": {"other@foreign": True}}
    settings.write_text(json.dumps(original))
    document["files"].append(
        {
            "path": str(settings),
            "after": hashlib.sha256(settings.read_bytes()).hexdigest(),
        }
    )
    bootstrap.write_text(json.dumps(document))
    receipt = tmp_path / "native.json"
    call = installer.native_call
    if fault is not None:

        def fail_after_write(client: str, config_root: Path, *args: str):
            result = call(client, config_root, *args)
            if args[0] == fault:
                raise installer.Refusal("The native reply is unavailable.")
            return result

        monkeypatch.setattr(installer, "native_call", fail_after_write)
        with pytest.raises(installer.Refusal, match="reply"):
            installer.install(
                bundle,
                "claude",
                root,
                receipt,
                runtime_root=runtime,
                bootstrap_receipt=bootstrap,
            )
        monkeypatch.setattr(installer, "native_call", call)
    else:
        result = installer.install(
            bundle,
            "claude",
            root,
            receipt,
            runtime_root=runtime,
            bootstrap_receipt=bootstrap,
        )
        assert result["native_registration"] == "configured"
        assert (
            installer.install(
                bundle,
                "claude",
                root,
                receipt,
                runtime_root=runtime,
                bootstrap_receipt=bootstrap,
            )
            == result
        )
        previous = bootstrap.with_name("runtime.py").read_bytes()
        bootstrap.with_name("runtime.py").write_text("print('changed')\n")
        with pytest.raises(installer.Refusal):
            installer.install(
                bundle,
                "claude",
                root,
                receipt,
                runtime_root=runtime,
                bootstrap_receipt=bootstrap,
            )
        bootstrap.with_name("runtime.py").write_bytes(previous)
        original["model"] = "changed"
        data = json.loads(settings.read_text())
        data["model"] = "changed"
        settings.write_text(json.dumps(data))
    assert installer.rollback(receipt)["state"] == "rolled-back"
    assert installer.rollback(receipt)["state"] == "rolled-back"
    assert json.loads(settings.read_text()) == original


@pytest.mark.parametrize(
    "field",
    [None, "id", "enabled", "scope", "version", "installPath", "raw-version-path"],
)
def test_claude_readback_requires_the_bound_registration(
    installer: ModuleType,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    field: str | None,
) -> None:
    market = "nott-public-" + "a" * 16
    version = "1.2.3+sha." + "b" * 64
    entry = {
        "id": "nott@" + market,
        "enabled": True,
        "scope": "user",
        "version": version,
        "installPath": str(
            tmp_path / "plugins/cache" / market / "nott" / version.replace("+", "-")
        ),
    }
    if field == "raw-version-path":
        entry["installPath"] = str(
            tmp_path / "plugins/cache" / market / "nott" / version
        )
    elif field is not None:
        entry.pop(field)
    monkeypatch.setattr(installer, "native_call", lambda *args: {"installed": [entry]})
    if field is None:
        installer.native_readback("claude", tmp_path, market, version)
    else:
        with pytest.raises(installer.Refusal, match="readback"):
            installer.native_readback("claude", tmp_path, market, version)


def test_public_agy_refuses_before_native_registration(
    installer: ModuleType,
    public_bundle: tuple[Path, Path],
    bootstrap: Path,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    bundle, runtime = public_bundle

    def native(*args):
        pytest.fail("Unsupported activation must not call a native client.")

    monkeypatch.setattr(installer, "native_call", native)
    with pytest.raises(installer.Refusal, match="public agy activation"):
        installer.install(
            bundle,
            "agy",
            tmp_path / "client",
            tmp_path / "activation.json",
            runtime_root=runtime,
            bootstrap_receipt=bootstrap,
        )
    assert not (tmp_path / "activation.json").exists()


@pytest.fixture
def claude_project(bootstrap: Path) -> Path:
    """Use owned Claude project files with a synthetic bootstrap probe."""
    document = json.loads(bootstrap.read_text())
    document["report"]["client"] = "claude"
    root = Path(document["root"])
    codex = root / ".codex/config.toml"
    codex.unlink()
    config = root / ".mcp.json"
    config.write_text(
        json.dumps(
            {
                "mcpServers": {
                    "keep": {"command": "before"},
                    "nmemory": {
                        "command": document["report"]["python"],
                        "args": [
                            "-I",
                            str(bootstrap.with_name("runtime.py")),
                            "mcp",
                            "serve",
                            "--project",
                            "example",
                        ],
                    },
                }
            },
            indent=2,
        )
        + "\n"
    )
    document["files"] = [
        item for item in document["files"] if item["path"] != str(codex)
    ]
    document["files"].append(
        {
            "path": str(config),
            "after": hashlib.sha256(config.read_bytes()).hexdigest(),
            "before": base64.b64encode(
                b'{"mcpServers":{"keep":{"command":"before"}}}'
            ).decode(),
        }
    )
    bootstrap.write_text(json.dumps(document))
    return bootstrap
