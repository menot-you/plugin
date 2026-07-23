#!/bin/sh
# nSOUL installer.
#
# What it does, in order:
#   1. Confirm that this host is in the release verification matrix.
#   2. Try the latest platform-neutral plugin release and verify its checksum.
#   3. Deny a 404 unless an immutable source fallback was explicitly granted.
#   4. Hand the selected source tree to the gated Claude plugin install step.
#
# The transport path is implemented. Host installation stays disabled until
# the public payload, external integrations, readback, and rollback are proven.
set -eu

REPO="${NSOUL_REPO:-}"
ALLOW_SOURCE_FALLBACK="${NSOUL_ALLOW_SOURCE_FALLBACK:-0}"
SOURCE_COMMIT="${NSOUL_SOURCE_COMMIT:-}"
ASSET="nsoul-plugin.tar.gz"

say() { printf '%s\n' "$*" >&2; }
die() { say "nsoul install: $*"; exit 1; }

[ -n "$REPO" ] || die "NSOUL_REPO is required until the public repository slug is ratified"

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"
command -v awk >/dev/null 2>&1 || die "awk is required"

OS=$(uname -s) ARCH=$(uname -m)
case "$OS:$ARCH" in
  Linux:x86_64|Linux:aarch64|Darwin:arm64) ;;
  *) die "host is outside the verification matrix: $OS $ARCH (accepted tuples: Linux x86_64, Linux aarch64, macOS arm64)" ;;
esac

TMP=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf "$TMP"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

BASE_URL="https://github.com/$REPO/releases/latest/download"

checksum() {
  file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    die "sha256sum or shasum is required to verify the release"
  fi
}

verify_release() {
  expected=$(awk -v asset="$ASSET" '$2 == asset { print $1 }' "$TMP/SHA256SUMS")
  [ -n "$expected" ] || die "SHA256SUMS has no exact entry for $ASSET"
  actual=$(checksum "$TMP/$ASSET")
  [ "$actual" = "$expected" ] || die "checksum mismatch for $ASSET"
}

install_plugin() {
  source_dir=$1
  [ -d "$source_dir" ] || die "selected source directory is missing"
  [ ! -d "$source_dir/lab" ] && [ ! -d "$source_dir/plugin/lab" ] \
    || die "selected source contains private lab content"

  # Definitive installation contract — implementation intentionally absent:
  # - choose a host-supported install surface only after its scope, update,
  #   cache, and rollback behavior has been observed;
  # - preflight plugin-local MCP launchers and their external executables;
  # - observe installed inventory and MCP startup against the exact candidate;
  # - prove update, interruption, rollback, and external-state ownership.
  die "public install gates are not green; Claude plugin installation is disabled"
}

say "nsoul install: trying release asset ($ASSET)..."
HTTP_STATUS=$(curl -sS -L -o "$TMP/$ASSET" -w '%{http_code}' \
  "$BASE_URL/$ASSET") || die "release asset lookup failed; refusing a source fallback"

case "$HTTP_STATUS" in
  200)
    curl -fsSL -o "$TMP/SHA256SUMS" "$BASE_URL/SHA256SUMS" \
      || die "release asset downloaded but SHA256SUMS is unavailable"
    verify_release
    mkdir "$TMP/release"
    tar -xzf "$TMP/$ASSET" -C "$TMP/release" \
      || die "verified release asset could not be unpacked"
    [ -d "$TMP/release/nsoul" ] \
      || die "release asset does not contain the nsoul/ directory"
    install_plugin "$TMP/release/nsoul"
    ;;
  404)
    [ "$ALLOW_SOURCE_FALLBACK" = 1 ] \
      || die "release asset absent (HTTP 404); source fallback is disabled"
    [ "${#SOURCE_COMMIT}" -eq 40 ] \
      || die "NSOUL_SOURCE_COMMIT must be a full 40-character commit id"
    case "$SOURCE_COMMIT" in
      *[!0-9a-f]*) die "NSOUL_SOURCE_COMMIT must contain lowercase hexadecimal only" ;;
    esac
    say "release asset absent (HTTP 404); explicitly fetching source commit: $SOURCE_COMMIT"
    say "the source fallback is not equivalent to released bytes."
    command -v git >/dev/null 2>&1 \
      || die "git is required for the source fallback"
    mkdir "$TMP/source"
    git -C "$TMP/source" init -q \
      || die "source checkout initialization failed"
    git -C "$TMP/source" remote add origin "https://github.com/$REPO" \
      || die "source remote setup failed"
    git -C "$TMP/source" fetch --depth 1 origin "$SOURCE_COMMIT" \
      || die "source commit fetch failed"
    git -C "$TMP/source" checkout -q --detach FETCH_HEAD \
      || die "source commit checkout failed"
    [ "$(git -C "$TMP/source" rev-parse HEAD)" = "$SOURCE_COMMIT" ] \
      || die "source checkout did not resolve to NSOUL_SOURCE_COMMIT"
    install_plugin "$TMP/source"
    ;;
  *)
    die "release asset lookup returned HTTP $HTTP_STATUS; refusing a source fallback"
    ;;
esac
