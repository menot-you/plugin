---
name: debug
description: >-
  Diagnose an observed failure or regression, identify its cause and prove
  recovery. Use when the cause is unknown or repeated attempts lack progress.
---

# Debug

Find the mechanism that fails, then remove its cause at the shared boundary.

<!-- nott:debug:two-fixes -->
Two misses without differentiating evidence suspend that path. A miss in the
proof's own scaffolding (harness, fixture, wait, lock or capture) counts against
that path whatever its cause; a new scaffolding cause is not differentiating
evidence about the result, so after two such misses prove the scaffolding offline
against the last run's captured evidence before spending another consumer slot.
The accepted result and integrated consumer judge own the monotonic attempt
history: revision IDs, symptom names, commands, wrappers, subtasks and sessions
never reset it. Preserve prior attempts and finish independent authorized work.
Resume only when material evidence addresses the cause and justifies a bounded next attempt.
A different label, another review or a new prerequisite is not that evidence.

<!-- nott:debug:reproduce -->
Reproduce the actual failure before editing. Record input, environment, command
and observed result; distinguish a product failure from unavailable infrastructure,
denied authority or malformed invocation. For a flaky failure, establish its
frequency rather than treating one passing run as recovery.

Never attach a tracer (py-spy included, also nonblocking) to a live process: an
attach can stall it. Profile a copy, or read the running version from the
service manager.

<!-- nott:debug:rank -->
<!-- nott:debug:experiment -->
Rank plausible causes by evidence and identify what would reject each one.
Use the smallest differentiating experiment; inspect a rejected tool's schema
and error before choosing a corrected call. Never replay an uncertain mutation.

<!-- nott:debug:regression-test -->
<!-- nott:debug:root-cause -->
Prove the regression RED, fix the owning shared mechanism and prove the same
check GREEN. A fallback, retry or weakened assertion that hides the cause is not
recovery. Preserve security boundaries and another writer's work.

<!-- nott:debug:recovery -->
Run the affected consumer path and required checks, including relevant failure
cases and rollback. Stop verification when the required evidence is sufficient;
new evidence, not a renamed task, determines whether more work is justified.

<!-- nott:debug:close -->
Report the cause, decisive reproducer, repair and witnessed recovery, or the
exact unresolved gap. "Not reproduced. No fix is claimed." is the honest result
when the affected path cannot be reproduced. Do not invent a follow-up task.

Read ../execute/references/complete-results.md before a repair: it holds the result, RED and proof law.

Read references/progress-and-stopping.md before another attempt: it holds the attempt and stop law.

Read ../review/references/evidence.md before classifying an observation.

Read ../execute/references/runtime.md before acting on a host or capability.

<!-- nott:procedure:recovery:start -->
## A failed CANON dependency

Use this section only when a required CANON capability actually fails.

Restore the same capability from its corresponding repository main; never emulate,
weaken or replace it. Suspend dependent work and name the blocked result and
consequence. Its success remains unproved until a real operation succeeds.

Bound the repair by files, time/tokens and one proof, on a surgical branch from
main. Resolve instance, host, repository, service, configuration, rollback and
prior mutation state before changing them. The blocked result's scope and fan-out
authority do not transfer to an installer, telemetry project or broader repair.

An indeterminate mutation blocks replay. Retry only a read-only/idempotent action
or one readback proves unapplied. Install or restart only the required component;
resume after the real operation succeeds, otherwise report the external act needed.

A missing optional host task UI is not a CANON outage. Independent authorized work
may continue when its inputs and authority are established. Effects requiring a
protected recoverable record wait for that record; never invent a substitute ledger.
<!-- nott:procedure:recovery:end -->
