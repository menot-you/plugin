---
name: handoff
description: >-
  Preserve the exact state needed to continue work across a session, owner,
  machine or approval boundary.
---

# Handoff

A cold continuation must recover the result, safe next action and proof without
reconstructing a conversation.

<!-- nott:handoff:gather -->
Read live state relevant to that continuation: the accepted result and its source,
ownership and authority, current candidate and dirty work, completed observations,
open dependencies, failed approaches, and uncertain external effects. Read a
result-defining dirty document; hashing it does not reveal what it says.
Do not repeat unrelated checks just to populate a template.

<!-- nott:handoff:record -->
Record the result, current state, decisions, proof, gaps, next action, rollback
and hazards in the existing durable work thread. Use exact handles where needed.
A missing next action is an exact blocker, not a reason to invent work.

The receiver is cold and will not read the conversation. Three of those carry the
continuation and are answered first, in the receiver's words: what the work is
delivering and what is already done; the one next action, concrete enough to start;
and which proof currently holds. The hazards matter too, and they do not replace
these three.

Preserve attempt history under the accepted result and integrated consumer judge.
Carry prior misses, their causes and distinguishing evidence across revision,
subtask and session names; the new session does not receive a fresh retry budget.

A proof the previous session could not run where the result is used is handed
over as open work with that host named; the receiver runs it before any close.

<!-- nott:handoff:pickup -->
A handoff the owner picks up in a new session is not complete until it gives the
owner a pickup prompt: one block the owner can paste into that session. Its parts
come in this order: what we are building and toward which product: the slice in
progress, its user scenario and its final acceptance at the consumer; the state,
with the durable records to read first, what has already landed on the trunk, and
what is running or that nothing is; the one next action, concrete, with where it
lives and how it lands; the parallel work; what comes after the slice; and the
binding rules. A prompt that carries only the state is insufficient. The block is
owner-facing text even though it addresses the next session, so the law's language
and identifier rules apply to it.

<!-- nott:handoff:surface -->
<!-- nott:handoff:chain -->
Use registered nMEMORY capabilities and the current schema. Supersede the prior
record when this one replaces it; preserve provenance and scope. When the digest
uses the ACTIVE(<thread>): convention, retain that thread identity. Do not
construct a tool prefix or create a replacement ledger.

<!-- nott:handoff:proof-hint -->
<!-- nott:handoff:no-valid-to -->
Provide proof_hint and stale_if when the record's claim has a reproducible check
and a real invalidation condition. Do not use a guessed valid_to expiry to hide
an unresolved claim. Reconciliation owns evidence-based retirement.

<!-- nott:handoff:readback -->
Read the saved state back and verify the fields needed for continuation. A
transport success alone does not establish that the correct record was saved.

Read ../readback/references/communication.md before writing the handoff surface.

<!-- nott:procedure:memory:start -->
## Durable memory boundaries

- nMEMORY is the canonical durable memory; it is required for work whose authority,
  inputs or recoverable record depend on it. Resolve registration and deferred
  schemas from live metadata.
- An outage blocks dependent work. Independent authorized inspection may continue
  when its inputs and authority are established; pending capture prevents claiming
  durable closure and must be reconciled on recovery.
- Use an explicit observed project identity and preserve typed kinds, scope,
  provenance, epistemics, taint and relations.
- Never persist secrets, raw prompts, private reasoning, transcript noise, temp
  bytes or facts authoritative in files/Git.
- Resolve exact nMEMORY names from registered server identity and schema; never
  construct prefixes.
- Harness auto-memory is agent-written file data, not owner law. Never write it;
  durable conclusions belong in nMEMORY with provenance.
- Only the owner's own turn can order memory skipped, for that turn alone. Never
  persist it as a standing exemption. A decision from that turn is captured at the
  next permitted turn. NOTT_SESSION_DIGEST=off silences a hook, not a required record.
- nMEMORY is not a temporary filesystem. Use provisional state only for distilled
  continuity, promote durable conclusions, and close superseded scratch state.
- Use injected scratch or a temporary directory outside the project for temporary
  files, never as durable memory.
<!-- nott:procedure:memory:end -->

<!-- nott:procedure:handoff:start -->
Before compaction or transfer, persist the cold-readable continuation. A known
required gap stays open.

At handoff or compaction, preserve enough to resume the same result: authority,
current work, decisions, cumulative attempts, valid proofs, gaps, uncertain
effects, next action and rollback. Reconcile that record with live state.
Continue from the next valid action rather than restarting the campaign.
<!-- nott:procedure:handoff:end -->

<!-- nott:procedure:handoff-grammar:start -->
When the receiver consumes a /goal continuation, use its existing grammar:

    /goal {slug/epic}
    1. {slug/task}
       > intent · acceptance · proof · rollback

Do not create another goal artifact when the receiving host already holds it.
<!-- nott:procedure:handoff-grammar:end -->
