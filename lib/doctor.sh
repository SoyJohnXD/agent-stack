#!/usr/bin/env bash
# lib/doctor.sh — doctor phase: aggregated health report
[ "${_DOCTOR_SH_LOADED:-}" = "1" ] && return 0
_DOCTOR_SH_LOADED=1

# check_tool <name> <command...> [optional]
# Runs the command; records pass/fail. When optional=true, a failure is reported but does not set exit failure.
_doctor_fails=0

_check() {
  local label="$1"
  local optional="${2:-false}"
  shift 2
  local out exit_code
  out=$("$@" 2>&1) && exit_code=0 || exit_code=$?

  if [ "$exit_code" = "0" ]; then
    printf '  [PASS] %s\n' "$label"
  else
    printf '  [FAIL] %s\n' "$label"
    if [ "$optional" = "false" ]; then
      _doctor_fails=$((_doctor_fails + 1))
    fi
  fi
}

phase_doctor() {
  log_start "doctor"
  _doctor_fails=0

  printf '\n=== Agent Stack Health Report ===\n\n'

  printf '%s\n' "-- Overlay --"
  _check "intent-overlay doctor"  "false" intent-overlay doctor

  printf '\n%s\n' "-- Codex MCP --"
  _check "codex-sdd-sync --mcp-audit" "false" codex-sdd-sync --mcp-audit

  printf '\n%s\n' "-- CLI versions --"
  _check "claude version"     "false" claude --version
  _check "codex version"      "false" codex --version
  _check "opencode version"   "false" opencode --version
  _check "gentle-ai version"  "false" gentle-ai --version
  _check "git version"        "false" git --version
  _check "gum version"        "true"  gum --version

  printf '\n================================\n'

  if [ "$_doctor_fails" -eq 0 ]; then
    printf 'All required checks passed.\n'
  else
    printf '%d required check(s) failed.\n' "$_doctor_fails"
  fi

  log_finish "doctor"

  return "$_doctor_fails"
}
