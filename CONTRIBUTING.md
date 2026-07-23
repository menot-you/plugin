# Contributing to nSOUL

## Change contract

Read `NOTT.md`, `PRD.md`, `SPEC.md`, and `decisions.md` before changing a
contract-bearing surface. Keep one writer per working tree. Make the smallest
coherent change, add a negative proof for every new rule, and preserve the
distinction between observed verification and external release state.

No implementation language is prohibited. Every runtime dependency must be
declared in `release/public-contract.json`, exercised by its consumer, and fail
closed when unavailable. Shell changes must remain portable to the declared
runtime and pass ShellCheck.

## Required checks

```sh
bash tools/public-release-check.sh full
```

The full check must pass on the exact candidate. Review is adversarial and
read-only by default. A reviewer blocks correctness, reliability,
maintainability, rollback, security, reach, or proof defects; taste alone does
not overturn ratified direction.

## Pull requests

State the observable result, affected surfaces, checks actually run, known
gaps, and rollback. Never include secrets or private operational context. A
local green result is not a claim that a pull request is mergeable, merged, or
deployed.

Contributions are licensed under AGPL-3.0-only.
