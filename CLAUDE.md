# CLAUDE.md — NOTT Plugin

Repository contract and contributor guide for the `NOTT` plugin.
The plugin compiles the engineering law, 17 task routes, review agents, and runtime hooks into native views for Claude Code, Codex, and AGY.
Read this file before changing the law, routes, hooks, packaging scripts, or bundled packages.

## What this repository builds

The plugin turns an AI coding client into a disciplined engineering team.
It connects grounded memory (`nMEMORY`), isolated multi-provider execution (`nSPAWN`), and bounded web evidence (`nBROWSER`).

| Part | Path | Responsibility |
| --- | --- | --- |
| Engineering law | [NOTT.md](NOTT.md) | Authority boundaries, devil's-advocate premise testing, change sequence, D18 verdicts (`0/1/2/3`), and Opus + Haiku fanout discipline |
| Task routes | [skills/execute](skills/execute/SKILL.md), [skills/review](skills/review/SKILL.md) | 17 on-demand engineering routes (`security`, `readback`, `feedback`, `debug`, `quality`, `brainstorm`, `ratify`, `plan`, `fanout`, `execute`, `review`, `release`, `ship`, `reconcile`, `handoff`, `goal`, `board`, `upscale`) |
| Specialized reviewers | [review route](skills/review/SKILL.md) | Read-only witness agents (`python-reviewer`, `security-reviewer`, `silent-failure-hunter`, `pr-test-analyzer`) |
| Runtime hooks | [hooks.json](hooks/hooks.json), [system1.py](hooks/system1.py) | Client event guards (`red-first.sh`, `law-contract.sh`, `final-state.sh`, `nmemory-capture-gate.py`) and the System1 upscale hook (`system1-suggest.py`) |
| Builder and installer | [plugin.py](scripts/plugin.py), [package.py](scripts/plugin/package.py), [install.py](scripts/plugin/install.py), [export.py](scripts/plugin/export.py) | Content-addressed bundle compilation (`clients/claude`, `clients/codex`, `clients/agy`), receipt-bound installation, rollback, and public export |
| Bundled workspace packages | [nmemory](packages/nmemory/README.md), [nspawn](packages/nspawn/README.md), [nbrowser](packages/nbrowser/README.md), [system1](packages/system1/nott_system1/__init__.py) | The three MCP services, shared SQLite/socket/netdoor/System1 libraries, and deterministic memory evaluations |

## Local checks and commands

Run these commands from the repository root with the pinned Python version and `uv.lock`:

| Need | Command |
| --- | --- |
| Sync workspace dependencies | `uv sync --group dev` |
| Build native client bundle | `python3 scripts/plugin.py build --source "$PWD" --output "$PWD/.nott/bundles/dev" --runtime-root "$PWD/.venv"` |
| Check built bundle integrity | `python3 scripts/plugin.py verify "$PWD/.nott/bundles/dev"` |
| Show client hook and route bindings | `python3 scripts/plugin.py show` |
| Run plugin and public contract tests | `uv run --group dev pytest tests/test_public_documents.py tests/test_public_activation.py -q` |
| Lint and format check | `uv run ruff check .` and `uv run ruff format --check .` |
| Lockfile consistency | `uv lock --check` |

Every test runs against disposable directories and temporary SQLite stores.
Never point a test at `~/.nott/state/database` or overwrite an active client configuration without an explicit receipt.

## Architecture and code boundaries

1. **Three-layer instruction hierarchy:** keep universal judgment and authority in [NOTT.md](NOTT.md) (capped at 20,000 bytes), task-specific methods in `skills/*/SKILL.md`, and conditional procedures in `skills/*/references/*.md`. Give every rule one canonical home.
2. **Closed-loop change sequence:** repository changes follow `BRAINSTORM -> PLAN <-> PLAN REVIEW -> APPROVAL -> EXECUTION -> INTENT VALIDATION -> QUALITY -> CLEANING -> gate -> landing -> release`. For any behavior change, write and run the failing regression test (`RED`) before touching product code.
3. **Client-native event translation:** Claude Code, Codex, and AGY emit different hook event names and payloads. [package.py](scripts/plugin/package.py) projects each hook into its verified client view (`clients/claude`, `clients/codex`, `clients/agy`). Never translate a hook event across clients by similar spelling.
4. **System1 advisory hook:** `system1-suggest.py` queries System1 (`laya-nott` via `/v1/systemone` or a local loopback `/v1/chat/completions` SLM). It suggests prompt improvements and fails open when the host has no System1 endpoint.
5. **Single SQLite boundary:** all bundled services open SQLite exclusively through `nott_database.connect` ([database](packages/database/nott_database/__init__.py)).
6. **Receipt-bound installation and rollback:** [install.py](scripts/plugin/install.py) requires a verified runtime and memory bootstrap receipt, preserves unrelated user settings, and records an atomic rollback receipt.

## Working rules for agents and contributors

- Write all code comments, docstrings, commit messages, pull requests, and documentation in Simplified Technical English (ASD-STE100). Keep sentences under 25 words and use active voice.
- Never place credentials, personal host paths, or private capsule IDs in source files, fixtures, or documentation.
- Keep `NOTT.md`, `README.md`, and the hook coverage tables synchronized with `python3 scripts/plugin.py show`.

## Canonical documentation map

| Need | Canonical document |
| --- | --- |
| Product overview, hook matrix, and quickstart | [README](README.md) |
| Engineering law and authority contract | [NOTT.md](NOTT.md) |
| Documentation index and first contribution | [Docs index](docs/README.md) |
| Client views and service boundaries | [Architecture](docs/ARCHITECTURE.md) |
| Build, activation, backup, and rollback | [Runbook](docs/RUNBOOK.md) |
| Packaging CLI and bundled MCP reference | [Reference](docs/REFERENCE.md) |
| Developer toolkit and Context7/RTK setup | [Setup](docs/SETUP.md) and [setup-catalog.json](docs/setup-catalog.json) |
| Quality gates and security review | [Quality](docs/QUALITY.md) |
| Bundled service rules | [nMEMORY rulebook](packages/nmemory/RULEBOOK.md) and [nSPAWN rulebook](packages/nspawn/RULEBOOK.md) |
| Source installation and prerequisites | [Installation](docs/INSTALLATION.md) |
| Data boundaries and external processing choices | [Privacy](docs/PRIVACY.md) |
| Existing data and upgrades | [Upgrade](docs/UPGRADE.md) |
| Failure diagnosis | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| Working agreements and pull requests | [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md) |
