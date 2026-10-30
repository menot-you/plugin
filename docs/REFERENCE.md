# NOTT plugin reference

## Packaging and activation commands

Source: [plugin.py](../scripts/plugin.py), `VERBS`.
Run each command from the public repository root.
Use `python3 scripts/plugin.py VERB --help` for the complete options.

| Command | Inputs and result |
| --- | --- |
| `python3 scripts/plugin.py build` | `--source DIR --output DIR --runtime-root DIR [--source-commit SHA]`, build native views |
| `python3 scripts/plugin.py verify` | Bundle path, check content integrity |
| `python3 scripts/plugin.py admit` | Bundle path, check admission |
| `python3 scripts/plugin.py deliver` | `<commit> <checkout> [--base COMMIT ...]`, write a commit's plugin files into a checkout and keep its local edits |
| `python3 scripts/plugin.py show` | `[--source DIR]`, source hook matrix with no native activation proof |
| `python3 scripts/plugin.py install` | `--bundle DIR --client CLIENT --config-root DIR --receipt FILE [--runtime-root DIR] [--memory-bootstrap FILE] [--previous-law FILE]` |
| `python3 scripts/plugin.py rollback` | Private receipt path, restore owned activation state |
| `python3 scripts/plugin.py export` | `--source-root DIR --output DIR`, create selected public source |

[package.py](../scripts/plugin/package.py) owns the `build`, `verify`, `admit`, and `show` verbs.
[install.py](../scripts/plugin/install.py) owns activation, receipt checks, and rollback.
[export.py](../scripts/plugin/export.py) owns source projection.
A command or generated view does not establish installed native behavior.
Public full-plugin activation supports `claude` and `codex`.
It requires both `--runtime-root` and `--memory-bootstrap`.
The receipt records native registration, runtime binding, memory binding, and readiness gaps.
Claude uses `plugin marketplace add`, `plugin install --scope user`, and `plugin list --json`.
Restoration uses `plugin uninstall --scope user` and `plugin marketplace remove`.
Codex keeps its existing native registry path.
AGY full-plugin activation remains refused.
Restore an older activation before replacement. A legacy-law option does not bypass public admission.

## Bundled MCP and CLI interfaces

Each bundled service keeps its own executable, schemas, and tool catalog.
The plugin does not add a fourth MCP server.

| Component | Complete reference | Primary declaration |
| --- | --- | --- |
| nMEMORY | [Tools, CLI, and optional evaluation CLI](components/nmemory/REFERENCE.md) | [tools_schema.json](../packages/nmemory/nmemory/tools_schema.json) |
| nSPAWN | [Tools and CLI](components/nspawn/REFERENCE.md) | [mcp.py](../packages/nspawn/nspawn/mcp.py) |
| nBROWSER | [Tools and CLI](components/nbrowser/REFERENCE.md) | [mcp_server.py](../packages/nbrowser/nbrowser/mcp_server.py) |

## Law, routes, and native views

[NOTT.md](../NOTT.md) owns universal authority and working rules.
The [skills](../skills/execute/SKILL.md) provide task-specific routes.
The [README matrix](../README.md#native-hook-coverage) lists generated client bindings and their proof limits.
The [MCP manifest](../.mcp.json) declares the service configuration.
Native manifests and source resources travel with the selected plugin bundle.
Client event names and payloads differ. Do not infer equal enforcement from a shared route name.

The [runbook](RUNBOOK.md) covers native registration, first use, and restoration.


## Review delivery readback

The lead runs installation and live acceptance after merge. The builder does
not install a candidate. Install nSPAWN first with
`bash tools/mcp.sh install nspawn`. Its CLI and MCP doors share one ledger.

Deliver the plugin only after its merge is an ancestor of HEAD in the target
checkout. Check with `git -C <checkout> merge-base --is-ancestor <merge> HEAD`.
Then run `python3 plugin/scripts/plugin.py deliver <merge> <checkout>` from
a clean source clone. Autoupdate can expose new hooks before a manual delivery;
keep the nSPAWN install ahead of plugin activation. Use a revert PR for durable
rollback. A stopgap delivery of the parent can dirty the checkout and stop
autoupdate until the revert lands. Do not discard local edits to cure that stop.

Coverage excludes nSPAWN children whose `~/plugins/nott` bundle still comes
from the old cutover commit. They need a cutover, as do NOTT.app nodes. Codex
and AGY leads have no new counted-hook binding. Use a repository-qualified PR
lineage and never reuse it for a later PR. A cure round keeps its subject.
A new plan or spec version uses a new version suffix. Counts measure the review
history. They never decide when to stop or merge.

Before the plugin merge, measure the named readers' types through
`nspawn session list` and `nspawn session show <vendor> <id>`. Do not read
vendor records directly. Record missing candidate lines, named reviewer
dispatches and other candidate-bearing calls. Include a miss count for inline
round messages and messages with no candidate signal. An inline
`Candidate: <40 or 64 hex>` token is refused at uncounted doors. A message
with no candidate signal to a reader of an unknown type remains uncounted.
The journal types of the historical readers and delivery by unnamed agent id
need live evidence; this build does not claim to have measured them.

In a fresh live client, check that each new head on one `acceptance/` subject
is admitted and counted, including heads beyond the former limit. Replay the
same head and check that the count stays unchanged. A refusal of a head beyond
the former limit means that the installed nSPAWN predates the current rule.
Report that gap, not a route failure. Do not bypass the review door. Exercise
the recorded inline form in SendMessage and check that it is refused. Read the
delivered file bytes and the hook binding after these calls. These are live
checks for the lead, not builder proof.
