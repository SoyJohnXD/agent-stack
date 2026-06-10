#!/usr/bin/env bash
# hooks/skill-registry-refresh.sh — Claude UserPromptSubmit hook
#
# Refreshes the per-project skill registry. On failure, surfaces a WARNING via
# additionalContext instead of failing silently — gate-wiring (persona/gate-wiring.md)
# falls back to the canonical ~/.codex/skills paths when the registry is stale.
# Always exits 0.
set -euo pipefail

MAX_ERROR_LEN=200

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

if error=$(gentle-ai skill-registry refresh --quiet --no-gitignore --cwd "$project_dir" 2>&1); then
  exit 0
fi

short_error=$(printf '%s' "$error" | tr '\n' ' ' | cut -c "1-${MAX_ERROR_LEN}")
warning="WARNING: skill-registry refresh failed (${short_error}). Gate skills will use the canonical ~/.codex/skills fallback."

jq -n --arg ctx "$warning" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'

exit 0
