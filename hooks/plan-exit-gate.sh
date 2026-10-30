#!/usr/bin/env -S bash -p
# The ExitPlanMode gate. /nott:plan has one write path: the plan-write recipe
# (plugin/skills/plan/references/write.md), which runs after plan mode ends. A text
# given at ExitPlanMode is a method note, not a plan, so a text that carries a plan's
# sections is denied with that fix. The floor judge runs in the recipe's Plan step.
set -uo pipefail

deny() {
  printf '%s\n' "$1" >&2
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 2
}

recipe=plugin/skills/plan/references/write.md

payload=$(cat)
# The scan reads the lines that plugin/scripts/floor.py reads: every line boundary
# that str.splitlines() honors (CRLF, CR, VT, FF, FS, GS, RS, NEL, U+2028, U+2029)
# becomes one LF first.
note=$(printf '%s' "$payload" | jq -r '.tool_input.plan // empty
  | if type == "string" then gsub("\r\n|[\r\u000b\u000c\u001c\u001d\u001e\u0085\u2028\u2029]"; "\n") else . end' 2>/dev/null) \
  || deny "plan-exit-gate: REFUSED — the hook payload did not parse as JSON (jq missing, or invalid input)"
[ -n "$note" ] \
  || deny "plan-exit-gate: REFUSED — the ExitPlanMode payload carries no tool_input.plan; write the method note before ExitPlanMode"

# A plan's own sections, as plugin/scripts/floor.py finds them: an ATX heading
# (indented at most three spaces) or a setext heading whose text opens with the
# word Readback, Assessment or Invariants, after optional markup.
printf '%s\n' "$note" | awk '
  BEGIN { found = 0 }
  { line = tolower($0) }
  line ~ /^ ? ? ?#+[ \t]+[*_`[]*(readback|assessment|invariants)([^a-z0-9_]|$)/ { found = 1 }
  NR > 1 && line ~ /^ ? ? ?(=+|-+)[ \t]*$/ && previous ~ /^ ? ? ?[*_`[]*(readback|assessment|invariants)([^a-z0-9_]|$)/ { found = 1 }
  { previous = line }
  END { exit found ? 0 : 1 }'
scan=$?
# Three outcomes, never two: awk 0 is a section found, 1 is none found, and any
# other exit is a scan that failed, which never reads as "no section found".
case $scan in
  0)
    deny "plan-exit-gate: REFUSED — this text is a plan, and plan mode does not write a plan. /nott:plan writes a plan only through the plan-write recipe ($recipe), after plan mode ends. Remove the Readback, Assessment and Invariants sections and give a method note: the result, the next act and, when the work needs a plan, the recipe as that act. Then call ExitPlanMode again."
    ;;
  1) ;;
  *)
    deny "plan-exit-gate: REFUSED — the plan-section scan failed (awk exit $scan), so the gate cannot tell a method note from a plan; restore a working awk on PATH, then call ExitPlanMode again"
    ;;
esac

# Context only: a permission decision here would take the owner's own choice to
# leave plan mode from him.
allowed="This text is a method note, not a plan. When the work needs a plan, the next act after plan mode ends is the plan-write recipe ($recipe). Planning alone does not authorize implementation the request did not cover; when the request covered it and the work needs no plan, continue into execution without asking again."
jq -cn --arg c "$allowed" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
exit 0
