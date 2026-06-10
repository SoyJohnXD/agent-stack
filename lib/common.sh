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

# ---------------------------------------------------------------------------
# markers_balanced <target_file> <start_marker> <end_marker>
#
# Returns success when the target has zero start markers, or exactly one
# start marker paired with exactly one end marker. Any other combination
# (orphaned start, orphaned end, or duplicated markers) is unbalanced.
# ---------------------------------------------------------------------------
markers_balanced() {
  local target="$1"
  local start="$2"
  local end="$3"
  local start_count end_count

  start_count=$(grep -Fxc "$start" "$target" 2>/dev/null || true)
  end_count=$(grep -Fxc "$end" "$target" 2>/dev/null || true)

  [ "$start_count" = "0" ] && [ "$end_count" = "0" ] && return 0
  [ "$start_count" = "1" ] && [ "$end_count" = "1" ]
}

# ---------------------------------------------------------------------------
# upsert_block_by_markers <target_file> <start_marker> <end_marker> <block_file>
#
# Replaces the start->end span (inclusive) with block_file content verbatim,
# or appends block_file at EOF when no markers are present.
# Write is atomic: temp file in same dir + mv.
#
# Refuses to modify the file when the markers are unbalanced (e.g. an
# orphaned start marker without its matching end marker), since the awk
# pass would otherwise drop everything from the start marker to EOF.
# ---------------------------------------------------------------------------
upsert_block_by_markers() {
  local target="$1"
  local start="$2"
  local end="$3"
  local block="$4"
  local dir tmp

  if ! markers_balanced "$target" "$start" "$end"; then
    printf 'ERROR: %s has unbalanced managed-block markers (%s / %s); fix the file manually\n' \
      "$target" "$start" "$end" >&2
    return 1
  fi

  dir=$(dirname "$target")
  tmp=$(mktemp "$dir/.agent-stack-upsert.XXXXXX")
  trap 'rm -f "$tmp"' RETURN

  # Normalize: ensure target ends with a newline so the append branch starts cleanly.
  # Only matters when the file is non-empty and lacks a trailing newline; harmless otherwise.
  if [ -s "$target" ] && [ -n "$(tail -c1 "$target")" ]; then
    cp "$target" "$tmp"
    printf '\n' >> "$tmp"
    mv "$tmp" "$target"
    tmp=$(mktemp "$dir/.agent-stack-upsert.XXXXXX")
    trap 'rm -f "$tmp"' RETURN
  fi

  awk \
    -v start="$start" \
    -v end="$end" \
    -v blockfile="$block" \
    '
    BEGIN { inblock = 0; replaced = 0 }

    $0 == start {
      # Emit the full block file (markers included) then skip old span.
      while ((getline line < blockfile) > 0) print line
      close(blockfile)
      inblock  = 1
      replaced = 1
      next
    }

    inblock && $0 == end { inblock = 0; next }   # consume end marker of old block
    inblock              { next }                 # consume body of old block

    { print }                                     # passthrough everything else

    END {
      if (!replaced) {
        # No markers found — append block at EOF.
        while ((getline line < blockfile) > 0) print line
        close(blockfile)
      }
    }
    ' "$target" > "$tmp"

  mv "$tmp" "$target"
  trap - RETURN
}

# ---------------------------------------------------------------------------
# ensure_symlink <target> <link>
# Creates or updates a symlink. Idempotent. Warns and skips when <link>
# exists and is not a symlink (never overwrites a real file/dir).
# ---------------------------------------------------------------------------
ensure_symlink() {
  local target="$1"
  local link="$2"
  local link_dir; link_dir="$(dirname "$link")"

  run mkdir -p "$link_dir"

  if [ -L "$link" ]; then
    run ln -sf "$target" "$link"
  elif [ -e "$link" ]; then
    printf 'warning: %s exists and is not a symlink; skipping\n' "$link"
  else
    run ln -s "$target" "$link"
  fi
}

# ---------------------------------------------------------------------------
# write_managed_block <target_file> <start_marker> <end_marker> <src_file>
#
# DRY_RUN gate: log intended action and return without writing.
# Otherwise: ensure parent dir + file exist, then upsert.
# ---------------------------------------------------------------------------
write_managed_block() {
  local target="$1"
  local start="$2"
  local end="$3"
  local src="$4"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '[dry-run] would upsert %s..%s block into %s\n' "$start" "$end" "$target"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  [ -e "$target" ] || : > "$target"

  upsert_block_by_markers "$target" "$start" "$end" "$src"
}
