#!/usr/bin/env bash
# hooks/check-plan-contract.sh — Claude PreToolUse hook (matcher: ExitPlanMode)
#
# Reads the hook payload from stdin, extracts .tool_input.plan, and verifies
# the plan-mode-contract hand-off brief is present (see persona/plan-mode-contract.md).
# A plan missing required sections is denied with the list of what's missing,
# so the model can add them and exit plan mode again.
#
# Deterministic, jq-based, no LLM calls. Always exits 0 (Claude reads the JSON
# decision; a non-zero exit would surface as a hook error instead).
set -euo pipefail

payload=$(cat)
plan=$(printf '%s' "$payload" | jq -r '.tool_input.plan // ""' 2>/dev/null) || plan=""

missing=()

printf '%s' "$plan" | grep -qiE 'intent gate:' || missing+=("Intent Gate:")
printf '%s' "$plan" | grep -qiE '(size estimate|slice count|slices?)[^0-9]*[0-9]' || missing+=("size estimate / slice count (with a number)")
{ printf '%s' "$plan" | grep -qiE 'decision' && printf '%s' "$plan" | grep -qiE 'option'; } || missing+=("decisions with options")
printf '%s' "$plan" | grep -qiE 'acceptance criteria' || missing+=("acceptance criteria")

if [ "${#missing[@]}" -eq 0 ]; then
  exit 0
fi

list=$(IFS=', '; printf '%s' "${missing[*]}")
reason="Plan missing required sections: ${list}. Add them, then exit plan mode again."

jq -n --arg reason "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'

exit 0
