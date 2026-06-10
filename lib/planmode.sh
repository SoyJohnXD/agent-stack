#!/usr/bin/env bash
# lib/planmode.sh — planmode phase: upsert plan-mode/serialization/gate-wiring
# blocks into the 3 agent configs
[ "${_PLANMODE_SH_LOADED:-}" = "1" ] && return 0
_PLANMODE_SH_LOADED=1

# Sources of truth resolved relative to repo root (mirrors persona.sh / PERSONA_SRC).
# Overridable via env so tests can point at fixtures without touching the real files.
_PLANMODE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/persona"
: "${PLANMODE_SRC:=$_PLANMODE_DIR/plan-mode-contract.md}"
: "${SERIALIZATION_SRC:=$_PLANMODE_DIR/serialization.md}"
: "${GATE_WIRING_SRC:=$_PLANMODE_DIR/gate-wiring.md}"

PLANMODE_START='<!-- plan-mode:start -->'
PLANMODE_END='<!-- plan-mode:end -->'

SERIALIZATION_START='<!-- serialization:start -->'
SERIALIZATION_END='<!-- serialization:end -->'

GATE_WIRING_START='<!-- gate-wiring:start -->'
GATE_WIRING_END='<!-- gate-wiring:end -->'

# ---------------------------------------------------------------------------
# planmode_targets — emit the 3 HOME-relative destination paths, one per line
# (same targets as persona_targets)
# ---------------------------------------------------------------------------
planmode_targets() {
  printf '%s\n' \
    "$HOME/.claude/CLAUDE.md" \
    "$HOME/.codex/AGENTS.override.md" \
    "$HOME/.config/opencode/AGENTS.md"
}

# ---------------------------------------------------------------------------
# phase_planmode — public entry point called by the dispatcher / run_sync
# ---------------------------------------------------------------------------
phase_planmode() {
  log_start "planmode"

  local target
  while IFS= read -r target; do
    write_managed_block "$target" "$PLANMODE_START" "$PLANMODE_END" "$PLANMODE_SRC"
    write_managed_block "$target" "$SERIALIZATION_START" "$SERIALIZATION_END" "$SERIALIZATION_SRC"
    write_managed_block "$target" "$GATE_WIRING_START" "$GATE_WIRING_END" "$GATE_WIRING_SRC"
  done < <(planmode_targets)

  log_finish "planmode"
}
