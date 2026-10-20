#!/usr/bin/env -S bash -p
# session-state — one JSON file per session that says what the session is doing,
# read by the native statusline and the external-session status projection.
#
# Owner complaint (measured 2026-09-15, 655 transcripts): half of everything the
# owner typed was «ping?» / «status?» after a median 18 min of silence, because
# nothing on screen said whether a tool was running, what was open in the
# background, or that an agent had died. This hook writes that state; nothing
# here renders or enforces cadence.
#
# Bound in hooks.json to PreToolUse/PostToolUse/PostToolUseFailure (long
# tools), UserPromptSubmit, SubagentStop, TeammateIdle, Stop, StopFailure.
# Only the MAIN THREAD writes the phase: inside an Agent the tool events carry
# `agent_id` (prova 0c, 2026-09-15) and this hook exits 0 without writing.
# Does NOT exit early on `stop_hook_active`: the second Stop must record idle.
#
# File: ${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nott/session-state/<sid>.json
#   phase           tool | thinking | idle | dead
#   native          {provider, session_id, home}, the CLI identity, not its model backend
#   event           the latest hook event, so a resume cannot reuse an old active phase
#   waiting         a native permission prompt, cleared when the session continues
#   tool            {name, summary, since}   summary = description or command, <= 60 chars;
#                   `<command with secret>` when secret-shapes.sh matches the command
#   turn_started_at UserPromptSubmit with source user (2.1.272 sends no `source`:
#                   absent counts as user)
#   stopped_at, final (at Stop: the turn's state line, cleaned, <= 80 — a fresh channel line before
#                   the reply's, the reply's first on a retry; with no line in either, the no-line
#                   marker, or empty when the reply and the channel are both empty)
#   open[]          background_tasks of Stop/SubagentStop minus ambient and monitor:
#                   {kind, label, description}
#   units[]         {unit, since} for `systemd-run --user --unit=X` seen in PostToolUse Bash
#   dead[]          a SubagentStop with an empty report or a rate-limit shape, or a
#                   StopFailure; cleared on the next owner prompt. An agent death carries
#                   {kind, id, name, label, transcript, reason, at}: `label` is the
#                   dispatcher's task (six same-typed agents told apart), `transcript` is
#                   agent_transcript_path (what it did before dying). A session death
#                   carries `resets_at` when its 429 names the window.
#   teammate_idle[] {name, at} from TeammateIdle; cleared with dead[]
#   route           {provider, endpoint, model, account, at} written at SessionStart from the
#                   configuration the session was GIVEN — never from a credential, and the
#                   endpoint is the host alone. A session death copies it into its dead[]
#                   entry, so the 429 that names only a window still says WHO died.
# Minimum CLI 2.1.272: below it there is no background_tasks and open[] stays empty.
# Fail-OPEN: garbage payload, no session_id, unwritable directory -> exit 0, no output.
set -uo pipefail

payload=$(cat)
# ONE jq READS EVERY FIELD THE SHELL NEEDS (hook review: this hook set the wait of each
# tool call, 24 jq calls). Each field ends in a NUL and none can hold one (it is removed), so the
# fields cannot shift; the command comes last. A payload that does not parse exits here.
{ IFS= read -r -d '' event && IFS= read -r -d '' sid && IFS= read -r -d '' agent \
    && IFS= read -r -d '' tool_name && IFS= read -r -d '' description && IFS= read -r -d '' cmd; } \
  < <(printf '%s' "$payload" | jq -j '[(.hook_event_name? // ""), (.session_id? // ""), (.agent_id? // ""),
        (.tool_name? // ""), (.tool_input.description? // ""), (.tool_input.command? // "")]
      | map(tostring | gsub("\u0000"; "") + "\u0000") | add' 2>/dev/null) || exit 0
sid=${sid//[!a-zA-Z0-9-]/}
[ -n "$sid" ] || exit 0
case "$event" in
  PreToolUse|PostToolUse|PostToolUseFailure|Notification)
    [ -z "$agent" ] || exit 0 ;;
  UserPromptSubmit|SubagentStop|Stop|StopFailure|TeammateIdle|SessionStart) ;;
  *) exit 0 ;;
esac

# THE WINDOW SAYS THE STATE, NOT ONLY THE PROSE. Owner request 2026-09-21: he reads the end
# of the turn by the terminal colour without having to read the line. OSC 11 paints the background of the
# surface and persists --- whoever enters the same pane later inherits it.
#
# THE PTY, NOT `/dev/tty`. Measured on this box 2026-09-21: a tool-call child opens
# `/dev/tty` with ENXIO (it has no controlling terminal). What always exists is fd 0 of the
# `claude` process, which points at the real pts. Hooks are children of `claude`, so
# the same walk up the tree resolves from here. Inside tmux that pts is the pty OF THE
# PANE, and a PLAIN OSC 11 written there is consumed by tmux and applied to the background of the
# PANE — which is the surface the owner sees per window (measured live 2026-09-22;
# see the write block, further down).
# Fail-OPEN like the rest of the hook: without /proc (macOS), without `claude` in the tree or with the
# pts already closed, it writes nothing and does not fail the Stop.
# `NOTT_TTY_COLOR=0` switches it off; `NOTT_TTY_COLOR_TARGET` is the seam the contract measures.
# A COLOUR IS ONLY WRITTEN WHEN IT CHANGES. Owner complaint 2026-09-21: «it blinks like a Christmas
# tree». This hook runs on every PreToolUse, PostToolUse and Stop, and wrote OSC 11 on
# ALL of them — a turn with many tools means dozens of repaints of the SAME colour, and the emulator
# redraws the screen on each. The state of the screen is a value, not an event: the last
# colour written is kept and a repeated one does not reach the terminal. The first write of each session always
# passes, and a session whose colour does not change stops touching the terminal.
nott_tint() { # <cor>
  [ "${NOTT_TTY_COLOR:-1}" != 0 ] || return 0
  # THE MARK DOES NOT LIVE IN THE STATE DIRECTORY. That directory has a contract: one file
  # per session, and a payload without `session_id` cannot leave anything there. A second kind
  # of file next to them broke that reading for every consumer.
  local marca=
  local alvo=${NOTT_TTY_COLOR_TARGET:-} p=$PPID tty=
  # `[ -d /proc ]` guarding the walk: the `2>/dev/null` sits AFTER the `<`, and bash applies
  # redirections in written order — the failure of `< /proc/...` is already printed
  # by the time stderr is redirected. Without /proc that is one error line per hook call, in the
  # owner terminal (measured 2026-09-21). On Linux /proc exists and nothing changes.
  # Builtins only: this walk ran a `tr` and an `awk` per ancestor on every call.
  local argv arg stat
  while [ -d /proc ] && [ -z "$alvo" ] && [ -n "$p" ] && [ "$p" != 1 ] && [ "$p" != 0 ]; do
    argv=
    # `2>/dev/null` before `<`: a process gone since the last step must not print an error.
    while IFS= read -r -d '' arg; do argv="$argv$arg "; done 2>/dev/null < "/proc/$p/cmdline"
    case " $argv" in
      *" claude "*|*"/claude "*) alvo=$(readlink "/proc/$p/fd/0" 2>/dev/null);;
    esac
    # The parent is the second field after the command name, which may hold spaces.
    stat=; IFS= read -r stat 2>/dev/null < "/proc/$p/stat"
    stat=${stat##*) }; p=${stat#* }; p=${p%% *}
  done
  # WITHOUT /proc THE WINDOW STAYED MUTE. The walk above reads /proc/<pid>/cmdline and
  # /proc/<pid>/stat, which do not exist on Darwin: `alvo` stayed empty and the hook left without
  # painting anything — the owner saw the end-of-turn colour on the Linux host and not on the Mac
  # (measured 2026-09-21). `ps` answers the same two questions on both systems: who is
  # the parent, and which tty. It runs AFTER /proc and only when /proc did not answer, so the
  # Linux host keeps exactly the path it already used.
  # WHAT THIS BRANCH DOES NOT SOLVE, stated and not hidden (review, 2026-09-21): inside a
  # tmux the controlling terminal of `claude` is the PTY OF THE PANE, not the outer emulator — the
  # contrary claim that stood here was false. It is no failure at all: it is the point. tmux
  # applies the OSC to the background OF THE PANE, the surface the owner sees per window, and that holds in
  # any tmux — Linux or Mac, with or without `allow-passthrough`, which is of no use here.
  if [ -z "$alvo" ] && [ ! -d /proc ]; then
    local nome dono
    p=$PPID
    while [ -z "$alvo" ] && [ -n "$p" ] && [ "$p" != 1 ] && [ "$p" != 0 ]; do
      # EXACT BASENAME, not `*claude*`. Review, 2026-09-21: the loose pattern matched
      # `/opt/tools/not-claude-helper` and stopped at a wrapper before the right ancestor.
      # On this box `ps -o comm=` returns `claude` with no path, and what matters is the
      # program, not a substring of the path of whoever launched it.
      nome=$(ps -o comm= -p "$p" 2>/dev/null); nome=${nome##*/}
      if [ "$nome" = claude ]; then
        # The CONTROLLING terminal, which is not the same object as the `fd 0` read via /proc.
        # They coincide in the case this serves — the interactive `claude` inherited both from the pty —
        # and Darwin does not expose `fd 0` without `lsof`. The difference is stated, not hidden.
        dono=$(ps -o uid= -p "$p" 2>/dev/null | tr -d '[:space:]')
        tty=$(ps -o tty= -p "$p" 2>/dev/null | tr -d '[:space:]')
        # The UID has to be ours: `-w` says the file allows writing, not that the
        # terminal is ours, and painting the background of somebody else terminal is not an effect
        # this hook may have.
        # `-c` here and not on the write line: the NOTT_TTY_COLOR_TARGET seam that the
        # contracts point at an ordinary file has to keep measuring, and the Linux host
        # resolves the target through /proc without passing here.
        case "$tty" in ''|'?'|'??') ;; *)
          [ "$dono" = "$(id -u)" ] && [ -c "/dev/$tty" ] && alvo=/dev/$tty ;;
        esac
      fi
      p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d '[:space:]')
    done
  fi
  [ -n "$alvo" ] && [ -w "$alvo" ] || return 0
  # THE VISIBLE SURFACE IS THE PANE, NOT THE CLIENT. Measured LIVE on 2026-09-22, with the
  # owner watching tmux: a PLAIN OSC 11 on the pane pty paints the WHOLE window (tmux
  # applies it to the background OF THE PANE, and that background is what each window shows); a write to the
  # tty of the CLIENT changes the GLOBAL background of the emulator, which tmux per-pane drawing covers —
  # #752 painted clients and the windows froze on the previous colour: the owner saw
  # amber on two turns already closed as DELIVERED. The `becac126` that motivated #752 was the
  # same family read backwards: the pane mark said `#2d1414` and the owner saw amber
  # because the DCS wrapper of that time crossed tmux and painted the global background,
  # invisible per pane — they were not two objects, it was the wrong transport.
  #
  # Inside tmux there is no wrapper and no questions: the claude pty is the pane pty, and
  # writing to it is the whole action. Each attached client sees that pane with its background;
  # outside tmux the target is the real terminal and the same write holds. tmux is never called —
  # a `display-message` with no target would answer for the most active client of the server and paint
  # another session terminal (review agy, 2026-09-22, P1), and there is nothing to ask.
  marca="${dir%/session-state}/tint/$(printf '%s' "$alvo" | tr -c 'A-Za-z0-9._-' '_')"
  mkdir -p "${marca%/*}" 2>/dev/null || return 0
  # THE MARK SUPPRESSES ONLY THE MID-TURN FLOOD. Measured 2026-09-23, session becac126: the
  # mark said amber for seven minutes while the pane showed green, and the `Stop` with
  # `RUNNING` -- decided correctly -- was suppressed because the mark already said amber. A
  # write that succeeded is not proof of what the surface holds, and a suppressed boundary
  # leaves the wrong colour with no recovery: the owner read «done» over running work. The
  # boundaries where the colour class is decided (`UserPromptSubmit`, `Stop`, `StopFailure`,
  # `SessionStart`) always paint -- one OSC per turn does not flicker, and a desynchronised
  # surface heals at the next boundary. Only the dozens of `PreToolUse`/`PostToolUse` of one
  # turn are suppressed. Review round 6, 2026-09-21, keeps its force: `SessionStart` still
  # paints on a recycled `/dev/pts/N`, because the mark lives by terminal path and the path
  # outlives the pane.
  case "$event" in
    PreToolUse|PostToolUse|PostToolUseFailure|SubagentStop|TeammateIdle)
      [ "$(cat "$marca" 2>/dev/null)" != "$1" ] || return 0 ;;
  esac
  printf '\033]11;%s\007' "$1" >> "$alvo" 2>/dev/null || return 0
  printf '%s' "$1" > "$marca" 2>/dev/null
  return 0
}
# THE COLOURS ARE THE THREE OF THE STATUSLINE, not four. ✅ green, 🚀 blue, ⛔ red.
# A fourth colour just for «the hook blocked me» told the owner about a distinction the
# statusline does not make and that is not his: a blocked turn is a stopped turn.
# It matches the already isolated verb --- the marker alternation lives ONCE in this
# file, in the clause that judges it, and two places with the same string erase the
# mutants that measure it.
# THE WINDOW ANSWERS A SINGLE QUESTION: «can I close the laptop?». Owner rule
# 2026-09-21: everything executing --- 🧠 thinking, 📟 tool, 🚀 `RUNNING` --- is
# AMBER; stopped is green (✅ `DELIVERED`) or red (⛔ `STOPPED`). `RUNNING` is
# amber because it is execution: the window only turns green or red when nothing moves.
#
# `idle` with no line and `dead` are RED. A session that stopped without saying what
# was left open is a stopped session, not a delivery --- painting green there would
# tell the owner he can close the laptop over a state nobody wrote.
nott_cor_da_fase() { # <phase> <tool name> <final>, printed by the state program
  local fase=$1 ferramenta=$2 final=$3 verbo
  # A QUESTION IS NOT WORK IN MOTION. Owner request 2026-09-22: the window stayed
  # AMBER while he was the one awaited, because asking is a tool call like any other and
  # the phase says `tool`. Amber answered «something is moving» to someone looking at an
  # unanswered question — the opposite of what the colour exists to say. Waiting on the
  # owner paints the stopped colour: the work is in his hands, not ours. The phase does NOT change
  # (`state.sh show` knows four phases and a fifth would erase its line); only the colour changes.
  case $fase:$ferramenta in
    tool:AskUserQuestion|tool:ExitPlanMode)
      nott_tint "${NOTT_TTY_COLOR_ASK:-${NOTT_TTY_COLOR_STOP:-#2d1414}}"; return 0;;
  esac
  case $fase in
    thinking|tool) nott_tint "${NOTT_TTY_COLOR_RUN:-#2d2410}"; return 0;;
    dead)          nott_tint "${NOTT_TTY_COLOR_STOP:-#2d1414}"; return 0;;
  esac
  verbo=${final#"${final%%[A-Za-z]*}"}
  case $verbo in
    ENTREGUE*|DELIVERED*) nott_tint "${NOTT_TTY_COLOR_OK:-#0f1a0f}";;
    'A CORRER'*|RUNNING*) nott_tint "${NOTT_TTY_COLOR_RUN:-#2d2410}";;
    *)                    nott_tint "${NOTT_TTY_COLOR_STOP:-#2d1414}";;
  esac
}
dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nott/session-state"
mkdir -p -m 700 "$dir" 2>/dev/null && [ -w "$dir" ] || exit 0
file=$dir/$sid.json
now=${EPOCHSECONDS:-$(date +%s)}
# Native identity differs from the model backend. The Codex view supplies its client name.
native_provider=${NOTT_HOOK_CLIENT:-claude}
[ "$native_provider" != codex ] || NOTT_TTY_COLOR=0
native_home=
case "$native_provider" in
  claude) native_home=${CLAUDE_CONFIG_DIR:-$HOME/.claude} ;;
  codex) native_home=${CODEX_HOME:-$HOME/.codex} ;;
esac
native_home=$(cd -- "$native_home" 2>/dev/null && pwd -P) || native_home=
# RETURNING THROUGH `StructuredOutput` IS NOT DYING. Measured 2026-09-20: 22 of 22 agents of
# one wave entered `dead[]` with their result already delivered. An agent that closes
# with the structured-output tool emits no text block at all, so
# `last_assistant_message` arrives EMPTY — the same shape as an agent that died with no
# report. The two are only told apart in the agent's own transcript, which the payload
# points to (`agent_transcript_path`) and which this hook already keeps so it can be resumed.
# A missing or unreadable transcript does NOT absolve: it would declare alive every agent whose
# record the host did not write, which is exactly the death this has to report.
# Measured again 2026-09-24 (`agent-a324d0028f89669a2`): the StructuredOutput return was in
# the transcript, but its mtime was 70 ms after its last line, in the same second as the
# SubagentStop. The host was still flushing when the hook read it. So the read tolerates a
# half-written line and, only for an empty report, retries for up to ~1 s. The return counts
# when it is the LAST tool_use and its tool_result is not an error; an agent that kept
# working afterwards, or whose return was rejected, has not reported.
# IT RUNS BEFORE THE LOCK. The retry waits on the HOST, not on the state file: held under
# `flock` it cost ~2.7 s on a 9.7 MB transcript (review of #794), past every other hook's
# `flock -w 2`, which then wrote unlocked. Only the verdict crosses into the locked section.
devolveu=false
if [ "$event" = SubagentStop ]; then
  agente_tr=$(printf '%s' "$payload" | jq -r '.agent_transcript_path // ""')
  vazio=$(printf '%s' "$payload" | jq -r '(.last_assistant_message // "") == ""')
  tentativas=1; [ "$vazio" = true ] && tentativas=10
  while [ -n "$agente_tr" ] && [ -r "$agente_tr" ] && [ "$tentativas" -gt 0 ]; do
    if jq -enR '[inputs | fromjson? | objects] as $l
          | ([$l[] | select((.type // "") == "assistant") | .message.content[]?
              | objects | select((.type // "") == "tool_use")] | last) as $u
          | $u != null and ($u.name // "") == "StructuredOutput"
            and any($l[] | select((.type // "") == "user") | .message.content[]? | objects;
                    (.type // "") == "tool_result" and .tool_use_id == $u.id
                    and ((.is_error // false) | not))' "$agente_tr" >/dev/null 2>&1; then
      devolveu=true; break
    fi
    tentativas=$((tentativas - 1)); [ "$tentativas" -gt 0 ] && sleep 0.1
  done
fi

# ONE WRITER AT A TIME. `mv` is atomic, but two overlapping hooks read the same
# `prev` and the later write erases the earlier one: measured in review, 40 pairs of
# SubagentStop + PreToolUse lost `dead[]` 40 times. SubagentStop races main-thread
# tool events by design. A missing or busy `flock` never blocks the session: the
# hook keeps going unlocked rather than delaying a tool call.
# ONE WRITER AT A TIME. `mv` is atomic, but two overlapping hooks read the same
# state and the later write erases the earlier one: measured in review, 40 pairs
# of SubagentStop + PreToolUse lost `dead[]` 40 times, and SubagentStop races
# main-thread tool events by design. A `flock` that is missing or busy never
# holds the session: the hook proceeds unlocked rather than delay a tool call.
# The lock is the state file itself (opened for append, never truncating): no second
# artifact appears in the state dir, which the contract checks stays empty.
{
  flock -w 2 9 2>/dev/null || true

  summary='' unit=''
  if [ "$event" = PreToolUse ]; then
    summary=$description
    [ -n "$summary" ] || summary=$cmd
    here=${BASH_SOURCE[0]%/*}; [ "$here" != "${BASH_SOURCE[0]}" ] || here=.
    # A missing shapes lib masks every command: leaking beats an unmasked line.
    # A missing shapes lib masks EVERY command: leaking beats an unmasked line. All
    # four names get the catch-all, not just the first — under `set -u` the other
    # three were unbound and printed an error per invocation (review, 2026-09-15).
    . "$here/secret-shapes.sh" 2>/dev/null || true
    . "$here/pcre.sh" 2>/dev/null || true
    : "${secret_name_re:=.}" "${secret_flag_re:=.}" "${secret_bearer_re:=.}"
    : "${secret_sk_re:=.}" "${secret_sk_fixture_re:=\x00}"
    # A missing ENGINE masks every command for the same reason a missing shapes lib does
    # (2026-09-21). These four probes were `grep -qP`; where grep has no -P each exits 2,
    # the `if` is false, and the raw command — credential included — went to the state
    # file. Not looking is not the same as looking and finding nothing.
    # AND A PROBE THAT ERRS IS NOT A PROBE THAT DID NOT MATCH. Review, 2026-09-21: the
    # `secret-in-output` fix did not reach here — with the engine CHOSEN and the probes returning 2
    # (a pattern that does not compile, the engine dying), the `||` chain read that as «no match»
    # and `echo ok` got `summary=echo ok`. A command WITH a credential walks the same
    # path and reaches persistence raw, which is exactly the defect this campaign came
    # to close. `sonda` keeps the three states apart.
    quebrou=0
    sonda() { printf '%s' "$cmd" | drain "$@"; local r=$?; [ "$r" -gt 1 ] && { quebrou=1; return 1; }; return $r; }
    sonda_sk() {
      printf '%s' "$cmd" | pcre_ol "$secret_sk_re" | drain pcre_qvl "$secret_sk_fixture_re"
      local st=("${PIPESTATUS[@]}")
      { [ "${st[1]}" -gt 1 ] || [ "${st[2]}" -gt 1 ]; } && { quebrou=1; return 1; }
      return "${st[2]}"
    }
    if [ -z "${pcre_engine:-}" ]; then
      summary='<command not verified: no PCRE engine>'
    elif sonda pcre_ql "$secret_name_re" \
       || sonda pcre_ql "$secret_flag_re" \
       || sonda pcre_qil "$secret_bearer_re" \
       || sonda_sk; then
      summary='<command with secret>'
    elif [ "$quebrou" -eq 1 ]; then
      summary='<command not verified: secret probe failed>'
    fi
  elif [ "$event" = PostToolUse ] && [ "$tool_name" = Bash ]; then
    here=${BASH_SOURCE[0]%/*}; [ "$here" != "${BASH_SOURCE[0]}" ] || here=.
    . "$here/pcre.sh" 2>/dev/null || true
    # `\K` means the same thing in both engines, so the captured text stays the unit name.
    unit=$(printf '%s' "$cmd" | sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n//g' \
      | { [ -n "${pcre_engine:-}" ] && pcre_o1 'systemd-run\b.*--user\b.*--unit[= ]\K[^ ]+' \
          || cat >/dev/null; })
  fi

  # THE ROUTE IN FLIGHT, recorded at startup because the death does not bring it. The
  # `StopFailure` payload carries neither provider nor account (audit 0b lists every key), and the
  # 429 text names the window and never the account — so the session that dies of quota
  # could not say WHO died. The session KNOWS which routing it was launched with: recording
  # the configuration it was GIVEN is not guessing. Guessing would be deriving it from a credential, and that
  # is the line. Nothing here reads, prints or stores a secret:
  #   provider  $PROVIDER as exported; otherwise `agy` if there is a base URL, otherwise `claude`
  #   endpoint  only the HOST of the base URL. The userinfo (`https://who:secret@host`) goes before
  #             any read, and the path and the query never come in
  #   model     what the payload says, otherwise $ANTHROPIC_MODEL
  #   account   the NAME of the configuration home (`claude2`), which is a directory, not a key
  route='{}'
  if [ "$event" = SessionStart ]; then
    # THE LAW'S WRITER RESOLVES FROM ANY CWD. The law names `~/.nott/bin/state.sh set`: a
    # repo-relative path only resolved inside the checkout (measured 2026-09-29 from /var/tmp).
    # install.sh keeps that copy current; a session the installer never saw gets it here, only
    # when absent, so an older bundle never overwrites a newer copy.
    w="$HOME/.nott/bin/state.sh"
    src="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/state.sh"
    if [ ! -e "$w" ] && [ -r "$src" ]; then
      # `ln` publishes without replacing: a newer copy published after the test above wins.
      mkdir -p "${w%/*}" 2>/dev/null && cp "$src" "$w.$$" 2>/dev/null \
        && chmod +x "$w.$$" && ln "$w.$$" "$w" 2>/dev/null
      rm -f "$w.$$" 2>/dev/null
    fi
    r_provider=$(printf '%s' "${PROVIDER:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
    r_base="${ANTHROPIC_BASE_URL:-}"
    # The host, and only the host. `sed` cuts the scheme, then the userinfo, then everything from
    # the first `/`, `?` or `#`. A malformed base URL gives an empty string, never a remainder.
    r_endpoint=$(printf '%s' "$r_base" | sed -e 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' \
                                             -e 's#^[^/@]*@##' -e 's#[/?#].*$##' \
                 | tr -cd 'a-zA-Z0-9.:-')
    [ -n "$r_provider" ] || { [ -n "$r_base" ] && r_provider=agy || r_provider=claude; }
    r_model=$(printf '%s' "$payload" | jq -r '.model.id // .model // ""' 2>/dev/null | tr -cd 'a-zA-Z0-9._-')
    [ -n "$r_model" ] || r_model=$(printf '%s' "${ANTHROPIC_MODEL:-}" | tr -cd 'a-zA-Z0-9._-')
    r_account=$(printf '%s' "${CLAUDE_CONFIG_DIR:-}" | sed 's#/*$##' | sed 's#.*/##' | tr -cd 'a-zA-Z0-9._-')
    [ -n "$r_account" ] || r_account=$(printf '%s' "${NOTT_ACCOUNT:-}" | tr -cd 'a-zA-Z0-9._-')
    # `select(length>0)` INSIDE an object does not give `null` — it gives NOTHING, and a field that
    # gives nothing voids the whole object. Measured by the contract: with no `model` in the payload, the
    # route came out empty, `--argjson` blew up and the hook did not write a single file.
    route=$(jq -nc --arg provider "$r_provider" --arg endpoint "$r_endpoint" \
                   --arg model "$r_model" --arg account "$r_account" --argjson at "$now" \
      'def orna: if length > 0 then . else null end;
       {provider:$provider, endpoint:($endpoint|orna), model:($model|orna),
        account:($account|orna), at:$at} | with_entries(select(.value != null))' 2>/dev/null) || route='{}'
  fi

  # THE `final` MAY COME FROM THE CHANNEL. Owner decision 2026-09-21: he wants the state
  # line OUT of the prose, without losing the statusline. `plugin/scripts/state.sh set`
  # writes `<sid>.final` next to this file, and final-state.sh writes the line it read in the prose or
  # its marker there. At Stop a fresh line joins the payload `last_assistant_message`, before the
  # reply (after it on a retry), so `state_line` below picks it without knowing where it came from.
  #
  # Validity by mtime against `turn_started_at`, which this hook writes on
  # UserPromptSubmit. NOBODY DELETES THE FILE: this hook and `final-state.sh`
  # run in an undefined order on Stop and a consumer that deleted it would leave the
  # other with nothing. A file from the previous turn therefore has to be inert by
  # itself, or the statusline would show the last written state forever.
  # The same literal as final-state.sh (pinned by final-state-contract.sh): a turn whose reply
  # carries no state line shows it, whichever Stop hook runs first.
  marcador_sem_linha='STOPPED: this turn wrote no state line · next action: read the last reply'
  # Only at Stop: the channel is the main turn's reply, and added to an agent's empty report it
  # hid that agent's death (review 7f0ea209).
  if [ "$event" = Stop ] && [ -f "$dir/$sid.final" ]; then
    inicio=$(jq -r '.turn_started_at // empty' "$file" 2>/dev/null)
    # `turn_started_at` IS EPOCH, not ISO --- measured 2026-09-21. A `date -u -d`
    # over the number fails, fell back to `0` by fail-open and ANY file passed
    # as fresh: the validity criterion judged nothing at all.
    case ${inicio:-} in ''|*[!0-9]*) inicio_s=$(date -u -d "${inicio:-@0}" +%s 2>/dev/null || printf 0);; *) inicio_s=$inicio;; esac
    # `stat -c %Y` IS GNU. On Darwin it fails, `escrito_s` stays 0, `0 >= inicio_s` is false,
    # the state line is never prefixed, `final` stays empty and the colour clause falls into
    # the `*)` branch: EVERY turn painted red on the Mac, whatever the line said
    # (measured 2026-09-21, owner complaint). Same family as the branch-lock `date -Is`.
    escrito_s=$(stat -c %Y "$dir/$sid.final" 2>/dev/null \
                || stat -f %m "$dir/$sid.final" 2>/dev/null || printf 0)
    # The marker final-state.sh writes for a turn with no line is not a line: joined to the reply, it
    # would stand before a line a later Stop of the turn writes in the prose. `state_line` shows it
    # by itself.
    # The retry of a blocked Stop (`stop_hook_active`) is the turn's newest text: its own line comes
    # first and the channel only stands in when it wrote none, as final-state.sh reads that retry.
    if [ -n "$inicio" ] && [ "$escrito_s" -ge "$inicio_s" ] \
       && [ "$(head -n1 "$dir/$sid.final" 2>/dev/null)" != "$marcador_sem_linha" ]; then
      payload=$(printf '%s' "$payload" | jq -c --rawfile c "$dir/$sid.final" \
        '($c | rtrimstr("\n")) as $c | (.last_assistant_message // "") as $m
         | .last_assistant_message = (if .stop_hook_active == true then $m + "\n" + $c else $c + "\n" + $m end)' 2>/dev/null || printf '%s' "$payload")
    fi
  fi
  # jq clips the summary to 60; the bound here keeps a 1 MB command out of argv (128 KB per
  # string), where it made jq fail and the update vanish (review, 2026-09-30).
  summary=${summary:0:4096}
  # ONE PROGRAM: it reads the previous state from the file (anything but an object is {}),
  # builds native{}, and prints the new state and then the three fields the colour needs.
  out=$(jq -nr --rawfile prevraw "$file" --arg ev "$event" --argjson now "$now" --arg summary "$summary" \
    --arg unit "$unit" --argjson route "$route" --argjson devolveu "$devolveu" \
    --arg provider "$native_provider" --arg home "$native_home" \
    --arg sem_linha "$marcador_sem_linha" \
    --slurpfile pp <(printf '%s' "$payload") '
    # The payload comes in through a file, never argv: one argv string stops at 128 KB, and a
    # 1 MB command or final message made jq fail and the update vanish (review, 2026-09-30).
    $pp[0] as $p |
    ($p.session_id | tostring) as $psid |
    {provider:$provider, home:$home, session_id:$psid} as $native |
    ($prevraw | fromjson? // {} | if type == "object" then . else {} end) |
    def clip(n): tostring | .[0:n];
    # Cutting at 80 in the middle of a word gives «…nott-sco», which reads as a name
    # that does not exist. Back off to the last space and sign the cut with an ellipsis.
    # The ellipsis counts against the budget: the result never exceeds `n`, so
    # the length contract stays a single number.
    def clipw(n): tostring
      | if length <= n then .
        else ((.[0:n - 1] | sub("[^ ]*$"; "") | sub(" +$"; "")) as $c
              | (if $c == "" then .[0:n - 1] else $c end) + "…") end;
    # THE STATE LINE IS NOT MARKDOWN. The selector below tolerates `**`, backticks and
    # leading bullets to FIND the line, but its consumer is a text
    # statusline: `state.sh show` does `startswith("RUNNING:")` to choose the mark
    # and to cut the verb. Stored verbatim, `**RUNNING:**` does not match — the line
    # came out with the neutral circle `○`, the verb stayed there taking width, and the backticks
    # showed raw (measured 2026-09-20). Stripping here, once, serves every
    # consumer; stripping in the renderer would leave the file dirty for the next one.
    # THE MARKUP OF THE STATE LINE SITS AT THE EDGES OF THE VERB, NOT INSIDE THE PROSE.
    # A global `gsub("__")`/`gsub("\\*\\*")` looks simple and erases identifiers:
    # `__init__` becomes `init` and `**kwargs` becomes `kwargs` (independent review,
    # 2026-09-21). Markup and identifier have the same shape, so it is only stripped where
    # it decorates: the head of the line, and the emphasis glued to the verb.
    #  - bullet/quote/heading/numbering want a space after them, as markdown
    #    requires: without that `>80 tests passed` lost the inequality;
    #  - emphasis (`**`/`__`/`*`/`_`) wants no space, and so it comes separately;
    #  - the backtick is pure presentation, never part of an identifier: all of it goes.
    def demark: tostring | gsub("`"; "")
      | sub("^[[:space:]]*(?:(?:[-*+#>]+|[0-9]+\\.)[[:space:]]+)+"; "")
      | sub("^[[:space:]]*[*_]{1,3}"; "")
      | sub("^(?<v>(?:A CORRER|PARADO|ENTREGUE|RUNNING|STOPPED|DELIVERED):)(?:\\*\\*|__|[*_])"; "\(.v)")
      | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "");
    def base: {phase:"thinking", tool:null, turn_started_at:null, stopped_at:null, final:null,
               open:[], units:[], dead:[], teammate_idle:[]};
    def open_of: [ ($p.background_tasks // [])[]
      | select(((.ambient // false) | not) and (.type // "") != "monitor")
      | {kind:(.type // ""), label:((.command // .agent_type // .id // "") | clip(60)),
         description:((.description // "") | clip(60))} ];
    def state_line: ($p.last_assistant_message // "") | split("\n") | map(select(length > 0))
      | (map(select(test("^[[:space:]]*(([*_#>`-]|[0-9]+\\.|[^[:alnum:][:space:]]{1,4})[[:space:]]*)*(A CORRER|PARADO|ENTREGUE|RUNNING|STOPPED|DELIVERED)[*_`]*[[:space:]]*(:|—|-)"))) | first) as $l
      | if $l != null then $l | demark | clipw(80) elif length > 0 then $sem_linha else "" end;
    (base + .) | .native = $native | .event = $ev
    | if $ev == "Notification" then
        if $p.notification_type == "permission_prompt" then .waiting = true else . end
      elif $ev == "UserPromptSubmit" or $ev == "PreToolUse" or $ev == "PostToolUse"
           or $ev == "PostToolUseFailure" or $ev == "Stop" or $ev == "StopFailure"
           or ($ev == "SessionStart" and ($p.source == "startup" or $p.source == "resume" or $p.source == "clear"))
      then .waiting = false else . end
    | if $ev == "UserPromptSubmit" then
        # A PROMPT OPENS A TURN ONLY WHEN THE LAST ONE CLOSED. A message queued while the turn runs
        # (from a teammate, another session or a task notification) is delivered mid-turn as a
        # UserPromptSubmit; restarting the clock there aged the `state.sh set` line written
        # seconds before, and three turns of session fc21ab3f were refused for a line they had
        # (2026-09-28/29). No apostrophe in this program: it is one single-quoted shell word.
        # A session that starts (startup, resume, clear) has no turn running: SessionStart below
        # clears the clock, so a turn cut short by a dead process does not carry into the next.
        (if ($p.source // "user") == "user" and (.phase == "idle" or .phase == "dead" or .turn_started_at == null)
         then .turn_started_at = $now else . end)
        | .phase = "thinking" | .tool = null | .final = null
        # ponytail: 2.1.272 sends no `source`; the completed-task wakeup is a prompt that
        # starts with <task-notification> and must not erase the death it announces.
        | if (($p.prompt // "") | startswith("<task-notification>")) then . else .dead = [] | .teammate_idle = [] end
      elif $ev == "PreToolUse" then
        .phase = "tool" | .tool = {name:($p.tool_name // ""), summary:($summary | clip(60)), since:$now}
      elif $ev == "PostToolUse" or $ev == "PostToolUseFailure" then
        .phase = "thinking" | .tool = null
        | if $unit != "" then
            .units = (((.units // []) | map(select(.unit != $unit))) + [{unit:$unit, since:$now}] | .[-8:])
          else . end
      elif $ev == "Stop" then
        # A death the model NAMED in its final message is paid for: it stays visible on
        # the status line but never blocks a second turn (review, 2026-09-15).
        ($p.last_assistant_message // "") as $last
        | .phase = "idle" | .tool = null | .stopped_at = $now | .final = state_line | .open = open_of
        # By .label (the task the dispatcher wrote), not .name: six delegates died on one quota
        # window all typed "general-purpose", and matching the TYPE let one mention
        # acknowledge all six (2026-09-15). Case-insensitive: the owner writes «Lane U7».
        | ($last | ascii_downcase) as $lc
        # A label shorter than four characters is not a name, it is a coincidence: «u»
        # matched «tudo» and marked a death acknowledged by accident (review, 2026-09-15).
        | .dead = ((.dead // []) | map(((.label // .name // "") | ascii_downcase) as $k
                                       | if (($k | length) >= 4 and ($lc | contains($k)))
                                         then .acknowledged = true else . end))
      elif $ev == "SubagentStop" then
        .open = open_of
        | ($p.last_assistant_message // "") as $m
        # WHAT RESUMES IT. The dying agent still lists itself in its own background_tasks
        # (audit 0b), and that entry carries the task description the dispatcher wrote — the only
        # field that tells six agents of one type apart. `agent_transcript_path` is the
        # sole record of what it did and pushed before dying: with it the next turn
        # continues from the work; without it the conductor relaunches from zero.
        | ([($p.background_tasks // [])[] | select(.id == ($p.agent_id // "x"))
            | (.description // "")] | first // "") as $task
        # A DEAD AGENT REPORTS NOTHING, or nothing but the error. Measured in review
        # (2026-09-15): matching the failure shape anywhere in the report declared a
        # healthy agent dead for merely DISCUSSING quota, and final-state then blocked
        # the main turn — the owner complaint, manufactured by us. So: an empty
        # report, or a short one (<= 240 chars) that BEGINS with the failure shape and
        # carries no state line of its own.
        | (($m | ltrimstr(" ")) | test("^[^a-zA-Z0-9]{0,4}[*_]*(You have reached|You.ve reached|Claude usage limit|API Error|rate.?limit|429|overloaded|quota)"; "i")) as $shaped
        | if ($devolveu | not)
             and (($m == "" and ($p.agent_type // "") != "")
                  or ($shaped and ($m | length) <= 240 and ($m | test("A CORRER|PARADO|ENTREGUE|RUNNING|STOPPED|DELIVERED") | not))) then
            .dead = ((((.dead // []) | map(select(.id != ($p.agent_id // "x"))))
                      + [{kind:"agent", id:($p.agent_id // ""), name:($p.agent_type // ""),
                          # The label is TEXT WRITTEN BY ANOTHER AGENT (its task description) and it
                          # travels into a block reason the model reads. Keep letters, digits and
                          # plain separators; markdown, backticks, mentions and comment syntax go.
                          label:(((if $task != "" then $task else ($p.agent_type // "") end)
                                  | gsub("[^A-Za-z0-9 ÀÁÂÃÉÊÍÓÔÕÚÇàáâãéêíóôõúç_./-]"; " ")
                                  | gsub(" +"; " ") | ltrimstr(" ") | rtrimstr(" ") | clip(60))),
                          transcript:($p.agent_transcript_path // ""),
                          reason:(if $m == "" then "no report" else ($m | clip(120)) end), at:$now}])
                     | .[-8:])
          else . end
      elif $ev == "StopFailure" then
        # A rate_limit StopFailure is the SESSION dying. The window it names is what the
        # next session needs in order not to re-dispatch blind, so it is a FIELD and not a
        # needle inside a reason the 120-char clip nearly ate (the live 429 fit by one
        # char). Only the shape measured live is read; the wording of another vendor yields
        # null rather than a guessed time. The payload carries NO provider or account
        # (audit 0b lists every key) — see plugin/evals/native/BLOCKED.md.
        (($p.error_details // $p.last_assistant_message // "") | tostring) as $detail
        | ([$detail | scan("(?i)reset(?:s)? at ([0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2})")]
           | first | .[0]?) as $reset
        | .phase = "dead" | .tool = null | .stopped_at = $now
        | .dead += [{kind:"session", id:($p.session_id // ""), name:"", at:$now, resets_at:$reset,
                     route:(.route // null),
                     reason:(($p.error // "unknown") + ": " + ($detail | clip(120)))}]
      elif $ev == "SessionStart" then
        # Startup does not touch the phase: a compaction, or a start that names no source, may be
        # in the middle of a turn. A new process (startup, resume, clear) runs no turn, so its
        # clock goes and the next prompt opens one (review 32a1a902).
        .route = $route
        | if ($p.source == "startup" or $p.source == "resume" or $p.source == "clear") then .turn_started_at = null else . end
      elif $ev == "TeammateIdle" then
        .teammate_idle = ((((.teammate_idle // []) | map(select(.name != ($p.teammate_name // ""))))
                           + [{name:($p.teammate_name // ""), at:$now}]) | .[-8:])
      else . end
    | .updated_at = $now
    | tojson, ([.phase // "", .tool.name // "", .final // ""] | map(tostring) | join("\u001f"))' 2>/dev/null) || exit 0
  next=${out%%$'\n'*}
  [ -n "$next" ] || exit 0
  # A unit separator, not a tab: IFS whitespace would merge the empty tool name away.
  IFS=$'\x1f' read -r fase_cor ferramenta_cor final_cor <<<"${out#*$'\n'}"
  tmp=$(mktemp "$dir/.$sid.XXXXXX" 2>/dev/null) || exit 0
  printf '%s\n' "$next" > "$tmp" && mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp"
  nott_cor_da_fase "$fase_cor" "$ferramenta_cor" "$final_cor"
} 9>>"$file"
exit 0
