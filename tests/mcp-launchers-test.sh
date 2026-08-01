#!/usr/bin/env bash
set -euo pipefail

die() { printf 'mcp-launchers-test: %s\n' "$*" >&2; exit 1; }
root=${1:-$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd -P)}
nmemory=$root/bin/nmemory-mcp
[[ -x "$nmemory" ]] || die 'launchers are not executable'
# Withdrawn in 0.3.0 by owner curation, declared in
# tools/mirror-strip.d/n-soul.list. Asserted absent so the adapter cannot
# return without a decision.
[[ ! -e "$root/bin/nbrowser-mcp" ]] || die 'withdrawn nBrowser launcher is back in the candidate'

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    die 'missing SHA-256 utility'
  fi
}
expected_nmemory_sha256=9e069e3c810b675dfa033fc9fc7d6434e5dfeaa093b0c133c110c277e03e14a4
[[ $(hash_file "$nmemory") == "$expected_nmemory_sha256" ]] || die 'nmemory launcher bytes differ from the reviewed offline candidate'

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM
mkdir -p "$scratch/path" "$scratch/empty"

cat >"$scratch/path/nmemory" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$CAPTURE"
[ "${TOUCH_MARKER:-0}" = 0 ] || : >"$TOUCH_MARKER"
exit "${FAKE_EXIT:-0}"
SH
chmod 0755 "$scratch/path/nmemory"

printf '%s\n' 'alpha beta' '--literal=*' >"$scratch/expected"
CAPTURE="$scratch/nmemory.args" PATH="$scratch/path" "$nmemory" 'alpha beta' '--literal=*'
cmp -s "$scratch/expected" "$scratch/nmemory.args" || die 'nmemory PATH fallback changed argv'

CAPTURE="$scratch/override.args" PATH="$scratch/empty" NOTT_NMEMORY_BIN="$scratch/path/nmemory" "$nmemory" 'alpha beta' '--literal=*'
cmp -s "$scratch/expected" "$scratch/override.args" || die 'nmemory override changed argv'

set +e
CAPTURE="$scratch/invalid.args" PATH="$scratch/path" NOTT_NMEMORY_BIN="$scratch/missing" "$nmemory" >"$scratch/invalid.out" 2>"$scratch/invalid.err"
status=$?
set -e
[[ "$status" -eq 126 && ! -e "$scratch/invalid.args" && ! -s "$scratch/invalid.out" ]] || die 'invalid override did not fail closed before PATH fallback'
[[ $(wc -l <"$scratch/invalid.err") -eq 1 ]] || die 'invalid override diagnostic is not one line'

set +e
PATH="$scratch/empty" "$nmemory" >"$scratch/missing.out" 2>"$scratch/missing.err"
status=$?
set -e
[[ "$status" -eq 127 && ! -s "$scratch/missing.out" ]] || die 'missing nmemory did not exit 127 with empty stdout'
[[ $(wc -l <"$scratch/missing.err") -eq 1 ]] || die 'missing nmemory diagnostic is not one line'

# The PATH self-resolution case retired with nBrowser and has no nmemory twin
# by construction: nBrowser's launcher basename equalled its resolved
# executable (`nbrowser-mcp`), so a PATH containing the plugin's own bin/ let
# it find itself. `nmemory-mcp` resolves `nmemory`, a different basename, so
# the launcher cannot resolve to itself through PATH at all — that path is
# covered by the missing-dependency case above, which exits 127.

for launcher_name in nmemory; do
  launcher=$nmemory
  override_name=NOTT_NMEMORY_BIN
  set +e
  (
    export "$override_name=$launcher"
    "$launcher" --probe
  ) >"$scratch/$launcher_name-self.out" 2>"$scratch/$launcher_name-self.err"
  status=$?
  set -e
  [[ "$status" -eq 126 && ! -s "$scratch/$launcher_name-self.out" ]] || die "$launcher_name accepted a direct self override"

  ln -s "$launcher" "$scratch/$launcher_name-alias"
  set +e
  (
    export "$override_name=$scratch/$launcher_name-alias"
    "$launcher" --probe
  ) >"$scratch/$launcher_name-alias.out" 2>"$scratch/$launcher_name-alias.err"
  status=$?
  set -e
  [[ "$status" -eq 126 && ! -s "$scratch/$launcher_name-alias.out" ]] || die "$launcher_name accepted an alias self override"

  mkdir -p "$scratch/$launcher_name-cwd" "$scratch/$launcher_name-other"
  cat >"$scratch/$launcher_name-cwd/child" <<'SH'
#!/bin/sh
printf 'cwd-target\n' >"$RELATIVE_CAPTURE"
SH
  cat >"$scratch/$launcher_name-other/child" <<'SH'
#!/bin/sh
printf 'path-target\n' >"$RELATIVE_CAPTURE"
SH
  chmod 0755 "$scratch/$launcher_name-cwd/child" "$scratch/$launcher_name-other/child"
  cwd_launcher=$scratch/$launcher_name-cwd-launcher
  cp "$launcher" "$cwd_launcher"
  chmod 0755 "$cwd_launcher"
  (
    cd "$scratch/$launcher_name-cwd"
    RELATIVE_CAPTURE="$scratch/$launcher_name-relative.result" PATH="$scratch/$launcher_name-other" NOTT_NMEMORY_BIN=child "$cwd_launcher"
  )
  [[ $(cat "$scratch/$launcher_name-relative.result") == cwd-target ]] || die "$launcher_name executed a PATH target after validating a relative override"
done

marker=$scratch/probe-ran
CAPTURE="$scratch/probe.args" TOUCH_MARKER="$marker" NOTT_NMEMORY_BIN="$scratch/path/nmemory" "$nmemory" --probe
[[ ! -e "$marker" && ! -e "$scratch/probe.args" ]] || die '--probe executed the resolved dependency'

# Injection-shaped override. Retargeted from NOTT_NBROWSER_BIN to
# NOTT_NMEMORY_BIN when the adapter was withdrawn: the property belongs to the
# launcher contract, not to one adapter, so it survives the withdrawal.
injection="$scratch/missing;touch $scratch/injected"
set +e
PATH="$scratch/path" NOTT_NMEMORY_BIN="$injection" "$nmemory" >/dev/null 2>"$scratch/injection.err"
status=$?
set -e
[[ "$status" -eq 126 && ! -e "$scratch/injected" ]] || die 'injection-shaped override was evaluated'

for launcher_name in nmemory; do
  launcher=$nmemory
  override_name=NOTT_NMEMORY_BIN
  target=$scratch/path/nmemory
  set +e
  (
    export "$override_name=$target"
    CAPTURE="$scratch/$launcher_name-status.args" FAKE_EXIT=42 "$launcher" status-check
  ) >/dev/null 2>"$scratch/$launcher_name-status.err"
  status=$?
  set -e
  [[ "$status" -eq 42 ]] || die "$launcher_name child exit status was not propagated"
done

printf 'mcp-launchers-test: pass\n'
