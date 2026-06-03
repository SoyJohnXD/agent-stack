#!/usr/bin/env bash
# lib/common.sh — shared seam: logging, dry-run gate, manifest parsing, repo management
# Source this file; do not execute directly.
# Guard against re-sourcing.
[ "${_COMMON_SH_LOADED:-}" = "1" ] && return 0
_COMMON_SH_LOADED=1

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log_start() {
  local action="$1"
  printf '\n>>> START: %s\n' "$action"
}

log_finish() {
  local action="$1"
  printf '<<< DONE: %s\n' "$action"
}

# ---------------------------------------------------------------------------
# Dry-run gate — SINGLE mutation point
# All commands that mutate machine state MUST go through run().
# Pure reads (existence checks, version queries) bypass it.
# ---------------------------------------------------------------------------

# DRY_RUN defaults to 0 when not set
: "${DRY_RUN:=0}"

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

# ---------------------------------------------------------------------------
# Path utilities
# ---------------------------------------------------------------------------

expand_path() {
  local path="$1"
  case "$path" in
    "~/"*) printf '%s' "${HOME}/${path#\~/}" ;;
    "~")  printf '%s' "${HOME}" ;;
    *)    printf '%s' "$path" ;;
  esac
}

# ---------------------------------------------------------------------------
# Manifest parsing
# parse_manifest <manifest_file>
# Reads repos.manifest, skips blank lines and # comments.
# Outputs one line per entry: name|local_path|remote|branch (pipe-separated, trimmed).
# ---------------------------------------------------------------------------

parse_manifest() {
  local manifest_file="$1"
  local line name local_path remote branch

  while IFS= read -r line || [ -n "$line" ]; do
    # Skip blank lines and comment lines
    case "$line" in
      ''|'#'*) continue ;;
    esac

    IFS='|' read -r name local_path remote branch <<< "$line"

    # Trim leading/trailing whitespace from each field
    name=$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local_path=$(printf '%s' "$local_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    remote=$(printf '%s' "$remote" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    branch=$(printf '%s' "$branch" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Expand ~ in local_path
    local_path=$(expand_path "$local_path")

    printf '%s|%s|%s|%s\n' "$name" "$local_path" "$remote" "$branch"
  done < "$manifest_file"
}

# ---------------------------------------------------------------------------
# ensure_repo <local_path> <remote> <branch>
# Clones if absent; pulls if present. Always via run() so --dry-run is safe.
# ---------------------------------------------------------------------------

ensure_repo() {
  local local_path="$1"
  local remote="$2"
  local branch="$3"

  if [ -d "$local_path/.git" ] || { [ -d "$local_path" ] && git -C "$local_path" rev-parse --git-dir >/dev/null 2>&1; }; then
    run git -C "$local_path" pull origin "$branch"
  else
    run git clone --branch "$branch" "$remote" "$local_path"
  fi
}
