#!/usr/bin/env bash
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1

die() { printf 'public-release-check: %s\n' "$*" >&2; exit 1; }
mode=${1:-full}
case "$mode" in ci|full|portable) ;; *) die 'usage: public-release-check.sh [ci|full|portable]' ;; esac
script_dir=${BASH_SOURCE[0]%/*}
[[ "$script_dir" != "${BASH_SOURCE[0]}" ]] || script_dir=.
candidate_path=$(unset CDPATH; cd -- "$script_dir/.." && pwd -P)
root=$candidate_path

command -v -- jq >/dev/null 2>&1 || die 'missing required command: jq'
contract=$root/release/public-contract.json
declared_dependencies=$(
  jq -er --arg mode "$mode" '
    .runtimeDependencies.release as $dependencies
    | ($dependencies.portable
       + (if $mode == "portable" then [] else $dependencies.ci end)
       + (if $mode == "full" then $dependencies.full else [] end)) as $required
    | if ($required | length) > 0
         and all($required[]; type == "string" and test("^[a-z0-9][a-z0-9._+-]*$"))
         and (($required | unique | length) == ($required | length))
      then $required[]
      else error("invalid runtime dependency contract")
      end
  ' "$contract"
) || die 'invalid runtime dependency contract'
required=()
while IFS= read -r command_name; do required+=("$command_name"); done <<<"$declared_dependencies"
for command_name in "${required[@]}"; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done
gitleaks_bin=$(type -P gitleaks) || die 'missing required command: gitleaks'
expected_gitleaks=$(jq -er '.toolchain.gitleaks.version' "$contract") || die 'invalid pinned Gitleaks version'
[[ $("$gitleaks_bin" version) == "$expected_gitleaks" ]] || die 'Gitleaks version differs from release contract'

file_identity() {
  stat -c '%d:%i' "$1" 2>/dev/null || stat -f '%d:%i' "$1"
}

cd -- "$candidate_path" || die "could not enter candidate root: $candidate_path"
root=.
candidate_root_identity=$(file_identity .) || die 'could not pin candidate root identity'
assert_candidate_root_bound() {
  local cwd_identity path_identity
  cwd_identity=$(file_identity .) || die 'could not re-read pinned candidate root'
  path_identity=$(file_identity "$candidate_path") || die 'candidate root path disappeared during release probes'
  [[ "$cwd_identity" == "$candidate_root_identity" ]] || die 'pinned candidate root identity changed during release probes'
  [[ "$path_identity" == "$candidate_root_identity" ]] || die 'candidate root path was substituted during release probes'
}
assert_candidate_root_bound
object_selector=GIT_OBJECT_DIRE; object_selector=${object_selector}CTORY
alternate_selector=GIT_ALT; alternate_selector=${alternate_selector}ERNATE_OBJECT_DIRE; alternate_selector=${alternate_selector}CTORIES
for selector in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR "$object_selector" "$alternate_selector" GIT_INDEX_FILE GIT_NAMESPACE GIT_REPLACE_REF_BASE GIT_GRAFT_FILE GIT_SHALLOW_FILE GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL; do
  if printenv "$selector" >/dev/null 2>&1; then
    die "ambient Git selector is set: $selector"
  fi
done

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else die 'missing SHA-256 utility'; fi
}
hash_stream() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}';
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}';
  else die 'missing SHA-256 utility'; fi
}
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
tree_digest() {
  (
    cd "$root"
    find . -path './.git' -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r path; do
      printf '%s\t%s\t%s\n' "$path" "$(mode_of "$path")" "$(hash_file "$path")"
    done
  ) | hash_stream
}

git_identity() {
  local repo=$1 head_ref state_path state_name child
  head_ref=$(git -C "$repo" symbolic-ref -q HEAD || printf '%s' '(detached)')
  (
    printf 'head-ref\t%s\n' "$head_ref"
    printf 'head-oid\t%s\n' "$(git -C "$repo" rev-parse --verify HEAD)"
    printf 'shallow\t%s\n' "$(git -C "$repo" rev-parse --is-shallow-repository)"
    git -C "$repo" for-each-ref --format='ref	%(refname)	%(objectname)	%(objecttype)	%(symref)' | LC_ALL=C sort
    for state_name in info/attributes info/grafts objects/info/alternates objects/info/http-alternates objects/info/commit-graph objects/info/commit-graphs shallow; do
      state_path=$(git -C "$repo" rev-parse --git-path "$state_name") || die 'could not resolve Git state'
      case "$state_path" in
        /*) ;;
        *) state_path=$repo/$state_path ;;
      esac
      if [[ -f "$state_path" && ! -L "$state_path" ]]; then
        printf 'git-state\t%s\t%s\n' "$state_name" "$(hash_file "$state_path")"
      elif [[ -d "$state_path" && ! -L "$state_path" ]]; then
        printf 'git-state-directory\t%s\n' "$state_name"
        while IFS= read -r child; do
          if [[ -f "$child" && ! -L "$child" ]]; then
            printf 'git-state-child\t%s\t%s\t%s\n' "$state_name" "${child#"$state_path"/}" "$(hash_file "$child")"
          else
            printf 'git-state-child\t%s\t%s\tnon-regular\n' "$state_name" "${child#"$state_path"/}"
          fi
        done < <(find "$state_path" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
      elif [[ -e "$state_path" || -L "$state_path" ]]; then
        printf 'git-state\t%s\tnon-regular\n' "$state_name"
      else
        printf 'git-state\t%s\tabsent\n' "$state_name"
      fi
    done
  ) | hash_stream
}

raw_git() {
  local repo=$1
  shift
  git -C "$repo" -c core.commitGraph=false "$@"
}

assert_git_identity_unchanged() {
  local repo=$1 expected=$2 actual
  actual=$(git_identity "$repo") || die 'could not re-read reachable Git identity'
  [[ "$actual" == "$expected" ]] || die 'reachable Git identity changed during release probes'
}

bash "$root/tools/hygiene-lint.sh" "$root"
git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 'candidate is not a Git worktree'
git -C "$root" diff --check HEAD
[[ -z $(git -C "$root" status --porcelain=v1 --untracked-files=all) ]] || die 'candidate repository is not clean'
before=$(tree_digest)
before_git=$(git_identity "$root")

secret_scratch=$(mktemp -d)
trap 'find "$secret_scratch" -depth -delete' EXIT HUP INT TERM
empty_ignore=$secret_scratch/empty-ignore
: >"$empty_ignore"

run_gitleaks() {
  local subcommand=$1
  shift
  (
    unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.commitGraph GIT_CONFIG_VALUE_0=false \
      "$gitleaks_bin" "$subcommand" \
      --no-banner --redact=100 --ignore-gitleaks-allow \
      --gitleaks-ignore-path "$empty_ignore" -l error "$@"
  )
}

write_git_metadata_corpus() {
  local repo=$1 destination=$2 oid type commit path_stream metadata_file
  mkdir -p "$destination"
  : >"$destination/commits"
  : >"$destination/tags"
  : >"$destination/paths"
  : >"$destination/refs"
  : >"$destination/.commits"
  raw_git "$repo" rev-list --objects --all --no-object-names >"$destination/.objects" || die 'could not enumerate reachable Git objects'
  raw_git "$repo" cat-file --batch-check='%(objectname) %(objecttype)' <"$destination/.objects" >"$destination/.types" || die 'could not type reachable Git objects'
  while IFS=' ' read -r oid type; do
    case "$type" in
      commit)
        printf '%s\n' "$oid" >>"$destination/.commits"
        raw_git "$repo" cat-file commit "$oid" >>"$destination/commits" || die 'could not read reachable Git commit metadata'
        printf '\n' >>"$destination/commits"
        ;;
      tag)
        raw_git "$repo" cat-file tag "$oid" >>"$destination/tags" || die 'could not read reachable Git tag metadata'
        printf '\n' >>"$destination/tags"
        ;;
    esac
  done <"$destination/.types"
  path_stream=$destination/.path-stream
  while IFS= read -r commit; do
    raw_git "$repo" ls-tree -r -z --name-only "$commit" >"$path_stream" || die 'could not enumerate historical path names'
    while IFS= read -r -d '' path; do printf '%s\n' "$path" >>"$destination/paths"; done <"$path_stream"
  done <"$destination/.commits"
  git -C "$repo" for-each-ref --format='%(refname)' >"$destination/refs" || die 'could not enumerate Git ref names'
  for metadata_file in "$destination/commits" "$destination/tags" "$destination/paths" "$destination/refs"; do
    if LC_ALL=C od -An -tx1 "$metadata_file" | grep -Eq '(^|[[:space:]])00([[:space:]]|$)'; then
      die 'reachable Git metadata contains a NUL byte'
    fi
  done
}

docs=()
while IFS= read -r -d '' document; do docs+=("$document"); done < <(find "$root" -type f -name '*.md' -not -path '*/.git/*' -print0)
bash "$root/tools/doc-lint.sh" "${docs[@]}"
bash "$root/tools/citation-lint.sh" "$root" "${docs[@]}"

while IFS= read -r -d '' json; do jq -e . "$json" >/dev/null; done < <(find "$root" -type f -name '*.json' -not -path '*/.git/*' -print0)
shell_files=()
while IFS= read -r -d '' file; do
  [[ -x "$file" ]] || continue
  shell_files+=("$file")
  case $(head -n 1 "$file") in
    '#!/bin/sh') sh -n "$file" ;;
    '#!/usr/bin/env bash') bash -n "$file" ;;
    *) die "unrecognized executable format: ${file#"$root"/}" ;;
  esac
done < <(find "$root" -type f -not -path '*/.git/*' -print0)
if [[ "$mode" != portable ]]; then
  shellcheck -x "${shell_files[@]}"
fi

bash "$root/tests/manifest-test.sh" "$root"
bash "$root/tests/docs-test.sh" "$root"
bash "$root/tests/mcp-launchers-test.sh" "$root"
bash "$root/tests/hooks-test.sh" "$root"
bash "$root/tests/gates-red-test.sh" "$root"

bash "$root/tools/history-hygiene.sh" "$root" "$gitleaks_bin" "$empty_ignore"
run_gitleaks dir "$root"
history_log_opts='--all -m'
run_gitleaks git --log-opts="$history_log_opts" "$root"
candidate_metadata=$secret_scratch/candidate-git-metadata
write_git_metadata_corpus "$root" "$candidate_metadata"
run_gitleaks dir "$candidate_metadata"
git -C "$root" diff --check HEAD
[[ -z $(git -C "$root" status --porcelain=v1 --untracked-files=all) ]] || die 'candidate repository is not clean'

fixture_dir=$secret_scratch/fixture
mkdir -p "$fixture_dir"
prefix='AK''IA'
inline_allow='gitleaks:''allow'
printf 'access_key = "%s%s" # %s\n' "$prefix" '7QWERTYUIOPASDFG' "$inline_allow" >"$fixture_dir/fixture.txt"
set +e
report=$(GITLEAKS_CONFIG="$secret_scratch/missing-config" GITLEAKS_CONFIG_TOML='deliberately invalid' \
  run_gitleaks dir --exit-code 23 --report-format json --report-path - "$fixture_dir" 2>"$secret_scratch/red.err")
status=$?
set -e
[[ "$status" -eq 23 ]] || die "Gitleaks red control exited $status, expected 23"
jq -e 'type == "array" and any(.[]; .RuleID == "aws-access-token")' <<<"$report" >/dev/null || die 'Gitleaks red control did not materialize the expected detector'

ambient=$secret_scratch/ambient-cwd
ambient_target=$secret_scratch/ambient-target
mkdir -p "$ambient" "$ambient_target"
printf 'access_key = "%s%s"\n' "$prefix" '7QWERTYUIOPASDFG' >"$ambient_target/fixture.txt"
set +e
ambient_report=$(cd "$ambient" && run_gitleaks dir --exit-code 23 --report-format json --report-path - "$ambient_target" 2>"$secret_scratch/ambient-baseline.err")
ambient_status=$?
set -e
[[ "$ambient_status" -eq 23 ]] || die "Gitleaks ambient baseline exited $ambient_status, expected 23"
fingerprint=$(jq -er 'map(select(.RuleID == "aws-access-token")) | first | .Fingerprint' <<<"$ambient_report") || die 'Gitleaks ambient baseline emitted no fingerprint'
ignore_name='.gitleaks''ignore'
printf '%s\n' "$fingerprint" >"$ambient/$ignore_name"
set +e
(cd "$ambient" && unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML && \
  "$gitleaks_bin" dir --no-banner --redact=100 -l error --exit-code 23 "$ambient_target" >/dev/null 2>"$secret_scratch/ambient-unprotected.err")
unprotected_status=$?
set -e
[[ "$unprotected_status" -eq 0 ]] || die 'Gitleaks ambient ignore control was not capable of suppressing the detector'
set +e
report=$(cd "$ambient" && run_gitleaks dir --exit-code 23 --report-format json --report-path - "$ambient_target" 2>"$secret_scratch/ambient.err")
status=$?
set -e
[[ "$status" -eq 23 ]] || die "Gitleaks ambient-ignore control exited $status, expected 23"
jq -e 'type == "array" and any(.[]; .RuleID == "aws-access-token")' <<<"$report" >/dev/null || die 'Gitleaks ambient-ignore control suppressed the detector'

merge_repo=$secret_scratch/merge-history
mkdir -p "$merge_repo"
git -C "$merge_repo" init -q
empty_tree=$(git -C "$merge_repo" mktree </dev/null)
committer_name_key=GIT_COMMI; committer_name_key=${committer_name_key}TTER_NAME
committer_email_key=GIT_COMMI; committer_email_key=${committer_email_key}TTER_EMAIL
merge_commit_tree() {
  env GIT_AUTHOR_NAME='nSOUL Merge Red' GIT_AUTHOR_EMAIL='nsoul@invalid.example' \
    "$committer_name_key=nSOUL Merge Red" "$committer_email_key=nsoul@invalid.example" \
    git -C "$merge_repo" -c commit.gpgsign=false commit-tree "$@"
}
base=$(printf 'base\n' | merge_commit_tree "$empty_tree")
left=$(printf 'left\n' | merge_commit_tree "$empty_tree" -p "$base")
right=$(printf 'right\n' | merge_commit_tree "$empty_tree" -p "$base")
secret_blob=$(printf 'access_key = "%s%s"\n' "$prefix" '7QWERTYUIOPASDFG' | git -C "$merge_repo" hash-object -w --stdin)
secret_tree=$(printf '100644 blob %s\tmerge-secret.txt\n' "$secret_blob" | git -C "$merge_repo" mktree)
merge=$(printf 'merge\n' | merge_commit_tree "$secret_tree" -p "$left" -p "$right")
clean_child=$(printf 'clean\n' | merge_commit_tree "$empty_tree" -p "$merge")
git -C "$merge_repo" update-ref refs/heads/main "$clean_child"
set +e
run_gitleaks git --exit-code 23 --log-opts='--all' "$merge_repo" >/dev/null 2>"$secret_scratch/merge-baseline.err"
baseline_status=$?
report=$(run_gitleaks git --exit-code 23 --report-format json --report-path - --log-opts="$history_log_opts" "$merge_repo" 2>"$secret_scratch/merge-red.err")
status=$?
set -e
[[ "$baseline_status" -eq 0 ]] || die 'Gitleaks merge-only fixture is not differentiating'
[[ "$status" -eq 23 ]] || die "Gitleaks merge-history control exited $status, expected 23"
jq -e 'type == "array" and any(.[]; .RuleID == "aws-access-token")' <<<"$report" >/dev/null || die 'Gitleaks merge-history control did not materialize the expected detector'

attribute_repo=$secret_scratch/attribute-suppressed-history
mkdir -p "$attribute_repo"
(cd "$root" && tar --exclude='./.git' -cf - .) | (cd "$attribute_repo" && tar -xf -)
git -C "$attribute_repo" init -q -b main
git -C "$attribute_repo" -c core.hooksPath=/dev/null add -A
git -C "$attribute_repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
  -c user.name='nSOUL Attribute Red' -c user.email='nsoul@invalid.example' commit -qm 'public baseline'
attribute_baseline=$(git -C "$attribute_repo" rev-parse HEAD)
attribute_key=${prefix}7LKJHGFDSAPOIUYT
printf 'access_key = "%s"\n' "$attribute_key" >"$attribute_repo/history-secret.txt"
git -C "$attribute_repo" -c core.hooksPath=/dev/null add history-secret.txt
git -C "$attribute_repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
  -c user.name='nSOUL Attribute Red' -c user.email='nsoul@invalid.example' commit -qm 'secret history'
git -C "$attribute_repo" -c core.hooksPath=/dev/null rm -q history-secret.txt
git -C "$attribute_repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
  -c user.name='nSOUL Attribute Red' -c user.email='nsoul@invalid.example' commit -qm 'clean child'
attribute_path=$(git -C "$attribute_repo" rev-parse --git-path info/attributes)
case "$attribute_path" in
  /*) ;;
  *) attribute_path=$attribute_repo/$attribute_path ;;
esac
mkdir -p "${attribute_path%/*}"
printf 'history-secret.txt -diff\n' >"$attribute_path"
set +e
run_gitleaks git --exit-code 23 --log-opts="$history_log_opts" "$attribute_repo" >/dev/null 2>"$secret_scratch/attribute-suppressed.err"
attribute_suppressed_status=$?
attribute_history_output=$(bash "$attribute_repo/tools/history-hygiene.sh" \
  "$attribute_repo" "$gitleaks_bin" "$empty_ignore" 2>&1)
attribute_history_status=$?
set -e
[[ "$attribute_suppressed_status" -eq 0 ]] || die 'Git info-attributes fixture did not suppress the diff-based history detector'
[[ "$attribute_history_status" -ne 0 && "$attribute_history_output" == *'a historical tree contains a secret'* ]] || die 'raw historical-tree secret scan did not defeat Git attribute suppression'
rm -f "$attribute_path"
git -C "$attribute_repo" -c core.hooksPath=/dev/null reset --hard -q "$attribute_baseline"
: >"$attribute_path"
set +e
attribute_state_output=$(bash "$attribute_repo/tools/history-hygiene.sh" "$attribute_repo" 2>&1)
attribute_state_status=$?
set -e
[[ "$attribute_state_status" -ne 0 && "$attribute_state_output" == *'repository uses an info attributes file'* ]] || die 'history hygiene did not reject Git info attributes directly'
rm -f "$attribute_path"

metadata_repo=$secret_scratch/git-metadata-history
mkdir -p "$metadata_repo"
git -C "$metadata_repo" init -q
metadata_commit_tree() {
  env GIT_AUTHOR_NAME='nSOUL Metadata Red' GIT_AUTHOR_EMAIL='nsoul@invalid.example' \
    "$committer_name_key=nSOUL Metadata Red" "$committer_email_key=nsoul@invalid.example" \
    git -C "$metadata_repo" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit-tree "$@"
}
metadata_empty_tree=$(git -C "$metadata_repo" mktree </dev/null)
commit_key=${prefix}7QWERTYUIOPASDFG
path_key=${prefix}7ASDFGHJKLQWERTY
ref_key=${prefix}7ZXCVBNMQWERTYUI
tag_key=${prefix}7POIUYTREWQLKJHG
metadata_base=$(printf 'metadata %s\n' "$commit_key" | metadata_commit_tree "$metadata_empty_tree")
metadata_empty_blob=$(printf '' | git -C "$metadata_repo" hash-object -w --stdin)
metadata_path_tree=$(printf '100644 blob %s\t%s\n' "$metadata_empty_blob" "$path_key" | git -C "$metadata_repo" mktree)
metadata_path_commit=$(printf 'path fixture\n' | metadata_commit_tree "$metadata_path_tree" -p "$metadata_base")
metadata_clean_commit=$(printf 'clean child\n' | metadata_commit_tree "$metadata_empty_tree" -p "$metadata_path_commit")
git -C "$metadata_repo" update-ref refs/heads/main "$metadata_clean_commit"
git -C "$metadata_repo" update-ref "refs/heads/$ref_key" "$metadata_clean_commit"
metadata_tag=$(printf 'object %s\ntype commit\ntag release\ntagger nSOUL Metadata Red <nsoul@invalid.example> 1700000000 +0000\n\ntag %s\n' "$metadata_clean_commit" "$tag_key" | git -C "$metadata_repo" mktag)
git -C "$metadata_repo" update-ref refs/tags/release "$metadata_tag"
set +e
run_gitleaks git --exit-code 23 --log-opts="$history_log_opts" "$metadata_repo" >/dev/null 2>"$secret_scratch/metadata-baseline.err"
metadata_baseline_status=$?
set -e
[[ "$metadata_baseline_status" -eq 0 ]] || die 'Gitleaks metadata fixture is not differentiating from the ordinary history scan'
metadata_corpus=$secret_scratch/metadata-red-corpus
write_git_metadata_corpus "$metadata_repo" "$metadata_corpus"
set +e
report=$(run_gitleaks dir --exit-code 23 --report-format json --report-path - "$metadata_corpus" 2>"$secret_scratch/metadata-red.err")
status=$?
set -e
[[ "$status" -eq 23 ]] || die "Gitleaks metadata control exited $status, expected 23"
jq -e '
  type == "array"
  and all(.[]; .RuleID == "aws-access-token")
  and ([.[].File | split("/") | last] | unique | sort) == ["commits", "paths", "refs", "tags"]
' <<<"$report" >/dev/null || die 'Gitleaks metadata control did not cover commit, tag, path, and ref metadata'

identity_before=$(git_identity "$metadata_repo")
metadata_attributes=$(git -C "$metadata_repo" rev-parse --git-path info/attributes)
case "$metadata_attributes" in
  /*) ;;
  *) metadata_attributes=$metadata_repo/$metadata_attributes ;;
esac
mkdir -p "${metadata_attributes%/*}"
: >"$metadata_attributes"
if (assert_git_identity_unchanged "$metadata_repo" "$identity_before") >/dev/null 2>&1; then
  die 'Git-identity pin accepted a post-scan info-attributes change'
fi
rm -f "$metadata_attributes"
metadata_main_oid=$(git -C "$metadata_repo" rev-parse refs/heads/main)
git -C "$metadata_repo" update-ref refs/heads/identity-alias "$metadata_main_oid"
identity_direct_ref=$(git_identity "$metadata_repo")
git -C "$metadata_repo" symbolic-ref refs/heads/identity-alias refs/heads/main
[[ $(git -C "$metadata_repo" rev-parse refs/heads/identity-alias) == "$metadata_main_oid" ]] || die 'symbolic-ref fixture changed the resolved object id'
if (assert_git_identity_unchanged "$metadata_repo" "$identity_direct_ref") >/dev/null 2>&1; then
  die 'Git-identity pin equated a direct ref with a symbolic ref at the same object id'
fi
git -C "$metadata_repo" update-ref -d refs/heads/identity-alias
identity_key=${prefix}7MNBVCXZLKJHGFDS
identity_blob=$(printf 'access_key = "%s"\n' "$identity_key" | git -C "$metadata_repo" hash-object -w --stdin)
identity_tree=$(printf '100644 blob %s\tidentity-secret.txt\n' "$identity_blob" | git -C "$metadata_repo" mktree)
identity_secret_commit=$(printf 'identity secret\n' | metadata_commit_tree "$identity_tree" -p "$metadata_clean_commit")
identity_clean_commit=$(printf 'identity clean child\n' | metadata_commit_tree "$metadata_empty_tree" -p "$identity_secret_commit")
git -C "$metadata_repo" update-ref refs/heads/main "$identity_clean_commit"
[[ -z $(git -C "$metadata_repo" status --porcelain=v1 --untracked-files=all) ]] || die 'Git-identity fixture did not preserve a clean current tree'
if (assert_git_identity_unchanged "$metadata_repo" "$identity_before") >/dev/null 2>&1; then
  die 'Git-identity pin accepted a post-scan reachable-history change'
fi

if [[ "$mode" == full ]]; then
  claude plugin validate --strict "$root"
  bash "$root/tests/client-discovery-test.sh" "$root"
fi

after=$(tree_digest)
[[ "$before" == "$after" ]] || die 'release probes changed candidate bytes or modes'
git -C "$root" diff --check HEAD
[[ -z $(git -C "$root" status --porcelain=v1 --untracked-files=all) ]] || die 'candidate repository changed during release probes'
assert_git_identity_unchanged "$root" "$before_git"
assert_candidate_root_bound
printf 'public-release-check: pass (mode=%s; candidate unchanged)\n' "$mode"
