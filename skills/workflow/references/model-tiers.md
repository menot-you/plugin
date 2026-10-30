# Model tiers

The rule is `../SKILL.md` (`<!-- nott:workflow:model-tier -->`). The classes are
nSPAWN's execution classes; their vocabulary's home is
`mcps/nspawn/nspawn/ranks.py`, and what each means is described for System1 in
`mcps/nspawn/nspawn/classify.py`. This table only maps them to a tier.

An nSPAWN dispatch declares the class. The host roster picks the route that
serves it. ../SKILL.md (opus-haiku) sets the route default. This table sets
model tiers for the Claude route. Never name a model id the roster does not
serve. A Claude model pin uses this table, including under the exception in
`delegation-and-recovery.md`.

| execution class | Claude `model` pin |
| --- | --- |
| `mechanical_fanout`, `deterministic` | `haiku` |
| `implementation` | `sonnet` |
| `judgment`, `planning`, `review`, `verification`, `design` | `opus` |
| `unclassified` (no class observed) | the dispatcher's explicit choice |

**Precedence (U1).** A model or an effort follows this order. First, the
caller's explicit pin. A mismatched model keeps it only with a `Tier reason:`
line in the brief (owner law, 2026-10-21). Second, Opus for a `judgment` unit,
whatever its agent file or class says. Third, the model of the dispatched
agent's own file, `plugin/agents/<name>.md`. Fourth, the class tier of this
table. In `hooks/dispatch-tier.py` that is `haiku` for `mechanical_fanout`
and `opus` for the rest. In nSPAWN it is the class route with its fast lane
and the review preference order. In nSPAWN, an unpinned review or native
writer turn runs on the route that `[roles]` binds to its role. On that
route, the `[role_profile]` of the role is the fourth step. A suggested model
or effort never blocks a run. A model or an effort that the route does not
serve, or an effort above the class ceiling, falls back with a warning.

**Frontmatter grammar (U1).** An agent file declares its suggestion in one of
two forms. `model` holds a Claude model. Claude Code, this hook, nSPAWN and a
node all read it. `nott-provider` with `nott-model` holds a suggestion for
another provider. nSPAWN and a node read it and dispatch through that
provider. Claude Code ignores it. The hook then falls back to the class tier
and names the suggestion in a context line. An agent file declares one form,
never both.

**What qualifies a unit for Haiku.** A unit with a precise contract (named
input files, the expected output, and a check that judges it) is declared
`mechanical_fanout` or `deterministic`. An experiment, probe or sweep whose
oracle decides it qualifies the same way. That contract is the qualification
for those classes, not a second rule.

**What requires a strong model on either route:** architecture, design,
concurrency, security, persistence, protocol and trust paths. The route default
still applies. The campaign reader uses the best available model at effort
`max` (../SKILL.md, reader). Other review vetoes use the reviewers that the
repository law requires for that surface.

**Escalation.** A Haiku unit that misses its check is dispatched once more on
Opus, with a `Tier reason:` line in its prompt naming the miss. A second miss is
a design question, not a third attempt.

**The guard.** `hooks/dispatch-tier.py` reads this table at each Agent and
Workflow call. It finds a unit's class from its brief with fixed markers, and
never asks System1. A sentence that starts with a prohibition ("Never read
credentials") is a rule of the brief: the guard does not read it for markers.
It still reads these subjects in any sentence: security, concurrency, deadlock,
race condition, persistence, migration, transaction and protocol. Credentials,
secrets, authentication, authorization, database and trust count only in the
rest of the brief.
- A read-only reviewer type, or a review brief, is `review`.
- A security, concurrency, persistence, protocol or trust unit is `judgment`.
  The guard never moves it to Haiku. On the Agent path, a named Haiku model
  gets a context line and keeps its model: a subject word alone does not move a
  unit up. On the Workflow path, the same subject keeps the call's own model,
  and the stage is not judged.
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
- a plugin agent's effort: the `effort` pin of `plugin/agents/<name>.md`, which
  the Agent tool applies when no override is set (`high` for an implementer,
  `max` for a reader, `low` for explorer, none for worker;
  `plugin/tests/test_plugin_agents.py` holds the values);
- findings: the review verdicts the loop already reads.
