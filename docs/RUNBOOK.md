# NOTT plugin runbook

Use the law, skills, and native client view to carry one result through implementation and proof.
The plugin connects nMEMORY, nSPAWN, and nBROWSER. It grants no account access by installation alone.

## Setup and configuration

Read [installation](INSTALLATION.md) and [privacy](PRIVACY.md).
Use the Python version and root lockfile from the public repository.
Run from its root:

```bash
uv sync --group dev
python3 scripts/plugin.py build --source "$PWD" --output "$PWD/.nott/bundles/first" --runtime-root "$PWD/.venv"
python3 scripts/plugin.py verify "$PWD/.nott/bundles/first"
python3 scripts/plugin.py show
```

Use a new output directory for each bundle.
The bundle emits separate `clients/claude`, `clients/codex`, and `clients/agy` views.
The bundle manifest binds the selected source content.
The [packager](../scripts/plugin/package.py) defines the build and admission checks.
A generated view does not prove native activation or equal client behavior.

Native clients need their own authentication.
Memory needs its store and explicit processing choices.
Dispatch needs a private roster and an admitted provider.
Browser operations need the browser runtime and host prerequisites.
Search and semantic code search remain optional integrations with separate credentials.
Use the bundled component runbooks:
[nMEMORY](components/nmemory/RUNBOOK.md), [nSPAWN](components/nspawn/RUNBOOK.md), and [nBROWSER](components/nbrowser/RUNBOOK.md).

For public Claude activation, create the project's memory bootstrap receipt first:

```bash
.venv/bin/nmemory project bootstrap --root /absolute/project --project example --client claude
python3 scripts/plugin.py install --bundle "$PWD/.nott/bundles/first" --client claude   --config-root /absolute/project/.claude --receipt /absolute/private/activation.json   --runtime-root "$PWD/.venv" --memory-bootstrap /absolute/project/.nott/nmemory/bootstrap.json
```

Use owned absolute paths. Keep the receipt private.
The [installer](../scripts/plugin/install.py) checks bootstrap identity and preserves unrelated client settings.
Native login, hook trust, and the loaded catalog remain separate readiness inputs.
The helper registers the full Claude plugin through the native marketplace and plugin commands.
It binds all MCP commands and hooks to the installed runtime and project memory launcher.
Repeat the same command to check the owned registration.
The wizard uses this check when you repeat a plugin installation.

Start Claude with the same configuration root:

```bash
CLAUDE_CONFIG_DIR=/absolute/project/.claude claude
```

For Codex, use `--client codex` in both setup commands and `/absolute/project/.codex` as the configuration root.
Start Codex with `CODEX_HOME=/absolute/project/.codex codex`.
AGY full-plugin activation remains refused.
A successful registration does not prove a loaded MCP catalog or an authenticated account.

## First useful result

Start a fresh native session in the configured synthetic project.
Inspect its loaded plugin, skills, and MCP catalog.
Ask the agent to recover project context from nMEMORY.
Give it one bounded synthetic-file correction and an explicit expected result.
Check that it records the result and uses the required review and proof boundaries.
Read the changed file and its focused check yourself.
Use the memory runbook's synthetic round trip to check persistence in a new session.
The [README hook matrix](../README.md#native-hook-coverage) names source bindings and proof limits.
Hooks and Markdown do not create a security boundary by themselves.

## Operation and failure diagnosis

`show` reports source client bindings. `verify` checks a built bundle's integrity.
`admit` checks the declared bundle and host inputs.
A missing model login differs from a missing System1 route.
A missing MCP registration differs from a refused tool call.
Read the named component error before changing configuration.
Do not remove an account home or unrelated plugin to resolve a duplicate registration.
Read [troubleshooting](TROUBLESHOOTING.md).

## Backup and restoration

Keep the previous bundle, runtime, configuration, and private activation receipt.
Back up nMEMORY and nSPAWN through their snapshot commands.
Preserve the browser vault with its key if you configured login profiles.
Use the component runbooks for data restoration.

Restore an activation with its receipt:

```bash
python3 scripts/plugin.py rollback /absolute/private/activation.json
```

Rollback restores only owned state and refuses ambiguous later changes.
A public Claude or Codex receipt also restores its native registration.
Other installation paths can require a separate native operation.
Preserve unrelated client settings.
Start a fresh session after restoration.
Read the loaded version and MCP catalog. Complete one known memory read.
A rollback command alone does not prove that the previous plugin is active.
