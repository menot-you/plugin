# Writer brief template

The lead fills each `<field>` for the unit.

## Result

<One observable result.>

- Cwd: `<absolute clone path>`.
- Unit branch: `<unit branch>`.
- Write-set: `<files that the result can change>`.
- Inputs: `<spec path, spec sha256, decisions and source paths>`.
- Reference: `<comparison commit>`.
- Writer role: `implementation` for product work; send `native_write=true` and
  `red_record=".nott/plans/<plan>/red/<unit>.json"` explicitly, including each
  continuation. Verification is only for verification work, never a lock bypass.
- RED inputs: `<judged-set path, exact producer-record path and checked digests>`.
  All selected tests must fail at the standalone clone's exact full HEAD.
- Acceptance: `<observations that prove the result>`.
- Main risk: `<failure that the proof must detect>`.
- STOP boundary: `<condition that requires a return to the lead>`.

## Proof

Use ../../../NOTT.md (Evidence and review) for the RED sequence.
Use ../SKILL.md (builder) for builder checks and campaign proof.
Use ../../execute/SKILL.md (self-review) for writer self-review.
Use ../../../../CLAUDE.md (Local verification) to select the Reference commit.

- Reached tests: `<test files and why each file reaches the change>`.
- Check commands: `<test, lint and type commands>`.
- Evidence: `cwd/.nott/<unit>`.

If initial prepared HEAD drift stops admission, return to the lead for the printed
revise-and-readmit procedure: remaining-work plan, new RED and compiled witnesses,
review, check/readback, old-workflow cancellation and key reconciliation, then a
new workflow. Never refresh JSON and resume the old initial admission.

For a cure, repair or base update, use the persisted witness-wait coordinates.
The lead prepares a distinct findings-based cure set as verification work, ensures
the reviewed head is on the existing origin branch, runs the printed producer and
resumes the same builder. Keep initial witnesses unchanged. Product edits wait for
that new exact-head admission. Monitor evidence with `nspawn run list --since`:
`valid`, `missing`, `invalid`, `unknown`, `not_required`; do not hide verification
writers or interpret failed history reads as clean results.

Classify each failing test id against a same-host reference.

1. Create a new reference directory under `cwd/.nott` from `git archive <Reference>`.
2. Record the reference sha.
3. For each failure, run the same failing ids with the same inputs on that host.
   If a new RED test is absent on the reference commit, copy only that test into the reference and record the copy.
4. Mark each id as inherited or introduced and record the command, exit code and classification evidence.
   If the reference is not available, record the proof gap.

## Authority

Copy the numbered rules of ../../../agents/worker.md into the brief. An nSPAWN child with another agent does not get them.
Use ../../execute/SKILL.md (owner-look) and ../SKILL.md (screen-qa) for install and presentation work.
Use ../../../README.md (Native hook coverage) for PR-body checks.

- PR body: `cwd/.nott/<PR body file>`.

## Return

Use ../../../agents/worker.md for return evidence and blockers.
Use ../SKILL.md (builder) for the builder return.
