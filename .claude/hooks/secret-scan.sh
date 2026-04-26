#!/usr/bin/env bash
# PreToolUse hook on Bash(git commit*): runs gitleaks against staged changes.
# If gitleaks finds anything, abort the commit.
# If gitleaks is missing, fail open with a warning (don't block routine work).
#
# Hook input: JSON on stdin with .tool_input.command
# Hook output: exit 0 (allow) or exit 2 (deny + stderr message)
#
# Stealth-aware: gitleaks runs in the nested git tree, but the config lives
# in the parent shell (REPO_BOUND_ROOT). Pass --config explicitly.

set -euo pipefail

source "$(dirname "$0")/_lib/find-git-root.sh"
GIT_ROOT="$(find_git_root)" || exit 0

# REPO_BOUND_ROOT is CLAUDE_PROJECT_DIR (which is the parent shell under stealth,
# the same as GIT_ROOT otherwise). The .gitleaks.toml lives here.
REPO_BOUND_ROOT="${CLAUDE_PROJECT_DIR:-$GIT_ROOT}"

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

# Only apply to `git commit` invocations
if [[ ! "$cmd" =~ git[[:space:]]+commit ]]; then
  exit 0
fi

# Allow `git commit --amend --no-edit` and similar metadata-only invocations to pass
# (they don't change file contents)
if [[ "$cmd" =~ --amend.*--no-edit ]]; then
  exit 0
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "WARN: gitleaks not installed. Secret-scan hook is failing open." >&2
  echo "Install with: brew install gitleaks (macOS) or download from github.com/gitleaks/gitleaks" >&2
  exit 0
fi

# Use the .gitleaks.toml at REPO_BOUND_ROOT if present
config_arg=""
if [[ -f "$REPO_BOUND_ROOT/.gitleaks.toml" ]]; then
  config_arg="--config=$REPO_BOUND_ROOT/.gitleaks.toml"
fi

# Run gitleaks against staged changes (must run from inside the git tree)
output=$(cd "$GIT_ROOT" && gitleaks protect --staged $config_arg --redact --no-banner 2>&1) && status=0 || status=$?

if [[ $status -ne 0 ]]; then
  echo "BLOCKED: gitleaks detected potential secrets in staged changes." >&2
  echo "" >&2
  echo "$output" >&2
  echo "" >&2
  echo "To fix:" >&2
  echo "  1. Remove the secret from the file (don't just unstage — git remembers)" >&2
  echo "  2. If it's a false positive, add to .gitleaks.toml allowlist" >&2
  echo "  3. NEVER use --no-verify to bypass this — secrets in commits are forever" >&2
  exit 2
fi

exit 0
