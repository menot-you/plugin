---
name: routine
description: Execute bounded engineering work through current-state checks, minimal changes, focused proof, and honest closure.
---

# Routine

Use for a clear, reversible engineering task whose result and scope are already locked. Keep one active result, one proof path, and one next action visible.

## Inputs to lock

- Exact result and acceptance proof.
- Allowed files and explicit exclusions.
- Current branch, working tree, and overlapping work.
- Risk, authority, rollback, and stop conditions.

## Method

1. Read the current target files and repository guidance.
2. Trace changed symbols to direct callers and affected processes. If no code graph is available, label the manual trace as limited.
3. Observe the failing state or missing behavior before editing when the result can be tested.
4. Choose the smallest clean change that removes the cause. Do not hide a failure behind retries, fallbacks, or unrelated refactors.
5. Match local style and remove only dead code created by this change.
6. Add or update focused tests that fail before the change and pass after it.
7. Run the narrow check first, then every broader gate required by the touched surface.
8. Review the diff for scope drift, security expansion, generated artifacts, and rollback.
9. Confirm no file outside the allowed scope changed.
10. Report the strongest proven state, observed verification, rollback status, and any remaining gap.

After two missed changes, stop. Switch to the debug skill and obtain new proof before another patch.

## Completion

A routine is complete only when the requested state is observed, required checks are green, scope is clean, and rollback remains available. Local green is not proof of merge, release, or live reachability. Do not close with status theater.
