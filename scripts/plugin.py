#!/usr/bin/env python3
"""The plugin's one entry point: `plugin.py <verb> ...` (D18).

build, verify, admit, show and deliver are the packager's (`plugin/package.py`);
install and rollback are the installer's (`plugin/install.py`). Each module is loaded
from its file under its own name, so no table another loader put on the import path
wins.
"""

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

sys.dont_write_bytecode = True

VERBS = {
    "build": "package",
    "verify": "package",
    "admit": "package",
    "show": "package",
    "deliver": "package",
    "install": "install",
    "rollback": "install",
    "export": "export",
}
USAGE = "usage: plugin.py {build,verify,admit,show,deliver,install,rollback,export} ..."


def _module(name: str) -> ModuleType:
    path = Path(__file__).resolve().parent / "plugin" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(f"nott_plugin_{name}", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main(argv: list[str]) -> int:
    owner = VERBS.get(argv[0]) if argv else None
    if owner is None:
        print(USAGE, file=sys.stderr)
        return 2
    result: int = _module(owner).main(argv)
    return result


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
