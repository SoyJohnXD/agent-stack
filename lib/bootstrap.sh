#!/usr/bin/env bash
# lib/bootstrap.sh — delegator to the standalone bootstrap.sh
# Source this file; do not execute directly.
[ "${_BOOTSTRAP_SH_LOADED:-}" = "1" ] && return 0
_BOOTSTRAP_SH_LOADED=1

# HERE resolves to the directory containing this file (lib/)
_BOOTSTRAP_LIB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

phase_bootstrap() {
  # Forward DRY_RUN and ASSUME_YES (already exported by entrypoint).
  # Delegate all logic to the standalone bootstrap.sh at repo root.
  "$_BOOTSTRAP_LIB_HERE/../bootstrap.sh" "$@"
}
