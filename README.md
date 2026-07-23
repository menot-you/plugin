# nSOUL

![nSOUL mark](assets/nsoul-mark.svg)

**One intent into one proof-bound deliverable.**

nSOUL is the public distribution of NOTT, an engineering peer that holds one
active result, chooses its method internally, acts inside explicit authority,
and limits every claim to observed verification. The distribution name is
**nSOUL**, the installed plugin id is **`nott`**, and the product voice is
**NOTT**.

## What ships

- 11 engineering skills: readback, brainstorm, ratify, plan, routine, design,
  debug, review, security, ship, and handoff;
- 6 bounded agents: planner, researcher, executor, reviewer, debugger, and
  tester;
- 4 registered Claude Code hooks for orientation, prompt discipline, post-edit
  proof, and an opt-in local voice lint;
- optional nMEMORY and nBrowser MCP adapters.

The MCP server implementations are **not bundled**. Their launchers resolve an
explicit executable override or one command on `PATH` and reject absence with a
non-zero exit. The private experimental lab is not part of nSOUL.

## Local use

From a checkout, validate and install through a disposable Claude marketplace.
This avoids loading the checkout's project MCP projection as a duplicate:

```sh
export CLAUDE_CONFIG_DIR="$(mktemp -d)"
claude plugin validate --strict .
claude plugin marketplace add "$(pwd -P)" --scope user
claude plugin install nott@nsoul --scope user
claude plugin details nott@nsoul
```

Codex discovers the plugin through its marketplace manifest. Use a disposable
profile for a local install test:

```sh
export CODEX_HOME="$(mktemp -d)"
codex plugin marketplace add "$(pwd -P)"
codex plugin add nott@nsoul
codex plugin list --marketplace nsoul --json
```

Delete the disposable profile directories when the probes finish.

After the repository exists publicly, install through its marketplace:

```text
claude plugin marketplace add menot-you/nsoul
claude plugin install nott@nsoul

codex plugin marketplace add menot-you/nsoul
codex plugin add nott@nsoul
```

Publication and remote installation are separate release actions; a green
local candidate does not claim either one happened.

## Optional MCP integrations

| Server | Default executable | Override |
|---|---|---|
| nMEMORY | `nmemory` on `PATH` | `NOTT_NMEMORY_BIN` |
| nBrowser | `nbrowser-mcp` on `PATH` | `NOTT_NBROWSER_BIN` |

An override must name an executable file. An invalid override is rejected even
when a fallback exists on `PATH`; this prevents a misconfigured explicit choice
from silently reaching a different binary.

## Privacy defaults

The default hooks persist no prompt, response, or session identifier. Voice
lint is disabled unless `NOTT_VOICE_LINT=on`. When enabled, it stores only a
timestamp, mode, and finding classes, retaining at most 200 local records. See
`PRIVACY.md` for the exact state boundary and deletion procedure.

## Honest boundary

nSOUL ships methods, roles, hooks, adapters, and repository gates. It does not
ship a sovereign trust spine, an independent witness kernel, an nMEMORY server,
or an nBrowser server. A session can report observed verification; it cannot
self-issue kernel closure.

## Verify the candidate

```sh
bash tools/public-release-check.sh full
```

The full gate is offline and fail-closed on missing declared local validators.
It checks tree and history hygiene, citations, normative docs, manifests, shell,
hook privacy, MCP launcher behavior, secret-detector output, and isolated client
install/discovery. The CI subset is documented in `RELEASE-CHECKLIST.md`.

## Documentation

- `NOTT.md` — operating canon.
- `PRD.md` — product law.
- `SPEC.md` — executable public contract.
- `decisions.md` — closed glossary and public decision slugs.
- `RUNBOOK.md` — installation, diagnostics, upgrade, and removal.
- `SECURITY.md` — security scope and private reporting.
- `PRIVACY.md` — local data behavior.
- `CONTRIBUTING.md` — change and review contract.

Licensed under AGPL-3.0-only. See `LICENSE` and `NOTICE`.
