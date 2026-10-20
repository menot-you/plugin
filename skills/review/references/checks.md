# Review evidence

Use this contract for a bounded independent review. Scale the examined surface
to the accepted result and the candidate's actual reach.

## Candidate and evidence inputs

Record the repository and candidate. For a PR retain baseRefOid for the formal
delivery tuple and the observed merge-base for diff analysis; use merge-base for
a bare branch. Inspect actual source, not a summary of its diff.

Bind observations to relevant bytes, policy, configuration, target, dependencies
and expiry. Candidate equality alone cannot validate changed authority or target
requirements. Main movement outside those inputs is not drift.

A repair pass inspects the changed closure and carries unaffected proof after
validating its inputs. Expand verification where changed reach is unknown.
Do not reload an entire document stack or repeat a complete pass merely because
a revision, task or session got a new name.

## What to judge

Inspect affected callers, transitions, trust boundaries, acceptance, required test
kinds, documentation, rollback and the claims being made. Correctness, security,
performance and maintainability matter where the change reaches them.

Read applicable repository instructions and existing contracts. Check required
documentation against changed behavior; do not manufacture README, ARCHITECTURE,
DESIGN, RUNBOOK, INTENT or PLAN files solely to populate a report. Where the
repository uses changelog fragments, use that owning convention.

A delivered result can have several acceptance observations. A suite over an
unreachable mechanism, an artifact count or a completion label is not consumer
proof. Retain required fuzz, concurrency, end-to-end and independent witness
obligations where the actual boundary earns them.

## Findings

Each finding needs a concrete input, failure path, consumer consequence and exact
evidence/location. A claimed law violation quotes the applicable rule and candidate
line. Drop a finding that cannot reproduce or reads the code backwards. Report
every other finding with its severity; one that changes no executable acceptance
verdict is non-blocking, not dropped. Required unrun proof remains a gap.

Hunt unnecessary layers, dependencies and scope. A deletion must preserve distinct
behavioral protections: several guards killed by one coarse mutant may still
cover different axes. Do not rank code by lines removed.

## Verification and completion

Keep the candidate read-only. Run focused checks in an isolated location when they
would otherwise mutate it. The author cannot supply required independent review.

For the accepted result and integrated consumer judge, retain monotonic miss history
across revision IDs, renamed subtasks, symptoms and sessions. After two misses
without differentiating evidence, suspend that path and identify the missing causal
input. A miss in the proof's own scaffolding (harness, fixture, wait, lock or
capture) counts against that path whatever its cause; a new scaffolding cause is not
differentiating evidence about the result, so after two such misses prove the
scaffolding offline against the last run's captured evidence before spending another
consumer slot. A material input can justify a bounded next attempt without erasing
history.

Do not order another review to process only editorial drift; a non-blocking
finding follows evidence.md. That never makes a required proof gap green or
permits an uncertain external mutation.

Post only under the target's actual authority. Before delivering a PR review,
read delivery.md; preserve its candidate/body/actor binding and no-replay boundary.
A local verdict without required publication readback is not delivered review.

<!-- nott:procedure:review:start -->
- Review is independent, adversarial, read-only and candidate-bound. When a findings
  artifact is required, write it early outside the candidate, refine it during the
  pass and write the verdict only after the pass finishes.
- Freeze candidate bytes and declared inputs for judgment. Changed bytes or material
  inputs stop the affected verdict; carry independently validated unaffected
  observations. The trunk moving underneath is not candidate movement.
- Begin from current authority and evidence, never another reviewer's assertion.
- Blocking means a finding changes an executable verdict: a test, gate or exit code,
  or a required acceptance observation. Anchor/citation drift is non-blocking and
  follows evidence.md.
- Return LGTM only when no blocking finding or required proof gap remains. Report
  limitations explicitly; source guards and local tests do not qualify native behavior.
<!-- nott:procedure:review:end -->
