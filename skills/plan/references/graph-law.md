# Result graph

Use a graph when dependencies need explicit representation. Preserve the complete
accepted result and materialize only the work that is ready.

An edge means a producer's output is needed by a consumer. Sequence alone is not
a dependency. Independent work may proceed in parallel subject to exclusive
writers and actual resource capacity. Name a full-set barrier only when that
consumer really requires the full set.

A node is a deliverable that can require multiple acceptance observations.
Do not split it by assertion, document, review round or commit. Keep shared
authority, scope and rollback conditions at the result level instead of copying
them into every node. Acceptance judgment belongs in nodes; edges carry data.

An unready node names the missing input and materialization condition. Do not
invent a path, signature or interface beyond observed evidence. Principal
discovery can itself be ready when the unknown technical fact lies inside its
authorized bounded result.

An upstream completion admits its consumer only when the required output and
proof are present. Preserve future requirements when the current frontier is
smaller. Use an integrated consumer judge to determine the result's completion;
a graph that merely drains its own bookkeeping is not delivery.

Attempt history belongs to the accepted result and that judge. A plan revision
that leaves the same acceptance false is still part of that history. Renaming,
repartitioning, changing a session or introducing a prerequisite never resets
misses. After two misses without differentiating evidence, suspend that path and
obtain a causal observation before a bounded next attempt. A miss in the proof's
own scaffolding (harness, fixture, wait, lock or capture) counts against that
path whatever its cause; a new scaffolding cause is not differentiating evidence
about the result, so after two such misses prove the scaffolding offline against
the last run's captured evidence before spending another consumer slot. Continue
independent authorized work and carry unaffected proof forward.
