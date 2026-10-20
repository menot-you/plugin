#!/usr/bin/env -S bash -p
# red-first — the law's "reproduce the intended failure on the affected path
# before the implementation" gets a mechanical moment: in a project with a test
# suite, a product edit is DENIED until the session has a RED, at most three times.
# A test recorded before that edit means no deny at all. A project with no test
# suite is never denied.
#
# Measured 2026-09-14 in `claude plugin eval` (p7-red-before-edit, 5/5 runs, with
# and without the plugin): the model edits the product file first, then the
# test, then runs the test once. The first cut of this hook was ADVISORY
# (additionalContext, exit 0) and measured ZERO effect in 2/2 runs: a PreToolUse
# additionalContext lands in the tool RESULT, so the model reads "before this
# edit" after the edit has already executed. Only a deny precedes the edit.
#
# UNTIL THERE IS A RED, not once. Measured 2026-09-14/15: the one-shot deny moved
# p7 from 0,12 to 0,25 and no further — the model took the deny, edited the test
# file, and went straight back to the product without running anything. So the
# gate now opens on either of the two acts the law actually asks for:
#   * a test command ran (`tested`, recorded from Bash), or
#   * a TEST FILE was written or edited in this session (`tested`, recorded from
#     the edit itself) — writing the failing check is the first half of RED.
# Docs, changelog, config files and anything under /etc/ always pass (the pass list
# below). In a project with a test suite, a product file needs a RED first wherever it
# lives, even outside the cwd.
# The deny names the way out with a concrete path, because a block without an
# exit is the owner's original complaint. It cannot loop: every deny is followed
# by an act that opens the gate, and `advised` still caps it at three per
# session so a stuck model is never held hostage.
# Fail-OPEN: bad JSON, no session_id, unwritable state -> exit 0 silent.
#
# THREE BINDINGS, one script, branch on hook_event_name:
#   PostToolUse / PostToolUseFailure on Bash -> record `tested` when the command
#     is a test runner. Both events: a RED run exits non-zero and the client
#     routes that call to PostToolUseFailure — the very run the law wants.
#   PreToolUse on Edit|Write|MultiEdit -> decide. Product file, no `tested`, fewer
#     than three `advised`, a test suite found -> count `advised`, deny.
# State: ${XDG_STATE_HOME:-$HOME/.local/state}/nott/red-first/<session_id>/{tested,advised}
#
# Two channels, as in pynott-branch-lock.sh: exit 2 + stderr is the block the
# client honours everywhere; the JSON permissionDecision is the courtesy.
set -uo pipefail

payload=$(cat)
printf '%s' "$payload" | jq -e . >/dev/null 2>&1 || exit 0
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""')
tool=$(printf '%s' "$payload" | jq -r '.tool_name // ""')
sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' | tr -cd 'a-zA-Z0-9-')
[ -n "$sid" ] || exit 0
state="${XDG_STATE_HOME:-$HOME/.local/state}/nott/red-first/$sid"

case "$event" in
  PostToolUse|PostToolUseFailure)
    [ "$tool" = Bash ] || exit 0
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
    # ponytail: bare `pytest` also matches `cat pytest.ini`; advisory, so a false `tested` only costs the nag.
    # ponytail: Gradle/SwiftPM by verb within one `|;&` segment — `gradlew lintTest`/`checkstyle` count too; same ceiling.
    # xcodebuild by its ACTION token, quoted strings removed first (review 2026-10-01):
    # `-derivedDataPath "build test"`, `-testPlan X build`, `build-for-testing` are not tests.
    bare=$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$cmd")
    grep -qE '(pytest|python3? [^[:space:]]*test_[^[:space:]]+\.py|bash [^[:space:]]*(-contract|-test)\.sh|npm test|cargo test|go test)' <<<"$cmd" \
      || grep -qE '(gradlew? [^|;&]*([tT]est|check)|swift test)' <<<"$cmd" \
      || grep -qE '(^|[|;&])[[:space:]]*(cd [^|;&]*&&[[:space:]]*)?(make (test|check)|(yarn|npm run|pnpm run) test|npx (jest|vitest run)|node --test|python3? -m unittest|tox|ctest|mvn test|bats test/|\./test\.sh|rspec)([[:space:]|;&]|$)' <<<"$bare" \
      || grep -qE 'xcodebuild([^|;&]*[[:space:]])?(test|test-without-building)([[:space:]|;&]|$)|xcodebuild[^|;&]*-only-testing' <<<"$bare" || exit 0
    mkdir -p "$state" 2>/dev/null && : > "$state/tested" 2>/dev/null
    exit 0 ;;
  PreToolUse) ;;
  *) exit 0 ;;
esac

case "$tool" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
[ -e "$state/tested" ] && exit 0

path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""')
[ -n "$path" ] || exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')
# EVERY RULE READS THE PATH LEXICALLY NORMALIZED (review 2026-10-01):
# `src/test/../main/x.kt` is product and `docs/../core.py` is not a doc. `.`/`..`
# resolve without the filesystem: GNU `realpath -m` is not on the Macs, and bash
# 3.2 (macOS /bin/bash) has no negative array index.
norm() {
  local IFS=/ seg parts out=()
  read -ra parts <<<"$1"
  for seg in ${parts[@]+"${parts[@]}"}; do
    case $seg in
      ''|.) ;;
      ..) if [ ${#out[@]} -gt 0 ] && [ "${out[${#out[@]}-1]}" != .. ]; then unset "out[${#out[@]}-1]"
          elif [ "${1:0:1}" != / ]; then out+=(..); fi ;;
      *) out+=("$seg") ;;
    esac
  done
  case $1 in /*) printf '/%s' "${out[*]-}" ;; *) printf '%s' "${out[*]-}" ;; esac
}
# The cwd too: `/w/`, `//w` and `/w/.` are `/w`. ponytail: lexical only — a symlinked
# cwd against a physical path is outside, so denied (a nag, never a pass); resolving
# needs the filesystem and has no portable spelling on the Macs.
[ -n "$cwd" ] && cwd=$(norm "$cwd")
case $path in /*) ;; *) [ -n "$cwd" ] && path=$cwd/$path ;; esac
path=$(norm "$path")
base=${path##*/}
# DOCS AND DATA FIRST, and they only PASS — they never open the gate. Reviewed
# 2026-09-15: with the test branch first, `docs/tests/notes.md` and
# `plugin/tests/README.md` counted as a RED, because they sit under a directory
# called tests. A markdown file is not a failing check.
grep -qE '\.(md|txt|json|yaml|yml|toml|conf|cfg|ini|env|service|timer|socket|properties)$|^(Dockerfile|Containerfile)$' <<<"$base" && exit 0
grep -qE '/(docs|changelog\.d)/' <<<"/$path" && exit 0
# Anything under /etc/ is system config, not a product file (absolute paths only; norm ran above).
grep -qE '^/etc/' <<<"$path" && exit 0
# A TEST FILE EDIT OPENS THE GATE and is itself the RED half: record it and pass.
# The NAME must look like a test (a directory called `test/` inside a product tree is
# not enough: `apps/x/nott_x/test/engine.py` was opening it), or the path must be a
# real test root at the top of a member.
# A TEST ROOT, judged against the session's own cwd: `tests/` at the top of the repo
# or at the top of a member. A directory called `test/` buried inside a package
# (`apps/x/nott_x/test/engine.py`) is product, and used to open the gate.
# JVM and Apple trees (2026-10-01), relative to the cwd too: a Gradle source set
# `src/test*/` or `src/<x>Test*/` (test, testDebug, testFixtures, androidTest,
# androidTestDebug, commonTest — never `testing`/`contest`), an Xcode/SwiftPM target
# `*Tests/` (case-sensitive: lowercase `tests/` keeps the rules above), and the
# CamelCase name `*Test.kt|java|swift`, `*Tests.*` — never under `src/main/` or
# `Sources/`, where a product class may be called `SpeedTest`.
# CONTAINED IN THE CWD before any directory rule: outside it (or climbing out of a
# relative path with no cwd) `rel` keeps a leading `/`, which no directory rule matches.
rel=$path
case $cwd in ?*) rel=${path#"${cwd%/}"/} ;; esac
case $rel in ..|../*) rel=/$rel ;; esac
if grep -qE '^(test_|.*_test\.|.*\.test\.|conftest\.py$|.*-contract.*\.sh$|.*-self-test\.sh$)' <<<"$base" \
   || grep -qE '^(tests?|__tests__)/' <<<"$rel" \
   || grep -qE '^(apps|libs|mcps|plugin|src)/[^/]+/(tests?|__tests__)/' <<<"$rel" \
   || grep -qE '^src/__tests__/' <<<"$rel" \
   || grep -qE '^(apps|libs)/[^/]+/[^/]+/(tests|__tests__)/' <<<"$rel" \
   || grep -qE '^([^/]+/)*src/(test|[a-z][A-Za-z0-9]*Test)([A-Z][A-Za-z0-9]*)?/' <<<"$rel" \
   || grep -qE '^([^/]+/)*[A-Za-z0-9_]*Tests/' <<<"$rel" \
   || { grep -qE '^[A-Za-z0-9_]*Tests?\.(kt|java|swift)$' <<<"$base" && ! grep -qE '/(src/main|Sources)/' <<<"/$rel"; }; then
  mkdir -p "$state" 2>/dev/null && : > "$state/tested" 2>/dev/null
  exit 0
fi

# Three denies per session is the hostage cap: past it the hook goes quiet and the
# law carries the rest. It is read before the suite search, so a capped session never walks the tree.
tries=$(cat "$state/advised" 2>/dev/null || echo 0)
case $tries in ''|*[!0-9]*) tries=0 ;; esac
[ "$tries" -ge 3 ] && exit 0

# NO TEST SUITE, NO REFUSAL (owner order, 2026-10-20): a project with no tests
# does not get tests written for it. The project is the git root of the session's cwd
# (else the cwd, else this process's directory). Its suite is a test runner config at that
# root, or a test file or test directory at most five levels down; vendored and build
# trees do not count. No suite found -> pass, and no refusal is spent. has_suite prints
# the path that proves the suite, and the refusal names it.
# Only entries BELOW the root are judged (-mindepth 1): the root's own name is neither a
# test directory nor a pruned build tree (reviews 9998d119, 88077ff4). "$r/" follows a
# symlinked root.
has_suite() {
  local r=${1%/}/ f
  [ -d "$r" ] || return 1
  f=$(find "$r" -mindepth 1 -maxdepth 1 \( -name pytest.ini -o -name tox.ini -o -name conftest.py -o -name 'jest.config.*' \
      -o -name 'vitest.config.*' -o -name 'karma.conf.*' -o -name 'phpunit.xml*' -o -name .rspec \) -print -quit 2>/dev/null)
  [ -n "$f" ] && { printf '%s' "$f"; return 0; }
  grep -qs '^\[tool\.pytest' "${r}pyproject.toml" && { printf '%s' "${r}pyproject.toml"; return 0; }
  grep -qsE '^test:' "${r}Makefile" && { printf '%s' "${r}Makefile"; return 0; }
  jq -e '(.scripts.test // "") | length > 0 and (test("no test specified") | not)' "${r}package.json" >/dev/null 2>&1 \
    && { printf '%s' "${r}package.json"; return 0; }
  f=$(find "$r" -mindepth 1 -maxdepth 5 \( -name .git -o -name node_modules -o -name .venv -o -name venv -o -name vendor \
      -o -name target -o -name build -o -name dist -o -name .tox \) -prune \
      -o -type d \( -name tests -o -name test -o -name __tests__ -o -name spec -o -name '*Tests' -o -name androidTest \) -print -quit \
      -o -type f \( -name 'test_*.py' -o -name '*_test.*' -o -name '*.test.*' -o -name '*.spec.*' -o -name '*Test.kt' \
      -o -name '*Test.java' -o -name '*Tests.swift' \) -print -quit 2>/dev/null)
  [ -n "$f" ] && printf '%s' "$f"
}
project=${cwd:-$PWD}
project=$(git -C "$project" rev-parse --show-toplevel 2>/dev/null) || project=${cwd:-$PWD}
proof=$(has_suite "$project") || exit 0

mkdir -p "$state" 2>/dev/null && printf '%s' "$((tries + 1))" > "$state/advised" 2>/dev/null || exit 0
# The way out, named: the test path this product file would have.
case $path in
  */apps/*|*/libs/*|*/mcps/*) suggest=$(printf '%s' "$path" | sed -E 's#(/(apps|libs|mcps)/[^/]+)/.*#\1/tests/test_<what_fails>.py#') ;;
  *plugin/hooks/*|*plugin/scripts/*) suggest="plugin/tests/<name>-contract.sh" ;;
  *) suggest="the nearest test for this file" ;;
esac
# THE EMERGENCY EXIT IS NAMED, as the one-shot version named it: a tree with no test
# to run must not be a wall (review, 2026-09-15). The third refusal is the last one.
reason="red-first: this project has tests (${proof}), no RED yet in this session, and this is a product file. Write the failing check first (${suggest}) or run the test that already covers this, then edit — editing a test file or running a test runner opens this gate, and docs, config and changelog never trip it. If this tree genuinely has no test to run, retry: this refusal is $((tries + 1)) of 3, and after the third the hook goes quiet."
printf '%s\n' "$reason" >&2
jq -cn --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 2
