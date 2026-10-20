#!/usr/bin/env -S bash -p
# secret-in-output — PostToolUse and PostToolUseFailure on Bash: two advisory scans of the
# command's output in one process (it took in chained-after-finding.sh).
#
# 1. CHAIN CUT. A gate that finds something exits 3 (D18: 0 satisfied, 1 operational, 2
# refused, 3 findings). `gate && next` therefore never runs `next` on a finding, but the
# transcript shows one tool call, and a reader who did not track the exit code reads the
# missing output of `next` as "nothing to report" (measured 2026-09-14 in the reform's eval
# runs). When the command carries ` && ` and the output shows a finding shape (`exit=3`,
# `rc=3`, `: RED (`, `findings: exit 3`), one sentence says the chain stopped there. A chain
# cut by a finding exits 3, so the call lands in PostToolUseFailure with its text in `error`;
# hooks.json binds this script to both events and the payload's `hook_event_name` is echoed.
#
# 2. CREDENTIAL. A credential that came back in the OUTPUT is named, never quoted. The law
# (NOTT.md, "Keep secrets out of prompts, output, artifacts") loses its grip the moment
# `cat config.env` lands in the transcript; the model then tends to repeat the line in its
# answer. Shapes: secret-shapes.sh, shared with the argv guard. The advisory names the KIND
# (name=value, flag, Bearer, sk-key) and never the value.
#
# ADVISORY ONLY: Claude does not let a hook alter a Bash result, so both findings are one
# additionalContext, exit 0. `tool_response` is read as {stdout,stderr} on Claude, as a string
# on the Codex projection. Fail-OPEN: bad JSON, non-Bash -> exit 0 silent.
set -uo pipefail

payload=$(cat)
printf '%s' "$payload" | jq -e . >/dev/null 2>&1 || exit 0
[ "$(printf '%s' "$payload" | jq -r '.tool_name // ""')" = Bash ] || exit 0
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // "PostToolUse"')
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
output=$(printf '%s' "$payload" | jq -r '(.tool_response
  | if type == "object" then ((.stdout // "") + "\n" + (.stderr // "")) else tostring end)
  + "\n" + (.error // "" | tostring)')

said=()
# finish: every advisory found so far, joined in one additionalContext; silence without one.
finish() {
  [ "${#said[@]}" -eq 0 ] || jq -cn --arg e "$event" --arg m "${said[*]}" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$m}}'
  exit 0
}

# A here-string, not a pipe: under pipefail `grep -q` SIGPIPEs a long writer and reads as no match.
case "$cmd" in *' && '*)
  grep -qE '(exit=3|rc=3|: RED \(|findings: exit 3)' <<<"$output" \
    && said+=('chained-after-finding: the output shows a D18 finding (exit 3) and the command was chained with `&&`, so the chain stopped at that finding and the later commands did not run — name the finding; do not read their absent output as green.')
  ;;
esac

here=$(dirname "${BASH_SOURCE[0]}")
. "$here/secret-shapes.sh" 2>/dev/null || finish
# 2026-09-21: these four probes were `grep -qP` directly. On a box whose grep is BSD grep
# every one of them exits 2, no branch is taken, and the hook exits 0 having looked at
# nothing — a leaked credential passed unnamed, in silence. pcre.sh resolves an engine
# that actually speaks PCRE; the statuses it returns are grep's, unchanged.
. "$here/pcre.sh" 2>/dev/null || finish

# An advisory hook fails open by design — but «I could not look» is not «I looked and saw
# nothing», and the owner has to hear the difference. Saying so once per call is the price
# of not pretending the output was scanned.
[ -n "$pcre_engine" ] || { said+=("secret-in-output: the output was NOT scanned for credentials — no PCRE engine on this box (this \`grep\` has no -P, and \`perl\` is absent). Treat any credential-shaped literal in it as unguarded."); finish; }

# Resolving an engine only covers «no engine». Once one is chosen a probe can still ERROR —
# a shape that does not compile, an engine that dies — and every such probe returns non-zero,
# which the `elif` chain reads as «did not match» (review, 2026-09-21: the chain fell through,
# $kind stayed empty and the hook exited 0, the same silence as a clean output). `probe`
# keeps the three statuses apart and remembers that a look FAILED.
broke=0
probe() { # pcre_fn RE...  : 0 match, 1 no match; a status above 1 is recorded, never «no»
  printf '%s' "$output" | drain "$@"
  local r=$?
  [ "$r" -gt 1 ] && { broke=1; return 1; }
  return $r
}
probe_sk() { # the two-stage row: EITHER stage erroring is a failed look
  printf '%s' "$output" | pcre_ol "$secret_sk_re" | drain pcre_qvl "$secret_sk_fixture_re"
  local st=("${PIPESTATUS[@]}")
  { [ "${st[1]}" -gt 1 ] || [ "${st[2]}" -gt 1 ]; } && { broke=1; return 1; }
  return "${st[2]}"
}

kind=""
if probe pcre_ql "$secret_name_re"; then kind='NAME=value'
elif probe pcre_ql "$secret_flag_re"; then kind='credential flag'
elif probe pcre_qil "$secret_bearer_re"; then kind='Bearer token'
elif probe_sk; then kind='sk-<vendor>- key'
fi

# A named credential outranks a broken probe: say the strongest true thing.
if [ -n "$kind" ]; then
  said+=("secret-in-output: the command output carried a credential-shaped literal ($kind). Do not quote it in your answer or persist it; if it is real, say so and treat it as leaked.")
elif [ "$broke" -ne 0 ]; then
  said+=("secret-in-output: the output was NOT scanned for credentials — a credential shape failed to compile or the PCRE engine errored. Treat any credential-shaped literal in it as unguarded.")
fi
finish
