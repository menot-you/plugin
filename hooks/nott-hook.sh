#!/bin/sh
set -eu
LC_ALL=C
export LC_ALL

fail() {
  printf '%s\n' "nott-hook: $*" >&2
  exit 2
}

escape_json() {
  awk '
    BEGIN { first = 1 }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\t/, "\\t")
      gsub(/\r/, "\\r")
      if (!first) printf "\\n"
      printf "%s", $0
      first = 0
    }
    END { if (NR > 0) printf "\\n" }
  '
}

block_fixed() {
  printf '{"decision":"block","reason":"%s"}\n' "$1"
}

recursive_stop_guard() {
  LC_ALL=C awk '
    function skip_ws( c) {
      while (pos <= json_length) {
        c = substr(json, pos, 1)
        if (c != " " && c != "\t" && c != "\r" && c != "\n") break
        pos++
      }
    }

    function hex_value(digit) {
      if (digit ~ /^[0-9]$/) return digit + 0
      return index("abcdef", tolower(digit)) + 9
    }

    function parse_string( c, digit, offset, code, encoded) {
      if (substr(json, pos, 1) != "\"") return 0
      pos++
      parsed_string = ""
      while (pos <= json_length) {
        c = substr(json, pos, 1)
        if (c == "\"") {
          pos++
          return 1
        }
        if (c == "\\") {
          pos++
          if (pos > json_length) return 0
          c = substr(json, pos, 1)
          if (c == "\"" || c == "\\" || c == "/" || c == "b" || c == "f" || c == "n" || c == "r" || c == "t") {
            parsed_string = parsed_string "\\" c
            pos++
            continue
          }
          if (c != "u" || pos + 4 > json_length) return 0
          code = 0
          for (offset = 1; offset <= 4; offset++) {
            digit = substr(json, pos + offset, 1)
            if (digit !~ /^[0-9A-Fa-f]$/) return 0
            code = (code * 16) + hex_value(digit)
          }
          encoded = substr(json, pos - 1, 6)
          if (code >= 32 && code <= 126) {
            parsed_string = parsed_string sprintf("%c", code)
          } else {
            parsed_string = parsed_string encoded
          }
          pos += 5
          continue
        }
        if (c ~ /[[:cntrl:]]/) return 0
        parsed_string = parsed_string c
        pos++
      }
      return 0
    }

    function parse_number( remainder) {
      remainder = substr(json, pos)
      if (match(remainder, /^-?(0|[1-9][0-9]*)([.][0-9]+)?([eE][+-]?[0-9]+)?/) != 1) return 0
      pos += RLENGTH
      return 1
    }

    function parse_array( c) {
      if (substr(json, pos, 1) != "[") return 0
      pos++
      skip_ws()
      if (substr(json, pos, 1) == "]") {
        pos++
        return 1
      }
      while (pos <= json_length) {
        if (!parse_value()) return 0
        skip_ws()
        c = substr(json, pos, 1)
        if (c == "]") {
          pos++
          return 1
        }
        if (c != ",") return 0
        pos++
        skip_ws()
      }
      return 0
    }

    function parse_object(is_top, key, kind, c) {
      if (substr(json, pos, 1) != "{") return 0
      pos++
      skip_ws()
      if (substr(json, pos, 1) == "}") {
        pos++
        return 1
      }
      while (pos <= json_length) {
        if (!parse_string()) return 0
        key = parsed_string
        skip_ws()
        if (substr(json, pos, 1) != ":") return 0
        pos++
        if (!parse_value()) return 0
        kind = value_kind
        if (is_top && key == "stop_hook_active") {
          found++
          active = (kind == "true")
        }
        skip_ws()
        c = substr(json, pos, 1)
        if (c == "}") {
          pos++
          return 1
        }
        if (c != ",") return 0
        pos++
        skip_ws()
      }
      return 0
    }

    function parse_value( c) {
      skip_ws()
      c = substr(json, pos, 1)
      if (c == "{") {
        if (!parse_object(0)) return 0
        value_kind = "other"
        return 1
      }
      if (c == "[") {
        if (!parse_array()) return 0
        value_kind = "other"
        return 1
      }
      if (c == "\"") {
        if (!parse_string()) return 0
        value_kind = "other"
        return 1
      }
      if (substr(json, pos, 4) == "true") {
        pos += 4
        value_kind = "true"
        return 1
      }
      if (substr(json, pos, 5) == "false") {
        pos += 5
        value_kind = "false"
        return 1
      }
      if (substr(json, pos, 4) == "null") {
        pos += 4
        value_kind = "other"
        return 1
      }
      if (c == "-" || c ~ /^[0-9]$/) {
        if (!parse_number()) return 0
        value_kind = "other"
        return 1
      }
      return 0
    }

    { json = json $0 "\n" }
    END {
      pos = 1
      json_length = length(json)
      found = 0
      active = 0
      valid = parse_object(1)
      skip_ws()
      if (pos <= json_length) valid = 0
      exit !(valid && (found > 1 || (found == 1 && active)))
    }
  '
}

command -v head >/dev/null 2>&1 || fail "required input limiter is unavailable"
command -v od >/dev/null 2>&1 || fail "required input encoder is unavailable"
command -v awk >/dev/null 2>&1 || fail "required input decoder is unavailable"
payload_limit=1048576
payload_hex=$(head -c $((payload_limit + 1)) 2>/dev/null | od -An -v -tx1) || fail "unable to encode bounded hook input"
payload_measure=$(printf '%s\n' "$payload_hex" | awk '
  {
    octets += NF
    for (field = 1; field <= NF; field++) if ($field == "00") has_nul = 1
  }
  END { printf "%d %d", octets, has_nul }
') || fail "unable to measure bounded hook input"
payload_octets=${payload_measure%% *}
payload_has_nul=${payload_measure#* }
payload_oversized=false
if [ "$payload_octets" -gt "$payload_limit" ]; then
  payload_oversized=true
  payload=''
elif [ "$payload_has_nul" -eq 1 ]; then
  # Raw NUL cannot occur in JSON. Keep the sample invalid instead of letting
  # shell command substitution silently delete bytes into a different object.
  payload=''
else
  payload=$(printf '%s\n' "$payload_hex" | awk '
    function digit(value) {
      if (value ~ /^[0-9]$/) return value + 0
      return index("abcdef", tolower(value)) + 9
    }
    function octet(value) {
      return (digit(substr(value, 1, 1)) * 16) + digit(substr(value, 2, 1))
    }
    { for (field = 1; field <= NF; field++) printf "%c", octet($field) }
  ') || fail "unable to decode bounded hook input"
fi
unset payload_hex payload_measure payload_octets payload_has_nul
event=${1-}

# Voice lint is opt-in. It stores only timestamp, mode, and finding classes;
# transcript text and session identifiers never enter the state file.
voice_lint() {
  [ "${NOTT_VOICE_LINT:-off}" = on ] || return 0

  # The recursion flag cannot be authenticated after bounded input truncation.
  # Fail open without state or output so an oversized recursive Stop cannot loop.
  if [ "$payload_oversized" = true ]; then
    return 0
  fi

  # One parser owns recursion preflight in every dependency state. Duplicate
  # top-level flags are ambiguous, so optional lint fails open for availability.
  if printf '%s' "$payload" | recursive_stop_guard; then
    return 0
  fi

  for command_name in awk chmod date grep jq mkdir mktemp mv rm tail wc; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      block_fixed "voice-lint is enabled but a required local command is unavailable; no state was written."
      return 0
    fi
  done

  if ! printf '%s' "$payload" | jq -e 'type == "object"' >/dev/null 2>&1; then
    block_fixed "voice-lint received an invalid Stop payload; no state was written."
    return 0
  fi

  active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')
  [ "$active" != true ] || return 0

  mode=${NOTT_VOICE_LINT_MODE:-warn}
  case "$mode" in
    warn|block) ;;
    *)
      block_fixed "voice-lint mode must be warn or block; no state was written."
      return 0
      ;;
  esac

  tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
  [ -n "$tp" ] || return 0
  [ ! -L "$tp" ] || {
    block_fixed "voice-lint refused a symlinked transcript; no state was written."
    return 0
  }
  [ -f "$tp" ] && [ -r "$tp" ] || {
    block_fixed "voice-lint could not read the declared transcript; no state was written."
    return 0
  }

  transcript_bytes=$(wc -c <"$tp" 2>/dev/null) || {
    block_fixed "voice-lint could not size the declared transcript; no state was written."
    return 0
  }
  [ "$transcript_bytes" -le 8388608 ] || {
    block_fixed "voice-lint refused a transcript larger than 8 MiB; no state was written."
    return 0
  }

  last=$(jq -rs '[.[] | select(.type == "assistant")] | last | .message.content // [] | map(select(.type == "text") | .text) | join("\n")' "$tp" 2>/dev/null) || {
    block_fixed "voice-lint could not parse the declared transcript; no state was written."
    return 0
  }
  [ -n "$last" ] || return 0

  tail_para=$(printf '%s\n' "$last" | awk 'BEGIN { RS = "" } { p = $0 } END { print p }')
  findings=''
  qm=$(printf '%s' "$tail_para" | awk -F '?' '{ n += NF - 1 } END { print n + 0 }')
  [ "$qm" -lt 2 ] || findings="menu-close(q=$qm)"
  if printf '%s' "$tail_para" | grep -qiE 'Topa\?|\bOu (quer|prefere)m?\b'; then
    findings="$findings menu-pattern"
  fi
  praise_pattern='\b(incr[ií]vel|fodon[ao]|perfeit[oa]|genial|insan[oa]|impressionante|sensacional|maravilhos[oa]|espetacular|amazing|incredible|awesome|perfect)\b'
  praise=$(printf '%s' "$last" | grep -icE "$praise_pattern" 2>/dev/null) || praise=0
  justified=$(printf '%s' "$last" | grep -iE "$praise_pattern" 2>/dev/null | grep -icE '\b(porque|pois|por causa|j[aá] que|because)\b' 2>/dev/null) || justified=0
  unjustified=$((praise - justified))
  [ "$unjustified" -le 0 ] || findings="$findings filler-praise($unjustified)"
  findings=${findings# }
  [ -n "$findings" ] || return 0

  state_base=${XDG_STATE_HOME:-}
  if [ -z "$state_base" ]; then
    [ -n "${HOME:-}" ] || {
      block_fixed "voice-lint cannot resolve a private state directory; no state was written."
      return 0
    }
    state_base=$HOME/.local/state
  fi
  state_dir=$state_base/nott
  umask 077
  if [ -e "$state_dir" ] || [ -L "$state_dir" ]; then
    [ -d "$state_dir" ] && [ ! -L "$state_dir" ] || {
      block_fixed "voice-lint refused an unsafe private state directory; no state was written."
      return 0
    }
  fi
  mkdir -p "$state_dir" 2>/dev/null || {
    block_fixed "voice-lint cannot create its private state directory; no state was written."
    return 0
  }
  chmod 700 "$state_dir" 2>/dev/null || {
    block_fixed "voice-lint cannot secure its private state directory; no state was written."
    return 0
  }

  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || {
    block_fixed "voice-lint cannot obtain a timestamp; no state was written."
    return 0
  }
  state_file=$state_dir/voice-lint.jsonl
  if [ -e "$state_file" ] || [ -L "$state_file" ]; then
    [ -f "$state_file" ] && [ ! -L "$state_file" ] || {
      block_fixed "voice-lint refused an unsafe private state file; no state was written."
      return 0
    }
  fi
  state_tmp=$(mktemp "$state_dir/voice-lint.XXXXXX" 2>/dev/null) || {
    block_fixed "voice-lint cannot allocate private temporary state; no state was written."
    return 0
  }
  {
    if [ -f "$state_file" ]; then
      tail -n 199 "$state_file" | jq -c '
        select(
          type == "object"
          and (keys | sort) == ["findings", "mode", "ts"]
          and (.ts | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
          and (.mode == "warn" or .mode == "block")
          and (.findings | type == "string" and test("^(menu-close\\(q=[0-9]{1,7}\\)( menu-pattern)?( filler-praise\\([0-9]{1,7}\\))?|menu-pattern( filler-praise\\([0-9]{1,7}\\))?|filler-praise\\([0-9]{1,7}\\))$"))
        )
      ' 2>/dev/null || :
    fi
    printf '{"ts":"%s","mode":"%s","findings":"%s"}\n' "$timestamp" "$mode" "$findings"
  } >"$state_tmp" 2>/dev/null || {
    rm -f "$state_tmp" 2>/dev/null || :
    block_fixed "voice-lint cannot write bounded private state; no finding was accepted."
    return 0
  }
  chmod 600 "$state_tmp" 2>/dev/null || {
    rm -f "$state_tmp" 2>/dev/null || :
    block_fixed "voice-lint cannot secure bounded private state; no finding was accepted."
    return 0
  }
  mv "$state_tmp" "$state_file" 2>/dev/null || {
    rm -f "$state_tmp" 2>/dev/null || :
    block_fixed "voice-lint cannot replace bounded private state; no finding was accepted."
    return 0
  }

  if [ "$mode" = block ] && [ "$active" != true ]; then
    reason=$(printf 'voice-lint %s — rewrite the close as the observed win plus one next action; use one question at most and justify praise.' "$findings" | escape_json) || {
      block_fixed "voice-lint found a blocking close but could not encode its diagnostic."
      return 0
    }
    printf '{"decision":"block","reason":"%s"}\n' "$reason"
  fi
  return 0
}

if [ "$event" = Stop ]; then
  voice_lint
  exit 0
fi

plugin_root=${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}
[ -n "$plugin_root" ] || fail "plugin root is unavailable"
[ -d "$plugin_root" ] || fail "plugin root is not a directory: $plugin_root"
canon=$plugin_root/NOTT.md
[ -f "$canon" ] || fail "NOTT.md is unavailable at plugin root"
[ -r "$canon" ] || fail "NOTT.md is not readable"
command -v awk >/dev/null 2>&1 || fail "required text utility is unavailable"

case "$event" in
  SubagentStart)
    context=$( { awk '/^## /{exit} {print}' "$canon"; printf 'Full canon: %s — read it before substantive work.\n' "$canon"; } | escape_json ) || fail "unable to encode canon context"
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$context"
    ;;
  UserPromptSubmit)
    context=$( { awk '/^## /{exit} {print}' "$canon"; printf 'Full canon: %s — read it before substantive work.\n' "$canon"; } | escape_json ) || fail "unable to encode canon context"
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$context"
    ;;
  # This handler remains deliberately unregistered. Register it only with a
  # matcher limited to mutating tools; never run it before every read.
  PreToolUse)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Before the action, verify current state, exact scope, authority, rollback, and the verification that proves this result. Stop on unexpected reach."}}'
    ;;
  PostToolUse)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Bind the next claim to observed output. State the strongest proven state, exact gap, rollback status, and one next action. Never repeat an uncertain action."}}'
    ;;
  *)
    fail "unsupported event: ${event:-<missing>}"
    ;;
esac
