# SPEC.md — nSOUL public plugin specification

This is the executable conformance surface for the nSOUL public distribution.
Authority order is `decisions.md`, then `PRD.md`, then this document. The
derived operating canon is `NOTT.md`.

**Normative scope.** Sentences carrying **MUST**, **MUST NOT**, or **NEVER** are
normative. A property is repo-gated only when this section names its shipped
enforcer; all kernel claims remain future-rung boundaries.

## 1. Shipped surface

The v2 package contains:

- eleven skills under `skills/`;
- six bounded agents under `agents/`;
- four registered Claude Code hook events through `hooks/hooks.json`;
- one product canon, one product law, this specification, and the closed
  glossary in `decisions.md`;
- two optional MCP declarations whose server implementations are external.

The package contains no MCP server executable. A manifest, launcher, or README
MUST NOT describe either external service as bundled; the manifest gate binds all
three inventory classes to closed path sets, and documentation checks in
`tools/public-release-check.sh` enforce the public wording.

## 2. Core and optional capabilities

Skills, agents, and hooks form the usable plugin core. nMEMORY and nBrowser are
optional capabilities with separate failure domains
(`d9-memory-split-core-capability`). A capability outage NEVER turns a core
method into a false success claim.

Each MCP declaration points to a plugin-local launcher that resolves its
documented override before one executable name on `PATH`. The adapter boundary
is owned by `PRD.md` §7. `tests/mcp-launchers-test.sh` observes precedence,
missing or invalid rejection, argument forwarding, recursion defense, and child
exit-status propagation for each launcher against controlled local executables.
Its digest literals are candidate-local regression guards, not independent
provenance. `tests/gates-red-test.sh` proves an install-capable nMEMORY mutation
reaches its sink before the digest guard rejects it, and separately requires the
behavior test to reject an nBrowser status-swallowing mutation even after its
local digest is updated. A separate-session exact-tree review supplies the
current independence basis. None of these checks attests to an external MCP
implementation or arbitrary host behavior.

## 3. Epistemic lanes

`PRD.md` §1 owns model-output authority, `decisions.md` owns the closed
kernel-lane meanings, and `PRD.md` §3 owns the session claim boundary. This
package ships no kernel and exposes only observed verification.

## 4. Hook privacy and failure behavior

The default `Stop` hook writes no state. When `NOTT_VOICE_LINT=on`, it implements
the metadata-only persistence boundary owned by `PRD.md` §7: timestamp, mode,
finding class, and bounded retention. An oversized payload is discarded without
state or block output because its recursion flag cannot be authenticated after
truncation; availability wins over an unprovable voice-lint decision.
A valid payload with duplicate top-level recursion flags is equally ambiguous
and follows the same no-output, no-state path before dependency discovery.

The public hook does not implement automatic handoff or write an integration
stamp. Hook output contains at most one block decision.
`tests/manifest-test.sh` binds every registered event to the plugin-local hook
command, while `tests/hooks-test.sh` exercises the shipped script's behavior.
The negative gate rejects a registration bypass and first proves an out-of-state
write can reach its isolated sink before the candidate-local digest guard rejects
that script mutation. Independent review, not the mutable digest literal,
provides provenance for the exact candidate tree.

## 5. Runtime dependencies and portability

`d26-declared-runtime-dependencies` owns the runtime dependency contract.
`release/public-contract.json` declares the commands required by the plugin hook,
its opt-in voice lint, and each release-check mode. The nMEMORY and nBrowser
executables remain declared separately as optional external integrations.

`tools/public-release-check.sh` reads its mode-specific command set from that
contract before inspecting candidate content. A missing declared command fails
closed. The Gitleaks version is also pinned in the contract and a mismatch fails
before scanning. `tests/manifest-test.sh` binds the exact schema and dependency
sets; `tests/gates-red-test.sh` materializes a missing command and a mismatched
pinned version and requires both to be rejected for those reasons.

The required hook utilities fail closed at their call sites. Optional voice lint
reports a block without writing state when an additional declared utility is
missing. The external MCP launchers reject an absent executable or invalid
override before fallback. These checks establish availability and declaration;
the repository does not inspect or prohibit implementation languages.

The public tree and its reachable history MUST NOT contain a NUL-bearing binary
file. Text-only custody prevents binary payloads from bypassing hygiene and
secret scans; `tools/hygiene-lint.sh` and
`tools/history-hygiene.sh` enforce the boundary.

Public path components MUST use printable ASCII and MUST be case-unique within
each Git tree. `tools/history-hygiene.sh` reads raw reachable tree bytes with
replacement resolution disabled for every namespace, rejects the default
replacement-ref namespace, ambient Git repository selectors, legacy grafts,
object alternates, Git info attributes, and logical refs that do not peel to a
commit. It rejects non-canonical modes, order, and paths, then materializes every
commit-tree blob without applying export or diff attributes. Authoritative
history traversal disables Git commit-graph acceleration, and a checksum-valid
forged-graph control must still expose its hidden parent. The negative gate also
materializes case collisions, a case-variant `.git`, non-printable paths, and
non-canonical entry order from raw bytes.

Runtime scripts target POSIX `sh`; gate orchestration targets Bash. ShellCheck
is required by the full release checklist and the Linux CI job; parsers and
behavior tests run on Linux and macOS. A local run proves only the current host.

## 6. Repository gates

- `release/public-contract.json` is the runtime-dependency source;
  `tools/public-release-check.sh` consumes its mode-specific sets,
  `tests/manifest-test.sh` binds the schema, and `tests/gates-red-test.sh`
  supplies the missing-command and pinned-version differentiators.
- `tools/doc-lint.sh` rejects undeclared normative scope and hedges inside
  normative paragraphs across every Markdown document.
- `tools/citation-lint.sh` enforces the citation boundary owned by `PRD.md` §7
  for recognized local inline links, reference-definition targets, inline-code
  file citations, decision slugs, and bare decision ids. Directory-shaped
  inline-code projections are checked only as navigation references. Its
  deterministic scanner recognizes same-line inline destinations and reference
  definitions; independent review covers Markdown forms outside that finite
  grammar.
- `tools/hygiene-lint.sh` rejects the declared private host-root, host/address,
  and extraction-history signatures; Slack-shaped operational identifiers with
  prefixes A, B, C, D, E, F, G, S, T, U, or W and at least nine uppercase
  alphanumeric characters; binary files; symlinks; and non-regular repository
  nodes. Exact public vocabulary is exempt only in its declared license,
  manifest, gate implementation, test, inventory, or conventional-document path
  context; the negative gate rejects the same tokens anywhere else.
- `tools/history-hygiene.sh` applies current public hygiene and secret scanning
  to every reachable commit tree.
- `tests/hooks-test.sh` proves root-session and subagent canon context, hook
  output, opt-in persistence, bounded state, recursive-Stop safety including
  raw-byte-counted bounded input and oversized input, and the absence of
  automatic handoff.
- `tests/mcp-launchers-test.sh` observes the digest-bound adapter behavior
  described in §2 against controlled local fixtures.
- `tools/public-release-check.sh` binds all candidate-relative reads to a
  pinned current-directory root and verifies that its original path still names the
  same filesystem object at close. It composes the gates, their negative controls,
  manifest validation, current and raw materialized commit-tree secret scans, a
  defense-in-depth merge-parent diff scan, raw commit/tag/ref/path metadata
  scans, direct-versus-symbolic ref and Git-control-state pinning, and isolated
  cold-install plus first-release removal probes. The client lifecycle requires
  both installed-plugin and marketplace state to read back empty.
- `.github/workflows/public-release.yml` runs the repository-owned subset on
  every push and pull request for both supported operating-system families.

A green local full checklist is observed verification for the candidate bytes;
it is NEVER proof that a public repository, remote CI run, or installation on a
different host exists.

## 7. Future rung

The sovereign trust spine does not ship here. Until it exists, kernel-derived
closure, witnessed outcomes, and journal guarantees are boundaries named by the
law and claimed by no nSOUL component.
