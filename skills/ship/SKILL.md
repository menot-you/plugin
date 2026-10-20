---
name: ship
description: >-
  Perform an authorized merge or deployment of a reviewed candidate and verify
  the target. Keep preparation and owner-reserved release acts distinct.
---

# Ship

Make the authorized result reach its consumer and observe it there.

<!-- nott:ship:candidate-binding -->
Bind candidate, target and action to current authority and evidence immediately
before mutation. Validate relevant policy, configuration, dependencies and expiry.
Carry unaffected observations; changed or unknown reach needs the corresponding
verification. A matching patch-id alone is insufficient.

<!-- nott:ship:authority -->
Use exact authority already granted; do not ask again for a routine campaign
merge. Public, production, destructive, financial, credential, history/data-loss,
tag and release acts retain their reserved authority. Never infer a broader next
act from permission for the current one.

<!-- nott:ship:workflow -->
A campaign's merge waits for the approver stage of ../workflow/SKILL.md. On
ESCALATE nothing merges before `/nott:accept <PR>` (../accept/SKILL.md).

<!-- nott:ship:rollback -->
Read and establish a reachable rollback before high-impact mutation. Name an
irreversible portion and its accepted compensating control. Preserve in-scope
state whose loss would falsify the result.

<!-- nott:ship:act-once -->
<!-- nott:ship:stop -->
Re-read target state, required checks and review. Execute once. An ambiguous
result requires target reconciliation before any replay. Stop the dependent act
for missing authority, unvalidated material changes, unsafe rollback or unavailable
verification; preserve independent authorized work.

<!-- nott:ship:readback -->
Read authoritative target state and observe the real consumer. A local green, a
merge receipt and a completed release job each prove different things. None alone
proves installed behavior or reachability.

A session that cannot reach the host where the result is used closes with that
proof `open:`, never delivered; a sample or a smoke on another box is candidate
proof only.

<!-- nott:ship:separate-merge-deploy -->
Merge and deployment are separate bound actions. Finish the merge readback before
binding deployment to its own candidate, target, authority, rollback and proof.

Read every check's status and conclusion in one call before the merge, and
merge in a separate call; an empty conclusion is a running check. Merge with
`--match-head-commit` and read back the merged state. Use `--admin` only when
the forge refuses the merge for the missing human approval alone.

This route's prerequisites, a reviewed candidate and a merge before deployment
included, bind the merge to the trunk and the installed delivery of the merged
result. Installing a candidate for the owner's first look follows
../execute/SKILL.md (<!-- nott:execute:owner-look -->), not this route.

<!-- nott:ship:closed-targets -->
<!-- nott:ship:empty-targets -->
Deploy only named authorized targets. If this repository's plan uses a deployment
manifest, read its targets and use `tools/body/manifest.py authorize` for those operations.
An explicit targets = [] means no deployment; an absent target declaration does
not authorize one. Do not demand that schema for a merge-only task.

<!-- nott:ship:main-green -->
After merge, establish that required proof covers the actual merged bytes.
Pre-merge green alone is insufficient. Rerun affected gates when integration changes
their inputs; retain valid unaffected evidence rather than chasing moving main.

<!-- nott:ship:smoke-closes -->
For installed targets, run the accepted post-install consumer smoke. If that smoke
cannot run on the installed target without building a replica of a live service or
bypassing a host safety pin, do not build the replica or bypass the pin: read back
the installed identity, keep the unobservable behavior in `open:`, and raise the conflict once
with its measured cost. Use INTENT.md when it supplies that acceptance, not as a
mandatory additional document.
A merge is completion only when the authorized result ends at the merge.

<!-- nott:procedure:shipping:start -->
One campaign has one PR; a stack connects separate campaigns only for a real result
dependency. Never push directly to trunk, force-push or delete branches without
the exact owner grant.

Open the PR early as a draft, keep publishing the candidate and obtain the required
independent review and proof. The draft flag is the not-ready state; lift it
(`gh pr ready`) only when readiness holds. Readiness is the exact-head reader
verdicts plus the declared checks' verdict posted on the PR; a changed head must
have its current evidence validated before it is ready. Never hand-post a commit
status: each status context belongs to the program that writes it. NOTT performs
the campaign's authorized merge at that head and reads it back; readiness alone
is not delivery and the owner is not handed its routine merge. On GitHub that
merge is `gh pr merge` with `--squash --match-head-commit` at that head, read
back as state=MERGED.

The trunk advances independently. Absorb only for a real conflict, semantic
dependency or the merge itself, preserving both ends and revalidating the affected
proof. Do not repin and restart because unrelated work landed.

<!-- nott:ship:record -->
Close only with delivered proof, the exact blocker, or an execution-ready handoff.
Name any weaker method and what it cannot prove. Preserve inherited debt and
authorized exceptions separately; neither excuses the original missing result.
<!-- nott:procedure:shipping:end -->
