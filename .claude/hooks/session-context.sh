#!/usr/bin/env bash
# SessionStart hook: inject git context (branch, recent commits, dirty files).
# Stealth-aware: uses find-git-root to locate the actual git tree even when
# CLAUDE_PROJECT_DIR is the parent shell under --stealth mode.

set -euo pipefail

# Source helper for stealth-mode git tree resolution
source "$(dirname "$0")/_lib/find-git-root.sh"
GIT_ROOT="$(find_git_root)" || exit 0

cd "$GIT_ROOT"

branch=$(git branch --show-current 2>/dev/null || echo "(detached)")
recent=$(git log --oneline -3 2>/dev/null || echo "(no history)")
status=$(git status --short 2>/dev/null | head -10 || echo "")

echo "Branch: $branch"
echo "Recent:"
echo "$recent" | sed 's/^/  /'
if [[ -n "$status" ]]; then
  echo "Status:"
  echo "$status" | sed 's/^/  /'
fi

exit 0
