#!/usr/bin/env bash
# lib/clis.sh — update-clis phase: update all 4 AI CLI binaries
[ "${_CLIS_SH_LOADED:-}" = "1" ] && return 0
_CLIS_SH_LOADED=1

phase_update_clis() {
  log_start "update-clis"

  if command -v claude >/dev/null 2>&1; then
    run claude update
  else
    printf '[skip] claude not installed\n'
  fi

  if command -v codex >/dev/null 2>&1; then
    run codex update
  else
    printf '[skip] codex not installed\n'
  fi

  if command -v opencode >/dev/null 2>&1; then
    run opencode upgrade
  else
    printf '[skip] opencode not installed\n'
  fi

  if command -v gentle-ai >/dev/null 2>&1; then
    run gentle-ai upgrade
  else
    printf '[skip] gentle-ai not installed\n'
  fi

  log_finish "update-clis"
}
