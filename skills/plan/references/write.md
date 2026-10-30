# Plan write

The lead conducts this recipe. It is the only procedure that writes a plan
(../SKILL.md, write). It runs after plan mode ends, never in plan mode
(../SKILL.md, native planning boundaries). For each agent step, the lead starts
an nSPAWN run with `agent=<name>` and `read_only`. A run gives its answer as its final text and
writes nothing.
Only the lead writes, and only under `.nott/plans/<slug>/`, which Git ignores.
In step 5, the lead also makes one snapshot of the base outside the repository
and deletes that snapshot at the end of the step.
The paths below are in that directory.

The lead does not read an answer to save it. It saves each answer from the
shell:

```bash
nspawn result show <run-id> | jq -r .final_text > <file>
```

The lead reads only the answers of the test judges, the review verdicts and the
output of `nott plan check` and `nott plan test`.

## Steps

1. **Recover.** Recover from nMEMORY the owner decisions that the request
   touches. Choose the slug. Write `INTENT.md` with the owner's verbatim words
   from the accepted decisions. Add no other text to that file.
   Keep `INTENT.md` at most 4096 characters.
   When the owner's words are longer, quote the decisions that state the result, within that bound.
   Write the questions that the code can answer.
2. **Explore.** For each question, start five or more `explorer` runs in one
   swarm. Save each answer as `explore/Q<n><letter>.md`.
3. **Plan.** Start one `planner` run. Give it the owner decisions and the paths
   of the answers, and mark the answers as hypotheses. Give each unit an id,
   agent, class, count, operation, reader, write set, deadline, silence, inputs,
   outputs and `depends_on`. Give its tests as a pytest file and name, with the
   RED lines. Give each host-proved acceptance item as one command, with its
   host and an optional threshold.
   Give each change unit its test set, `tests/<unit>.md`, as a file parameter
   and as an input of the unit.
   Give the install targets with their host (or none), the intention reader and each file parameter.
   Save its answer as
   `PLAN.md`. From the repository root, run
   `python3 plugin/scripts/floor.py judge --profile principal .nott/plans/<slug>/PLAN.md`.
   When the floor gives a finding, start the `planner` again with that finding.
4. **Review.** For each round `N`, write `review/r<N>/brief.md`. It has the line
   `Candidate: <slug>@<sha256>`, where `<sha256>` is the full sha256 of the
   current `PLAN.md`. A run cannot calculate it, so the lead writes it. In
   round 1, start one `plan-reviewer` run and one `adversarial` run with
   `nspawn_review_start`. ../../review/SKILL.md (rounds) sets the rounds, what
   each round checks and when a finding blocks. Save each answer as
   `review/r<N>/<agent>.md`. The last nonblank line of an answer is its verdict
   line, `SHIP` or `FIX-FIRST`. The docstring of `harness/nott_harness/plan.py`
   holds this rule and the layout of the review record.
   - When a verdict line is `FIX-FIRST`, start the `planner` again with the
     open findings. It revises the final text of `PLAN.md`.
   - The next brief lists only the open findings of the previous round. It goes
     only to the readers that raised them.
   - Each reader that answered `FIX-FIRST` must answer `SHIP` in a later
     `PLAN.md` round on the final `PLAN.md`. A compile round does not clear it.
     The check refuses the plan until it does.
   Set `subject` to the plan's subject and `candidate` to the PLAN.md sha256.
   The first subject is `<slug>`; version k uses `<slug>/v<k>`. Each reader
   uses the same subject and candidate for that round.
5. **Tests.** Fetch origin's base branch that `PLAN.md` declares. Use `main`
   when it declares none. Freeze its head as one commit, `<base>`.
   Make one snapshot with `plugin/scripts/review.sh snapshot <base>`.
   For each unit, start five `test-writer` runs in one swarm. Then start
   one `test-judge` run with their drafts. Give every run that snapshot as its
   working directory. Save the judge's answer as `tests/<unit>.md`.
   - For each change unit, run
     `nott plan test .nott/plans/<slug>/tests/<unit>.md --base <base>`
     from the repository root. Add `--branch <branch>` when the base branch is
     not `main`. Save the output as `tests/<unit>.out`.
     The command writes the RED record to `red/<unit>.json`.
   - On exit 2 or 3, start the `test-judge` again with the drafts, the current
     set and the output of `nott plan test`. Give it the same snapshot as its
     working directory. Save its answer over `tests/<unit>.md`.
     Run `nott plan test` again on the revised set, at the same `<base>`.
     Do not compile until each change unit has its RED record without a refusal.
   - For a unit with no change, keep the drafts and the judged set without a RED run.
   - At the end of step 5, delete the snapshot.
6. **Compile.** Start one `compiler` run with `INTENT.md`, `PLAN.md`, the test sets,
   the RED records and the agent files. Save its answer as `plan.py`. Run
   `nott plan check .nott/plans/<slug>/plan.py`. Before the compile review, the
   check refuses for the missing `Compiled:` line and names the review digest of
   `plan.py`.
   - When it refuses the `PLAN.md` rounds of the review record, go back to
     step 4. The check reads these rounds before the `Compiled:` line.
   - When a refusal names `nott plan test`, go back to step 5 for that unit.
   - When it refuses for the `Compiled:` line, go to step 7.
   - When the check refuses a value that `PLAN.md` gives wrong or does not give,
     go back to step 3.
   - When it refuses another thing, start the `compiler` again with the refusal
     line and the path of the current `plan.py`.
7. **Compile review.** Write the brief of a new round, `review/r<N>/brief.md`.
   It has the `Candidate:` line of the current `PLAN.md` and the line
   `Compiled: <review digest>`, with the review digest that the check named.
   The compile review is the first review of a new artifact, `plan.py`. It is
   not a cure round of `PLAN.md`. Its rounds follow ../../review/SKILL.md
   (rounds) for `plan.py`, and the lead counts them apart from the `PLAN.md`
   rounds.
   Start one `plan-reviewer` run with `nspawn_review_start`, and give it the
   paths of `INTENT.md`, `PLAN.md`, the test sets, the RED records and `plan.py`.
   The reader compares each field of `plan.py` with its source: `intention`
   with `INTENT.md`, and each other field with the reviewed `PLAN.md` and the
   judged test sets,
   except the owner's edits that the docstring of `harness/nott_harness/plan.py`
   lists. Each field must carry out its source.
   Reject work in `plan.py` that `PLAN.md` and the judged test sets do not give.
   The RED records are also sources for `red_witness`.
   The check compares each `red_witness` with its RED record.
   Compare the `assertion` of each witness with the `fails today` reason of its test.
   Save its answer as `review/r<N>/plan-reviewer.md`.
   - When a finding is on a test set or on a witness, go back to step 5 for that unit.
   - When a `FIX-FIRST` finding is on `plan.py`, start the `compiler` again with
     it and the path of the current `plan.py`. Then do a new compile review.
   - When a `FIX-FIRST` finding is on `PLAN.md`, go back to step 3.
   - Only a `SHIP` of the same reader in a later compile round on the final
     `Compiled:` digest clears a `FIX-FIRST` in a compile round.
   - On `SHIP`, run the check again. It must exit 0.
   Add `Spec revision: <sha256 of PLAN.md>` to the compile brief. Start its
   reader with `nspawn_review_start`, `subject` set to `<plan subject>/plan.py`
   and `candidate` set to the review digest. The PLAN.md candidate line stays
   in the brief. The compiled digest names the head that this review counts.
8. **Readback.** Run `nott plan check --question <path>`, where `<path>` is
   `.nott/plans/<slug>/plan.py`. Record verbatim the body that it prints with
   `nott_question_record`. Only a plain `Confirm` admits the run.
   Treat any other reply as a `Change`.
   When the owner changes the result, go back to step 1 to rewrite `INTENT.md` first.
   When the owner asks to change an owner's edit that the docstring of
   `harness/nott_harness/plan.py` lists, edit `plan.py`, set `suggested: False`
   for a changed suggestion and run the check again. Then close the old
   question and record the new body from `nott plan check --question <path>`.
   Any other change goes back to step 3.
   A Change that returns to step 1 or step 3 starts the next version of the
   plan's subject before its new review round.
9. **Capture.** Capture the nMEMORY plan capsule, as ../SKILL.md (home) says.
10. **Run.** Run `nott plan run <path>` in the background, with the path
    from step 8. Each stop prints an OPEN line:
    `OPEN: <what waits>; next: <act>; resume: nott workflow resume <id>`.
    Do the `next:` act. When the act records a body, record it with
    `nott_question_record` and wait for the owner's verified answer.
    When the act is the owner's own (an answer, a signed `Accept` or `Revise`,
    or `/nott:accept`), wait for it and do not do it yourself.
    At a needs-human stop, also ingest the needs-human capsule. Then run
    `nott workflow resume <id>`. This includes the resume after `Accept` and the
    merge, and the resume after `Revise`. Repeat until the run reads DELIVERED,
    ACCEPTED or CANCELLED. A revise stop goes to step 11.
11. **Revise.** At a revise stop, write a revised plan of the remaining work
    from `nott workflow show <id>`. The phases that are done stay out. Take
    the revised plan through steps 3 to 8. Then run `nott workflow cancel <id>`.
    When it stops OPEN, do the act of its OPEN line as in step 10.
    When the cancel completes, take the revised plan to steps 9 and 10.
    A revised plan starts the next version of the plan's subject before
    steps 3 to 8. Keep the review history. The version change never clears an
    open blocker.
