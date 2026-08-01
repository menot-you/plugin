# Roles — the judgment axis

An agent is the MOTION — plan, review, execute, research, test, debug (`plugin/agents/`).
A role is the LENS that motion is judged through. They compose: N agents plus M roles,
never N×M agent files.

A role is a CHECKLIST, because a checklist item is answerable and red-testable while a
persona degrades with context. A role is NOT a persona, NOT a tone instruction, and NOT
extra authority: a role MUST NEVER widen the dispatched agent's tools, scope, or grant.

## Composition law

1. A dispatch MAY attach AT MOST ONE role. A second lens is a second dispatch.
2. The conductor APPENDS the role's checklist to the dispatch brief. The checklist rides
   the Agent `prompt` parameter and MUST NEVER ride a hook — `SubagentStart` carries no
   prompt text, so a hook prepends context and can never amend the brief it would judge.
3. The dispatched agent MUST answer EVERY checklist item in its report. An unanswered item
   is an incomplete report, NEVER a silent pass.
4. Legality: each role file declares `applies-to`. Attaching a role to an agent outside
   that list is an illegal dispatch, and the conductor MUST NOT send it.
5. Rung: advisory convention. The mechanical layer is the birth gate
   (`d41-base-document-births`) — it governs where these files are born, never whether a
   dispatch obeys the law above.

## The roles

| Role | applies-to |
| --- | --- |
| `plugin/roles/product-manager.md` | planner · reviewer · researcher |
| `plugin/roles/rust-engineer.md` | reviewer · executor · debugger · tester |
| `plugin/roles/ux-designer.md` | planner · reviewer · executor |
| `plugin/roles/security-reviewer.md` | reviewer · researcher |
