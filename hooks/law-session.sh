#!/usr/bin/env -S bash -p
# law-session — SessionStart: the plugin carries its own law.
#
# Measured 2026-09-15 with `claude plugin eval` (case "quote the sentence that begins
# with 'Stop only the act'"): a plugin loaded by --plugin-dir puts skills, hooks and
# MCP in front of the model but NOT NOTT.md — the law only reached real
# sessions through the owner's `--append-system-prompt-file` flag, and reached the
# eval harness never. Every "with plugin" measurement before this hook measured hooks,
# skills and the memory note, not the law. The harness's own `append_system_prompt`
# applies to BOTH ablation arms, so it cannot measure the law either.
#
# This hook emits the law as SessionStart context: with the plugin the model quotes
# it (1/1), without it it does not (0/1). It fires on startup, resume, clear, compact
# and fork, so a compaction re-injects it.
#
# It emits it in PARTS. Claude Code 2.1.283 (measured 2026-09-26) judges each hook's
# output alone and hands the model a 2 KB preview of one over 10,000 characters; from
# abd23bbbe (2026-09-18) the law was over that, and a session without the flag saw only
# its first ~2 KB. So hooks.json binds `law-session.sh N` once per part, and part N is
# the whole `## ` sections of NOTT.md that pack, in order, into the Nth output under the
# limit; a part past the last prints nothing. The host lists the parts in the order they
# finish, so each names itself. A session that appends the law itself sets
# NOTT_LAW_SESSION=off to silence every part (nSPAWN does it for its children).
set -uo pipefail
[ "${NOTT_LAW_SESSION:-on}" = off ] && exit 0
root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
law=$root/NOTT.md
[ -r "$law" ] || exit 0
exec python3 - "$law" "${1:-0}" <<'PY'
import re, sys

LIMIT = 10_000  # per hook output, counted as the host counts: UTF-16 units
law, want = open(sys.argv[1], encoding="utf-8").read(), int(sys.argv[2])
head = "[NOTT plugin · SessionStart hook law-session.sh — the plugin's law, in force for this session, part {} of {}]\n\n"


def units(text: str) -> int:
    return len(text.encode("utf-16-le")) // 2


room = LIMIT - units(head.format(99, 99))
cuts = [m.start() for m in re.finditer(r"(?m)^## ", law)]
parts = [""]
for start, end in zip([0, *cuts], [*cuts, len(law)]):
    if parts[-1] and units(parts[-1] + law[start:end]) > room:
        parts.append("")
    parts[-1] += law[start:end]
if 1 <= want <= len(parts):
    sys.stdout.buffer.write((head.format(want, len(parts)) + parts[want - 1]).encode("utf-8"))
PY
