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
# phase_persona — public entry point called by the dispatcher / run_sync
# ---------------------------------------------------------------------------
phase_persona() {
  log_start "persona"

  local target
  while IFS= read -r target; do
    write_managed_block "$target" "$PERSONA_START" "$PERSONA_END" "$PERSONA_SRC"
  done < <(persona_targets)

  log_finish "persona"
}
