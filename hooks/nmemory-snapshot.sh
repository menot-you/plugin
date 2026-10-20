#!/usr/bin/env bash
# PreCompact / PostCompact → write the status a compaction is about to erase. SessionEnd (and an
# explicit call with no hook_event_name) → the capture reminder below, which writes the same
# file (it was nmemory-stop-reminder.sh).
#
# Neither event can inject context: in claude 2.1.251 PreCompact, PostCompact and
# SessionEnd carry NO `hookSpecificOutput` schema and no additionalContext branch
# (measured against the binary). So this half only SAVES; nmemory-session.sh reads
# it back at SessionStart, whose `compact` source is the event that can inject.
#
# PreCompact writes the snapshot; PostCompact appends the summary compaction
# produced, which is the only place `compact_summary` is ever offered. Order between
# PostCompact and SessionStart is not relied on: a summary that lands late is simply
# read on the next injection.
#
# Fail-open EVERYWHERE. A hook that errors or blocks here costs the session more than
# the snapshot is worth: every branch exits 0, and only the explicit call below prints.
set -u

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""' 2>/dev/null) || exit 0
sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null) || exit 0
case "$sid" in ''|*[!a-zA-Z0-9-]*) exit 0 ;; esac

dir="${XDG_STATE_HOME:-$HOME/.local/state}/nott/nmemory-compact"
mkdir -p "$dir" 2>/dev/null || exit 0
snap="$dir/$sid.md"

# THE CAPTURE REMINDER (it was nmemory-stop-reminder.sh).
# It recognizes unacknowledged capture after edits. Two deliveries, one observation.
#
# This is NOT registered on automatic Claude Stop, and must not be. Stop
# additionalContext resumes the model after its final answer; native controls
# proved that this helper caused a seventh request after five tools and a
# completed consumer result. Removing that registration left six requests with
# the same consumers and the same cleanup.
#
# It IS registered on SessionEnd, which in this host carries no
# `hookSpecificOutput` schema and no additionalContext branch — the same measured
# property that makes PreCompact write-only. So the SessionEnd delivery cannot
# re-enter the model: it only APPENDS the observation to the per-session file
# nmemory-session.sh replays at the next SessionStart. That closes the law's
# order to persist an owner correction, its consequence and any revocation, which
# until now had no mechanism watching it at all.
#
# When explicitly invoked (no hook_event_name), it speaks on stdout only when the transcript
# shows edit requests without an acknowledged ingest/handoff capture. Reading or
# requesting a write is not a capture. Silence proves at most one acknowledged
# operation, never that every pending obligation is covered. A marker keeps the
# advisory to one utterance per session.
#
# Fail-open EVERYWHERE: no jq, no transcript, no state dir → silence, exit 0.
if [ "$event" = SessionEnd ] || [ -z "$event" ]; then
  # An nSPAWN child or workflow run has no nMEMORY (owner decision), so it
  # gets no capture reminder: its parent captures what it reports. Its compaction
  # snapshot below is local state, not memory, and stays.
  [ -n "${NOTT_NSPAWN_RUN_ID:-}" ] && exit 0
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // ""' 2>/dev/null) || exit 0
  [ -n "$transcript" ] && [ -r "$transcript" ] || exit 0

  marker="$dir/$sid.reminded"
  [ -e "$marker" ] && exit 0

  counts=$(jq -rs '
    def capture_tool:
      test("^mcp__(nmemory|plugin_nott_nmemory|plugin_nott_nmemory-http)__nmemory_(capsule_ingest|session_finish)$");
    def receipt($name):
      if type != "object" then false
      elif ($name | endswith("__nmemory_capsule_ingest")) then
        (.rejected // 0) == 0 and (.outcomes | type) == "array"
        and (.outcomes | length) > 0
        and all(.outcomes[]; (.status == "captured" or .status == "deduplicated")
          and (.id | type) == "string" and (.id | test("^cap-[0-9]+$")))
      else
        (.session_id | type) == "string" and (.session_id | length) > 0
        and (.handoff_capsule | type) == "string"
        and (.handoff_capsule | test("^cap-[0-9]+$"))
      end;
    def text_blocks:
      if type == "string" then .
      elif type == "array" then .[] | select(.type == "text") | .text
      else empty end;
    reduce .[] as $row ({edits:0,calls:{},captures:0};
      reduce ($row.message.content // [] | arrays)[] as $block (.;
        if $row.type == "assistant" and $block.type == "tool_use" then
          if (["Write","Edit","NotebookEdit"] | index($block.name)) != null
            then .edits += 1 else . end
          | if ($block.id | type) == "string" then
              .calls[$block.id] = (if (.calls | has($block.id)) then null else $block.name end)
            else . end
        elif $row.type == "user" and $block.type == "tool_result"
          and $block.is_error != true and ($block.tool_use_id | type) == "string" then
          .calls[$block.tool_use_id] as $name
          | if ($name | type) == "string" and ($name | capture_tool) then
              .captures += ([$block.content | text_blocks | fromjson?
                | select(try receipt($name) catch false)] | length)
            else . end
        else . end))
    | "\(.edits) \(.captures)"
  ' "$transcript" 2>/dev/null) || exit 0

  read -r edits captures <<<"$counts" || exit 0
  edits=${edits:-0}
  captures=${captures:-0}
  case "$edits$captures" in *[!0-9]*) exit 0 ;; esac
  [ "$edits" -gt 0 ] || exit 0
  [ "$captures" -eq 0 ] || exit 0

  : >"$marker" 2>/dev/null || :

  if [ "$event" = SessionEnd ]; then
    # No stdout: SessionEnd has no injection channel, and printing here would be a
    # silent no-op at best. The next SessionStart for this session reads the file.
    printf 'PENDING CAPTURE (nMEMORY): before this point the session requested %s file edit(s) and acknowledged no ingest or handoff receipt. Whatever trigger, correction, consequence or revocation it was ordered to persist is still only in the transcript. Persist the missing records through the registered tools before relying on them as durable authority. Silence from this observation never certifies that every capture obligation is covered.\n\n' \
      "$edits" >>"$dir/$sid.md" 2>/dev/null || :
    exit 0
  fi

  jq -n '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}' \
    --arg msg "File edits were requested, but this transcript shows no acknowledged nMEMORY ingest or handoff capture. Check which decisions, outcomes or blockers still need durable capture and persist only the missing records through the registered tools. Finish only an already-open memory session; do not create a session merely for this reminder. Silence from this advisory never certifies that every capture obligation is covered." \
    2>/dev/null || :
  exit 0
fi

if [ "$event" = PostCompact ]; then
  summary=$(printf '%s' "$payload" | jq -r '.compact_summary // ""' 2>/dev/null) || exit 0
  [ -n "$summary" ] || exit 0
  { printf '\n## compaction summary\n\n'; printf '%s\n' "${summary:0:6000}"; } >>"$snap" 2>/dev/null
  exit 0
fi

cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null) || cwd=''
trigger=$(printf '%s' "$payload" | jq -r '.trigger // "unknown"' 2>/dev/null) || trigger=unknown
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // ""' 2>/dev/null) || transcript=''

# The last assistant text is the closest thing to "where the owner stopped" that a
# shell can read: the model's own last statement of state, before the summariser
# rewrites it. Truncated hard — this is injected back into a fresh context.
last_text=''
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
  last_text=$(tail -n 400 "$transcript" 2>/dev/null | jq -rs '
    [ .[]
      | select(.type == "assistant")
      | (.message.content // [])
      | map(select(.type == "text") | .text)
      | join("\n") ]
    | map(select(. != ""))
    | (last // "")[0:4000]' 2>/dev/null) || last_text=''
fi

{
  printf '# pre-compaction snapshot · %s · trigger=%s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$trigger"
  [ -n "$cwd" ] && printf 'cwd: %s\n' "$cwd"
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=''
    head=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null) || head=''
    dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l) || dirty=''
    [ -n "$branch" ] && printf 'branch: %s @ %s · %s dirty path(s)\n' "$branch" "$head" "$dirty"
  fi
  [ -n "$last_text" ] && { printf '\n## last stated state\n\n'; printf '%s\n' "$last_text"; }
} >"$snap" 2>/dev/null

exit 0
