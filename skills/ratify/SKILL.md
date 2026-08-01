---
name: ratify
description: Turn an accepted direction into a locked decision and result contract with authority, proof, rollback, and stop conditions.
---

# Ratify

Use after direction is chosen but before planning or autonomous actions. Ratification removes ambiguity; it does not add implementation detail. Collapse the contract for the engineer into result, proof, authority, rollback, and the first blocked decision.

## Inputs to lock

- Accepted direction and the reason it won.
- Observable result.
- Scope in and explicit scope out.
- Non-negotiable constraints.
- Reversible authority already granted.
- Effects that require the engineer's approval.
- Independent verification required for acceptance.
- Rollback path and stop conditions.

## Method

1. Read the decision source and current repository facts.
2. Rewrite the result as an observable state, not an activity.
3. Enumerate all capabilities named by the engineer. Put each one in scope or out with a reason, without exposing skills or agents as choices.
4. Separate preparation from the action. Mark destructive, public, production, financial, credential, data-loss, and merge-to-main actions as gated unless authority is explicit.
5. Define the witness that can prove the result without trusting the implementation's own claim.
6. Define rollback in operational terms and state any irreversible portion.
7. Define stop conditions: missing authority, unexpected reach, failed witness, unsafe rollback, or conflict with current state.
8. Check correctness, reliability, maintainability, reversibility, security, and reach.
9. Return one ratified contract or one blocking question. Never return a menu, multi-question survey, or process ritual as the product surface.

## Output

Produce a compact record with:

- Decision and rationale.
- Outcome.
- Scope in / scope out.
- Constraints.
- Authority and gated actions.
- Witness.
- Rollback.
- Stop conditions.
- Known trade-off.

The record is ready when a cold planner can build work units without inventing a product or safety decision.
