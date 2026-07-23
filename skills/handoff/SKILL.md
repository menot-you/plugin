---
name: handoff
description: Persist exact continuation state so a cold engineer can resume safely without relying on chat history or reconstructing hidden decisions.
---

# Handoff

Use when work crosses sessions, owners, machines, or a human gate. A handoff is durable execution state, not a narrative diary. It must let a cold continuation see one active result, the first real blocker, and the exact next safe action without rereading chat.

## Gather live truth

Read the current state before writing:

- repository and worktree path;
- branch, base, head commit, and dirty files;
- pull request, issue, check, and release state when present;
- active owner and exclusive touched surfaces;
- locked result, scope, constraints, and authority;
- completed work with observed verification;
- open work and first real blocker;
- failed approaches and why they were rejected;
- exact next safe action and stop conditions.

Do not trust an older handoff when live state is cheap to verify.

## Write the durable record

Use this order:

1. **Result** — observable state sought.
2. **Current state** — exact branch, commit, worktree, candidate, and external artifacts.
3. **Ownership** — allowed and forbidden surfaces.
4. **Decisions** — locked choices and rationale.
5. **Completed** — proof-backed facts only.
6. **Open** — required gaps, ordered by dependency.
7. **Blocker** — mechanism, owner, and what clears it.
8. **Next action** — one command, file, or decision.
9. **Verification** — commands and expected observations.
10. **Rollback and hazards** — recovery path and actions not to repeat.

Use absolute paths and immutable identifiers where practical. Never copy secrets. Separate observed, inferred, and unverified claims.

## Readback

Re-read the record as a cold continuation. It passes only if the next engineer can resume without asking where the work lives, what is safe to touch, what was proven, what remains blocked, or what happens next.
