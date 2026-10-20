#!/usr/bin/env -S bash -p
# The marker regex below reads bytes differently under LC_ALL=C; only a locale the box has is pinned.
if [ "$(LC_ALL=C.UTF-8 locale charmap 2>/dev/null)" = UTF-8 ]; then export LC_ALL=C.UTF-8; fi
# final-state — Stop: records the turn's state line for the status line, and judges the reply's
# voice (it took in voice.sh). The voice check is the only thing it may print.
#
# A state line starts (after optional markdown emphasis) with RUNNING / STOPPED / DELIVERED
# followed by `:`, anywhere in the last message at line start, or comes from the `<sid>.final`
# channel `state.sh set` writes. A line found in the prose is written to that channel; a turn with
# no line leaves a fixed marker there and one `miss` record in the audit log.
#
# THE STATE LINE IS SILENT (owner order 2026-10-06): the advisory prose findings this hook
# printed and re-injected burned tokens on the owner's screen and added nothing, so they were
# deleted. Only the voice check below speaks, and only on a pt-PT word.
# Fail-open: a payload that does not parse, a missing transcript or an empty turn exit 0.
set -uo pipefail

payload=$(cat)
printf '%s' "$payload" | jq -e . >/dev/null 2>&1 || exit 0
# The next prompt carries what the voice check found in the last reply (`<sid>.voice-advice`), once.
if [ "$(printf '%s' "$payload" | jq -r '.hook_event_name // ""')" = UserPromptSubmit ]; then
  sid_a=$(printf '%s' "$payload" | jq -r '.session_id // ""' | tr -cd 'a-zA-Z0-9-')
  [ -n "$sid_a" ] || exit 0
  f_a="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nott/session-state/$sid_a.voice-advice"
  t_a=$(cat "$f_a" 2>/dev/null; rm -f "$f_a")
  [ -n "$t_a" ] || exit 0
  jq -Rsc '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: ("voice, about your previous reply (advisory, do not resend it): " + .)}}' <<<"$t_a"
  exit 0
fi
reentrada=0
if [ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = true ]; then reentrada=1; fi
# A DISPATCHED nSPAWN CHILD ANSWERS ITS CALLER, NOT THE OWNER: its final text is its product
# (run 10eb29fe). Only the session nSPAWN launched is exempt: a session that inherits the
# child's environment has another `session_id` (review 7f0a88ff).
printf '%s' "$payload" | jq -e --arg s "${NOTT_NSPAWN_SESSION_ID:-}" '$s != "" and .session_id == $s' >/dev/null && exit 0
# At Stop time the transcript does not yet hold the final text (measured 2026-09-14); the payload's
# `last_assistant_message` is the turn's own. A Stop without it (a host that does not send it, a
# final message with no text block) has nothing of its own to record: nothing is written or marked,
# as session-state.sh shows nothing for it.
texto_proprio=$(printf '%s' "$payload" | jq -r '.last_assistant_message // ""')
[ -n "$texto_proprio" ] || exit 0

# THE VOICE CHECK (it was voice.sh) — Stop: a Portuguese reply to the owner is written in Brazilian Portuguese.
#
# Measured 2026-09-25 over 30 days of final replies whose user turn was Portuguese:
# 136 of 460 on Claude, 63 of 226 on Codex and 18 of 46 on AGY carried a European
# Portuguese word, against the owner's standing correction (pt-BR, never pt-PT).
# The words were `ficheiro(s)` 878 times, `a correr` 332, `registo` 124, `facto` 122,
# and the words for screen and user 17 and 12. plugin/NOTT.md states the same list.
#
# Only PROSE is judged. Removed first: the state-line MARKER (its text is owner-facing
# and stays judged), fenced and inline code, quoted lines and straight-quoted spans (a log or an error; the
# guillemets these models use for their own paraphrase stay judged), URLs, path-shaped and
# dotted tokens (file names, fields), since a
# file name, a log line or a quote is not the reply's own voice. A reply is
# judged unless its body reads as English or Spanish (see the language block below);
# an English worker final never reaches the list. Every entry of the list is
# justified by plugin/tests/fixtures/final-state/voice/ (voice-contract.sh): it
# catches a real reply and fires on no clean one.
#
# Output: `{"systemMessage":...}` on a hit (advisory), nothing otherwise. ONE SHOT: a
# Stop with `stop_hook_active` true is not judged again.
# voice_check: its variables are local, so the state-line code below reads none of them.
voice_check() {
local last estado prose body gate english spanish signal pt en es lista achados r sid dir
last=$texto_proprio
# The state-line regex, as voice.sh had it, including the pre-2026-09-23 markers.
estado='^[[:space:]]*([*_#>`-]|[0-9]+\.|[^[:alnum:][:space:]]{1,4})*[[:space:]]*(A CORRER|PARADO|ENTREGUE|RUNNING|STOPPED|DELIVERED)[*_`]*[[:space:]]*(:|—|-)'
# Removes what is not the reply's own voice from stdin.
strip() {
  awk '{ run = $0; sub(/^[[:space:]]*/, "", run) }
       !open && match(run, /^(````*|~~~~*)/) { open = substr(run, 1, RLENGTH); next }
       open && match(run, /^(````*|~~~~*)[[:space:]]*$/) && substr(run, 1, 1) == substr(open, 1, 1) \
         && RLENGTH >= length(open) { open = ""; next }
       !open' \
  | grep -vE '^[[:space:]]*>' \
  | sed -E 's/``([^`]|`[^`])*``/ /g; s/`[^`]*`/ /g; s/"[^"]*"/ /g;' \
  | sed -E 's#https?://[^[:space:]]+# #g; s#[~./]?[[:alnum:]_.-]+/[[:alnum:]_./-]+# #g; s/[[:alnum:]_-]+(\.[[:alnum:]_-]+)+/ /g'
}
# The judged prose keeps the state line's text: the owner reads it too.
prose=$(printf '%s\n' "$last" | sed -E "s/${estado}/ /" | strip)
# The language is read from the body; a state line is often English over a
# Portuguese reply. A reply that is only a state line is read from that line.
body=$(printf '%s\n' "$last" | grep -vE "$estado" | strip)
# A here-string and grep, not ${body//[[:space:]]/}: that expansion is quadratic, 4.5 s on 6000 lines.
grep -q '[^[:space:]]' <<<"$body" || body=$prose

# The language, read from the body with the listed words taken out (an English reply
# that names them is still English). Portuguese when it carries ANY Portuguese signal
# word (a tilde or cedilla word counts; Spanish has neither); with no signal, only
# when it carries no English and no Spanish function word either, since a short pt-PT
# reply often has none (live probe and reviews of 2026-09-26).
gate='(?<!\w)([Nn]ão|[Ss]ão|[Vv]ocê|[Tt]ambém|[Ee]ntão|[Ii]sso|[Ee]ssa|[Ee]sse|[Uu]ma|[Pp]elo|[Pp]ela|[Jj]á|[Ff]oi|[Cc]om|[Aa]os?|às?|\w*[ãõçÃÕÇ]\w*)(?!\w)'
english='(?<!\w)(the|and|is|are|was|were|of|to|in|on|at|with|for|from|by|that|this|it|be|not)(?!\w)'
spanish='(?<!\w)(el|la|los|las|del|es|y|en|lo)(?!\w)'
signal=$(printf '%s\n' "$body" | sed -E 's/[[:alpha:]]*(ficheir|ecrã|regist|utilizador|equipa|contact|fact)[[:alpha:]]*/ /Ig')
pt=$(printf '%s\n' "$signal" | grep -cP "$gate")
en=$(printf '%s\n' "$signal" | grep -ciP "$english")
es=$(printf '%s\n' "$signal" | grep -ciP "$spanish")
[ "$pt" -gt 0 ] || { [ "$en" -eq 0 ] && [ "$es" -eq 0 ]; } || return 0

lista='(?<!\w)(?<!--)(ficheiros?|ecrãs?|registos?|regist(ar|a|am|ado|ada|ados|adas|ou|ei)|(?<!setor )(?<!dispositivo )utilizador(es|a|as)?|equipas?|contactos?|(?<!\bde )(?<!\bipso )factos?|(?<=estou |estar |está |estão |estava |estavam |esteve |fico |fica |ficam |ficou |continua |continuam )a correr|estás|tens de)(?!\w)(?!-(?!(se|me|te|lhes?|nos|vos|[ol]?[oa]s?)(?!\w)))'
achados=$(printf '%s\n' "$prose" | grep -oiP "$lista" | sed 's/.*/\L&/' | sort -u | paste -sd, - | sed 's/,/, /g')
[ -n "$achados" ] || return 0
# ADVISORY, NEVER A BLOCK (owner decision, 2026-10-06): the reply is already on screen,
# so a block made the owner read a second reply. `systemMessage` shows the finding, and
# `<sid>.voice-advice` hands it to the model on the next prompt (the UserPromptSubmit branch above).
r="voice: pt-PT in a Portuguese reply: $achados. Write the next replies in Brazilian Portuguese (arquivo, rodando, registro, fato, tela, usuário, equipe, contato; você está, você tem que); code, quotes and paths are not judged."
sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' | tr -cd 'a-zA-Z0-9-')
dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nott/session-state"
if [ -n "$sid" ] && mkdir -p -m 700 "$dir" 2>/dev/null; then printf '%s\n\n' "$r" >"$dir/$sid.voice-advice" 2>/dev/null || :; fi
jq -cn --arg r "$r" '{systemMessage:$r}'
}
# finish: the voice check runs LAST, once the state line is on record, so a slow judgement of a
# long reply cannot cost the line its write under the hook's timeout. A re-entry is not judged.
finish() {
  [ "$reentrada" = 1 ] || voice_check
  exit 0
}
# Codex and AGY run this hook through their runners for the voice check alone: their sessions
# have no Claude statusline to read a state line (README client matrix).
case ${NOTT_HOOK_CLIENT:-claude} in claude) ;; *) finish ;; esac

# THE MARKER LIVES IN ONE ASSIGNMENT: the self-test mutates it by `sed` over a unique occurrence.
# state-line compat, pre-2026-09-23, remove after one release: A CORRER|PARADO|ENTREGUE
MARCADOR_ESTADO='^[[:space:]]*(([*_#>`-]|[0-9]+\.|[^[:alnum:][:space:]]{1,4})[[:space:]]*)*(A CORRER|PARADO|ENTREGUE|RUNNING|STOPPED|DELIVERED)[*_`]*[[:space:]]*(:|—|-)'
# THE LINE MAY COME FROM THE CHANNEL (owner decision 2026-09-21: a clean chat that keeps the
# status line). Valid by mtime against `turn_started_at` (epoch), never by existence: nobody
# deletes the file, so one from the previous turn must be inert by itself.
# The marker of a turn with no state line says only that none was reported.
marcador='STOPPED: this turn wrote no state line · next action: read the last reply'
canal_marcado=0
sid_canal=$(printf '%s' "$payload" | jq -r '.session_id // ""' | tr -cd 'a-zA-Z0-9-')
if [ -n "$sid_canal" ]; then
  dir_canal="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/nott/session-state"
  if [ -f "$dir_canal/$sid_canal.final" ]; then
    inicio=$(jq -r '.turn_started_at // empty' "$dir_canal/$sid_canal.json" 2>/dev/null)
    case ${inicio:-} in ''|*[!0-9]*) inicio_s=$(date -u -d "${inicio:-@0}" +%s 2>/dev/null || printf 0);; *) inicio_s=$inicio;; esac
    # `stat -c` is GNU; Darwin's stat takes `-f %m` (the same fallback as session-state.sh).
    escrito_s=$(stat -c %Y "$dir_canal/$sid_canal.final" 2>/dev/null \
                || stat -f %m "$dir_canal/$sid_canal.final" 2>/dev/null || printf 0)
    if [ -n "$inicio" ] && [ "$escrito_s" -ge "$inicio_s" ]; then
      linha_canal=$(cat "$dir_canal/$sid_canal.final")
      # The marker is never a written line (review a44dba90).
      [ "$linha_canal" = "$marcador" ] && { linha_canal=''; canal_marcado=1; }
    fi
  fi
fi

last="${linha_canal:+$linha_canal
}$texto_proprio"
linha_estado=$(grep -m1 -E "$MARCADOR_ESTADO" <<<"$last")
# canal_escreve <line>: the line into the channel `state.sh set` writes (its first line, raw).
# Dated at the turn's start (0 when unknown): this turn's for every reader, inert once the next
# turn opens. `touch -d @` is GNU; BSD takes `-t` from `date -r`, in UTC.
canal_escreve() {
  [ -n "$sid_canal" ] && mkdir -p -m 700 "$dir_canal" 2>/dev/null || return 0
  local f=$dir_canal/$sid_canal.final inicio_t
  printf '%s\n' "${1%%$'\n'*}" > "$f" 2>/dev/null || return 0
  inicio_t=$(jq -r '.turn_started_at // empty' "$dir_canal/$sid_canal.json" 2>/dev/null)
  case $inicio_t in ''|*[!0-9]*) inicio_t=0 ;; esac
  touch -d "@$inicio_t" "$f" 2>/dev/null \
    || TZ=UTC0 touch -t "$(TZ=UTC0 date -r "$inicio_t" +%Y%m%d%H%M.%S 2>/dev/null)" "$f" 2>/dev/null
}
# marca_turno: the turn ends with no state line. The marker goes to the channel, and the miss is
# one record in the audit log, `jq 'select(.miss)'` counts them: one per Stop with no line.
marca_turno() {
  canal_escreve "$marcador"
  auditoria="${XDG_STATE_HOME:-$HOME/.local/state}/nott/system1-audit.jsonl"
  mkdir -p "$(dirname "$auditoria")" 2>/dev/null \
    && jq -cn --arg s "$sid_canal" '{at: (now|todate), sid: $s, miss: "no state line"}' >> "$auditoria" 2>/dev/null
}
# THE RETRY OF A STOP another hook blocked: a line it wrote in its own text replaces what the
# channel holds; with no line it is marked, unless an earlier Stop of this turn already left a
# line or the marker.
if [ "$reentrada" = 1 ]; then
  linha_propria=$(grep -m1 -E "$MARCADOR_ESTADO" <<<"$texto_proprio")
  if [ -n "$linha_propria" ]; then canal_escreve "$linha_propria"
  elif [ -z "$linha_estado" ] && [ "$canal_marcado" = 0 ]; then marca_turno; fi
  finish
fi
# A turn with no line is marked over any line of an earlier turn; a line written in the prose goes
# to the channel, as `state.sh set` would have put it.
if [ -z "$linha_estado" ]; then
  marca_turno
elif [ "$linha_estado" != "${linha_canal:-}" ]; then
  canal_escreve "$linha_estado"
fi
finish
