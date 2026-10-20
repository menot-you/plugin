#!/usr/bin/env -S bash -p
# two-misses — the law's "after two misses without differentiating evidence,
# suspend that path" (skills/debug/references/progress-and-stopping.md:8-11)
# gets a mechanical moment: a Bash command whose BYTE-IDENTICAL input already
# failed twice in this session is DENIED once on the third run. The retry
# passes unconditionally (`advised`), and a success clears the count.
#
# Ledger: ${XDG_STATE_HOME:-$HOME/.local/state}/nott/two-misses/<session_id>/
#   <sha256(tool_name + canonical tool_input)>/{fails,advised}
# `canonical` is `jq -cS` with `description` dropped, so key order and the
# model's prose never split one input in two; any other byte — a flag, a path,
# a space — is a different input, which is the point: the law asks for ONE
# changed input, and a changed input is a new key.
#
# THREE BINDINGS, one script, branch on hook_event_name:
#   PostToolUseFailure on Bash -> FAIL: the client routes a non-zero exit here
#     (red-first.sh reads it the same way). Measured 2026-09-15 in `claude
#     plugin eval` (p9b-two-misses-hook, --keep-temp): one `python3
#     test_impossible.py` with exit 1 left `fails` = 1 in the sealed home; the
#     tool result text begins "Exit code 1", so either event lands here.
#   PostToolUse on Bash -> FAIL when the payload still shows a failure (an
#     `error` field, an `"exit_code": N` other than 0 in the response's JSON
#     text, or an "Exit code N" line — the Codex projection flattens the
#     response to a string); otherwise SUCCESS: the entry is removed.
#   PreToolUse on Bash -> decide: fails >= 2 and not advised -> mark advised,
#     deny once.
# ONLY Bash. The task's `Bash|Edit|Write` matcher was measured against the
# ledger: an Edit/Write failure carries no exit code and is never counted, so
# a deny on those tools could never fire — dead code. PreToolUse is restricted
# to Bash and hooks.json binds only Bash.
# Fail-OPEN: bad JSON, no session_id, unwritable state -> exit 0 silent.
# Two channels, as in red-first.sh: exit 2 + stderr is the block the client
# honours everywhere; the JSON permissionDecision is the courtesy.
set -uo pipefail

payload=$(cat)
printf '%s' "$payload" | jq -e . >/dev/null 2>&1 || exit 0
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""')
[ "$(printf '%s' "$payload" | jq -r '.tool_name // ""')" = Bash ] || exit 0
sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' | tr -cd 'a-zA-Z0-9-')
[ -n "$sid" ] || exit 0
# `description` is model prose the client rewrites freely between identical
# commands (measured 2026-09-15: the same `python3 test_impossible.py` arrived
# with and without one), so it is not part of the input.
key=$(printf '%s' "$payload" | jq -cS '{t:.tool_name, i:((.tool_input // {}) | del(.description))}' | sha256sum | cut -c1-64)
entry="${XDG_STATE_HOME:-$HOME/.local/state}/nott/two-misses/$sid/$key"

case "$event" in
  PostToolUseFailure) failed=1 ;;
  PostToolUse)
    # An object response is read as its JSON text, so `"exit_code":1` and a
    # flattened Codex string are one grep.
    failed=$(printf '%s' "$payload" | jq -r 'if (.error // null) != null then 1 else 0 end')
    if [ "$failed" = 0 ]; then
      printf '%s' "$payload" | jq -r '.tool_response | if type == "string" then . else tojson end' \
        | grep -E '^Exit code [1-9]|"exit_code\\?": ?[1-9]' >/dev/null && failed=1
    fi ;;
  PreToolUse)
    [ -e "$entry/advised" ] && exit 0
    n=$(cat "$entry/fails" 2>/dev/null || echo 0)
    [ "${n:-0}" -ge 2 ] 2>/dev/null || exit 0
    : > "$entry/advised" 2>/dev/null || exit 0
    reason='two-misses: this exact command failed twice without a changed input. Decide internally what changes (the hypothesis and the one changed input) or reduce the reproducer, then retry; this deny fires once for this input.'
    printf '%s\n' "$reason" >&2
    jq -cn --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 2 ;;
  *) exit 0 ;;
esac

if [ "$failed" = 1 ]; then
  mkdir -p "$entry" 2>/dev/null || exit 0
  n=$(cat "$entry/fails" 2>/dev/null || echo 0)
  printf '%s' "$(( ${n:-0} + 1 ))" > "$entry/fails" 2>/dev/null
else
  rm -rf "$entry" 2>/dev/null
fi
exit 0
