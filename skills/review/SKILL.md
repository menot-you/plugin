---
name: review
description: >-
  Independently assess a bounded candidate or plan against acceptance, affected
  callers and trust boundaries. Report findings without editing the candidate.
---

# Review

Decide whether the requested result is actually supported by the candidate.

<!-- nott:review:pin -->
Bind the repository, candidate and relevant inputs before judgment. For a PR,
record its observed baseRefOid for formal delivery and merge-base for diff analysis;
for a branch, use its merge-base. Include policy, configuration, target, dependencies
and expiry when they affect evidence. Main moving alone is not candidate drift.

Check what you were pointed at before you measure it: the directory the
dispatcher names, which is not your working directory when the review runs
caged in a scratch of its own. A frozen candidate carries
`.nott-review-sha` at its root and no `.git`; a live worktree carries neither.
`.nott-review-diff` is there only when the dispatcher named a base, and its
absence is not a live tree: without one, and with no `.git`, you cannot compute
a delta from inside, so say that as a stated limit and either ask for the base
or scope the verdict to the whole tree instead of to what changed. A file the
candidate deleted is only named in that diff; its base version is
`.nott-review-deleted/<path>`. When the tree you were given is live, say so as a
finding and pin every measurement to a hash you record, because anything the
dispatcher commits while you work silently ages half your verdict. Read
`.nott-review-omitted` when it exists: it names the paths the snapshot could not
carry, so a diff hunk with no file on disk is that, not a missing change. Never
edit the tree you are measuring.

When you are the one dispatching, freeze the candidate first
(`plugin/scripts/review.sh snapshot <sha> <repo> <base>`, which copies the commit
and writes its diff beside it) and point the reviewer at that copy, never at the
live campaign worktree. Remove the copy once its verdict is read.

<!-- nott:review:witness -->
Brief an independent witness with the artefact under judgment, the source it is
traced against, and the specific question it must decide. Split a review across
several dispatches only when its questions are independent and each is large
enough to repay its own context; otherwise use one well-scoped dispatch.

Dispatch the witness with `nspawn_review_start` and do not pin `provider` or
`model`: nSPAWN chooses the reader by the owner's preference order, skips a
route that cannot serve now, and continues on the next route when one refuses
the turn. Name the author in `producer` (its route, account and model) so that
the witness never runs as the author. A witness is always a new cold session,
never the author's. Read back the executed route, account and model, and the
skip record in `warning`, from `nspawn_run_show`. A campaign reader is
dispatched by ../workflow/SKILL.md (readers), not by this paragraph.

Every reader brief says: do not read a host secret file such as `~/.nott/.env`,
and do not print an environment value. Judge a configuration claim from the
code and the templates.

<!-- nott:review:read-only -->
Keep the candidate, worktree and branch read-only. Use isolated verification where
needed; do not repair findings without a separate assignment. When a findings file
is required, start it outside the candidate early and write no verdict before the
pass is complete.

<!-- nott:review:checks -->
Inspect the relevant diff, callers, transitions, acceptance, tests, documentation,
trust boundaries and rollback. Use references/checks.md for the detailed review
contract when needed. Do not require a plan, architecture file or document stack
that the actual result never needed.

This route authorizes bounded registered delegation for independent ready lenses.
Choose lenses by consequence and reach, not file count or model identity. Preserve
the required witness's independence, exact candidate binding and STOP boundary.

<!-- nott:review:quote-or-drop -->
A finding names input, failure mechanism, consumer consequence and exact evidence.
When alleging a law violation, quote both the applicable rule and candidate line;
a guessed interpretation is not a finding. Deduplicate by root cause.

<!-- nott:review:blocking -->
A blocking finding is a reproducible defect against the accepted contract or
plan, or a regression, with its input, mechanism and consequence. The accepted
contract always includes the standing law: a safety, authority, security or
data-loss violation blocks even when the plan does not name it. Test and eval
adequacy (a missing case, a surviving mutant, an eval that cannot observe its
promise) and hypothetical findings are recorded as an **nMEMORY** capsule, never
a veto, unless the DoD or plan names that proof. Every finding records its
origin: `head` when it is present in the reviewed head, `fix` when a fix
introduced it.

<!-- nott:review:rounds -->
An axis is one required review lens the applicable law names; for a campaign,
the four workflow readers are four axes, whatever route and model nSPAWN
gives each. Each axis has one veto
reviewer. A round is one reviewed head of the candidate, whatever the axes or
restarts on it, and every review prompt carries one line
`Candidate: <branch-or-plan-id>@<sha-or-revision>` naming it.

Round 1 is exhaustive over the whole candidate. The accepted contract or plan,
the owner's request and the diff of exactly that head are pasted into the brief
or written where the reviewer can read them; a reviewer cannot read git or
GitHub, and nothing edits the candidate while a review of it runs. A fix is
re-reviewed only by the axis that raised the finding it cures, never by every
axis again. A campaign's re-reads follow ../workflow/SKILL.md, where the
security reader also reads every fix delta. That re-review checks only two things: whether each finding is cured, and whether the fix
regressed anything. A new finding about code round 1 already had is a round-1
miss with origin `head`: it is recorded and does not change that round's
verdict, unless it violates acceptance or the standing law, in which case it
blocks like any other finding.

<!-- nott:review:campaign -->
A campaign has one review, at the end, on its integrated head: the four readers
of the workflow pipeline (../workflow/SKILL.md). That route holds the
readers' dispatch, the wait for all four, the 2 builder rounds, the last gate and
the escalation. This route does not restate that text.

A reader has no nMEMORY (owner decision). It reports each finding to the
lead, and the lead records the capsule.

A fix rewrites the predicate or design that failed, not the reproduced
scenario. When the same defect family returns twice, the work goes back to
design and is not patched again.

<!-- nott:review:over-engineering -->
Look for unnecessary dependencies, abstractions and invented scope. A cut needs
evidence that it preserves the required result. Test guards with distinct failure
axes are not duplicates merely because one coarse mutant kills all of them.

<!-- nott:review:dod -->
<!-- nott:review:test-kinds -->
Judge accepted consumer observations, including required failure cases, test kinds
and quality floors. A green suite, generated artifact or status label cannot prove
a caller-reaching result. Multiple observations may establish one deliverable.

<!-- nott:review:repair -->
A repair keeps the candidate, its evidence and every proof whose declared inputs
did not change, after validating those inputs. Revalidate only the changed
dependency closure, expanding where reach is unknown; patch-id equality
alone never preserves acceptance. Carry the recorded technical direction inside
the accepted scope into the next writer attempt, so a settled finding is not
rediscovered. Do not repeat a whole pass for unrelated trunk movement or
cosmetic changes.

The accepted result and integrated consumer judge retain monotonic miss history
across revisions, tasks, wrappers and sessions. Two misses without differentiating
evidence suspend the failing path. A miss in the proof's own scaffolding (harness,
fixture, wait, lock or capture) counts against that path whatever its cause; a new
scaffolding cause is not differentiating evidence about the result, so after two
such misses prove the scaffolding offline against the last run's captured evidence
before spending another consumer slot. Material causal evidence can justify a
bounded next attempt, not a fresh budget. A non-blocking finding follows
references/evidence.md; never waive a real required gap.

<!-- nott:review:deliver -->
An exact PR-review request authorizes one evidence-backed COMMENT on that target,
not APPROVE, REQUEST_CHANGES, product edits or a draft-state change. Before that
effect, read references/delivery.md and use the existing
scripts/deliver-github-review.sh contract. Resolve actor, candidate, body and target
from current evidence. Otherwise return the review unposted with its exact gap.

<!-- nott:review:no-retry -->
An ambiguous POST is never repeated. "do not retry" means reconcile the target
first; only "no write attempted" establishes the helper made no outward effect.

<!-- nott:review:final-report -->
<!-- nott:review:route -->
Report findings, the strongest supported verdict and any required proof gap.
Assess full intent and plan coverage when those artifacts govern the result.
A blocker returns to its owning decision or implementation; this review does not
expand scope or silently execute the repair.

Read references/evidence.md before judging: it holds the evidence, witness and judge law.

<!-- nott:review:close -->
LGTM requires no blocking finding or required proof gap. State what was verified
and what was not; required PR delivery ends with the exact authoritative readback.
