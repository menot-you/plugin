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
# The nsoul-mark brand asset was retired in 0.3.0 by owner curation and is
# declared in tools/mirror-strip.d/n-soul.list. Asserted absent so it cannot
# return without a decision; the rest of the brand set is checked above.
[[ ! -e "$root/assets/nsoul-mark.svg" ]] || die 'retired brand mark is back in the candidate'

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
# The nBrowser override is gone with the adapter it configured. Asserted ABSENT from the
# published README rather than merely unrequired, so the withdrawn adapter cannot be
# documented back into existence without a decision.
reject_text README.md 'NOTT_NBROWSER_BIN'
require_text README.md 'at most 200 local records'
require_text README.md 'does not claim either one happened'
require_text NOTT.md 'one witnessed deliverable'
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
# Re-pointed 2026-08-01: this assertion required a sentence that was FALSE against the
# shipped hook, which records a session identifier and a 240-byte excerpt of assistant
# text. A gate that demands a false claim is the gate being wrong. It now requires the
# document to state what is actually recorded, and to keep the two denials that remain
# true — prompt text and the transcript path.
require_text PRIVACY.md 'Your prompt text is never recorded, the'
require_text PRIVACY.md 'transcript path is never recorded'
require_text PRIVACY.md 'at most the last 240 bytes of the closing paragraph'
require_text PRIVACY.md 'There is no opt-in variable and no way to turn'
require_text README.md "Licensed under $license"
require_text CONTRIBUTING.md "licensed under $license"
require_text RELEASE-CHECKLIST.md 'Publication authority'
require_text RELEASE-CHECKLIST.md 'controlled fixtures'
require_text RELEASE-CHECKLIST.md 'Private reporting'
require_text skills/ratify/SKILL.md 'the witness that can prove the result without trusting the implementation'
# PRD.md and SPEC.md are no longer published (tools/mirror-strip.d/n-soul.list):
# this repository's copies are owner-ratify stubs, and publishing a stub as
# product authority is worse than publishing nothing. Their assertions are gone
# rather than weakened, and the authority chain is now checked where it is
# actually stated.
require_text decisions.md 'On conflict, this authority and `NOTT.md` win'
require_text NOTT.md 'on conflict, that authority wins and the conflicting clause here is void'
# The epistemic guarantee that makes publishing the canon honest: it declares its
# own rung instead of borrowing a stronger one.
require_text NOTT.md 'NEVER claim a rung the mechanism cannot hold'
require_text NOTT.md 'kernel-enforced arrives only when the sovereign `trust_spine` exists'
require_text wiki.md 'Kernel-lane terms are defined only in the `decisions.md` closed glossary'
require_text decisions.md 'd27-declared-sync-verifier'
require_text CONTRIBUTING.md 'No implementation language is prohibited.'
require_text RELEASE-CHECKLIST.md 'Runtime dependencies'

# THE SCRUB HALF IS RETIRED, and the reason is a decision rather than a convenience.
#
# This block used to hold twenty-one rejections whose single purpose was to prove the
# published documents were NOT this repository's own — it rejected, in the shipped tree,
# the exact sentences of the internal canon. That premise ended when the owner ruled that
# the plugin IS the leg and the internal texts ARE the public ones: there is one source
# now, so there is no second edition for a gate to tell apart, and a rejection of the only
# text that exists can never pass.
#
# What survives is the half that was never about editions. Two of those rejections were
# honest-rung guards, and they caught a real overclaim: the seven-classes sentence asserted
# that each failure class HAS a mechanical enforcer, while the published artifact ships none
# of them — they live in this repository's tools/, which the release does not carry. The
# sentences are now SCOPED to the source monorepo, so each rejection below targets the
# UNQUALIFIED form specifically. A scoped claim passes; an unscoped one is refused.
reject_text NOTT.md 'classes; each has one mechanical enforcer'
reject_text wiki.md 'each with a mechanical enforcer.'
reject_text wiki.md 'Source: PRD '
reject_text wiki.md 'Source: decisions.md'

printf 'docs-test: pass\n'
