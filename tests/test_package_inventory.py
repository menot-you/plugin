"""Package inventory resource contracts on disposable filesystem state."""

import hashlib
import importlib.util
import os
from pathlib import Path
from types import ModuleType

import pytest


@pytest.fixture
def packager() -> ModuleType:
    path = Path(__file__).resolve().parents[1] / "scripts/plugin/package.py"
    spec = importlib.util.spec_from_file_location("inventory_packager", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_fifo_is_refused_without_opening_or_removing_it(
    tmp_path: Path, packager: ModuleType
) -> None:
    fifo = tmp_path / "pipe"
    os.mkfifo(fifo)
    with pytest.raises(packager.Refusal, match="not a regular package resource: pipe"):
        packager.inventory(tmp_path)
    assert fifo.is_fifo()


@pytest.mark.parametrize("target", ["missing", "loop", "../outside"])
def test_invalid_links_are_refused_and_preserved(
    tmp_path: Path, packager: ModuleType, target: str
) -> None:
    root = tmp_path / "package"
    root.mkdir()
    (tmp_path / "outside").write_text("foreign")
    link = root / "loop"
    link.symlink_to(target)
    with pytest.raises(packager.Refusal, match="escaping or broken link: loop"):
        packager.inventory(root)
    assert os.readlink(link) == target
    assert (tmp_path / "outside").read_text() == "foreign"


def test_inventory_binds_bytes_mode_and_relative_link(
    tmp_path: Path, packager: ModuleType
) -> None:
    resource = tmp_path / "resource"
    resource.write_bytes(b"owned content")
    resource.chmod(0o644)
    (tmp_path / "alias").symlink_to("resource")
    expected: dict[str, dict[str, str | bool]] = {
        "resource": {
            "sha256": hashlib.sha256(b"owned content").hexdigest(),
            "executable": False,
        },
        "alias": {"link": "resource"},
    }
    assert packager.inventory(tmp_path) == expected
    resource.chmod(0o744)
    expected["resource"]["executable"] = True
    assert packager.inventory(tmp_path) == expected


@pytest.mark.parametrize("content", [b"", b" \n\t\r"])
def test_empty_law_is_refused_without_rewriting(
    tmp_path: Path, packager: ModuleType, content: bytes
) -> None:
    law = tmp_path / "NOTT.md"
    law.write_bytes(content)
    with pytest.raises(packager.Refusal, match="native law must contain"):
        packager.validate_law(tmp_path)
    assert law.read_bytes() == content


def test_law_limit_counts_encoded_bytes_and_accepts_exact_boundary(
    tmp_path: Path, packager: ModuleType
) -> None:
    law = tmp_path / "NOTT.md"
    limit: int = packager.MAX_RULE_BYTES
    content = ("é" * (limit // 2)).encode() + b"x" * (limit % 2)
    assert len(content) == limit
    law.write_bytes(content)
    packager.validate_law(tmp_path)
    law.write_bytes(content + b"x")
    with pytest.raises(packager.Refusal, match="native law must contain"):
        packager.validate_law(tmp_path)
    assert law.read_bytes() == content + b"x"
