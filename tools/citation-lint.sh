#!/usr/bin/env bash
set -euo pipefail

die() { printf 'citation-lint: %s\n' "$*" >&2; exit 2; }
for command_name in awk dirname find grep sed sort; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done
[[ "$#" -ge 2 ]] || die "usage: citation-lint.sh REPO_ROOT DOCUMENT [DOCUMENT...]"
root=$1
shift
[[ -d "$root" && ! -L "$root" ]] || die "repository root is not an ordinary directory: $root"
decisions=$root/decisions.md
[[ -f "$decisions" ]] || die "closed glossary is unavailable: $decisions"

repo_dirs='agents|skills|hooks|bin|tests|tools|release|assets|plugin|docs|\.github|\.agents|\.claude-plugin|\.codex-plugin'
status=0
finding() { printf 'citation-lint: %s: %s\n' "$1" "$2" >&2; status=1; }
resolves_bare() {
  find "$root" -name "$1" -type f -not -path '*/.git/*' -print -quit 2>/dev/null | grep -q .
}
resolves_decision() {
  awk -v wanted="**$1**" '$1 == "-" && $2 == wanted { found=1 } END { exit !found }' "$decisions"
}
is_regular_file() {
  [[ -f "$1" && ! -L "$1" ]]
}
is_git_metadata_target() {
  case "/$1/" in
    */.[Gg][Ii][Tt]/*) return 0 ;;
    *) return 1 ;;
  esac
}
validate_link_target() {
  local document=$1 docdir=$2 token=$3
  if is_git_metadata_target "$token"; then
    finding "$document" "citation enters Git metadata: $token"
  elif ! is_regular_file "$docdir/$token" && ! is_regular_file "$root/$token"; then
    finding "$document" "Markdown link target is not a regular candidate file: $token"
  fi
}
extract_markdown_targets() {
  LC_ALL=C awk '
    BEGIN { squote = sprintf("%c", 39) }
    function is_hspace(character) {
      return character == " " || character == "\t"
    }
    function skip_hspace(text, position) {
      while (position <= length(text) && is_hspace(substr(text, position, 1))) position++
      return position
    }
    function title_end(text, position, opener,   closer, character) {
      closer = (opener == "(" ? ")" : opener)
      for (position++; position <= length(text); position++) {
        character = substr(text, position, 1)
        if (character == "\\" && position < length(text)) {
          position++
          continue
        }
        if (character == closer) return position
      }
      return 0
    }
    function emit_inline(text,   position, start, character, depth, target, before_space, opener, last) {
      parsed = 1
      position = skip_hspace(text, 1)
      if (position > length(text)) return
      if (substr(text, position, 1) == "<") {
        start = ++position
        for (; position <= length(text); position++) {
          character = substr(text, position, 1)
          if (character == "\\" && position < length(text)) {
            position++
            continue
          }
          if (character == ">") break
        }
        if (position > length(text)) return
        target = substr(text, start, position - start)
        position++
      } else {
        start = position
        depth = 0
        for (; position <= length(text); position++) {
          character = substr(text, position, 1)
          if (character == "\\" && position < length(text)) {
            position++
            continue
          }
          if (is_hspace(character)) break
          if (character == "(") {
            depth++
            continue
          }
          if (character == ")") {
            if (depth == 0) break
            depth--
          }
        }
        if (depth != 0) return
        target = substr(text, start, position - start)
      }
      before_space = position
      position = skip_hspace(text, position)
      if (substr(text, position, 1) == ")") {
        parsed = position
        if (target != "") print "link\t" target
        return
      }
      if (position == before_space) return
      opener = substr(text, position, 1)
      if (opener != "\"" && opener != squote && opener != "(") return
      last = title_end(text, position, opener)
      if (last == 0) return
      position = skip_hspace(text, last + 1)
      if (substr(text, position, 1) != ")") return
      parsed = position
      if (target != "") print "link\t" target
    }
    function emit_reference(text,   position, start, character, target) {
      position = skip_hspace(text, 1)
      if (position > length(text)) return
      if (substr(text, position, 1) == "<") {
        start = ++position
        for (; position <= length(text); position++) {
          character = substr(text, position, 1)
          if (character == "\\" && position < length(text)) {
            position++
            continue
          }
          if (character == ">") break
        }
        if (position > length(text)) return
        target = substr(text, start, position - start)
      } else {
        start = position
        while (position <= length(text) && !is_hspace(substr(text, position, 1))) position++
        target = substr(text, start, position - start)
      }
      if (target != "") print "link\t" target
    }
    function scan_reference(line,   text, indent, close_at) {
      text = line
      indent = 0
      while (substr(text, 1, 1) == " " && indent < 4) {
        text = substr(text, 2)
        indent++
      }
      if (indent > 3 || substr(text, 1, 1) != "[") return
      close_at = index(text, "]:")
      if (close_at < 3) return
      emit_reference(substr(text, close_at + 2))
    }
    {
      scan_reference($0)
      scan = $0
      while ((marker = index(scan, "](")) != 0) {
        tail = substr(scan, marker + 2)
        emit_inline(tail)
        scan = substr(tail, parsed + 1)
      }
    }
  ' <"$1"
}
for document in "$@"; do
  [[ -f "$document" ]] || die "document not found: $document"
  docdir=$(dirname -- "$document")
  tick='`'
  while IFS=$'\t' read -r citation_kind token; do
    [[ -n "$token" ]] || continue
    if [[ "$citation_kind" == code ]]; then
      case "$token" in *'{'*|*'}'*) continue ;; esac
    fi
    private_one='/no''tt/'
    private_two='/ho''me/'
    private_three='/Us''ers/'
    private_four='/var/tm''p/'
    if [[ "$token" == "$private_one"* || "$token" == "$private_two"* || "$token" == "$private_three"* || "$token" == "$private_four"* ]]; then
      finding "$document" "private absolute path cited"
      continue
    fi
    token=${token%%#*}
    [[ -n "$token" ]] || continue
    case "$token" in
      ../*|*/../*|*/..) finding "$document" "citation escapes the repository: $token"; continue ;;
    esac
    case "$token" in
      http://*|https://*|mailto:*) ;;
      *)
        if [[ "$citation_kind" == link && "$token" != *:* ]]; then
          validate_link_target "$document" "$docdir" "$token"
        elif [[ "$token" =~ ^($repo_dirs)/ ]]; then
          checkpath=${token%\*}
          if [[ "$checkpath" =~ \.[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
            is_regular_file "$root/$checkpath" || finding "$document" "cited repository file does not resolve: $token"
          else
            [[ -e "$root/$checkpath" ]] || finding "$document" "cited repository path does not resolve: $token"
          fi
        elif [[ "$token" =~ ^[^:/[:space:]]+/[^[:space:]]+\.[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
          if ! is_regular_file "$docdir/$token" && ! is_regular_file "$root/$token"; then
            finding "$document" "recognized local file citation does not resolve: $token"
          fi
        elif [[ "$token" =~ ^[A-Za-z0-9_.-]+\.(md|sh|json|ya?ml)$ ]]; then
          if ! is_regular_file "$docdir/$token" && ! is_regular_file "$root/$token" && ! resolves_bare "$token"; then
            finding "$document" "cited file does not resolve: $token"
          fi
        elif [[ "$token" =~ ^d[0-9]+$ ]]; then
          finding "$document" "bare decision id is not a slug: $token"
        elif [[ "$token" =~ ^d[0-9]+-[a-z0-9-]+$ ]]; then
          resolves_decision "$token" || finding "$document" "decision slug does not resolve in decisions.md: $token"
        elif [[ "$token" =~ ^d[0-9] ]]; then
          finding "$document" "malformed decision citation: $token"
        fi
        ;;
    esac
  done < <(
    {
      grep -oE "${tick}[^${tick}]+${tick}" -- "$document" 2>/dev/null | sed "s/^${tick}//; s/${tick}$//" | awk '{ print "code\t" $0 }' || :
      extract_markdown_targets "$document"
    } | LC_ALL=C sort -u
  )
done
[[ "$status" -eq 0 ]] || exit 1
printf 'citation-lint: pass (%d document(s))\n' "$#"
