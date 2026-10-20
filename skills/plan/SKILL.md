---
name: plan
description: >-
  Turn an agreed result into an execution-ready plan or identify the next ready
  work. Planning alone does not authorize implementation.
---

# Plan

Preserve the full result while making the next authorized work executable.

<!-- nott:plan:interview -->
Consume decisions already made. Resolve repository facts and technical choices
within scope. Ask only for a new owner-held purpose, taste, authority or result
decision that changes the plan; do not reopen a settled interview.

<!-- nott:plan:independent-authorship -->
<!-- nott:plan:write -->
The principal may author the plan. An execution-ready plan requires independent
review; the author cannot supply that witness. A simple ordering answer does not
create a new plan or review stage.

That review runs BEFORE execution, and it loops: a finding that holds returns to
the plan and the revised plan is reviewed again. When two rounds in a row find
only execution-level detail, the loop stops and the plan is delivered: a plan
holds on design, order, authority and observable acceptance, and a campaign's
exact commands get their own readback and independent review against live state
when that campaign starts. Carrying an unresolved finding into execution turns
it into rework, which is the expensive place to find it. A review that holds
readies the plan; the owner accepts results, never a plan or a draft.

<!-- nott:plan:final-text -->
A plan's text is its final version. The rounds, verdicts, finding tables and
revision notes of its review stay in the review record, never in the plan.

<!-- nott:plan:home -->
Use the existing planning surface. When a durable repository plan is requested,
record it as the nMEMORY plan capsule with a principal-chosen slug; its working
copy lives at .nott/plans/<slug>/PLAN.md, ignored by Git, never in the tracked
tree. Materialize INTENT.md beside it from accepted owner decisions only when the
campaign needs that source; the owner owns its meaning. Do not demand a document
stack for an ordering answer.

<!-- nott:plan:contract -->
<!-- nott:plan:coverage -->
<!-- nott:plan:matrix -->
Connect every accepted requirement to its deliverable and observable acceptance.
Name what the ready work proves, what remains and what makes it ready. Use a
coverage matrix when it makes those relationships easier to verify; its presence
or a fixed section order is not acceptance.

Write the next useful increment as an observable result, concrete changes,
necessary dependencies, consumer proof and next action. Keep later outcomes
visible with the condition that makes them ready. State current constraints once
where they affect a decision; reference their owning record instead of repeating
approval disclaimers, capsule histories or policy text in every chapter. Remove
planning steps that neither advance delivery nor protect a real boundary. Keep
material risks, missing inputs and required owner decisions (result, taste,
scope or a reserved act) explicit.

The responsible principal chooses delegation under the owner's standing grant; a
leader may decompose only its assigned scope. Base the choice on independent
deliverables, required expertise, risks, dependencies, shared writers and
observed resource limits. Software-house roles such as #brainstorm,
#workflow and #review name available responsibilities, not mandatory model calls
or spawning levels. Use one responsible executor for a bounded task. Required
independent review follows applicable rules and accepted criteria; the executor
cannot waive it. Delegation cannot expand scope, budget, permissions or reserved
acts; bring changes to those limits to the owner. Give each worker the original
intention and acceptance alongside its scoped assignment; the principal owns
integration and the full result. Use code and events for routine monitoring,
adding model calls when interpretation is needed.

<!-- nott:plan:workflow -->
For a campaign, the spec stage follows ../workflow/SKILL.md (spec).

<!-- nott:plan:graph -->
<!-- nott:plan:frontier -->
<!-- nott:plan:parallel -->
A dependency exists where one result supplies an input another needs. Preserve
future results with their materialization conditions. Dispatch only observed,
bounded ready work; independent disjoint results may proceed together. Use an
existing graph where available and references/graph-law.md when graph topology
needs definition. Do not invent speculative interfaces beyond the frontier.

<!-- nott:plan:waves -->
Name the dispatch waves: which units are ready together, because their
write-sets are disjoint and none needs another's output, and the dependency that
makes each later wave wait. A wave states readiness, not a running order; the
phase order a change passes through and when a ready unit is held back are the
law's, not this route's.

<!-- nott:plan:unit -->
<!-- nott:plan:executor-floor -->
A unit is a coherent deliverable, not an observation, test or commit. Multiple
observations may establish one result. Give a principal the bounded result and
evidence needed for technical discovery; give a mechanical worker exact paths,
commands, values and signals. Use references/unit-contract.md when scheduling
cold execution. Missing technical detail is not a reason to stop a principal
who is authorized to discover it.

A plan that reaches the owner opens with a `## Readback`: one sentence naming the
promised result plus, only when the ask is ambiguous, the one question that
resolves it, never a numbered list. The owner never receives a plan without it;
plugin/scripts/floor.py refuses the principal plan that lacks it.

<!-- nott:plan:dod -->
<!-- nott:plan:judge -->
Use the real consumer boundary and an integrated judge to decide completion.
Reuse existing executable proof. Build only a missing judge that is necessary to
observe the requested result, never machinery whose sole consumer is the plan.
Persist scheduled accepted DoDs with dod_of relations before dispatch; do not
recreate existing accepted records or split units by the number of observations.

Acceptance names the host and the complete run there, not a sampled smoke;
configuration being present is an input, never the result.

<!-- nott:plan:floors -->
The checks and limits the repository declares, required test kinds and
independent witnesses remain binding; where the repository declares no limit, the
plan names checks proportional to the change and no invented floor. A structural plan check cannot establish product behavior or replace a
consumer proof. Keep accepted authority separate from met/partial/failed verdicts.

<!-- nott:plan:panel -->
<!-- nott:plan:verify -->
Review coverage, feasibility, scope and consequential trust boundaries. Bind
evidence to candidate bytes and relevant policy, configuration, target,
dependencies and expiry. Reuse unaffected observations. A relevant change ages
only its affected proof; patch-id equality alone is insufficient.

The accepted result and integrated consumer judge own the monotonic miss history.
Revision IDs, repartitioning, session names and new prerequisite labels do not
reset it. After two misses without differentiating evidence, stop that path; a
material input addressing the cause may justify a bounded next attempt. A miss in
the proof's own scaffolding (harness, fixture, wait, lock or capture) counts
against that path whatever its cause; a new scaffolding cause is not
differentiating evidence about the result, so after two such misses prove the
scaffolding offline against the last run's captured evidence before spending
another consumer slot.

<!-- nott:plan:proof -->
<!-- nott:plan:one-pr -->
<!-- nott:plan:merge-route-boundary -->
<!-- nott:plan:mergeable -->
Deliver the plan with its actual verification and open decisions. Planning alone
does not authorize implementation, installation or merge. When execution is also
authorized, continue through the same campaign and PR without a plan-only PR.
Unrelated movement of main is not a reason to rebuild the plan or repeat review.

<!-- nott:plan:output -->
A cold executor can identify the result, allowed next action, proof and rollback.
Use references/register.md only when a requested artifact, canonical diagram or
imagery needs those domain conventions. Do not add media or documents as ceremony.

Read ../execute/references/complete-results.md when defining a unit: it holds the result, RED and proof law.

Read ../workflow/references/delegation-and-recovery.md when scheduling parallel or delegated work.

Read ../readback/references/communication.md before producing a durable artifact or diagram.

<!-- nott:procedure:native-planning:start -->
## Native planning boundaries

AskUserQuestion, EnterPlanMode and ExitPlanMode are conditional host bindings.
Use a registered question interface only for an unresolved owner decision or action.
Respect a planning mode the owner opened and the host's gate on leaving it;
never enter plan mode to have a plan or method approved, never invent a gate the
host lacks, and never ask again for implementation already granted. When the
project has tests, the first implementation mutation of an authorized behavior
change is its regression test, observed RED before product editing.
<!-- nott:procedure:native-planning:end -->
