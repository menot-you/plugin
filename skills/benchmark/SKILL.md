---
name: benchmark
description: >-
  Find where the NOTT plugin fails and what to fix, with proof. Turn each
  observable failure class into a native eval case, and measure friction with paired Terminal-Bench rounds.
  Use when the owner asks to benchmark or audit the plugin. Not for fixing the plugin.
---

# Benchmark

Find where the plugin is bad and what to fix. Accuracy is a consequence, not the goal.

<!-- nott:benchmark:read-only -->
This route measures and reports. It writes only native eval cases with their fixtures, `AXES.tsv` rows and `QUARANTINE.tsv` rows, `BLOCKED.md` entries and run captures. Write a `QUARANTINE.tsv` row only when the README criterion holds: the case is red in both arms. Keep run captures outside the tracked tree. It does not edit the law, a route, a hook, an agent or a plugin script. Hand each fix with its evidence to the lead that owns the cause: the plugin lead, or the hooks lead for a hook.

<!-- nott:benchmark:native -->
## 1. Native suite

The failure classes come from the owner. This route does not mine nMEMORY or session transcripts. Each class that a grader can observe becomes one case in `plugin/evals/native`. A case and its fixture use invented values only, so no credential, address or personal datum enters the tree. Read its `README.md` and `BLOCKED.md` first, and follow them for tags and for a case that ties. Run a case only through `run.sh`, with both arms: `NOTT_EVAL_ABLATION=with-without NOTT_EVAL_TAG= plugin/evals/native/run.sh '<case>'`. That with-without run is the RED. A class that no grader can observe goes to `BLOCKED.md`.

<!-- nott:benchmark:tbench -->
## 2. Terminal-Bench

This layer runs one solo coding task through `evals/tbench` (Harbor). Its targets are friction and judgment cost: guard cuts, output rereads, hook refusals, hook context bytes, subagent law presence and cost. Report only the counts that a capture contains. If a capture has no count for a class, say so. Do not derive or estimate the count. `evals/tbench` arrives with pull request #1643 (branch `tbench-plugin`). If it is not on main, report this layer as not available and continue with layer 1. Use Opus as the agent model. Each round spends paid Opus quota. Thus each round needs an explicit owner grant and the `--cap-usd` ceiling of its capture. Run short paired rounds, with and without the plugin. Use the same task in each round. Write one capture per run, each to a new `--out` directory. A class is at its ceiling after two rounds with no change in its count.

<!-- nott:benchmark:loop -->
## Loop

Take one failure class at a time, highest count first. Hand the fix to the owning lead. After the fix, run the class's native case again, and its Terminal-Bench rounds when that layer is available. A class closes only when its native case failed in the plugin arm before the fix and passed in that arm after the fix. Both readings use the run count that the README requires for a gate, and the README must read the change as movement. A Terminal-Bench count at its ceiling does not close a class: report whether the fix moved the count. If no layer can measure the class, report it as not measured and take the next class.

<!-- nott:benchmark:report -->
## Report

For each class, give the causing plugin part. Also give its native case or its `BLOCKED.md` entry, and its Terminal-Bench counts when that layer ran. Name each layer that did not run and why.
