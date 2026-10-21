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

**The guard.** `hooks/dispatch-tier.py` reads this table at each Agent and
Workflow call. It finds a unit's class from its brief with fixed markers, and
never asks System1. A sentence that starts with a prohibition ("Never read
credentials") is a rule of the brief, and the guard does not read it.
- A read-only reviewer type, or a review brief, is `review`.
- A security, concurrency, persistence, protocol or trust unit is `judgment`.
  The guard never moves it to Haiku. On a named Haiku model it adds a context
  line and keeps the model: a subject word alone does not move a unit up.
- A contract marker (rerun, report each command with its exit, read back,
  smoke, sweep, probe, watcher, mechanical edit) is `mechanical_fanout`. The
  class is ambiguous when a task verb of judgment or of an edit (fix, add,
  move, measure, answer, cure and the like, at the start of a sentence or a
  clause) or a RED-first test is also in the brief. An edit verb does not count
  when the brief says "mechanical edit".

An Agent dispatch whose model does not fit its class gets the class's model
through `updatedInput`, and a context line names the class, the tier and the
signal. A dispatch is never refused, and an ambiguous brief keeps its model.
A brief with a `Tier reason:` line keeps its model. A sonnet reader keeps the
model that its pipeline stage names. A fork is exempt.

The guard reads a Workflow script before the script starts. An `agent()` call
whose label or phase names a mechanical stage (evidence, ship, install, smoke,
probe, sweep, watch), or whose `agentType` is a reviewer, must use its class's
tier. A mismatch denies the whole Workflow call, with one line per call and the
fix: JavaScript is not rewritten. A call with a `tierReason` option keeps its
model. The guard does not judge options built at run time, a script that it
cannot parse, or a saved workflow called by name. A context line says so.

**The record.** Nothing new stores it. Per unit, read:
- a Workflow run: its transcript directory, `journal.jsonl` (each agent's label
  and result) and `agent-<id>.jsonl` / `agent-<id>.meta.json` (model, usage tokens
  and timestamps per message, so wall-clock is the first to the last);
- an nSPAWN run: `nspawn_run_show` (provider, model, tokens, phase and times);
- findings: the review verdicts the loop already reads.
