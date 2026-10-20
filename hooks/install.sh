#!/usr/bin/env bash
# Retire NOTT's automatic Git hook in this worktree. Verification is explicit.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
current=$(git config --get core.hooksPath || true)
case "$current" in
  plugin/hooks|"$root/plugin/hooks")
    # The shared setting must remain intact for the owner's other worktrees.
    git config extensions.worktreeConfig true
    git config --worktree core.hooksPath /dev/null
    [ "$(git config --get core.hooksPath)" = /dev/null ] || exit 1
    printf 'NOTT automatic Git hooks retired in this worktree.\n'
    ;;
  *) printf 'No NOTT automatic Git hook to retire; existing configuration preserved.\n' ;;
esac
