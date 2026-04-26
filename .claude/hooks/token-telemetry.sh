#!/usr/bin/env bash
# PostToolUse hook: log token spend estimate per tool call.
# Writes JSONL to <REPO_BOUND_ROOT>/.claude/telemetry/spend.jsonl
#
# Estimation: char count / 4 fallback. If `python3 -c "import tiktoken"` works,
# uses tiktoken (cl100k_base) for ±15% accuracy. Statusline reads latest line.
#
# Note in output that values are estimates (~ prefix in /maintain reports).
# Use for trend detection only, not raw budgeting.

set -euo pipefail

input=$(cat)

ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tool=$(echo "$input" | jq -r '.tool_name // "unknown"')
result_chars=$(echo "$input" | jq -r '.tool_response // ""' | wc -c | tr -d ' ')

# Telemetry lives in REPO_BOUND_ROOT/.claude/telemetry/, which is the parent
# shell under stealth and the repo root otherwise.
REPO_BOUND_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
mkdir -p "$REPO_BOUND_ROOT/.claude/telemetry"
log_file="$REPO_BOUND_ROOT/.claude/telemetry/spend.jsonl"

# Token estimation: prefer tiktoken if available, else char count / 4
if python3 -c "import tiktoken" >/dev/null 2>&1; then
  est_tokens=$(echo "$input" | jq -r '.tool_response // ""' | python3 -c "
import sys, tiktoken
enc = tiktoken.get_encoding('cl100k_base')
print(len(enc.encode(sys.stdin.read())))
" 2>/dev/null || echo "$((result_chars / 4))")
else
  est_tokens=$((result_chars / 4))
fi

entry=$(jq -nc \
  --arg ts "$ts" \
  --arg tool "$tool" \
  --arg est "$est_tokens" \
  '{ts: $ts, tool: $tool, est_tokens: ($est | tonumber), method: ("tiktoken-or-charcount-div-4")}')

echo "$entry" >> "$log_file"

# Don't block on telemetry — always exit 0
exit 0
