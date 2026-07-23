#!/usr/bin/env bash
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1

die() { printf 'history-hygiene: %s\n' "$*" >&2; exit 1; }
for command_name in bash chmod find git mkdir mktemp od printenv; do
  command -v -- "$command_name" >/dev/null 2>&1 || die "missing required command: $command_name"
done
object_selector=GIT_OBJECT_DIRE; object_selector=${object_selector}CTORY
alternate_selector=GIT_ALT; alternate_selector=${alternate_selector}ERNATE_OBJECT_DIRE; alternate_selector=${alternate_selector}CTORIES
for selector in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR "$object_selector" "$alternate_selector" GIT_INDEX_FILE GIT_NAMESPACE GIT_REPLACE_REF_BASE GIT_GRAFT_FILE GIT_SHALLOW_FILE GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL; do
  if printenv "$selector" >/dev/null 2>&1; then
    die "ambient Git selector is set: $selector"
  fi
done
[[ "$#" -eq 1 || "$#" -eq 3 ]] || die 'usage: history-hygiene.sh REPOSITORY_ROOT [GITLEAKS_BIN EMPTY_IGNORE]'
root=$1
gitleaks_bin=${2:-}
gitleaks_ignore=${3:-}
[[ -d "$root" && ! -L "$root" ]] || die 'repository root is not an ordinary directory'
if [[ -n "$gitleaks_bin" ]]; then
  [[ -x "$gitleaks_bin" && -f "$gitleaks_bin" ]] || die 'Gitleaks binary is not executable'
  [[ -f "$gitleaks_ignore" && ! -L "$gitleaks_ignore" ]] || die 'Gitleaks ignore input is not an ordinary file'
fi
git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 'repository root is not a Git worktree'
[[ $(git -C "$root" rev-parse --is-shallow-repository) == false ]] || die 'repository history is shallow'
common_dir=$(git -C "$root" rev-parse --git-common-dir) || die 'could not resolve the Git common directory'
case "$common_dir" in
  /*) ;;
  *) common_dir=$root/$common_dir ;;
esac
[[ -d "$common_dir" && ! -L "$common_dir" ]] || die 'Git common directory is unavailable'
[[ ! -e "$common_dir/info/grafts" && ! -L "$common_dir/info/grafts" ]] || die 'repository uses a legacy graft file'
attributes_path=$(git -C "$root" rev-parse --git-path info/attributes) || die 'could not resolve repository attribute state'
case "$attributes_path" in
  /*) ;;
  *) attributes_path=$root/$attributes_path ;;
esac
for alternate_name in alternates http-alternates; do
  alternate_path=$(git -C "$root" rev-parse --git-path "objects/info/$alternate_name") || die 'could not resolve object-alternate state'
  case "$alternate_path" in
    /*) ;;
    *) alternate_path=$root/$alternate_path ;;
  esac
  [[ ! -e "$alternate_path" && ! -L "$alternate_path" ]] || die 'repository uses an object alternate'
done
replace_ref=$(git -C "$root" for-each-ref --count=1 --format='%(refname)' refs/replace) || die 'could not inspect replacement refs'
[[ -z "$replace_ref" ]] || die 'repository contains replacement refs'
logical_refs=$(git -C "$root" for-each-ref --format='%(refname)') || die 'could not enumerate logical refs'
while IFS= read -r logical_ref; do
  [[ -n "$logical_ref" ]] || continue
  git -C "$root" rev-parse --verify "$logical_ref^{commit}" >/dev/null 2>&1 || die 'repository contains a logical ref that does not peel to a commit'
done <<<"$logical_refs"

scratch=$(mktemp -d)
trap 'find "$scratch" -depth -delete' EXIT HUP INT TERM

raw_git() {
  local repository=$1
  shift
  git -C "$repository" -c core.commitGraph=false "$@"
}

parse_raw_tree() {
  local tree_object=$1 output=$2 hash_digits hash_bytes
  hash_digits=${#tree_object}
  [[ "$tree_object" =~ ^[0-9a-f]+$ && $((hash_digits % 2)) -eq 0 ]] || die 'historical tree has an invalid object id'
  hash_bytes=$((hash_digits / 2))
  if ! raw_git "$root" cat-file tree "$tree_object" \
    | LC_ALL=C od -An -v -tu1 \
    | LC_ALL=C awk -v hash_bytes="$hash_bytes" '
      function reject(message) {
        print "invalid raw tree: " message > "/dev/stderr"
        exit 2
      }
      {
        for (field = 1; field <= NF; field++) {
          if ($field !~ /^[0-9]+$/ || $field < 0 || $field > 255) reject("invalid byte stream")
          bytes[++byte_count] = $field + 0
        }
      }
      END {
        position = 1
        entry_count = 0
        while (position <= byte_count) {
          mode = ""
          while (position <= byte_count && bytes[position] != 32) {
            if (bytes[position] < 48 || bytes[position] > 57) reject("non-numeric mode")
            mode = mode sprintf("%c", bytes[position])
            position++
          }
          if (position > byte_count || mode == "") reject("unterminated mode")
          position++

          name = ""
          while (position <= byte_count && bytes[position] != 0) {
            value = bytes[position]
            if (value < 32 || value > 126 || value == 47) reject("non-portable path component")
            name = name sprintf("%c", value)
            position++
          }
          if (position > byte_count || name == "") reject("unterminated or empty path component")
          position++

          folded = tolower(name)
          if (name == "." || name == ".." || folded == ".git") reject("reserved path component")
          if (seen[folded]++) reject("duplicate or case-colliding path component")
          if (mode != "40000" && mode != "100644" && mode != "100755") reject("unsupported raw mode")

          if (byte_count - position + 1 < hash_bytes) reject("truncated object id")
          object = ""
          for (offset = 0; offset < hash_bytes; offset++) {
            object = object sprintf("%02x", bytes[position + offset])
          }
          position += hash_bytes

          sort_key = name (mode == "40000" ? "/" : sprintf("%c", 1))
          if (entry_count > 0 && sort_key <= previous_sort_key) reject("non-canonical entry order")
          previous_sort_key = sort_key
          entry_count++
          print mode "\t" object "\t" name
        }
      }
    ' >"$output"; then
    die 'could not parse a historical tree without normalization'
  fi
}

entry_file_count=0
materialize_tree() {
  local tree_object=$1 tree=$2 prefix=$3 entries mode object name path target
  entry_file_count=$((entry_file_count + 1))
  entries=$scratch/tree-entries-$entry_file_count
  parse_raw_tree "$tree_object" "$entries"
  while IFS=$'\t' read -r mode object name; do
    [[ -n "$mode" && -n "$object" && -n "$name" ]] || die 'historical tree parser emitted an invalid entry'
    path=$prefix$name
    if [[ "$mode" == 40000 ]]; then
      mkdir -p -- "$tree/$path"
      materialize_tree "$object" "$tree" "$path/"
      continue
    fi
    target=$tree/$path
    mkdir -p -- "${target%/*}"
    raw_git "$root" cat-file blob "$object" >"$target" || die 'could not read a historical blob'
    if [[ "$mode" == 100755 ]]; then
      chmod 0755 "$target"
    else
      chmod 0644 "$target"
    fi
  done <"$entries"
}

commits=$scratch/commits
raw_git "$root" rev-list --all >"$commits" || die 'could not enumerate reachable commit history'
count=0
while IFS= read -r commit; do
  tree=$scratch/tree
  mkdir -p "$tree"
  tree_object=$(raw_git "$root" rev-parse "$commit^{tree}") || die 'could not resolve a historical commit tree'
  entry_file_count=0
  materialize_tree "$tree_object" "$tree" ''
  if [[ -n "$gitleaks_bin" ]]; then
    if ! (
      unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
      "$gitleaks_bin" dir --no-banner --redact=100 --ignore-gitleaks-allow \
        --gitleaks-ignore-path "$gitleaks_ignore" -l error "$tree"
    ) >/dev/null 2>&1; then
      die 'a historical tree contains a secret'
    fi
  fi
  bash "$root/tools/hygiene-lint.sh" "$tree" >/dev/null || die 'a historical tree violates public hygiene'
  find "$tree" -depth -delete
  count=$((count + 1))
done <"$commits"
[[ "$count" -gt 0 ]] || die 'repository has no reachable commit history'
[[ ! -e "$attributes_path" && ! -L "$attributes_path" ]] || die 'repository uses an info attributes file'
printf 'history-hygiene: pass (%s tree(s))\n' "$count"
