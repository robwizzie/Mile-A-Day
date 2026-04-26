#!/usr/bin/env bash
# PostCompact hook: re-inject behavior + workflow-overrides spokes after compaction.
# Reads from both repo-specific references AND universal references (~/.claude/references/),
# whichever exist. In --share mode, universal refs are inside the repo too.

set -euo pipefail

# Repo-specific references live in CLAUDE_PROJECT_DIR/.claude/references/.
# Universal references live in ~/.claude/references/ (default/--commit/--stealth)
# or in CLAUDE_PROJECT_DIR/.claude/references/ (--share).
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
repo_refs="${project_dir}/.claude/references"
user_refs="${HOME}/.claude/references"

echo "=== Reloaded after PostCompact ==="
echo ""

# Universal refs first — workflow rules
for ref in behavior.md workflow-overrides.md security.md; do
  for refs_dir in "$repo_refs" "$user_refs"; do
    if [[ -f "${refs_dir}/${ref}" ]]; then
      echo "--- ${ref} (from ${refs_dir}) ---"
      cat "${refs_dir}/${ref}"
      echo ""
      break
    fi
  done
done

# Repo-specific refs — conventions and gotchas
for ref in conventions.md gotchas.md; do
  if [[ -f "${repo_refs}/${ref}" ]]; then
    echo "--- ${ref} ---"
    cat "${repo_refs}/${ref}"
    echo ""
  fi
done

exit 0
