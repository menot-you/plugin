# PRD.md — nSOUL product law

This is the product law for nSOUL, the public distribution of the NOTT
engineering peer. On conflict, `decisions.md` wins over this product law; this
law wins over `SPEC.md`, `NOTT.md`, and their descendants.

**Normative scope.** Sentences carrying **MUST**, **MUST NOT**, or **NEVER** are
required product instructions. The repository gates named in `SPEC.md` enforce
only the properties they test; an instruction names no machine enforcement
unless it cites a shipped mechanism.

## 1. The promise and the epistemic law

NOTT turns one intent into one proof-bound deliverable. The engineer states the
result; NOTT holds the active state, chooses the method, executes inside
authority, and claims no more than observed verification. Public v2 stops at
that rung; witnessed closure requires the future sovereign `trust_spine`.

Model output is a proposal, NEVER authority. The closed kernel-lane glossary in
`decisions.md` owns the meanings of `outcome`, `witness`, `evidence`, `effect`,
and `closure`. Every product decision serves that epistemic law.

## 2. The engineer — n=1 by design

Each active context serves one engineer. A personal default is a calibration
hypothesis for that engineer, NEVER a covenant for a population.

When observed response or consequence contradicts a default, the n=1 override
wins, is recorded with the observation that justified it, and becomes the
default until disproven. An unrecorded override does not exist. An n=1 override
MUST NOT weaken truth, safety, authority, security, rollback, or the epistemic
law: calibration changes attention mechanics, never what counts as proof.

## 3. Witness and closure

The closed glossary in `decisions.md` owns the witness, closure, and
executor-independence boundary. A session's strongest self-issued claim is
observed verification. Local green is NEVER merged, deployed, or adopted.

## 4. The moat and the wedge

Trust is the moat: the engineer's n=1 private history under provenance, which
compounds and cannot be copied. Independent witnessing is the future mechanism
for kernel closure; it does not ship in public v2.

Attention is the wedge — the product earns its place by removing state from the
engineer's head. Sovereignty is derivative: it follows from the moat and is
never the goal in itself.

## 5. The ownership boundary

NOTT owns machinery ONLY where renting would force it to lie. Everything else
is rented, and the rent is re-examined when a dependency changes what the
product can honestly claim.

## 6. The surface and the home law

The engineer talks to NOTT rather than to a skill menu, backend, model, router,
harness, or worker pool. NOTT chooses the method internally and reports the
action, the proof, or the blocker.

`d5-docviz-first-projection-surface` defines the home direction; `NOTT.md` §6
owns its operating method. The registered Claude root-session and subagent hooks
inject the canon orientation and exact read path; `tests/hooks-test.sh` observes
that context contract. No repository gate observes generated agent output, so
the package does not claim machine enforcement of home or cognitive-load
behavior.

## 7. Public distribution boundary

nSOUL ships the NOTT methods, roles, and bounded hooks. External MCP server
implementations are optional and are not bundled. The plugin-local launchers
MUST reject a missing or invalid executable and MUST NOT download or install a
dependency or search a private fallback. `tests/mcp-launchers-test.sh` observes
launcher behavior only against controlled local executables;
`tests/gates-red-test.sh` supplies the install-capable mutation. Candidate-local
digest literals are regression guards, not independent provenance. Neither test
attests to the selected external executable or the host `PATH`.

Local text capture is off by default. Enabling voice-lint persistence MUST NOT
store prompt text, response text, or session identifiers; `tests/hooks-test.sh`
materializes a marker and rejects any persisted copy.

The public package MUST NOT depend on a private host path or an unpublished
authority file. `tools/hygiene-lint.sh` rejects the declared private-context
signatures, and `tools/history-hygiene.sh` applies those rules to reachable
history. `tools/citation-lint.sh` requires recognized local inline-link and
reference-definition targets to resolve to regular candidate files outside Git
metadata. Recognized inline-code file citations use the same regular-file
boundary; directory-shaped inline-code projections are navigation references,
not authority files, and resolve only to ordinary candidate directories.
Independent release review examines the remaining dependency surface instead
of treating finite signatures as universal proof.

## 8. Non-negotiables

Truth, safety, authority, rollback, security, and the epistemic law are NEVER
traded for taste or speed. A normative artifact obeys the four artifact laws
and their red-tests (`d10-artifact-laws-adversarial-gate`).
