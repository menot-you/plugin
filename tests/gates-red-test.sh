#!/usr/bin/env bash
set -euo pipefail

die() { printf 'gates-red-test: %s\n' "$*" >&2; exit 1; }
root=${1:-$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd -P)}
for command_name in awk bash chmod cp dd env find git gitleaks grep jq mkdir mktemp mv od rm rmdir sed tar wc; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1" | awk '{print $1}'
  else die 'missing SHA-256 utility'; fi
}
sha1_file() {
  if command -v sha1sum >/dev/null 2>&1; then sha1sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 1 -- "$1" | awk '{print $1}'
  else die 'missing SHA-1 utility'; fi
}
append_hex_bytes_to() {
  local hex=$1 destination=$2
  while [[ -n "$hex" ]]; do
    printf '%b' "\\x${hex:0:2}" >>"$destination"
    hex=${hex:2}
  done
}
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM

dependency_root=$scratch/dependency-contract
mkdir -p "$dependency_root/tools" "$dependency_root/release"
cp "$root/tools/public-release-check.sh" "$dependency_root/tools/public-release-check.sh"
jq '.runtimeDependencies.release.portable += ["nsoul-missing-dependency"]' \
  "$root/release/public-contract.json" >"$dependency_root/release/public-contract.json"
set +e
dependency_output=$(bash "$dependency_root/tools/public-release-check.sh" portable 2>&1)
dependency_status=$?
set -e
[[ "$dependency_status" -ne 0 ]] || die 'release gate accepted a missing declared runtime dependency'
grep -qF 'missing required command: nsoul-missing-dependency' <<<"$dependency_output" || \
  die 'missing declared runtime dependency failed for the wrong reason'

jq '.toolchain.gitleaks.version = "0.0.0"' \
  "$root/release/public-contract.json" >"$dependency_root/release/public-contract.json"
set +e
dependency_output=$(bash "$dependency_root/tools/public-release-check.sh" portable 2>&1)
dependency_status=$?
set -e
[[ "$dependency_status" -ne 0 ]] || die 'release gate accepted a mismatched declared tool version'
grep -qF 'Gitleaks version differs from release contract' <<<"$dependency_output" || \
  die 'mismatched declared tool version failed for the wrong reason'


cat >"$scratch/hedge.md" <<'EOF'
# Red fixture

**Normative scope.** Sentences carrying **MUST**, **MUST NOT**, or **NEVER** are normative.

This value MUST maybe pass.
EOF
if bash "$root/tools/doc-lint.sh" "$scratch/hedge.md" >/dev/null 2>&1; then
  die 'doc gate accepted a hedge in normative scope'
fi
cat >"$scratch/undeclared-scope.md" <<'EOF'
# Red fixture

NEVER accept an undeclared normative scope.
EOF
if bash "$root/tools/doc-lint.sh" "$scratch/undeclared-scope.md" >/dev/null 2>&1; then
  die 'doc gate accepted an undeclared normative scope'
fi

cat >"$scratch/citation.md" <<'EOF'
# Red fixture

Reference: `tools/does-not-exist.md`
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted an unresolved local path'
fi
cat >"$scratch/citation.md" <<'EOF'
# Red fixture

Reference: `private-authority/DOES-NOT-EXIST.md`
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted an unresolved non-allowlisted local path'
fi
cat >"$scratch/citation.md" <<'EOF'
# Red fixture

[private authority](private-authority/secret)
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted an unresolved extensionless local path'
fi
cat >"$scratch/citation.md" <<'EOF'
# Red fixture

[private authority](secret)
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted an unresolved extensionless basename'
fi
mkdir -p "$scratch/citation-node/secret"
cat >"$scratch/citation-node/citation.md" <<'EOF'
# Red fixture

[private authority](secret)
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation-node/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted an unshippable directory target'
fi
cat >"$scratch/citation.md" <<'EOF'
# Red fixture

[private authority](.git/HEAD)
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted Git metadata as authority'
fi
cat >"$scratch/citation.md" <<'EOF'
# Red fixture

Reference: `d999`
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted a bare decision id'
fi
cat >"$scratch/citation.md" <<'EOF'
# Red fixture

Reference: `d25-public-distribution`
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted an unresolved decision-slug prefix'
fi
for malformed_decision in d9_private d9-UPPER d9-; do
  printf '%s\n' '# Red fixture' '' "\`$malformed_decision\`" >"$scratch/citation.md"
  if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
    die "citation gate accepted a malformed decision citation: $malformed_decision"
  fi
done
for decision_like_path in d9/DOES-NOT-EXIST.md d9-private/DOES-NOT-EXIST.md; do
  printf '%s\n' '# Red fixture' '' "\`$decision_like_path\`" >"$scratch/citation.md"
  if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation.md" >/dev/null 2>&1; then
    die "citation gate accepted an unresolved decision-like path: $decision_like_path"
  fi
done
citation_root=$scratch/citation-root
mkdir -p "$citation_root/private-authority/FAKE.md"
cp "$root/decisions.md" "$citation_root/decisions.md"
cat >"$citation_root/citation.md" <<'EOF'
# Red fixture

Reference: `private-authority/FAKE.md`
EOF
if bash "$root/tools/citation-lint.sh" "$citation_root" "$citation_root/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted a directory as a cited file'
fi
mkdir -p "$scratch/citation-dir"
: >"$scratch/outside.md"
cat >"$scratch/citation-dir/citation.md" <<'EOF'
# Red fixture

Reference: `../outside.md`
EOF
if bash "$root/tools/citation-lint.sh" "$root" "$scratch/citation-dir/citation.md" >/dev/null 2>&1; then
  die 'citation gate accepted a repository escape'
fi

citation_parser_root=$scratch/citation-parser-root
mkdir -p "$citation_parser_root/skills" "$citation_parser_root/release/private-authority" "$citation_parser_root/.git"
cp "$root/decisions.md" "$citation_parser_root/decisions.md"
printf 'target\n' >"$citation_parser_root/target.md"
printf 'target with spaces\n' >"$citation_parser_root/target file.md"
printf 'git metadata\n' >"$citation_parser_root/.git/HEAD"
cat >"$citation_parser_root/citation.md" <<'EOF'
# Positive citation parser fixture

[plain](target.md)
[titled](target.md "title")
[angle](<target file.md> "title")
[reference][local]

[local]: <target file.md> 'title'

Reference: `skills/`
EOF
bash "$root/tools/citation-lint.sh" "$citation_parser_root" "$citation_parser_root/citation.md" >/dev/null || die 'citation gate rejected supported link forms or directory navigation'

assert_citation_parser_rejected() {
  local label=$1 body=$2
  printf '# Red citation parser fixture\n\n%b\n' "$body" >"$citation_parser_root/citation.md"
  if bash "$root/tools/citation-lint.sh" "$citation_parser_root" "$citation_parser_root/citation.md" >/dev/null 2>&1; then
    die "citation gate accepted $label"
  fi
}
assert_citation_parser_rejected 'a titled missing target' '[bad](missing.md "title")'
assert_citation_parser_rejected 'an angle-bracket missing target' '[bad](<missing file.md> "title")'
assert_citation_parser_rejected 'a missing reference-definition target' '[bad][missing]\n\n[missing]: <missing file.md> "title"'
assert_citation_parser_rejected 'a directory inline-link target' '[bad](skills/)'
assert_citation_parser_rejected 'an allowlisted release directory link target' '[bad](release/private-authority)'
assert_citation_parser_rejected 'an inline Git-metadata target' '[bad](.git/HEAD)'
assert_citation_parser_rejected 'a reference-definition Git-metadata target' '[bad][git]\n\n[git]: .git/HEAD'

copy=$scratch/candidate
mkdir -p "$copy"
(cd "$root" && tar -cf - .) | (cd "$copy" && tar -xf -)

cp "$copy/hooks/hooks.json" "$scratch/hooks-registration.original"
jq '.hooks.Stop[0].hooks[0].command = "/bin/true"' \
  "$scratch/hooks-registration.original" >"$copy/hooks/hooks.json"
if bash "$copy/tests/manifest-test.sh" "$copy" >/dev/null 2>&1; then
  die 'manifest gate accepted a Stop registration that bypasses the shipped hook'
fi
cp "$scratch/hooks-registration.original" "$copy/hooks/hooks.json"

chmod 0664 "$copy/assets/nsoul-mark.svg"
if bash "$copy/tests/manifest-test.sh" "$copy" >/dev/null 2>&1; then
  die 'manifest gate accepted a group-writable release file'
fi
chmod 0644 "$copy/assets/nsoul-mark.svg"

awk '
  { print }
  $0 == "event=${1-}" { print "printf '\''%s'\'' \"$payload\" >>\"$RED_HOOK_SINK\"" }
' "$copy/hooks/nott-hook.sh" >"$copy/hooks/nott-hook.red"
mv "$copy/hooks/nott-hook.red" "$copy/hooks/nott-hook.sh"
chmod 0755 "$copy/hooks/nott-hook.sh"
hook_marker=NSOUL_RED_HOOK_WRITE
hook_sink=$scratch/red-hook-sink
printf '%s' "$hook_marker" | RED_HOOK_SINK="$hook_sink" NOTT_VOICE_LINT=off "$copy/hooks/nott-hook.sh" Stop >/dev/null
grep -qF "$hook_marker" "$hook_sink" || die 'write-capable hook fixture did not reach its sink'
if bash "$copy/tests/hooks-test.sh" "$copy" >/dev/null 2>&1; then
  die 'hook tests accepted a write-capable hook mutation'
fi
cp "$root/hooks/nott-hook.sh" "$copy/hooks/nott-hook.sh"
chmod 0755 "$copy/hooks/nott-hook.sh"

cp "$copy/tests/hooks-test.sh" "$scratch/hooks-test.original"
awk '
  $0 == "  UserPromptSubmit)" { in_user_prompt=1; print; next }
  in_user_prompt && $0 ~ /^    context=/ { next }
  in_user_prompt && $0 ~ /^    printf / {
    print "    printf '\''%s\\n'\'' '\''{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"\"}}'\''"
    in_user_prompt=0
    next
  }
  { print }
' "$copy/hooks/nott-hook.sh" >"$copy/hooks/nott-hook.context-red"
mv "$copy/hooks/nott-hook.context-red" "$copy/hooks/nott-hook.sh"
chmod 0755 "$copy/hooks/nott-hook.sh"
context_red_sha256=$(sha256_file "$copy/hooks/nott-hook.sh")
sed "s/^expected_hook_sha256=.*/expected_hook_sha256=$context_red_sha256/" \
  "$scratch/hooks-test.original" >"$copy/tests/hooks-test.sh"
set +e
context_red_output=$(bash "$copy/tests/hooks-test.sh" "$copy" 2>&1)
context_red_status=$?
set -e
[[ "$context_red_status" -ne 0 && "$context_red_output" == *'root-session context does not carry the canon orientation and exact read path'* ]] || \
  die 'hook behavior tests accepted an empty root-session canon context after a matching digest update'
cp "$root/hooks/nott-hook.sh" "$copy/hooks/nott-hook.sh"
chmod 0755 "$copy/hooks/nott-hook.sh"
cp "$scratch/hooks-test.original" "$copy/tests/hooks-test.sh"

awk '
  $0 == "  SubagentStart)" { in_subagent=1; print; next }
  in_subagent && $0 ~ /^    context=/ { next }
  in_subagent && $0 ~ /^    printf / {
    print "    printf '\''%s\\n'\'' '\''{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"\"}}'\''"
    in_subagent=0
    next
  }
  { print }
' "$copy/hooks/nott-hook.sh" >"$copy/hooks/nott-hook.subagent-context-red"
mv "$copy/hooks/nott-hook.subagent-context-red" "$copy/hooks/nott-hook.sh"
chmod 0755 "$copy/hooks/nott-hook.sh"
subagent_context_red_sha256=$(sha256_file "$copy/hooks/nott-hook.sh")
sed "s/^expected_hook_sha256=.*/expected_hook_sha256=$subagent_context_red_sha256/" \
  "$scratch/hooks-test.original" >"$copy/tests/hooks-test.sh"
set +e
subagent_context_red_output=$(bash "$copy/tests/hooks-test.sh" "$copy" 2>&1)
subagent_context_red_status=$?
set -e
[[ "$subagent_context_red_status" -ne 0 && "$subagent_context_red_output" == *'subagent context does not carry the canon orientation and exact read path'* ]] || \
  die 'hook behavior tests accepted an empty subagent canon context after a matching digest update'
cp "$root/hooks/nott-hook.sh" "$copy/hooks/nott-hook.sh"
chmod 0755 "$copy/hooks/nott-hook.sh"
cp "$scratch/hooks-test.original" "$copy/tests/hooks-test.sh"

awk '
  $0 == "exec \"$resolved\" \"$@\"" { print "brew install nmemory" }
  { print }
' "$copy/bin/nmemory-mcp" >"$copy/bin/nmemory-mcp.red"
mv "$copy/bin/nmemory-mcp.red" "$copy/bin/nmemory-mcp"
chmod 0755 "$copy/bin/nmemory-mcp"
launcher_red_path=$scratch/launcher-red-path
mkdir -p "$launcher_red_path"
cat >"$launcher_red_path/brew" <<'EOF'
#!/bin/sh
: >"$INSTALL_MARKER"
EOF
cat >"$launcher_red_path/nmemory" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$launcher_red_path/brew" "$launcher_red_path/nmemory"
install_marker=$scratch/install-marker
INSTALL_MARKER="$install_marker" PATH="$launcher_red_path" "$copy/bin/nmemory-mcp"
[[ -f "$install_marker" ]] || die 'install-capable launcher fixture did not execute its installer'
if bash "$copy/tests/mcp-launchers-test.sh" "$copy" >/dev/null 2>&1; then
  die 'launcher tests accepted an install-capable launcher mutation'
fi
cp "$root/bin/nmemory-mcp" "$copy/bin/nmemory-mcp"
chmod 0755 "$copy/bin/nmemory-mcp"

cp "$copy/tests/mcp-launchers-test.sh" "$scratch/mcp-launchers-test.original"
awk '
  $0 == "exec \"$resolved\" \"$@\"" {
    print "\"$resolved\" \"$@\" || true"
    print "exit 0"
    next
  }
  { print }
' "$copy/bin/nbrowser-mcp" >"$copy/bin/nbrowser-mcp.red"
mv "$copy/bin/nbrowser-mcp.red" "$copy/bin/nbrowser-mcp"
chmod 0755 "$copy/bin/nbrowser-mcp"
nbrowser_red_sha256=$(sha256_file "$copy/bin/nbrowser-mcp")
sed "s/^expected_nbrowser_sha256=.*/expected_nbrowser_sha256=$nbrowser_red_sha256/" \
  "$scratch/mcp-launchers-test.original" >"$copy/tests/mcp-launchers-test.sh"
set +e
nbrowser_status_output=$(bash "$copy/tests/mcp-launchers-test.sh" "$copy" 2>&1)
nbrowser_status=$?
set -e
[[ "$nbrowser_status" -ne 0 && "$nbrowser_status_output" == *'nbrowser child exit status was not propagated'* ]] || \
  die 'launcher behavior tests accepted an nBrowser mutation that swallowed child status after a matching digest update'
cp "$root/bin/nbrowser-mcp" "$copy/bin/nbrowser-mcp"
chmod 0755 "$copy/bin/nbrowser-mcp"
cp "$scratch/mcp-launchers-test.original" "$copy/tests/mcp-launchers-test.sh"

printf '%s\n' "/no"'tt/private' >"$copy/red-path.txt"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a private host path'
fi
rm -f "$copy/red-path.txt"
printf '/%s%s\n' no tt >"$copy/red-path.txt"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted the exact private host root'
fi
rm -f "$copy/red-path.txt"
private_home='/ro''ot/company-internal/repo'
printf '%s\n' "$private_home" >"$copy/red-path.txt"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted the private root home'
fi
rm -f "$copy/red-path.txt"

internal='no''tt-dev'
printf '%s\n' "$internal" >"$copy/red-host.txt"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted an internal hostname'
fi
rm -f "$copy/red-host.txt"

operational='T0''ABCDEF12'
printf '%s\n' "$operational" >"$copy/red-id.txt"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted an operational identifier'
fi
rm -f "$copy/red-id.txt"

assert_identifier_content_rejected() {
  local token=$1 label=$2
  printf '%s\n' "$token" >"$copy/red-id.txt"
  if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
    die "hygiene gate accepted $label in content"
  fi
  rm -f "$copy/red-id.txt"
}
assert_identifier_path_rejected() {
  local token=$1 label=$2
  : >"$copy/$token"
  if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
    die "hygiene gate accepted $label in a path"
  fi
  rm -f "$copy/$token"
}

for prefix in A B; do
  printf '%s\n' "${prefix}0ABCDEF12" >"$copy/red-id.txt"
  if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
    die "hygiene gate accepted a Slack $prefix identifier"
  fi
  rm -f "$copy/red-id.txt"
done
enterprise='E123''ABC456'
printf '%s\n' "$enterprise" >"$copy/red-id.txt"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a Slack enterprise identifier'
fi
rm -f "$copy/red-id.txt"
for prefix in A B C D E F G S T U W; do
  operational="${prefix}ABCD"'EFGHI'
  assert_identifier_content_rejected "$operational" "an opaque Slack $prefix identifier"
  assert_identifier_path_rejected "$operational" "an opaque Slack $prefix identifier"
done
for prefix in A B C D E F G S T U W; do
  operational="${prefix}ABCD"'EFGH'"IJKL"'MNOPQ'
  assert_identifier_content_rejected "$operational" "a long opaque Slack $prefix identifier"
  assert_identifier_path_rejected "$operational" "a long opaque Slack $prefix identifier"
done
file_id=F0A12; file_id=${file_id}BCDE
usergroup_id=S0615; usergroup_id=${usergroup_id}G0KT
assert_identifier_content_rejected "$file_id" 'a Slack file identifier'
assert_identifier_path_rejected "$file_id" 'a Slack file identifier'
assert_identifier_content_rejected "$usergroup_id" 'a Slack usergroup identifier'
assert_identifier_path_rejected "$usergroup_id" 'a Slack usergroup identifier'
for public_word in AVAIL ABLE DIREC TORY WARRAN TIES; do
  case "$public_word" in
    AVAIL) public_word=${public_word}ABLE ;;
    DIREC) public_word=${public_word}TORY ;;
    WARRAN) public_word=${public_word}TIES ;;
    ABLE|TORY|TIES) continue ;;
  esac
  assert_identifier_content_rejected "$public_word" 'fixed public vocabulary outside its declared context'
  assert_identifier_path_rejected "$public_word" 'fixed public vocabulary outside its declared context'
done

printf 'public\0payload\n' >"$copy/red-binary"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a binary file'
fi
rm -f "$copy/red-binary"

mkdir -p "$copy/no"'tt-prod'
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a private hostname in a path'
fi
rmdir "$copy/no"'tt-prod'

config_name='.gitleaks.''toml'
printf '[extend]\nuseDefault = true\n' >"$copy/$config_name"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a target Gitleaks config'
fi
rm -f "$copy/$config_name"

ignore_name='.gitleaks''ignore'
: >"$copy/$ignore_name"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a Gitleaks ignore file'
fi
rm -f "$copy/$ignore_name"

cp "$copy/README.md" "$scratch/readme.original"
sed 's/Licensed under AGPL-3.0-only/Licensed under MIT/' "$scratch/readme.original" >"$copy/README.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a README license contradiction'
fi
cp "$scratch/readme.original" "$copy/README.md"

cp "$copy/SECURITY.md" "$scratch/security.original"
grep -vF 'request for a private contact channel' "$scratch/security.original" >"$copy/SECURITY.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a missing private-reporting fallback'
fi
cp "$scratch/security.original" "$copy/SECURITY.md"

cp "$copy/SPEC.md" "$scratch/spec.original"
sed 's/controlled local executables/local executables/' "$scratch/spec.original" >"$copy/SPEC.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted an unqualified MCP proof basis'
fi
cp "$scratch/spec.original" "$copy/SPEC.md"

printf '\nNOTT turns one intent into one witnessed deliverable.\n' >>"$copy/PRD.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a public promise above the observed-verification rung'
fi
cp "$root/PRD.md" "$copy/PRD.md"

printf '\nModel output is a proposal, NEVER authority.\n' >>"$copy/SPEC.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a duplicated model-authority rule'
fi
cp "$scratch/spec.original" "$copy/SPEC.md"

cp "$copy/NOTT.md" "$scratch/nott.original"
printf '\nAn executor MUST NOT certify its own success.\n' >>"$copy/NOTT.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a duplicated session-claim rule'
fi
cp "$scratch/nott.original" "$copy/NOTT.md"

cp "$copy/skills/ratify/SKILL.md" "$scratch/ratify.original"
printf '\nDefine the witness that can prove the result.\n' >>"$copy/skills/ratify/SKILL.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a collapsed witness-and-evidence role'
fi
cp "$scratch/ratify.original" "$copy/skills/ratify/SKILL.md"

printf '\nThe n=1 override MUST win.\n' >>"$copy/NOTT.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a duplicated n=1 override rule'
fi
cp "$scratch/nott.original" "$copy/NOTT.md"

printf '\nAn n=1 preference MUST NOT become a standing rule.\n' >>"$copy/NOTT.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a duplicated calibration-record rule'
fi
cp "$scratch/nott.original" "$copy/NOTT.md"

cp "$copy/decisions.md" "$scratch/decisions.original"
printf '\nAn unavailable capability is NEVER a reason to fabricate success.\n' >>"$copy/decisions.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a duplicated optional-capability rule'
fi
cp "$scratch/decisions.original" "$copy/decisions.md"

printf '\nThe seven failure classes each has one mechanical enforcer and one red-test.\n' >>"$copy/NOTT.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted phantom mechanical enforcers'
fi
cp "$scratch/nott.original" "$copy/NOTT.md"

printf '\nDirection drift: derived docs are regenerate-and-diff linted.\n' >>"$copy/NOTT.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted a generated-view policy projected onto all derived documents'
fi
cp "$scratch/nott.original" "$copy/NOTT.md"

sed "s/, \`SPEC.md\`, and \`NOTT.md\`/, and \`NOTT.md\`/" "$copy/NOTT.md" >"$copy/NOTT.md.authority-red"
mv "$copy/NOTT.md.authority-red" "$copy/NOTT.md"
if bash "$copy/tests/docs-test.sh" "$copy" >/dev/null 2>&1; then
  die 'documentation gate accepted an incomplete derived authority order'
fi
cp "$scratch/nott.original" "$copy/NOTT.md"

git -C "$copy" -c core.hooksPath=/dev/null add -A
if ! git -C "$copy" diff --cached --quiet; then
  git -C "$copy" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
    -c user.name='nSOUL Red Baseline' -c user.email='nsoul@invalid.example' \
    commit -qm 'exact red-fixture baseline'
fi
copy_baseline=$(git -C "$copy" rev-parse HEAD)

commit_graph_repo=$scratch/commit-graph-history
mkdir -p "$commit_graph_repo"
(cd "$root" && tar --exclude='./.git' -cf - .) | (cd "$commit_graph_repo" && tar -xf -)
git -C "$commit_graph_repo" init -q -b main --object-format=sha1
git -C "$commit_graph_repo" -c core.hooksPath=/dev/null add -A
git -C "$commit_graph_repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
  -c user.name='nSOUL Commit Graph Red' -c user.email='nsoul@invalid.example' \
  commit -qm baseline
graph_base_commit=$(git -C "$commit_graph_repo" rev-parse HEAD)

graph_secret_prefix='AK''IA'
printf 'access_key = "%s%s"\n' "$graph_secret_prefix" '7QWERTYUIOPASDFG' \
  >"$commit_graph_repo/history-secret.txt"
git -C "$commit_graph_repo" -c core.hooksPath=/dev/null add history-secret.txt
git -C "$commit_graph_repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
  -c user.name='nSOUL Commit Graph Red' -c user.email='nsoul@invalid.example' \
  commit -qm secret
graph_secret_commit=$(git -C "$commit_graph_repo" rev-parse HEAD)
git -C "$commit_graph_repo" -c core.hooksPath=/dev/null rm -q history-secret.txt
git -C "$commit_graph_repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
  -c user.name='nSOUL Commit Graph Red' -c user.email='nsoul@invalid.example' \
  commit -qm clean
graph_clean_commit=$(git -C "$commit_graph_repo" rev-parse HEAD)

graph_secret_probe=$scratch/commit-graph-secret-probe
mkdir -p "$graph_secret_probe"
git -C "$commit_graph_repo" -c core.commitGraph=false \
  cat-file blob "$graph_secret_commit:history-secret.txt" >"$graph_secret_probe/secret.txt"
graph_empty_ignore=$scratch/commit-graph-empty-ignore
: >"$graph_empty_ignore"
gitleaks_bin=$(type -P gitleaks) || die 'missing Gitleaks for commit-graph red control'
set +e
graph_secret_report=$(
  (unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
   "$gitleaks_bin" dir --no-banner --redact=100 --ignore-gitleaks-allow \
     --gitleaks-ignore-path "$graph_empty_ignore" -l error --exit-code 23 \
     --report-format json --report-path - "$graph_secret_probe") \
    2>"$scratch/commit-graph-secret.err"
)
graph_secret_status=$?
set -e
[[ "$graph_secret_status" -eq 23 ]] || die 'commit-graph secret fixture did not trigger Gitleaks'
jq -e 'type == "array" and any(.[]; .RuleID == "aws-access-token")' \
  <<<"$graph_secret_report" >/dev/null || die 'commit-graph secret fixture triggered the wrong detector'

git -C "$commit_graph_repo" commit-graph write --reachable
git -C "$commit_graph_repo" config core.commitGraph true
commit_graph_file=$(git -C "$commit_graph_repo" rev-parse --git-path objects/info/commit-graph)
case "$commit_graph_file" in
  /*) ;;
  *) commit_graph_file=$commit_graph_repo/$commit_graph_file ;;
esac
graph_clean_position=$(
  printf '%s\n' "$graph_base_commit" "$graph_secret_commit" "$graph_clean_commit" | \
    LC_ALL=C sort | awk -v wanted="$graph_clean_commit" '$0 == wanted { print NR - 1 }'
)
[[ "$graph_clean_position" =~ ^[0-9]+$ ]] || die 'could not locate clean commit in commit-graph object order'
graph_fields=$(
  LC_ALL=C od -An -v -tu1 "$commit_graph_file" | LC_ALL=C awk '
    { for (field = 1; field <= NF; field++) byte[++count] = $field + 0 }
    END {
      if (byte[1] != 67 || byte[2] != 71 || byte[3] != 80 || byte[4] != 72) exit 2
      if (byte[5] != 1 || byte[6] != 1 || byte[8] != 0) exit 3
      chunks = byte[7]
      for (entry = 0; entry < chunks; entry++) {
        position = 9 + (entry * 12)
        if (byte[position] == 67 && byte[position + 1] == 68 &&
            byte[position + 2] == 65 && byte[position + 3] == 84) {
          offset = 0
          for (octet = 4; octet < 12; octet++) offset = (offset * 256) + byte[position + octet]
          print byte[6], chunks, offset
          found = 1
          break
        }
      }
      if (!found) exit 4
    }
  '
)
read -r graph_hash_version graph_chunk_count graph_cdat_offset <<<"$graph_fields"
[[ "$graph_hash_version" == 1 && "$graph_chunk_count" =~ ^[1-9][0-9]*$ && "$graph_cdat_offset" =~ ^[0-9]+$ ]] || \
  die 'commit-graph fixture has an invalid SHA-1 chunk table'
graph_hash_bytes=20
graph_record_bytes=36
graph_parent_offset=$((graph_cdat_offset + graph_clean_position * graph_record_bytes + graph_hash_bytes))
graph_total_bytes=$(wc -c <"$commit_graph_file")
graph_body_bytes=$((graph_total_bytes - graph_hash_bytes))
(( graph_parent_offset + 4 <= graph_body_bytes )) || die 'commit-graph parent offset is outside the checksummed body'
tampered_graph=$scratch/commit-graph.tampered
dd if="$commit_graph_file" of="$tampered_graph" bs=1 count="$graph_body_bytes" 2>/dev/null
printf '\160\000\000\000' | dd of="$tampered_graph" bs=1 seek="$graph_parent_offset" conv=notrunc 2>/dev/null
graph_checksum=$(sha1_file "$tampered_graph")
[[ "$graph_checksum" =~ ^[0-9a-f]{40}$ ]] || die 'could not compute the commit-graph checksum'
append_hex_bytes_to "$graph_checksum" "$tampered_graph"
[[ $(wc -c <"$tampered_graph") -eq "$graph_total_bytes" ]] || die 'tampered commit-graph has the wrong length'
chmod 0444 "$tampered_graph"
mv -f "$tampered_graph" "$commit_graph_file"

graph_raw_parent=$(git -C "$commit_graph_repo" -c core.commitGraph=false cat-file commit "$graph_clean_commit" | sed -n 's/^parent //p')
graph_ordinary_history=$(git -C "$commit_graph_repo" rev-list --all)
graph_raw_history=$(git -C "$commit_graph_repo" -c core.commitGraph=false rev-list --all)
[[ "$graph_raw_parent" == "$graph_secret_commit" ]] || die 'raw clean commit does not retain the secret parent'
[[ "$graph_ordinary_history" == "$graph_clean_commit" ]] || die 'tampered commit-graph did not hide the parent'
grep -qxF "$graph_secret_commit" <<<"$graph_raw_history" || die 'raw history traversal did not recover the hidden secret commit'
git -C "$commit_graph_repo" -c core.commitGraph=false cat-file -e "$graph_secret_commit^{commit}" || die 'hidden secret commit is unavailable as a raw object'
set +e
git -C "$commit_graph_repo" commit-graph verify >"$scratch/commit-graph-verify.out" 2>&1
graph_verify_status=$?
set -e
[[ "$graph_verify_status" -ne 0 ]] || die 'semantically forged commit-graph unexpectedly verified'
set +e
graph_history_output=$(bash "$commit_graph_repo/tools/history-hygiene.sh" \
  "$commit_graph_repo" "$gitleaks_bin" "$graph_empty_ignore" 2>&1)
graph_history_status=$?
set -e
if [[ "$graph_history_status" -eq 0 || "$graph_history_output" != *'a historical tree contains a secret'* ]]; then
  die "history hygiene accepted a secret hidden by a commit-graph parent (status=$graph_history_status; output=$graph_history_output)"
fi

ambient_repo=$scratch/ambient-git
mkdir -p "$ambient_repo"
git -C "$ambient_repo" init -q
printf 'public\n' >"$ambient_repo/README.md"
git -C "$ambient_repo" -c core.hooksPath=/dev/null add README.md
git -C "$ambient_repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name='nSOUL Red Test' -c user.email='nsoul@invalid.example' commit -qm base
alternate_selector=GIT_ALT
alternate_selector=${alternate_selector}ERNATE_OBJECT_DIRE
alternate_selector=${alternate_selector}CTORIES
git_selector_bindings=(
  "GIT_DIR=$ambient_repo/.git"
  "GIT_WORK_TREE=$copy"
  "GIT_COMMON_DIR=$ambient_repo/.git"
  "GIT_OBJECT_DIRECTORY=$ambient_repo/.git/objects"
  "$alternate_selector=$ambient_repo/.git/objects"
  "GIT_INDEX_FILE=$ambient_repo/.git/index"
  'GIT_NAMESPACE=adversarial'
  'GIT_REPLACE_REF_BASE=refs/adversarial-replacements'
  "GIT_GRAFT_FILE=$scratch/adversarial-grafts"
  "GIT_SHALLOW_FILE=$scratch/adversarial-shallow"
  'GIT_CONFIG_COUNT=1'
  'GIT_CONFIG_PARAMETERS=adversarial'
  "GIT_CONFIG_GLOBAL=$scratch/adversarial-config"
)
for binding in "${git_selector_bindings[@]}"; do
  selector=${binding%%=*}
  set +e
  selector_output=$(
    export "${binding?}"
    bash "$copy/tools/history-hygiene.sh" "$copy" 2>&1
  )
  selector_status=$?
  set -e
  [[ "$selector_status" -ne 0 && "$selector_output" == *"ambient Git selector is set: $selector"* ]] || die "history hygiene accepted ambient selector $selector"
done

graft_base=$(git -C "$copy" rev-parse HEAD)
printf '%s\n' "/no"'tt/private' >"$copy/red-history.txt"
printf '%s\n' 'red-history.txt export-ignore' >"$copy/.gitattributes"
git -C "$copy" -c core.hooksPath=/dev/null add red-history.txt .gitattributes
git -C "$copy" -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name='nSOUL Red Test' -c user.email='nsoul@invalid.example' commit -qm 'red history add'
red_history_commit=$(git -C "$copy" rev-parse HEAD)
git -C "$copy" -c core.hooksPath=/dev/null rm -q red-history.txt .gitattributes
git -C "$copy" -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name='nSOUL Red Test' -c user.email='nsoul@invalid.example' commit -qm 'red history remove'
if bash "$copy/tools/history-hygiene.sh" "$copy" >/dev/null 2>&1; then
  die 'history hygiene accepted private context hidden by export attributes'
fi
git -C "$copy" replace "$red_history_commit" HEAD
set +e
replace_output=$(bash "$copy/tools/history-hygiene.sh" "$copy" 2>&1)
replace_status=$?
set -e
[[ "$replace_status" -ne 0 && "$replace_output" == *'repository contains replacement refs'* ]] || die 'history hygiene did not reject a replacement ref directly'
git -C "$copy" replace -d "$red_history_commit" >/dev/null
custom_replace_base=refs/nsoul-custom-replacements
env GIT_REPLACE_REF_BASE="$custom_replace_base" git -C "$copy" replace "$red_history_commit" HEAD
if env GIT_REPLACE_REF_BASE="$custom_replace_base" bash "$copy/tools/history-hygiene.sh" "$copy" >/dev/null 2>&1; then
  die 'history hygiene resolved a custom replacement namespace'
fi
env GIT_REPLACE_REF_BASE="$custom_replace_base" git -C "$copy" replace -d "$red_history_commit" >/dev/null
graft_file=$(git -C "$copy" rev-parse --absolute-git-dir)/info/grafts
printf '%s %s\n' "$(git -C "$copy" rev-parse HEAD)" "$graft_base" >"$graft_file"
set +e
graft_output=$(bash "$copy/tools/history-hygiene.sh" "$copy" 2>&1)
graft_status=$?
set -e
[[ "$graft_status" -ne 0 && "$graft_output" == *'repository uses a legacy graft file'* ]] || die 'history hygiene did not reject a legacy graft directly'
rm -f "$graft_file"
alternate_file=$(git -C "$copy" rev-parse --absolute-git-dir)/objects/info/alternates
printf '%s\n' "$ambient_repo/.git/objects" >"$alternate_file"
set +e
alternate_output=$(bash "$copy/tools/history-hygiene.sh" "$copy" 2>&1)
alternate_status=$?
set -e
[[ "$alternate_status" -ne 0 && "$alternate_output" == *'repository uses an object alternate'* ]] || die 'history hygiene did not reject an on-disk object alternate directly'
rm -f "$alternate_file"

git -C "$copy" -c core.hooksPath=/dev/null reset --hard -q "$copy_baseline"
bash "$copy/tools/history-hygiene.sh" "$copy" >/dev/null || die 'structural-history baseline is not green'
info_attributes=$(git -C "$copy" rev-parse --git-path info/attributes)
case "$info_attributes" in
  /*) ;;
  *) info_attributes=$copy/$info_attributes ;;
esac
mkdir -p "${info_attributes%/*}"
: >"$info_attributes"
set +e
attributes_output=$(bash "$copy/tools/history-hygiene.sh" "$copy" 2>&1)
attributes_status=$?
set -e
[[ "$attributes_status" -ne 0 && "$attributes_output" == *'repository uses an info attributes file'* ]] || die 'history hygiene did not reject Git info attributes directly'
rm -f "$info_attributes"

ref_blob=$(printf 'public tag payload\n' | git -C "$copy" hash-object -w --stdin)
git -C "$copy" update-ref refs/tags/nsoul-red-blob "$ref_blob"
set +e
ref_output=$(bash "$copy/tools/history-hygiene.sh" "$copy" 2>&1)
ref_status=$?
set -e
git -C "$copy" update-ref -d refs/tags/nsoul-red-blob
[[ "$ref_status" -ne 0 && "$ref_output" == *'repository contains a logical ref that does not peel to a commit'* ]] || die 'history hygiene accepted a logical ref that does not peel to a commit'

raw_tree=
git_bad() {
  git -C "$copy" "$@"
}
start_structural_red() {
  raw_tree=$scratch/tree-$1.raw
  : >"$raw_tree"
}
append_oid_bytes() {
  local oid=$1
  [[ "$oid" =~ ^[0-9a-f]+$ && $((${#oid} % 2)) -eq 0 ]] || die 'red fixture received an invalid object id'
  while [[ -n "$oid" ]]; do
    printf '%b' "\\x${oid:0:2}" >>"$raw_tree"
    oid=${oid:2}
  done
}
append_tree_entry() {
  local mode=$1 path=$2 oid=$3
  printf '%s %s\0' "$mode" "$path" >>"$raw_tree"
  append_oid_bytes "$oid"
}
assert_structural_history_rejected() {
  local label=$1 tree commit status ref=refs/heads/nsoul-red-structure
  tree=$(git_bad hash-object -w -t tree --literally "$raw_tree")
  commit=$(printf 'red structural history\n' | \
    GIT_AUTHOR_NAME='nSOUL Red Test' GIT_AUTHOR_EMAIL='nsoul@invalid.example' \
    GIT_COMMITTER_NAME='nSOUL Red Test' GIT_COMMITTER_EMAIL='nsoul@invalid.example' \
    git_bad -c commit.gpgsign=false commit-tree "$tree" -p HEAD)
  git_bad update-ref "$ref" "$commit"
  set +e
  bash "$copy/tools/history-hygiene.sh" "$copy" >/dev/null 2>&1
  status=$?
  set -e
  git_bad update-ref -d "$ref"
  [[ "$status" -ne 0 ]] || die "history hygiene accepted $label"
}

start_structural_red duplicate-path
private_blob=$(printf '%s\n' "/no"'tt/private' | git_bad hash-object -w --stdin)
public_blob=$(printf 'public\n' | git_bad hash-object -w --stdin)
append_tree_entry 100644 red-duplicate "$private_blob"
append_tree_entry 100644 red-duplicate "$public_blob"
assert_structural_history_rejected 'duplicate materialization paths'

start_structural_red reserved-dotgit
public_blob=$(printf 'public\n' | git_bad hash-object -w --stdin)
append_tree_entry 100644 .git "$public_blob"
assert_structural_history_rejected 'a reserved .git path'

start_structural_red reserved-dotgit-case
public_blob=$(printf 'public\n' | git_bad hash-object -w --stdin)
append_tree_entry 100644 .GiT "$public_blob"
assert_structural_history_rejected 'a case-variant reserved .git path'

start_structural_red case-collision
public_blob=$(printf 'public\n' | git_bad hash-object -w --stdin)
append_tree_entry 100644 README "$public_blob"
append_tree_entry 100644 Readme "$public_blob"
assert_structural_history_rejected 'case-colliding materialization paths'

start_structural_red noncanonical-order
public_blob=$(printf 'public\n' | git_bad hash-object -w --stdin)
append_tree_entry 100644 z-last "$public_blob"
append_tree_entry 100644 a-first "$public_blob"
assert_structural_history_rejected 'non-canonical raw entry order'

start_structural_red invalid-mode
public_blob=$(printf 'public\n' | git_bad hash-object -w --stdin)
append_tree_entry 100600 red-mode "$public_blob"
assert_structural_history_rejected 'a non-canonical raw file mode'

start_structural_red control-character
public_blob=$(printf 'public\n' | git_bad hash-object -w --stdin)
printf '100644 red\001path\0' >>"$raw_tree"
append_oid_bytes "$public_blob"
assert_structural_history_rejected 'a non-printable raw path component'

shallow_file=$(git -C "$copy" rev-parse --absolute-git-dir)/shallow
git -C "$copy" rev-parse HEAD >"$shallow_file"
if bash "$copy/tools/history-hygiene.sh" "$copy" >/dev/null 2>&1; then
  die 'history hygiene accepted a shallow repository'
fi
rm -f "$shallow_file"

ln -s README.md "$copy/red-link"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a symlink'
fi
rm -f "$copy/red-link"

cp "$copy/release/inventory.tsv" "$scratch/inventory.original"
cat >"$copy/bin/nmemory" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$copy/bin/nmemory"
printf 'bin/nmemory\trelease-support\t-\t100755\n' >>"$copy/release/inventory.tsv"
if bash "$copy/tests/manifest-test.sh" "$copy" >/dev/null 2>&1; then
  die 'manifest gate accepted a bundled MCP server executable'
fi
rm -f "$copy/bin/nmemory"
cp "$scratch/inventory.original" "$copy/release/inventory.tsv"

cp "$copy/wiki.md" "$scratch/wiki.original"
cat >"$copy/bin/nmemory" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$copy/bin/nmemory"
awk -F '\t' 'BEGIN { OFS="\t" }
  $1 == "wiki.md" { print "bin/nmemory", "core-scrubbed", "plugin/bin/nmemory", "100755"; next }
  { print }
' "$scratch/inventory.original" >"$copy/release/inventory.tsv"
rm -f "$copy/wiki.md"
if bash "$copy/tests/manifest-test.sh" "$copy" >/dev/null 2>&1; then
  die 'manifest gate accepted a bundled MCP server reclassified as core'
fi
rm -f "$copy/bin/nmemory"
cp "$scratch/wiki.original" "$copy/wiki.md"
cp "$scratch/inventory.original" "$copy/release/inventory.tsv"

cp "$copy/release/public-contract.json" "$scratch/contract.original"
cp "$copy/.claude-plugin/plugin.json" "$scratch/claude-plugin.original"
cp "$copy/.codex-plugin/plugin.json" "$scratch/codex-plugin.original"
cp "$copy/.agents/plugins/marketplace.json" "$scratch/codex-market.original"

jq '.distribution.authorityDecision = "d25-public-distribution"' "$scratch/contract.original" >"$copy/release/public-contract.json"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted an unresolved authority-decision prefix'
fi
cp "$scratch/contract.original" "$copy/release/public-contract.json"

jq '.distribution.license = "MIT"' "$scratch/contract.original" >"$copy/release/public-contract.json"
jq '.license = "MIT"' "$scratch/claude-plugin.original" >"$copy/.claude-plugin/plugin.json"
jq '.license = "MIT"' "$scratch/codex-plugin.original" >"$copy/.codex-plugin/plugin.json"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted license metadata that contradicts the legal files'
fi
cp "$scratch/contract.original" "$copy/release/public-contract.json"
cp "$scratch/claude-plugin.original" "$copy/.claude-plugin/plugin.json"
cp "$scratch/codex-plugin.original" "$copy/.codex-plugin/plugin.json"

for identity_filter in \
  '.interface.developerName = "Other Corp"' \
  '.interface.websiteURL = "https://example.invalid"' \
  '.author.url = "https://example.invalid"' \
  '.homepage = "https://example.invalid"'; do
  jq "$identity_filter" "$scratch/codex-plugin.original" >"$copy/.codex-plugin/plugin.json"
  if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
    die 'hygiene gate accepted an inconsistent Codex identity projection'
  fi
done
cp "$scratch/codex-plugin.original" "$copy/.codex-plugin/plugin.json"
jq '.homepage = "https://example.invalid"' "$scratch/claude-plugin.original" >"$copy/.claude-plugin/plugin.json"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted an inconsistent Claude identity projection'
fi
cp "$scratch/claude-plugin.original" "$copy/.claude-plugin/plugin.json"

cp "$copy/NOTICE" "$scratch/notice.original"
sed 's/under AGPL-3.0-only/under MIT/' "$scratch/notice.original" >"$copy/NOTICE"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a notice that contradicts the release license'
fi
cp "$scratch/notice.original" "$copy/NOTICE"

jq '.distribution.displayName = "Other"' "$scratch/contract.original" >"$copy/release/public-contract.json"
jq '.interface.displayName = "Other"' "$scratch/codex-plugin.original" >"$copy/.codex-plugin/plugin.json"
jq '.interface.displayName = "Other"' "$scratch/codex-market.original" >"$copy/.agents/plugins/marketplace.json"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted a self-consistent unratified distribution identity'
fi
cp "$scratch/contract.original" "$copy/release/public-contract.json"
cp "$scratch/codex-plugin.original" "$copy/.codex-plugin/plugin.json"
cp "$scratch/codex-market.original" "$copy/.agents/plugins/marketplace.json"

jq '.name = "wrong-market"' "$copy/.claude-plugin/marketplace.json" >"$copy/.claude-plugin/marketplace.tmp"
mv "$copy/.claude-plugin/marketplace.tmp" "$copy/.claude-plugin/marketplace.json"
if bash "$copy/tools/hygiene-lint.sh" "$copy" >/dev/null 2>&1; then
  die 'hygiene gate accepted inconsistent public identity'
fi

printf 'gates-red-test: pass\n'
