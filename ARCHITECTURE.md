# ARCHITECTURE — how nSOUL fits together

**Normative scope.** This document describes structure and trust boundaries. Clauses
with MUST / MUST NOT / NEVER are normative; the rest is rationale. On any conflict with
`NOTT.md` or `decisions.md`, those win.

nSOUL is a distribution boundary, not a runtime. It ships the reusable operating core of
NOTT — methods, roles, hooks, adapters, and the gates that govern them — as a plugin two
hosts (Claude Code and Codex) can load. It runs no server of its own.

## The operating loop

```
intent → readback → (plan) → act inside authority → review → close
                                                              │
                              shipped · blocked · handed back ┘
```

Every substantive turn crosses this loop. A **skill** owns each segment end to end; a
**bounded agent** executes a scoped unit inside it; a **hook** binds the turn's claims to
observed output. The loop always terminates in one of three closes — a proven result, a
named gap, or a pre-computed next action — and NEVER in an unobserved success claim.

## Layers

1. **Voice & canon.** `NOTT.md` is the constitution; `decisions.md` the closed glossary
   and decision ledger; `PRD.md`/`SPEC.md` the product law and executable contract. Every
   other artifact derives from these and cites, never restates, them.

2. **Skills (11).** Each is a `skills/<name>/SKILL.md` with a frontmatter contract. A
   skill is a method a cold agent can follow without inventing a decision. The host routes
   exactly one per intent.

3. **Agents (6).** Each is an `agents/<name>.md` charter — planner, researcher, executor,
   reviewer, debugger, tester. An agent has a narrow scope and reads back its acceptance
   before working. It MUST NOT self-certify: what a session observes is observed
   verification, never a witnessed kernel closure.

4. **Hooks (4).** Registered in `hooks/hooks.json`: orientation, prompt discipline,
   post-edit proof, and an opt-in local voice lint. Hooks are the only layer that runs on
   every turn regardless of the chosen skill. The default set persists no prompt, response,
   or session identifier.

5. **External adapters.** nMEMORY and nBrowser are declared MCP integrations, resolved by
   plugin-local launchers. A launcher resolves a documented environment override first,
   then one command on `PATH`, and rejects absence with a non-zero exit. **No MCP server
   binary is bundled** — nSOUL depends on them, it does not contain them.

## Trust boundaries

- **Host ↔ plugin.** The host loads skills, agents, and hooks from the manifest. nSOUL
  never writes host configuration by inferring internal paths; installation uses only a
  host-supported surface whose scope, cache, update, and rollback behavior is observed.
- **Plugin ↔ MCP adapter.** An adapter override MUST name an executable file; an invalid
  explicit override is rejected even when a `PATH` fallback exists, so a misconfiguration
  never silently reaches a different binary.
- **Public ↔ private.** The private experimental lab, host layout, and owner operating
  context are OUT of the distribution boundary and NEVER ship. Hygiene gates reject a
  private-context signature anywhere in the tree or history.

## The gates

`tools/public-release-check.sh` orchestrates the offline, fail-closed gate suite:
hygiene (tree + history), citation resolution, normative-document lint, manifest and
client-discovery checks, shell lint, hook-privacy proof, MCP-launcher behavior, and secret
detection. `tests/gates-red-test.sh` materializes a violation of each rule and asserts its
rejection — a gate with no red test is aspirational, so every gate ships its red.

## What nSOUL is not

It is not a trust spine and not a witness kernel. A session can prove what it observed; it
cannot derive sovereign closure. That layer (nKERNEL) is future work — until it exists,
every "kernel-enforced" claim names its current rung honestly and never borrows future
force.
