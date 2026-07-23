# Public release checklist

The isolated candidate is acceptable for a local commit only when every
repository-owned row and independent review are observed green against its exact
bytes. Rows marked external block publication, not construction of the isolated
candidate. `tools/public-release-check.sh` is the executable source for
repository gates; this document explains the decision each gate changes.

| Check | Proof | Blocks |
|---|---|---|
| Core extraction | Exactly 11 skills, 6 agents, and no `lab` path | Private-surface inclusion or dropped capability |
| Tree custody | Regular files/directories only; no nested VCS state | Symlink or special-node escape |
| Public identity | Every duplicated distribution identity and URL projection equals `release/public-contract.json`; legal files remain byte-bound | Stale monorepo, contradictory license notice, or inconsistent brand metadata |
| Citation resolution | `PRD.md` §7 citation boundary: recognized local inline/reference targets and local file citations resolve to regular candidate files outside Git metadata; directory-shaped inline-code projections are navigation only | Private, missing, or unshippable authority dependency |
| Public hygiene | Raw current and historical tree paths, modes, and text contain no declared private-context signature or Slack-shaped identifier outside the fixed public-vocabulary contexts | Private-context disclosure or normalized-tree bypass |
| Secret detector | Gitleaks returns zero detector matches in current bytes, every raw reachable commit tree, every merge-parent diff, raw commit/tag metadata, ref names, and current or historical path names | Credential-like material |
| Runtime dependencies | Mode-specific commands are declared in `release/public-contract.json`; missing commands and a mismatched pinned validator are differentiating controls | Undeclared or unavailable release tooling |
| Candidate pin | A pinned current-directory root remains bound to the original path and filesystem identity; worktree bytes/modes, HEAD, direct-versus-symbolic ref topology, and Git reachability controls including commit-graph state remain unchanged across release probes | Transient root substitution, post-scan history, or candidate substitution |
| JSON and shell | Parsers succeed on Linux and macOS; ShellCheck succeeds once in the Linux job | Malformed runtime/configuration |
| Hook behavior | Exact event registration reaches the shipped hook; Claude root and subagent context carries the canon read path; default privacy, opt-in metadata only, bounded retention, and oversized recursive Stop fail-open behavior are observed | Registration/context bypass, transcript persistence, or recursive Stop loop |
| MCP adapter behavior | Both launchers pass precedence, rejection, forwarding, recursion, and child-status checks against controlled fixtures; matching-digest behavioral mutation remains red; no external-server attestation | Host-bound or overstated execution proof |
| Claude package | Strict validation, local marketplace install, two declared MCPs | Invalid Claude distribution |
| Codex package | Isolated marketplace add/install and two declared MCPs | Invalid Codex distribution |
| Client lifecycle | Disposable install, discovery, first-release removal, and empty installed-plugin plus marketplace readback pass for both clients | Stale install, stale marketplace, or rollback path |
| Cross-platform CI (external) | Linux and macOS jobs green on the public commit | Unsupported operating-system claim |
| Independent review | Read-only reviewer returns no blocking finding | Executor self-certification |
| Private reporting (external) | After repository creation, “Report a vulnerability” is observed available, or the detail-free contact-request fallback in `SECURITY.md` is usable | Dead or disclosure-inducing security channel |
| Publication authority (external) | Owner authorizes the exact repository/tag/push | Unauthorized public action |

The local `full` mode executes every row that can be observed on the current
host. Cross-platform CI, private-reporting availability, and publication remain
red until their external observations occur; local output never upgrades those
states.
