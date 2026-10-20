"""Check document paths, links, and source catalogs for each public root."""

import ast
import hashlib
import importlib.util
import json
import os
import re
import shutil
from pathlib import Path
from urllib.parse import unquote, urlsplit

import pytest
import tomllib

HERE = Path(__file__).resolve()
ROOT = HERE.parents[1]
if ROOT.name == "plugin" and (ROOT.parent / "mcps/nmemory").is_dir():
    ROOT = ROOT.parent
PUBLIC = not (ROOT / "mcps/nmemory").is_dir()
MAP = ROOT / (
    "docs/export-map.json" if PUBLIC else "docs/design/public/export-map.json"
)
REPOSITORIES = {
    "nmemory": "menot-you/n-memory",
    "nspawn": "menot-you/n-spawn",
    "nbrowser": "menot-you/n-browser",
    "napple": "menot-you/n-apple",
    "plugin": "menot-you/plugin",
}
DOCUMENTS = {
    "CLAUDE.md",
    "README.md",
    "LICENSE",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "SECURITY.md",
    "SUPPORT.md",
    "CITATION.cff",
    *(
        f"docs/{name.upper()}.md"
        for name in (
            "README",
            "runbook",
            "architecture",
            "reference",
            "installation",
            "privacy",
            "upgrade",
            "troubleshooting",
            "roadmap",
            "setup",
            "quality",
        )
    ),
}
SETUP_FILES = {
    "CLAUDE.md",
    "docs/SETUP.md",
    "docs/QUALITY.md",
    "docs/setup-catalog.json",
    ".claude/context7.json",
    ".codex/config.toml",
}
TOOLKIT_REVISION = "de66fe371a49f5a4d3b521759e5c401f390b6424"
TOOLKIT_DESTINATIONS = {
    "PRODUCT.md",
    "README.md",
    "AGENTS.md",
    "CLAUDE.md",
    "docs/architecture.md",
    "docs/design.md",
    "docs/onboarding.md",
    "docs/quality.md",
    "docs/setup.md",
}
LINK = re.compile(
    r"(?<=\]\()(?P<inline><[^>\n]+>|[^\s)]+)"
    r"|(?m:^\s*\[[^]\n]+\]:\s*)(?P<reference><[^>\n]+>|[^\s]+)"
    r"|\b(?:href|src|xlink:href)=[\"'](?P<html>[^\"']+)[\"']"
)


def command_declarations(component: str) -> dict[tuple[str, str], str]:
    member = ROOT / (f"packages/{component}" if PUBLIC else f"mcps/{component}")
    tree = ast.parse((member / component / "cli.py").read_text())
    table = next(
        node.value
        for node in tree.body
        if isinstance(node, ast.AnnAssign)
        and isinstance(node.target, ast.Name)
        and node.target.id == "COMMANDS"
    )
    return {
        ast.literal_eval(key): ast.literal_eval(value.args[0])
        for key, value in zip(table.keys, table.values, strict=True)
    }


def check_local_links(root: Path, paths: list[Path]) -> None:
    for output in paths:
        if output.suffix not in {".md", ".svg", ".html"} or not output.is_file():
            continue
        for match in LINK.finditer(output.read_text()):
            url = urlsplit(match.group(match.lastgroup).strip("<>"))
            if url.scheme or url.netloc:
                continue
            target = (
                (output.parent / unquote(url.path)).resolve() if url.path else output
            )
            assert target.is_relative_to(root) and target.exists(), (output, url.path)
            if url.fragment and target.suffix == ".md":
                headings = re.findall(r"(?m)^#{1,6} (.+)$", target.read_text())
                anchors = {
                    re.sub(r"[^\w -]", "", heading.lower()).replace(" ", "-")
                    for heading in headings
                }
                assert unquote(url.fragment) in anchors, (output, url.fragment)


def check_readme_navigation(root: Path) -> None:
    text = (root / "README.md").read_text()
    for path in DOCUMENTS:
        if path.startswith("docs/"):
            assert path in text, path


def test_local_link_check_accepts_valid_and_refuses_missing_targets(
    tmp_path: Path,
) -> None:
    page = tmp_path / "README.md"
    target = tmp_path / "REFERENCE.md"
    target.write_text("# Tools\n")
    page.write_text("[Tools](REFERENCE.md#tools)\n")
    check_local_links(tmp_path, [page])
    target.unlink()
    with pytest.raises(AssertionError):
        check_local_links(tmp_path, [page])
    target.write_text("# Commands\n")
    with pytest.raises(AssertionError):
        check_local_links(tmp_path, [page])
    page.write_text("[Outside](../outside.md)\n")
    with pytest.raises(AssertionError):
        check_local_links(tmp_path, [page])


@pytest.mark.parametrize(
    "component,repository",
    [("plugin", REPOSITORIES["plugin"])] if PUBLIC else REPOSITORIES.items(),
)
def test_public_document_links_resolve_inside_the_selected_source(
    component: str,
    repository: str,
    tmp_path: Path,
) -> None:
    mapping = json.loads(MAP.read_text())
    assert repository in mapping["targets"], repository
    documents = mapping["targets"][repository]
    assert DOCUMENTS <= set(documents.values()), DOCUMENTS - set(documents.values())
    assert SETUP_FILES <= set(documents.values()), SETUP_FILES - set(documents.values())
    assert len(documents.values()) == len(set(documents.values()))
    assert documents[mapping["root_readmes"][repository]] == "README.md"
    if PUBLIC:
        for name in documents.values():
            assert (ROOT / name).is_file(), name
        check_local_links(ROOT, [ROOT / name for name in documents.values()])
        check_readme_navigation(ROOT)
        check_contributor_setup(ROOT, component)
        return
    primary = "plugin" if component == "plugin" else f"mcps/{component}"
    libraries = {
        "nmemory": ("database", "netdoor", "system1", "socket"),
        "nspawn": ("database", "system1", "socket"),
        "nbrowser": ("database", "netdoor", "spine"),
        "napple": (),
        "plugin": ("database", "netdoor", "system1", "socket", "spine"),
    }
    members = {f"libs/{name}": f"packages/{name}" for name in libraries[component]}
    if component == "plugin":
        members.update(
            {
                f"mcps/{name}": f"packages/{name}"
                for name in ("nmemory", "nspawn", "nbrowser")
            }
        )
    if component == "nmemory":
        members["mcps/nspawn"] = "packages/nspawn"
    if component in ("nmemory", "plugin"):
        members["evals/nmemory"] = "evals"
    members[primary] = ""

    def destination(source: Path) -> Path:
        relative = source.relative_to(ROOT).as_posix()
        if relative in documents:
            return tmp_path / documents[relative]
        for prefix, target in members.items():
            if relative.startswith(prefix + "/"):
                assert source.is_file(), relative
                assert source.suffix not in {".md", ".svg", ".html"} or (
                    component == "plugin"
                    and (
                        relative == "plugin/NOTT.md"
                        or relative.startswith("plugin/skills/")
                    )
                ), relative
                result = tmp_path / target / relative.removeprefix(prefix + "/")
                result.parent.mkdir(parents=True, exist_ok=True)
                result.touch()
                return result
        pytest.fail(f"No public destination for {relative}")

    for origin, target in documents.items():
        source = ROOT / origin
        assert source.is_file(), origin
        output = tmp_path / target
        assert output.resolve().is_relative_to(tmp_path)
        output.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix not in {".md", ".svg", ".html"}:
            output.write_bytes(source.read_bytes())
            continue

        def rewrite(
            match: re.Match[str],
            source: Path = source,
            origin: str = origin,
            output: Path = output,
        ) -> str:
            url = urlsplit(match.group(match.lastgroup).strip("<>"))
            if url.scheme or url.netloc or not url.path:
                return match.group()
            resolved = (source.parent / unquote(url.path)).resolve()
            assert resolved.is_relative_to(ROOT) and resolved.exists(), (
                origin,
                url.path,
            )
            selected = destination(resolved)
            relative = os.path.relpath(selected, output.parent)
            value = relative + ("#" + url.fragment if url.fragment else "")
            start, end = match.span(match.lastgroup)
            return (
                match.group()[: start - match.start()]
                + value
                + match.group()[end - match.start() :]
            )

        output.write_text(LINK.sub(rewrite, source.read_text()))

    check_local_links(tmp_path, list(tmp_path.rglob("*")))
    check_readme_navigation(tmp_path)
    check_contributor_setup(tmp_path, component)

    # Use the owning exporter after the independent link oracle.
    spec = importlib.util.spec_from_file_location(
        "public_document_layout", ROOT / "mcps/nmemory/nmemory/commands/layout.py"
    )
    assert spec is not None and spec.loader is not None
    layout = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(layout)

    def copy_document(root: Path, source: Path, stage: Path, target: Path) -> None:
        output = stage / target
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / source, output)

    layout.documents(ROOT, tmp_path, layout.read(ROOT), component, copy_document)
    first = {name: (tmp_path / name).read_bytes() for name in documents.values()}
    layout.documents(ROOT, tmp_path, layout.read(ROOT), component, copy_document)
    assert first == {
        name: (tmp_path / name).read_bytes() for name in documents.values()
    }
    check_local_links(tmp_path, list(tmp_path.rglob("*")))
    check_contributor_setup(tmp_path, component)
    for name in DOCUMENTS:
        if name.endswith(".md") and name != "README.md":
            text = (tmp_path / name).read_text()
            assert not re.search(r"(?m)^.*(?:uv|python3|cd).*mcps/", text), name


def check_contributor_setup(root: Path, component: str) -> None:
    """Check the contributor contract at its emitted paths."""
    assert not (root / "AGENTS.md").exists()
    claude_doc = (root / "CLAUDE.md").read_text()
    assert "CONTRIBUTING.md" in claude_doc and "docs/SETUP.md" in claude_doc
    catalog = json.loads((root / "docs/setup-catalog.json").read_text())
    assert catalog["project"] == component
    assert catalog["toolkit_revision"] == TOOLKIT_REVISION
    assert set(catalog["document_map"]) == TOOLKIT_DESTINATIONS
    for paths in catalog["document_map"].values():
        assert paths
        for path in paths:
            assert (root / path).is_file(), path
    decisions = catalog["decisions"]
    assert len(decisions) == len({row["component"] for row in decisions}) == 161
    assert {row["component"] for row in decisions} == set(catalog["components"])
    assert hashlib.sha256(
        "\n".join(sorted(catalog["components"])).encode()
    ).hexdigest() == (
        "298e709c6fe401255395ea729412c50859ad1179e01804d3b483142aa831f6cf"
    )
    assert len([name for name in catalog["components"] if name.startswith("T")]) == 23
    assert (
        len([name for name in catalog["components"] if name.startswith("prompt.")])
        == 14
    )
    assert (
        len([name for name in catalog["components"] if name.startswith("template.")])
        == 46
    )
    assert (
        len([name for name in catalog["components"] if name.startswith("machine.")])
        == 15
    )
    for row in decisions:
        assert row["project"] == component
        for key in (
            "need",
            "observed_state",
            "action_or_existing_equivalent",
            "scope",
            "dependencies",
            "risk",
            "validation",
            "blocker",
            "status",
        ):
            assert key in row, (row["component"], key)
        assert row["status"] in {
            "verified",
            "configured without execution",
            "reused equivalent",
            "inapplicable",
            "blocked",
        }
        assert set(row["observed_state"]) == {
            "installed",
            "configured",
            "loaded",
            "observed",
        }
        if row["status"] == "inapplicable":
            assert row["blocker"] is None
        if row["blocker"]:
            assert row["blocker"]["cause"] and row["blocker"]["next_action"]
    setup = (root / "docs/SETUP.md").read_text()
    for number in range(1, 23):
        assert len(re.findall(rf"(?m)^\| {number:02d} \|", setup)) == 1
    assert "--mcp-config .claude/context7.json" in setup
    assert "rtk proxy" in setup
    quality = (root / "docs/QUALITY.md").read_text()
    assert TOOLKIT_REVISION in quality and "13-security-review.md" in quality
    claude = json.loads((root / ".claude/context7.json").read_text())
    codex = tomllib.loads((root / ".codex/config.toml").read_text())
    endpoint = "https://mcp.context7.com/mcp"
    assert claude == {"mcpServers": {"context7": {"type": "http", "url": endpoint}}}
    assert codex == {"mcp_servers": {"context7": {"url": endpoint}}}
    for name in SETUP_FILES:
        text = (root / name).read_text()
        assert not re.search(
            r"/(?:home|Users|var/tmp|data/repos|guara|nott)/|\bcap-\d+\b"
            r"|github[.]com/menot-you/pynott|NOTT_DATABASE_DIR"
            r"|gh[pousr]_[A-Za-z0-9]{30,}|sk-(?:live-|proj-)?[A-Za-z0-9_-]{24,}"
            r"|-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----",
            text,
        ), name
    for name in ("CLAUDE.md", "docs/SETUP.md", "docs/QUALITY.md"):
        headings = re.findall(r"(?m)^#{1,6} .+$", (root / name).read_text())
        assert len(headings) == len(set(headings)), name


@pytest.mark.parametrize("component,repository", REPOSITORIES.items())
def test_contributor_sources_and_native_runtime_are_separate(
    component: str,
    repository: str,
) -> None:
    if PUBLIC:
        pytest.skip("The source map belongs to the producer workspace.")
    documents = json.loads(MAP.read_text())["targets"][repository]
    member = "plugin" if component == "plugin" else f"mcps/{component}"
    assert documents.get(f"{member}/CLAUDE.md") == "CLAUDE.md"
    assert "AGENTS.md" not in documents.values()
    prefix = f"{member}/docs"
    for name in (
        "SETUP.md",
        "QUALITY.md",
        "setup-catalog.json",
    ):
        assert f"{prefix}/{name}" in documents
    for name in ("plugin/.mcp.json", "plugin/mcp_config.json"):
        assert "context7" not in json.loads((ROOT / name).read_text())["mcpServers"]


def test_spawn_roster_template_is_available_without_plugin_arguments(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    if PUBLIC:
        path = ROOT / "templates/nott/spawn.toml"
    else:
        mapping = json.loads(MAP.read_text())["targets"]
        for component in ("nmemory", "nspawn", "plugin"):
            assert (
                mapping[REPOSITORIES[component]]["templates/public/spawn.toml"]
                == "templates/nott/spawn.toml"
            )
        path = ROOT / "templates/public/spawn.toml"
    from nspawn.owner_roster import Roster

    monkeypatch.setenv("HOME", str(tmp_path))
    roster = Roster.read(path)
    assert {provider.kind for provider in roster.providers} == {"claude", "codex"}
    assert not roster.defaults.args
    for provider in roster.providers:
        alias = "example-" + provider.kind
        assert provider.discovered_accounts() == [alias]
        assert not provider.args
        assert not provider.auth_env and provider.secrets is None
        assert set(provider.accounts) == {alias}
    assert "$PLUGIN" not in path.read_text()


# The public plugin carries no nAPPLE package: its reference ships in n-apple.
@pytest.mark.parametrize(
    "component", ("nmemory", "nspawn", "nbrowser", *(() if PUBLIC else ("napple",)))
)
def test_component_reference_covers_source_declarations(component: str) -> None:
    member = ROOT / (f"packages/{component}" if PUBLIC else f"mcps/{component}")
    reference = (
        ROOT
        / (
            f"docs/components/{component}/REFERENCE.md"
            if PUBLIC
            else f"mcps/{component}/docs/REFERENCE.md"
        )
    ).read_text()
    for (noun, verb), synopsis in command_declarations(component).items():
        arguments = (synopsis or "None").replace("|", "\\|")
        assert f"| `{component} {noun} {verb}` | `{arguments}` |" in reference, (
            component,
            noun,
            verb,
        )
    if component == "nmemory":
        schema = json.loads((member / "nmemory/tools_schema.json").read_text())
        names = {tool["name"] for tool in schema}
    else:
        path = {
            "nspawn": "nspawn/mcp.py",
            "nbrowser": "nbrowser/mcp_server.py",
            "napple": "napple/server.py",
        }[component]
        source = (member / path).read_text()
        names = set(re.findall(r'["\'](' + component + r'_[a-z_]+)["\']', source))
    listed = set(re.findall(r"`(" + component + r"_[a-z_]+)`", reference))
    assert listed == names, (names - listed, listed - names)


def test_plugin_reference_covers_packaging_verbs() -> None:
    source = ROOT / ("scripts/plugin.py" if PUBLIC else "plugin/scripts/plugin.py")
    tree = ast.parse(source.read_text())
    table = next(
        node.value
        for node in tree.body
        if isinstance(node, ast.Assign)
        and any(
            isinstance(target, ast.Name) and target.id == "VERBS"
            for target in node.targets
        )
    )
    verbs = set(ast.literal_eval(table))
    reference = ROOT / ("docs/REFERENCE.md" if PUBLIC else "plugin/docs/REFERENCE.md")
    listed = set(
        re.findall(r"`python3 scripts/plugin.py ([a-z]+)`", reference.read_text())
    )
    assert listed == verbs
