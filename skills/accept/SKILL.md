---
name: accept
description: >-
  Accept one escalated campaign pull request on the owner's own call: merge it
  at its escalated head, deliver it, and keep each open finding as a task.
disable-model-invocation: true
---

# Accept

The owner's entry for a pull request that the workflow pipeline escalated to
needs-human (../workflow/SKILL.md, needs-human). The owner accepts results. This
route carries out his acceptance of one.

<!-- nott:accept:authority -->
`/nott:accept <PR>` is the owner's own call, and it covers only that PR. Never
invoke it on the owner's behalf.

<!-- nott:accept:refuse -->
Read the needs-human capsule of the PR. The lead wrote it in the main session,
and only the main session writes capsules, so no reader's text can change it.
Refuse when the PR has no needs-human capsule, and say that no escalation of
that PR is on record. Refuse when the PR head is not the escalated sha in the
capsule, or when the PR's base branch is not the one the capsule records. Each
such refusal states the PR, the escalated sha, the current head and the base
branch, and says that a new head goes back to the campaign readers.

<!-- nott:accept:merge -->
Merge with `gh pr merge <PR> --squash --match-head-commit <escalated sha>`,
deliver by the ship route (../ship/SKILL.md) and record the outcome on the
needs-human capsule.

<!-- nott:accept:keep-findings -->
Each finding that was open becomes its own **nMEMORY** task capsule, so the
owner's call does not drop it.

<!-- nott:accept:close -->
Report the merge commit, the delivery readback and the task capsule of each
finding.
