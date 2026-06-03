#!/usr/bin/env bash
# lib/gentle.sh — gentle phase: upgrade + sync gentle-ai
[ "${_GENTLE_SH_LOADED:-}" = "1" ] && return 0
_GENTLE_SH_LOADED=1

phase_gentle() {
  log_start "gentle"
  run gentle-ai upgrade
  run gentle-ai sync
  log_finish "gentle"
}
