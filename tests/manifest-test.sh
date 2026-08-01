#!/usr/bin/env bash
set -euo pipefail

die() { printf 'manifest-test: %s\n' "$*" >&2; exit 1; }
root=${1:-$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd -P)}
for command_name in basename diff dirname find grep jq mktemp rm sed sort stat; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done

while IFS= read -r json; do
  jq -e . "$json" >/dev/null || die "invalid JSON: ${json#"$root"/}"
done < <(find "$root" -type f -name '*.json' -not -path '*/.git/*' | LC_ALL=C sort)

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

printf '%s\n' brainstorm debug design handoff plan ratify readback review routine security ship | LC_ALL=C sort >"$scratch/expected-skills"
for file in "$root"/skills/*/SKILL.md; do
  [[ -f "$file" ]] || continue
  basename "$(dirname "$file")"
done | LC_ALL=C sort >"$scratch/actual-skills"
diff -u "$scratch/expected-skills" "$scratch/actual-skills" >/dev/null || die 'skill inventory differs from the public contract'

jq -r '.interface.capabilities[]' "$root/.codex-plugin/plugin.json" | LC_ALL=C sort >"$scratch/capabilities"
diff -u "$scratch/expected-skills" "$scratch/capabilities" >/dev/null || die 'Codex capability inventory differs from shipped skills'

printf '%s\n' debugger executor planner researcher reviewer tester | LC_ALL=C sort >"$scratch/expected-agents"
for file in "$root"/agents/*.md; do
  [[ -f "$file" ]] || continue
  base=$(basename "$file")
  printf '%s\n' "${base%.md}"
done | LC_ALL=C sort >"$scratch/actual-agents"
diff -u "$scratch/expected-agents" "$scratch/actual-agents" >/dev/null || die 'agent inventory differs from the public contract'

# Six events, not four: the recall hooks ship (owner decision — they are this
# release's honest-recall feature, they fail open without a store, and the leg
# bundles bin/nmemory-mcp). session-digest, recall-inject and dispatch-recall are
# registered alongside nott-hook, and hooks.json ships as-is with no transform.
jq -e '
  .hooks == {
    "SessionStart": [{"hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:?plugin root unavailable}}/hooks/session-digest.sh\""}]}],
    "SubagentStart": [{"hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:?plugin root unavailable}}/hooks/nott-hook.sh\" SubagentStart"}]}],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:?plugin root unavailable}}/hooks/nott-hook.sh\" UserPromptSubmit"}]},
      {"hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:?plugin root unavailable}}/hooks/recall-inject.sh\""}]}
    ],
    "PreToolUse": [{"matcher": "Agent|Task", "hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:?plugin root unavailable}}/hooks/dispatch-recall.sh\""}]}],
    "PostToolUse": [{"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:?plugin root unavailable}}/hooks/nott-hook.sh\" PostToolUse"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:?plugin root unavailable}}/hooks/nott-hook.sh\" Stop"}]}]
  }
' "$root/hooks/hooks.json" >/dev/null || die 'hook registration differs from the public contract'
[[ $(grep -c '^  PreToolUse)' "$root/hooks/nott-hook.sh") -eq 1 ]] || die 'dormant PreToolUse handler inventory is ambiguous'

jq -r '.mcpServers | keys[]' "$root/.mcp.json" | LC_ALL=C sort >"$scratch/claude-mcp"
jq -r '.mcpServers | keys[]' "$root/.codex-plugin/mcp.json" | LC_ALL=C sort >"$scratch/codex-mcp"
printf '%s\n' nmemory >"$scratch/expected-mcp"
diff -u "$scratch/expected-mcp" "$scratch/claude-mcp" >/dev/null || die 'Claude MCP inventory differs from the public contract'
diff -u "$scratch/expected-mcp" "$scratch/codex-mcp" >/dev/null || die 'Codex MCP inventory differs from the public contract'

jq -e '
  .mcpServers.nmemory.type == "stdio"
  and .mcpServers.nmemory.command == "${CLAUDE_PLUGIN_ROOT}/bin/nmemory-mcp"
  and .mcpServers.nmemory.args == ["--project", "nott"]
  and (.mcpServers | has("nbrowser") | not)
' "$root/.mcp.json" >/dev/null || die 'Claude MCP projection is not plugin-relative'
jq -e '
  .mcpServers.nmemory.type == "stdio"
  and .mcpServers.nmemory.command == "/bin/sh"
  and .mcpServers.nmemory.args == ["./bin/nmemory-mcp", "--project", "nott"]
  and .mcpServers.nmemory.cwd == "."
  and .mcpServers.nmemory.env_vars == ["NOTT_NMEMORY_BIN"]
  and (.mcpServers | has("nbrowser") | not)
' "$root/.codex-plugin/mcp.json" >/dev/null || die 'Codex MCP projection is not plugin-root-relative'
jq -e '
  .schemaVersion == 2
  and .runtimeDependencies == {
    "plugin": {
      "hookRequired": ["awk", "head", "od", "sh"],
      "voiceLintAdditional": ["chmod", "date", "grep", "jq", "mkdir", "mktemp", "mv", "rm", "tail", "wc"]
    },
    "release": {
      "portable": ["awk", "bash", "diff", "find", "git", "gitleaks", "grep", "head", "jq", "mkdir", "mktemp", "od", "printenv", "sed", "sort", "stat", "tar"],
      "ci": ["shellcheck"],
      "full": ["claude", "codex"]
    }
  }
  and (.toolchain.gitleaks.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
  and (.toolchain.gitleaks.sha256 | keys | sort) == ["darwin_arm64", "darwin_x64", "linux_arm64", "linux_x64"]
  and all(.toolchain.gitleaks.sha256[]; type == "string" and test("^[0-9a-f]{64}$"))
' "$root/release/public-contract.json" >/dev/null || die 'runtime dependency or Gitleaks toolchain contract is incomplete'

for launcher in "$root/bin/nmemory-mcp"; do
  [[ -f "$launcher" && ! -L "$launcher" && -x "$launcher" ]] || die "invalid launcher: ${launcher#"$root"/}"
done
# Withdrawn in 0.3.0 by owner curation and declared in
# tools/mirror-strip.d/n-soul.list. Asserted as ABSENT rather than dropped from
# the test, so re-adding either path without a decision turns this red.
[[ ! -e "$root/bin/nbrowser-mcp" ]] || die 'withdrawn nBrowser launcher is back in the candidate'
[[ ! -e "$root/assets/nsoul-mark.svg" ]] || die 'retired brand mark is back in the candidate'
[[ -f "$root/LICENSE" && -f "$root/NOTICE" ]] || die 'license surface is incomplete'
[[ ! -e "$root/lab" ]] || die 'private lab entered the public candidate'

inventory=$root/release/inventory.tsv
[[ -f "$inventory" ]] || die 'release inventory is missing'
awk -F '\t' '
  NF != 4 { exit 1 }
  # `core-scrubbed` is retired: it meant "copied from plugin/ and altered on the way
  # out", and the collapse ended that — the leg IS plugin/, so nothing is copied and
  # nothing is scrubbed. Refused rather than merely unused, so the dead provenance
  # cannot reappear silently.
  $2 !~ /^(core-as-is|release-support)$/ { exit 1 }
  $2 ~ /^core-/ && $3 != "plugin/" $1 { exit 1 }
  $2 == "release-support" && $3 != "-" { exit 1 }
  $4 != "100644" && $4 != "100755" { exit 1 }
  $2 == "core-as-is" { as_is++ }
  $2 == "core-scrubbed" { scrubbed++ }
  END { exit !(as_is == 12 && scrubbed == 15) }
' "$inventory" || die 'release inventory does not account for the 12/15 core cut'
cat >"$scratch/expected-core-as-is" <<'EOF'
agents/debugger.md
agents/executor.md
agents/researcher.md
agents/reviewer.md
agents/tester.md
hooks/hooks.json
skills/debug/SKILL.md
skills/design/SKILL.md
skills/readback/SKILL.md
skills/review/SKILL.md
skills/security/SKILL.md
skills/ship/SKILL.md
EOF
cat >"$scratch/expected-core-scrubbed" <<'EOF'
.claude-plugin/marketplace.json
.claude-plugin/plugin.json
.codex-plugin/plugin.json
NOTT.md
PRD.md
SPEC.md
agents/planner.md
decisions.md
hooks/nott-hook.sh
skills/brainstorm/SKILL.md
skills/handoff/SKILL.md
skills/plan/SKILL.md
skills/ratify/SKILL.md
skills/routine/SKILL.md
wiki.md
EOF
awk -F '\t' '$2 == "core-as-is" { print $1 }' "$inventory" | LC_ALL=C sort >"$scratch/actual-core-as-is"
awk -F '\t' '$2 == "core-scrubbed" { print $1 }' "$inventory" | LC_ALL=C sort >"$scratch/actual-core-scrubbed"
diff -u "$scratch/expected-core-as-is" "$scratch/actual-core-as-is" >/dev/null || die 'core-as-is inventory is not the closed public set'
diff -u "$scratch/expected-core-scrubbed" "$scratch/actual-core-scrubbed" >/dev/null || die 'core-scrubbed inventory is not the closed public set'
cat >"$scratch/expected-support" <<'EOF'
.agents/plugins/marketplace.json
.codex-plugin/mcp.json
.github/workflows/public-release.yml
.mcp.json
ARCHITECTURE.md
CHANGELOG.md
CODE_OF_CONDUCT.md
CONTRIBUTING.md
LICENSE
NOTICE
PRIVACY.md
README.md
RELEASE-CHECKLIST.md
RUNBOOK.md
SECURITY.md
assets/act1-surface.png
assets/act2-rule.png
assets/act3-refuse.png
assets/architecture.png
assets/architecture.svg
assets/comparison.png
assets/comparison.svg
assets/demo-script.md
assets/demo.gif
assets/demo.mp4
assets/hero.png
assets/hero.svg
assets/logo.png
assets/logo.svg
assets/og.png
assets/og.svg
assets/one-rule.png
assets/one-rule.svg
bin/nmemory-mcp
release/inventory.tsv
release/public-contract.json
tests/client-discovery-test.sh
tests/docs-test.sh
tests/gates-red-test.sh
tests/hooks-test.sh
tests/manifest-test.sh
tests/mcp-launchers-test.sh
tools/citation-lint.sh
tools/doc-lint.sh
tools/history-hygiene.sh
tools/hygiene-lint.sh
tools/public-release-check.sh
EOF
awk -F '\t' '$2 == "release-support" { print $1 }' "$inventory" | LC_ALL=C sort >"$scratch/actual-support"
diff -u "$scratch/expected-support" "$scratch/actual-support" >/dev/null || die 'release-support inventory is not the closed public set'
cut -f1 "$inventory" | LC_ALL=C sort >"$scratch/declared-files"
find "$root" -path "$root/.git" -prune -o -type f -print \
  | while IFS= read -r file; do printf '%s\n' "${file#"$root"/}"; done \
  | LC_ALL=C sort >"$scratch/actual-files"
diff -u "$scratch/declared-files" "$scratch/actual-files" >/dev/null || die 'release inventory does not match candidate files'
while IFS=$'\t' read -r path _class _source expected_mode; do
  [[ -f "$root/$path" && ! -L "$root/$path" ]] || die "inventory path is not a regular file: $path"
  actual_mode=$(mode_of "$root/$path")
  [[ "$actual_mode" == "${expected_mode#100}" ]] || die "inventory mode differs: $path"
done <"$inventory"

printf 'manifest-test: pass (11 skills, 6 agents, 4 hooks, 1 external MCP adapter)\n'
