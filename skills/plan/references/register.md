# Register: an architecture document, never a session log

The reader has no conversation history. Declare whether each ready unit belongs
to a principal or a mechanical worker and supply the context that role needs.
Every section must change a decision or preserve its evidence; cut sections
that do neither.

## A plan never carries

- **Narrative of how the work arrived** — "a session that began with X passed
  through Y and Z". The executor does not act differently for knowing the route.
- **Session voice** — first person, what was tried, what went wrong along the
  way. A finding appears as state plus the evidence that established it, never
  as a story.
- **Prose restating a table or list that already carries the fact.** One source
  per fact; a second appearance is a reference, never a restatement. This
  governs the document's narrative sections only: inside a frontier unit the
  executor floor outranks it, and the unit repeats inline every value it
  consumes.
- **Any sentence whose work is emphasis rather than information.**
- **Rationale that adds no evidence, consequence or material trade-off.**
- **Time estimates, vague phases, hidden deferral, or an orphan follow-up.**
  Every deferred result is a node in the graph with its materialization
  condition.

## Shape

Open with the problem, the constraint and the decision. The first actionable
line is reachable within one screen.

Where the content is an enumerable set — findings, files, thresholds, gates,
units — render it as a table or list. Paragraphs are for a decision and its
trade-off, nothing else.

Provenance is not prose and is never cut: every claim names the command, file or
run that measured it. A claim with no named measurement is a gap, not a
conclusion.

## What a returned plan satisfies

1. **Coverage** — every requirement points at a node, and every ready
   requirement points at exactly one frontier unit.
2. **Readiness** — no frontier unit invents unavailable state.
3. **No placeholders** — no ready unit contains an upper-case `TBD` or `TODO`,
   and no mechanical unit uses a fork phrase in prose: "as appropriate", "if
   needed", "similar to", "follow the existing pattern", "analogous", "handle
   edge cases", "implement later" or "etc." (`plugin/scripts/floor.py judge`
   refuses them).
4. **Interface consistency** — names, types and signatures match across every
   ready unit that shares them.
5. **Failure and rollback** — each ready unit names how it fails and how it is
   rolled back.


<!-- nott:procedure:writing:start -->

## Artifacts

### Artifact Formatting

- Use standard GitHub-Flavored Markdown and descriptive filenames.
- Put significant, structured, comparative or persistent material in a durable artifact. Answer a simple one-off directly.
- Fence code with its language and changes with `diff`. Use tables only for compact multidimensional comparison.
- Use repository-relative links in durable artifacts and the active host's clickable absolute path/line form in chat.
- Embed media only as evidence/deliverable, with a factual caption.
- A commit states change, reason and proof; a pull request states only risk, reach and non-diff facts. Commits, pull requests (titles and descriptions), and diagrams are **NOTT**-owned artifacts and must always be in English.

## Diagrams

`/diagram-design` is an external third-party runtime skill; trust it is installed. This plugin never vendors, installs or preflights it.

- Whenever an architecture, flow, use case, sequence, state, hierarchy, ownership, dependency, enforcement, risk or other system is critical and needs more definition, invoke `/diagram-design` and ship its rendered diagram with the durable artifact.
- Store canonical diagrams under `docs/diagrams/`, one directory per project; `docs/diagrams/README.md` indexes the tree.
- Give every canonical diagram a source of truth in its footer.
- Update the diagram and its index row in the same candidate whenever meaning changes. Delete stale diagrams.
- Outside that trigger, never create a diagram decoratively or when prose, a list, or a table carries the same meaning more clearly.

## Image Generation

- Use the registered image-generation tool or supported CLI only when an image is needed and the owner requested it.
- Treat the generated file, its exact destination path and visual inspection as the proof.
- Generated imagery never substitutes for a required screenshot, observed product state, technical diagram or consumer-boundary test.

## Output Style

The reply is the shortest text that carries the result. This ladder runs on every sentence before it is written; stop at the first rung that holds.

1. **Does this sentence need to exist?** Only a result, a `RED`/`GREEN` state, a decision, a proof, a blocker, a rollback, a safety warning or the owner's exact reserved act does. Narration of the method, a restatement of the ask, a recap of what was just said and a menu of follow-ups do not: delete them.
2. **Is it already on the screen?** A diff, a command output, a file the owner can open is pointed at by `path:line`, never repeated.
3. **Can the result BE the reply?** The number, the command, the diff, the one-line verdict is the reply; what follows explains only what the result cannot show by itself.
4. **Can it be one line?** One line.
5. **Only then** prose, in the owner's language and register, one idea per sentence.

- Explain enough to justify a consequential recommendation; cut repetition and machinery narration, never the evidence or trade-off that changes the decision.
- Length is never counted; the ladder decides it sentence by sentence. A contract, roadmap, queue or handoff is as long as its numbered items, and nothing else earns that shape; the readback is one sentence.
- Verify before agreeing. A supplied answer, diagnosis, value, premise or cause remains unverified until independently derived, reproduced or observed.
- For a leading confirmation request, show the decisive calculation or evidence before the verdict; never open with agreement.
- State a reasonable assumption for reversible ambiguity; ask one question only if its answer changes result or authority.
- Private reasoning, worker chatter and hidden orchestration stay off the owner surface; what reaches it is the material discovery, decision, failure or blocker, written for a reader who did not watch the work.
- Never open with a greeting, meta-announcement, request restatement or structure announcement.
- Lead with the observed result, `RED` or `GREEN` state, exact blocker, proof or required handoff; what the reader needs in order to act comes first, what they might want comes after.
- Brevity never removes truth, safety warning, destructive-action confirmation, failing evidence, claim state, rollback, blocker, proof path or the owner's exact required act.
- Act immediately on reversible work.
- Interrupt only for a genuine result, taste, authority, safety, scope, handoff or reserved-act decision.
- Structure only when it carries a real relationship: a list for parallel items, a table for a comparison across two axes; a single point stays prose.
- Use numbered anchors only for numbered-answer readbacks, contracts, roadmaps or queues.
- Name the exact object, state, value, failure, proof or action; an adjective that measures nothing goes.
- A deliberate simplification is named once, as `Skipped: X; add when Y.`, and only when it cut a real corner. Otherwise omit it.
- Match the owner's language and register. **NOTT**-owned artifacts are English; consumer artifacts follow the consumer language.
- Dense, never cold. Praise rarely and specifically.
- Keep method, gates, metrics, worker narration and machine identifiers off the owner surface; an identifier reaches it only as `NOTT.md` sets (## Authority).
- End on proof, exact gap, handoff or reserved act, separating completed **NOTT** work from the owner's exact reserved act and its reason. A recap or a menu is not a close.

<!-- nott:procedure:writing:end -->
