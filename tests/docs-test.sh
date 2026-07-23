#!/usr/bin/env bash
set -euo pipefail

die() { printf 'docs-test: %s\n' "$*" >&2; exit 1; }
root=${1:-$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd -P)}
for command_name in grep jq; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done
for file in README.md RUNBOOK.md SECURITY.md PRIVACY.md CONTRIBUTING.md CHANGELOG.md RELEASE-CHECKLIST.md LICENSE NOTICE; do
  [[ -s "$root/$file" ]] || die "missing public document: $file"
done
[[ -s "$root/assets/nsoul-mark.svg" ]] || die 'missing public brand asset: assets/nsoul-mark.svg'

require_text() {
  local file=$1 text=$2
  grep -qF -- "$text" "$root/$file" || die "$file does not declare: $text"
}
reject_text() {
  local file=$1 text=$2
  if grep -qF -- "$text" "$root/$file"; then
    die "$file repeats a fact owned by another authority: $text"
  fi
}

license=$(jq -er '.distribution.license' "$root/release/public-contract.json") || die 'release contract has no license'

require_text README.md 'nSOUL is the public distribution of NOTT'
require_text README.md "installed plugin id is **\`nott\`**"
require_text README.md '11 engineering skills'
require_text README.md '6 bounded agents'
require_text README.md '4 registered Claude Code hooks'
require_text README.md 'not bundled'
require_text README.md 'NOTT_NMEMORY_BIN'
require_text README.md 'NOTT_NBROWSER_BIN'
require_text README.md 'at most 200 local records'
require_text README.md 'does not claim either one happened'
require_text PRD.md 'one proof-bound deliverable'
require_text NOTT.md 'one proof-bound deliverable'
require_text README.md 'claude plugin install nott@nsoul'
require_text README.md 'codex plugin add nott@nsoul'
require_text RUNBOOK.md 'Linux and macOS'
require_text RUNBOOK.md 'claude plugin uninstall'
require_text RUNBOOK.md 'codex plugin remove'
require_text RUNBOOK.md 'claude plugin marketplace remove nsoul --scope user'
require_text RUNBOOK.md 'Restoring that checkout alone does not roll back a client installation'
require_text RUNBOOK.md 'first-release removal path above is the currently observed'
require_text SECURITY.md 'private vulnerability reporting'
require_text SECURITY.md 'request for a private contact channel'
require_text SECURITY.md 'controlled local fixtures'
require_text PRIVACY.md 'has no telemetry'
require_text PRIVACY.md 'Prompt text, assistant text, transcript paths, and session identifiers are not'
require_text README.md "Licensed under $license"
require_text CONTRIBUTING.md "licensed under $license"
require_text RELEASE-CHECKLIST.md 'Publication authority'
require_text RELEASE-CHECKLIST.md 'controlled fixtures'
require_text RELEASE-CHECKLIST.md 'Private reporting'
require_text SPEC.md 'controlled local executables'
require_text SPEC.md 'None of these checks attests to an external MCP'
require_text SPEC.md 'a checksum-valid'
require_text SPEC.md 'forged-graph control must still expose its hidden parent'
require_text SPEC.md 'direct-versus-symbolic ref'
require_text SPEC.md 'pinned current-directory root'
require_text skills/ratify/SKILL.md "Apply the closed \`witness\` and \`evidence\` meanings in \`decisions.md\`"
require_text decisions.md "\`decisions.md\` wins, followed by \`PRD.md\`, \`SPEC.md\`, and \`NOTT.md\`"
require_text PRD.md "\`decisions.md\` wins over this product law"
require_text NOTT.md "\`decisions.md\` wins, followed by \`PRD.md\`, \`SPEC.md\`, and \`NOTT.md\`"
require_text PRD.md 'registered Claude root-session and subagent hooks'
require_text NOTT.md 'required client-loaded instruction; the keyword alone does not claim machine enforcement'
require_text wiki.md 'closed names whose definitions are not projected here'
require_text decisions.md 'd26-declared-runtime-dependencies'
require_text SPEC.md 'does not inspect or prohibit implementation languages'
require_text CONTRIBUTING.md 'No implementation language is prohibited.'
require_text RELEASE-CHECKLIST.md 'Runtime dependencies'
require_text SPEC.md 'raw-byte-counted bounded input'

reject_text SPEC.md 'Model output is a proposal, NEVER authority.'
reject_text NOTT.md 'An executor MUST NOT certify its own success'
reject_text NOTT.md 'the executor NEVER witnesses itself'
reject_text skills/ratify/SKILL.md 'Define the witness that can prove the result'
reject_text NOTT.md 'n=1 override MUST'
reject_text NOTT.md 'n=1 preference MUST NOT become a standing rule'
reject_text decisions.md 'NEVER a reason to fabricate success'
reject_text NOTT.md 'each has one mechanical enforcer and one red-test'
reject_text NOTT.md 'derived docs are regenerate-and-diff linted'
reject_text wiki.md 'each with a mechanical enforcer'
reject_text NOTT.md 'client-loaded advisory guidance'
reject_text wiki.md 'Pre-kernel, everything NOTT reports lives here'
reject_text wiki.md 'outcome = kernel-derived terminal state'
reject_text wiki.md 'when observed response contradicts a default, the override wins'
reject_text PRD.md 'one witnessed deliverable'
reject_text NOTT.md 'one witnessed deliverable'
reject_text wiki.md 'the *witnessed deliverable* of the promise'
reject_text wiki.md 'Source: NOTT.md'
reject_text wiki.md 'Source: PRD '
reject_text wiki.md 'Source: decisions.md'

printf 'docs-test: pass\n'
