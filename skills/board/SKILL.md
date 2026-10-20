---
name: board
description: >-
  Show existing work as a read-only snapshot. Use for a board or status view,
  not for choosing priorities or starting work.
---

# Board

Draw the work the store actually holds.

<!-- nott:board:read-only -->
The board does not mutate capsules, edges or files, assign work, or decide priority.
An instruction to choose or begin work belongs to plan or execution.

A request often carries both: draw the board, and then start something. Draw the
board, and say in one line which part was not done here and which route owns it.
Silently dropping that half leaves the owner believing work began.

<!-- nott:board:digest -->
Resolve the registered nMEMORY digest operation and call it once for the requested
scope. Use project_prefix when the owner names a sector. Retrieve a missing
headline only when needed to make a displayed row intelligible; do not invent it.

<!-- nott:board:mapping -->
| View | Source | Preserve |
| --- | --- | --- |
| Work | dag.ready, dag.blocked, dag.done | Each list's own total |
| Sessions | open_sessions, open_session_ids | The count when the ids are capped |

The digest has no thread-handoff, epic or planning-pressure section; a view
without a source is not drawn.

<!-- nott:board:cycle -->
A cycle verdict is a failed projection: display the named cycle and its admitted
repair, without drawing ready or blocked work that the store refused to derive.

<!-- nott:board:no-invent -->
Do not fabricate priorities, assignees, sprints, percentages or manual order.
Missing fields remain missing. A capped list is never presented as complete.

<!-- nott:board:snapshot -->
<!-- nott:board:draw -->
Render a snapshot, not a self-refreshing view. Group rows with their counts and
make states distinguishable without relying on color alone.

<!-- nott:board:close -->
The result is an intelligible view of the requested scope, including its gaps.
Report ready work as returned; an empty ready set stays empty.
