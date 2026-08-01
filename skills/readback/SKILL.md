---
name: readback
description: Lock shared understanding before substantive work — translate the ask into executable form and read it back as numbered, falsifiable statements the owner confirms by number.
---

# Readback

Use before substantive work whenever ambiguity affects the result, authority, safety, scope, or
a handoff — and at every delegation seam: owner→session, session→subagent, PRD→issue. This
skill executes the shared-understanding gate: the numbered list IS the claim of
understanding, and per-number confirmation is the gate. Never claim "yes, I understood."

Fast path: for low-risk reversible work with an obvious next action, keep the gate internal —
state the working assumption, act inside granted authority, and bind the close to observed
verification. Do not turn the gate into ceremony.

## Method

1. Read the current artifacts and repository state first; anchor every statement in what is
   actually there, never in memory of it.
2. Translate the ask into the executable form — **Task** (one goal) · **Input** ·
   **Constraints** (including what NOT to do) · **Output** · **Verify** (observable success
   criteria). One prompt = one goal: split a compound ask into chained single-goal units.
3. A success criterion that cannot be verified is a numbered gap to surface, never a license
   to improvise.
4. Write the readback as numbered, atomic, falsifiable statements. Label inferences and
   separate them from what the owner said. Give each load-bearing term one verified meaning;
   an ambiguous term gets its own numbered statement.
5. Deliver with default-confirm: "what you do not mark, I take as said" — the confirmer
   corrects or confirms by number.
6. Block: the gated step stays `blocked` until the readback returns confirmed; the next step
   does not fire without it. A readback that does not block is decoration.
7. Apply corrections by number and re-emit only the changed statements, until confirmed.
8. Recurse across the seams: a dispatched subagent reads back acceptance criteria and bounded
   scope before working; an issue a cold agent cannot execute without asking is not ready.

## Orientation asks — answer with the story, not the ledger

An orientation ask ("what's going on?", "where are we?", "what are we actually doing?",
"why?") is a request for the STORY, and the reply MUST open with it in product language:
name the feature and what it does for its user, its proven state, why the current work
exists in the feature's service, the honest proportion (feature vs. debt vs. gate), and
where it lands next. No ceremony, no section scaffolding, no artifact names or ids unless
one is the next action to type. Technical mechanics appear only as consequence ("any machine
rebuilds the same bytes without internet"), never as inventory.

The numbered register is NOT the default reply to an orientation ask. It returns exactly
when the reply carries decisions the owner must dispose of — story first, then only the
numbered dispositions. Calibration source: owner 2026-07-22, after a numbered status
readback to "o que ta rolando?" was re-asked as "qual a story? sem cerimonia, qual a
feature" — the story answer is the one the owner wanted.

## Output

The confirmed readback record — the executable form plus the confirmed numbered statements
and any surfaced gaps — attached to the work it unblocks; it becomes part of that work's
contract.

The gate is closed when the confirmer has disposed of every number and no load-bearing term
is left unverified.
