---
name: plan
description: Convert a ratified result into an execution-ready dependency graph whose units a zero-context executor can land without inventing a decision.
---

# Plan

**Normative scope.** Sentences carrying **MUST**, **MUST NOT**, or **NEVER** are
mandatory method clauses. The client-loaded skill is the instruction mechanism;
`tools/doc-lint.sh` gates the declared scope and normative hedges in this file.

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

## Placeholders are plan failures

NEVER write: "TBD" · "TODO" · "implement later" · "add appropriate error handling" · "handle edge cases" · a test step without the actual test content · "similar to unit N" in place of the repeated content (executors read units out of order) · a name, type, or signature defined in no unit. A step that states what to do without showing how, where code is the deliverable, is a blocking finding.

## Output

Return one durable master plan plus atomic work units. It must distinguish decision from execution detail, keep one active result visible, and let the executor derive the clean diff from current code. Its opening declares the plan's normative scope and current enforcement rung; plan review rejects an omitted declaration.

No time estimates, vague phases, hidden deferral, or orphan follow-up. A deferred requirement needs its own durable work unit and dependency edge.
