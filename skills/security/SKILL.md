---
name: security
description: Model trust boundaries, trace untrusted input to privileged actions, harden controls, and verify fail-closed behavior.
---

# Security

Use for auth, identity, secrets, untrusted input, network exposure, data mutation, migrations, infrastructure, release, or destructive actions.

## Inputs to lock

- Assets and security goals.
- Actors, identities, trust boundaries, and entry points.
- Privileged actions and data stores.
- Current controls, failure history, and accepted risk.
- Authority and rollback for any change.

## Method

1. Draw the data and authority flow across every trust boundary.
2. Enumerate attacker-controlled inputs, credentials, tokens, files, messages, and network paths.
3. Trace each input to a privileged sink. Record validation, authorization, isolation, logging, and rate limits along the path.
4. Identify abuse cases: privilege escalation, confused deputy, replay, injection, path escape, unsafe deserialization, race, resource exhaustion, and secret disclosure.
5. Confirm least privilege, explicit allow rules, secure defaults, bounded resources, and fail-closed behavior when dependencies are missing.
6. Bind approval to the exact candidate and prevent substitution between review and the action.
7. Keep secrets out of command lines, logs, generated artifacts, and durable handoffs.
8. Add negative tests at each boundary and prove denied actions cause no state change.
9. Verify audit records are useful without leaking sensitive data.
10. Define rollback, recovery, and post-action readback before high-impact action.

## Findings

For every finding include asset, entry point, broken control, privileged-action sink, realistic impact, proof, and a clean remediation. Rank severity from demonstrated reach and preconditions, not alarm language.

Do not approve a high-impact action while identity, candidate binding, rollback, or independent verification remains ambiguous. Surface one real blocker and one safe next action; never bury security uncertainty in a long option list.
