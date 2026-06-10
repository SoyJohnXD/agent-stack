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

# _check_duplicate_binaries
# Warn-only: for each known binary name, if a copy exists in both
# $HOME/.local/bin and $HOME/go/bin, print their versions and suggest
# removing the $HOME/go/bin copy (agent-stack's canonical install target
# is $HOME/.local/bin). Never increments _doctor_fails.
_check_duplicate_binaries() {
  local name local_path go_path local_version go_version

  for name in gentle-ai engram; do
    local_path="$HOME/.local/bin/$name"
    go_path="$HOME/go/bin/$name"

    if [ -x "$local_path" ] && [ -x "$go_path" ]; then
      local_version=$("$local_path" --version 2>&1) || local_version="(unknown version)"
      go_version=$("$go_path" --version 2>&1) || go_version="(unknown version)"

      printf '  [WARN] duplicate binary: %s\n' "$name"
      printf '         %s -> %s\n' "$local_path" "$local_version"
      printf '         %s -> %s\n' "$go_path" "$go_version"
      printf '         suggested: rm "%s"\n' "$go_path"
    fi
  done
}

# _check_path_duplicates
# Warn-only: scan ~/.bashrc for `PATH=` assignment lines and detect any
# directory that is added to PATH more than once (e.g. re-running an
# installer keeps prepending the same dir). Suggests an idempotency guard
# so PATH doesn't keep growing on every new shell.
# Never increments _doctor_fails.
_check_path_duplicates() {
  local bashrc="$HOME/.bashrc"
  [ -f "$bashrc" ] || return 0

  local line dir dirs_seen=() dirs_warned=() seen warned

  while IFS= read -r line; do
    case "$line" in
      [[:space:]]*'#'*|'#'*) continue ;;
    esac
    case "$line" in
      *PATH=*) ;;
      *) continue ;;
    esac

    while [[ "$line" =~ \$\{?HOME\}?(/[A-Za-z0-9._/-]*)?|~(/[A-Za-z0-9._/-]*)? ]]; do
      dir="${BASH_REMATCH[0]}"
      line="${line/$dir/}"

      [ "$dir" = '$HOME' ] || [ "$dir" = '~' ] && continue

      seen=0
      for d in "${dirs_seen[@]+"${dirs_seen[@]}"}"; do
        [ "$d" = "$dir" ] && seen=1 && break
      done

      if [ "$seen" = "1" ]; then
        warned=0
        for d in "${dirs_warned[@]+"${dirs_warned[@]}"}"; do
          [ "$d" = "$dir" ] && warned=1 && break
        done
        if [ "$warned" = "0" ]; then
          printf '  [WARN] %s adds %s to PATH more than once\n' "$bashrc" "$dir"
          printf '         suggested idempotency guard:\n'
          printf '           case ":$PATH:" in\n'
          printf '             *":%s:"*) ;;\n' "$dir"
          printf '             *) export PATH="%s:$PATH" ;;\n' "$dir"
          printf '           esac\n'
          dirs_warned+=("$dir")
        fi
      else
        dirs_seen+=("$dir")
      fi
    done
  done < "$bashrc"
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

  printf '\n%s\n' "-- Environment --"
  _check_duplicate_binaries
  _check_path_duplicates

  printf '\n================================\n'

  if [ "$_doctor_fails" -eq 0 ]; then
    printf 'All required checks passed.\n'
  else
    printf '%d required check(s) failed.\n' "$_doctor_fails"
  fi

  log_finish "doctor"

  return "$_doctor_fails"
}
