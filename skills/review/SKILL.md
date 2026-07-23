---
name: review
description: Perform an adversarial, read-only review of the actual candidate against its base, contracts, tests, safety, and rollback.
---

# Review

Use for a change set, branch, pull request, plan, or release candidate. Default to read-only. Never repair findings unless the engineer separately asks for implementation.

## Inputs to lock

- Exact candidate and base identifiers.
- Required result and acceptance criteria.
- Repository rules and affected trust boundaries.
- Claimed proof and rollback.

## Method

1. Pin the candidate and base. Read the actual diff or artifact, not a recap.
2. Separate authored changes from generated or vendored bulk so meaningful logic is not hidden.
3. Trace each changed input through callers, state transitions, external state changes, and user-visible output.
4. Test six dimensions: correctness, reliability, maintainability, reversibility, security, and reach.
5. Challenge every acceptance claim with the verification that can independently prove it.
6. Look for partial failure, stale state, race conditions, idempotency failure, unsafe retry, privilege expansion, secret exposure, and rollback gaps.
7. Run focused checks when read-only execution is safe. Never mutate the candidate to make review green.
8. Rank findings by impact:
   - **Blocker** — unsafe or fundamentally wrong; cannot ship.
   - **High** — likely serious user or system failure.
   - **Medium** — real defect with bounded impact.
   - **Low** — maintainability or edge-case weakness worth fixing.
9. Cite the smallest useful location and explain input, failure path, and impact.
10. Return `LGTM` only when no blocking finding remains and required verification is green.

## Output

Lead with findings, highest impact first. Then list open questions and proof gaps. If no findings remain, state `LGTM` and name the proof reviewed. Do not pad the result with a change recap, process theater, or menu of possible review modes.
