#!/usr/bin/env -S bash -p
# bash-guards — PreToolUse on Bash: one process, one table, three former guards.
#
# 2026-09-15: secret-in-argv-guard.sh, owned-process-guard.sh and trunk-guard.sh
# each cost a bash + three jq per Bash call (three processes, ~50 ms together).
# The rules were regexes with a reason; this script reads them from
# bash-guards.tsv (name, regex, reason, optional token-level exemption) and
# denies on the first row that matches, in table order — the order hooks.json
# used to run the three scripts in. Every deny reason keeps its former prefix
# byte-for-byte (`trunk-guard: REFUSED`, `secret-in-argv-guard: REFUSED`,
# `owned-process-guard: REFUSED`): the eval cases, the client smokes and the
# live traces read them. The two guards with state (pynott-branch-lock.sh,
# two-misses.sh) stay apart.
#
# The command is matched WHOLE (`grep -z`): the former scripts read it line by
# line, but two rules see across lines (a name match in one line feeding `kill`
# in another; a push segment tested twice). Rows that anchor carry `(?m)`, so
# `^`/`$` keep their line meaning. A backslash-newline is whitespace to the
# shell and is read as such for every row (trunk-guard alone did this before;
# for the other rows it is stricter, never looser). A regex or reason may name
# a shape by `$name`/`${name}`: the shared credential shapes come from
# secret-shapes.sh beside this script, the shell/git prefixes are defined
# below. Names resolve ONCE, by indirection, never by eval: the reasons carry
# literal `$VAR` and `$(cat file)` and must stay that way. The reason names the
# class, never the value: echoing it would put a secret where this hook exists
# to keep it out of.
#
# Fail-CLOSED like plan-exit-gate.sh: a payload that does not parse, a missing
# table, a missing shapes lib or an unknown `$name` is denied. `exit 2` is the
# block — a permission JSON is skipped under bypassPermissions, measured on
# pynott-branch-lock.sh — and the JSON is courtesy.
set -uo pipefail

deny() {
  printf '%s\n' "$1" >&2
  # Without jq the deny is the exit alone: a missing jq must not add noise to the reason.
  command -v jq >/dev/null 2>&1 &&
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  # SOMBRA (2026-09-18): every refusal leaves ONE line — when, which rule, a hash of the
  # command — so a readout can count false positives later. Never the command itself: a
  # command can carry a secret, and this hook exists to keep secrets out of files. A log
  # that cannot be written changes nothing: the verdict is the `exit 2` below, not the line.
  # `${HOME:-…}`: under `set -u` an unset HOME would abort deny() with status 1 before the
  # `exit 2` — the refused command would run (review finding, 2026-09-18).
  # The hash in a variable, and the `--arg h` on a line by itself: the mutant
  # that proves the line does NOT carry the anchor command on that line, and
  # an `--arg` split in two left the anchor with zero occurrences —
  # INAPPLICABLE, which the harness counts as RED (round 4 review,
  # 2026-09-21).
  # `sha256sum` is coreutils’; Darwin brings `shasum`. Both give the same hex.
  { local dir="${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/nott"
    local cmd_h; cmd_h=$(printf '%s' "${cmd:-}" | { command -v sha256sum >/dev/null 2>&1 \
      && sha256sum || shasum -a 256; } | cut -c1-64)
    mkdir -p "$dir" && jq -cn --arg at "$(date -u +%FT%TZ)" --arg n "${rule:-hook}" \
      --arg h "$cmd_h" \
      '{at:$at,name:$n,cmd_sha256:$h}' >> "$dir/bash-guards-refusals.jsonl"
  } 2>/dev/null || true
  exit 2
}

payload=$(cat)
command -v jq >/dev/null 2>&1 \
  || deny "bash-guards: REFUSED — jq is not installed, so this guard cannot read the call. Install jq (for example apt-get install jq)."
# One jq: the command when the tool is Bash (exit 0), null for another tool
# (exit 1); a payload that does not parse, or is empty, is any other exit.
cmd=$(printf '%s' "$payload" | jq -er 'if .tool_name == "Bash" then (.tool_input.command // "") else null end' 2>/dev/null)
case $? in
  0) ;;
  1) exit 0 ;;
  *) deny "bash-guards: REFUSED — the hook payload did not parse as JSON (invalid input)" ;;
esac
# A backslash-newline is whitespace to the shell; read it as such. Not in a quoted heredoc
# body, where it is text: the heredoc strip reads `raw`, so a joined line cannot hide its
# terminator.
raw=$cmd
cmd=${cmd//\\$'\n'/ }

here=$(dirname "${BASH_SOURCE[0]}")
. "$here/secret-shapes.sh" 2>/dev/null \
  || deny "bash-guards: REFUSED — secret-shapes.sh is missing beside the hook"
# The engine the table is judged with, resolved by behaviour; see pcre.sh for why a
# `grep` that lacks -P must not read as a table that does not compile.
. "$here/pcre.sh" 2>/dev/null \
  || deny "bash-guards: REFUSED — pcre.sh is missing beside the hook"
[ -r "$here/bash-guards.tsv" ] \
  || deny "bash-guards: REFUSED — bash-guards.tsv is missing beside the hook"

# Shell prefixes the rows name. One command segment: from the verb to the next
# `;`, `|`, `&` or newline. A flag is a word that starts with `-` after
# whitespace, so `my-fancy-proc` as a pattern argument does not read as `-f`.
start='(^|[;&|(\s])(\S*/)?'
fflag='(-[A-Za-z0-9]*f[A-Za-z0-9]*|--full)(\s|$)'
# `git`, then any global options (`-C dir`, `-c k=v`), then the verb.
git='(^|[;&|(\s])(\S*/)?git\s+(?:(?:-[cC]\s+\S+|--\S+|-\S)\s+)*'
seg='[^;&|\n]*'
# The reason fragments the rows share.
grant='the owner'"'"'s explicit written grant naming this act'
by_identity='kill <pid> by identity — the process you started has a pid (\$!, a pid file); a name match hits strangers and the caller itself.'
route='pass it on stdin or in the process'"'"'s own environment (`VAR=$VAR`, `$(cat file)`), never as a literal in argv'
# A secret value that is only a placeholder (unit H3): `your-…`, `<…>`, a run of x, X or *,
# a stock word, or a value with a regex construct (a `grep` pattern for a key, not a key):
# a class with a quantifier (`[a-z]+`), a counted quantifier (`{16,}`) or a class escape
# (`\d`). A lone `?`, `[`, `{` or `\` does not count: a live password can carry one.
placeholder='(?:your-[A-Za-z0-9-]+|<[^<>]*>|[xX*]{4,}|(?i:example|dummy|changeme|placeholder|redacted)|\S*(?:\[[^\]\s]+\][*+?]|\{\d+(?:,\d*)?\}|\\[dwsDWS])\S*)'

expand() { # $1: NAME of a variable holding `$name`/`${name}` references; resolved in place, once
  local -n s=$1
  local out rest lit n
  # A single left-to-right pass in bash (no process): a resolved value is never
  # rescanned, so the `$VAR` and `$(cat file)` a reason carries stay literal.
  out=${s%%\$*}; rest=${s#"$out"}
  while [ -n "$rest" ]; do
    if [[ $rest =~ ^\$\{?([A-Za-z_]+)\}? ]]; then
      n=${BASH_REMATCH[1]}
      # In place, never in a subshell: a deny here must end the hook, not a $(...).
      [ -n "${!n:-}" ] || deny "bash-guards: REFUSED — bash-guards.tsv names an undefined shape ${BASH_REMATCH[0]}"
      out+=${!n}; rest=${rest#"${BASH_REMATCH[0]}"}
    else
      out+='$'; rest=${rest#\$}
    fi
    lit=${rest%%\$*}; out+=$lit; rest=${rest#"$lit"}
  done
  s=$out
}

# The table, expanded once. Most commands match no row: ONE grep over the
# alternation of every regex answers those, and only a match walks the rows to
# name the first one (the sk exemption is judged there, not here).
names=() res=() reasons=() exempts=() all=
# `|| [ -n "$name" ]`: a table whose last line has no trailing newline still reaches
# the body for that line. Without it `read` returns non-zero there and the LAST rule
# is dropped in silence (measured in review, 2026-09-15: `git reset --hard` passed).
while IFS=$'\t' read -r name re reason exempt || [ -n "$name" ]; do
  case $name in ''|'#'*) continue ;; esac
  expand re; expand reason; expand exempt
  names+=("$name"); res+=("$re"); reasons+=("$reason"); exempts+=("$exempt")
  all+="${all:+|}(?:$re)"
done < "$here/bash-guards.tsv"
[ "${#res[@]}" -gt 0 ] || deny "bash-guards: REFUSED — bash-guards.tsv has no rows"
# grep exits 1 for «no match» and 2 for «this pattern does not compile». Reading 2 as
# «no match» disarmed the WHOLE table on one bad row (measured in review, 2026-09-15:
# a push to the trunk and a `pkill -f` both passed). A broken table is fail-CLOSED,
# like a missing one.
# An engine that cannot be found is a DIFFERENT fault from a table that cannot compile,
# and saying so is the whole point: the old message sent a session hunting a regex that
# was never wrong. Still fail-CLOSED — an unjudged table denies.
[ -n "$pcre_engine" ] || deny "bash-guards: REFUSED — no PCRE engine on this box: this \`grep\` has no -P (BSD grep answers 2, like a bad pattern), no \`ggrep\` answers -P either, and \`perl\` is absent. The table was NOT judged. Install GNU grep (\`brew install grep\`) or perl."

printf '%s' "$cmd" | drain pcre_q "$all" && hit=0 || hit=$?
case $hit in
  0) ;;
  1) exit 0 ;;
  *) deny "bash-guards: REFUSED — bash-guards.tsv carries a pattern that does not compile" ;;
esac

# DATA IS NOT A COMMAND (unit H3, 2026-10-19, owner point N4). The trunk and process rows
# denied text that the shell never runs: a commit message, a PR body or a note that names
# `git push origin main`, and the pattern of a `grep` for it. `data` is the command with
# that text taken out; the trunk-* and owned-* rows read it, and every other row (the
# secret rows above all) reads the whole command. Each strip is narrow on purpose: when a
# form is in doubt, its text stays in and the row judges it as before.
nl=$'\n' tab=$'\t' q="'" dq='"' bs='\' bt='`'
# A heredoc operator with its delimiter: <<, <<-, then 'D', "D", \D or a bare D.
w='[A-Za-z_][A-Za-z0-9_]*'
hd_re="<<(-?)[[:space:]]*($q($w)$q|$dq($w)$dq|[$bs]($w)|($w))"
data_file="([^[:space:]$q$dq\$$bt]+\\.(md|txt|json|yaml|yml|toml|csv|patch|diff))"
commit_re='^([^[:space:]]*/)?git[[:space:]]+commit([[:space:]]|$)'
commit_stdin_re='[[:space:]](-F[[:space:]]*|--file[[:space:]]*=?[[:space:]]*)-$'
gh_re='^([^[:space:]]*/)?gh[[:space:]]'
gh_stdin_re='[[:space:]](--body-file|-F)([[:space:]]+|=)-$'
cat_to_re="^cat[[:space:]]*>>?[[:space:]]*$data_file\$"
tee_to_re="^tee([[:space:]]+-a)?[[:space:]]+$data_file\$"
to_file_re="^[[:space:]]*>>?[[:space:]]*$data_file[[:space:]]*\$"
blank_re='^[[:space:]]*$'
# heredoc_sink <consumer> <after>: 0 when the heredoc feeds a data sink; prints the sink
# file, if any, so the caller can keep the body when another command names that file.
heredoc_sink() {
  local seg=$1 post=$2 f
  if { [[ $seg =~ $commit_re ]] && [[ $seg =~ $commit_stdin_re ]]; } \
     || { [[ $seg =~ $gh_re ]] && [[ $seg =~ $gh_stdin_re ]]; }; then
    [[ $post =~ $blank_re ]]; return
  fi
  if [[ $seg =~ $cat_to_re ]]; then f=${BASH_REMATCH[1]}
  elif [[ $seg =~ $tee_to_re ]]; then f=${BASH_REMATCH[2]}
  elif [ "$seg" = cat ] && [[ $post =~ $to_file_re ]]; then
    printf '%s' "${BASH_REMATCH[1]}"; return 0
  else return 1; fi
  [[ $post =~ $blank_re ]] || return 1
  printf '%s' "$f"
}
# Take out the body of a heredoc whose delimiter is quoted (the shell expands nothing in
# it) and whose consumer is a data sink: `git commit -F -`, `gh ... --body-file -`/`-F -`,
# or `cat > F`/`cat >> F`/`tee F` with F a data file and nothing after the operator (so no
# pipe). The body stays when the operator is not alone on its line, sits inside quotes, has
# no terminator, or follows a backslash (`bash -s x\; git commit -F -` runs it). For a file
# sink it also stays when any command follows the terminator (`bash *.md`) or another part
# of the command names F.
strip_heredocs() {
  local -a lines; local out= i=0 j n line pre post seg delim dash bare f t outside after q1 q2
  mapfile -t lines <<<"$data"
  n=${#lines[@]}
  while [ "$i" -lt "$n" ]; do
    line=${lines[i]}
    if ! [[ $line =~ $hd_re ]]; then out+=$line$nl; i=$((i + 1)); continue; fi
    dash=${BASH_REMATCH[1]} bare=${BASH_REMATCH[6]}
    delim=${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}${BASH_REMATCH[6]}
    pre=${line%%"${BASH_REMATCH[0]}"*}; post=${line#*"${BASH_REMATCH[0]}"}
    # The terminator: the first later line equal to the delimiter (`<<-` drops leading tabs).
    j=$((i + 1))
    while [ "$j" -lt "$n" ]; do
      t=${lines[j]}; [ -n "$dash" ] && t=${t#"${t%%[!$'\t']*}"}
      [ "$t" = "$delim" ] && break
      j=$((j + 1))
    done
    if [ "$j" -ge "$n" ]; then out+=$line$nl; i=$((i + 1)); continue; fi
    seg=${pre##*[;&|(]}; seg=${seg#"${seg%%[![:space:]]*}"}; seg=${seg%"${seg##*[![:space:]]}"}
    q1=${pre//[!\']/}; q2=${pre//[!\"]/}
    if [ -z "$bare" ] && [[ $pre != *'<' && $pre != *'<<'* && $post != *'<<'* && $pre != *"$bs"* ]] \
       && [ $((${#q1} % 2)) -eq 0 ] && [ $((${#q2} % 2)) -eq 0 ] \
       && f=$(heredoc_sink "$seg" "$post"); then
      outside=$out$line$nl$(printf '%s\n' "${lines[@]:j}")
      t=${outside//"$f"/}; after=$(printf '%s' "${lines[@]:j+1}")
      if [ -z "$f" ] || { [[ $after =~ $blank_re ]] && [ $(( (${#outside} - ${#t}) / ${#f} )) -le 1 ]; }; then
        out+=$line$nl${lines[j]}$nl; i=$((j + 1)); continue
      fi
    fi
    # Not a data sink: its body is kept whole and not parsed again for heredocs.
    out+=$(printf '%s\n' "${lines[@]:i:j-i+1}")$nl; i=$((j + 1))
  done
  data=$out
}
# Take out the FIRST quoted argument of a grep, rg, ag or git grep that is the command of
# its segment (`ssh h grep '…'`, `eval grep '…'` and `watch grep '…'` run the text, so they
# keep it): a single-quoted one, or a double-quoted one with no `$`, backtick or backslash
# (those run or move the quote). The content holds no quote of the other kind, which an
# outer shell layer could turn back into code. Nothing between the verb and the quote may
# hold a quote, `\`, `$`, a backtick, `(`, `)`, `<`, `>` or a segment end: an escaped quote
# or a `<(bash -c '…')` there would hide a real command.
pat_re="(^|[;&|($nl])[ $tab]*(([^ $tab$nl;&|]*/)?(grep|egrep|fgrep|rg|ag)|git[ $tab]+grep)[ $tab]+([^;&|$q$dq\$$bt$nl$bs()<>]*)($q[^$q$dq]*$q|$dq[^$dq$q\$$bt$bs]*$dq)"
verb_re='grep|rg|ag'
# `git grep -O<cmd>`/`--open-files-in-pager=<cmd>` gives the quote to a shell: keep it.
pager_re="(^|[ $tab])(-[A-Za-z]*O|--op)"
strip_patterns() {
  local out= rest=$data m q
  while [[ $rest =~ $pat_re ]]; do
    m=${BASH_REMATCH[0]}; q=${BASH_REMATCH[6]}
    if [[ ${BASH_REMATCH[5]} =~ $pager_re ]]; then out+=${rest%%"$m"*}$m
    else out+=${rest%%"$m"*}${m%"$q"}${q:0:1}${q:0:1}; fi
    rest=${rest#*"$m"}
  done
  data=$out$rest
}
data=$raw
[[ $data == *'<<'* ]] && strip_heredocs
data=${data//\\$'\n'/ }
[[ $data =~ $verb_re ]] && strip_patterns

for i in "${!res[@]}"; do
  case ${names[i]} in trunk-*|owned-*) text=$data ;; *) text=$cmd ;; esac
  if [ -n "${exempts[i]}" ]; then
    # Token-level exemption: a match that is NOT exempt denies (`sk-test-`
    # beside a live key is still a live key).
    # The `set +e`/`set -e` pair that used to wrap this is gone (2026-09-21). Errexit was
    # never on in this script, so turning it on for these three lines only could change
    # behaviour here and nowhere else — and review could NOT reproduce the exit-1 path the
    # first version of this comment claimed, so that claim is withdrawn: `[ x -gt 1 ] && deny`
    # is protected by the `&&` and does not trip errexit. The pair goes for being a local,
    # undocumented mode change, not for a measured defect.
    printf '%s' "$text" | pcre_o "${res[i]}" | drain pcre_qv "${exempts[i]}"
    stat=("${PIPESTATUS[@]}")  # FIRST command after the pipeline: `rc=$?` resets it
    rc=${stat[2]}; first=${stat[1]}   # printf | match -o | match -v
    # Under `pipefail` a compile error in the FIRST grep feeds the second an empty
    # input, whose 1 would read as «no match»; the first grep's status decides.
    [ "$first" -gt 1 ] && deny "bash-guards: REFUSED — ${names[i]} does not compile"
    # AND SO DOES THE SECOND'S. Review, 2026-09-21: this line read `[ "$rc" -eq 0 ] || continue`,
    # so the exemption filter answering 2 («this regex does not compile») took the same branch
    # as 1 («nothing escaped the exemption») and the command was ALLOWED — measured as
    # PIPESTATUS=(0 0 2) -> exit 0. An exemption that cannot be evaluated is the one case where
    # allowing is worst: the row exists because a token that is NOT exempt is a live key.
    [ "$rc" -gt 1 ] && deny "bash-guards: REFUSED — the exemption for ${names[i]} does not compile"
    [ "$rc" -eq 0 ] || continue
  else
    printf '%s' "$text" | drain pcre_q "${res[i]}" && one=0 || one=$?
    case $one in
      0) ;;
      1) continue ;;
      *) deny "bash-guards: REFUSED — ${names[i]} does not compile" ;;
    esac
  fi
  rule=${names[i]}
  deny "${reasons[i]}"
done
exit 0
