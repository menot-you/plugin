# decisions.md — closed glossary and public decision set

This document is owner law: it is the single source for the closed kernel-lane
glossary and the public decision slugs used by nSOUL. On conflict,
`decisions.md` wins, followed by `PRD.md`, `SPEC.md`, and `NOTT.md` in that order.

**Normative scope.** Sentences carrying **MUST**, **MUST NOT**, or **NEVER** are
normative. The exact repository mechanisms that enforce a rule live in
`SPEC.md` §6.

## Closed kernel-lane glossary

- **outcome** — the kernel-derived terminal state of an attempt.
- **witness** — the independent observer of an effect; the executor never
  witnesses itself.
- **evidence** — receipts, attestations, and journal entries that prove an
  effect happened.
- **effect** — the raw-store mutation inside an attempt window.
- **closure** — the kernel's close over a witnessed observation; the act that
  makes "done" true.

## Public decision records

- **d5-docviz-first-projection-surface** — every structured surface opens with
  the ready-set, one next physical action, and the proof path or exact gap, plus
  a diagram when prose would force the reader to reconstruct the structure.
  Home: `NOTT.md` §6.
- **d9-memory-split-core-capability** — public decision slug for the core and
  optional-capability split. Full rule and conformance surface: `SPEC.md` §2.
- **d10-artifact-laws-adversarial-gate** — public decision slug for the artifact
  laws. Full rule and review method: `NOTT.md` §11.
- **d16-independent-review-rung** — a contract-bearing candidate earns an
  independent, adversarial, read-only review before release. Home: `NOTT.md`
  §7 and §10.
- **d17-session-isolation** — one writer owns a surface; concurrent writers use
  separate worktrees or directories. Home: `NOTT.md` §13 and §14.
- **d18-model-family-neutral-review** — independent review remains adversarial
  and read-only; it does not require a different model family. Current public
  rung: reviewer contract plus separate-session adversarial review; no
  repository gate observes reviewer model identity. Home: `NOTT.md` §7.
- **d24-continuous-fanout** — substantive work decomposes into bounded units and
  uses available parallelism inside the grant and session isolation. Current
  public rung: client-loaded operating direction; no repository gate observes
  scheduler utilization. Home: `NOTT.md` §0.
- **d25-public-distribution-boundary** — nSOUL is the public distribution name,
  `nott` is the installed plugin id, and NOTT is the product voice. The first
  public cut contains the core skills, agents, and hooks; it excludes the
  experimental lab and treats nMEMORY and nBrowser as external optional
  capabilities. Home: `PRD.md` §7 and `SPEC.md` §1.
- **d26-declared-runtime-dependencies** — runtime dependencies MUST be declared
  in the public release contract and tested fail-closed. The public contract
  does not prohibit an implementation language. Mechanism: `SPEC.md` §5 and §6.
