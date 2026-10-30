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

Dispatch each witness, the required reviewer included, with
`nspawn_review_start`, and pin no `provider` or `model`. nSPAWN chooses the reader by the owner's preference order, skips a
route that cannot serve now, and continues on the next route when one refuses
the turn. Put only the author's account alias in `producer`, never its route or
model, so that the witness never runs on the author's account and a witness on
the same model stays possible. A witness is always a new cold session that
shares no context with the author: never the author's own session, its fork or
the session that dispatched the author. Its model may be the same as the
author's or
another. Read back the executed route, account and model, and the
skip record in `warning`, from `nspawn_run_show`. A campaign reader is
dispatched by this paragraph, with the type and the effort that
../workflow/SKILL.md (reader) sets. The lead
watches each witness run as ../workflow/SKILL.md (watch) sets.
Dispatch an adversarial reader with `nspawn_review_start` as the `adversarial` agent.

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
a guessed interpretation is not a finding.

<!-- nott:review:blocking -->
A blocking finding is a reproducible defect against the accepted contract or
plan, or a regression, with its input, mechanism and consequence. The accepted
contract always includes the standing law. A safety, authority, security or
data-loss violation that the candidate introduces blocks even when the plan does
not name it. A finding outside the PR's accepted result is not a veto when the
base already has the same consequence on the same input. The candidate is no worse
than the base. Record that finding as an **nMEMORY** capsule. The exception never
covers a regression or an introduced safety, authority, security or data-loss
failure. It never covers a defect that the accepted result promises to cure.
Test and eval adequacy (a missing case, a surviving mutant,
an eval that cannot observe its promise) and hypothetical findings are recorded
as an **nMEMORY** capsule, never
a veto, unless the DoD or plan names that proof. Every finding records its
origin: `head` when it is present in the reviewed head, `fix` when a fix
introduced it.

<!-- nott:review:rounds -->
An axis is one required review lens the applicable law names. Each axis has one
veto reviewer. A campaign round has one reader, and its axis is the main risk
of the diff (owner, 2026-10-21). Count each new head that a reviewer reads as
one round, whatever the axes, readers or sub-passes on that head. A pass after
a fix reads a new head and counts as another round. Every review prompt carries
one line `Candidate: <branch-or-plan-id>@<sha-or-revision>` naming the
candidate.

Review rounds have no numeric limit. A cure round adds no scope. The reader's
SHIP ends the review loop at the reviewed head when no blocker remains.
FIX-FIRST starts another cure round with the same builder. A round count never
triggers a stop, an escalation, a judge or a merge. The lead may ask a cold
judge whether to continue, revise the spec, or stop at needs-human, as
../workflow/SKILL.md (convergence) sets. The question must concern
convergence, not the count.

nSPAWN counts review rounds. Two doors count a head: `nspawn_review_start`
with `subject` and `candidate`, and an Agent or Task dispatch of a reviewer
type with one `Candidate: <subject>@<40 or 64 hex>` prompt line. Each round
starts a new reader. A reviewer type takes no `name`. A brief or message that
is not a review round has no `Candidate:` line or inline candidate token. The
count is a measure, not a stop condition.

Use a repository-qualified branch lineage as a PR subject, for example
`<repository>/<branch>`; do not reuse it for another PR. A plan's subject is
its slug. A compile subject is the plan's subject followed by `/plan.py`.
A spec's subject is its repository path. A base branch is never a subject.
A revised plan after Change or a revise stop uses `/v2`, `/v3` and so on.
A revised spec after a returning root cause also uses the next version.
A cure round in one review loop keeps its subject. A PR or compile review
carries `Spec revision: <64-hex>` to bind it to the spec or PLAN.md reviewed
under its own subject before the builder starts. A revised spec preserves the
review history. It does not clear an open blocker.

Round 1 is exhaustive over the whole candidate. In round 1, each reviewer
repeats its search from a new angle (another input, caller, transition or
failure path) until two consecutive passes add no new finding. Then the review
is dry, and it returns every finding at once, grouped by root cause: each group
is one finding and names every failure of that cause. A review that stops at its
first finding is not a round. The accepted contract or plan,
the owner's request and the diff of exactly that head are pasted into the brief
or written where the reviewer can read them; a reviewer cannot read git or
GitHub, and nothing edits the candidate while a review of it runs. A fix is
re-reviewed only by the axis that raised the finding it cures, never by every
axis again. That re-review checks only the findings that the previous round
listed: whether each finding is cured, and whether its fix regressed anything.
It does not search the candidate again. A new finding about code that round 1
already had is a round-1 miss with origin `head`. It blocks only when it is a
safety, authority, security or data-loss failure (owner, 2026-10-23). The
reviewer records any other round-1 miss, and that miss does not block.

<!-- nott:review:dry -->
A reader of round 1 runs again on the same head, in a new cold session that
gets the findings already known, only while its last pass found a new blocking
finding. A non-blocking finding becomes a debt line, as references/evidence.md
says, and starts no new pass. These passes are one round, not a cure round.
When no reader runs again, the lead sends the blocking findings of round 1 to
one cure round. With no blocking finding, no cure round starts. A root cause with
two or more failures goes back to the spec or design first, as the fix rule
below says.

<!-- nott:review:quality-measure -->
The lead measures the review quality of each PR with two numbers: the findings
of round 1, where each root-cause group counts as one, and the findings with
origin `fix`. The lead records both numbers in nMEMORY after each round. In the
lead's progress report, the state of the PR's line shows both numbers, for
example `r1 7, fix 2`.

<!-- nott:review:campaign -->
Each pull request of a campaign gets its own review, on its integrated head: one
reader for each round, in the workflow pipeline (../workflow/SKILL.md). That route
holds the choice of the reader, the rerun of the checks, the merge and the
escalation. This route does not restate that text.

A reader has no nMEMORY (owner decision). It reports each finding to the
lead, and the lead records the capsule.

A fix rewrites the predicate or design that failed, not the reproduced
scenario. When one root cause has two or more failures, in one round or across
rounds, the work goes back to the spec or design before any fix. The revised
spec or design is a
new candidate, and it gets its own exhaustive round 1 before the builder starts
on it.

When a data-loss, race or destructive-act family returns twice, the lead
removes the automatic act from scope within the accepted result. If the
automatic act is the owner's required result, the lead keeps it in scope. The
lead alone makes this method decision. Do not send it to the owner as a question.

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
