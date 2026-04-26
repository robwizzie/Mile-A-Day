#!/usr/bin/env bash
# Shared hook helper: resolve the actual git tree root.
#
# Stealth mode complication: under `cc-optimize --stealth`, the user's
# CLAUDE_PROJECT_DIR is the *parent shell* (where claude config lives), and the
# real git tree is in a subdirectory one level down. The subdirectory's name
# matches the parent's basename by convention (cc-optimize creates it that way).
#
# Custom multi-repo parent shells (like ~/wisely-optimize/wo_app) can override
# the resolution by setting CC_GIT_TREE_SUBDIR=wo_app in the environment, or by
# placing a `.cc-git-tree` file in CLAUDE_PROJECT_DIR with the relative path on
# the first line.
#
# Usage in a hook:
#   source "$(dirname "$0")/_lib/find-git-root.sh"
#   GIT_ROOT="$(find_git_root)" || { echo "no git root found"; exit 0; }

find_git_root() {
  local start_dir="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

  # Case 1: start_dir IS a git root (default/--commit/--share, or invoked from inside a git tree)
  if [[ -d "$start_dir/.git" ]]; then
    echo "$start_dir"
    return 0
  fi

  # Case 2: explicit override via env var (custom multi-repo parent shells)
  if [[ -n "${CC_GIT_TREE_SUBDIR:-}" ]] && [[ -d "$start_dir/$CC_GIT_TREE_SUBDIR/.git" ]]; then
    echo "$start_dir/$CC_GIT_TREE_SUBDIR"
    return 0
  fi

  # Case 3: explicit override via .cc-git-tree marker file
  if [[ -f "$start_dir/.cc-git-tree" ]]; then
    local subdir
    subdir=$(head -1 "$start_dir/.cc-git-tree" | tr -d '[:space:]')
    if [[ -n "$subdir" ]] && [[ -d "$start_dir/$subdir/.git" ]]; then
      echo "$start_dir/$subdir"
      return 0
    fi
  fi

  # Case 4: stealth-mode convention — nested subdirectory matches parent basename
  local stealth_candidate="$start_dir/$(basename "$start_dir")"
  if [[ -d "$stealth_candidate/.git" ]]; then
    echo "$stealth_candidate"
    return 0
  fi

  # Case 5: walk up from start_dir (covers running from a subdir inside a repo)
  local found
  found=$(cd "$start_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || true
  if [[ -n "$found" ]]; then
    echo "$found"
    return 0
  fi

  # Case 6: last resort — scan one level down for any .git directory.
  # If multiple match, return the first alphabetically (deterministic but possibly wrong).
  # Set CC_GIT_TREE_SUBDIR or use a .cc-git-tree marker to disambiguate.
  local nested
  nested=$(find "$start_dir" -mindepth 2 -maxdepth 2 -name .git -type d 2>/dev/null | sort | head -1)
  if [[ -n "$nested" ]]; then
    dirname "$nested"
    return 0
  fi

  return 1
}
