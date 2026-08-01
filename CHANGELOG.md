# Changelog

## 0.3.0 — 2026-08-01

- Version realigned with the n-modules line (nMEMORY 0.3.0). This is a
  DECREASE from 2.0.0, taken deliberately so one number means one thing across
  the family; a client that orders updates by semver can read it as a
  downgrade, and that cost is accepted rather than hidden.
- Withdrew the nBrowser adapter: `bin/nbrowser-mcp` is removed, along with its
  entries in `.mcp.json`, the Codex MCP manifest, the public contract, and the
  release inventory. It shipped in 2.0.0 and is withdrawn rather than carried
  forward unproven.
- Removed the retired `assets/nsoul-mark.svg` brand mark. Every other asset is
  unchanged.

Both removals are declared in the release's strip manifest rather than left as
omissions, so the release states what it takes away from people who already
have it.

## 2.0.0 — 2026-07-22

- Established nSOUL as the public distribution of the NOTT plugin.
- Extracted the 11-skill, 6-agent core and excluded the experimental lab.
- Replaced host-bound MCP commands with plugin-local, fail-closed adapters.
- Made voice-lint persistence opt-in, metadata-only, and retention-bounded.
- Added public documentation, privacy and security contracts, behavior tests,
  release gates, and dual-client cold-discovery probes.
