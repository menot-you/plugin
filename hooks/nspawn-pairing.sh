#!/usr/bin/env sh
# PostToolUse on the nSPAWN DISPATCH verbs → make visible the work the
# harness does not see.
#
# An `nspawn_run_start` runs in a child process OUTSIDE the session: it is not a background
# Bash, not a subagent, not a workflow. The UI has nothing to show,
# and the owner reads «review running» with a frozen screen — measured 2026-09-01, with
# four dispatches in a row and zero signal.
#
# Prose did not cure this. The law already ordered the task list kept alive and it rotted;
# the `nspawn_run_show` description already shouted «DO NOT POLL» and the agent called it
# anyway. This hook is the mechanism: it fires by itself, at the exact instant of the
# dispatch, and hands over the identifiers without imposing another harness tools.
#
# UNCONDITIONAL on purpose. Detecting whether the pair already exists would require reading the
# harness task state, and a false silence is the worst possible failure mode
# here — silence is exactly what this hook exists to end.
set -eu

# READ BY BUILTIN, never by `cat`. This hook first falsifier caught
# the dependency: with `cat` off the PATH the payload comes out empty and the hook GOES SILENT —
# the same omission it exists to cure, committed by itself. `read` is
# a shell builtin and cannot be missing. It joins the lines because JSON has no significant
# newline outside a string, and inside one it already arrives escaped.
# The `|| [ -n "$__line" ]` is not ornament: `read` returns non-zero at EOF with no
# trailing newline and the loop body does not run, LOSING the last line. A one-line
# payload with no newline — which is what a test `printf` sends — vanished
# entirely and the hook went silent again.
payload=""
__line=""
while IFS= read -r __line || [ -n "$__line" ]; do
    payload="${payload}${__line}"
    __line=""
done
[ -n "$payload" ] || exit 0

# The run_id comes from the singular verb or from each route of a batch. Without `jq` the hook
# still speaks, only without the identifiers: a reminder made mute by a missing
# tool is the same omission it denounces.
runs=""
if command -v jq >/dev/null 2>&1; then
    runs=$(printf '%s' "$payload" | jq -r '
        [ (.tool_response.run_id // empty),
          (.tool_response.runs[]?.run_id // empty) ] | .[]' 2>/dev/null || printf '')
fi

text='ASYNC DISPATCH: the owner'"'"'s UI does not show this run. Track it in nMEMORY; use native task/plan UI only when registered. Without that UI, continue from the same durable state. Use registered completion notifications or a supported completion event; never invent a background tool or a polling loop.'
if [ -n "$runs" ]; then
    set -- $runs
    text="$text Run identifiers (data, not shell commands): $*."
fi
text="$text A task item is a claim; completion needs the actual executor result and its evidence."

# PostToolUse stdout is not shown to the model; hookSpecificOutput.additionalContext is.
if command -v jq >/dev/null 2>&1; then
    jq -cn --arg context "$text" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
else
    # Without jq no run_id was read, and the fixed text needs no JSON escaping.
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$text"
fi
exit 0
