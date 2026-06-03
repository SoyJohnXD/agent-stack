#!/usr/bin/env bash
# lib/codex.sh — codex phase: pull codex repo + install + mcp-audit
[ "${_CODEX_SH_LOADED:-}" = "1" ] && return 0
_CODEX_SH_LOADED=1

# MANIFEST_FILE must be set by the entrypoint before sourcing
: "${MANIFEST_FILE:=$(dirname "$(dirname "${BASH_SOURCE[0]}")")/repos.manifest}"

phase_codex() {
  log_start "codex"

  local local_path remote branch
  while IFS='|' read -r _name local_path remote branch; do
    _name=$(printf '%s' "$_name" | tr -d ' ')
    local_path=$(printf '%s' "$local_path" | tr -d ' ')
    remote=$(printf '%s' "$remote" | tr -d ' ')
    branch=$(printf '%s' "$branch" | tr -d ' ')
    [ "$_name" = "codex" ] && break
  done < <(parse_manifest "$MANIFEST_FILE")

  ensure_repo "$local_path" "$remote" "$branch"
  run bash "$local_path/install.sh"
  run codex-sdd-sync --mcp-audit
  log_finish "codex"
}
