#!/usr/bin/env bash
# lib/overlay.sh — overlay phase: pull clean-code-lab + install intent-overlay
[ "${_OVERLAY_SH_LOADED:-}" = "1" ] && return 0
_OVERLAY_SH_LOADED=1

# MANIFEST_FILE must be set by the entrypoint before sourcing
: "${MANIFEST_FILE:=$(dirname "$(dirname "${BASH_SOURCE[0]}")")/repos.manifest}"

phase_overlay() {
  log_start "overlay"

  local local_path remote branch
  while IFS='|' read -r _name local_path remote branch; do
    _name=$(printf '%s' "$_name" | tr -d ' ')
    local_path=$(printf '%s' "$local_path" | tr -d ' ')
    remote=$(printf '%s' "$remote" | tr -d ' ')
    branch=$(printf '%s' "$branch" | tr -d ' ')
    [ "$_name" = "overlay" ] && break
  done < <(parse_manifest "$MANIFEST_FILE")

  ensure_repo "$local_path" "$remote" "$branch"

  local overlay_script="$local_path/overlay/intent-overlay"
  ensure_symlink "$overlay_script" "$HOME/.local/bin/intent-overlay"

  if [ -f "$overlay_script" ]; then
    run "$overlay_script" install
  elif command -v intent-overlay >/dev/null 2>&1; then
    run intent-overlay install
  else
    printf '[skip] intent-overlay not found\n'
  fi

  log_finish "overlay"
}
