---
name: execute
description: >-
  Deliver a clear, bounded engineering change with focused proof. Use when the
  result and authority are settled; diagnose unknown causes with debug.
---

# Execute

Make the requested consumer result true with the smallest coherent change.

<!-- nott:execute:boundary -->
<!-- nott:execute:inputs -->
Read current state, relevant instructions, affected callers and existing evidence.
Preserve unrelated dirty work and the declared write-set. Resolve discoverable
engineering facts yourself; ask only for unresolved result, authority or safety.
An already-authorized task needs no new interview or approval.

<!-- nott:execute:executor-floor -->
A principal owns technical discovery within the boundary. Only an explicitly
mechanical worker requires verbatim commands and stops on an unspecified technical
choice. Role comes from the dispatch, never provider identity.

<!-- nott:execute:ladder -->
Reuse the repository solution, stdlib, native platform or installed dependency
before adding code. Remove the shared root cause; avoid speculative layers,
dependencies and symptom-masking retries. Measure a guard's distinct failure mode
before deleting it.

Before a behavior edit, run the smallest permanent regression check and observe
the intended RED. Setup failure is not RED. Apply the change and observe the same
check GREEN, then run the broader checks the actual consequence requires.

<!-- nott:execute:scope -->
<!-- nott:execute:proof -->
Review the diff for scope, trust boundaries, generated state and rollback.
A finding blocks this task only as ../review/SKILL.md defines blocking
(<!-- nott:review:blocking -->); a falsified input or a required proof gap stops it
too. Record unrelated debt without adopting it as new work.
Verification stops when the accepted consumer observations and required checks pass;
do not repeat them without changed inputs, failures or an unresolved proof gap.

A review or fix loop this task runs, by hand or by workflow script, follows
../workflow/SKILL.md (<!-- nott:workflow:review-loop -->).

<!-- nott:execute:workflow -->
In a campaign, the builder and its resume follow ../workflow/SKILL.md (builder,
resume).

<!-- nott:execute:two-fix -->
After two misses without differentiating evidence, suspend that path and use debug to
obtain a causal observation. A miss in the proof's own scaffolding (harness, fixture,
wait, lock or capture) counts against that path whatever its cause; a new scaffolding
cause is not differentiating evidence about the result, so after two such misses
prove the scaffolding offline against the last run's captured evidence before
spending another consumer slot. Keep the miss history under the accepted result and
integrated consumer judge across revision, task, wrapper and session renames.
Material new evidence can justify one bounded next attempt; it does not erase misses.

<!-- nott:execute:after-execution -->
Execution is not the last phase. On what this change touched, run intent
validation, then quality, then cleaning, before the gate sees it; the owner law
holds that order and why it is that one. A green check is not the end of the
unit, and a unit whose intent nobody validated is not delivered.

<!-- nott:execute:gate-once -->
Prove compilation, affected unit suites, fast integration or startup probes, and
required review in isolation before running the full member gate, so the full
gate runs once at the end without back-and-forth reruns.

<!-- nott:execute:owner-look -->
When the change has a result the owner judges by using it (an app, UI, UX or
another experience), his look is its intent validation. Once the candidate
passes its own tests, install it where he looks, or present it, and tell him,
before any review round. Review rounds gate the merge to the trunk, not his
first look; a result he rejects returns to execution with no review spent on
it. A change with no such result goes to review without a preview.

<!-- nott:execute:closure -->
Completion is the observed requested state, not effort, local green or a commit.
Carry proof gaps into the state line's `open:`. If authorized
delivery requires a merge or deployment, continue through ship; do not hand routine
delivery back to the owner. Keep one durable state surface when work spans steps.

Read references/complete-results.md before changing anything: it holds the result, RED and proof law.

Read references/runtime.md before touching a host, runtime or model configuration.

Read ../review/references/evidence.md before claiming a proof or reusing one.

Read ../debug/references/progress-and-stopping.md after a miss or during long work.

<!-- nott:procedure:execution:start -->
## Protected implementation requirements

- Respect the write-set; remove only code created by this change or dead for its
  proven cause. Preserve other writers' changes.
- Restraint governs what is BUILT, not what is proved: build no unneeded exposure,
  and keep bounded resources, fail-closed trust, tested failures and deterministic
  recovery. The checks and limits the repository declares stay required.
- A red check outside scope is debt, not permission to expand the task. The checks
  and limits the repository declares for a touched unit remain binding until met or
  covered by the repository's own dated exception; they cannot be deferred to another
  candidate. A pull request is not ready while a touched unit lacks the proof a
  declared requirement needs.
- Keep applicable code, docs, tests, diagrams, contracts and rollback in one candidate.
  A behavior change updates its changelog in the same commit, or names why none applies.
<!-- nott:procedure:execution:end -->

<!-- nott:procedure:local-execution:start -->
## When execution needs host processes

Use the project's runtime and commands; never install its dependencies into the
agent control runtime. Optional CLI/canvas integrations do not block unrelated work.

For long work, use an owned detached process and a run-bound completion sentinel.
The fork's exit is not the work's completion and is never read as the result. Bind
a tracked waiter to that sentinel so completion re-invokes the session; a detached
run nothing waits on leaves the owner watching a state line that never resolves.
Read EXIT= from the sentinel created after this run started; an absent or stale
sentinel proves no completion. Use the host's equivalent completion evidence where
those shell primitives do not exist.

Redirect the whole output and cut it only on read; never put tail or head inside
the background pipeline. Kill only the owned PID, never pkill -f. Never put a
secret in argv; use stdin. A [killed] marker and [exited with code N] are different
observations, neither sufficient alone to identify who sent a signal.
<!-- nott:procedure:local-execution:end -->
