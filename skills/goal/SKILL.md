---
name: goal
description: >-
  Bind an active goal or cold worker session to one accepted result, existing
  evidence, authority and stop conditions.
---

# Goal

Give a session enough context to finish its result without recreating the project.

<!-- nott:goal:single-writer -->
The host's active goal record is the contract when one exists. Reuse its durable
work record and acceptance. For cold dispatch, supply the contract through the
receiver's supported context; write GOAL.md only when that receiver needs the file.

<!-- nott:goal:result -->
<!-- nott:goal:per-task -->
State the accepted result, consumer and integrated judge, authority, scope,
write-set, proof, dependencies and rollback. A deliverable may need multiple
acceptance observations. Split work for independently deliverable results or
exclusive ownership, not to give each assertion its own task.

<!-- nott:goal:phases -->
Say which phase the receiver enters and what its input already is. A goal that
hands over a plan whose independent review holds enters EXECUTION; one that
hands over a draft enters PLAN REVIEW. The owner accepts the result, never the
plan. Never name a later phase to skip an earlier one whose input is missing.

<!-- nott:goal:salvage -->
Start from the exact good state already achieved. Carry unaffected evidence and
open gaps forward. A finish-goal is a continuation, never a restart.

<!-- nott:goal:two-strike -->
The accepted result and integrated consumer judge own monotonic attempt history.
Preserve misses across revision IDs, renamed subtasks, symptoms and sessions.
After two misses without differentiating evidence, suspend that path and name the
reproducer and missing input. A miss in the proof's own scaffolding (harness,
fixture, wait, lock or capture) counts against that path whatever its cause; a new
scaffolding cause is not differentiating evidence about the result, so after two
such misses prove the scaffolding offline against the last run's captured evidence
before spending another consumer slot. Material new evidence addressing the cause
permits a bounded next attempt. Never reset the count by rewriting the goal.

<!-- nott:goal:ceilings -->
Bound time/tokens, findings and output scope to the actual assignment. At a ceiling,
preserve work and return its state and exact gap; do not start new checks that the
remaining budget cannot finish or enlarge the result to justify further activity.

<!-- nott:goal:do-not-reinvent -->
Name existing machinery and evidence the receiver should reuse. References are
loaded only for an operation that needs them, not as a mandatory skill stack.
For scheduled execution, use the relevant fields of
../plan/references/unit-contract.md; conductors use the campaign reference only
when coordinating multiple lanes.

<!-- nott:goal:boundary -->
<!-- nott:goal:executor-floor -->
Declare principal or mechanical worker. A principal may discover technical facts
within scope; a mechanical worker gets the exact commands, values and signals it
needs. No worker invents product authority or touches another writer's files.

<!-- nott:goal:capture -->
Before dispatch, persist accepted DoD records linked by dod_of to the durable work
capsule through registered nMEMORY operations. Do not recreate already accepted
records. Keep authority status separate from observed verdict.

<!-- nott:goal:idempotence -->
<!-- nott:goal:finish -->
<!-- nott:goal:close -->
Continue only unresolved work. If acceptance already holds, validate the relevant
evidence inputs and close without rebuilding or gratuitous reruns. Finish with the
consumer observation, remaining gaps and the receiver's
actual completion signal. Create ./DONE only when that exact signal is required.
Commits are useful checkpoints; they are not an extra task-completion criterion.
