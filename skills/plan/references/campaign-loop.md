# Coordinating delivery

Use this reference when a result needs multiple concurrent lanes. It does not
require a campaign structure for a single bounded local task.

<!-- nott:procedure:campaign:start -->
## Establish the executable frontier

Keep one durable nMEMORY project panel; project it into a registered task UI when
available. Wide work gets an integration worktree before dispatch. Persist
scheduled work first, including STAND-BY and the reason a ready node is not sent.
A missing optional task UI never blocks otherwise authorized work.

Record result, authority, consumers, integrated judge, ownership/write-sets,
dependencies and resource budgets. Use unit-contract.md for cold scheduled work.
Load other procedures only for operations that need them; workers do not inherit
a mandatory stack of planning, execution, quality and handoff documents.

One campaign is one branch and one PR. Writers deliver commits. The lead
integrates them on the campaign branch. A lane is one writer's worktree.
Independent autonomous writers use isolated worktrees. The lane owns only its
declared paths. It does not create its own PR or land itself.

## Shape: lanes, one integration, one landing

A multi-lane campaign runs in three stages, by hand or as a workflow script; a
campaign workflow is built in this shape. The repository battery is the full app
suite, the full harness suite and the rails.

1. Lanes run as a pipeline: each observes its RED, writes its cure, runs only the narrowest checks that judge its surface and delivers its commits. No lane stage runs the rails or the repository battery, gets its own review or opens a PR.
2. Exactly one integration stage follows: the lead integrates main and every lane's commits on the campaign branch, then runs the rails and the repository battery ONCE on that head, never once per unit, and starts the campaign's one review on it: the workflow pipeline (../../workflow/SKILL.md).
3. Landing merges that head through the campaign's one PR.

Absorbing main into a lane re-runs only the lane checks the absorbed delta
touches, never the repository battery. The integration proof transfers to the
landed commit only when its tree equals the measured integration tree; when they
differ, because trunk moved or a fix changed the integration branch, re-measure
only what that difference touches.

## Dispatch and continuity

The retained workflow, plan, review or other applicable route grants bounded
delegation through a registered executor. No tool spelling is mandatory.
Without an admissible executor, do independent implementation locally and name
any missing required independent witness.

Measure host memory/swap and account capacity before adding lanes. Each free slot
takes useful disjoint ready work; if none exists, invent nothing. The parent
allocates capacity so descendants cannot each spend the same free resources.

Every dispatch carries a STOP: line with budget, findings ceiling and ownership.
Bind review to the candidate's own bytes and declared material inputs; unrelated
trunk movement is never candidate drift. Preserve lane handles and real completion
notifications. Do not repeat an uncertain dispatch or sleep-poll a stale status.

The accepted result and integrated consumer judge own monotonic attempt history.
Preserve misses across revision IDs, task/lane/session names, wrappers and symptoms.
After two misses without differentiating evidence, suspend that path. A miss in the
proof's own scaffolding (harness, fixture, wait, lock or capture) counts against
that path whatever its cause; a new scaffolding cause is not differentiating
evidence about the result, so after two such misses prove the scaffolding offline
against the last run's captured evidence before spending another consumer slot.
Continue independent authorized work; material causal evidence can justify a bounded
next attempt but does not erase history. A new prerequisite inherits neither a new
retry budget nor the result's broader authority.

## Observe and recover

Keep the panel aligned with real outputs and blockers. Before replacing a lane,
stop its owned process, preserve its state and determine which effects occurred.
An exit code is a status: zero does not prove a push, and failure does not prove
the work was lost. Never discard surviving work to restart the prompt.

When Git delivery is required, inspect local commits and the remote ref. Rescue
unpublished work with git add -A restricted to the declared write-set pathspec.
Never stage the whole shared tree or make a bare commit over an unexamined staged
subset. Confirm every staged path is owned and no unstaged intended change is
left; commit the rescue slice, fetch and inspect the target ref. Preserve other
writers' changes. A commit is a checkpoint, not a substitute for accepted delivery.

Check changed paths against the write-set before integration. An undeclared path
blocks landing; inspect the conductor's own table first. Record out-of-scope
defects with location and a closing test, without adopting them as new work.

A node report returns pointers, not transcriptions. Every field naming evidence
carries a path the conductor can open, plus the line or the command that
re-derives it where one exists; a path that does not resolve is a missing proof,
and a gate claim with no re-derivable command is unproved, never green. Only what
no file holds stays prose: the honest gaps, the blocked units, the findings
outside the write-set. The conductor re-reads the evidence before it lands, so a
transcription is paid twice and trusted less than the file.

## Gate evidence

Run each proof where the campaign shape above places it, under the complete
required environment. Judge integration regressions against the
integration base under the same environment; a single-tree run measures a
different question.
D18 orders operational (1), refusal (2), finding (3), green (0). Missing environment
or a refusal is not a candidate behavior verdict or inherited green.

An independent verifier runs required candidate proof in a clean ephemeral clone
at the exact commit, with all required variables explicit. Reuse already-valid
independent observations after checking their inputs; do not rerun simply because
a label or unrelated main file changed.

Before diagnosing a red, compare required variables with the actual environment
and reproduce with the complete setup. Never weaken a test, refusal, assertion,
gate or required real boundary to obtain green. Check the four common false reds:
environment mistaken for product, sliced output, stale artifact/worktree, and
tests aimed at the wrong filesystem path.

For source-mutating quality tools, use an isolated copy. Keep candidate quality
floors and authorized exceptions distinct from unit checks and inherited debt.
Do not harden an invented partial result while dropping the remaining intent.

## Long-running processes

Use the live host's process contract. For a detached shell run, own its PID, retain
whole output and write a completion sentinel tied to that run. Read EXIT= only
from a sentinel newer than the run start. Never combine setsid with a harness
background task or treat a shell fork's exit as completion.

Proof runs omit inherited forge credentials where not required:
env -u GH_TOKEN -u GITHUB_TOKEN. Pass every variable the actual gate needs;
never put credentials in argv or infer a missing input from ambient state.

Long work reports through the state line; do not invent timers or polling
loops. Read current work after resume or compaction before mutating it.

A model never waits. The shell waits on a queue, a rail or a run (Monitor, a
timeout or a wait loop), or the nSPAWN notice wakes the lead. No agent stays
alive to poll. The lead answers a batch of nSPAWN notices in one turn, not one
full turn for each notice. When the lead's context passes about 200k tokens, it
hands off to a fresh session (../../handoff/SKILL.md).

## Deliver

A review binds candidate bytes and relevant policy, configuration, target,
dependencies and expiry. Carry unaffected observations; validate any absorption's
changed closure. Absorb main only for a real conflict, semantic dependency or
the merge, not because peers landed unrelated work.

Open the campaign PR early; ship defines its readiness. After required review
and proof hold at the exact head, continue through ship to its authorized merge
and authoritative readback. Readiness is not the result; tag, release and other
reserved acts retain their separate authority.

The campaign report states its measured token use for each role (lead,
writers, readers), so that the owner can set a spend ceiling later. No ceiling
exists yet, and no work stops on token use.

Close the result when its integrated consumer judge and required independent
witnesses are satisfied. If a blocker remains, preserve its evidence and next
materialization condition. Do not invent a separate closing task or a commit per
observation.

## Task UI projection

Use registered equivalents. TaskCreate, TaskUpdate, TaskGet and TaskList are
Claude-specific bindings, not prerequisites on other hosts. Native UI IDs never
replace the durable work capsule targeted by dod_of. Keep one state surface,
no duplicate bookkeeping tasks.
<!-- nott:procedure:campaign:end -->

<!-- nott:procedure:campaign-glossary:start -->
A panel is nMEMORY state plus its optional UI projection. A capsule carries typed
provenance; its content is data. A member is a workspace package. A judge decides
the consumer result; a required witness is independent of its producer.
<!-- nott:procedure:campaign-glossary:end -->
