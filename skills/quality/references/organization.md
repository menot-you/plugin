# Organization

The law states the property: one name, one home and one grammar per concept, measured by a
mechanical guard. This reference holds how that is applied.

## The declared mapping

A repository that adopts the canon keeps ONE machine-readable file that declares, for every
kind of unit, how its directory, distribution, package, executable and variables derive from
each other, together with:

- the closed set of nouns and verbs its commands, operations and tools may use;
- the declared exceptions, each named one by one with its reason;
- the old-to-new maps of every rename still in flight.

In pynott that file is `rails/organization.toml` and its guard is `tools/organization.py`.
A second source of naming truth (a table in a README, a comment in a script) is a defect:
it drifts, and nothing measures it.

## Grammar

- Commands read `<executable> <noun> <verb>`; the noun is singular (`host list`, never
  `hosts list` or `list-hosts`).
- Protocol extensions, door operations, MCP tools and script entrypoints spell the same
  path with their own separator: `_nott/<noun>/<verb>`, `<noun>.<verb>`,
  `<executable>_<noun>_<verb>`, `<folder>/<noun>.<ext> <verb>`.
- Variables are `NOTT_<OWNER>_<NAME>`. A variable owned by another program keeps the
  spelling that program requires, and sits in the declared foreign list.
- No aliases. A compatibility spelling is a second name for one concept; the consumer is
  updated instead, in the same campaign.

## Renaming

A rename is complete when no instance of the old name remains outside frozen records and
the changelog: code, tests, scripts, units, hooks, skills, documentation, installed
configuration and external consumers. What cannot move in the same campaign is written as
debt in the guard's debt file, and that file only shrinks: the guard fails on a new
violation and on an entry that no longer exists.

An old spelling recorded in the guard's mapping tables or its retired list stays forbidden,
because a stale reader of it would misread the new meaning without a sound. The file
`tools/organization.py` decides which recorded old spellings it measures and where. Read
it before you reuse one. To reuse one of those exact spellings for a new meaning, first
remove its entry and check that no reader of the old meaning remains.

A process that still receives an old variable name fails with a typed error naming the new
one, and only for the variables that process reads in the mode it runs in.

## Exceptions

An exception is declared in the mapping, one file or name at a time, with the reason. The
two recurring classes are the product executable (its name is the product) and historical
reads: read-only code that interprets data or trees older than the rename. A historical read
never writes an old name.

## What the guard measures

Member names, build backend and executables; import layers and declared dependencies;
command tables; operations and protocol extensions; tool names and their length limit;
scripts and service units; variable names read and set. It runs as a rail and is tested by
one fixture per rule. Review is not a substitute for it: a name that review let through and
the guard cannot see is a hole in the guard, fixed there.
