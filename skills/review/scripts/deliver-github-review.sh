#!/usr/bin/env bash
trap - DEBUG RETURN ERR
set +x
set -euo pipefail
set +a
unset BASH_ENV ENV
unset DEBUG GH_DEBUG
unset NOTT_REVIEW_GH_CHILD
unset ambient_github_token selected_token body_json payload_json gh_output posted_json readback_json
unset actor_json preflight_json final_state_json stdin_bytes captured_output body_capture_json captured_body_size
ambient_github_token=${GH_TOKEN:-${GITHUB_TOKEN:-}}
unset GH_TOKEN GITHUB_TOKEN GITHUB_ENTERPRISE_TOKEN GH_ENTERPRISE_TOKEN

# Every refusal ends in one of two phrases, and the difference is the whole
# point: `no write attempted` promises an untouched target, `do not retry`
# warns the write may already exist. The PHASE decides, never the call site —
# the refusals inside run_gh_capture and open_gh_output_pipe fire both before
# and during the POST, so no fixed literal there could be honest in both. Same
# dispatch github_timeout_gap already uses. A message that carries its own
# phrase is left exactly as written.
die() {
  local message=$*
  case "$message" in
    *'no write attempted' | *'do not retry') ;;
    *)
      if [[ "${delivery_phase:-pre_post}" == pre_post ]]; then
        message="$message; no write attempted"
      else
        message="$message; do not retry"
      fi
      ;;
  esac
  printf 'review-delivery: %s\n' "$message" >&2
  exit 1
}

[[ "$#" -eq 8 ]] || die 'usage: deliver-github-review.sh REPOSITORY PULL_NUMBER BASE_REF BASE_COMMIT HEAD_COMMIT EXPECTED_LOGIN BODY_SHA256 BODY_FILE'

readonly repository=$1
readonly pull_number=$2
readonly base_ref=$3
readonly base_commit=$4
readonly head_commit=$5
readonly expected_login=$6
readonly expected_body_sha256=$7
readonly body_file=$8

owner=${repository%%/*}
name=${repository#*/}
[[ -n "$owner" && -n "$name" && "$owner/$name" == "$repository" ]] ||
  die 'repository must be OWNER/NAME'
[[ "$owner$name" != *[!A-Za-z0-9_.-]* ]] || die 'repository contains unsupported characters'
[[ "$owner" != . && "$owner" != .. && "$name" != . && "$name" != .. ]] ||
  die 'repository contains an unsupported path component'
[[ "$pull_number" =~ ^[1-9][0-9]*$ ]] || die 'pull-request number must be a canonical positive integer'
for commit in "$base_commit" "$head_commit"; do
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] ||
    die 'base and head commits must be full lowercase SHA-1 identifiers'
done
[[ "$expected_login" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*(\[bot\])?$ ]] ||
  die 'expected reviewer login has unsupported characters'
[[ "$expected_body_sha256" =~ ^[0-9a-f]{64}$ ]] ||
  die 'review-body SHA-256 must be a full lowercase digest'

for command_name in find gh git head iconv id jq ls mkdir mkfifo mktemp shasum sleep stat wc; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done
git check-ref-format --branch "$base_ref" >/dev/null 2>&1 || die 'base ref is not a valid Git branch name'

unset CLICOLOR_FORCE GH_FORCE_TTY LESS LV MANPAGER
export NO_COLOR=1
export CLICOLOR=0
export GH_PAGER=
export PAGER=
readonly NO_COLOR CLICOLOR GH_PAGER PAGER
export GH_PROMPT_DISABLED=1
export GH_NO_EXTENSION_UPDATE_NOTIFIER=1
export GH_NO_UPDATE_NOTIFIER=1
export GH_TELEMETRY=0
readonly GH_TELEMETRY

access_metadata_is_plain() {
  local path=$1 listing permissions
  [[ "$path" == /* ]] || path=./$path
  listing=$(LC_ALL=C ls -ldn "$path" 2>/dev/null) || return 1
  listing=${listing%%$'\n'*}
  permissions=${listing%%[[:space:]]*}
  [[ "$permissions" =~ ^[-d][rwxstST-]{9}[.]?$ ]]
}

scratch=
early_cleanup() {
  [[ -z "$scratch" ]] || find "$scratch" -depth -delete 2>/dev/null || true
}

umask 077
scratch=$(mktemp -d "${TMPDIR:-/tmp}/nott-review-delivery.XXXXXX") ||
  die 'could not create private scratch directory'
trap early_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
[[ -d "$scratch" && ! -L "$scratch" ]] || die 'scratch path is not a private directory'
access_metadata_is_plain "$scratch" ||
  die 'scratch directory carries extended access metadata; no write attempted'
readonly scratch
readonly error_log=$scratch/error.log
delivery_phase=pre_post
review_id=
body_capture_pid=
body_watchdog_pid=
gh_process_pid=
gh_watchdog_pid=
gh_output=
cleanup() {
  trap '' HUP INT TERM
  stop_body_jobs
  stop_gh_jobs
  find "$scratch" -depth -delete 2>/dev/null || true
}
terminate_process_group() {
  local process_pid=$1
  if [[ "$process_pid" =~ ^[1-9][0-9]*$ ]]; then
    kill -TERM -- "-$process_pid" 2>/dev/null || true
    kill -KILL -- "-$process_pid" 2>/dev/null || true
    wait "$process_pid" 2>/dev/null || true
  fi
}
stop_body_jobs() {
  local capture_pid=$body_capture_pid watchdog_pid=$body_watchdog_pid
  body_capture_pid=
  body_watchdog_pid=
  terminate_process_group "$capture_pid"
  terminate_process_group "$watchdog_pid"
}
stop_gh_jobs() {
  local process_pid=$gh_process_pid watchdog_pid=$gh_watchdog_pid active=0
  local pid
  gh_process_pid=
  gh_watchdog_pid=
  for pid in "$process_pid" "$watchdog_pid"; do
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
      active=1
      kill -TERM -- "-$pid" 2>/dev/null || true
    fi
  done
  if [[ "$active" -eq 1 ]]; then sleep "$gh_term_grace_seconds"; fi
  for pid in "$process_pid" "$watchdog_pid"; do
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
      kill -KILL -- "-$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}
handle_signal() {
  local signal_name=$1 exit_status=$2
  trap '' HUP INT TERM
  stop_body_jobs
  stop_gh_jobs
  case "$delivery_phase" in
    pre_post)
      printf 'review-delivery: interrupted by %s before POST; no write attempted\n' "$signal_name" >&2
      ;;
    post_started)
      printf 'review-delivery: interrupted by %s after POST started; outcome is ambiguous; do not retry\n' "$signal_name" >&2
      ;;
    review_id_known)
      printf 'review-delivery: review %s was posted; interrupted by %s before exact completion; do not retry\n' "$review_id" "$signal_name" >&2
      ;;
    complete)
      printf 'review-delivery: review %s was posted and read back; interrupted by %s before the receipt; do not retry\n' "$review_id" "$signal_name" >&2
      ;;
  esac
  exit "$exit_status"
}
trap cleanup EXIT
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM
export NOTT_REVIEW_DELIVERY_PID=$$
readonly NOTT_REVIEW_DELIVERY_PID

file_identity() {
  stat -Lc '%d:%i' -- "$1" 2>/dev/null || stat -Lf '%d:%i' "$1" 2>/dev/null
}
file_size() {
  stat -Lc '%s' -- "$1" 2>/dev/null || stat -Lf '%z' "$1" 2>/dev/null
}
file_owner() {
  stat -Lc '%u' -- "$1" 2>/dev/null || stat -Lf '%u' "$1" 2>/dev/null
}
file_mode() {
  stat -Lc '%a' -- "$1" 2>/dev/null || stat -Lf '%Lp' "$1" 2>/dev/null
}
caller_uid=$(id -u) || die 'caller identity could not be read'
[[ "$caller_uid" =~ ^[0-9]+$ ]] || die 'caller identity is invalid'
readonly caller_uid
readonly max_body_bytes=65536
readonly body_open_timeout_seconds=5
if [[ ! -f "$body_file" || -L "$body_file" || ! -s "$body_file" ]]; then
  die 'review body must be one pinned, non-empty regular file'
fi
initial_size=$(file_size "$body_file") || die 'review body size could not be read'
if [[ ! "$initial_size" =~ ^[0-9]+$ ]] || (( initial_size < 1 || initial_size > max_body_bytes )); then
  die "review body must contain 1-$max_body_bytes bytes"
fi

# Opening an attacker-swapped FIFO can block before descriptor validation. Keep
# the open and bounded read in a killable child. Its compact JSON reaches the
# parent through a helper-owned FIFO that is validated and unlinked before use;
# no pathname-backed body copy or write authority on BODY_FILE exists.
body_timeout_marker=$scratch/body-open-timeout
body_pipe=$scratch/body-pipe
mkfifo -m 0600 "$body_pipe" || die 'could not allocate review body pipe'
body_pipe_identity=$(file_identity "$body_pipe") || die 'review body pipe identity could not be read'
exec 7<>"$body_pipe"
opened_pipe_identity=$(file_identity /dev/fd/7) || die 'opened review body pipe identity could not be read'
if [[ ! -p "$body_pipe" || ! -p /dev/fd/7 || -L "$body_pipe" ||
      "$body_pipe_identity" != "$opened_pipe_identity" ]]; then
  exec 7>&-
  die 'review body pipe was substituted'
fi
exec 8</dev/fd/7
exec 9>/dev/fd/7
read_pipe_identity=$(file_identity /dev/fd/8) || die 'review body read-pipe identity could not be read'
write_pipe_identity=$(file_identity /dev/fd/9) || die 'review body write-pipe identity could not be read'
if [[ ! -p /dev/fd/8 || ! -p /dev/fd/9 || "$read_pipe_identity" != "$body_pipe_identity" ||
      "$write_pipe_identity" != "$body_pipe_identity" ]]; then
  exec 9>&-
  exec 8<&-
  exec 7>&-
  die 'review body pipe descriptors were substituted'
fi
exec 7>&-
find "$body_pipe" -delete || die 'could not unlink review body pipe'
set -m
(
  exec 8<&-
  exec 2>>"$error_log"
  if ! exec 6<"$body_file"; then exit 40; fi
  path_identity=$(file_identity "$body_file") || exit 41
  opened_identity=$(file_identity /dev/fd/6) || exit 41
  opened_size=$(file_size /dev/fd/6) || exit 41
  opened_owner=$(file_owner /dev/fd/6) || exit 42
  opened_mode=$(file_mode /dev/fd/6) || exit 42
  if [[ ! -f "$body_file" || ! -f /dev/fd/6 || -L "$body_file" || ! -s "$body_file" ||
        "$path_identity" != "$opened_identity" || ! "$opened_size" =~ ^[0-9]+$ ]] ||
     (( opened_size < 1 || opened_size > max_body_bytes )); then
    exit 41
  fi
  if [[ "$opened_owner" != "$caller_uid" || ! "$opened_mode" =~ ^[0-7]+$ ||
        "${opened_mode: -2}" != 00 ]]; then
    exit 42
  fi
  access_metadata_is_plain "$body_file" || exit 43
  head -c "$((max_body_bytes + 1))" <&6 | iconv -f UTF-8 -t UTF-8 |
    jq -cRs --argjson opened_size "$opened_size" '{body: ., opened_size: $opened_size}' >&9
) &
body_capture_pid=$!
set +m
exec 9>&-
set -m
(
  sleep "$body_open_timeout_seconds"
  if kill -TERM -- "-$body_capture_pid" 2>/dev/null; then
    : >"$body_timeout_marker"
    sleep 1
    kill -KILL -- "-$body_capture_pid" 2>/dev/null || true
  fi
) &
body_watchdog_pid=$!
set +m
set +e
IFS= read -r -d '' body_capture_json <&8
wait "$body_capture_pid"
body_capture_status=$?
set -e
terminate_process_group "$body_watchdog_pid"
exec 8<&-
body_capture_pid=
body_watchdog_pid=
if [[ -e "$body_timeout_marker" ]]; then
  die 'review body capture timed out; no write attempted'
fi
if [[ "$body_capture_status" -ne 0 ]]; then
  if [[ "$body_capture_status" -eq 42 ]]; then
    die 'review body must be owned by the caller and deny group or other access'
  fi
  if [[ "$body_capture_status" -eq 43 ]]; then
    die 'review body carries extended access metadata; no write attempted'
  fi
  die 'review body could not be safely opened and decoded as UTF-8 text'
fi
body_capture_json=${body_capture_json%$'\n'}
if ! body_json=$(printf '%s' "$body_capture_json" | jq -ce \
  'if (.body | type) == "string" then .body else error("body capture is not a string") end'); then
  die 'review body could not be safely opened and decoded as UTF-8 text'
fi
if ! captured_body_size=$(printf '%s' "$body_capture_json" | jq -er \
  'if (.opened_size | type) == "number" and .opened_size >= 1 and .opened_size == (.opened_size | floor)
   then .opened_size | tostring else error("opened size is invalid") end'); then
  die 'review body could not be safely opened and decoded as UTF-8 text'
fi
unset body_capture_json
body_json=${body_json%$'\n'}
body_size=$(printf '%s' "$body_json" | jq -jr '.' | wc -c) ||
  die 'review body snapshot size could not be read'
body_size=${body_size//[[:space:]]/}
if [[ "$body_size" != "$captured_body_size" ]]; then
  die 'review body could not be safely opened and decoded as UTF-8 text'
fi
if [[ ! "$body_size" =~ ^[0-9]+$ ]] || (( body_size < 1 || body_size > max_body_bytes )); then
  die "review body must contain 1-$max_body_bytes bytes"
fi
snapshot_digest=$(printf '%s' "$body_json" | jq -jr '.' | shasum -a 256) ||
  die 'review body snapshot could not be hashed'
snapshot_digest=${snapshot_digest%% *}
[[ "$snapshot_digest" =~ ^[0-9a-f]{64}$ && "$snapshot_digest" == "$expected_body_sha256" ]] ||
  die 'review body changed after its digest was pinned; no write attempted'
readonly body_json snapshot_digest

readonly candidate_footer="Reviewed candidate: $repository#$pull_number; base $base_ref@$base_commit; head $head_commit; actor $expected_login"
readonly required_footer=$'\n\n---\n'"$candidate_footer"
if ! printf '%s' "$body_json" | jq -e --arg required_footer "$required_footer" \
  'endswith($required_footer)' >/dev/null; then
  die 'review body must end with the exact candidate footer; no write attempted'
fi
readonly expected_pull_url="https://api.github.com/repos/$repository/pulls/$pull_number"
readonly expected_review_url_prefix="https://github.com/$repository/pull/$pull_number#pullrequestreview-"
if ! payload_json=$(printf '%s' "$body_json" | jq -ce \
  --arg commit_id "$head_commit" \
  '. as $body | {commit_id: $commit_id, body: $body, event: "COMMENT"}'); then
  die 'review payload could not be encoded'
fi
expected_post_body_digest=$snapshot_digest
readonly expected_post_body_digest payload_json

readonly gh_timeout_seconds=30
readonly gh_term_grace_seconds=1
open_gh_output_pipe() {
  local gh_pipe=$scratch/gh-output-pipe
  local gh_pipe_identity opened_gh_pipe_identity read_gh_pipe_identity write_gh_pipe_identity
  mkfifo -m 0600 "$gh_pipe" || die 'could not allocate GitHub output pipe'
  gh_pipe_identity=$(file_identity "$gh_pipe") || die 'GitHub output pipe identity could not be read'
  exec 7<>"$gh_pipe"
  opened_gh_pipe_identity=$(file_identity /dev/fd/7) || die 'opened GitHub output pipe identity could not be read'
  if [[ ! -p "$gh_pipe" || ! -p /dev/fd/7 || -L "$gh_pipe" ||
        "$gh_pipe_identity" != "$opened_gh_pipe_identity" ]]; then
    exec 7>&-
    die 'GitHub output pipe was substituted'
  fi
  exec 8</dev/fd/7
  exec 9>/dev/fd/7
  read_gh_pipe_identity=$(file_identity /dev/fd/8) || die 'GitHub output read-pipe identity could not be read'
  write_gh_pipe_identity=$(file_identity /dev/fd/9) || die 'GitHub output write-pipe identity could not be read'
  if [[ ! -p /dev/fd/8 || ! -p /dev/fd/9 || "$read_gh_pipe_identity" != "$gh_pipe_identity" ||
        "$write_gh_pipe_identity" != "$gh_pipe_identity" ]]; then
    exec 9>&-
    exec 8<&-
    exec 7>&-
    die 'GitHub output pipe descriptors were substituted'
  fi
  exec 7>&-
  find "$gh_pipe" -delete || die 'could not unlink GitHub output pipe'
}
github_timeout_gap() {
  case "$delivery_phase" in
    pre_post) die 'GitHub command timed out before POST; no write attempted' ;;
    post_started) die 'GitHub POST timed out; outcome is ambiguous; do not retry' ;;
    review_id_known) die "review $review_id was posted; GitHub readback timed out; do not retry" ;;
    complete) die "review $review_id was posted and read back; final receipt timed out; do not retry" ;;
  esac
}
run_gh_capture() {
  local token_mode=$1 stdin_bytes=$2
  local captured_output='' process_status=125 read_status=0
  local timeout_marker=$scratch/gh-command-timeout status_file=$scratch/gh-command-status
  local hold_pipe=$scratch/gh-command-hold
  shift 2
  [[ "$token_mode" == with-token || "$token_mode" == without-token ]] ||
    die 'internal GitHub token mode is invalid'
  find "$timeout_marker" "$status_file" -delete 2>/dev/null || true
  gh_output=
  open_gh_output_pipe
  mkfifo -m 0600 "$hold_pipe" || die 'could not allocate GitHub process hold pipe'
  exec 7<>"$hold_pipe"
  exec 6<"$hold_pipe"
  exec 5>"$hold_pipe"
  find "$hold_pipe" -delete || die 'could not unlink GitHub process hold pipe'
  set -m
  (
    set +m
    trap - HUP INT TERM
    exec 5>&-
    exec 7>&-
    exec 8<&-
    exec 1>&9 9>&-
    exec 2>>"$error_log"
    set +e
    if [[ "$token_mode" == with-token ]]; then
      if [[ -n "$stdin_bytes" ]]; then
        printf '%s' "$stdin_bytes" | NOTT_REVIEW_GH_CHILD=1 GH_TOKEN=$selected_token gh "$@"
      else
        NOTT_REVIEW_GH_CHILD=1 GH_TOKEN=$selected_token gh "$@"
      fi
    elif [[ -n "$stdin_bytes" ]]; then
      printf '%s' "$stdin_bytes" | gh "$@"
    else
      gh "$@"
    fi
    command_status=$?
    set -e
    printf '%s\n' "$command_status" >"$status_file"
    exec 1>&-
    IFS= read -r _ <&6 || true
    exec 6<&-
    exit "$command_status"
  ) &
  gh_process_pid=$!
  set +m
  exec 6<&-
  exec 7>&-
  exec 9>&-
  set -m
  (
    set +m
    trap - HUP INT TERM
    exec 5>&-
    exec 8<&-
    sleep "$gh_timeout_seconds"
    if kill -TERM -- "-$gh_process_pid" 2>/dev/null; then
      : >"$timeout_marker"
      sleep "$gh_term_grace_seconds"
      kill -KILL -- "-$gh_process_pid" 2>/dev/null || true
    fi
  ) &
  gh_watchdog_pid=$!
  set +m
  set +e
  IFS= read -r -d '' captured_output <&8
  read_status=$?
  set -e
  if [[ -s "$status_file" ]]; then
    IFS= read -r process_status <"$status_file" || process_status=125
  fi
  [[ "$process_status" =~ ^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]] || process_status=125
  terminate_process_group "$gh_process_pid"
  exec 5>&-
  terminate_process_group "$gh_watchdog_pid"
  exec 8<&-
  gh_process_pid=
  gh_watchdog_pid=
  while [[ "$captured_output" == *$'\n' ]]; do
    captured_output=${captured_output%$'\n'}
  done
  if [[ -e "$timeout_marker" ]]; then
    find "$timeout_marker" -delete 2>/dev/null || true
    github_timeout_gap
  fi
  find "$status_file" -delete 2>/dev/null || true
  [[ "$read_status" -ne 0 ]] || return 1
  [[ "$process_status" -eq 0 ]] || return "$process_status"
  gh_output=$captured_output
}

if [[ -n "$ambient_github_token" ]]; then
  selected_token=$ambient_github_token
elif ! run_gh_capture without-token '' auth token --hostname github.com; then
  die 'GitHub authentication is unavailable; no write attempted'
else
  selected_token=$gh_output
fi
gh_output=
unset ambient_github_token
[[ -n "$selected_token" && "$selected_token" != *[[:space:]]* ]] ||
  die 'GitHub authentication returned an invalid token; no write attempted'
readonly selected_token
mkdir -m 0700 "$scratch/gh-config" || die 'could not isolate GitHub configuration'
export GH_CONFIG_DIR=$scratch/gh-config
readonly GH_CONFIG_DIR

if ! run_gh_capture with-token '' api --hostname github.com \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  --method GET user; then
  die 'GitHub actor preflight failed; no write attempted'
fi
actor_json=$gh_output
if ! printf '%s' "$actor_json" | jq -e --arg wanted_login "$expected_login" '.login == $wanted_login' >/dev/null; then
  die 'active GitHub actor differs from the pinned reviewer login; no write attempted'
fi
# GH_TOKEN has precedence over stored credentials. Keep the verified credential
# non-exported and scope it only to each GitHub CLI process.
unset GITHUB_ENTERPRISE_TOKEN GH_ENTERPRISE_TOKEN GITHUB_TOKEN GH_TOKEN

readonly api_path="repos/$repository/pulls/$pull_number"
if ! run_gh_capture with-token '' api --hostname github.com \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  --method GET "$api_path"; then
  die 'pull-request preflight failed; no write attempted'
fi
preflight_json=$gh_output
# The recorded base belongs to the review's provenance, not the live target
# identity. Publishing a comment does not certify merge readiness or validate
# changed dependencies; the reviewer owns that judgment before delivery.
if ! printf '%s' "$preflight_json" | jq -e \
  --arg repository "$repository" \
  --arg pull_number "$pull_number" \
  --arg base_ref "$base_ref" \
  --arg head_commit "$head_commit" \
  '.state == "open"
   and .number == ($pull_number | tonumber)
   and .base.repo.full_name == $repository
   and .base.ref == $base_ref
   and .head.sha == $head_commit' >/dev/null; then
  die 'pull-request identity, state, or candidate changed; no write attempted'
fi

# This is the sole explicit POST process invocation in one helper run. A non-zero exit is
# ambiguous because the remote may have accepted the review before the client
# lost the response; the helper never retries it.
delivery_phase=post_started
if ! run_gh_capture with-token "$payload_json" api --hostname github.com \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  --method POST "$api_path/reviews" --input -; then
  die 'POST outcome is ambiguous; do not retry'
fi
posted_json=$gh_output
if ! printf '%s' "$posted_json" | jq -e '(.id | type) == "number" and .id > 0 and .id == (.id | floor)' >/dev/null; then
  die 'POST returned no positive integer review identifier; do not retry'
fi
review_id=$(printf '%s' "$posted_json" | jq -er '.id | tostring') ||
  die 'POST returned no review identifier; do not retry'
readonly review_id
delivery_phase=review_id_known
readonly expected_review_url=$expected_review_url_prefix$review_id

if ! run_gh_capture with-token '' api --hostname github.com \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  --method GET "$api_path/reviews/$review_id"; then
  die "review $review_id was posted but exact readback failed; do not retry"
fi
readback_json=$gh_output
if ! readback_body_digest=$(printf '%s' "$readback_json" | jq -jer \
  'if (.body | type) == "string" then .body else error("review body is not a string") end' |
  shasum -a 256); then
  die "review $review_id was posted but its body could not be verified; do not retry"
fi
readback_body_digest=${readback_body_digest%% *}
if [[ "$readback_body_digest" != "$expected_post_body_digest" ]]; then
  die "review $review_id was posted but exact readback differed; do not retry"
fi
if ! printf '%s' "$readback_json" | jq -e \
  --arg review_id "$review_id" \
  --arg review_url "$expected_review_url" \
  --arg head_commit "$head_commit" \
  --arg expected_login "$expected_login" \
  --arg pull_url "$expected_pull_url" \
  '.id == ($review_id | tonumber)
   and .html_url == $review_url
   and .commit_id == $head_commit
   and .pull_request_url == $pull_url
   and .user.login == $expected_login
   and .state == "COMMENTED"' >/dev/null; then
  die "review $review_id was posted but exact readback differed; do not retry"
fi

if ! run_gh_capture with-token '' api --hostname github.com \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  --method GET "$api_path"; then
  die "review $review_id was posted but final candidate readback failed; do not retry"
fi
final_state_json=$gh_output
if ! printf '%s' "$final_state_json" | jq -e \
  --arg repository "$repository" \
  --arg pull_number "$pull_number" \
  --arg base_ref "$base_ref" \
  --arg head_commit "$head_commit" \
  '.state == "open"
   and .number == ($pull_number | tonumber)
   and .base.repo.full_name == $repository
   and .base.ref == $base_ref
   and .head.sha == $head_commit' >/dev/null; then
  die "review $review_id was posted but the target or candidate changed during delivery; do not retry"
fi

delivery_phase=complete
printf 'review-delivery: posted and read back %s\n' "$expected_review_url"
