#!/usr/bin/env bash
# SubagentStop hook for executor agent: enforce change-budget.
# Compares the diff after task completion to the task's declared file scope.
# Out-of-scope changes:
#   < 5 lines: warn but allow
#   5-50 lines: require justification (block, ask user)
#   > 50 lines: revert and split (block hard)
#
# Reads task scope from .claude/specs/<current-task>.scope or
# from a per-task scope marker the executor writes pre-flight.

set -euo pipefail

# Source helper for stealth-mode git tree resolution
source "$(dirname "$0")/_lib/find-git-root.sh"
GIT_ROOT="$(find_git_root)" || { echo "change-budget: no git root found, skipping" >&2; exit 0; }

input=$(cat)

# Find the task's declared scope file. The executor agent should write
# .claude/.current-task-scope (a glob list, one per line) before starting.
# In stealth mode, this lives in CLAUDE_PROJECT_DIR (parent shell), not GIT_ROOT.
scope_file="${CLAUDE_PROJECT_DIR:-$GIT_ROOT}/.claude/.current-task-scope"
if [[ ! -f "$scope_file" ]]; then
  # No scope declared = no enforcement (e.g., for ad-hoc invocations)
  exit 0
fi

# Get the diff that just landed (run from inside the git tree)
diff_files=$(cd "$GIT_ROOT" && git diff --name-only HEAD 2>/dev/null || true)

if [[ -z "$diff_files" ]]; then
  exit 0
fi

# Read declared scope globs
mapfile -t scope_globs < "$scope_file"

# Find out-of-scope files
out_of_scope=()
while IFS= read -r file; do
  in_scope=false
  for glob in "${scope_globs[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$file" == $glob ]]; then
      in_scope=true
      break
    fi
  done
  if [[ "$in_scope" == "false" ]]; then
    out_of_scope+=("$file")
  fi
done <<< "$diff_files"

if [[ ${#out_of_scope[@]} -eq 0 ]]; then
  exit 0
fi

# Count lines changed in out-of-scope files (run from inside git tree)
oos_lines=0
for file in "${out_of_scope[@]}"; do
  lines=$(cd "$GIT_ROOT" && git diff --numstat HEAD -- "$file" 2>/dev/null | awk '{print $1+$2}' || echo 0)
  oos_lines=$((oos_lines + lines))
done

# Threshold logic
if [[ $oos_lines -lt 5 ]]; then
  echo "WARN: ${#out_of_scope[@]} out-of-scope files (${oos_lines} lines). Allowed (cleanup-tier)." >&2
  printf '  %s\n' "${out_of_scope[@]}" >&2
  exit 0
fi

if [[ $oos_lines -le 50 ]]; then
  echo "BLOCKED: ${#out_of_scope[@]} out-of-scope files (${oos_lines} lines)." >&2
  echo "" >&2
  echo "Out-of-scope files:" >&2
  printf '  %s\n' "${out_of_scope[@]}" >&2
  echo "" >&2
  echo "Either:" >&2
  echo "  1. Justify in the task summary why these changes are essential" >&2
  echo "  2. Revert these changes and stay in scope" >&2
  echo "  3. Update the scope (.claude/.current-task-scope) and re-run" >&2
  exit 2
fi

# > 50 lines: hard block
echo "BLOCKED: ${oos_lines} lines changed in ${#out_of_scope[@]} out-of-scope files (limit: 50)." >&2
echo "" >&2
echo "Out-of-scope files:" >&2
printf '  %s\n' "${out_of_scope[@]}" >&2
echo "" >&2
echo "This is too much scope creep for a single task. Split into a new task and revert these files." >&2
exit 2
