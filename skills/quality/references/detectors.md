# The twenty detectors

The set is closed at twenty. Each detector states a metric, a threshold, and the
judgment clause that keeps the number honest. A number shipped without its
judgment clause is a detector nobody can read.

1. **Q01 — cold start.** Metric: clone to bootstrap to green suite in a clean
   container, timed. Threshold: zero hidden prerequisites, and the recorded time
   must not regress. Judgment: the CI job is the detector — a bootstrap that
   works only on a maintainer's machine is a broken product, never a local quirk.
2. **Q02 — test falsifiability.** Metric: a guarded behavior broken on purpose
   turns the suite red. Threshold: every test relied on as proof. Judgment:
   assertion inversion is never that proof, and coverage is never that proof;
   this is the human red-test of what Q18 mechanizes.
3. **Q03 — error handling.** Metric: swallowed errors, empty catch, panics in
   library code, context-free failures. Threshold: zero for new code. Judgment: a
   caught-and-discarded error is a decision to lie about the failure, never a
   shortcut.
4. **Q04 — boundary visibility.** Metric: a cold reader recovers the declared
   architecture from the directory tree alone. Threshold: recovered with no guide
   and no tribal memory. Judgment: a drill, recorded — this is the readable face
   of what Q16 enforces.
5. **Q05 — illegal states.** Metric: stringly-typed domain values, primitive
   obsession, nullable-mania. Threshold: compiler strictness at its maximum, and
   every domain value built through a validating constructor. Judgment: an
   illegal state that compiles is a defect the type system was asked to hold and
   must not be argued down to a convention.
6. **Q06 — history hygiene.** Metric: commit-message intent rate and diff
   cohesion, sampled. Threshold: the sampled rate must not fall between rounds.
   Judgment: sampling is what makes this affordable; it samples what Q17
   quantifies.
7. **Q07 — mechanized law.** Metric: every claimed convention names its enforcing
   mechanism. Threshold: zero conventions with no named mechanism. Judgment: the
   scorecard's own advisory count is the detector — a convention with no
   mechanism is a wish, and calling it enforcement is the overclaim this whole
   system exists to refuse.
8. **Q08 — doc truth.** Metric: public surface changed implies documentation
   changed in the same candidate. Threshold: zero co-change violations. Judgment:
   code and the documentation describing it are one deliverable, so a doc gap
   resets the candidate rather than shipping as a caveat.
9. **Q09 — deletability.** Metric: files that bleed when one feature is removed
   on a throwaway branch. Threshold: the bleeding count trends to zero. Judgment:
   no machine holds this; a deletion drill measures it, and its finding is a
   design finding.
10. **Q10 — single responsibility.** Metric: cohesion, public-interface size, and
    an honest one-sentence description. Threshold: no demonstrated independently
    changing responsibilities hidden in one package. A conjunction is a prompt to inspect independent reasons to change;
    it is never enough to order a split. Name the consumers and changes that
    justify separation; preserve the repository's committed detector floors.
11. **Q11 — naming abdication.** Metric: module, file and type names matching
    `utils`, `helpers`, `manager`, `data` or `misc`. Threshold: zero demonstrated
    naming abdications for new code. A name alone does not prove a responsibility defect.
    The grep is a negative proxy, never a quality score: name the obscured decision
    or responsibility, otherwise drop the finding. Existing ratchet floors remain binding.
12. **Q12 — cognitive complexity.** Metric: per-function cognitive complexity,
    reported at p95 and max, with production and test values counted separately.
    Threshold: the linter's default ceiling or tighter, never loosened to admit
    existing code. Judgment: never cyclomatic — cyclomatic punishes an exhaustive
    match, which is good code; cognitive measures what a reader must hold in mind
    at once, which is the actual cost.
13. **Q13 — duplication.** Metric: duplicated-token percentage over normalized
    windows. Threshold: a committed ratchet that only tightens. Judgment: the
    crime is duplicating a decision, never text — coincidental textual
    duplication is cheap to carry, and the wrong abstraction invented to dry up
    two things that only looked alike is the most expensive defect there is, so a
    finding here must name the shared decision or be dropped.
14. **Q14 — speculation.** Metric: single-implementation interfaces that are not
    extension points, never-varied parameters, dead configuration flags.
    Threshold: zero speculative extension points. Judgment: a seam built for a
    caller that does not exist is cost charged today against a benefit nobody
    ordered.
15. **Q15 — dead code.** Metric: unreferenced symbols. Threshold: zero — this
    detector is binary, never "few". Judgment: one unreferenced symbol is a
    reader's dead end and a maintainer's false obligation, so the count must not
    be negotiated into a ratchet.
16. **Q16 — dependency discipline.** Metric: module cycles, and domain modules
    importing I/O. Threshold: cycles zero, and the functional core names no I/O.
    Judgment: the cargo-cult anti-signal is a layer that only delegates — a layer
    that makes no decision is ceremony, never architecture, and must be deleted
    rather than documented.
17. **Q17 — hotspots.** Metric: overlap of top-decile churn with top-decile
    complexity. Threshold: zero files in both sets. Judgment: the overlap, never
    either list alone, is where a defect is both likely and expensive.
18. **Q18 — mutation score.** Metric: percentage of mutants killed on enrolled
    suites. Threshold: the floor the repository declares per enrolled suite, which
    only tightens; none is invented where none is declared.
    Mutation score is evidence about the exercised mutants, not proof of overall
    correctness. Check oracle quality, equivalent mutants, reach and failure modes.
    Preserve a declared floor; neither coverage nor mutation alone certifies
    consumer behavior or justifies deleting a guard.
19. **Q19 — flake rate.** Metric: reruns-to-green, and retry-on-red constructs
    anywhere on the test execution path. Threshold: zero tolerated. Judgment: a
    tolerated nondeterministic test is culture in decomposition — the first
    accepted retry teaches the team that red means "run it again", so a flake is
    a defect and never weather.
20. **Q20 — determinism.** Metric: same declared inputs produce the same bytes at
    the declared scope. Threshold: byte-identical on a double build of every
    enrolled artifact. Judgment: same input, same bytes, or no other proof in
    this list is trustworthy — every downstream comparison inherits this
    detector's verdict.

## Why three pairs overlap

Overlap is deliberate, never accidental. Q02 is the human red-test of what Q18
mechanizes. Q04 is the readable face of what Q16 enforces. Q06 samples what Q17
quantifies. Each pair keeps both members because each member catches a failure
its twin cannot: the mechanized half misses what only a human notices, and the
human half misses what only a machine measures every run.
