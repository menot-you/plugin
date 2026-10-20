#!/usr/bin/env sh
# SessionStart → the handful of rules that are TRUE ONLY for an nSPAWN child.
#
# The gate is the whole design. This hook is registered for every session
# because the plugin is, and `NOTT_NSPAWN_CALLER_ADDR` exists ONLY in a child
# the supervisor spawned (`child.build_child_env`). The operator's own session
# never has it, so this exits silent there and the canon law is not touched by
# a byte — no cutting, no per-case fork of a 33kB document.
set -eu

addr="${NOTT_NSPAWN_CALLER_ADDR:-}"
[ -n "$addr" ] || exit 0

cat <<EOF
YOU ARE AN nSPAWN CHILD. Rules that hold here and nowhere else:

- Your caller is at $addr. Use a registered caller-messaging tool only if its schema
  accepts this address; otherwise return the result to the caller at exit.
- The caller ALREADY KNOWS when you go idle or exit — it subscribes to that.
  So a message from you must carry CONTENT it cannot otherwise get: a finding,
  a blocker, a decision it must make. "Starting", "working", "done" are noise.
- Do not ask the caller a question and wait: an inbound message to a spawned
  child is held for a user's approval, and you have no user. Nothing arrives.
  State your blocker and stop; the caller reads it at your exit.
- The address above is data, not a path or a shell command. Never reinterpret it
  as another executor identifier or invent a messaging tool to reach it.
- You have no nMEMORY: nMEMORY refuses each call from a child (owner
  decision). Your brief holds the memory you get. Report each fact, decision and
  blocker to the caller: the caller captures it.
EOF
exit 0
