#!/usr/bin/env bash
# state — the turn’s state line: `set` writes it, `show` renders it in the statusline.
#
# --- set ------------------------------------------------------------------------
#
# Owner request on 2026-09-21: «I want to OMIT that last line from the chat
# without affecting the statusline’s behaviour». No text trick works ---
# probing showed that the Claude Code renderer displays even HTML comments,
# and any prefix breaks the `startswith("RUNNING:")` that `state.sh show`
# does over the stored line. So the line changes CHANNEL: it is written via a
# tool call, here, and the Stop hooks read it from this file instead of the
# turn’s text.
#
#   bash plugin/scripts/state.sh set ’DELIVERED: <result> · <proof> · nothing left open’
#
# The file sits alongside the `<sid>.json` that `session-state.sh` already
# keeps, with the same session key. It is NOT DELETED by anyone: the two Stop
# hooks run in undefined order, and a consumer that deleted it would leave
# the other with nothing. Validity is by mtime against the turn’s
# `turn_started_at`, which `session-state.sh` writes on UserPromptSubmit ---
# a file from the previous turn is left behind on its own, with nobody having
# to remove it.
#
# --- show -----------------------------------------------------------------------
#
#   state.sh show <original statusline command...>
#
# Reads the statusline stdin, runs the original command with it, then prints ONE
# extra line from the session-state file plugin/hooks/session-state.sh writes:
#
#   📟 pytest tests/test_gate for 02:31 · turn for 14:03         (tool)
#   🧠 for 00:12                                                 (thinking)
#   🚀 11:07: gate #464 …                          (idle, `final` RUNNING)
#   ⛔ 11:07: no disposable database               (idle, `final` STOPPED)
#   ✅ 11:07: PR #614 merged                        (idle, `final` DELIVERED)
#   😴 11:07                                       (idle, no `final`)
#   ⏳ shell «wait law-only sentinel» · ⏳ unit nott-u4 active for 42 min
#   💀 general-purpose 11:20: rate_limit · ⏸ lane-x since 14:10
#
# Without a state file for the session it prints nothing extra, so the wrapper is
# invisible until the hook has written once. Installed to ~/.nott/bin/ by
# `./install.sh --statusline` (outside the bundle: survives a git revert).
#
# Cache of the original's output, TTL 10 s (two 5 s ticks): measured 2026-09-15
# (prova 0d) the live statusline renderer costs ~120 ms warm, above the ~100 ms
# ceiling the plan set. Consequence, declared: the heartbeat clock on the
# original's second line is the cache's time, up to 10 s behind; the state line
# itself is always live.
set -uo pipefail

usage() { printf 'usage: state.sh set <line> | state.sh show [<original statusline command...>]\n' >&2; exit 2; }

cmd_set() {
  local linha=${1:-} sid dir
  [ -n "$linha" ] || { printf 'state set: the state line is missing\n' >&2; exit 2; }
  # Codex: CODEX_THREAD_ID is the session_id that its hook payloads carry (measured 2026-10-16).
  sid=${CLAUDE_CODE_SESSION_ID:-${ANTIGRAVITY_TRAJECTORY_ID:-${CONVERSATION_ID:-${CODEX_THREAD_ID:-}}}}
  # Cut as the readers cut the payload's session_id, so the file they look for is this one.
  sid=$(printf '%s' "$sid" | tr -cd 'a-zA-Z0-9-')
  [ -n "$sid" ] || { printf 'state set: CLAUDE_CODE_SESSION_ID, ANTIGRAVITY_TRAJECTORY_ID, CONVERSATION_ID and CODEX_THREAD_ID are not set — outside a session?\n' >&2; exit 1; }
  dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nott/session-state"
  mkdir -p "$dir" || exit 1
  # THE FIRST LINE IS THE LINE. The rest is noise from someone who pasted a
  # paragraph; `state.sh show` cuts at 80 characters and long prose is no use
  # to it.
  printf '%s\n' "${linha%%$'\n'*}" > "$dir/$sid.final" || exit 1
}

cmd_show() {
  in=$(cat)
  now=$(date +%s)
  sid=$(printf '%s' "$in" | jq -r '.session_id // ""' 2>/dev/null | tr -cd 'a-zA-Z0-9-')
  dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nott/session-state"
  cache=$dir/$sid.orig

  if [ $# -gt 0 ]; then
    if [ -n "$sid" ] && [ -f "$cache" ] && [ $((now - $(stat -c %Y "$cache" 2>/dev/null || echo 0))) -lt 10 ]; then
      cat "$cache"
    else
      # `statusLine.command` is a SHELL string in settings.json, not an argv: the host
      # runs it through a shell, so a command with quoting, a pipe or `$HOME` in it must
      # keep working when wrapped (review, 2026-09-15). One bare argument that is not an
      # executable file goes back through the shell; everything else runs as argv.
      if [ $# -eq 1 ] && [ ! -x "$1" ]; then
        out=$(printf '%s' "$in" | sh -c "$1" 2>/dev/null)
      else
        out=$(printf '%s' "$in" | "$@" 2>/dev/null)
      fi
      printf '%s\n' "$out"
      if [ -n "$sid" ] && mkdir -p -m 700 "$dir" 2>/dev/null; then
        printf '%s\n' "$out" > "$cache.tmp" 2>/dev/null && mv -f "$cache.tmp" "$cache" 2>/dev/null
      fi
    fi
  fi

  file=$dir/$sid.json
  [ -n "$sid" ] && [ -r "$file" ] || return 0
  # Units come from `systemd-run --user`; the line shows only the ones still active.
  active=$(jq -r '.units[]?.unit' "$file" 2>/dev/null | while read -r u; do
    [ -n "$u" ] && [ "$(systemctl --user is-active "$u" 2>/dev/null)" = active ] && printf '%s\n' "$u"; done)
  jq -r --argjson now "$now" --arg active "$active" '
    def mmss: ($now - .) | if . < 0 then 0 else . end | "\(. / 60 | floor | tostring | if length < 2 then "0" + . else . end):\(. % 60 | tostring | if length < 2 then "0" + . else . end)";
    def hhmm: strflocaltime("%H:%M");
    def mins: (($now - .) / 60 | floor | tostring) + " min";
    # THE MARK SAYS THE STATE, AND THE WORD IT REPLACES GOES. A state line is read at a
    # glance or not at all, and two words saying the same thing spend the width the
    # useful text needs.
    # The Portuguese verbs are the compat reader for the pre-2026-09-23 state line: a live
    # session still on the old law keeps its mark for one release.
    def lower1: if (.[1:2] | test("[a-z]")) then (.[0:1] | ascii_downcase) + .[1:] else . end;
    def marca_final:
      . as $f
      | ([["A CORRER:", "🚀"], ["RUNNING:", "🚀"],
          ["PARADO:", "⛔"], ["STOPPED:", "⛔"],
          ["ENTREGUE:", "✅"], ["DELIVERED:", "✅"]]
         # `. as $p` BEFORE the pipe: after it `.` is $f (a string), and `.[0]` there
         # indexes it with a number — jq dies and the line vanishes, silenced by 2>/dev/null.
         | map(. as $p | select($f | startswith($p[0]))) | first) as $par
      # With no known verb the line passes whole, with the usual circle: inventing a
      # mark would assert a state nobody declared.
      | if $par == null then ["○", $f]
        else [$par[1], ($f[($par[0] | length):] | ltrimstr(" ") | lower1)] end;
    # An `as` inside an `if` branch extends BEYOND the `else` and swallows it — jq
    # dies and the whole line vanishes silently (the `2>/dev/null` is what hides it). Inside
    # a `def` the scope closes where it should.
    def linha_idle:
      (.final // "") as $f
      | (.stopped_at | hhmm) as $t
      | if $f != "" then ($f | marca_final) as $m | "\($m[0]) \($t): \($m[1])"
        else "😴 \($t)" end;
    ($active | split("\n") | map(select(length > 0))) as $active
    | [ (if .phase == "tool" then "📟 \(.tool.summary | lower1) for \(.tool.since | mmss)"
         elif .phase == "thinking" then "🧠 for \(.updated_at | mmss)"
         elif .phase == "idle" then linha_idle
         else empty end),
        (if (.phase == "tool" or .phase == "thinking") and (.turn_started_at != null) and ($now - .turn_started_at) >= 120
         then "turn for \(.turn_started_at | mmss)" else empty end),
        (.open[]? | "⏳ \(.kind) «\(if .description != "" then .description else .label end)»"),
        (.units[]? | select(.unit as $u | $active | index($u)) | "⏳ unit \(.unit) active for \(.since | mins)"),
        (.dead[]? | if .kind == "agent" then "💀 \(.label // .name) \(.at | hhmm): \(.reason | .[0:40])"
                    else "💀 \(.at | hhmm): \(.reason)" + (if (.resets_at // null) != null then " · back at \(.resets_at)" else "" end) end),
        (.teammate_idle[]? | "⏸ \(.name) since \(.at | hhmm)")
      ] | join(" · ")' "$file" 2>/dev/null
}

verb=${1:-}
[ $# -gt 0 ] && shift
case $verb in
  set) cmd_set "$@" ;;
  show) cmd_show "$@"; exit 0 ;;
  *) usage ;;
esac
