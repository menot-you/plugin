#!/usr/bin/env -S bash -p
set -uo pipefail

deny() {
  printf '%s\n' "$1" >&2
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 2
}

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
judge=${NOTT_PLAN_FLOOR:-$plugin_dir/scripts/floor.py}

payload=$(cat)
plan=$(printf '%s' "$payload" | jq -r '.tool_input.plan // empty' 2>/dev/null) \
  || deny "plan-exit-gate: REFUSED — the hook payload did not parse as JSON (jq missing, or invalid input)"
[ -n "$plan" ] \
  || deny "plan-exit-gate: REFUSED — the ExitPlanMode payload carries no tool_input.plan; write the plan before ExitPlanMode"
[ -f "$judge" ] \
  || deny "plan-exit-gate: REFUSED — the judge is missing at $judge; restore plugin/scripts/floor.py"

plan_file=$(umask 077 && mktemp "${TMPDIR:-/tmp}/plan-exit-gate.XXXXXX") \
  || deny "plan-exit-gate: REFUSED — could not create a private scratch file for the plan bytes"
trap 'rm -f "$plan_file"' EXIT
printf '%s\n' "$plan" > "$plan_file" \
  || deny "plan-exit-gate: REFUSED — could not write the plan bytes to $plan_file; an empty file judged green would wave the plan through"

out=$(python3 "$judge" judge --profile principal "$plan_file" 2>&1); rc=$?
# An allowed plan gets one fixed reminder (it was plan-exit-persist.sh). Context only:
# a permission decision here would skip the owner's own approval of the plan.
allowed='If the owner accepts this plan, preserve the agreed full result and its acceptance in the explicit campaign home. Planning alone does not authorize implementation the request did not cover; when it did, continue into execution without asking again.'
[ "$rc" -eq 0 ] && { jq -cn --arg c "$allowed" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'; exit 0; }
deny "plan-exit-gate: the plan does not meet the executor floor (judge exit $rc). Fix every line below in the plan, then call ExitPlanMode again:
$out"
