#!/usr/bin/env bash
set -euo pipefail

die() { printf 'doc-lint: %s\n' "$*" >&2; exit 1; }
for command_name in awk basename grep; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done
[[ "$#" -gt 0 ]] || die "usage: doc-lint.sh DOCUMENT..."

status=0
for document in "$@"; do
  [[ -f "$document" ]] || die "document does not exist: $document"
  base=$(basename -- "$document")
  if awk '
    /^```/ { in_fence=!in_fence; next }
    !in_fence && $0 ~ /(^|[^[:alnum:]_])(MUST|NEVER)([^[:alnum:]_]|$)/ { found=1 }
    END { exit !found }
  ' "$document"; then
    if ! grep -qE '^\*\*Normative scope\.\*\*' "$document"; then
      printf 'doc-lint: normative scope is undeclared: %s\n' "$document" >&2
      status=1
    fi
  fi
  if [[ "$base" == decisions.md ]]; then
    if grep -inE '\b(should|could|might|maybe|ideally|possibly)\b' "$document" >/dev/null; then
      printf 'doc-lint: hedge in decisions normative scope: %s\n' "$document" >&2
      status=1
    fi
    continue
  fi
  if ! awk '
    function inspect(text, lowered) {
      if (text == "") return
      lowered = tolower(text)
      if (text ~ /(MUST|NEVER)/ && lowered ~ /(^|[^[:alnum:]_])(should|could|might|maybe|ideally|possibly)([^[:alnum:]_]|$)/) {
        print FILENAME ":" paragraph_start ": hedge in normative paragraph" > "/dev/stderr"
        failed = 1
      }
    }
    /^```/ { inspect(paragraph); paragraph=""; in_fence=!in_fence; next }
    in_fence { next }
    /^[[:space:]]*$/ { inspect(paragraph); paragraph=""; next }
    { if (paragraph == "") paragraph_start=FNR; paragraph=paragraph " " $0 }
    END { inspect(paragraph); exit failed }
  ' "$document"; then
    status=1
  fi
done
[[ "$status" -eq 0 ]] || exit "$status"
printf 'doc-lint: pass (%s document(s))\n' "$#"
