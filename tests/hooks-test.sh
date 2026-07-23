#!/usr/bin/env bash
set -euo pipefail

die() { printf 'hooks-test: %s\n' "$*" >&2; exit 1; }
root=${1:-$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd -P)}
hook=$root/hooks/nott-hook.sh
[[ -x "$hook" ]] || die 'hook is not executable'
for command_name in awk dd grep jq mktemp od stat wc; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    die 'missing SHA-256 utility'
  fi
}
expected_hook_sha256=56242eb4bd2426fafa1e923b41923d0fa0afef79d192cb50d0a7176a45c035ac
[[ $(hash_file "$hook") == "$expected_hook_sha256" ]] || die 'hook bytes differ from the reviewed privacy candidate'

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM
marker=NSOUL_MARKER_7F3A91
session=SESSION_MARKER_4C20
transcript=$scratch/transcript.jsonl
jq -cn --arg text "$marker Amazing? Or prefer another path?" \
  '{type:"assistant",message:{content:[{type:"text",text:$text}]}}' >"$transcript"
payload=$(jq -cn --arg path "$transcript" --arg session "$session" \
  '{transcript_path:$path,session_id:$session,stop_hook_active:false}')

default_state=$scratch/default-state
output=$(HOME="$scratch/home" XDG_STATE_HOME="$default_state" NOTT_VOICE_LINT=off "$hook" Stop <<<"$payload")
[[ -z "$output" && ! -e "$default_state" ]] || die 'default Stop wrote state or emitted output'

warn_state=$scratch/warn-state
output=$(HOME="$scratch/home" XDG_STATE_HOME="$warn_state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=warn "$hook" Stop <<<"$payload")
[[ -z "$output" ]] || die 'warn mode emitted a block'
log=$warn_state/nott/voice-lint.jsonl
[[ -f "$log" ]] || die 'warn mode did not write diagnostic state'
jq -e 'keys | sort == ["findings", "mode", "ts"]' "$log" >/dev/null || die 'voice state contains an unexpected field'
if grep -R -F "$marker" "$warn_state" >/dev/null || grep -R -F "$session" "$warn_state" >/dev/null; then
  die 'voice state persisted transcript text or session identity'
fi

mode_of() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}
[[ $(mode_of "$warn_state/nott") == 700 ]] || die 'voice state directory is not private'
[[ $(mode_of "$log") == 600 ]] || die 'voice state file is not private'

block_state=$scratch/block-state
output=$(HOME="$scratch/home" XDG_STATE_HOME="$block_state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=block "$hook" Stop <<<"$payload")
[[ $(printf '%s\n' "$output" | wc -l) -eq 1 ]] || die 'block mode emitted more than one line'
printf '%s\n' "$output" | jq -e '.decision == "block" and (.reason | type == "string")' >/dev/null || die 'block mode did not emit one valid decision'
if grep -R -F "$marker" "$block_state" >/dev/null || grep -R -F "$session" "$block_state" >/dev/null; then
  die 'block mode persisted transcript text or session identity'
fi

active_payload=$(jq -cn --arg path "$transcript" '{transcript_path:$path,stop_hook_active:true}')
output=$(HOME="$scratch/home" XDG_STATE_HOME="$scratch/active-state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=block "$hook" Stop <<<"$active_payload")
[[ -z "$output" ]] || die 'recursive Stop emitted another block'

active_error_payload=$(jq -cn --arg path "$scratch/missing-transcript" '{transcript_path:$path,stop_hook_active:true}')
output=$(HOME="$scratch/home" XDG_STATE_HOME="$scratch/active-error-state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=invalid "$hook" Stop <<<"$active_error_payload")
[[ -z "$output" && ! -e "$scratch/active-error-state" ]] || die 'recursive Stop emitted an error block or wrote state'

mkdir -p "$scratch/active-path"
ln -s "$(command -v head)" "$scratch/active-path/head"
ln -s "$(command -v awk)" "$scratch/active-path/awk"
ln -s "$(command -v od)" "$scratch/active-path/od"
spaced_active_payload=$(printf '{ "transcript_path" : "%s", "stop_hook_active" : true }' "$scratch/missing-transcript")
output=$(PATH="$scratch/active-path" HOME="$scratch/home" XDG_STATE_HOME="$scratch/active-dependency-state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$spaced_active_payload")
[[ -z "$output" && ! -e "$scratch/active-dependency-state" ]] || die 'recursive Stop blocked again when a dependency was unavailable'
top_active_payload=$(printf '{"metadata":{"stop_hook_active":false},"transcript_path":"%s","stop_hook_active":true}' "$scratch/missing-transcript")
output=$(PATH="$scratch/active-path" HOME="$scratch/home" XDG_STATE_HOME="$scratch/active-dependency-state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$top_active_payload")
[[ -z "$output" ]] || die 'top-level recursive Stop was shadowed by a nested value'
unicode_active_payload=$(printf '{"\\u0073top\\u005fhook\\u005factive":true,"transcript_path":"%s"}' "$scratch/missing-transcript")
output=$(PATH="$scratch/active-path" HOME="$scratch/home" XDG_STATE_HOME="$scratch/active-dependency-state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$unicode_active_payload")
[[ -z "$output" ]] || die 'Unicode-escaped recursive Stop emitted another block'
duplicate_index=0
for duplicate_active_payload in \
  '{"stop_hook_active":true,"stop_hook_active":false}' \
  '{"stop_hook_active":false,"stop_hook_active":true}'; do
  for detector_path in "$PATH" "$scratch/active-path"; do
    duplicate_index=$((duplicate_index + 1))
    duplicate_state=$scratch/duplicate-active-state-$duplicate_index
    output=$(PATH="$detector_path" HOME="$scratch/home" XDG_STATE_HOME="$duplicate_state" \
      NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=invalid "$hook" Stop <<<"$duplicate_active_payload")
    [[ -z "$output" && ! -e "$duplicate_state" ]] || \
      die 'ambiguous duplicate recursive Stop emitted a block or wrote state'
  done
done
nonactive_payload=$(printf '{ "transcript_path" : "%s", "stop_hook_active" : false }' "$scratch/missing-transcript")
output=$(PATH="$scratch/active-path" HOME="$scratch/home" XDG_STATE_HOME="$scratch/active-dependency-state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$nonactive_payload")
printf '%s\n' "$output" | jq -e '.decision == "block"' >/dev/null || die 'missing jq did not fail closed for a non-recursive Stop'
nested_active_payload=$(printf '{"metadata":{"stop_hook_active":true},"transcript_path":"%s","stop_hook_active":false}' "$scratch/missing-transcript")
output=$(PATH="$scratch/active-path" HOME="$scratch/home" XDG_STATE_HOME="$scratch/active-dependency-state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$nested_active_payload")
printf '%s\n' "$output" | jq -e '.decision == "block"' >/dev/null || die 'nested recursive flag bypassed a top-level false value'
malformed_active_payload='{"stop_hook_active":true "metadata":{"source":"red"}}'
output=$(PATH="$scratch/active-path" HOME="$scratch/home" XDG_STATE_HOME="$scratch/active-dependency-state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$malformed_active_payload")
printf '%s\n' "$output" | jq -e '.decision == "block"' >/dev/null || die 'malformed JSON bypassed recursive Stop validation'

invalid_state=$scratch/invalid-state
output=$(HOME="$scratch/home" XDG_STATE_HOME="$invalid_state" NOTT_VOICE_LINT=on "$hook" Stop <<<'not-json')
printf '%s\n' "$output" | jq -e '.decision == "block"' >/dev/null || die 'enabled voice lint did not reject invalid JSON'
[[ ! -e "$invalid_state" ]] || die 'invalid payload created state'

ln -s "$transcript" "$scratch/transcript-link"
symlink_payload=$(jq -cn --arg path "$scratch/transcript-link" '{transcript_path:$path,stop_hook_active:false}')
output=$(HOME="$scratch/home" XDG_STATE_HOME="$scratch/link-state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$symlink_payload")
printf '%s\n' "$output" | jq -e '.decision == "block"' >/dev/null || die 'symlinked transcript was not rejected'
[[ ! -e "$scratch/link-state" ]] || die 'symlinked transcript created state'

printf -v oversized '%*s' 1048577 ''
output=$(HOME="$scratch/home" XDG_STATE_HOME="$scratch/oversized-state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$oversized")
[[ -z "$output" && ! -e "$scratch/oversized-state" ]] || die 'oversized Stop did not fail open without state'
oversized_active='{"stop_hook_active":true,"padding":"'
oversized_active=$oversized_active$oversized'"}'
output=$(HOME="$scratch/home" XDG_STATE_HOME="$scratch/oversized-active-state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=block "$hook" Stop <<<"$oversized_active")
[[ -z "$output" && ! -e "$scratch/oversized-active-state" ]] || die 'oversized recursive Stop emitted another block or wrote state'
unset oversized
unset oversized_active

newline_oversized_input=$scratch/newline-oversized-input
awk 'BEGIN {
  for (index_ = 0; index_ < 1048577; index_++) printf "\n"
  print "{\"stop_hook_active\":true}"
}' >"$newline_oversized_input"
output=$(HOME="$scratch/home" XDG_STATE_HOME="$scratch/newline-oversized-state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=block "$hook" Stop <"$newline_oversized_input")
[[ -z "$output" && ! -e "$scratch/newline-oversized-state" ]] || die 'newline-terminated oversized recursive Stop emitted another block or wrote state'

nul_oversized_input=$scratch/nul-oversized-input
dd if=/dev/zero of="$nul_oversized_input" bs=1048577 count=1 2>/dev/null
printf '{"stop_hook_active":true}\n' >>"$nul_oversized_input"
output=$(HOME="$scratch/home" XDG_STATE_HOME="$scratch/nul-oversized-state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=block "$hook" Stop <"$nul_oversized_input")
[[ -z "$output" && ! -e "$scratch/nul-oversized-state" ]] || die 'NUL-bearing oversized recursive Stop emitted another block or wrote state'

unsafe_state=$scratch/unsafe-state
mkdir -p "$unsafe_state/nott"
printf 'do-not-replace\n' >"$scratch/symlink-target"
ln -s "$scratch/symlink-target" "$unsafe_state/nott/voice-lint.jsonl"
output=$(HOME="$scratch/home" XDG_STATE_HOME="$unsafe_state" NOTT_VOICE_LINT=on "$hook" Stop <<<"$payload")
printf '%s\n' "$output" | jq -e '.decision == "block"' >/dev/null || die 'symlinked state file was not rejected'
[[ $(cat "$scratch/symlink-target") == do-not-replace ]] || die 'symlinked state target was changed'

legacy_state=$scratch/legacy-state
mkdir -p "$legacy_state/nott"
cat >"$legacy_state/nott/voice-lint.jsonl" <<EOF
{"ts":"2025-01-01T00:00:00Z","mode":"warn","findings":"menu-pattern"}
{"ts":"2025-01-01T00:00:01Z","mode":"warn","findings":"menu-pattern","session_id":"$session","evidence":"$marker"}
not-json-$marker
EOF
HOME="$scratch/home" XDG_STATE_HOME="$legacy_state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=warn "$hook" Stop <<<"$payload" >/dev/null
legacy_log=$legacy_state/nott/voice-lint.jsonl
[[ $(wc -l <"$legacy_log") -eq 2 ]] || die 'legacy voice state was not normalized before append'
jq -se 'length == 2 and all(.[]; keys | sort == ["findings", "mode", "ts"])' "$legacy_log" >/dev/null || die 'legacy voice state retained an unsafe schema'
if grep -R -F "$marker" "$legacy_state" >/dev/null || grep -R -F "$session" "$legacy_state" >/dev/null; then
  die 'legacy voice state retained transcript text or session identity'
fi

retention_state=$scratch/retention-state
for ((iteration=0; iteration<205; iteration++)); do
  HOME="$scratch/home" XDG_STATE_HOME="$retention_state" NOTT_VOICE_LINT=on NOTT_VOICE_LINT_MODE=warn "$hook" Stop <<<"$payload" >/dev/null
done
retention_log=$retention_state/nott/voice-lint.jsonl
[[ $(wc -l <"$retention_log") -eq 200 ]] || die 'voice state retention is not bounded to 200 records'
jq -se 'length == 200 and all(.[]; keys | sort == ["findings", "mode", "ts"])' "$retention_log" >/dev/null || die 'retained voice state contains unexpected data'
if grep -R -F "$marker" "$retention_state" >/dev/null || grep -R -F "$session" "$retention_state" >/dev/null; then
  die 'retention state persisted transcript text or session identity'
fi

for event in SubagentStart UserPromptSubmit PostToolUse PreToolUse; do
  output=$(CLAUDE_PLUGIN_ROOT="$root" "$hook" "$event" <<<'{}')
  printf '%s\n' "$output" | jq -e --arg event "$event" '.hookSpecificOutput.hookEventName == $event' >/dev/null || die "$event contract is invalid"
done
output=$(CLAUDE_PLUGIN_ROOT="$root" "$hook" SubagentStart <<<'{}')
printf '%s\n' "$output" | jq -e --arg canon "$root/NOTT.md" '
  .hookSpecificOutput.additionalContext
  | contains("one proof-bound deliverable") and contains("Full canon: " + $canon)
' >/dev/null || die 'subagent context does not carry the canon orientation and exact read path'
output=$(CLAUDE_PLUGIN_ROOT="$root" "$hook" UserPromptSubmit <<<'{}')
printf '%s\n' "$output" | jq -e --arg canon "$root/NOTT.md" '
  .hookSpecificOutput.additionalContext
  | contains("one proof-bound deliverable") and contains("Full canon: " + $canon)
' >/dev/null || die 'root-session context does not carry the canon orientation and exact read path'

set +e
CLAUDE_PLUGIN_ROOT="$root" "$hook" Unsupported <<<'{}' >"$scratch/unsupported.out" 2>"$scratch/unsupported.err"
status=$?
set -e
[[ "$status" -eq 2 && ! -s "$scratch/unsupported.out" && $(wc -l <"$scratch/unsupported.err") -eq 1 ]] || die 'unsupported event did not fail with one diagnostic'

[[ $(grep -c 'auto[_-]handoff\|last-autohandoff' "$hook" || true) -eq 0 ]] || die 'public hook still implements automatic handoff state'
printf 'hooks-test: pass\n'
