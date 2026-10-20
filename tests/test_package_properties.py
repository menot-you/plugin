"""Inventory properties on bounded disposable trees; no native clients are started."""

import hashlib
import importlib.util
import os
import stat
import tempfile
from pathlib import Path
from types import ModuleType

import pytest
from hypothesis import example, given, settings
from hypothesis import strategies as st


@pytest.fixture(scope="module")
def packager() -> ModuleType:
    path = Path(__file__).resolve().parents[1] / "scripts/plugin/package.py"
    spec = importlib.util.spec_from_file_location("property_packager", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


EXEC_BITS = {"owner": stat.S_IXUSR, "group": stat.S_IXGRP, "other": stat.S_IXOTH}
EXECUTORS = st.frozensets(st.sampled_from(tuple(EXEC_BITS)), max_size=3)
READ_WRITE = st.sampled_from((0o600, 0o640, 0o644, 0o660, 0o664, 0o666))
RESOURCE = st.tuples(
    st.binary(max_size=1024),
    EXECUTORS,
    READ_WRITE,
    st.integers(min_value=0, max_value=3),
)


def resource_state(paths: list[Path]) -> list[tuple[bytes | str, int, int, int]]:
    """Capture content, permission mode, inode and mtime without following links."""
    return [
        (
            os.readlink(path) if path.is_symlink() else path.read_bytes(),
            path.lstat().st_mode,
            path.lstat().st_ino,
            path.lstat().st_mtime_ns,
        )
        for path in paths
    ]


# deadline=None: each example writes disposable trees to disk, so the default 200 ms
# per-example deadline measures host load (332 ms seen at load ~50), not the inventory.
@settings(max_examples=100, derandomize=True, deadline=None)
@given(st.lists(RESOURCE, min_size=1, max_size=6))
@example(resources=[(b"", frozenset({"group"}), 0o600, 3)])
def test_inventory_matches_descriptor_oracle_and_preserves_resources(
    packager: ModuleType, resources: list[tuple[bytes, frozenset[str], int, int]]
) -> None:
    # At most six 1-KiB files, six confined links and one identity file per example.
    with tempfile.TemporaryDirectory(prefix="nott-inventory-property-") as directory:
        root = Path(directory)
        expected: dict[str, dict[str, str | bool]] = {}
        paths: list[Path] = []
        for index, (data, executors, permissions, depth) in enumerate(resources):
            parent = root.joinpath(*(f"level-{number}" for number in range(depth)))
            parent.mkdir(parents=True, exist_ok=True)
            path = parent / f"resource-{index}"
            path.write_bytes(data)
            path.chmod(permissions + sum(EXEC_BITS[name] for name in executors))
            alias = root / "aliases" / f"alias-{index}"
            alias.parent.mkdir(exist_ok=True)
            relative_target = os.path.relpath(path, alias.parent)
            alias.symlink_to(relative_target)
            expected[path.relative_to(root).as_posix()] = {
                "sha256": hashlib.sha256(data).hexdigest(),
                "executable": bool(executors),
            }
            expected[alias.relative_to(root).as_posix()] = {"link": relative_target}
            paths.extend((path, alias))
        identity = root / ".nott-bundle.json"
        identity.write_bytes(b"identity is excluded from its own inventory")
        paths.append(identity)
        before = resource_state(paths)
        observed = packager.inventory(root)
        assert observed == expected
        assert list(observed) == sorted(expected)
        assert packager.inventory(root) == observed
        assert resource_state(paths) == before


@settings(max_examples=100, derandomize=True, deadline=None)
@given(
    data=st.binary(max_size=1024),
    permissions=READ_WRITE,
    executor=st.sampled_from(tuple(EXEC_BITS)),
)
@example(data=b"", permissions=0o600, executor="other")
def test_inventory_separates_content_execute_bits_and_link_target(
    packager: ModuleType, data: bytes, permissions: int, executor: str
) -> None:
    with tempfile.TemporaryDirectory(prefix="nott-inventory-change-") as directory:
        root = Path(directory)
        first, twin, alias = root / "first", root / "twin", root / "alias"
        first.write_bytes(data)
        first.chmod(0o600)
        twin.write_bytes(data)
        twin.chmod(0o600)
        alias.symlink_to("first")
        original = packager.inventory(root)
        first.chmod(permissions)
        assert packager.inventory(root) == original
        first.chmod(permissions + EXEC_BITS[executor])
        executable = packager.inventory(root)
        assert executable == {
            **original,
            "first": {"sha256": hashlib.sha256(data).hexdigest(), "executable": True},
        }
        changed = data + b"\0"
        first.write_bytes(changed)
        mutated = packager.inventory(root)
        assert mutated == {
            **executable,
            "first": {
                "sha256": hashlib.sha256(changed).hexdigest(),
                "executable": True,
            },
        }
        assert mutated["first"]["sha256"] != executable["first"]["sha256"]
        # Retarget to distinct bytes: the link binds its spelling, not a copied hash.
        alias.unlink()
        alias.symlink_to("twin")
        assert packager.inventory(root) == {**mutated, "alias": {"link": "twin"}}
        assert first.read_bytes() == changed and twin.read_bytes() == data
        assert alias.readlink() == Path("twin")


@settings(max_examples=100, derandomize=True, deadline=None)
@given(
    data=st.binary(max_size=1024),
    kind=st.sampled_from(
        ("escape", "absolute-escape", "broken", "cycle", "indirect-escape")
    ),
)
def test_unconfined_or_unresolvable_links_refuse_without_mutation(
    packager: ModuleType, data: bytes, kind: str
) -> None:
    with tempfile.TemporaryDirectory(prefix="nott-inventory-refusal-") as directory:
        scratch = Path(directory)
        root = scratch / "package"
        root.mkdir()
        outside = scratch / "outside"
        outside.write_bytes(data)
        link = root / "link"
        paths = [outside, link]
        if kind == "escape":
            target = "../outside"
        elif kind == "absolute-escape":
            target = str(outside)
        elif kind == "broken":
            target = "absent"
        elif kind == "cycle":
            target = "link"
        else:
            bridge = root / "zbridge"
            bridge.symlink_to("../outside")
            paths.append(bridge)
            target = "zbridge"
        link.symlink_to(target)
        before = resource_state(paths)
        with pytest.raises(packager.Refusal, match="escaping or broken link"):
            packager.inventory(root)
        assert resource_state(paths) == before
        assert sorted(path.name for path in root.iterdir()) == (
            ["link", "zbridge"] if kind == "indirect-escape" else ["link"]
        )
