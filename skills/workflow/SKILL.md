---
name: workflow
description: >-
  Run an agreed result as a workflow: start all independent ready units under
  bounded ownership and resource limits, then the campaign pipeline of spec,
  builder, one reader for each round, cure rounds and merge on SHIP. Also a
  side unit (host housekeeping, the fix of a defect in a NOTT tool), which runs
  fire-and-forget in one background agent. Not for choosing direction or merely
  writing a plan.
---

# Workflow

Put independent ready work in motion without creating competing writers.

<!-- nott:workflow:freeze -->
Establish one durable campaign home and, when integration requires it, one
integration worktree and branch. Record each unit's result, authority, inputs,
write-set, consumer acceptance, executor and STOP boundary before dispatch.
Use the applicable fields in ../plan/references/unit-contract.md; the complete
campaign procedure is ../plan/references/campaign-loop.md for multi-lane delivery.

A unit is a deliverable and may need several observations. Do not split a result
to give each check its own worker, task, review or commit.

<!-- nott:workflow:ceiling -->
Measure host and account capacity before admitting lanes. The parent allocates
the budget; children do not each treat the same free memory as theirs.
Every available slot takes a disjoint ready result when useful. If none exists,
invent no work.

The campaign shape in ../plan/references/campaign-loop.md sets lane ownership.

<!-- nott:workflow:ultra -->
This route authorizes bounded native delegation. `nspawn_run_start`,
`nspawn_review_start` and `nspawn_batch_start` are its only dispatch path
(owner, 2026-10-21). references/delegation-and-recovery.md holds its one
exception, for a unit that no nSPAWN route can serve, and the routing rule.
Reuse qualified idle agents, choose by actual capability and keep one writer
per mutable surface. Autonomous writers use isolated worktrees.

<!-- nott:workflow:agent-type -->
Choose the agent type deliberately: the full-tool type is the fallback, not the default.
Pick the narrowest INSTALLED type whose tools cover the unit. An implementer needs
every tool, MCP included, so it takes a full-tool type. Discovery takes a read-only
search type. An independent reader takes a read-only reviewer type matched to the
changed surface (language, tests, error paths, security); brief it to review the
supplied diff only, with no builds or edits, to report findings as file:line plus
a concrete failure, and that the repository's floors and rules win over its own
defaults. Never pick a type whose built-in rules contradict a repository law.
Before you dispatch a non-mechanical brief, apply the `upscale` route to it
(../upscale/SKILL.md).

A worker has no nMEMORY (owner decision): the plugin refuses the nMEMORY
tool calls of a Claude subagent and an nSPAWN child. A Codex sub-agent is not
covered, and the nmemory CLI through Bash stays open until a later change. Put the decisions, pins and facts that bind the
unit in its brief. The worker reports facts to you, and you capture them.

<!-- nott:workflow:workflows -->
<!-- nott:workflow:maestri -->
Use the current registered contract of the dispatch tool when dispatching through
it. Preserve handles, outputs and its real completion notifications. Do not guess
tool names or delete a terminal that still owns work. A unit is counted started
only once its native admission or start is read back; a send that times out or
returns silence is counted as unconfirmed, never as started, and is never
dispatched again before that readback settles.

<!-- nott:workflow:recursion -->
A child may delegate only within its assigned authority, role and resource budget.
Do not recursively decompose an already bounded mechanical operation.

<!-- nott:workflow:housekeeping -->
A side unit is work that the owner did not ask to follow. Examples are host
housekeeping (disk cleanup, measurements, cache pruning) and the fix unit for a
defect in a **NOTT** tool (the law, Authority). The main session starts a side
unit fire-and-forget: it gives the unit to one background agent (owner,
2026-10-20 and 2026-10-28). The Agent dispatch of a side-unit owner names its
model and has a `Tier reason:` line in its prompt. The unit's brief names
mechanical steps such as a readback, so without both the dispatch-tier hook runs
the agent on the mechanical tier. That agent owns the whole unit: for a change,
the spec, RED, build, review, merge and delivery. It watches each run that it
starts and verifies each checkpoint of the unit (watch). It starts each run with
`nspawn run start` or `nspawn review start`, with the tool's arguments as one
JSON object on stdin and `"notice": false`, so that the end of a run does not
wake the main session. The command runs the installed nSPAWN. The agent's own
tool list can be older than the installed nSPAWN and then has no `notice` field.
It waits for each run with `nspawn run wait <run_id>` in the background: the Bash
tool with `run_in_background`, or the Monitor tool. The harness wakes the agent when the wait ends. The main session
watches only that agent, and the harness wakes the main session when the agent
finishes or stops. So only two events reach the main session: the outcome and
each decision that only the owner can make. The main session tells the owner
only these two. It does not run the unit's steps or review rounds or report its
progress.

Read references/delegation-and-recovery.md before dispatch: it holds the delegation, process and CANON-repair law.

Read ../execute/references/runtime.md before pinning a worker's model, host or capability.

<!-- nott:workflow:fan-in -->
Track ready, active and blocked work on the same panel, naming for every ready
node left idle the input it is missing. On completion verify the candidate bytes,
declared write-set and required evidence; a worker's prose is not the witness.
Rescue existing work before replacing a failed lane.

Before the lead stops on an owner question, it dispatches every ready unit
independent of that question.

<!-- nott:workflow:review-loop -->
Every review loop loads the review route and
pastes its blocking, origin and round rules (../review/SKILL.md) into each
reviewer's brief; a hand-written prompt without them is not that route. Before
its first round, read ../execute/SKILL.md (<!-- nott:execute:owner-look -->). A
campaign's workflow takes the shape of ../plan/references/campaign-loop.md, read
before the campaign starts.
Verification reuses a reference whose inputs did not change (the same file) and
runs in parallel where the suite allows it, as the law's slow-check rule says. A host that cannot be reached or a
locked screen is D18 `1`, operational, never a test failure.

<!-- nott:workflow:opus-haiku -->
Use the GPT route by default for builders, explorers, test writers and the
`adversarial` agent. Claude runs the lead and the required Opus reviewer
(../review/SKILL.md, witness). When the GPT route cannot serve, nSPAWN routes
the unit to Claude.

Use references/model-tiers.md for execution classes and Claude model tiers. A
fast-model result is a hypothesis until its oracle or an Opus verifier proves
it. Run as many parallel fast-model experiments as the independent work allows,
within the budget. One lock, one running
suite or one shared branch serves one unit at a time. Through nSPAWN, an
experiment or probe declares `mechanical_fanout`. A roster class marked
`fast = true` runs that unit on its fast lane.

<!-- nott:workflow:model-tier -->
Every `nspawn_run_start` names its execution class in `class`. A unit's tier
comes from its execution class through the one table in references/model-tiers.md,
which also holds what qualifies a unit for Haiku and the one escalation after a
miss. Where a result holds genuinely independent units, dispatch them separately
so each can qualify for its own tier; that never splits one result into a worker
per check. Each workflow's result reports, per unit, its tier, tokens, wall-clock
and findings, read from the records the reference names.

Miss history follows the accepted result and integrated consumer judge across
revision, task, lane and session renames. Two misses without distinguishing
evidence suspend that path while other authorized work continues. A miss in the
proof's own scaffolding (harness, fixture, wait, lock or capture) counts against
that path whatever its cause; a new scaffolding cause is not differentiating
evidence about the result, so after two such misses prove the scaffolding offline
against the last run's captured evidence before spending another consumer slot.
Material causal evidence may permit a bounded new attempt without erasing the
history.

A campaign lands as small, well-scoped PRs. Each PR is one coherent result that
a reviewer can judge alone. The conductor continues through required review and
ship. It does not stop at a ready check or ask the owner to perform its merge.
No lane pushes main or opens its own PR.

<!-- nott:workflow:watch -->
## Watch

Every campaign and every unit runs this way, and only this way (owner,
2026-10-21). Before dispatch, the lead declares for each unit its expected time
(a deadline) and its checkpoints. A checkpoint is a fact the lead reads itself:
a commit on the remote branch, a check exit, a merge state, an installed
version. A worker's report never closes a checkpoint. In a side unit
(housekeeping), its background agent runs this watch in place of the lead, and
the main session watches only that agent.

A code monitor, not a model, watches each running unit. It wakes the lead on
three events. Silence: the worker gives no output for a declared time. Overrun:
the deadline passes. Checkpoint: an event such as a push. The lead verifies each
checkpoint when it fires. The state line shows the progress as checkpoints done
over total, with the deadline.

On silence or overrun, the lead acts in the same turn. It diagnoses, cuts the
unit's scope inside the accepted result, returns the work to the spec, or asks
the owner one question. It never lets a
unit run on past an alarm without a recorded decision.

<!-- nott:workflow:pipeline -->
## Pipeline

A campaign's result runs through one pipeline (owner, 2026-10-21):
feature -> spec -> builder -> one reader for each round, as ../review/SKILL.md
(rounds) sets -> cure rounds -> merge on SHIP. FIX-FIRST resumes the same
builder. The reader's verdict decides when
the review loop ends, not the round count.

<!-- nott:workflow:stages -->
| Stage | Agent type | Model | Signal |
| --- | --- | --- | --- |
| spec | the lead | opus | each acceptance item names its observation |
| builder | the sector agent `plugin/agents/<sector>.md` | the default route (opus-haiku) | DONE or BLOCKED |
| reader | the reviewer type for the main risk of the diff | the best available (today opus), effort `max` | SHIP or FIX-FIRST |
| screen qa | `nott:qa`, for an app UI change | opus | SHIP or FIX-FIRST |
| evidence | `general-purpose`, reruns the named checks on the frozen head | haiku | each check with its command and exit |
| ship | `general-purpose`, lands the frozen head and reads back the delivery | haiku | the landed sha and the readback |

<!-- nott:workflow:spec -->
The lead writes the spec before the builder starts: the result, the acceptance
items, the touched surfaces and the main risk. Each acceptance item names the
observation that proves it. When an item cannot name one, ask the one question
that settles it (../readback/SKILL.md). The spec stays outside the builder's
write scope, in the lead's checkout. When the lead freezes a head, it checks the
spec's sha256 against the one it recorded and puts it in each brief. A mismatch
stops the round until the lead restores the recorded spec or records a new
revision. The plan readback of ../plan/SKILL.md (write) comes before the builder
starts.

Each reader brief carries the spec's sha256 in its spec revision line,
`Spec revision: <64-hex>`. A revised spec gets its own counted review, as the
next version of its subject, before the builder starts on it. Builder,
evidence and ship briefs carry no line that starts with `Candidate:` and no
inline candidate token. Builder, evidence and ship briefs do not count as review
rounds.

Before the lead sends a brief, the lead checks the brief's premise in the code.

<!-- nott:workflow:builder -->
Use references/writer-brief.md for each `native_write` builder brief.

Native writers admit only `implementation` with explicit exact-HEAD `red_record`,
or `verification` for verification work without RED. Other classes cannot bypass
this binding; do not relabel implementation as verification. Use the producer's
exact judged-set/record pair, not JSON reconstructed from phase witness fields.

Initial prepared-HEAD drift is a persisted `revise` stop: revise remaining work,
rejudge, produce RED at the actual head/containing origin branch, recompile and
review, check and record a new question readback, cancel/reconcile the old
workflow, then run the revised artifact. Refreshing JSON and resuming is not a
recovery. For cures, repairs and base updates, prepare a distinct findings-based
cure set as verification work, publish the reviewed head on the existing branch,
run the printed producer command, then resume the same builder at its saved key.
Do not replace that builder or overwrite the initial admitted set.

`nspawn run list --since` exposes retained admission evidence as `valid`, `missing`,
`invalid`, `unknown`, or `not_required`. Verification writers remain visible;
unknown/missing evidence and a failed history read are never a healthy audit.

The builder is the sector agent of the touched paths. It gets the spec and the
campaign worktree. Before the first reader, it checks its own diff against the
spec. It returns its commits and each check with its command and exit.

The builder brief requires the builder to run the RED test, the member's lint
and type checks, and the touched tests only. The builder runs no whole suite
and no rail. The lead runs the heavy proof once on the head with SHIP. The lead
rebuilds its reference whenever main moves.

<!-- nott:workflow:reader -->
The lead picks the type of the round's one reader by the main risk of the diff.
For a trust, credential, permission or data-loss path, use
`nott:security-reviewer`. For a flow or a screen, use `nott:ux-reviewer` or
`nott:ui-reviewer`. Else use the reader that the sector agent names for the
diff's language: `nott:python-reviewer` or `nott:swift-reviewer`. When the diff
is mainly tests or contracts, or the sector names no reader for its language,
use `nott:pr-test-analyzer`. Dispatch it as ../review/SKILL.md (witness) sets,
with `agent` set to that type and `effort` set to `max`. Give it the frozen
candidate (../review/SKILL.md, pin) and the spec's sha256. Wait on its run with
`nspawn_result_show` and `timeout_ms`.

<!-- nott:workflow:blocking -->
Only a blocker returns the PR (../review/SKILL.md, blocking). The lead keeps
each other finding as ../review/SKILL.md (dry) sets, and that finding starts no
round. The lead never drops a finding silently.

<!-- nott:workflow:resume -->
On FIX-FIRST, the lead sends all open blockers of the round in one message to
the same builder session. For an nSPAWN builder, that is `nspawn_run_start` with
`original_run` set to the builder's run id. Never start a new builder for a fix.

<!-- nott:workflow:rounds -->
The round rules are ../review/SKILL.md (rounds). A cure round reads
the fix diff since the head that the last reader reviewed. A root cause that
goes back to the spec (../review/SKILL.md, campaign) goes to the lead's spec,
not to the builder. The revised spec is a new candidate with its own rounds.

<!-- nott:workflow:evidence -->
The lead does not trust an exit that the builder reports. Before each reader
starts, the lead runs again the builder checks on the frozen head. It uses a
disposable checkout whose process environment holds no `gh` token and no
**nMEMORY** key. It gives the reader those exits.

<!-- nott:workflow:screen-qa -->
An app UI change changes what NOTT.app draws. It is not done until `nott:qa`
gives SHIP on screenshots of the installed app (owner, 2026-10-20). After the
reader gives SHIP, the builder runs one capture on the M5. For screen QA,
install a candidate only with
`apps/apple/Scripts/qa-capture.sh <candidate-commit> <output-directory> -- <capture-command> [arguments...]`.
Set `NOTT_APP_CLI_PATH` to the executable local stand-in CLI. The command pins
the candidate as CLAUDE.md (The Apple app) requires. It gives the output
directory to the capture command as its last argument. It restores the saved owner app with
`install.sh --rollback` on success, failure, INT and TERM. It checks the original
commit, bundle id and one registered NOTT.app. It holds the shared build lock
through restore. INT and TERM wait for an installer; only the capture child
stops. Accept only exit 0 and the last line `restored <commit>`. The capture command must capture each changed screen and
each window that shows the same component. Capture both themes and each changed
icon control under hover. The lead puts the screenshots where `nott:qa` can read
them. It starts `nott:qa` with `nspawn_review_start` on opus. Give the reader the
screenshot paths, the spec's items, the touched surfaces and the diff. FIX-FIRST
resumes the same builder. The review follows ../review/SKILL.md (rounds),
with no numeric limit.
The lead does not merge an app UI change without that SHIP on the head it merges.
The rules are references/app-ui.md.

<!-- nott:workflow:merge -->
On the reader's SHIP, the lead merges only at the head in its `Candidate:`
line and only when its own record has no blocker whose last verdict is FIX-FIRST,
with `gh pr merge <PR> --squash --match-head-commit <that sha>`. It delivers by
the ship route (../ship/SKILL.md). For an app UI change, `nott:qa` also gives
SHIP on that head first (screen-qa). A later head goes back to a reader.

<!-- nott:workflow:convergence -->
The lead may ask Codex as a cold GPT judge through nSPAWN whether the work
converges. The judge chooses whether to continue with the same builder, revise
the spec, or stop at needs-human. The lead gives the judge the spec, the
reviewed head, the open findings and the cure history. The lead asks because
of the findings, never because of a round count. The lead records the judgment
and its reason, acts on it and reports it to the owner. A revised spec gets a
cold review before a fresh builder starts. A decision to continue resumes the
same builder.

<!-- nott:workflow:needs-human -->
An open blocker stops the merge. The lead or judge may stop work when a
builder cannot cure a finding within the accepted result, or when the work
needs a redesign. For that stop, the lead, in the main session, ingests one
**nMEMORY** task capsule tagged needs-human. The capsule holds the PR number,
the escalated head sha, the PR's base branch and the spec path. It holds each
open blocker with its file:line and mechanism. It also holds the reason for
the stop, the options and the lead's recommendation. The options are a cure
revision or a redesign. For a cure revision, the lead adds a spec revision
that states the required behavior for each open blocker. It adds no scope. For
a redesign, the lead adds a spec revision that changes the design. Follow
../review/SKILL.md (campaign) when its rule requires redesign. Before work
resumes on a revised spec, a cold reader reviews it under the spec's own
subject. Then a fresh builder works on that revision. The PR's next review
brief names that revision. The lead records the decision and its reason on the
needs-human capsule and reports them to the owner. Only the owner's own
`/nott:accept <PR>` permits a merge with an open blocker (../accept/SKILL.md).

<!-- nott:workflow:production-line -->
Run a multi-unit campaign by the method in ../plan/references/campaign-loop.md
(Shape): one branch per PR, writers deliver commits, the lead integrates. The
pipeline above sets review and proof timing. A writer runs the failing
regression test first when the project has tests.
