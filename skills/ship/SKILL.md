---
name: ship
description: Execute one reviewed action with exact candidate binding, explicit authority, rollback readiness, and independent readback.
---

# Ship

Use only when implementation and required review are complete. Shipping means producing the intended real-world result and proving it, not merely preparing a command. The surface stays one action, one verification, one rollback path, one result.

## Inputs to lock

- Exact reviewed candidate identifier and immutable digest when available.
- Target environment and action.
- Green required checks and review verdict.
- Authority for the action.
- Rollback command, data recovery need, and stop conditions.
- Independent post-action verification.

## Method

1. Re-read candidate, target, current state, and authority immediately before the action.
2. Confirm the candidate being executed is byte-for-byte the reviewed candidate.
3. Confirm required checks are green and no new change invalidated review.
4. Verify credentials, target, backups, capacity, and rollback without exposing secrets.
5. State the action boundary: what will change and what will not.
6. Execute one action once.
7. Read back authoritative state and run the independent smoke check.
8. If the result is ambiguous, determine whether the target changed before any retry.
9. On failed acceptance, stop further rollout and use the prepared rollback when its trigger is met.
10. Record candidate, target, proof, result, rollback status, and any remaining gap.

## Stop conditions

Stop before the action on candidate drift, failed check, missing authority, unknown target, unavailable rollback, or missing verification. Stop after the action on ambiguous state or failed acceptance; never repeat blindly.

Completion requires observed target state and independent verification. A merged branch is not a release; a completed release job is not proof of user reachability. Close with the result, proof, rollback status, and remaining blocker only.
