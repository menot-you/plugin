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
# A LINE THAT CLAIMS DELIVERY AND NAMES A PULL REQUEST is written only when gh reads each named
# pull request as MERGED (retro cures slice 2, U1). The claim rule below is its one home: `set`
# reads gh for it, and `check` refuses it for the two Stop hooks, which write a line found in
# the reply.
#
# --- check ----------------------------------------------------------------------
#
#   state.sh check <line>
#
# The claim rule in reply mode: no network, no file. A claim with a reference gives exit 2 and
# the reply-refusal line on stdout, any other line exit 0 and no output, an empty line exit 2.
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
# invisible until the hook has written once.
#
# THE HOST SAYS DONE, NOT THE AGENT (live-plan-0). The session's place is
# $XDG_RUNTIME_DIR/nott/requests/: the spool that plugin/hooks/prompt-capture.py appends
# (<sid>.prompts.jsonl) and the node host's requests file (<sid>.json,
# harness/nott_harness/acp/schema/requests-file.v1.schema.json). As soon as either is there
# the line opens with the requests part:
#
#   requests: waiting for the host                   (a spool, no requests file, first line < 75 s)
#   🔴 requests: host not read                       (a spool, and no requests file after that)
#   🔴 requests: host not read since 11:07           (the host has not written for 2 min)
#   🔴 requests: host could not read runs since 11:07 (the file's inputErrors)
#   🔴 requests: prompt not recorded at 11:09        (an owner prompt with no spool line of its own)
#   🔴 requests: spool line unreadable               (a spool line that does not parse)
#   🔴 #3 overrun 42/30 min                          (the worst red alarm, of any entry)
#   🔴 died run 7a1f0c2e failed                      (the worst of a pending or unasked run)
#   #3 ▰▰▰▱ 18/30 min · 2 runs                       (else the newest open entry, with its live runs)
#   requests: waiting for the host                   (a spool line newer than the host's reading)
#   #5 answered by agent                             (a replied entry, and none open)
#   requests: all closed · 1 pending                 (every entry closed; the runs not attributed yet)
#
# and the agent's own state line keeps the neutral ○, never ✅. NOTHING SAYS GREEN IN THIS
# SLICE: every entry closed is not proof that nothing runs, because the host attributes a run
# only after it reads it, and an agent that writes DELIVERED is a claim, not a delivery.
#
# A PROMPT WITH NO LINE IS RED. session-state.sh keeps `owner_prompts`, the last owner prompts
# that prompt-capture.py owes a spool line, each {id, at}: the payload's prompt_id and the epoch
# ms. The line of a prompt is the spool line with its prompt_id, never the newest line by time.
# A prompt with no line counts as not yet recorded for PROMPT_GRACE (neutral), then as not
# recorded (red). This holds as soon as the requests directory is there, also with no spool and
# no host file: a capture hook that cannot write the spool leaves neither. A state of the
# previous hook carries only `owner_prompt_at`, the newest prompt with no id: it is read beside a
# spool or a host file alone, and a spool line up to PROMPT_GRACE older than it is its line.
#
# A SPOOL LINE THAT DOES NOT PARSE IS RED (a partial write). It never hides a prompt: the prompt
# that it was for has no line of its own. The judge reads the last SPOOL_TAIL lines of the
# spool, enough for the prompts that session-state.sh keeps; the whole spool cost 30-90 ms at
# 2000 lines (measured 2026-10-22), on each hook event of the session.
#
# --- judge ----------------------------------------------------------------------
#
#   state.sh judge <session_id>
#
# Prints the window colour that the requests place allows: red or neutral, never green, or
# nothing when the session has neither a spool nor a requests file and no prompt is lost. plugin/hooks/session-state.sh paints
# from it, so the rule has this one home for both the window and the line. Installed to ~/.nott/bin/ by
# `./install.sh --statusline` (outside the bundle: survives a git revert).
#
# Cache of the original's output, TTL 10 s (two 5 s ticks): measured 2026-09-15
# (prova 0d) the live statusline renderer costs ~120 ms warm, above the ~100 ms
# ceiling the plan set. Consequence, declared: the heartbeat clock on the
# original's second line is the cache's time, up to 10 s behind; the state line
# itself is always live.
set -uo pipefail

usage() { printf 'usage: state.sh set <line> | state.sh check <line> | state.sh show [<original statusline command...>] | state.sh judge <session_id>\n' >&2; exit 2; }

#: A host that has not written for this long is not reading; how far apart the two hooks
#: of one prompt may write; and how long a spool may wait for the host's first file (one 30 s
#: pass plus margin), from the session's first spool line, in ms.
STALE_MS=120000
PROMPT_GRACE_MS=5000
HOST_GRACE_MS=75000
#: The spool lines that the judge reads, from the end: eight times the prompts that
#: session-state.sh keeps (8).
SPOOL_TAIL=64

# requests_read <sid> — two lines from the session's requests place: the colour class (red or
# neutral), then the requests part of the state line. Nothing when the session has neither a
# spool nor a requests file and no owner prompt is lost, or when the requests directory is not
# there. A file that does not parse is red: an unreadable host never reads as a quiet one.
#
# ONE MILLISECOND CLOCK for the plugin's scripts: jq's `now * 1000 | floor`, here and in
# plugin/hooks/session-state.sh. BSD date has no %N (it prints `date +%s%3N` as "<s>3N"), and
# bash 3.2 has no $EPOCHREALTIME; jq is already a dependency of both scripts.
requests_read() {
  local sid=$1 place file spool has_file=false has_spool=false legacy=false prompts out
  [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -n "$sid" ] || return 0
  place=$XDG_RUNTIME_DIR/nott/requests
  file=$place/$sid.json
  spool=$place/$sid.prompts.jsonl
  [ -d "$place" ] || [ -e "$file" ] || [ -e "$spool" ] || return 0
  [ -e "$file" ] && has_file=true
  [ -e "$spool" ] && has_spool=true
  { $has_file || $has_spool; } && legacy=true
  # The owner prompts that session-state.sh kept, each {id, at}. An id that is not a string can
  # match no line. The clock of the previous hook (no id) counts beside a spool or a host file
  # alone, as it did. A state that does not parse keeps no prompt.
  prompts=$(jq -c --argjson legacy "$legacy" '
    if (.owner_prompts | type) == "array" then
      [.owner_prompts[] | objects | select(.at | type == "number")
       | {id: (.id | if type == "string" or type == "null" then . else "" end), at}]
    elif $legacy and (.owner_prompt_at | type) == "number" then [{id: null, at: .owner_prompt_at}]
    else [] end' "$XDG_RUNTIME_DIR/nott/session-state/$sid.json" 2>/dev/null) || prompts='[]'
  [ -n "$prompts" ] || prompts='[]'
  # The requests directory alone, with no prompt kept: nothing to judge.
  $legacy || [ "$prompts" != '[]' ] || return 0
  # A missing requests file is the null input, so one program judges both cases; a file that
  # does not parse stays an error. The spool comes in through files, never argv (128 KB a string).
  $has_file || file=/dev/null
  $has_spool || spool=/dev/null
  out=$(jq -nr --rawfile tail <(tail -n "$SPOOL_TAIL" "$spool" 2>/dev/null) \
    --rawfile first <(head -n 1 "$spool" 2>/dev/null) \
    --argjson prompts "$prompts" --argjson has_file "$has_file" --argjson has_spool "$has_spool" \
    --argjson stale_ms "$STALE_MS" --argjson grace_ms "$PROMPT_GRACE_MS" --argjson host_grace_ms "$HOST_GRACE_MS" '
    def hhmm: . / 1000 | floor | strflocaltime("%H:%M");
    # A spool line: an object with a number `at`, or null for a line that does not parse.
    def row: try (fromjson | if type == "object" and (.at | type) == "number" then . else null end) catch null;
    def rows: split("\n") | map(select(test("\\S")) | row);
    (now * 1000 | floor) as $now_ms
    | ($tail | rows) as $rows
    | [$rows[] | objects] as $lines
    | (($rows | length) - ($lines | length)) as $bad
    # The newest time of a line that parses; 0 with none.
    | ([$lines[].at] | max // 0) as $spool_at
    # The first line starts the host grace; one that does not parse (-1) gets none.
    | ($first | rows | if length == 0 or .[0] == null then -1 else .[0].at end) as $first_at
    | ([$lines[] | .prompt_id | strings | {key: ., value: true}] | from_entries) as $ids
    # An owner prompt with no spool line of its own: not recorded yet while the capture hook may
    # still write it, then lost. The clock of the previous hook (no id) takes the newest line up
    # to the grace older than it.
    | [$prompts[] | select(if .id == null then .at - $spool_at > $grace_ms else $ids[.id] != true end)] as $unrecorded
    | [$unrecorded[] | select($now_ms - .at > $grace_ms)] as $lost
    | (if ($lost | length) == 0 then null
       elif ($lost | length) == 1 then "🔴 requests: prompt not recorded at \($lost[0].at | hhmm)"
       else "🔴 requests: \($lost | length) prompts not recorded, the last at \([$lost[].at] | max | hhmm)" end) as $lost_line
    | (if $bad == 0 then null
       elif $bad == 1 then "🔴 requests: spool line unreadable"
       else "🔴 requests: \($bad) spool lines unreadable" end) as $bad_line
    # No host file yet: its first pass may be up to 30 s away, so the session waits while its
    # first spool line is younger than the grace. A first line further ahead than the grace is
    # a clock that cannot be read, never a wait that would not end.
    | ($first_at >= 0 and ($now_ms - $first_at | if . < 0 then -. else . end) < $host_grace_ms) as $in_grace
    | (if $has_file then input else null end)
    | if . == null then
        if $lost_line != null then "red", $lost_line
        elif $bad_line != null then "red", $bad_line
        elif ($has_file or $has_spool) | not then "none"
        elif ($has_file | not) and $in_grace then "neutral", "requests: waiting for the host"
        else "red", "🔴 requests: host not read" end
      else
    # Worst first, as the schema orders them; every alarm but no-expectation is red.
    def rank: {"loop":0, "died":1, "unasked":2, "overrun":3, "silent":4, "stalled":5, "no-expectation":6}[.];
    def is_red: rank < 6;
    def terminal: . as $p | ["orphaned", "completed", "failed", "closed"] | index($p) != null;
    def bar($spent; $of): ([4, (4 * $spent / $of | ceil)] | min) as $n | ("▰" * $n) + ("▱" * (4 - $n));
    def live_runs: [.runs[] | select(.phase | terminal | not)] | length;
    # A list the host file names (absent in an older host file): a value that is not one makes
    # the file unreadable, never quiet.
    def list($key): .[$key] // [] | if type == "array" then map(objects) else error($key) end;
    (.observedAt | numbers) as $seen
    | [.entries[] | objects] as $entries
    | [.unasked[] | objects] as $unasked
    | list("pending") as $pending
    | list("inputErrors") as $input_errors
    | ($now_ms - $seen >= $stale_ms) as $stale
    | ($entries | map(select(.state == "open")) | sort_by(-.number)) as $open
    # A closed entry carries the alarms of its runs (died, silent): red wherever the run sits.
    | ([$entries | sort_by(-.number) | .[] | . as $e | .alarms[] | select(is_red) | {rank: rank, alarm: ., entry: $e}]
       + [$pending[], $unasked[] | . as $u | .alarms[] | select(is_red) | {rank: rank, alarm: ., run: $u}]
       | sort_by(.rank) | first) as $worst
    # A spool line the host has not read yet: a line that does not parse counts as not read.
    | ($bad > 0 or $spool_at >= $seen or ($unrecorded | length) > 0) as $unread
    | (if $stale or $worst != null or ($input_errors | length) > 0 or $lost_line != null or $bad_line != null
       then "red" else "neutral" end) as $class
    | $class,
      (if $stale then "🔴 requests: host not read since \($seen | hhmm)"
       elif ($input_errors | length) > 0 then
         "🔴 requests: host could not read " + ($input_errors | map("\(.input | tostring) since \(.since | hhmm)") | join(", "))
       elif $lost_line != null then $lost_line
       elif $bad_line != null then $bad_line
       elif $worst.entry != null then
         $worst.entry as $e
         | "🔴 #\($e.number) \($worst.alarm) \($e.spentMin)\(if $e.minutes != null then "/\($e.minutes)" else "" end) min"
       elif $worst.run != null then "🔴 \($worst.alarm) run \($worst.run.runId[0:8]) \($worst.run.phase)"
       elif ($open | length) > 0 then
         $open[0] as $e | ($e | live_runs) as $n
         | "#\($e.number) "
           + (if $e.minutes != null then "\(bar($e.spentMin; $e.minutes)) \($e.spentMin)/\($e.minutes) min"
              else "\($e.spentMin) min · no expectation" end)
           + (if $n == 0 then "" elif $n == 1 then " · 1 run" else " · \($n) runs" end)
       elif $unread then "requests: waiting for the host"
       elif ($entries | any(.state == "replied")) then
         "#\($entries | map(select(.state == "replied")) | max_by(.number) | .number) answered by agent"
       # No entry is open or replied: every one is closed.
       else "requests: all closed" + (if ($pending | length) > 0 then " · \($pending | length) pending" else "" end) end)
      end
  ' "$file" 2>/dev/null)
  [ "$out" != none ] || return 0
  if [ "$(printf '%s\n' "$out" | wc -l)" -ne 2 ]; then
    printf 'red\n🔴 requests: file unreadable\n'
  else
    printf '%s\n' "$out"
  fi
}

cmd_judge() {
  local sid
  sid=$(printf '%s' "${1:-}" | tr -cd 'a-zA-Z0-9-')
  [ -n "$sid" ] || usage
  requests_read "$sid" | sed -n 1p
}

# THE CLAIM RULE. A line is split into segments at `·`. It is a claim when its verb is DELIVERED
# or ENTREGUE, or when a segment holds the whole word delivered, entregue or entregues in any
# case, or DONE or LIVE in capitals, and no negation word (the list in `negated`, in English
# and Portuguese) is one of the two words before it. The proof segments of a DELIVERED or ENTREGUE line are all
# its segments but one that starts with `open:` or `aberto:`; those of another claim are its
# claim segments. A reference is `#` and digits with no letter, digit or underscore touching it:
# `PR #12` and `(#12)` are references, `PR#12`, `_#12_`, `owner/repo#12` and `README.md#2` are not.
# MARKDOWN DOES NOT HIDE A CLAIM. Each backtick goes first, as `demark` in
# plugin/hooks/session-state.sh removes them all from the stored line: `PR #\`2\`` is a reference.
# The verb test and the claim words then read each `*` as a space, and each `_` that is not
# between two letters or digits: that `_` is emphasis, so `__DELIVERED__:` and `_entregue_` are
# claims. An `_` between two letters or digits is part of an identifier, so `delivered_at`,
# `NOTT_LIVE` and `no_regressions` are one word each. The reference scan reads the segment with
# only its backticks gone.
# claim_refs <line> — the references of the claim in its proof segments, once each, in order.
# Nothing for a line that is no claim or a claim with no reference.
claim_refs() {
  jq -nr --arg l "$1" '
    ($l | gsub("`"; "")) as $raw
    | ($raw | gsub("[*]"; " ") | gsub("(?<![[:alnum:]])_|_(?![[:alnum:]])"; " ")) as $l
    | def words: [scan("[[:alnum:]_]+")];
    def negated($w; $i): [$w[(if $i < 2 then 0 else $i - 2 end):$i][]
      | test("^(?i:not|no|nothing|never|não|nao|nada|nunca)$")] | any;
    def claim_segment: words as $w
      | any(range(0; $w | length); . as $i
            | ($w[$i] | test("^(?i:delivered|entregues?)$") or test("^(DONE|LIVE)$")) and (negated($w; $i) | not));
    ($l | split("·")) as $segs | ($raw | split("·")) as $raws
    | if ($l | test("^[^[:alpha:]]*(DELIVERED|ENTREGUE)(?![[:alnum:]_])"))
      then [range(0; $segs | length) | select($segs[.] | sub("^[[:space:]]+"; "") | test("^(open|aberto):") | not)]
      else [range(0; $segs | length) | select($segs[.] | claim_segment)] end
    | [.[] | $raws[.] | scan("(?<![[:alnum:]_])#([0-9]+)(?![[:alnum:]_])")[0]]
    | reduce .[] as $r ([]; if index([$r]) then . else . + [$r] end) | .[]'
}

#: How long one gh call may take, in seconds.
GH_BOUND_S=5
# gh_state <n> — `<STATE> <url>` as gh reads PR #<n> in the repository it resolves (GH_REPO,
# else the cwd's checkout). Fails when gh is missing, fails, or passes GH_BOUND_S. The watchdog is
# bash, not `timeout`, which macOS lacks. Neither it nor gh keeps the caller's stdout or stderr
# open: gh writes a file, and the watchdog and its sleep write /dev/null.
gh_state() {
  local f pid w rc
  command -v gh >/dev/null 2>&1 || return 1
  f=$(mktemp "${TMPDIR:-/tmp}/state-gh.XXXXXX") || return 1
  gh pr view "$1" --json state,url --jq '.state + " " + .url' > "$f" 2>/dev/null < /dev/null &
  pid=$!
  ( trap 'kill "${s:-}" 2>/dev/null; exit 0' TERM; sleep "$GH_BOUND_S" & s=$!; wait "$s"; kill "$pid" 2>/dev/null ) > /dev/null 2>&1 < /dev/null &
  w=$!
  wait "$pid"; rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  [ "$rc" = 0 ] && cat "$f"
  rm -f "$f"
  return "$rc"
}

cmd_check() {
  local linha=${1:-} refs
  [ -n "$linha" ] || exit 2
  refs=$(claim_refs "${linha%%$'\n'*}") || exit 1
  [ -z "$refs" ] || { printf '%s\n' 'STOPPED: claim refused, written in the reply · next action: use state.sh set'; exit 2; }
  exit 0
}

cmd_set() {
  local linha=${1:-} sid dir child refs n answer estado url repo
  [ -n "$linha" ] || { printf 'state set: the state line is missing\n' >&2; exit 2; }
  # Codex: CODEX_THREAD_ID is the session_id that its hook payloads carry (measured 2026-10-16).
  sid=${CLAUDE_CODE_SESSION_ID:-${ANTIGRAVITY_TRAJECTORY_ID:-${CONVERSATION_ID:-${CODEX_THREAD_ID:-}}}}
  # Cut as the readers cut the payload's session_id, so the file they look for is this one.
  sid=$(printf '%s' "$sid" | tr -cd 'a-zA-Z0-9-')
  [ -n "$sid" ] || { printf 'state set: CLAUDE_CODE_SESSION_ID, ANTIGRAVITY_TRAJECTORY_ID, CONVERSATION_ID and CODEX_THREAD_ID are not set — outside a session?\n' >&2; exit 1; }
  # THE SESSION nSPAWN LAUNCHED ANSWERS ITS CALLER (the test of plugin/hooks/final-state.sh): its
  # final text is its product, and its caller writes the owner's line.
  child=$(printf '%s' "${NOTT_NSPAWN_SESSION_ID:-}" | tr -cd 'a-zA-Z0-9-')
  if [ -n "$child" ] && [ "$child" = "$sid" ]; then
    printf 'state set: this session is an nSPAWN child. Put the result in the final text. The session that started this one writes the state line.\n' >&2
    exit 2
  fi
  dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nott/session-state"
  mkdir -p "$dir" || exit 1
  # THE FIRST LINE IS THE LINE. The rest is noise from someone who pasted a
  # paragraph; `state.sh show` cuts at 80 characters and long prose is no use
  # to it.
  linha=${linha%%$'\n'*}
  refs=$(claim_refs "$linha") || { printf 'state set: the claim rule did not run (jq failed). Nothing was written.\n' >&2; exit 1; }
  # Each reference is read in turn, and the first one that is not MERGED stops the claim.
  for n in $refs; do
    answer=$(gh_state "$n") || answer=
    estado=${answer%% *} url=${answer#* }
    case $estado in ''|*[!A-Z_]*) answer= ;; esac
    case $url in https://*/pull/*) ;; *) answer= ;; esac
    case $url in *[[:space:]]*) answer= ;; esac
    if [ -z "$answer" ]; then
      printf '%s\n' "STOPPED: claim not verified on PR #$n · next action: set from its repo" > "$dir/$sid.final" || exit 1
      printf 'state set: gh did not read PR #%s from %s (gh failed, is missing, gave an answer that does not parse, or passed its %s s bound), so no repository was read. Run set from a checkout of the pull request'"'"'s repository. If GitHub was down, try again. gh must be on PATH and logged in. If #%s is not a pull request, write the number without "#".\n' \
        "$n" "$PWD" "$GH_BOUND_S" "$n" >&2
      exit 1
    fi
    repo=${url#https://*/}; repo=${repo%/pull/*}
    if [ "$estado" != MERGED ]; then
      printf '%s\n' "STOPPED: claim refused, PR #$n is not merged · next action: claim after merge" > "$dir/$sid.final" || exit 1
      printf 'state set: PR #%s in %s is %s, not MERGED (%s). Write the claim again after the merge. If #%s is not a pull request of this claim, write the number without "#".\n' \
        "$n" "$repo" "$estado" "$url" "$n" >&2
      exit 2
    fi
    printf 'state set: PR #%s in %s is MERGED (%s)\n' "$n" "$repo" "$url" >&2
  done
  printf '%s\n' "$linha" > "$dir/$sid.final" || exit 1
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

  # The requests part, and whether the agent's own verb keeps its mark: with the host file
  # present no verb keeps it, and nothing is green.
  requests=$(requests_read "$sid" | sed -n 2p)
  # A state write that session-state.sh could not make (<sid>.error: "<epoch s> <what>"): the
  # state below is the last one written, so the line opens red and no verb keeps its mark.
  if [ -n "$sid" ] && [ -s "$dir/$sid.error" ]; then
    failed=$(jq -Rr 'capture("^(?<at>[0-9]+) (?<what>.*)$")
      | "🔴 session-state hook failed \(.at | tonumber | strflocaltime("%H:%M")): \(.what)"' \
      "$dir/$sid.error" 2>/dev/null | head -n 1)
    requests="${failed:-🔴 session-state hook failed}${requests:+ · $requests}"
  fi
  [ -n "$requests" ] && verbs=false || verbs=true
  file=$dir/$sid.json
  if [ -z "$sid" ] || [ ! -r "$file" ]; then
    [ -z "$requests" ] || printf '%s\n' "$requests"
    return 0
  fi
  # Units come from `systemd-run --user`; the line shows only the ones still active.
  active=$(jq -r '.units[]?.unit' "$file" 2>/dev/null | while read -r u; do
    [ -n "$u" ] && [ "$(systemctl --user is-active "$u" 2>/dev/null)" = active ] && printf '%s\n' "$u"; done)
  jq -r --argjson now "$now" --arg active "$active" --arg requests "$requests" --argjson verbs "$verbs" '
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
      | if $par == null or ($verbs | not) then ["○", $f]
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
    | [ (if $requests != "" then $requests else empty end),
        (if .phase == "tool" then "📟 \(.tool.summary | lower1) for \(.tool.since | mmss)"
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
  check) cmd_check "$@" ;;
  show) cmd_show "$@"; exit 0 ;;
  judge) cmd_judge "$@" ;;
  *) usage ;;
esac
