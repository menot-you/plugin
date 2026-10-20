# Model tiers

The rule is `../SKILL.md` (`<!-- nott:workflow:model-tier -->`). The classes are
nSPAWN's execution classes; their vocabulary's home is
`mcps/nspawn/nspawn/ranks.py`, and what each means is described for System1 in
`mcps/nspawn/nspawn/classify.py`. This table only maps them to a tier.

An Agent dispatch or a Workflow `agent()` names the tier as the route it
accepts. An nSPAWN dispatch declares the class instead, and the host roster picks
the route that serves it; never name a model id the roster does not serve.

| execution class | Agent / Workflow `model` |
| --- | --- |
| `mechanical_fanout`, `deterministic` | `haiku` |
| `implementation`, `judgment`, `planning`, `review`, `verification`, `design` | `opus` (or a Codex route through nSPAWN) |
| `unclassified` (no class observed) | the dispatcher's explicit choice |

The method is two tiers, Opus and Haiku (`../SKILL.md`,
`<!-- nott:workflow:opus-haiku -->`); no third tier sits between them.

**What qualifies a unit for Haiku.** A unit with a precise contract (named
input files, the expected output, and a check that judges it) is declared
`mechanical_fanout` or `deterministic`. An experiment, probe or sweep whose
oracle decides it qualifies the same way. That contract is the qualification
for those classes, not a second rule.

**What stays on Opus or Codex whatever its class:** architecture and design
decisions, concurrency, security, persistence, protocol and trust paths. A
campaign's review vetoes run at the model each campaign stage names
(the pipeline in ../SKILL.md): opus for the security reader and the approver, sonnet
for the ux, ui and code readers. Every other review veto stays on Opus or Codex, with the
reviewers the repository law names for that surface.

**Escalation.** A Haiku unit that misses its check is dispatched once more on
Opus, with a `Tier reason:` line in its prompt naming the miss. A second miss is
a design question, not a third attempt.

**The guard.** `hooks/dispatch-tier.py` gives an Agent dispatch that names no
model the `opus` tier and tells the dispatcher; it never refuses the dispatch (a
fork runs on its parent's model and is exempt). Whether the named tier
fits the class is the dispatcher's judgment; no hook sees a workflow's run-time `agent()` calls, and a class is
observed only where nSPAWN dispatches (BLOCKED.md, "Workflow agent() prompts").

**The record.** Nothing new stores it. Per unit, read:
- a Workflow run: its transcript directory, `journal.jsonl` (each agent's label
  and result) and `agent-<id>.jsonl` / `agent-<id>.meta.json` (model, usage tokens
  and timestamps per message, so wall-clock is the first to the last);
- an nSPAWN run: `nspawn_run_show` (provider, model, tokens, phase and times);
- findings: the review verdicts the loop already reads.
