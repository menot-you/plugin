#!/usr/bin/env bash
# The repository's primary checkout is the tree every spawned worker reads its
# law from ($NOTT_PLUGIN/NOTT.md). On 2026-08-29 an agent moved
# that checkout onto a lane 117 commits behind, and for a day every worker read
# a stale law with no gate wired. Owner order, same day: nothing moves that HEAD.
#
# This is PREVENTION for anything running through the Bash tool — which is every
# agent on this box. It cannot see a human typing git in a bare terminal; git has
# no pre-checkout hook, so that rung does not exist and is not claimed.
#
# THREAT MODEL: it stops an agent moving HEAD BY ACCIDENT. It reads the call's
# text, so deliberate obfuscation is out of its reach, bound or unbound: a verb in
# a variable (`c=checkout; git $c`), `eval`, an encoding, a git alias in config.
#
# Native callers bind the selected plugin source explicitly because installed
# hooks live in a cache. Other callers use this file's source tree. The guard
# acts only when that tree is the PRIMARY worktree. A lane worktree is supposed
# to sit on a lane; pinning it would break the thing the lock protects.
set -uo pipefail

allow() { exit 0; }
deny() {
  # Two channels, and only one of them works everywhere. The JSON is a PERMISSION
  # decision, which `defaultMode: bypassPermissions` skips entirely — measured
  # 2026-08-29: this hook denied the payload by hand while the same command ran.
  # `exit 2` does not route through that layer. It is the block; the JSON is
  # courtesy. `plugin/tests/branch-lock-contract.sh` asserts the exit code.
  printf '%s\n' "$1" >&2
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 2
}

plugin_root=${NOTT_NSPAWN_PLUGIN_ROOT-$(dirname "${BASH_SOURCE[0]}")/..}
[ -d "$plugin_root" ] || deny "REFUSED — the selected plugin source is unavailable."
TREE=$(cd -- "$plugin_root/.." && pwd -P) \
  || deny "REFUSED — the selected plugin repository could not be resolved."

# TEXT IS NOT A COMMAND. Measured 2026-10-19: the owner removed this lock from his
# live hooks.json because it refused his `claude -p` at the repository root; a
# verb word inside a prompt was read as a verb. Replace with `_` only the whole
# quoted argument of three text-taking commands: the prompt of `claude -p` or
# `claude --print`, the line of `state.sh set` and the message of `git commit -m`.
# A quote opens only outside another quote, so a separator inside it ends no
# segment. A double-quoted string that holds `$(` or a backtick runs a command
# and stays. A quoted string after `-c`, `eval`, `ssh` or any other command stays.
# The C locale reads bytes: in UTF-8 gawk walks every character to index a string,
# and a 360 KB command took 10 s, past the hook's timeout. Each byte it reads is ASCII.
strip_text() {  # stdin: the command text; stdout: the same text with those arguments as `_`
  LC_ALL=C awk -v RS='\001' -v sq="'" '{
    s = $0; n = length(s); out = ""; i = 1
    while (i <= n) {
      c = substr(s, i, 1)
      if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
      if (c != sq && c != "\"") { out = out c; i++; continue }
      j = i + 1; plain = 1
      while (j <= n && (d = substr(s, j, 1)) != c) {
        if (c == "\"" && d == "\\") j++
        else if (c == "\"" && (d == "`" || (d == "$" && substr(s, j + 1, 1) == "("))) plain = 0
        j++
      }
      if (j > n) { out = out substr(s, i); break }
      # Only the last 512 characters can hold the command: a longer one stays as text.
      # Other words of the same command may come between, as in `claude -p --model x`;
      # a separator or a newline ends the command.
      if (plain && substr(out, length(out) - 511) ~ /(claude([ \t]+[^ \t\n;&|]+)*[ \t]+(-p|--print)([ \t]+[^ \t\n;&|]+)*|state\.sh[ \t]+set|git[ \t]+(-C[ \t]+[^ \t\n;&|]+[ \t]+)?commit([ \t]+[^ \t\n;&|]+)*[ \t]+(-[a-zA-Z]*m|--message))[ \t]+$/)
        out = out "_"
      else out = out substr(s, i, j - i + 1)
      i = j + 1
    }
    printf "%s", out
  }'
}

# A selected plugin source may itself be a linked worktree. Follow its own Git
# metadata to the common directory, whose parent is the protected primary tree.
# Never ask git: a git hook exports GIT_DIR, and `git rev-parse --git-dir` then
# answers for the OUTER repository — measured 2026-08-29, when that made this
# lock allow all eight refusals from inside the pre-commit.
if [ -f "$TREE/.git" ]; then
  gitdir=$(sed -n 's/^gitdir: //p' "$TREE/.git")
  [ -n "$gitdir" ] || deny "REFUSED — the selected plugin worktree binding is invalid."
  case "$gitdir" in /*) ;; *) gitdir="$TREE/$gitdir" ;; esac
  gitdir=$(realpath -e -- "$gitdir" 2>/dev/null) \
    || deny "REFUSED — the selected plugin worktree binding is invalid."
  [ -f "$gitdir/commondir" ] \
    || deny "REFUSED — the selected plugin worktree has no primary repository binding."
  commondir=$(cat -- "$gitdir/commondir")
  case "$commondir" in /*) ;; *) commondir="$gitdir/$commondir" ;; esac
  common=$(realpath -e -- "$commondir" 2>/dev/null) \
    || deny "REFUSED — the protected primary repository could not be resolved."
  TREE=$(dirname -- "$common")
  [ "$common" = "$TREE/.git" ] \
    || deny "REFUSED — the protected primary repository binding is invalid."
fi
if [ ! -e "$TREE" ]; then   # ABSENT, not merely «not a repo»: a path that exists
                            # without .git is the cached-copy case and still refuses.
  payload=$(cat)
  printf '%s' "$payload" | jq -e . >/dev/null 2>&1 || allow
  [ "$(printf '%s' "$payload" | jq -r '.tool_name // ""')" = Bash ] || allow
  gone_cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
  case "$gone_cmd" in
    *"$TREE"*) deny "REFUSED — this command names the protected primary checkout, which is not on disk. Reinstall the plugin from the repository's main checkout with ./install.sh." ;;
  esac
  allow
fi
payload=$(cat)
if [ ! -d "$TREE/.git" ]; then
  printf '%s' "$payload" | jq -e . >/dev/null 2>&1 || allow
  [ "$(printf '%s' "$payload" | jq -r '.tool_name // ""')" = Bash ] || allow
  ub_cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
  ub_cmd=$(strip_text <<<"$ub_cmd") \
    || deny "REFUSED — awk could not read the branch command text."
  # Line continuations, then quotes and backslashes, go first: bash joins
  # `check\<newline>out`, `check""out` and `che\ckout` back into the verb.
  ub_words=${ub_cmd//$'\\\n'/}
  ub_words=$(tr -d "\"'\\\\" <<<"$ub_words") \
    || deny "REFUSED — tr could not normalize the branch command text."
  ub_status=0
  grep -qwE 'checkout|switch|reset|rebase|symbolic-ref|update-ref|bisect' <<<"$ub_words" || ub_status=$?
  [ "$ub_status" = 1 ] && allow
  [ "$ub_status" = 0 ] || deny "REFUSED — grep could not check the branch command text."
  ub_targets=("$(printf '%s' "$payload" | jq -r '.cwd // ""')")
  [[ $ub_cmd =~ git[[:space:]]+-C[[:space:]]+([^[:space:]\;\&\|]+) ]] && ub_targets+=("${BASH_REMATCH[1]}")
  [[ $ub_cmd =~ (^|[[:space:]\;\&])cd[[:space:]]+([^[:space:]\;\&\|]+) ]] && ub_targets+=("${BASH_REMATCH[2]}")
  for d in "${ub_targets[@]}"; do
    [ -n "$d" ] || deny "REFUSED — the protected primary repository is unavailable."
    d=$(realpath -m -- "${d//\"/}")
    while :; do
      if [ -e "$d/.git" ]; then
        [ -e "$d/plugin/hooks/pynott-branch-lock.sh" ] \
          && deny "REFUSED — the protected primary repository is unavailable."
        break
      fi
      [ "$d" = / ] && break
      d=$(dirname -- "$d")
    done
  done
  allow
fi
printf '%s' "$payload" | jq -e . >/dev/null 2>&1 || allow
[ "$(printf '%s' "$payload" | jq -r '.tool_name // ""')" = Bash ] || allow

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')

# One line per Bash call, allowed or denied. Without it, a lock that never fires
# and a lock that fires and is ignored look identical from the outside — which is
# exactly the ambiguity that cost a diagnosis on 2026-08-29.
lock_log="${NOTT_STATE_DIR:-$HOME/.nott/state}/branch-lock.log"
# `date -Is` is GNU’s: BSD date answers «invalid argument ’s’ for -I» and
# exits 1, and the line ended up with an EMPTY timestamp while the error went
# to the hook’s stderr — measured 2026-09-21 in a reviewer’s trace. `-Is`
# comes first, so the Linux host keeps the format it already wrote (with
# offset); only a box without it falls back to UTC.
# Store a command hash because a later guard can refuse a credential literal.
cmd_h=$(printf '%s' "$cmd" | { command -v sha256sum >/dev/null 2>&1 \
  && sha256sum || shasum -a 256; } | cut -c1-64)
printf '%s\tBash\t%s\n' "$(date -Is 2>/dev/null || date -u +%FT%TZ)" "$cmd_h" \
  >> "$lock_log" 2>/dev/null || true

# AND THE LOG HAS A CEILING. Measured 2026-08-31: 7,391,592 bytes and 36,488 lines, one per
# Bash call of EVERY session on this host, with no trimming at all — this `>>` was the only
# write and nothing bounded it. `tools/worktree/sync.sh` already avoided the same
# defect in its own log; the technique comes from there and so does the reason: `tail` into a
# temporary and `mv`, NEVER `>` over the file itself, because the
# redirection truncates before `tail` reads and a concurrent run would see the
# log empty. The `mv` is atomic within the same filesystem.
#
# The trim runs on the hot path of every Bash call, so it reads the size with
# `wc -l` and leaves without touching anything in the common case.
lock_log_max=${NOTT_BRANCH_LOCK_LOG_MAX:-500}
lock_log_n=$(wc -l < "$lock_log" 2>/dev/null) || lock_log_n=0
if [ "$lock_log_n" -gt "$lock_log_max" ] 2>/dev/null; then
  tail -n "$lock_log_max" "$lock_log" > "$lock_log.trim" 2>/dev/null \
    && mv "$lock_log.trim" "$lock_log" 2>/dev/null || rm -f "$lock_log.trim" 2>/dev/null
fi

text=$(strip_text <<<"$cmd") || deny "REFUSED — awk could not read the branch command text."

# ORIGIN/MAIN'S RULE, UNCHANGED, ON THE STRIPPED TEXT. The rules below only add
# refusals, so the lock never passes a move this rule refuses (lead decision after
# review 2e6c1a88). Two reviews found a new parse that passed such a move; this
# keeps that from coming back. Only the quoted text that strip_text removes is new.
main_rule() {
  # Not a HEAD-moving verb at all -> none of this rule's business.
  grep -qE 'git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(checkout|switch)' <<<"$text" || return
  # `git -C <path>` names the tree outright; a leading `cd <path>` moves the shell
  # into it; otherwise it is the session cwd.
  local target=$cwd flags ref
  if [[ $text =~ git[[:space:]]+-C[[:space:]]+([^[:space:]\;\&\|]+) ]]; then
    target=${BASH_REMATCH[1]}
  elif [[ $text =~ (^|[[:space:]\;\&])cd[[:space:]]+([^[:space:]\;\&\|]+) ]]; then
    target=${BASH_REMATCH[2]}
  fi
  target=$(realpath -m -- "${target//\"/}" 2>/dev/null || printf '%s' "$target")
  [ "$target" = "$TREE" ] || return
  # `git checkout [<ref>] -- <path>` restores FILES; HEAD never moves.
  case " $text " in
    *" -- "*) return ;;
  esac
  IFS=$'\t' read -r flags ref < <(awk '
    { for (i = 1; i <= NF; i++) {
        if ($i == "checkout" || $i == "switch") { seen = 1; continue }
        if (!seen) continue
        if (substr($i, 1, 1) == "-") { flags = flags $i " "; continue }
        if (ref == "") ref = $i
    } }
    END { printf "%s\t%s\n", (flags == "" ? "-" : flags), (ref == "" ? "-" : ref) }' <<<"$text")
  case " $flags " in
    *" -b "*|*" -B "*|*" -c "*|*" -C "*|*" --detach "*|*" --orphan "*)
      deny "REFUSED — this command creates a branch or detaches HEAD in the protected primary checkout. Workers read their law from that checkout. Use a worktree: git -C <primary-checkout> worktree add ../worktrees/<name> -b <branch>" ;;
  esac
  case "$ref" in
    -|main|master) return ;;
  esac
  deny "REFUSED — this command moves the protected primary checkout off main. Workers read their law from that checkout. Use a worktree: git -C <primary-checkout> worktree add ../worktrees/<name> <ref>"
}
main_rule

# A `cd` or `git -C` argument, read from the directory $1. Quotes go first.
at() {
  local p=${2//[\"\']/}
  case $p in /*) ;; *) p=$1/$p ;; esac
  realpath -m -- "$p" 2>/dev/null || printf '%s' "$p"
}
# True when git run in $1 acts on the primary: the nearest directory above $1 that
# holds `.git` is the primary. A subdirectory counts; a linked worktree does not.
walk_primary() {
  local d=$1
  until [ -e "$d/.git" ]; do
    [ "$d" = / ] && return 1
    d=$(dirname -- "$d")
  done
  [ "$d" = "$TREE" ]
}
# The last answer is kept: a heredoc can repeat one `cd` thousands of times, and
# each walk forks `dirname`. No associative array: bash 3.2, macOS's /bin/bash, has none.
last_walked='' last_primary=1
primary() {
  if [ "$1" != "$last_walked" ]; then
    last_walked=$1 last_primary=1
    walk_primary "$1" && last_primary=0
  fi
  return "$last_primary"
}

# One verb aimed at the primary ($1, with its arguments $2): return when it moves
# no HEAD and no branch, else refuse.
judge() {
  # The flags, the first other word (the ref), the count of other words and the
  # count of words after a standalone `--`, and the count of flags that can change
  # what a move to the pin does, in one pass. Adjacency is not required:
  # `checkout -q -b` creates a branch just as surely as `checkout -b`.
  # TAB-separated on purpose: `flags` holds several tokens, and a space-split read
  # hands its second word to `ref` — measured by the mutation self-test, which found
  # `checkout -q -b main` reading its ref as `-b`. A failed awk leaves every field
  # empty, and each rule below refuses an empty field.
  local flags ref n paths odd
  IFS=$'\t' read -r flags ref n paths odd < <(awk '
    BEGIN { split("-q --quiet -f --force -m --merge --progress --no-progress", w, " ")
            for (k in w) plain[w[k]] = 1 }
    { for (i = 1; i <= NF; i++) {
        if ($i ~ /^#/) break   # a comment ends the words
        # A redirection is not a word of git: skip it, and its target when it stands apart.
        if ($i ~ /^([0-9]*|&)[<>]/) { if ($i ~ /^([0-9]*|&)[<>]+&?$/) i++; continue }
        if (dd) { p++; continue }
        if ($i == "--") { dd = 1; continue }
        if (substr($i, 1, 1) == "-") { flags = flags $i " "; if (!($i in plain)) odd++; continue }
        gsub(/["\047]/, "", $i)
        n++; if (ref == "") ref = $i
    } }
    END { printf "%s\t%s\t%d\t%d\t%d\n", (flags == "" ? "-" : flags), (ref == "" ? "-" : ref), n, p, odd }' <<<"$2")
  case $1 in
    checkout|switch)
      # `git checkout [<ref>] -- <path>` restores FILES; HEAD never moves. ONLY a
      # standalone `--` with a path after it earns this exit. The earlier form also
      # accepted the pattern `" --"`, which matched every long flag ever passed —
      # `--detach` walked straight through the lock on it.
      [ "$1" = checkout ] && [ "${paths:-0}" -gt 0 ] && return
      case " $flags" in
        *" -b"*|*" -B"*|*" -c"*|*" -C"*|*" --detach"*|*" --orphan"*|*" --create"*|*" --force-create"*)
          deny "REFUSED — this command creates a branch or detaches HEAD in the protected primary checkout. Workers read their law from that checkout. Use a worktree: git -C <primary-checkout> worktree add ../worktrees/<name> -b <branch>" ;;
      esac
      # The pin itself, or no ref at all, with no flag outside the plain list.
      case "$ref:$n:$odd" in
        -:0:0|main:1:0|master:1:0) return ;;
      esac
      deny "REFUSED — this command moves the protected primary checkout off main. Workers read their law from that checkout. Use a worktree: git -C <primary-checkout> worktree add ../worktrees/<name> <ref>" ;;
    reset)
      # `git reset [HEAD] [-- <path>]` moves no HEAD; any other revision moves the branch.
      [ "${paths:-0}" -gt 0 ] && return
      case "$ref" in -|HEAD) return ;; esac
      deny "REFUSED — this command moves the branch of the protected primary checkout to another commit. Workers read their law from that checkout. To unstage a file, use git reset -- <path>. Otherwise use a worktree: git -C <primary-checkout> worktree add ../worktrees/<name> <ref>" ;;
    symbolic-ref)
      # One name and no delete flag only reads HEAD: `git symbolic-ref --short HEAD`.
      case " $flags " in *" -d "*|*" --delete "*) ;; *) [ "$n" = 1 ] && return ;; esac ;;
  esac
  deny "REFUSED — this command moves HEAD or a branch of the protected primary checkout. Workers read their law from that checkout. Use a worktree: git -C <primary-checkout> worktree add ../worktrees/<name> <ref>"
}

# WHICH tree does each verb act on? Its own `git -C <path>` names it; otherwise the
# shell's directory does: the session cwd, moved by each `cd <path>` before the verb,
# a relative one read from the directory before it, `cd -` from the one before that.
# A `cd` inside a subshell or inside quoted text can move that directory in this
# reading but not in bash. So when ANY `cd` or `git -C` of the command, or the
# directory of any verb, is the primary, every verb of the command is judged as
# acting on the primary. That over-refuses `cd <primary> && cd <lane> && git
# checkout x`, which fails safe. A `cd` that touches `(` or a quote is not read;
# the lock stops accidents (the threat model above).
cd_re='(^|[[:space:];&])cd[[:space:]]+([^[:space:];&|)]+)'
# A global option before the verb moves HEAD all the same: `git -c k=v checkout`, `git --no-pager switch`.
opt='(-c[[:space:]]+[^[:space:];&|]+|--?[[:alpha:]][^[:space:];&|]*)[[:space:]]+'
# The arguments run to a separator; `2>&1`, `>&2` and `&>` are redirections, not separators.
# A backtick does not end them: a ref computed by `git rev-parse` reads as a ref that is not the pin.
verb_re='git[[:space:]]+('"$opt"')*(-C[[:space:]]+([^[:space:];&|]+)[[:space:]]+)?('"$opt"')*(checkout|switch|reset|rebase|symbolic-ref|update-ref|bisect)(([^;&|)'$'\n'']|[<>]&|&>)*)'
step_re="$cd_re|$verb_re"
# awk finds the steps line by line, one step per output line: a bash
# `${rest#*"$step"}` cut is quadratic, and a 400 KB heredoc outran the hook's
# timeout, which lets the call run. No step crosses a line: a newline ends a command.
steps=$(step_re=$step_re LC_ALL=C awk '{
    s = $0
    while (match(s, ENVIRON["step_re"])) {
      st = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      sub(/^[[:space:];&]+/, "", st); print st
    } }' <<<"$text") || deny "REFUSED — awk could not read the branch command text."
here=$(at / "$cwd") prev=$here hit='' verbs=() verb_args=()
while IFS= read -r step; do
  # A `cd` step needs no regex: bash compiles one per test, and that cost adds up.
  if [[ $step == cd[[:space:]]* ]]; then
    cd_to=${step#cd} && cd_to=${cd_to#"${cd_to%%[![:space:]]*}"}
    [ "$here/$cd_to" = "${last_key-}" ] || { last_key=$here/$cd_to; resolved=$(at "$here" "$cd_to"); }
    if [ "$cd_to" = - ]; then to=$prev; else to=$resolved; fi
    prev=$here here=$to
    primary "$here" && hit=1
    continue
  fi
  [[ $step =~ $verb_re ]] || continue
  git_c=${BASH_REMATCH[4]} verb=${BASH_REMATCH[7]} args=${BASH_REMATCH[8]}
  target=$here
  [ -z "$git_c" ] || target=$(at "$here" "$git_c")
  primary "$target" && hit=1
  verbs+=("$verb") verb_args+=("$args")
done <<<"$steps"
[ -n "$hit" ] || allow
for i in "${!verbs[@]}"; do judge "${verbs[$i]}" "${verb_args[$i]}"; done
allow
