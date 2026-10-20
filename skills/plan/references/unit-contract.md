# A ready unit

Use this reference when scheduling work for a cold executor. A unit is a bounded
deliverable with enough authority, inputs and proof to finish it safely.

## Contract

Carry the result and consumers, acceptance observations and falsifiers, inputs and
outputs, ownership/write-set, executor role, dependencies, risk, rollback and STOP
boundary. Include exact paths and commands where the receiver needs them; a
principal may discover technical details inside an observed bounded subsystem.

One deliverable may need several observations. Split only for independently
deliverable results, real dependency boundaries or exclusive ownership. Do not
create one task per observation or define closure as one commit. Commits preserve
and publish work when Git delivery is required; they do not prove consumer success.

Reuse the existing task and acceptance record. Setup, documentation, tests and
rollback belong to the result they enable, not automatically to separate units.
A missing protected input or authority blocks its dependent act; a discoverable
technical fact does not remove a principal's engineering responsibility.

## Proof and witness

Acceptance is the observable consumer result, not an artifact count or a green
suite over an unreachable mechanism. Name the integrated judge and the relevant
caller paths. Include the failure modes and test kinds the change earns. A parser,
network door or MCP must retain its required fuzz, concurrency or end-to-end proof.

Independent review is required when the unit changes executable behavior,
normative authority, a security or trust boundary, or high-impact external state,
or when repository law requires it. Artifact durability alone never triggers it,
and required review is never waived by the author.

Reuse valid evidence after checking its declared inputs: candidate bytes, policy,
configuration, target, dependencies and expiry. Revalidate the affected closure
when these change; expand verification when reach is unknown. Main movement or
a new label alone does not invalidate the evidence.

## Attempt continuity

The accepted result and integrated consumer judge own monotonic attempt history.
Record each miss, its cause or unresolved hypothesis, and evidence that would
change the next action. Preserve the history across candidate revisions, renamed
subtasks, wrappers, symptoms and sessions.

Two misses without differentiating evidence suspend that path. A miss in the
proof's own scaffolding (harness, fixture, wait, lock or capture) counts against
that path whatever its cause; a new scaffolding cause is not differentiating
evidence about the result, so after two such misses prove the scaffolding offline
against the last run's captured evidence before spending another consumer slot.
Continue unrelated authorized work and report the precise missing input. A
material observation that addresses the cause may justify a bounded next attempt;
it does not erase earlier misses. Repartitioning, another review or a new
prerequisite is not recovery.

## Required quality

Use named thresholds supplied by owner law, the repository's declared checks or
the accepted contract; never invent a floor. Name the touched unit's declared
checks and the command the repository runs them with; where it declares none, name
checks proportional to the change. Mutation is not a candidate floor unless a
current repository requirement names it; where one does, its scope, schedule and
threshold are the repository's. Otherwise the standard tool (mutmut in Python)
runs by hand on the functions it is wanted for, and a survivor it reports carries
a verdict (a test that kills it, or the tool's documented exclusion with a
reason). Preserve any separately required property-test obligation.

Distinguish unit gate proof from candidate floors and from final delivery.
A candidate cannot defer a touched member's required floors to a follow-up;
only its dated owner-signed exception applies. Explain what a fake cannot model;
mock-only success does not substitute for a required real boundary.

<!-- nott:procedure:acceptance:start -->
## Acceptance state

- Before dispatch, persist accepted DoDs as typed nMEMORY capsules related by
  dod_of to the durable work capsule. Reuse existing accepted records.
- Authority status (proposed, accepted, waived) and observed verdict
  (unmet, met, partial, failed) are independent axes.
- A waiver names the owner, reason and decision. Replace invalid acceptance through
  supersession, never by silently ignoring it.
- Mutation-prove a new judge: the unmutated subject must first be accepted where
  the mutants run, then the relevant broken behavior must produce RED and the
  restored behavior GREEN. Otherwise mutant deaths may be trivial.
- The result closes when its accepted consumer observations and required independent
  witnesses cover the actual candidate without a required gap.
- The checks and limits the repository declares bind to the candidate. A unit
  closes on the checks its repository declares for it, with its intent proved;
  unit green is not the final consumer result.
<!-- nott:procedure:acceptance:end -->
