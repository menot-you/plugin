---
name: plan
description: Convert a ratified result into an execution-ready dependency graph whose units a zero-context executor can land without inventing a decision.
---

# Plan

Use for non-trivial implementation, cross-cutting change, production work, or any result that needs several dependent actions. Do not size by time.

## Inputs to lock

- Ratified result contract.
- Current code and repository state.
- Active overlapping work.
- Affected callers, services, state, and trust boundaries.
- Required review and ship gates.

## The executor assumption

Write for a skilled engineer with ZERO context for this codebase and no access to this conversation. Each unit carries everything its executor needs: exact paths, the complete change content where code is the deliverable, exact commands with expected output, and the interfaces neighboring units rely on. An executor who must ask a question or invent a decision marks the plan not ready — the shared-understanding gate at the plan-to-work seam.

## Method

1. Open with the home: problem, resolved result, keystone next action, proof path, and the dependency graph as a diagram.
2. Map the file structure before drawing units: every file created or modified, one responsibility each. Follow existing patterns; split only what the goal touches.
3. Confirm every capability named by the engineer is in scope or explicitly out with a reason; do not make the engineer choose a skill, agent, or backend.
4. Identify the keystone: the one unit other units depend on.
5. Split work into atomic units, right-sized: the smallest unit that carries its own proof cycle and is worth a fresh reviewer's gate. Fold setup, scaffolding, and documentation into the unit whose deliverable needs them; split only where a reviewer could reject one unit while approving its neighbor.
6. Each unit carries:
   - a human-readable id and testable acceptance criteria;
   - exact files to create or modify, with line anchors when modifying;
   - interfaces — consumes: exact names and signatures taken from earlier units; produces: exact names and types later units rely on (an implementer sees only their own unit; this block is how neighbors stay consistent);
   - proof-first steps in order: write the failing check, observe it fail, apply the minimal change, observe it pass, commit;
   - caller reach, risk tier, and trust boundary;
   - required independent review;
   - shipping action, post-action readback, and rollback.
7. Express dependencies as `blocked_by` edges. Validate the graph: all edges resolve, no cycles exist, roots are intentional, and topological order is possible.
8. Run the cold-executor test. If a decision is missing, put a `[DECIDE FIRST]` block at the top with one recommendation.
9. Self-review against the contract: (a) coverage — every requirement points at a unit that implements it; (b) placeholder scan — hunt the failures listed below; (c) interface consistency — names, types, and signatures match across units.
10. Run an adversarial pass over decisions, coverage, failure paths, and rollback. Revise until no blocking finding remains.

## Every unit carries its senior bar, or the plan has deferred quality to nobody

A unit that names a deliverable and not the threshold it must meet has moved the quality decision to whoever implements it, at the moment they are least able to argue for it. The bar is a pull request the most sceptical reviewer at a bank approves, and a plan states it in numbers.

Each unit MUST therefore also carry:

- **The thresholds it is held to**, by name and value, not by adjective. Complexity, function length, nesting, argument count are measured by tools the repository already runs; a unit that will exceed one states that up front with an owner, a reason and an expiry — never by loosening the threshold, because debt admitted that way is invisible forever.
- **Its test-strength bar as mutation, never coverage.** Coverage says a line ran; mutation says something would have noticed it being wrong. A unit whose acceptance is a coverage number has not stated a bar.
- **The falsifiability step, written out.** Not "add tests" — the exact mutation to apply to the SOURCE, the red it must produce, and the green after reverting. A test that has never failed proves nothing, and inverting an assertion is not that proof.
- **Whether the unit's fixture can express the failure it guards.** A double more permissive than the real subject makes every red written against it vacuous. Where a unit's proof depends on a fake, the plan says what that fake CANNOT model — that sentence is where shipped defects hide.
- **The rung its mechanism honestly holds.** A unit claiming enforcement it cannot perform is a finding, not a unit.

**Structural units are planned before the units that would relocate their defect.** Decomposing a module before its invariants are declared and tested moves the defect somewhere harder to see. Where both are needed, the ordering edge is `declare → prove → fix → split`, and it is a `blocked_by` edge like any other.

## Placeholders are plan failures

NEVER write: "TBD" · "TODO" · "implement later" · "add appropriate error handling" · "handle edge cases" · a test step without the actual test content · "similar to unit N" in place of the repeated content (executors read units out of order) · a name, type, or signature defined in no unit. A step that states what to do without showing how, where code is the deliverable, is a blocking finding.

## Output

Return one durable master plan plus atomic work units. It must distinguish decision from execution detail, keep one active result visible, and let the executor derive the clean diff from current code.

No time estimates, vague phases, hidden deferral, or orphan follow-up. A deferred requirement needs its own durable work unit and dependency edge.
