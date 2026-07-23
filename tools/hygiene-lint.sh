#!/usr/bin/env bash
set -euo pipefail

die() { printf 'hygiene-lint: FAIL %s %s\n' "$1" "${2:-}" >&2; exit 1; }
for command_name in awk find grep jq mktemp od rm sort; do
  command -v -- "$command_name" >/dev/null 2>&1 || die dependency "$command_name"
done
[[ "$#" -eq 1 ]] || die USAGE 'hygiene-lint.sh REPOSITORY_ROOT'
root=$1
[[ -d "$root" && ! -L "$root" ]] || die TREE_NODE "$root"

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    die dependency 'sha256sum or shasum'
  fi
}
expected_license_sha256=8486a10c4393cee1c25392769ddd3b2d6c242d6ec7928e1414efff7dfb2f07ef
expected_notice_sha256=d1ad94fcc32a57b91db957dbda4c149fd4e060f7968bbb237a687d463762ccdf
[[ -f "$root/LICENSE" && ! -L "$root/LICENSE" ]] || die public-vocabulary LICENSE
[[ $(sha256_file "$root/LICENSE") == "$expected_license_sha256" ]] || die public-vocabulary LICENSE
[[ -f "$root/NOTICE" && ! -L "$root/NOTICE" ]] || die public-vocabulary NOTICE
[[ $(sha256_file "$root/NOTICE") == "$expected_notice_sha256" ]] || die public-vocabulary NOTICE

if find "$root" -path "$root/.git" -prune -o -type l -print -quit | grep -q .; then
  die TREE_NODE symlink
fi
if find "$root" -path "$root/.git" -prune -o ! -type d ! -type f -print -quit | grep -q .; then
  die TREE_NODE special
fi
while IFS= read -r -d '' file; do
  # Curated public media lives under assets/; a binary there is expected. Any
  # other binary in the tree is still rejected (the red test plants one at root).
  case "${file#"$root"/}" in assets/*) continue ;; esac
  if LC_ALL=C od -An -tx1 "$file" | grep -Eq '(^|[[:space:]])00([[:space:]]|$)'; then
    die BINARY_FILE "${file#"$root"/}"
  fi
done < <(find "$root" -path "$root/.git" -prune -o -type f -print0)
while IFS= read -r -d '' node; do
  if printf '%s' "$node" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    die TREE_NODE control-character
  fi
done < <(find "$root" -path "$root/.git" -prune -o -print0)
if find "$root" -path '*/lab' -o -path '*/lab/*' | grep -q .; then
  die PRIVATE_SURFACE lab
fi
while IFS= read -r -d '' vcs_dir; do
  [[ "$vcs_dir" == "$root/.git" ]] || die TREE_NODE nested-vcs
done < <(find "$root" -type d -name .git -print0)
gitleaks_config='.gitleaks.''toml'
gitleaks_ignore='.gitleaks''ignore'
suppression_path=$(find "$root" -path "$root/.git" -prune -o -type f \( -name "$gitleaks_config" -o -name "$gitleaks_ignore" \) -print -quit)
if [[ -n "$suppression_path" ]]; then
  die secret-suppression "${suppression_path#"$root"/}"
fi

scan_rule() {
  local rule=$1 pattern=$2 hit status scan_status=0
  : >"$scratch/hits"
  : >"$scratch/grep.err"
  while IFS= read -r -d '' file; do
    set +e
    grep -lE -- "$pattern" "$file" >>"$scratch/hits" 2>>"$scratch/grep.err"
    status=$?
    set -e
    case "$status" in
      0|1) ;;
      *) scan_status=$status; break ;;
    esac
  done < <(find "$root" -path "$root/.git" -prune -o -type f -print0)
  [[ "$scan_status" -eq 0 ]] || die SCAN_IO "$rule"
  if [[ -s "$scratch/hits" ]]; then
    IFS= read -r hit <"$scratch/hits"
    die "$rule" "${hit#"$root"/}"
  fi
}

scan_path_rule() {
  local rule=$1 pattern=$2 node relative
  while IFS= read -r -d '' node; do
    [[ "$node" == "$root" ]] && continue
    relative=${node#"$root"/}
    if printf '/%s\n' "$relative" | LC_ALL=C grep -qE -- "$pattern"; then
      die "$rule" "$relative"
    fi
  done < <(find "$root" -path "$root/.git" -prune -o -print0)
}

operational_prefixes=ABCDE
operational_prefixes=${operational_prefixes}FGSTUW
operational_id_hits() {
  awk -v prefixes="$operational_prefixes" '
    {
      line=$0
      gsub(/[^A-Z0-9]/, " ", line)
      count=split(line, words, /[[:space:]]+/)
      for (i=1; i<=count; i++) {
        word=words[i]
        if (length(word) >= 9 && word ~ ("^[" prefixes "]")) print word
      }
    }
  ' "$@"
}

applicable=APPLI; applicable=${applicable}CABLE
architecture=ARCHI; architecture=${architecture}TECTURE
available=AVAIL; available=${available}ABLE
changelog=CHANGE; changelog=${changelog}LOG
checklist=CHECK; checklist=${checklist}LIST
committer=COMMI; committer=${committer}TTER
conditions=CONDI; conditions=${conditions}TIONS
consequential=CONSE; consequential=${consequential}QUENTIAL
contributing=CONTRI; contributing=${contributing}BUTING
copyright=COPY; copyright=${copyright}RIGHT
correction=CORREC; correction=${correction}TION
defective=DEFEC; defective=${defective}TIVE
dependency=DEPEN; dependency=${dependency}DENCY
directory=DIREC; directory=${directory}TORY
executable=EXECU; executable=${executable}TABLE
expressed=EXPRE; expressed=${expressed}SSED
servicing=SERVI; servicing=${servicing}CING
suppression=SUPPR; suppression=${suppression}ESSION
sustained=SUSTA; sustained=${sustained}INED
warranties=WARRAN; warranties=${warranties}TIES

is_fixed_public_vocabulary() {
  local lane=$1 relative=$2 word=$3
  case "$lane:$relative:$word" in
    "content:LICENSE:$applicable"|"content:LICENSE:$conditions"|"content:LICENSE:$consequential"|\
    "content:LICENSE:$copyright"|"content:LICENSE:$correction"|"content:LICENSE:$defective"|\
    "content:LICENSE:$expressed"|"content:LICENSE:$servicing"|"content:LICENSE:$sustained"|\
    "content:LICENSE:$warranties"|\
    "content:.agents/plugins/marketplace.json:$available"|\
    "content:README.md:$architecture"|"content:README.md:$checklist"|"content:README.md:$contributing"|\
    "content:ARCHITECTURE.md:$architecture"|"path:ARCHITECTURE.md:$architecture"|\
    "content:release/inventory.tsv:$architecture"|\
    "path:assets/architecture.svg:$architecture"|"path:assets/architecture.png:$architecture"|\
    "content:release/inventory.tsv:$changelog"|"content:release/inventory.tsv:$checklist"|\
    "content:release/inventory.tsv:$contributing"|\
    "content:tests/docs-test.sh:$changelog"|"content:tests/docs-test.sh:$checklist"|\
    "content:tests/docs-test.sh:$contributing"|\
    "content:tests/gates-red-test.sh:$committer"|"content:tests/gates-red-test.sh:$directory"|\
    "content:tests/manifest-test.sh:$changelog"|"content:tests/manifest-test.sh:$checklist"|\
    "content:tests/manifest-test.sh:$contributing"|\
    "content:tools/hygiene-lint.sh:$applicable"|"content:tools/hygiene-lint.sh:$architecture"|"content:tools/hygiene-lint.sh:$available"|\
    "content:tools/hygiene-lint.sh:$changelog"|"content:tools/hygiene-lint.sh:$checklist"|\
    "content:tools/hygiene-lint.sh:$committer"|"content:tools/hygiene-lint.sh:$conditions"|\
    "content:tools/hygiene-lint.sh:$consequential"|"content:tools/hygiene-lint.sh:$contributing"|\
    "content:tools/hygiene-lint.sh:$copyright"|"content:tools/hygiene-lint.sh:$correction"|\
    "content:tools/hygiene-lint.sh:$defective"|"content:tools/hygiene-lint.sh:$dependency"|\
    "content:tools/hygiene-lint.sh:$directory"|"content:tools/hygiene-lint.sh:$executable"|\
    "content:tools/hygiene-lint.sh:$expressed"|"content:tools/hygiene-lint.sh:$suppression"|\
    "content:tools/hygiene-lint.sh:$warranties"|\
    "path:$changelog.md:$changelog"|"path:$contributing.md:$contributing"|\
    "path:RELEASE-$checklist.md:$checklist") return 0 ;;
  esac
  return 1
}

part_no='no'
part_tt='tt'
slash='/'
private_root="${slash}${part_no}${part_tt}(${slash}|[^[:alnum:]_-]|$)"
home_root="${slash}ho"'me/'
root_home="${slash}ro"'ot/'
user_root="${slash}Us"'ers/'
temp_root="${slash}var${slash}tm"'p/'
internal_one="${part_no}${part_tt}-dev"
internal_two="${part_no}${part_tt}-prod"
private_repo="menot-you/${part_no}${part_tt}-monorepo"
campaign_one='nD''OOR'
campaign_two='nD''ECK'
campaign_three='happy''day'
slice_marker='slices/''wi-'
constraint_marker='prds/n''MEMORY'
adr_marker='docs/''adr/'
matrix_marker='docs/enforcement-''matrix'
lab_marker='nott-''lab'
suppression_one='gitleaks:''allow'
suppression_two='gitleaks''ignore'

path_boundary='(^|[^[:alnum:]_$}{.-])'
scan_rule HOST_PATH "${path_boundary}(${private_root}|${home_root}|${root_home}|${user_root}|${temp_root})|${private_repo}"
scan_rule HOST_NAME "${internal_one}|${internal_two}"
scan_rule HOST_IP '(^|[^0-9])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9]|$)'
scan_path_rule HOST_PATH "${path_boundary}(${private_root}|${home_root}|${root_home}|${user_root}|${temp_root})|${private_repo}"
scan_path_rule HOST_NAME "${internal_one}|${internal_two}"
scan_path_rule HOST_IP '(^|[^0-9])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9]|$)'
while IFS= read -r -d '' file; do
  relative=${file#"$root"/}
  # The operational-id token scan is text-only; binary assets (png/gif/mp4)
  # produce false positives. Secrets in binaries are Gitleaks' lane, not this one.
  grep -Iq . "$file" || continue
  operational_id_hits "$file" >"$scratch/id-hits" 2>"$scratch/awk.err" || die SCAN_IO OPERATIONAL_ID
  while IFS= read -r word; do
    [[ -n "$word" ]] || continue
    is_fixed_public_vocabulary content "$relative" "$word" || die OPERATIONAL_ID "$relative"
  done <"$scratch/id-hits"
done < <(find "$root" -path "$root/.git" -prune -o -type f -print0)
while IFS= read -r -d '' node; do
  [[ "$node" == "$root" ]] && continue
  relative=${node#"$root"/}
  printf '%s\n' "$relative" >"$scratch/path"
  operational_id_hits "$scratch/path" >"$scratch/id-hits" 2>"$scratch/awk.err" || die SCAN_IO OPERATIONAL_ID
  while IFS= read -r word; do
    [[ -n "$word" ]] || continue
    is_fixed_public_vocabulary path "$relative" "$word" || die OPERATIONAL_ID "$relative"
  done <"$scratch/id-hits"
done < <(find "$root" -path "$root/.git" -prune -o -print0)
scan_rule OPERATIONAL_URL 'https://[^/[:space:]]+\.slack\.com'
scan_rule PRIVATE_HISTORY "cap-[0-9]+|${slice_marker}|wi-[0-9]+|owner (calibration|ratification|request) [0-9]{4}-|${campaign_one}|${campaign_two}|${campaign_three}|${constraint_marker}|${adr_marker}|${matrix_marker}|${lab_marker}"
scan_rule secret-suppression "${suppression_one}|${suppression_two}"
scan_path_rule PRIVATE_HISTORY "cap-[0-9]+|${slice_marker}|wi-[0-9]+|owner (calibration|ratification|request) [0-9]{4}-|${campaign_one}|${campaign_two}|${campaign_three}|${constraint_marker}|${adr_marker}|${matrix_marker}|${lab_marker}"

runtime_pattern='(^|[;&|[:space:]])(curl|wget|ssh|scp|rsync|nc|netcat)([;&|[:space:]]|$)|git[[:space:]]+(clone|fetch|pull)|cargo[[:space:]]+install|npm[[:space:]]+install|(^|[;&|[:space:]])eval([;&|[:space:]]|$)'
for runtime in "$root/hooks/nott-hook.sh" "$root/bin/nmemory-mcp" "$root/bin/nbrowser-mcp"; do
  [[ -f "$runtime" && -x "$runtime" && ! -L "$runtime" ]] || die executable "${runtime#"$root"/}"
  if grep -E "$runtime_pattern" "$runtime" >/dev/null 2>&1; then
    die OFFLINE_EXEC "${runtime#"$root"/}"
  fi
done

contract=$root/release/public-contract.json
claude_market=$root/.claude-plugin/marketplace.json
claude_plugin=$root/.claude-plugin/plugin.json
codex_market=$root/.agents/plugins/marketplace.json
codex_plugin=$root/.codex-plugin/plugin.json
for json in "$contract" "$claude_market" "$claude_plugin" "$codex_market" "$codex_plugin" "$root/.mcp.json" "$root/.codex-plugin/mcp.json"; do
  jq -e . "$json" >/dev/null 2>&1 || die JSON "${json#"$root"/}"
done
jq -e '
  (keys | sort) == ["distribution", "integrations", "runtimeDependencies", "schemaVersion", "toolchain"]
  and .schemaVersion == 2
  and (.distribution | keys | sort) == ["authorityDecision", "developer", "displayName", "license", "marketplaceName", "pluginName", "repository", "version"]
  and .distribution.marketplaceName == "nsoul"
  and .distribution.displayName == "nSOUL"
  and .distribution.pluginName == "nott"
  and (.distribution.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
  and .distribution.developer == "menot-you"
  and .distribution.repository == "https://github.com/menot-you/nsoul"
  and .distribution.license == "AGPL-3.0-only"
  and .distribution.authorityDecision == "d25-public-distribution-boundary"
  and (.integrations | keys | sort) == ["nbrowser", "nmemory"]
  and (.integrations.nmemory | keys | sort) == ["executable", "launcher", "override"]
  and .integrations.nmemory.launcher == "bin/nmemory-mcp"
  and .integrations.nmemory.override == "NOTT_NMEMORY_BIN"
  and .integrations.nmemory.executable == "nmemory"
  and (.integrations.nbrowser | keys | sort) == ["executable", "launcher", "override"]
  and .integrations.nbrowser.launcher == "bin/nbrowser-mcp"
  and .integrations.nbrowser.override == "NOTT_NBROWSER_BIN"
  and .integrations.nbrowser.executable == "nbrowser-mcp"
' "$contract" >/dev/null || die PUBLIC_IDENTITY release/public-contract.json

marketplace_name=$(jq -r '.distribution.marketplaceName' "$contract")
display_name=$(jq -r '.distribution.displayName' "$contract")
plugin_name=$(jq -r '.distribution.pluginName' "$contract")
version=$(jq -r '.distribution.version' "$contract")
developer=$(jq -r '.distribution.developer' "$contract")
repository=$(jq -r '.distribution.repository' "$contract")
license=$(jq -r '.distribution.license' "$contract")
authority_decision=$(jq -r '.distribution.authorityDecision' "$contract")
developer_url=${repository%/*}
homepage=${repository}#readme
awk -v wanted="**$authority_decision**" '$1 == "-" && $2 == wanted { found=1 } END { exit !found }' "$root/decisions.md" || die PUBLIC_IDENTITY release/public-contract.json

jq -e '
  (keys | sort) == ["$schema", "description", "name", "owner", "plugins"]
  and (.owner | keys | sort) == ["name", "url"]
  and (.plugins[0] | keys | sort) == ["category", "description", "homepage", "name", "source", "tags", "version"]
  and .plugins[0].source == "./"
  and .plugins[0].category == "development"
' "$claude_market" >/dev/null || die PUBLIC_IDENTITY .claude-plugin/marketplace.json
[[ $(jq -r '.name' "$claude_market") == "$marketplace_name" ]] || die PUBLIC_IDENTITY .claude-plugin/marketplace.json
[[ $(jq -r '.owner.name' "$claude_market") == "$developer" ]] || die PUBLIC_IDENTITY .claude-plugin/marketplace.json
[[ $(jq -r '.owner.url' "$claude_market") == "$repository" ]] || die PUBLIC_IDENTITY .claude-plugin/marketplace.json
[[ $(jq '.plugins | length' "$claude_market") -eq 1 ]] || die PRIVATE_SURFACE .claude-plugin/marketplace.json
[[ $(jq -r '.plugins[0].name' "$claude_market") == "$plugin_name" ]] || die PUBLIC_IDENTITY .claude-plugin/marketplace.json
[[ $(jq -r '.plugins[0].version' "$claude_market") == "$version" ]] || die PUBLIC_IDENTITY .claude-plugin/marketplace.json
[[ $(jq -r '.plugins[0].homepage' "$claude_market") == "$repository" ]] || die PUBLIC_IDENTITY .claude-plugin/marketplace.json

jq -e '
  (keys | sort) == ["$schema", "author", "description", "homepage", "keywords", "license", "name", "repository", "version"]
  and (.author | keys | sort) == ["name"]
' "$claude_plugin" >/dev/null || die PUBLIC_IDENTITY .claude-plugin/plugin.json
[[ $(jq -r '.name' "$claude_plugin") == "$plugin_name" ]] || die PUBLIC_IDENTITY .claude-plugin/plugin.json
[[ $(jq -r '.version' "$claude_plugin") == "$version" ]] || die PUBLIC_IDENTITY .claude-plugin/plugin.json
[[ $(jq -r '.author.name' "$claude_plugin") == "$developer" ]] || die PUBLIC_IDENTITY .claude-plugin/plugin.json
[[ $(jq -r '.homepage' "$claude_plugin") == "$repository" ]] || die PUBLIC_IDENTITY .claude-plugin/plugin.json
[[ $(jq -r '.repository' "$claude_plugin") == "$repository" ]] || die PUBLIC_IDENTITY .claude-plugin/plugin.json
[[ $(jq -r '.license' "$claude_plugin") == "$license" ]] || die PUBLIC_IDENTITY .claude-plugin/plugin.json

jq -e '
  (keys | sort) == ["author", "description", "homepage", "interface", "keywords", "license", "mcpServers", "name", "repository", "skills", "version"]
  and (.author | keys | sort) == ["name", "url"]
  and (.interface | keys | sort) == ["brandColor", "capabilities", "category", "defaultPrompt", "developerName", "displayName", "longDescription", "shortDescription", "websiteURL"]
' "$codex_plugin" >/dev/null || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.name' "$codex_plugin") == "$plugin_name" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.version' "$codex_plugin") == "$version" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.author.name' "$codex_plugin") == "$developer" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.author.url' "$codex_plugin") == "$developer_url" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.homepage' "$codex_plugin") == "$homepage" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.repository' "$codex_plugin") == "$repository" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.license' "$codex_plugin") == "$license" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.interface.developerName' "$codex_plugin") == "$developer" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.interface.websiteURL' "$codex_plugin") == "$repository" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.name' "$codex_market") == "$marketplace_name" ]] || die PUBLIC_IDENTITY .agents/plugins/marketplace.json
[[ $(jq -r '.interface.displayName' "$codex_market") == "$display_name" ]] || die PUBLIC_IDENTITY .agents/plugins/marketplace.json
[[ $(jq -r '.plugins[0].name' "$codex_market") == "$plugin_name" ]] || die PUBLIC_IDENTITY .agents/plugins/marketplace.json
jq -e --arg available "$available" '
  (keys | sort) == ["interface", "name", "plugins"]
  and (.interface | keys) == ["displayName"]
  and (.plugins | length) == 1
  and (.plugins[0] | keys | sort) == ["category", "name", "policy", "source"]
  and (.plugins[0].source | keys | sort) == ["source", "url"]
  and .plugins[0].source.source == "url"
  and .plugins[0].source.url == "./"
  and (.plugins[0].policy | keys | sort) == ["authentication", "installation"]
  and .plugins[0].policy.installation == $available
  and .plugins[0].policy.authentication == "ON_INSTALL"
  and .plugins[0].category == "Developer Tools"
' "$codex_market" >/dev/null || die PUBLIC_IDENTITY .agents/plugins/marketplace.json
[[ $(jq -r '.interface.displayName' "$codex_plugin") == "$display_name" ]] || die PUBLIC_IDENTITY .codex-plugin/plugin.json
[[ $(jq -r '.mcpServers' "$codex_plugin") == './.codex-plugin/mcp.json' ]] || die MCP_MAPPING .codex-plugin/plugin.json

printf 'hygiene-lint: pass\n'
