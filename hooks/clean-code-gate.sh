#!/usr/bin/env bash
# hooks/clean-code-gate.sh — Claude Stop hook
#
# If the last assistant turn used a code-editing tool (Edit, Write, apply_patch,
# NotebookEdit) and did not self-report a "Clean Code Gate:" line, nudge via
# additionalContext. Never blocks (no decision:block) — low friction, no hard
# loops. Handles a missing/garbled transcript gracefully (always exits 0).
set -euo pipefail

EDIT_TOOLS_PATTERN='^(Edit|Write|apply_patch|NotebookEdit)$'
GATE_LINE_PATTERN='Clean Code Gate:'
NUDGE_MESSAGE='Code was edited but no Clean Code Gate: passed|blocked self-report was emitted. Run the gate against the touched code and report.'

payload=$(cat)
transcript_path=$(printf '%s' "$payload" | jq -r '.transcript_path // ""' 2>/dev/null) || transcript_path=""

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

# Last assistant "turn" = the trailing run of assistant messages after the
# last user message. Collect their tool_use names and text blocks.
turn=$(jq -c 'select(.type == "assistant" or .type == "user")' "$transcript_path" 2>/dev/null) || exit 0

last_turn=$(printf '%s\n' "$turn" | awk '
  /"type":"user"/ { buf = ""; next }
  { buf = buf $0 ORS }
  END { printf "%s", buf }
')

[ -z "$last_turn" ] && exit 0

edited=$(printf '%s' "$last_turn" | jq -r --arg pat "$EDIT_TOOLS_PATTERN" '
  select(.message.content != null) | .message.content[]?
  | select(.type == "tool_use" and (.name | test($pat)))
  | .name
' 2>/dev/null | head -n1) || edited=""

[ -z "$edited" ] && exit 0

gate_reported=$(printf '%s' "$last_turn" | jq -r --arg pat "$GATE_LINE_PATTERN" '
  select(.message.content != null) | .message.content[]?
  | select(.type == "text" and (.text | test($pat)))
  | .type
' 2>/dev/null | head -n1) || gate_reported=""

[ -n "$gate_reported" ] && exit 0

jq -n --arg ctx "$NUDGE_MESSAGE" \
  '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $ctx}}'

exit 0
