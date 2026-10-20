#!/usr/bin/env -S bash -p
# law-contract — run the law's own contract the moment the law is edited.
#
# WHAT THIS PROTECTS AGAINST: the agent's SLIP, never an agent that circumvents.
# It reads the tool payload it is handed; edits through another route still need
# explicit verification. Automatic Git commit gates are retired.
#
# WHY IT EXISTS: on 2026-08-27 the law was edited, committed and pushed while
# plugin/tests/system-prompt-contract.sh — already written, already green, already
# proving its own falsifiability — was never run. It would have caught two of the
# five defects an independent review found afterwards, in under a second.
# The mechanism was never missing. The trigger was.
set -uo pipefail

payload=$(cat)
# WITHOUT jq THIS HOOK READS NOTHING AND SAYS SO. Absent, the path came back empty and the next
# line exited 0 — the only automatic trigger of the law contract ran nothing and reported success,
# which is the fail-open direction. It cannot refuse a commit from here, so it says it is blind.
# The guard is on the CALL, not on `command -v`: a jq that exists and fails answers `command -v`
# perfectly well, and the empty path it returns is indistinguishable from a payload with no file.
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null) || {
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"jq did not run, so the law-contract trigger could not read which file was edited and did NOT check anything. Run plugin/tests/system-prompt-contract.sh by hand before committing."}}\n'
  exit 0
}
[ -n "$path" ] || exit 0
resolved=$(realpath -m -- "$path" 2>/dev/null) || resolved=$path
root=$resolved
while [ "$root" != / ]; do
  root=$(dirname -- "$root")
  [ -f "$root/plugin/tests/system-prompt-contract.sh" ] && break
done
[ -f "$root/plugin/tests/system-prompt-contract.sh" ] || exit 0
# AND THAT ROOT MUST BE A CHECKOUT OF THE REPOSITORY THIS HOOK WAS LOADED FROM. Without this line
# the hook runs whatever plugin/tests/*.sh a foreign clone ships, as the user, on the first edit
# there — a new execution surface, named by the round-2 review of PR #198. Worktrees of one
# repository share `--git-common-dir`; a foreign clone never does. A root that is not a git
# repository at all (the contract's scratch fixtures) is refused the same way, unless the hook
# itself was loaded from a tree with no git — which is the only way the contract can drive it.
loaded_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
loaded_common=$(git -C "$loaded_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || loaded_common=''
edited_common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || edited_common=''
if [ -n "$loaded_common" ]; then
  [ "$edited_common" = "$loaded_common" ] || exit 0
fi
pdir=$root/plugin
case "$resolved" in
  "$pdir/NOTT.md"|"$pdir/tests/system-prompt-contract.sh"|"$pdir/tests/system-prompt-contract-self-test.sh")
    contract="$pdir/tests/system-prompt-contract.sh"; target="$pdir/NOTT.md"; marker='system-prompt-contract: GREEN' ;;
  "$root/CLAUDE.md"|"$pdir/tests/claude-md-contract.sh"|"$pdir/tests/claude-md-contract-self-test.sh")
    contract="$pdir/tests/claude-md-contract.sh"; target="$root/CLAUDE.md"; marker='claude-md-contract: GREEN' ;;
  "$pdir/skills/plan/references/campaign-loop.md"|"$pdir/skills/plan/SKILL.md"|"$pdir/tests/plan-skill-contract.sh"|"$pdir/tests/plan-skill-contract-self-test.sh")
    contract="$pdir/tests/plan-skill-contract.sh"; target="$pdir/skills/plan/SKILL.md"; marker='plan-skill-contract: GREEN' ;;
  *) exit 0 ;;
esac
[ -x "$contract" ] || [ -f "$contract" ] || exit 0
# THE SELF-TEST LEG IS GONE, not given a bigger budget. Measured: it takes 45s against this hook's
# 15s timeout, so it was killed on EVERY edit and a RED self-test could never reach the agent — the
# kill looked exactly like the silent green path. A 45s hook on every Write would also be a tax on
# every edit in the repository. This trigger's job is fast feedback on the LAW; the self-test is the
# explicit verification's job; commits do not run it automatically.
# EXIT 0 IS NOT PROOF THAT THE CONTRACT RAN, and this line judged by exit status alone in a plain
# `bash`. Measured: with `BASH_ENV=<file containing exit 0>` the contract exits 0 with ZERO bytes —
# bash sources $BASH_ENV before line 1, so the contract self-seal at system-prompt-contract.sh:23
# never runs — and the old `&& exit 0` declared the law edit clean. The `bash -p` shebang protects
# THIS file, never the child it spawns. So the child is launched with the launcher scrubbed and
# green is accepted only in the contract OWN WORDS, which only a run that reached its last line
# prints. The marker alone is not enough either: a BASH_ENV that PRINTS the marker and exits 0
# forges it without one line of the contract running — measured. Both halves are load-bearing.
# The variables are UNSET for the child rather than running it under `-p`: privileged mode
# makes the contract skip its own re-exec, and
# a box with POSIXLY_CORRECT set would then get a syntax error instead of a verdict.
# REACH ON 2026-08-30: BASH_ENV is not set in this environment. Latent hazard, cure available.
out=$(env -u BASH_ENV -u ENV -u SHELLOPTS bash "$contract" "$target" 2>&1)
case "$out" in *"$marker"*) exit 0 ;; esac

# RED: hand the failures straight back, so the next turn cannot proceed unaware.
context=$(printf 'A law contract (%s) did not establish GREEN after this edit. Preserve the diagnostic and block only acceptance that depends on this contract. Continue independent authorized work. This feedback does not expand repair scope.\n%s' "$(basename "$contract")" "$out" \
  | jq -Rs .)
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$context"
exit 0
