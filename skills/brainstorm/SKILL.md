---
name: brainstorm
description: Interview the engineer to turn an open idea into a validated direction — questions one at a time, then proof-backed approaches, then one signed recommendation.
---

# Brainstorm

**Normative scope.** Sentences carrying **MUST**, **MUST NOT**, or **NEVER** are
mandatory method clauses. The client-loaded skill is the instruction mechanism;
`tools/doc-lint.sh` gates the declared scope and normative hedges in this file.

Use when the problem frame, product direction, or architecture choice is still open. Do not use for a bounded bug fix with an accepted result. Choose this method internally; never expose a skill menu.

Brainstorm is a dialogue. The engineer holds context no repository supplies — purpose, constraints, taste, success criteria — and the method extracts it by interview before any direction is argued. A brainstorm that arrives with a finished analysis and a terminal go/no-go is a monologue: the named failure mode of this skill. The dopamine-first opening law binds result asks; in a brainstorm the conversation is the work.

## Hard gates

- NEVER present approaches or a signed recommendation before purpose, constraints, and success criteria are confirmed by the engineer in dialogue.
- NEVER implement, ratify, or edit law from this skill. The output is a validated direction; ratification is its own act with its own owner go.
- NEVER skip the dialogue because the topic looks simple. Simple topics are where unexamined assumptions cost the most; scale the depth, keep the interview.

## Method

**1. Context before questions.** Read the repository, ledger, and active state first. NEVER ask what the repo, ledger, or a command already answers — verify it and state it. Questions are reserved for what only the engineer knows.

**2. Scope check.** A request naming multiple independent subsystems is decomposed before refinement: name the pieces, their relations, and a build order, then interview toward the first piece. Refining an undecomposed request wastes the engineer's answers.

**3. Interview — one question per message.** The interview locks, in the engineer's own words: the decision to make, the desired result and non-goals, hard constraints and irreversible choices, current proof and known unknowns, and who owns the final choice.

- Exactly ONE question per message. A topic needing more exploration becomes a sequence, never a bundle.
- Multiple choice with a recommended default when the option space is known; open-ended when the space belongs to the engineer.
- Every question earns its slot by extracting purpose, constraint, success criterion, or taste. A question that transfers a decision the method resolves is a defect — the interview draws information out of the engineer, never pushes a burden onto them.
- Mirror the engineer's register and energy; hold one active topic.
- Continue until the locks above are confirmed, or the engineer says move.

**4. Approaches — after understanding.** Propose two or three genuinely different approaches, never cosmetic variants. Test each against correctness, reliability, maintainability, reversibility, security, and reach. Lead with the recommendation and its reason. Expose the root assumptions behind the frame, labeled proof, convention, precedent, fear, or unexamined default; mark load-bearing ones with how the problem changes if false. Interview answers are assumptions confirmed at the source — cite them instead of guessing.

**5. Incremental validation.** Present the direction in sections sized to their complexity and confirm each section in dialogue before the next. NEVER one monolithic block with a terminal go/no-go. Name the strongest argument against the leading approach; surface the high-leverage move the current framing hides. Carry a diagram when flow or component shape matters.

**6. Close.** One signed recommendation: the trade-off and the rejected alternative explicit, the smallest observation that would reject the leading approach named, every high-load assumption carrying proof or a validation action. The validated direction is captured to the ledger; no new .md file is born for it. Terminal state: hand to ratify (lock the decision) or plan (execution graph) on the engineer's go.

When independent research is available, delegate bounded fact gathering only. The interview, the decision, and the recommendation remain here; the skill completes without any helper.

## Anti-patterns — each one is a protocol failure

- **The monologue** — analysis complete on arrival; the engineer reduced to approve/veto.
- **The bundle** — two or more questions in one message.
- **The oracle question** — asking what the repo, ledger, or a command answers.
- **The premature approach** — options argued before purpose is confirmed.
- **The undecomposed refinement** — detailing a request that needs splitting first.
