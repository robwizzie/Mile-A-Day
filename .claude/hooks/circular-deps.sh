#!/usr/bin/env bash
# PostToolUse hook on multi-file Write/Edit: detect new circular dependencies.
# Stack-conditional: runs madge for JS/TS, pylint --enable=cyclic-import for Python.
# Skip if no cycle-detection tool is installed for the detected stack.

set -euo pipefail

# Source helper for stealth-mode git tree resolution
source "$(dirname "$0")/_lib/find-git-root.sh"
GIT_ROOT="$(find_git_root)" || exit 0

input=$(cat)

# Only run when 3+ files were touched recently (rough heuristic via git status)
files_changed=$(cd "$GIT_ROOT" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [[ $files_changed -lt 3 ]]; then
  exit 0
fi

# Detect stack — look in the actual git tree, not CLAUDE_PROJECT_DIR (which is
# the parent shell under stealth mode, where these files don't exist).
is_js_ts=false
is_python=false
[[ -f "$GIT_ROOT/package.json" ]] && is_js_ts=true
[[ -f "$GIT_ROOT/pyproject.toml" || -f "$GIT_ROOT/setup.py" || -f "$GIT_ROOT/requirements.txt" ]] && is_python=true

if [[ "$is_js_ts" == "true" ]] && command -v madge >/dev/null 2>&1; then
  src_dir="$GIT_ROOT/src"
  [[ ! -d "$src_dir" ]] && src_dir="$GIT_ROOT"
  cycles=$(madge --circular "$src_dir" 2>/dev/null || true)
  if [[ -n "$cycles" ]] && [[ "$cycles" != *"No circular dependency found"* ]]; then
    echo "WARN: Circular dependency detected after this task:" >&2
    echo "$cycles" >&2
    echo "" >&2
    echo "Resolve before /ship. Options:" >&2
    echo "  1. Extract shared code to a third module" >&2
    echo "  2. Invert one of the dependencies (DI / callbacks)" >&2
    echo "  3. Merge the cyclic modules if they truly belong together" >&2
    # Warn but don't block — let task continue, surface at /ship
    exit 0
  fi
fi

if [[ "$is_python" == "true" ]] && command -v pylint >/dev/null 2>&1; then
  src_dir="$GIT_ROOT/src"
  [[ ! -d "$src_dir" ]] && src_dir="$GIT_ROOT"
  cycles=$(pylint --disable=all --enable=cyclic-import --score=no "$src_dir" 2>/dev/null || true)
  if [[ -n "$cycles" ]] && [[ "$cycles" == *"cyclic-import"* ]]; then
    echo "WARN: Circular import detected after this task:" >&2
    echo "$cycles" >&2
    exit 0
  fi
fi

exit 0
