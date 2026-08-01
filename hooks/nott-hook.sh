#!/bin/sh
set -eu

fail() {
  printf '%s\n' "nott-hook: $*" >&2
  exit 2
}

escape_json() {
  awk '
    BEGIN { first = 1 }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\t/, "\\t")
      gsub(/\r/, "\\r")
      if (!first) {
        printf "\\n"
      }
      printf "%s", $0
      first = 0
    }
    END {
      if (NR > 0) {
        printf "\\n"
      }
    }
  '
}

payload=$(cat 2>/dev/null) || payload=''
event=${1-}

# Stop = voice lint (owner calibration cap-69/cap-70), WARN-first observer: findings
# append to the state ledger; NOTT_VOICE_LINT_MODE=block turns rejection on once the
# WARN ledger proves the heuristics. Runs before the canon checks because a lint
# failure must never be able to break a session stop — every path degrades to exit 0.
voice_lint() {
  command -v jq >/dev/null 2>&1 || return 0
  tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || return 0
  [ -n "$tp" ] || return 0
  [ -f "$tp" ] || return 0
  sid=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null) || sid=unknown
  active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null) || active=false
  last=$(jq -rs '[.[] | select(.type == "assistant")] | last | .message.content // [] | map(select(.type == "text") | .text) | join("\n")' "$tp" 2>/dev/null) || return 0
  [ -n "$last" ] || return 0
  tail_para=$(printf '%s\n' "$last" | awk 'BEGIN { RS = "" } { p = $0 } END { print p }')
  findings=''
  qm=$(printf '%s' "$tail_para" | awk -F '?' '{ n += NF - 1 } END { print n + 0 }')
  if [ "$qm" -ge 2 ]; then
    findings="menu-close(q=$qm)"
  fi
  if printf '%s' "$tail_para" | grep -qiE 'Topa\?|\bOu (quer|prefere)m?\b'; then
    findings="$findings menu-pattern"
  fi
  plex='\b(incr[ií]vel|fodon[ao]|perfeit[oa]|genial|insan[oa]|impressionante|sensacional|maravilhos[oa]|espetacular|amazing|incredible|awesome|perfect)\b'
  praise=$(printf '%s' "$last" | grep -icE "$plex" 2>/dev/null) || praise=0
  justified=$(printf '%s' "$last" | grep -iE "$plex" 2>/dev/null | grep -icE '\b(porque|pois|por causa|j[aá] que|because)\b' 2>/dev/null) || justified=0
  unj=$((praise - justified))
  if [ "$unj" -gt 0 ]; then
    findings="$findings filler-praise($unj)"
  fi
  # LENGTH, and it BLOCKS while the heuristics above only warn. Measured on this
  # box 2026-07-30 across one session: the closes the owner called "extremamente
  # verboso" ran 219, 313, 360, 456, 500 and 622 words; the one turn in that span he
  # did not object to ran 129. So the ceiling is 150 words of user-facing text —
  # derived from observed tolerance, not chosen for roundness.
  #
  # WHY THIS ONE BLOCKS AND THE OTHERS DO NOT. The canon already carries the rule
  # ("state what became true and the one next action, then stop"), the agent reads it
  # every turn, and the agent still overran — twice in one session, the second time
  # after saying it had understood. "Received and did not follow" is not a diagnosis
  # anybody can act on, so voice stops being the enforcer here. The retired Stop block
  # (see handoff_clause below) was withdrawn because it renders a paragraph in the
  # owner's chat and costs an extra turn; that price is real and it is smaller than a
  # 600-word close, which is why length gets the rung the menu and praise heuristics
  # do not. Those stay in warn until a ledger justifies otherwise.
  #
  # THE ONE EXEMPTION IS MECHANICAL, never a claim the agent makes: the canon's
  # REFERENCE register — a roadmap, queue, or contract the owner answers BY NUMBER —
  # is legitimately long, and it is recognisable without judgement as three or more
  # lines opening with `N.`. Anything else is conversation register and is capped.
  words=$(printf '%s' "$last" | wc -w 2>/dev/null) || words=0
  numbered=$(printf '%s\n' "$last" | grep -cE '^[[:space:]]*[0-9]+\.[[:space:]]' 2>/dev/null) || numbered=0
  ceiling=${NOTT_VOICE_MAX_WORDS:-150}
  over=0
  if [ "$words" -gt "$ceiling" ] && [ "$numbered" -lt 3 ]; then
    over=1
    findings="$findings over-length($words>$ceiling)"
  fi
  findings=${findings# }
  [ -n "$findings" ] || return 0
  mode=${NOTT_VOICE_LINT_MODE:-warn}
  state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/nott
  mkdir -p "$state_dir" 2>/dev/null || return 0
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || ts=unknown
  ev=$(printf '%s' "$tail_para" | tail -c 240 | escape_json) || ev=''
  printf '{"ts":"%s","session_id":"%s","mode":"%s","findings":"%s","evidence":"%s"}\n' \
    "$ts" "$sid" "$mode" "$findings" "$ev" >>"$state_dir/voice-lint.jsonl" 2>/dev/null || return 0
  # THIS LINT IS NOW SILENT, ALWAYS, WITH NO OPT-IN. It writes the ledger line above and
  # emits NOTHING — no block, no rendered reason, no path that can reach the owner's chat.
  #
  # Owner ruling 2026-07-31 (`cap-946`): "some com esse hook". Both shapes had failed, and
  # the blocking one failed in the direction that matters — a Stop block leaves the ORIGINAL
  # close rendered, adds its reason, then renders the rewrite, so a mechanism built to halve
  # the surface DOUBLED it and the owner paid output tokens for all three. A gate on output
  # can only APPEND; it cannot un-print what it objects to.
  #
  # The `block` mode is gone rather than defaulted off, because a switch that renders text
  # into the owner's chat is one env var away from doing it again, and nothing in this repo
  # needs it. The rule it used to enforce now lives where a rule about prose belongs — in
  # `NOTT.md`'s Output Style section, ahead of the sentence rather than after it.
  #
  # The MEASUREMENT stays, and that is the whole reason this function still exists: the law
  # in the canon is advisory (it sat in context through all 29 of the closes that produced
  # it), so `over-length` accumulating in the ledger is the only way "the law worked" stays
  # answerable from data instead of impression. If the count does not fall, the next rung is
  # structural, not another sentence.
  return 0
}

# UserPromptSubmit = silent auto-handoff reminder (owner calibration 2026-07-30;
# supersedes the Stop block shipped 2026-07-20 under cap-79/cap-80). The block held
# the mechanism but paid with exactly the two costs a Stop block IS MADE OF: the
# reason paragraph is rendered in the owner's chat, and a blocked stop forces one
# more assistant turn whose only content is an acknowledgement. Neither is a side
# effect to tune away. So the reminder moves off Stop and onto the turn the agent is
# ALREADY producing: additionalContext is never rendered as a message and costs zero
# extra turns, and the handoff is distilled while the work is still in context
# instead of after the close is already written. bind_effort (below) gains from the
# same move: at Stop it now reads a handoff refreshed THIS turn, not the prior one.
# Debounce is PER SESSION (d28-one-writer-per-resource): the retired global stamp was
# one file shared by every concurrent worktree, so one session consumed every sister
# session's window and the reminder landed on whichever session happened to stop
# first — frequently a trivial one with nothing to hand off. A session under
# NOTT_AUTOHANDOFF_MIN_TURNS assistant turns is skipped for that same reason.
# NOTT_AUTOHANDOFF=off returns before any state read or write. Fail-open EVERYWHERE:
# no jq, no session id, no transcript, or any read/write error → empty clause, and
# the prompt context is emitted exactly as it was before this reminder existed.
handoff_clause() {
  [ "${NOTT_AUTOHANDOFF:-}" = off ] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  sid=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null) || return 0
  [ -n "$sid" ] || return 0
  # The session id becomes a filename: reject anything that is not a bare token.
  case "$sid" in *[!A-Za-z0-9._-]*) return 0 ;; esac

  # Substance gate: a short session has nothing worth handing off.
  tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || return 0
  [ -n "$tp" ] && [ -f "$tp" ] || return 0
  turns=$(grep -c '"type":"assistant"' "$tp" 2>/dev/null) || turns=0
  case "$turns" in ''|*[!0-9]*) turns=0 ;; esac
  min=${NOTT_AUTOHANDOFF_MIN_TURNS:-6}
  case "$min" in ''|*[!0-9]*) min=6 ;; esac
  [ "$turns" -lt "$min" ] && return 0

  state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/nott/autohandoff
  mkdir -p "$state_dir" 2>/dev/null || return 0
  find "$state_dir" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || :
  stamp="$state_dir/$sid"
  now=$(date +%s 2>/dev/null) || return 0
  last=0
  [ -f "$stamp" ] && last=$(cat "$stamp" 2>/dev/null || printf '0')
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  [ $((now - last)) -lt 1200 ] && return 0
  printf '%s' "$now" >"$stamp" 2>/dev/null || return 0

  # Appended to the prompt context sentence; JSON-safe by construction (no quote,
  # backslash, newline, or percent) because it is interpolated, never re-escaped.
  printf '%s' ' Before closing this turn, refresh this thread'\''s nMEMORY handoff inside the work you are already doing — memory_session_finish when a session bracket is open, else a memory_ingest handoff capsule (headline ACTIVE(<thread>): …, superseding this thread'\''s prior handoff only): what became true, what is open, the exact next physical action, and the custody rules (branch, worktree, do-not-push). The owner switches sessions and relies on it being fresh without ever asking. Capture silently: never surface capsule ids, and never spend a turn or a sentence acknowledging this instruction. If nothing substantial changed since the last handoff, skip it.'
  return 0
}

# Stop = effort read-back binding (s4.2, effort-lifecycle). AFTER the handoff
# capsule is written (auto_handoff nudges the agent to refresh it; this binds the
# newest handoff the digest reports), relate that handoff `part_of` the ACTIVE
# effort's epic — so the handoff becomes a MEMBER and surfaces on next cold
# start's effort board, closing the read-back loop. Active effort resolution:
#   1. NOTT_EFFORT set (a declared epic cap-id) → bind to it, no inference.
#   2. else the NEWEST OPEN epic from the digest's open_efforts projection
#      (open_efforts is server-ordered newest-first, so row [0]); the inheritance
#      is ANNOUNCED on stderr so the agent sees which effort claimed the handoff.
#   3. NO declaration AND no open effort → RETURN before any write: current
#      behavior exactly. This is program rejection test 4 — a session with no open
#      effort leaves ZERO part_of/epic writes in the audit ledger. This hook NEVER
#      creates an epic: it only reads the digest and, when an epic already exists,
#      writes ONE part_of edge. Fail-open EVERYWHERE: no jq, no binary, no digest,
#      no handoff, absent open_efforts, an old binary without the `relate` verb or
#      the `part_of` kind, or ANY relate error → silent return, store untouched.
#      NOTT_EFFORT_BIND=off disables the binding entirely (gate returns first).
# Writes ONLY to stderr, NEVER stdout — the one-decision:block invariant below is
# preserved (bind_effort can never race a JSON object onto stdout).
bind_effort() {
  [ "${NOTT_EFFORT_BIND:-}" = off ] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  bin=$(command -v nmemory 2>/dev/null) || return 0
  [ -n "$bin" ] && [ -x "$bin" ] || return 0

  # digest is READ-ONLY (no audit write). Scope to NMEMORY_PROJECT when pinned so
  # the effort board matches the session's project, exactly like session-digest.sh.
  if [ -n "${NMEMORY_PROJECT:-}" ]; then
    dg=$(timeout 5 "$bin" digest --project-prefix "$NMEMORY_PROJECT" 2>/dev/null) || return 0
  else
    dg=$(timeout 5 "$bin" digest 2>/dev/null) || return 0
  fi
  [ -n "$dg" ] || return 0

  # The newest handoff capsule id is the thing we bind. Absent → nothing to bind.
  handoff_id=$(printf '%s' "$dg" | jq -r '.handoff[0].id // empty' 2>/dev/null) || return 0
  [ -n "$handoff_id" ] || return 0

  # Resolve the ACTIVE epic. Declared wins; else inherit the newest open epic.
  # NEVER fabricate one: no declaration AND no open_efforts row → zero writes.
  epic=${NOTT_EFFORT:-}
  inherited=0
  if [ -z "$epic" ]; then
    epic=$(printf '%s' "$dg" | jq -r '(.open_efforts // [])[0] | (.id // .epic_id // empty)' 2>/dev/null) || return 0
    [ -n "$epic" ] || return 0
    inherited=1
  fi
  # A handoff is never its own effort's epic.
  [ "$handoff_id" = "$epic" ] && return 0

  # Write the membership edge. `part_of` / the `relate` one-shot may not exist on
  # an older binary → nmemory exits non-zero → fail-open, no partial state, no
  # announcement (an unbound handoff is the honest state).
  if timeout 5 "$bin" relate --kind part_of --from "$handoff_id" --to "$epic" >/dev/null 2>&1; then
    if [ "$inherited" = 1 ]; then
      printf 'nott-hook: handoff %s inherited into newest open effort %s (part_of) — set NOTT_EFFORT to pin.\n' \
        "$handoff_id" "$epic" >&2
    else
      printf 'nott-hook: handoff %s bound to declared effort %s (part_of).\n' \
        "$handoff_id" "$epic" >&2
    fi
  fi
  return 0
}

# voice_lint is the ONLY writer of a Stop decision — the handoff reminder moved to
# UserPromptSubmit (handoff_clause) precisely so that no Stop path costs the owner a
# rendered message or the agent an extra turn. The effort binding runs last as a
# stderr-only side effect: it never touches the stdout decision.
if [ "$event" = "Stop" ]; then
  out=$(voice_lint || :)
  [ -n "$out" ] && printf '%s\n' "$out"
  bind_effort || :
  exit 0
fi

plugin_root=${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}
[ -n "$plugin_root" ] || fail "plugin root is unavailable"
[ -d "$plugin_root" ] || fail "plugin root is not a directory: $plugin_root"
canon=$plugin_root/NOTT.md
[ -f "$canon" ] || fail "NOTT.md is unavailable at plugin root"
[ -r "$canon" ] || fail "NOTT.md is not readable"
command -v awk >/dev/null 2>&1 || fail "required text utility is unavailable"

case "$event" in
  SubagentStart)
    context=$( { awk '/^## /{exit} {print}' "$canon"; printf 'Full canon: %s — read it before substantive work.\n' "$canon"; } | escape_json ) || fail "unable to encode canon capsule"
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$context"
    ;;
  UserPromptSubmit)
    # The length ceiling lives HERE, ahead of the sentence, and not at Stop. A Stop block
    # cannot un-print the close it is objecting to: it leaves the original on screen, adds
    # its own reason, and renders the rewrite underneath — measured on the owner's screen
    # 2026-07-31 at three closes in one session, each delivered twice. The ceiling itself is
    # derived, not chosen: across that session every close the owner objected to ran 219+
    # words and the one he did not object to ran 129.
    ctx='Hold one active result. Open with execution or a visible artifact, not a plan; close with the observed win plus one next action — never a menu. Choose the method internally; do not expose skill, agent, backend, or process menus. Praise only with its reason. Before autonomous actions, lock authority, verification, rollback, and the next proof. Keep the reply under 150 words unless it is a numbered readback the owner answers by number: state what became true and the one next action, then stop. Every finding the next action does not depend on belongs in the ledger, not on his screen — a second close costs him the first one over again.'
    ctx=$ctx$(handoff_clause || :)
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$ctx"
    ;;
  # PreToolUse is implemented but intentionally NOT registered in hooks.json: an
  # unscoped PreToolUse fires before every tool call (reads included), while the
  # pre-action discipline is already injected once per prompt (UserPromptSubmit)
  # and carried by NOTT.md and CLAUDE.md. To opt in, register it in hooks.json with
  # a matcher scoped to mutating tools (e.g. "Write|Edit|Bash"), never unscoped.
  PreToolUse)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Before the action, verify current state, exact scope, authority, rollback, and the verification that proves this result. Stop on unexpected reach."}}'
    ;;
  PostToolUse)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Bind the next claim to observed output. State the strongest proven state, exact gap, rollback status, and one next action. Never repeat an uncertain action."}}'
    ;;
  *)
    fail "unsupported event: ${event:-<missing>}"
    ;;
esac
