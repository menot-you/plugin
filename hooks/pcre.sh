# pcre — the one PCRE engine the hooks judge with. Sourced, never run; lives flat in
# hooks/ because the packager (plugin/package.py) copies hooks/ with copy2 per file and would refuse a
# subdirectory (the same reason secret-shapes.sh sits here).
#
# 2026-09-21. Three hooks matched credential and command shapes with `grep -P`, which is
# GNU-only. On Darwin /usr/bin/grep is BSD grep: it answers -P with exit 2 — the SAME
# status a pattern that does not compile gives — and the three hooks read that differently,
# all of them wrongly:
#
#   bash-guards.sh      read it as «the table is broken» and fail-CLOSED on every Bash
#                       call; the box lost its shell for the whole session.
#   secret-in-output.sh took no branch, so $kind stayed empty and a credential in a
#                       command's output was never named. Fail-OPEN, in silence.
#   session-state.sh    the same four probes decide the `<command with secret>` mask; with
#                       every probe erroring, the raw command was written to the state file.
#
# The engine is resolved by BEHAVIOUR, never by name: a GNU grep built without PCRE fails
# `-P` exactly like BSD grep, so the probe RUNS the option instead of trusting the binary.
# `grep` first keeps the Linux host on its native, fastest lane; `ggrep` picks up a Homebrew
# GNU grep; perl is the portable last resort, so a box with no GNU grep still JUDGES instead
# of losing its shell or its secret guard. Perl is the reference engine these shapes were
# written against (`(?m)`, `(?i)`, lookbehind, `\K` all mean the same thing there).
#
# Every primitive keeps grep's three statuses exactly: 0 match, 1 no match, 2 the regex does
# not compile. A caller that cannot tell 2 from 1 is how this class of bug starts.
# `pcre_engine` is empty when nothing can judge — the caller decides whether that denies
# (a gate) or is reported (an advisory). It must never read as «no match».

# UTF-8: THE PERL LANE HAS TO READ WHAT GNU GREP READS. Measured on the Linux
# host on 2026-09-21 (round 4 review): under a UTF-8 locale `grep -P` turns on
# PCRE2’s Unicode rules, and `\s` matches U+00A0 (NBSP). Perl in BYTE mode
# does not match — a `--token` preceded by NBSP passed through the perl lane
# and was refused by the grep lane. For a credential shape, the permissive
# lane is the one that lets the secret out. `-CSD` decodes stdin/stdout and
# aligns the two readings; outside a UTF-8 locale it switches to `-C0`, which
# is the byte behaviour this box already had.
# `no warnings ’utf8’` because the input is an arbitrary command, which may
# not be valid UTF-8: a warning on the hook’s stderr is not a verdict and
# must not pass as one.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*utf8*|*UTF8*|*utf-8*) _pcre_perlc=-CSD ;;
  *) _pcre_perlc=-C0 ;;
esac

pcre_engine=
for _pcre_cand in grep ggrep; do
  command -v "$_pcre_cand" >/dev/null 2>&1 || continue
  printf 'x' | "$_pcre_cand" -zqP 'x' >/dev/null 2>&1 && { pcre_engine=$_pcre_cand; break; }
done
if [ -z "$pcre_engine" ] && command -v perl >/dev/null 2>&1 \
   && printf 'x' | perl "$_pcre_perlc" -0777 -e 'no warnings "utf8";
                   my $r=shift; exit((<STDIN>//"") =~ /$r/ ? 0 : 1)' -- 'x' >/dev/null 2>&1
then pcre_engine=perl; fi
unset _pcre_cand

# A reader that quits at its first answer SIGPIPEs its writer once the input passes the 64 KB
# pipe buffer, and under `pipefail` the writer's 141 becomes the pipe's status: a secret on
# line 1 of a 1 MB output read as «NOT scanned» (review, 2026-09-30). Every pipe into a `pcre_q*`
# reader ends in `drain`, which answers with the reader's status and then reads the rest.
drain() { # CMD...  <stdin
  "$@"; local r=$?
  cat >/dev/null
  return $r
}

# Whole input as ONE record, like `grep -zqP`: `.` does not cross a newline and `^`/`$`
# keep their line meaning only for a pattern that carries `(?m)`.
pcre_q() { # RE  <stdin
  if [ "$pcre_engine" = perl ]; then
    perl "$_pcre_perlc" -0777 -e 'no warnings "utf8";
                   my $r=shift; my $x=eval{qr/$r/}; exit 2 unless defined $x;
                   exit((<STDIN>//"") =~ $x ? 0 : 1)' -- "$1"
  else "$pcre_engine" -zqP "$1"; fi
}

# Case-insensitive twin (`grep -zqiP`). A shape that already carries `(?i)` is unharmed.
pcre_qi() { # RE  <stdin
  if [ "$pcre_engine" = perl ]; then
    perl "$_pcre_perlc" -0777 -e 'no warnings "utf8";
                   my $r=shift; my $x=eval{qr/$r/i}; exit 2 unless defined $x;
                   exit((<STDIN>//"") =~ $x ? 0 : 1)' -- "$1"
  else "$pcre_engine" -zqiP "$1"; fi
}

# Every match, NUL-terminated (`grep -ozP`) — the token stream a per-token exemption reads.
pcre_o() { # RE  <stdin
  if [ "$pcre_engine" = perl ]; then
    perl "$_pcre_perlc" -0777 -e 'no warnings "utf8";
                   my $r=shift; my $x=eval{qr/$r/}; exit 2 unless defined $x;
                   my $s=<STDIN>//""; my $n=0; while ($s =~ /$x/g) { print $&, "\0"; $n++ }
                   exit($n ? 0 : 1)' -- "$1"
  else "$pcre_engine" -ozP "$1"; fi
}

# Is there a NUL record that does NOT match (`grep -zqvP`)? Pairs with pcre_o: a token that
# escapes the exemption is the one that decides.
pcre_qv() { # RE  <stdin
  if [ "$pcre_engine" = perl ]; then
    perl "$_pcre_perlc" -0 -e 'no warnings "utf8";
                my $r=shift; my $x=eval{qr/$r/}; exit 2 unless defined $x;
                my $f=0; while (defined(my $l=<STDIN>)) { chomp $l; $f=1 if $l !~ $x }
                exit($f ? 0 : 1)' -- "$1"
  else "$pcre_engine" -zqvP "$1"; fi
}

# ---------------------------------------------------------------------------
# The LINE family: `grep -qP` and friends WITHOUT -z, one record per line.
#
# Not a convenience (review, 2026-09-21). A caller that used plain `grep -qP` and is handed
# the -z twin gets a DIFFERENT match on the very same GNU grep: measured on the Linux host,
# "FOO\n--token abcdefghij" does not match secret_flag_re under -qP and does match under
# -zqP, because the shape's leading `\s` may then consume the preceding newline. That is a
# behaviour change on the host this work was told not to change, so the two readings stay
# apart and each call site keeps the one it always had.
pcre_ql() { # -qP   <stdin
  if [ "$pcre_engine" = perl ]; then
    perl "$_pcre_perlc" -ne 'BEGIN{no warnings "utf8"; $r=shift; $x=eval{qr/$r/}; exit 2 unless defined $x; $f=0}
              chomp; $f=1 if /$x/; END{exit($f?0:1)}' -- "$1"
  else "$pcre_engine" -qP "$1"; fi
}
pcre_qil() { # -qiP  <stdin
  if [ "$pcre_engine" = perl ]; then
    perl "$_pcre_perlc" -ne 'BEGIN{no warnings "utf8"; $r=shift; $x=eval{qr/$r/i}; exit 2 unless defined $x; $f=0}
              chomp; $f=1 if /$x/; END{exit($f?0:1)}' -- "$1"
  else "$pcre_engine" -qiP "$1"; fi
}
pcre_ol() { # -oP   <stdin : every match, one per LINE
  if [ "$pcre_engine" = perl ]; then
    perl "$_pcre_perlc" -ne 'BEGIN{no warnings "utf8"; $r=shift; $x=eval{qr/$r/}; exit 2 unless defined $x; $n=0}
              chomp; while (/$x/g) { print $&, "\n"; $n++ } END{exit($n?0:1)}' -- "$1"
  else "$pcre_engine" -oP "$1"; fi
}
pcre_qvl() { # -qvP  <stdin : is there a LINE that does not match?
  if [ "$pcre_engine" = perl ]; then
    perl "$_pcre_perlc" -ne 'BEGIN{no warnings "utf8"; $r=shift; $x=eval{qr/$r/}; exit 2 unless defined $x; $f=0}
              chomp; $f=1 if !/$x/; END{exit($f?0:1)}' -- "$1"
  else "$pcre_engine" -qvP "$1"; fi
}

# The FIRST match only (`grep -oP RE | head -n 1`). LINE-oriented, like the grep it replaces:
# a -0777 slurp let `.` cross a newline and returned "demo\nid" where grep returned "demo"
# (review, 2026-09-21 — session-state would then record a unit name that never existed).
# `\K` keeps its meaning in both engines, so a pattern may drop its prefix from the match.
pcre_o1() { # RE  <stdin
  if [ "$pcre_engine" = perl ]; then
    # `exit 0` inside the loop RUNS the END block, whose `exit 1` overrode it:
    # the primitive returned 1 even having matched and printed (review,
    # 2026-09-21), and the consumer took the `|| cat` branch by mistake. The
    # state lives in a variable and END is the only one that decides, as in
    # every other primitive in this file.
    perl "$_pcre_perlc" -ne 'BEGIN{no warnings "utf8"; $r=shift; $x=eval{qr/$r/}; exit 2 unless defined $x; $h=0}
              next if $h; chomp; if (/$x/) { print $&, "\n"; $h=1 }
              END{exit($h?0:1)}' -- "$1"
  else "$pcre_engine" -oP "$1" | head -n 1; fi
}
