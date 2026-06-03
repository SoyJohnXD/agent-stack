#!/usr/bin/env bash
# lib/persona.sh — persona phase: upsert Gentleman-CO override into the 3 agent configs
[ "${_PERSONA_SH_LOADED:-}" = "1" ] && return 0
_PERSONA_SH_LOADED=1

# Source of truth resolved relative to repo root (mirrors MANIFEST_FILE pattern in overlay.sh/codex.sh).
# Overridable via env so tests can point at a fixture without touching the real file.
: "${PERSONA_SRC:=$(dirname "$(dirname "${BASH_SOURCE[0]}")")/persona/gentleman-co.md}"

PERSONA_START='<!-- persona-co:start -->'
PERSONA_END='<!-- persona-co:end -->'

# ---------------------------------------------------------------------------
# persona_targets — emit the 3 HOME-relative destination paths, one per line
# ---------------------------------------------------------------------------
persona_targets() {
  printf '%s\n' \
    "$HOME/.claude/CLAUDE.md" \
    "$HOME/.codex/AGENTS.override.md" \
    "$HOME/.config/opencode/AGENTS.md"
}

# ---------------------------------------------------------------------------
# upsert_block_by_markers <target_file> <start_marker> <end_marker> <block_file>
#
# Replaces the start→end span (inclusive) with block_file content verbatim,
# or appends block_file at EOF when no markers are present.
# Write is atomic: temp file in same dir + mv.
# ---------------------------------------------------------------------------
upsert_block_by_markers() {
  local target="$1"
  local start="$2"
  local end="$3"
  local block="$4"
  local dir tmp

  dir=$(dirname "$target")
  tmp=$(mktemp "$dir/.persona-co.XXXXXX")

  # Normalize: ensure target ends with a newline so the append branch starts cleanly.
  # Only matters when the file is non-empty and lacks a trailing newline; harmless otherwise.
  if [ -s "$target" ] && [ -n "$(tail -c1 "$target")" ]; then
    cp "$target" "$tmp"
    printf '\n' >> "$tmp"
    mv "$tmp" "$target"
    tmp=$(mktemp "$dir/.persona-co.XXXXXX")
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
}

# ---------------------------------------------------------------------------
# write_persona_block <target_file>
#
# DRY_RUN gate: log intended action and return without writing.
# Otherwise: ensure parent dir + file exist, then upsert.
# ---------------------------------------------------------------------------
write_persona_block() {
  local target="$1"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '[dry-run] would upsert persona-co block into %s\n' "$target"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  [ -e "$target" ] || : > "$target"

  upsert_block_by_markers "$target" "$PERSONA_START" "$PERSONA_END" "$PERSONA_SRC"
}

# ---------------------------------------------------------------------------
# phase_persona — public entry point called by the dispatcher / run_sync
# ---------------------------------------------------------------------------
phase_persona() {
  log_start "persona"

  local target
  while IFS= read -r target; do
    write_persona_block "$target"
  done < <(persona_targets)

  log_finish "persona"
}
