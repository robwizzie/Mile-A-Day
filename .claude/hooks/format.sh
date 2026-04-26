#!/usr/bin/env bash
# PostToolUse hook on Write/Edit: run the project's formatter on the file.
# Stack-conditional: detects formatter from project config in the actual git tree.

set -euo pipefail

# Source helper for stealth-mode git tree resolution
source "$(dirname "$0")/_lib/find-git-root.sh"
GIT_ROOT="$(find_git_root)" || exit 0

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
  exit 0
fi

ext="${file##*.}"

case "$ext" in
  ts|tsx|js|jsx|mjs|cjs)
    if [[ -f "$GIT_ROOT/biome.json" || -f "$GIT_ROOT/biome.jsonc" ]] && command -v biome >/dev/null 2>&1; then
      (cd "$GIT_ROOT" && biome format --write "$file") >/dev/null 2>&1 || true
    elif [[ -f "$GIT_ROOT/.prettierrc" || -f "$GIT_ROOT/.prettierrc.json" || -f "$GIT_ROOT/.prettierrc.js" || -f "$GIT_ROOT/prettier.config.js" ]] && command -v prettier >/dev/null 2>&1; then
      (cd "$GIT_ROOT" && prettier --write "$file") >/dev/null 2>&1 || true
    elif command -v npx >/dev/null 2>&1; then
      (cd "$GIT_ROOT" && npx prettier --write "$file") >/dev/null 2>&1 || true
    fi
    ;;
  py)
    if [[ -f "$GIT_ROOT/pyproject.toml" ]] && grep -q '\[tool.ruff\]' "$GIT_ROOT/pyproject.toml" 2>/dev/null && command -v ruff >/dev/null 2>&1; then
      ruff format "$file" >/dev/null 2>&1 || true
    elif command -v black >/dev/null 2>&1; then
      black --quiet "$file" >/dev/null 2>&1 || true
    fi
    ;;
  rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt "$file" 2>/dev/null || true
    ;;
  go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$file" 2>/dev/null || true
    ;;
  swift)
    command -v swiftformat >/dev/null 2>&1 && swiftformat --quiet "$file" 2>/dev/null || true
    ;;
  c|cc|cpp|h|hpp)
    command -v clang-format >/dev/null 2>&1 && clang-format -i "$file" 2>/dev/null || true
    ;;
esac

exit 0
