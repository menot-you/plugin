#!/usr/bin/env bash
set -euo pipefail

die() { printf 'client-discovery-test: %s\n' "$*" >&2; exit 1; }
root=${1:-$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd -P)}
for command_name in cat chmod claude codex git grep jq mkfifo mktemp tar; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done

scratch_parent=${NSOUL_TEST_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-}/.cache}}
[[ -n "$scratch_parent" ]] || die 'no private scratch parent is available'
mkdir -p "$scratch_parent"
scratch=$(mktemp -d "$scratch_parent/nsoul-client.XXXXXXXX")
codex_app_pid=
cleanup() {
  if [[ -n "$codex_app_pid" ]]; then
    kill "$codex_app_pid" 2>/dev/null || :
    wait "$codex_app_pid" 2>/dev/null || :
  fi
  find "$scratch" -depth -delete
}
trap cleanup EXIT HUP INT TERM
repo=$scratch/repo
mkdir -p "$repo" "$scratch/home" "$scratch/claude" "$scratch/codex"
(cd "$root" && tar --exclude='./.git' -cf - .) | (cd "$repo" && tar -xf -)
git -C "$repo" init -q -b main
git -C "$repo" -c core.hooksPath=/dev/null add -A
git -C "$repo" -c core.hooksPath=/dev/null -c user.name='nSOUL Release Probe' -c user.email='nsoul@invalid.example' commit -qm 'release probe'

HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin marketplace add "$repo" --scope user >"$scratch/claude-marketplace.out"
HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin list --available --json >"$scratch/claude-available.json"
jq -e 'any(.available[]; .pluginId == "nott@nsoul") and ([.available[].pluginId] | all(contains("lab") | not))' "$scratch/claude-available.json" >/dev/null || die 'Claude marketplace inventory is wrong'
HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin install nott@nsoul --scope user >"$scratch/claude-install.out"
HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin list --json >"$scratch/claude-installed.json"
jq -e '
  any(.[]; .id == "nott@nsoul" and .enabled == true)
  and ([.[] | select(.id == "nott@nsoul") | .mcpServers | keys] | first | sort) == ["nmemory"]
' "$scratch/claude-installed.json" >/dev/null || die 'Claude installed inventory or MCP discovery is wrong'
HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin details nott@nsoul >"$scratch/claude-details.txt"
grep -Eq 'Skills \(11\).*readback' "$scratch/claude-details.txt" || die 'Claude did not discover 11 skills'
grep -Eq 'Agents \(6\)' "$scratch/claude-details.txt" || die 'Claude did not discover 6 agents'
grep -Eq 'Hooks \(4\)' "$scratch/claude-details.txt" || die 'Claude did not discover 4 hooks'
grep -Eq 'MCP servers \(1\).*nmemory' "$scratch/claude-details.txt" || die 'Claude did not discover 1 MCP server'

HOME="$scratch/home" CODEX_HOME="$scratch/codex" codex plugin marketplace add "$repo" --json >"$scratch/codex-marketplace.json"
jq -e '.marketplaceName == "nsoul"' "$scratch/codex-marketplace.json" >/dev/null || die 'Codex marketplace id is wrong'
HOME="$scratch/home" CODEX_HOME="$scratch/codex" codex plugin list --marketplace nsoul --available --json >"$scratch/codex-available.json"
jq -e 'any(.available[]; .pluginId == "nott@nsoul")' "$scratch/codex-available.json" >/dev/null || die 'Codex marketplace inventory is wrong'
HOME="$scratch/home" CODEX_HOME="$scratch/codex" codex plugin add nott@nsoul --json >"$scratch/codex-install.json"
jq -e '.pluginId == "nott@nsoul" and .version == "0.3.0"' "$scratch/codex-install.json" >/dev/null || die 'Codex install result is wrong'
installed_path=$(jq -r '.installedPath // empty' "$scratch/codex-install.json")
[[ -d "$installed_path" ]] || die 'Codex install path is missing'
HOME="$scratch/home" CODEX_HOME="$scratch/codex" codex plugin list --marketplace nsoul --json >"$scratch/codex-installed.json"
jq -e 'any(.installed[]; .pluginId == "nott@nsoul" and .installed == true and .enabled == true)' "$scratch/codex-installed.json" >/dev/null || die 'Codex plugin is not installed and enabled'
HOME="$scratch/home" CODEX_HOME="$scratch/codex" codex mcp list --json >"$scratch/codex-mcp.json"
jq -e '
  ([.[].name] | sort) == ["nmemory"]
  and all(.[]; .enabled == true and .transport.type == "stdio")
  and any(.[]; .name == "nmemory" and .transport.command == "/bin/sh" and .transport.args == ["./bin/nmemory-mcp", "--project", "nott"] and .transport.env_vars == ["NOTT_NMEMORY_BIN"])
' "$scratch/codex-mcp.json" >/dev/null || die 'Codex MCP projection is wrong or duplicated'

fake_mcp=$scratch/fake-mcp
cat >"$fake_mcp" <<'FAKE'
#!/bin/sh
set -eu
if [ "${NOTT_NMEMORY_BIN:-}" = "$0" ] && [ -z "${NOTT_NBROWSER_BIN:-}" ]; then
  marker=${0%/*}/nmemory.started
elif [ "${NOTT_NBROWSER_BIN:-}" = "$0" ] && [ -z "${NOTT_NMEMORY_BIN:-}" ]; then
  marker=${0%/*}/nbrowser.started
else
  exit 90
fi
printf '%s\n' "$PWD" >"$marker"
while IFS= read -r request; do
  method=$(printf '%s\n' "$request" | jq -r '.method // empty')
  id=$(printf '%s\n' "$request" | jq -c '.id')
  case "$method" in
    initialize)
      protocol=$(printf '%s\n' "$request" | jq -r '.params.protocolVersion')
      printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"%s","capabilities":{},"serverInfo":{"name":"nsoul-env-probe","version":"1.0.0"}}}\n' "$id" "$protocol"
      ;;
    tools/list)
      printf '{"jsonrpc":"2.0","id":%s,"result":{"tools":[]}}\n' "$id"
      ;;
  esac
done
FAKE
chmod 0700 "$fake_mcp"

app_in=$scratch/codex-app.in
app_out=$scratch/codex-app.out
app_log=$scratch/codex-app.jsonl
mkfifo "$app_in" "$app_out"
HOME="$scratch/home" CODEX_HOME="$scratch/codex" \
  NOTT_NMEMORY_BIN="$fake_mcp" NOTT_NBROWSER_BIN="$fake_mcp" \
  codex app-server --stdio <"$app_in" >"$app_out" 2>"$scratch/codex-app.err" &
codex_app_pid=$!
exec 7>"$app_in"
exec 8<"$app_out"
printf '%s\n' \
  '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"nsoul-env-probe","version":"1"}}}' \
  '{"method":"initialized"}' \
  '{"id":2,"method":"mcpServerStatus/list","params":{"detail":"toolsAndAuthOnly"}}' >&7

: >"$app_log"
status_seen=false
deadline=$((SECONDS + 10))
while (( SECONDS < deadline )); do
  if IFS= read -r -t 1 line <&8; then
    printf '%s\n' "$line" >>"$app_log"
    if printf '%s\n' "$line" | jq -e '.id == 2' >/dev/null; then
      status_seen=true
      break
    fi
  elif ! kill -0 "$codex_app_pid" 2>/dev/null; then
    break
  fi
done
exec 7>&-
kill "$codex_app_pid" 2>/dev/null || :
wait "$codex_app_pid" 2>/dev/null || :
codex_app_pid=
exec 8<&-

$status_seen || { cat "$scratch/codex-app.err" >&2; die 'Codex MCP startup timed out'; }
jq -s -e '
  any(.[]; .id == 2
    and ([.result.data[] | select(.serverInfo.name == "nsoul-env-probe") | .name] | sort)
      == ["nmemory"])
' "$app_log" >/dev/null || die 'Codex did not start the plugin MCP'
[[ -f "$scratch/nmemory.started" && $(<"$scratch/nmemory.started") == "$installed_path" ]] || die 'Codex did not forward NOTT_NMEMORY_BIN into the plugin cwd'
[[ ! -e "$scratch/nbrowser.started" ]] || die 'withdrawn nBrowser MCP was started by Codex'

claude_state_empty() {
  jq -e 'all(.[]; .id != "nott@nsoul")' "$1" >/dev/null &&
    jq -e 'length == 0' "$2" >/dev/null
}

HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin uninstall nott@nsoul --scope user >"$scratch/claude-uninstall.out"
HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin list --json >"$scratch/claude-uninstalled.json"
HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin marketplace list --json >"$scratch/claude-marketplace-retained.json"
jq -e 'all(.[]; .id != "nott@nsoul")' "$scratch/claude-uninstalled.json" >/dev/null || die 'Claude uninstall left the plugin installed'
jq -e 'any(.[]; .name == "nsoul")' "$scratch/claude-marketplace-retained.json" >/dev/null || die 'Claude stale-marketplace differentiator did not retain the marketplace'
if claude_state_empty "$scratch/claude-uninstalled.json" "$scratch/claude-marketplace-retained.json"; then
  die 'Claude empty-state check accepted a retained marketplace'
fi

HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin marketplace remove nsoul --scope user >"$scratch/claude-marketplace-remove.out"
HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin list --json >"$scratch/claude-removed.json"
HOME="$scratch/home" CLAUDE_CONFIG_DIR="$scratch/claude" claude plugin marketplace list --json >"$scratch/claude-marketplace-removed.json"
claude_state_empty "$scratch/claude-removed.json" "$scratch/claude-marketplace-removed.json" || die 'Claude first-release rollback left plugin or marketplace state'

HOME="$scratch/home" CODEX_HOME="$scratch/codex" codex plugin remove nott@nsoul >"$scratch/codex-remove.out"
HOME="$scratch/home" CODEX_HOME="$scratch/codex" codex plugin marketplace remove nsoul >"$scratch/codex-marketplace-remove.out"
HOME="$scratch/home" CODEX_HOME="$scratch/codex" codex plugin list --json >"$scratch/codex-removed.json"
jq -e '(.installed | length) == 0 and (.available | length) == 0' "$scratch/codex-removed.json" >/dev/null || die 'Codex first-release rollback left plugin or marketplace state'

claude plugin marketplace add --help | grep -q '<source>' || die 'Claude marketplace add command is unavailable'
claude plugin install --help | grep -q '<plugin>' || die 'Claude install command is unavailable'
claude plugin uninstall --help | grep -q '<plugin>' || die 'Claude uninstall command is unavailable'
claude plugin marketplace remove --help | grep -q '<name>' || die 'Claude marketplace remove command is unavailable'
codex plugin marketplace add --help | grep -q '<SOURCE>' || die 'Codex marketplace add command is unavailable'
codex plugin remove --help | grep -q '<PLUGIN' || die 'Codex remove command is unavailable'
codex plugin marketplace remove --help | grep -q '<MARKETPLACE_NAME>' || die 'Codex marketplace remove command is unavailable'

printf 'client-discovery-test: pass (Claude 11/6/4/2; Codex plugin + 2 controlled local MCP adapters started; first-release removal read back)\n'
