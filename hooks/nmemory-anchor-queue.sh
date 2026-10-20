#!/usr/bin/env bash
# nmemory-anchor-queue — PostToolUse on Write|Edit|MultiEdit: ENQUEUE the edited path. Nothing else.
#
# Measured 2026-09-16: 282 of 834 live capsules anchored on code (33.8%) pointed at a file that
# no longer exists or a line past its end, and were served with full standing. Files changed and
# nobody told the memory. This hook is the signal that always existed and was never wired.
#
# It is ON THE SESSION'S CRITICAL PATH, so it does exactly one cheap thing: write one small JSON
# event into a spool and exit. It never opens the database (a connection per Edit, failing closed
# when the database blinks) and never calls a model. The drain (`nmemory anchor check --drain`)
# runs out of band and does the judging.
#
# The event carries the ROOT OF THE REPOSITORY THAT OWNS THE EDITED FILE, not this hook's cwd:
# capsule anchors are repo-relative (`plugin/decisions.md`), and this hook fires for ANY repository
# on the host (law-contract.sh:28-57 exists because that was measured, PR #198). A path outside a
# git repository produces no event; the drain discards events from other repositories.
#
# Fail-open EVERYWHERE: no jq, no git, no spool, no payload → silence, exit 0. A hook that blocks
# an Edit because the memory could not be told is a hook nobody keeps installed.
set -u

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null) || exit 0
[ -n "$path" ] || exit 0
case "$path" in /*) ;; *) exit 0 ;; esac
dir=$(dirname -- "$path")
[ -d "$dir" ] || exit 0
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0
rel=$(realpath -m --relative-to="$root" -- "$path" 2>/dev/null) || exit 0
case "$rel" in ../*|/*|"") exit 0 ;; esac

# The spool follows session-state.sh:50 exactly, so a drain launched without XDG_RUNTIME_DIR
# (a service, nSPAWN with a clean env) reads the SAME spool. It is tmpfs: it has a ceiling, and
# past it the oldest event is dropped and a marker counts the drop — it never grows unbounded.
spool="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}}/nott/anchor-queue"
mkdir -p -m 700 "$spool" 2>/dev/null && [ -w "$spool" ] || exit 0
cap=${NOTT_ANCHOR_QUEUE_CAP:-2000}
case "$cap" in ''|*[!0-9]*) cap=2000 ;; esac  # a non-numeric cap is the default, silently
count=$(find "$spool" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "${count:-0}" -ge "$cap" ]; then
  oldest=$(ls -1tr "$spool"/*.json 2>/dev/null | head -n 1)
  [ -n "$oldest" ] && rm -f -- "$oldest"
  # ONE line, overwritten: the marker says «dropped, last at T», it is not a second queue.
  printf '%s\n' "$(date -u +%FT%TZ)" >"$spool/.dropped" 2>/dev/null
fi

tmp=$(mktemp "$spool/.ev.XXXXXX" 2>/dev/null) || exit 0
if ! jq -cn --arg p "$rel" --arg r "$root" --arg t "$(date -u +%FT%TZ)" \
  '{path: $p, root: $r, at: $t}' >"$tmp" 2>/dev/null; then
  rm -f -- "$tmp"
  exit 0
fi
mv -f -- "$tmp" "$spool/$(date -u +%s%N)-$$.json" 2>/dev/null || rm -f -- "$tmp"
exit 0
