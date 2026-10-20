---
name: quality
description: >-
  Grade or install a repository's quality controls using its declared checks,
  detector definitions, baselines and dated exceptions.
---

# Quality

Report the bar the repository actually meets. Numbers do not replace judgment.

<!-- nott:quality:validate -->
Read the checks, limits and controls the repository declares. Production changes
retain their declared floors; this route does not authorize relaxing a check,
expanding a repair or installing a new system just because a number is red. Where
the repository declares no limit, choose checks proportional to the change and do
not invent a numeric floor.

<!-- nott:quality:detectors -->
Read references/detectors.md when grading or installing the twenty detectors,
Q01 through Q20. Their definitions and judgment clauses are the domain contract.
Do not claim a complete grade from a partial measurement. Read references/rituals.md
when a required human round is part of that assessment.

<!-- nott:quality:organization -->
Read references/organization.md when naming, moving or renaming a unit, command,
operation, tool, variable or script, or when grading how a repository is organized.
The repository's declared mapping and its guard decide; review does not.

<!-- nott:quality:layers -->
Install controls in order: baseline first (L1), enforceable binary gates (L2),
ratchets that only tighten (L3), then dated owner exceptions for remaining gaps
(L4). Do not install a gate before observing its baseline or loosen a floor to
admit current code. An expired exception fails the control that reads it.

<!-- nott:quality:rungs -->
The closed rung set is gate, ratchet, ritual, advisory. A missing mechanism is
advisory; no measurement or confidence can turn it into enforcement.

<!-- nott:quality:scorecard -->
Where the repository keeps a machine-readable scorecard, it is authoritative;
generated tables are projections.
Keep property, metric, threshold, mechanism, rung, status and evidence aligned.
Never hand-edit generated state or omit a detector merely because it cannot run.

<!-- nott:quality:rituals -->
Q02, Q04, Q06, Q09, Q11, Q13 and Q14 require their recorded human rounds rather
than invented metrics. Preserve cadence, owner and evidence; an overdue round
is a gap.

<!-- nott:quality:qualification -->
Qualify against the profile the repository declares. Coverage, mutation and
property thresholds bind only where the repository declares them; never carry one
repository's floor into another or invent one. Measure a declared threshold over
the complete maintained source, with integer counts; sampling, rounding, missing
files and unlisted exclusions cannot qualify. A mutation run is required only
where a current repository requirement names it, and then with the scope, schedule
and threshold it declares. Otherwise mutation is point use through the standard
tool: run it by hand on the functions it is wanted for and give each survivor it
reports a verdict, a test that kills it or the tool's documented exclusion with a
reason.

Bind the candidate, source inventory, policy, runtime inputs and native reports to
the evidence the repository reads. Historical or incomplete evidence remains
readable but cannot qualify.
Preserve all D18 causes. When the accepted result forbids debt and waivers,
inherited debt and L4 exceptions cannot close it.

Keep static and architectural obligations separate from test percentages. Remove
demonstrated dead code, duplicated decisions, speculative layers and symptom
workarounds; justify boundaries by consumers and independent reasons to change.
Prove real persistence, protocol, concurrency, cancellation, faults, recovery and
native consumer behavior on disposable state. Candidate proof admits integration;
installed proof closes delivery. Neither phase can stand in for the other.

Independent measurement may run in parallel through registered delegation when
useful, with a bounded STOP contract and sufficient host resources. One missing
integration does not justify a fake result or self-supplied independent witness.

D18 distinguishes operational failure (1), refusal (2), findings (3) and green (0),
aggregated in that order. Missing infrastructure is not a product verdict.
Report measured rows, inherited debt, required gaps and the affected result.
Do not open a remediation campaign unless that work is authorized.
