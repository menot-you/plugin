#!/usr/bin/env bash
# hooks-test — behaviour contract for the SHIPPED plugin/hooks/nott-hook.sh.
#
# This suite asserts what the hook DOES, and every assertion is proven falsifiable
# by breaking the hook line it pins (`d39-proven-falsifiable-tests`): each property
# runs twice, once against an intact copy which MUST hold it, and once against a
# copy with one line mutated which MUST lose it. A test that has never failed
# proves nothing, and inverting an assertion is never that proof.
#
# HOST INDEPENDENCE IS PINNED, not assumed. Two ambient things reach into a Stop
# and would otherwise decide the verdict:
#   * `bind_effort` shells out to a real `nmemory` when one is on PATH, and that
#     binary creates its OWN state under XDG_STATE_HOME — so "Stop wrote no state"
#     silently measured whether the developer had nmemory installed. Every Stop
#     case below sets NOTT_EFFORT_BIND=off, which returns before any binary probe.
#   * HOME and XDG_STATE_HOME are fenced per case, so no run reads or writes the
#     developer's real state directory.
#
# WHAT THIS SUITE DELIBERATELY RECORDS AS TRUE, because it is:
#   * the ledger is UNBOUNDED — nothing trims it, and a growing file is the
#     contract until a trim ships;
#   * the session identifier and a bounded excerpt of assistant text ARE recorded.
# Asserting these honestly is the point. A suite that asserted the protections it
# wishes existed would report green while the hook did something else.
set -euo pipefail

die() { printf 'hooks-test: %s\n' "$*" >&2; exit 1; }
root=${1:-$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd -P)}
hook=$root/hooks/nott-hook.sh
[[ -x "$hook" ]] || die 'hook is not executable'
for command_name in awk grep jq mktemp seq stat wc; do
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
expected_hook_sha256=7d286ec372dc4a14ad0781a38e769e0b6506575324839c4a3fb27d4d4f3f2c74
[[ $(hash_file "$hook") == "$expected_hook_sha256" ]] || die 'hook bytes differ from the reviewed candidate'

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM
mkdir -p "$scratch/home"

status=0
cases_run=0
PROPERTIES_TOTAL=16

verdict() {
  cases_run=$((cases_run + 1))
  if [[ "$2" == "$3" ]]; then
    printf 'hooks-test: PASS [%s] property %s\n' "$1" "$3"
  else
    printf 'hooks-test: FAIL [%s] expected the property %s, got %s\n' "$1" "$2" "$3" >&2
    status=1
  fi
}

# stage ID [ANCHOR REPLACEMENT] -> path to a scratch copy of the hook. The mutation
# is a whole-file literal substitution CONFIRMED to have landed: the anchor MUST be
# present before, the replacement present after, and the anchor gone after — a
# mutation that silently no-ops hands back a false green. Every anchor is ONE line,
# because grep -F reads a newline inside a pattern as two alternatives and a
# multi-line anchor can never be confirmed gone.
stage() {
  local id="$1" anchor="${2:-}" replacement="${3:-}"
  local dir="$scratch/mut/$id" copy before after
  mkdir -p "$dir"
  copy="$dir/nott-hook.sh"
  cp -- "$hook" "$copy"
  chmod +x "$copy"
  if [[ -n "$anchor" ]]; then
    grep -qF -- "$anchor" "$copy" || { printf 'hooks-test: [%s] anchor absent before\n' "$id" >&2; return 1; }
    before="$(cat -- "$copy")"
    after="${before//"$anchor"/"$replacement"}"
    printf '%s\n' "$after" >"$copy"
    grep -qF -- "$replacement" "$copy" || { printf 'hooks-test: [%s] replacement absent after\n' "$id" >&2; return 1; }
    if grep -qF -- "$anchor" "$copy"; then
      printf 'hooks-test: [%s] anchor survived — the edit no-opped\n' "$id" >&2
      return 1
    fi
  fi
  printf '%s' "$copy"
}

transcript() { jq -cn --arg t "$2" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' >"$1"; }

noisy=$scratch/noisy.jsonl
clean=$scratch/clean.jsonl
transcript "$noisy" 'Amazing? Or prefer another path?'
transcript "$clean" 'done.'
session=SESSMARKER4C20
noisy_payload=$(jq -cn --arg path "$noisy" --arg s "$session" '{transcript_path:$path,session_id:$s,stop_hook_active:false}')
clean_payload=$(jq -cn --arg path "$clean" --arg s "$session" '{transcript_path:$path,session_id:$s,stop_hook_active:false}')

stop_out=''
stop_err=''
stop_run() {
  local copy="$1" state="$2" body="$3" err
  shift 3
  err="$scratch/stderr.$$.$RANDOM"
  stop_out="$(env HOME="$scratch/home" XDG_STATE_HOME="$state" NOTT_EFFORT_BIND=off "$@" \
    "$copy" Stop <<<"$body" 2>"$err")" || true
  stop_err="$(cat "$err")"
}
ledger_of() { printf '%s/nott/voice-lint.jsonl' "$1"; }

p1() {
  local state="$scratch/s1-$RANDOM" log
  stop_run "$1" "$state" "$noisy_payload"
  log=$(ledger_of "$state")
  if [[ -z "$stop_out" && -z "$stop_err" && -f "$log" && $(wc -l <"$log") -eq 1 ]]; then printf held; else printf lost; fi
}

p2() {
  local state="$scratch/s2-$RANDOM" log
  stop_run "$1" "$state" "$noisy_payload"
  log=$(ledger_of "$state")
  if [[ -f "$log" ]] && jq -e 'keys | sort == ["evidence","findings","mode","session_id","ts"]' "$log" >/dev/null 2>&1; then
    printf held
  else
    printf lost
  fi
}

# The retired suite asserted the OPPOSITE — that no session identity was stored.
# It is stored, PRIVACY.md now says so, and this pins the fact so the document and
# the code cannot drift apart again.
p3() {
  local state="$scratch/s3-$RANDOM" log
  stop_run "$1" "$state" "$noisy_payload"
  log=$(ledger_of "$state")
  if [[ -f "$log" ]] && [[ $(jq -r '.session_id' "$log" 2>/dev/null) == "$session" ]]; then printf held; else printf lost; fi
}

p4() {
  local state="$scratch/s4-$RANDOM" log ev pad
  pad=$(printf 'x%.0s' $(seq 1 600))
  transcript "$scratch/long.jsonl" "Amazing? Or prefer another path? $pad"
  local body; body=$(jq -cn --arg path "$scratch/long.jsonl" --arg s "$session" \
    '{transcript_path:$path,session_id:$s,stop_hook_active:false}')
  stop_run "$1" "$state" "$body"
  log=$(ledger_of "$state")
  [[ -f "$log" ]] || { printf lost; return; }
  ev=$(jq -r '.evidence' "$log" 2>/dev/null) || { printf lost; return; }
  if [[ -n "$ev" && ${#ev} -le 240 ]]; then printf held; else printf lost; fi
}

p5() {
  local state="$scratch/s5-$RANDOM"
  stop_run "$1" "$state" "$clean_payload"
  if [[ -z "$stop_out" && ! -e "$(ledger_of "$state")" ]]; then printf held; else printf lost; fi
}

# Asserted as GROWTH, honestly: no trim exists, so "bounded to N records" would be
# a wish rather than a contract.
p6() {
  local state="$scratch/s6-$RANDOM" log i
  for i in 1 2 3; do stop_run "$1" "$state" "$noisy_payload"; done
  log=$(ledger_of "$state")
  if [[ -f "$log" && $(wc -l <"$log") -eq 3 ]]; then printf held; else printf lost; fi
}

# The block BEHAVIOUR was withdrawn (cap-946); the mode survives only as a field.
p7() {
  local state="$scratch/s7-$RANDOM" log
  stop_run "$1" "$state" "$noisy_payload" NOTT_VOICE_LINT_MODE=block
  log=$(ledger_of "$state")
  if [[ -z "$stop_out" && -f "$log" ]] && [[ $(jq -r '.mode' "$log") == block ]]; then printf held; else printf lost; fi
}

p8() {
  local state="$scratch/s8-$RANDOM" body
  body=$(jq -cn --arg path "$scratch/missing.jsonl" --arg s "$session" \
    '{transcript_path:$path,session_id:$s,stop_hook_active:false}')
  stop_run "$1" "$state" "$body"
  if [[ -z "$stop_out" && -z "$stop_err" && ! -e "$(ledger_of "$state")" ]]; then printf held; else printf lost; fi
}

handoff_run() {
  local copy="$1" state="$2" body="$3"
  shift 3
  env HOME="$scratch/home" XDG_STATE_HOME="$state" CLAUDE_PLUGIN_ROOT="$root" "$@" \
    "$copy" UserPromptSubmit <<<"$body" 2>/dev/null || true
}
long_transcript=$scratch/turns.jsonl
: >"$long_transcript"
for _ in $(seq 1 8); do
  jq -cn '{type:"assistant",message:{content:[{type:"text",text:"t"}]}}' >>"$long_transcript"
done
handoff_payload=$(jq -cn --arg path "$long_transcript" --arg s "$session" '{transcript_path:$path,session_id:$s}')
has_reminder() { printf '%s' "$1" | jq -e '.hookSpecificOutput.additionalContext | contains("refresh this thread")' >/dev/null 2>&1; }

p9() {
  local state="$scratch/s9-$RANDOM" out stamp
  out=$(handoff_run "$1" "$state" "$handoff_payload")
  stamp="$state/nott/autohandoff/$session"
  if [[ -f "$stamp" ]] && [[ $(cat "$stamp") =~ ^[0-9]+$ ]] && has_reminder "$out"; then printf held; else printf lost; fi
}

p10() {
  local state="$scratch/s10-$RANDOM" out body
  transcript "$scratch/short.jsonl" 'one turn'
  body=$(jq -cn --arg path "$scratch/short.jsonl" --arg s "$session" '{transcript_path:$path,session_id:$s}')
  out=$(handoff_run "$1" "$state" "$body")
  if [[ ! -e "$state/nott/autohandoff" ]] && ! has_reminder "$out"; then printf held; else printf lost; fi
}

p11() {
  local state="$scratch/s11-$RANDOM" body
  body=$(jq -cn --arg path "$long_transcript" --arg s '../escape me' '{transcript_path:$path,session_id:$s}')
  handoff_run "$1" "$state" "$body" >/dev/null
  if [[ ! -e "$state/nott/autohandoff" ]]; then printf held; else printf lost; fi
}

p12() {
  local state="$scratch/s12-$RANDOM" out
  out=$(handoff_run "$1" "$state" "$handoff_payload" NOTT_AUTOHANDOFF=off)
  if [[ ! -e "$state/nott/autohandoff" ]] && ! has_reminder "$out"; then printf held; else printf lost; fi
}

p13() {
  local state="$scratch/s13-$RANDOM" second
  handoff_run "$1" "$state" "$handoff_payload" >/dev/null
  second=$(handoff_run "$1" "$state" "$handoff_payload")
  if ! has_reminder "$second"; then printf held; else printf lost; fi
}

p14() {
  local copy="$1" event out
  for event in SubagentStart UserPromptSubmit PostToolUse PreToolUse; do
    out=$(env CLAUDE_PLUGIN_ROOT="$root" HOME="$scratch/home" NOTT_AUTOHANDOFF=off \
      "$copy" "$event" <<<'{}' 2>/dev/null) || { printf lost; return; }
    printf '%s' "$out" | jq -e --arg event "$event" \
      '.hookSpecificOutput.hookEventName == $event' >/dev/null 2>&1 || { printf lost; return; }
  done
  printf held
}

p15() {
  local out
  out=$(env CLAUDE_PLUGIN_ROOT="$root" HOME="$scratch/home" "$1" SubagentStart <<<'{}' 2>/dev/null) || { printf lost; return; }
  if printf '%s' "$out" | jq -e --arg canon "$root/NOTT.md" \
       '.hookSpecificOutput.additionalContext | contains("one witnessed deliverable") and contains("Full canon: " + $canon)' >/dev/null 2>&1; then
    printf held
  else
    printf lost
  fi
}

p16() {
  local st
  set +e
  env CLAUDE_PLUGIN_ROOT="$root" HOME="$scratch/home" "$1" Unsupported <<<'{}' \
    >"$scratch/unsup.out" 2>"$scratch/unsup.err"
  st=$?
  set -e
  if [[ "$st" -eq 2 && ! -s "$scratch/unsup.out" && $(wc -l <"$scratch/unsup.err") -eq 1 ]]; then printf held; else printf lost; fi
}

APPEND_LINE='    "$ts" "$sid" "$mode" "$findings" "$ev" >>"$state_dir/voice-lint.jsonl" 2>/dev/null || return 0'

d="$(stage p1-intact)" && verdict "P1 a lint-tripping Stop appends one ledger line and emits nothing" held "$(p1 "$d")"
d="$(stage p1-mutant "$APPEND_LINE" '    : "$ts" "$sid" "$mode" "$findings" "$ev" || return 0')" \
  && verdict "P1 red: the ledger append is removed" lost "$(p1 "$d")"

d="$(stage p2-intact)" && verdict "P2 the recorded line carries exactly five fields" held "$(p2 "$d")"
d="$(stage p2-mutant \
  '  printf '\''{"ts":"%s","session_id":"%s","mode":"%s","findings":"%s","evidence":"%s"}\n'\'' \' \
  '  printf '\''{"ts":"%s","mode":"%s","findings":"%s","evidence":"%s"}\n'\'' \')" \
  && verdict "P2 red: a field is dropped from the recorded schema" lost "$(p2 "$d")"

d="$(stage p3-intact)" && verdict "P3 the session identifier is recorded verbatim" held "$(p3 "$d")"
d="$(stage p3-mutant \
  '  sid=$(printf '\''%s'\'' "$payload" | jq -r '\''.session_id // "unknown"'\'' 2>/dev/null) || sid=unknown' \
  '  sid=redacted')" \
  && verdict "P3 red: the session identifier is replaced before recording" lost "$(p3 "$d")"

d="$(stage p4-intact)" && verdict "P4 evidence is present and bounded to 240 bytes" held "$(p4 "$d")"
d="$(stage p4-mutant \
  '  ev=$(printf '\''%s'\'' "$tail_para" | tail -c 240 | escape_json) || ev='\'''\' \
  '  ev=$(printf '\''%s'\'' "$tail_para" | tail -c 4000 | escape_json) || ev='\'''\')" \
  && verdict "P4 red: the evidence excerpt loses its bound" lost "$(p4 "$d")"

d="$(stage p5-intact)" && verdict "P5 a clean close writes no ledger at all" held "$(p5 "$d")"
d="$(stage p5-mutant '  [ -n "$findings" ] || return 0' '  [ -n "$findings" ] || findings=forced')" \
  && verdict "P5 red: the no-findings guard stops guarding" lost "$(p5 "$d")"

d="$(stage p6-intact)" && verdict "P6 the ledger is unbounded — three trips leave three lines" held "$(p6 "$d")"
d="$(stage p6-mutant "$APPEND_LINE" \
  '    "$ts" "$sid" "$mode" "$findings" "$ev" >"$state_dir/voice-lint.jsonl" 2>/dev/null || return 0')" \
  && verdict "P6 red: the append becomes a truncating write" lost "$(p6 "$d")"

d="$(stage p7-intact)" && verdict "P7 block mode is recorded and still silent" held "$(p7 "$d")"
d="$(stage p7-mutant '  mode=${NOTT_VOICE_LINT_MODE:-warn}' '  mode=warn')" \
  && verdict "P7 red: the mode field stops reflecting the environment" lost "$(p7 "$d")"

d="$(stage p8-intact)" && verdict "P8 a Stop with no usable transcript writes nothing" held "$(p8 "$d")"
# The mutant makes the guard CREATE the ledger instead of returning. A milder edit —
# pointing $tp at an existing but empty file — is absorbed by the two guards behind
# it (empty `last`, then empty `findings`) and the property survives, which would
# have reported a lethal mutation that is not one. Three redundant guards stand
# between a missing transcript and a write; this proves the FIRST is load-bearing by
# making it the thing that writes.
d="$(stage p8-mutant '  [ -f "$tp" ] || return 0' \
  '  [ -f "$tp" ] || { mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/nott" 2>/dev/null; : >"${XDG_STATE_HOME:-$HOME/.local/state}/nott/voice-lint.jsonl"; return 0; }')" \
  && verdict "P8 red: the missing-transcript guard writes instead of returning" lost "$(p8 "$d")"

d="$(stage p9-intact)" && verdict "P9 the handoff stamp is named by session and holds an epoch" held "$(p9 "$d")"
d="$(stage p9-mutant \
  '  printf '\''%s'\'' "$now" >"$stamp" 2>/dev/null || return 0' \
  '  printf '\''%s'\'' "$now" >/dev/null 2>&1 || return 0')" \
  && verdict "P9 red: the stamp is never written" lost "$(p9 "$d")"

d="$(stage p10-intact)" && verdict "P10 a session under the turn floor gets no stamp and no reminder" held "$(p10 "$d")"
d="$(stage p10-mutant '  [ "$turns" -lt "$min" ] && return 0' '  [ "$turns" -lt "$min" ] && turns=$min')" \
  && verdict "P10 red: the substance gate admits a short session" lost "$(p10 "$d")"

d="$(stage p11-intact)" && verdict "P11 a session id that is not a bare token never becomes a filename" held "$(p11 "$d")"
d="$(stage p11-mutant \
  '  case "$sid" in *[!A-Za-z0-9._-]*) return 0 ;; esac' \
  '  case "$sid" in *[!A-Za-z0-9._-]*) : ;; esac')" \
  && verdict "P11 red: the session-id character fence is removed" lost "$(p11 "$d")"

d="$(stage p12-intact)" && verdict "P12 NOTT_AUTOHANDOFF=off writes no stamp and appends no reminder" held "$(p12 "$d")"
d="$(stage p12-mutant \
  '  [ "${NOTT_AUTOHANDOFF:-}" = off ] && return 0' \
  '  [ "${NOTT_AUTOHANDOFF:-}" = never ] && return 0')" \
  && verdict "P12 red: the off switch stops being read" lost "$(p12 "$d")"

d="$(stage p13-intact)" && verdict "P13 the debounce suppresses a second reminder in the window" held "$(p13 "$d")"
d="$(stage p13-mutant \
  '  [ $((now - last)) -lt 1200 ] && return 0' \
  '  [ $((now - last)) -lt 0 ] && return 0')" \
  && verdict "P13 red: the debounce window collapses to nothing" lost "$(p13 "$d")"

d="$(stage p14-intact)" && verdict "P14 every registered event answers with its own contract" held "$(p14 "$d")"
d="$(stage p14-mutant \
  '    printf '\''{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n'\'' "$event" "$context"' \
  '    printf '\''{"hookSpecificOutput":{"hookEventName":"wrong","additionalContext":"%s"}}\n'\'' "$context"')" \
  && verdict "P14 red: an event answers under the wrong name" lost "$(p14 "$d")"

d="$(stage p15-intact)" && verdict "P15 SubagentStart carries the canon opening and the exact read path" held "$(p15 "$d")"
d="$(stage p15-mutant \
  '    context=$( { awk '\''/^## /{exit} {print}'\'' "$canon"; printf '\''Full canon: %s — read it before substantive work.\n'\'' "$canon"; } | escape_json ) || fail "unable to encode canon capsule"' \
  '    context=$( { printf '\''nothing\n'\''; } | escape_json ) || fail "unable to encode canon capsule"')" \
  && verdict "P15 red: the canon capsule stops carrying the canon" lost "$(p15 "$d")"

d="$(stage p16-intact)" && verdict "P16 an unsupported event fails closed with one diagnostic" held "$(p16 "$d")"
d="$(stage p16-mutant '    fail "unsupported event: ${event:-<missing>}"' '    exit 0')" \
  && verdict "P16 red: an unsupported event is accepted" lost "$(p16 "$d")"

if [[ "$cases_run" -ne $((PROPERTIES_TOTAL * 2)) ]]; then
  printf 'hooks-test: FAIL [suite integrity] %s of %s cases ran — a skipped case proves nothing\n' \
    "$cases_run" "$((PROPERTIES_TOTAL * 2))" >&2
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  printf 'hooks-test: pass (%s cases: %s properties, each held intact and lost under its own mutation)\n' \
    "$cases_run" "$PROPERTIES_TOTAL"
fi
exit "$status"
