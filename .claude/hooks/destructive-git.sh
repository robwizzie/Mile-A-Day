#!/usr/bin/env bash
# PreToolUse hook: intercepts destructive git operations.
# Hook input is JSON on stdin: { tool_name, tool_input: { command, ... }, ... }
# Hook output: JSON on stdout: { decision: "allow"|"deny", reason: "..." }
# OR exit code 0 (allow), exit code 2 with stderr (deny + reason).
#
# Patterns intercepted (revised, post-review):
#   - git push --force (without --force-with-lease)
#   - git reset --hard
#   - git checkout HEAD -- <path>
#   - git clean -f
#   - git branch -D
#   - git reflog expire ... --expire=now
#   - git filter-branch
#   - git filter-repo
#   - git push origin :branch (delete remote branch)
#
# git rebase --abort is intentionally NOT intercepted (safe escape hatch).

set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

if [[ -z "$cmd" ]]; then
  exit 0
fi

# Quick allowlist: not a git command at all
if [[ ! "$cmd" =~ (^|[[:space:]])git[[:space:]] ]]; then
  exit 0
fi

deny() {
  local reason="$1"
  echo "BLOCKED: $reason" >&2
  echo "" >&2
  echo "If you intended this operation, type the EXACT command back to the user for confirmation." >&2
  echo "Force-with-lease alternative may be safer for force-push." >&2
  exit 2
}

# Detect each pattern
match_force_push=$(echo "$cmd" | grep -E 'git[[:space:]]+push[^|;&]*--force([^-]|$)' | grep -vE -- '--force-with-lease' || true)
match_force_with_lease=$(echo "$cmd" | grep -E 'git[[:space:]]+push[^|;&]*--force-with-lease' || true)
match_reset_hard=$(echo "$cmd" | grep -E 'git[[:space:]]+reset[^|;&]*--hard' || true)
match_checkout_head=$(echo "$cmd" | grep -E 'git[[:space:]]+checkout[[:space:]]+HEAD[[:space:]]+--' || true)
match_clean_f=$(echo "$cmd" | grep -E 'git[[:space:]]+clean[^|;&]*[[:space:]]-[a-zA-Z]*f' || true)
match_branch_delete=$(echo "$cmd" | grep -E 'git[[:space:]]+branch[^|;&]*-D[[:space:]]' || true)
match_reflog_wipe=$(echo "$cmd" | grep -E 'git[[:space:]]+reflog[[:space:]]+expire.*--expire=now' || true)
match_filter_branch=$(echo "$cmd" | grep -E 'git[[:space:]]+filter-branch' || true)
match_filter_repo=$(echo "$cmd" | grep -E 'git[[:space:]]+filter-repo' || true)
match_remote_delete=$(echo "$cmd" | grep -E 'git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+:[^[:space:]]+' || true)

# --force-with-lease gets a single re-confirm prompt (deny first, user re-runs)
if [[ -n "$match_force_with_lease" ]]; then
  marker_dir="${TMPDIR:-/tmp}/cc-optimize-force-with-lease"
  mkdir -p "$marker_dir"
  marker="$marker_dir/$(echo -n "$cmd" | md5 -q 2>/dev/null || echo -n "$cmd" | md5sum | cut -d' ' -f1)"
  if [[ -f "$marker" ]] && [[ $(($(date +%s) - $(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker"))) -lt 60 ]]; then
    rm -f "$marker"
    exit 0  # allow on second invocation within 60s
  fi
  touch "$marker"
  deny "force-with-lease push detected. Re-run within 60s to confirm: $cmd"
fi

if [[ -n "$match_force_push" ]]; then
  deny "force-push detected (without --force-with-lease). Use --force-with-lease for safer force-push, or re-confirm explicitly: $cmd"
fi

if [[ -n "$match_reset_hard" ]]; then
  deny "git reset --hard destroys uncommitted changes: $cmd"
fi

if [[ -n "$match_checkout_head" ]]; then
  deny "git checkout HEAD -- <path> destroys uncommitted work: $cmd"
fi

if [[ -n "$match_clean_f" ]]; then
  deny "git clean -f deletes untracked files irreversibly: $cmd"
fi

if [[ -n "$match_branch_delete" ]]; then
  deny "git branch -D force-deletes a branch (loses unmerged work): $cmd"
fi

if [[ -n "$match_reflog_wipe" ]]; then
  deny "reflog expiry wipes recovery history: $cmd"
fi

if [[ -n "$match_filter_branch" ]]; then
  deny "git filter-branch rewrites history: $cmd"
fi

if [[ -n "$match_filter_repo" ]]; then
  deny "git filter-repo rewrites history: $cmd"
fi

if [[ -n "$match_remote_delete" ]]; then
  deny "git push :branch deletes a remote branch: $cmd"
fi

# All clear
exit 0
