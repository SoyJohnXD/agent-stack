#!/usr/bin/env bash
# lib/clis.sh — update-clis phase: update all 4 AI CLI binaries
[ "${_CLIS_SH_LOADED:-}" = "1" ] && return 0
_CLIS_SH_LOADED=1

phase_update_clis() {
  log_start "update-clis"
  run claude update
  run codex update
  run opencode upgrade
  run gentle-ai upgrade
  log_finish "update-clis"
}
