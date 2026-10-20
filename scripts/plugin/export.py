"""Export the public plugin and its workspace packages from an explicit source."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import Any

import tomllib

SCHEMA = 1
EXCLUDE = {
    "__pycache__",
    ".pytest_cache",
    ".ruff_cache",
    ".hypothesis",
    "evals",
    ".git",
    ".nott",
}
# Diagnostics contain only relative paths, rule names and line numbers.


def projection(source: Path) -> ModuleType:
    """Load the shared policy from the selected source."""
    path = source / "mcps/nmemory/nmemory/commands/projection.py"
    if (source / "source-manifest.json").is_file():
        path = source / "packages/nmemory/nmemory/commands/projection.py"
    if not path.resolve(strict=True).is_relative_to(source) or any(
        part.is_symlink() for part in (path, *path.parents) if part != source
    ):
        raise ValueError("the policy path escapes the selected source")
    spec = importlib.util.spec_from_file_location("public_projection", path)
    if spec is None or spec.loader is None:
        raise ValueError("the public projection policy is unavailable")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def layout(source: Path) -> ModuleType:
    path = source / "mcps/nmemory/nmemory/commands/layout.py"
    if (source / "source-manifest.json").is_file():
        path = source / "packages/nmemory/nmemory/commands/layout.py"
    if not path.resolve(strict=True).is_relative_to(source) or any(
        part.is_symlink() for part in (path, *path.parents) if part != source
    ):
        raise ValueError("the policy path escapes the selected source")
    spec = importlib.util.spec_from_file_location("selected_public_layout", path)
    if spec is None or spec.loader is None:
        raise ValueError("the selected layout helper is unavailable")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


_SELF_ROOT = Path(__file__).resolve().parents[3]
if (Path(__file__).resolve().parents[2] / ".nott-public.json").is_file():
    _SELF_ROOT = Path(__file__).resolve().parents[2]
_policy = projection(_SELF_ROOT)
Refusal = _policy.Refusal
Finding = _policy.Finding
PRIVATE = _policy.PRIVATE
scan = _policy.scan
private = _policy.private
executable_ast = _policy.executable_ast
public_python = _policy.public_python
public_toml = _policy.public_toml
public_runtime = _policy.public_runtime


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def copy(
    source: Path, relative: str, target: Path, destination_name: str | None = None
) -> None:
    """Copy one selected path. Refuse links outside the explicit source."""
    destination_name = relative if destination_name is None else destination_name
    for value in (relative, destination_name):
        if (
            not value
            or PurePosixPath(value).is_absolute()
            or ".." in PurePosixPath(value).parts
            or "\\" in value
        ):
            raise Refusal("the source profile contains an unsafe path")
    parts = PurePosixPath(relative).parts
    if not parts or relative.startswith("/") or ".." in parts:
        raise Refusal("the source profile contains an unsafe path")
    origin = source / relative
    try:
        origin.resolve(strict=True).relative_to(source)
    except (OSError, ValueError, RuntimeError) as error:
        raise Refusal(
            f"source path is absent or escapes the source: {relative}"
        ) from error
    if origin.is_dir():
        if origin.is_symlink():
            raise Refusal(f"directory links are unsupported: {relative}")
        (target / destination_name).mkdir(parents=True, exist_ok=True)
        for child in sorted(origin.iterdir()):
            if child.name in EXCLUDE or child.name.endswith(
                (".pyc", ".test.ts", ".test.tsx")
            ):
                continue
            copy(
                source,
                str(child.relative_to(source)),
                target,
                str(Path(destination_name) / child.name),
            )
    elif origin.is_file():
        destination = target / destination_name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if origin.is_symlink():
            # Retain internal relative links. Never publish an absolute source path.
            link = os.path.relpath(origin.resolve(), origin.parent)
            destination.symlink_to(link)
        else:
            shutil.copy2(origin, destination)
    else:
        raise Refusal(f"unsupported source file: {relative}")


def rewrite_links(text: str, origin: Path, destination: Path) -> str:
    result: str = layout(_SELF_ROOT).rewrite_links(text, origin, destination, {})
    return result


def local_links(root: Path) -> list[str]:
    result: list[str] = layout(_SELF_ROOT).local_links(root)
    return result


def public_readme(path: Path) -> None:
    """Keep runtime API documentation and remove private plan references."""
    text = path.read_text()
    text = re.sub(r"(?m)^The crawl frontier was designed in [^\n]+\n", "", text)
    text = re.sub(
        r"The source parity inventory and outstanding real-vendor observations live in\n"
        r"\[the native completion plan\]\([^)]+\)[.] ",
        "",
        text,
    )
    text = re.sub(r"\s*\(cap-\d+\)", "", text)
    text = PRIVATE["private-record"].sub("", text)
    if "../../docs/runbooks/public-installation.md" not in text:
        text += "\nUse the [public installation guide](../../docs/runbooks/public-installation.md).\n"
    if "../../docs/design/public/catalog.md" not in text:
        text += "See the [public catalog](../../docs/design/public/catalog.md) for commands.\n"
    path.write_text(text)


def public_documents(source: Path, stage: Path) -> None:
    selected = layout(source)
    policy = projection(source)

    def copy_document(
        root: Path, origin: Path, output: Path, destination: Path
    ) -> None:
        copy(root, str(origin), output, str(destination))

    selected.documents(source, stage, selected.read(source), "plugin", copy_document)
    policy.public_contributing(
        stage, "uv run --group dev pytest tests/test_public_documents.py -q"
    )


def public_law(path: Path) -> None:
    """Remove the producer's standing grant and personal language rule."""
    text = path.read_text()
    start = "Commit, push to the campaign branch,"
    end = "A request to plan authorizes a plan, not implementation."
    if start in text:
        before, tail = text.split(start, 1)
        if end not in tail:
            raise Refusal(
                "the standing grant changed. Inspect the public law transform"
            )
        text = before + (
            "Use only authority that the user grants in this project. Installation grants no authority "
            "to commit, push, merge, deploy, tag or release. "
            + end
            + tail.split(end, 1)[1]
        )
    start = "verbatim. Reply in the owner's language; Portuguese is Brazilian, never"
    end = "the same agent rewrites it."
    if start in text:
        before, tail = text.split(start, 1)
        if end not in tail:
            raise Refusal("the language rule changed. Inspect the public law transform")
        text = (
            before + "verbatim. Reply in the user's language." + tail.split(end, 1)[1]
        )
    text = text.replace("(owner law, 2026-09-19)", "(the change sequence)")
    text = text.replace(
        "Merging the campaign's pull request after review and checks is **NOTT**'s own\nact, never reserved or asked for.",
        "Merge only when the user grants that act and the required review and checks pass.",
    )
    path.write_text(text)


def export(source: Path, output: Path) -> dict[str, Any]:
    source = source.resolve(strict=True)
    if output.exists() or output.is_symlink():
        raise Refusal("export output already exists. Use a new directory")
    output = output.resolve()
    if (
        output == source
        or output in source.parents
        or (source in output.parents and output.relative_to(source).parts[0] != ".nott")
    ):
        raise Refusal("export output must be outside selected source paths")
    selected = layout(source)
    policy = projection(source)
    contract = selected.read(source)
    mapping = selected.paths(contract, "plugin")
    public = (source / "source-manifest.json").is_file()
    plugin_root = "." if public else "plugin"
    profile = json.loads((source / plugin_root / "public/manifest.json").read_text())
    members = list(contract["components"]["plugin"]["packages"])

    if (
        profile.get("schema") != SCHEMA
        or not isinstance(members, list)
        or not members
        or not all(isinstance(member, str) for member in members)
        or len(members) != len(set(members))
    ):
        raise Refusal("the public package profile is unsupported")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".nott-export-", dir=output.parent
    ) as scratch:
        stage = Path(scratch) / "source"
        stage.mkdir()
        for name in ("LICENSE", ".python-version"):
            copy(source, name, stage)
        for member in members:
            base = mapping[member] if public else member
            metadata = tomllib.loads((source / base / "pyproject.toml").read_text())
            module = metadata["project"]["name"].replace("-", "_")
            for name in ("pyproject.toml", "README.md"):
                copy(source, f"{base}/{name}", stage, f"{member}/{name}")
            if member == "evals/nmemory":
                for path in sorted((source / base / module).rglob("*")):
                    if path.suffix in {".py", ".typed"} and not any(
                        part in EXCLUDE
                        for part in path.relative_to(source / base / module).parts
                    ):
                        copy(
                            source,
                            str(path.relative_to(source)),
                            stage,
                            str(Path(member) / path.relative_to(source / base)),
                        )
            else:
                copy(source, f"{base}/{module}", stage, f"{member}/{module}")
            if member == "mcps/nspawn":
                copy(source, f"{base}/tests", stage, f"{member}/tests")
        try:
            selected.resources(
                source,
                stage,
                contract,
                {member: member for member in members},
                lambda root, origin, output, target: copy(
                    root, str(origin), output, str(target)
                ),
            )
        except ValueError as error:
            raise Refusal(str(error)) from None
        for name in profile["plugin_paths"]:
            # These are the only optional native source resources.
            if (
                name in {"rules", "agents", "types"}
                and not (source / plugin_root / name).exists()
            ):
                continue
            copy(source, str(Path(plugin_root) / name), stage, f"plugin/{name}")
        for name in profile["omit_hooks"]:
            if Path(name).name != name:
                raise Refusal("the public hook profile contains an unsafe path")
            (stage / "plugin/hooks" / name).unlink(missing_ok=public)
        for name in profile["omit_agents"]:
            if Path(name).name != name:
                raise Refusal("the public agent profile contains an unsafe path")
            (stage / "plugin/agents" / name).unlink(missing_ok=public)
        for agent in (stage / "plugin/agents").glob("*.md"):
            agent.write_text(
                "".join(
                    line
                    for line in agent.read_text().splitlines(keepends=True)
                    if "apps/apple" not in line
                )
            )
        register = stage / "plugin/hooks/register.ts"
        register.write_text(
            "".join(
                line
                for line in register.read_text().splitlines(keepends=True)
                if not any(name in line for name in ("motd", "watch"))
            )
        )
        native_hooks = stage / "plugin/hooks/hooks.json"
        hooks = json.loads(native_hooks.read_text())
        for group in hooks["hooks"]["Stop"]:
            group["hooks"] = [
                hook for hook in group["hooks"] if "voice.sh" not in hook["command"]
            ]
        write_json(native_hooks, hooks)
        selected.hooks(
            source,
            stage,
            Path(mapping["mcps/nmemory"]) / "nmemory/hooks"
            if public
            else Path("plugin/hooks"),
            Path("mcps/nmemory/nmemory/hooks"),
            lambda root, origin, output, target: copy(
                root, str(origin), output, str(target)
            ),
        )
        for name in profile["portable_paths"]:
            origin = selected.destination(name, mapping) if public else name
            copy(source, origin, stage, name)
        for resource in ("npm", "python"):
            base = mapping["mcps/nbrowser"] if public else "mcps/nbrowser"
            copy(source, f"{base}/{resource}", stage, f"mcps/nbrowser/{resource}")
        public_law(stage / "plugin/NOTT.md")
        original = json.loads((source / plugin_root / ".mcp.json").read_text())[
            "mcpServers"
        ]
        config = {
            "mcpServers": {
                name: {
                    "type": "stdio",
                    "command": name,
                    "args": ["mcp", "serve"],
                    **(
                        {"env_vars": original[name]["env_vars"]}
                        if "env_vars" in original[name]
                        else {}
                    ),
                }
                for name in ("nmemory", "nspawn", "nbrowser")
            }
        }
        for name in (".mcp.json", "mcp_config.json"):
            write_json(stage / "plugin" / name, config)
        # This marker selects public build behavior. It carries no machine binding.
        write_json(stage / "plugin/.nott-public.json", {"schema": SCHEMA})
        claude = stage / "plugin/.claude-plugin/plugin.json"
        native = json.loads(claude.read_text())
        native.pop("experimental", None)
        write_json(claude, native)
        original_lock = source / "uv.lock"
        shutil.copy2(original_lock, stage / "uv.lock")
        root_metadata = tomllib.loads((source / "pyproject.toml").read_text())
        try:
            policy.public_runtime(stage)
            policy.public_wire_fixtures(stage)
            policy.commentary(stage)
        except policy.Finding as error:
            raise Finding(str(error)) from None
        except policy.Refusal as error:
            raise Refusal(str(error)) from None
        try:
            policy.format_source(stage)
        except policy.Refusal as error:
            raise Refusal(str(error)) from None
        # Move the selected source before resolving document and code links.
        flattened = Path(scratch) / "flattened"
        flattened.mkdir()
        for origin, destination in mapping.items():
            base = stage / origin
            target = flattened / destination
            target.mkdir(parents=True, exist_ok=True)
            for child in base.iterdir():
                shutil.move(str(child), target / child.name)
        for name in ("LICENSE", ".python-version", "uv.lock"):
            shutil.copy2(stage / name, flattened / name)
        stage = flattened
        copy(source, "ops/mirror/projects.json", stage)
        packages = selected.metadata(source, stage, mapping)
        members = [value for value in mapping.values() if value != "."]
        (stage / "pyproject.toml").write_text(
            "[tool.uv.workspace]\nmembers = "
            + json.dumps(members)
            + "\n\n[dependency-groups]\ndev = "
            + json.dumps(root_metadata["dependency-groups"]["dev"])
            + "\n"
        )
        public_documents(source, stage)
        for name in ("plugin.json", ".claude-plugin/plugin.json"):
            path = stage / name
            metadata = json.loads(path.read_text())
            metadata.setdefault("license", selected.LICENSE)
            write_json(path, metadata)
        write_json(
            stage / ".claude-plugin/marketplace.json",
            {
                "name": "nott-public",
                "owner": {"name": "menot-you"},
                "plugins": [
                    {"name": "nott", "source": "./", "version": native["version"]}
                ],
            },
        )
        missing = selected.local_links(stage)
        if missing:
            raise Refusal("public local links are missing: " + json.dumps(missing))
        findings = policy.scan(stage)
        if findings:
            raise Finding(
                "public source scan refused: " + json.dumps(findings, sort_keys=True)
            )
        locked = subprocess.run(
            ["uv", "lock", "--offline", "--directory", str(stage)],
            env=dict(os.environ, UV_PYTHON_DOWNLOADS="never"),
            capture_output=True,
            text=True,
            check=False,
            timeout=120,
        )
        if locked.returncode:
            stage.rename(output)
            (output / "lock-diagnostic.txt").write_text(
                selected.diagnostic(locked.stdout + locked.stderr)
            )
            raise Refusal(
                "the selected workspace lock requires the uv resolution cache. The output directory contains the preparation and diagnostics."
            )
        # Generate install requirements from the selected workspace lock.
        done = subprocess.run(
            [
                "uv",
                "export",
                "--offline",
                "--frozen",
                "--no-dev",
                "--no-emit-workspace",
                "--no-header",
                "--directory",
                str(stage),
                "--package",
                "nmemory",
                "--package",
                "nspawn",
                "--package",
                "nbrowser",
            ],
            env=dict(os.environ, UV_PYTHON_DOWNLOADS="never"),
            capture_output=True,
            text=True,
            check=False,
            timeout=120,
        )
        if done.returncode:
            stage.rename(output)
            (output / "export-diagnostic.txt").write_text(
                selected.diagnostic(done.stdout + done.stderr)
            )
            raise Refusal(
                "uv could not export the source lock. Prepare the approved workspace lock before export"
            )
        (stage / "requirements.txt").write_text(done.stdout)
        for path in stage.rglob("*"):
            if path.is_symlink():
                try:
                    path.resolve(strict=True).relative_to(stage)
                except (ValueError, OSError, RuntimeError) as error:
                    raise Refusal("an exported link has no selected target") from error
        missing = selected.local_links(stage)
        if missing:
            raise Refusal("public local links are missing: " + json.dumps(missing))
        findings = policy.scan(stage)
        if findings:
            raise Finding(
                "public source scan refused: " + json.dumps(findings, sort_keys=True)
            )
        files = selected.inventory(stage)
        manifest: dict[str, Any] = {
            "schema": SCHEMA,
            "component": "plugin",
            "primary_module": None,
            "license": selected.LICENSE,
            "members": members,
            "packages": packages,
            "version": native["version"],
            "source_lock_sha256": hashlib.sha256(
                (source / "uv.lock").read_bytes()
            ).hexdigest(),
            "lock_sha256": hashlib.sha256((stage / "uv.lock").read_bytes()).hexdigest(),
            "files": files,
            "clients": profile["clients"],
            "platforms": profile["platforms"],
            "optional_integrations": profile["optional_integrations"],
            "digest": hashlib.sha256(
                json.dumps(files, sort_keys=True).encode()
            ).hexdigest(),
        }
        write_json(stage / "source-manifest.json", manifest)
        findings = policy.scan(stage)
        if findings:
            raise Finding(
                "public source scan refused: " + json.dumps(findings, sort_keys=True)
            )
        stage.rename(output)
    return manifest


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="plugin.py export", description=__doc__)
    parser.add_argument("verb", choices=["export"])
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = export(args.source_root, args.output)
    except Finding as error:
        print(f"EXPORT FINDING: {error}", file=sys.stderr)
        return 3
    except (Refusal, ValueError, KeyError, TypeError) as error:
        print(f"EXPORT REFUSED: {error}", file=sys.stderr)
        return 2
    except (OSError, subprocess.SubprocessError):
        print(
            "EXPORT OPERATIONAL: source or dependency setup is unavailable",
            file=sys.stderr,
        )
        return 1
    print(json.dumps({"digest": result["digest"], "members": result["members"]}))
    return 0
