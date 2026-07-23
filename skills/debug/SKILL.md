---
name: debug
description: Isolate a failure with a reliable reproducer, differentiate ranked causes, remove the root cause, and prove recovery.
---

# Debug

Use for failures, regressions, flaky behavior, or any task after one missed fix. After two missed fixes, this method is mandatory before another patch. Keep the engineer focused on the failure mechanism, differentiating experiment, and proof.

## Inputs to lock

- User-visible failure and required behavior.
- Exact environment, input, and last known good state.
- Current logs, traces, fixtures, and commands.
- Layers crossed from input to failure.
- Safe boundaries for experiments.

## Method

1. Reproduce the failure reliably. Record the command, input, output, and frequency.
2. Map the failure chain across caller, application, service, host, network, datastore, and external dependency.
3. Rank candidate causes by proof. For each one, state what observation would reject it.
4. Design the smallest experiment that separates the leading candidates. Change one variable at a time.
5. Gather proof before editing. Do not convert an error label into a cause without the mechanism.
6. Reduce the reproducer until it still fails and irrelevant layers are removed.
7. State the root cause as input, broken mechanism, and user impact.
8. Add a regression test that is red on the broken state.
9. Apply the smallest clean fix at the owning layer. Avoid retries or fallbacks that conceal the defect.
10. Prove the regression test green, run affected broader checks, and retest the original path.
11. Verify rollback and watch for adjacent failure modes created by the fix.

## Output

Return one focused debug close:

- failure mechanism;
- ranked proof and rejected candidates;
- reproducer;
- fix and why it removes the cause;
- before/after proof;
- remaining uncertainty and one next action if not closed.

If the failure cannot be reproduced, say so and stop at the best proof-gathering action. Do not claim a fix.
