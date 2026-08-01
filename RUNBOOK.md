# nSOUL runbook

## Support boundary

nSOUL targets Claude Code and Codex on Linux and macOS. Runtime adapters use
POSIX `sh`; repository gates use Bash. Native Windows is not claimed. The core
plugin remains usable when either optional MCP integration is absent, but an
attempt to start that integration fails with an actionable diagnostic.

## Install from a local checkout

### Claude Code

Validate before loading:

```sh
export CLAUDE_CONFIG_DIR="$(mktemp -d)"
claude plugin validate --strict .
claude plugin marketplace add "$(pwd -P)" --scope user
claude plugin install nott@nsoul --scope user
claude plugin details nott@nsoul
```

Starting `claude --plugin-dir .` from the plugin checkout also loads the root
`.mcp.json` as project configuration and duplicates the MCP registrations. Use
the marketplace probe above, or start `--plugin-dir` from a different project.

### Codex

Use a disposable profile for a release probe, or add the published marketplace
to the normal profile:

```sh
export CODEX_HOME="$(mktemp -d)"
codex plugin marketplace add .
codex plugin list --marketplace nsoul --available --json
codex plugin add nott@nsoul
```

Remove the disposable directory when the probe completes.

## Configure optional MCP servers

Prefer installing the public executables on `PATH`. To bind an exact local
binary instead, set:

```sh
export NOTT_NMEMORY_BIN=/path/to/nmemory
```

The explicit path wins. It must be a regular executable file. The launchers do
not download, install, retry, or fall back to a private build tree.

Probe resolution without starting the server:

```sh
bin/nmemory-mcp --probe
```

## Voice lint

Voice lint is off by default. Enable local classification with:

```sh
export NOTT_VOICE_LINT=on
export NOTT_VOICE_LINT_MODE=warn
```

Use `block` instead of `warn` only when a rejected close should prevent the
current Stop event. An enabled lint fails closed when its local parser or state
boundary is unavailable.

State lives at `${XDG_STATE_HOME:-$HOME/.local/state}/nott/voice-lint.jsonl`.
The file contains only `ts`, `mode`, and `findings`, and retains at most 200
records.

Reset the optional state:

```sh
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/nott/voice-lint.jsonl"
```

## Diagnose

Run the full offline release gate first:

```sh
bash tools/public-release-check.sh full
```

Then isolate the relevant layer:

```sh
bash tests/hooks-test.sh
bash tests/mcp-launchers-test.sh
claude plugin validate --strict .
```

- Exit 126 from an MCP launcher means an explicit override was invalid.
- Exit 127 means no executable resolved.
- A voice-lint block naming a missing command means lint was explicitly enabled
  but cannot run safely.

## Rollback

Before public repository creation, rollback means deleting this isolated
candidate; the source checkout remains untouched. For the first published
release, rollback removes the installed plugin and marketplace from each client,
then reads back both installed-plugin and marketplace state as empty.
`tests/client-discovery-test.sh` first proves that uninstall alone leaves the
Claude marketplace visible, then observes the complete removal cycle in
disposable profiles.

## Upgrade rollback

Before an upgrade, retain the last known-good checkout or release tag and run
the full gate against the exact new bytes. Restoring that checkout alone does not roll back a client installation.
Both clients keep installed bytes in their own caches.

To roll back, resolve the previous tag into a separate checkout, verify its
declared version, then replace the user-scoped installation and read it back:

```sh
previous_checkout=/absolute/path/to/nsoul-previous

claude plugin uninstall nott@nsoul --scope user
claude plugin marketplace remove nsoul --scope user
claude plugin marketplace add "$previous_checkout" --scope user
claude plugin install nott@nsoul --scope user
claude plugin details nott@nsoul

codex plugin remove nott@nsoul
codex plugin marketplace remove nsoul
codex plugin marketplace add "$previous_checkout"
codex plugin add nott@nsoul
codex plugin list --marketplace nsoul --json
```

The readbacks must show the previous version before an upgrade rollback is
claimed. This replacement path becomes testable only after a prior public
release exists; the first-release removal path above is the currently observed
rollback.
On its next write, voice lint keeps only records matching the current
metadata-only schema and drops legacy or malformed rows; the entire diagnostic
file can instead be deleted at any time.

## Remove a published install

```text
claude plugin uninstall nott@nsoul --scope user
claude plugin marketplace remove nsoul --scope user

codex plugin remove nott@nsoul
codex plugin marketplace remove nsoul
```

Command spelling is revalidated by the release checklist against the installed
client versions before publication.
