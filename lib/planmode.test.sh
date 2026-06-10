#!/usr/bin/env bash
# Tests for lib/planmode.sh
# Run: bash lib/planmode.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# Create a throwaway HOME directory
new_home() {
  local h; h=$(mktemp -d); printf '%s' "$h"
}

# Write a block fixture (markers included) to a temp file.
# Usage: make_src <start_marker> <end_marker> <inner_content>
make_src() {
  local start="$1" end="$2" content="$3"
  local src
  src=$(mktemp)
  printf '%s\n%s\n%s\n' "$start" "$content" "$end" > "$src"
  printf '%s' "$src"
}

export_fixture_env() {
  local home="$1"
  export HOME="$home" DRY_RUN=0
  export PLANMODE_SRC SERIALIZATION_SRC GATE_WIRING_SRC
}

# ---------------------------------------------------------------------------
# T1 — insert all 3 blocks when absent
# ---------------------------------------------------------------------------
T1_HOME=$(new_home)
PLANMODE_SRC=$(make_src '<!-- plan-mode:start -->' '<!-- plan-mode:end -->' "PLANMODE-T1")
SERIALIZATION_SRC=$(make_src '<!-- serialization:start -->' '<!-- serialization:end -->' "SERIALIZATION-T1")
GATE_WIRING_SRC=$(make_src '<!-- gate-wiring:start -->' '<!-- gate-wiring:end -->' "GATEWIRING-T1")

(
  export_fixture_env "$T1_HOME"
  PLANMODE_SRC="$PLANMODE_SRC" SERIALIZATION_SRC="$SERIALIZATION_SRC" GATE_WIRING_SRC="$GATE_WIRING_SRC"
  source "$HERE/common.sh"
  source "$HERE/planmode.sh"
  phase_planmode
) >/dev/null 2>&1

for target in "$T1_HOME/.claude/CLAUDE.md" "$T1_HOME/.codex/AGENTS.override.md" "$T1_HOME/.config/opencode/AGENTS.md"; do
  PM=$(grep -c '<!-- plan-mode:start -->' "$target" 2>/dev/null || echo 0)
  SR=$(grep -c '<!-- serialization:start -->' "$target" 2>/dev/null || echo 0)
  GW=$(grep -c '<!-- gate-wiring:start -->' "$target" 2>/dev/null || echo 0)
  if [ "$PM" = "1" ] && [ "$SR" = "1" ] && [ "$GW" = "1" ]; then
    pass "T1: all 3 blocks inserted into $target"
  else
    fail "T1: expected one of each marker in $target, got plan-mode=$PM serialization=$SR gate-wiring=$GW"
  fi

  if grep -q 'PLANMODE-T1' "$target" && grep -q 'SERIALIZATION-T1' "$target" && grep -q 'GATEWIRING-T1' "$target"; then
    pass "T1: block content present in $target"
  else
    fail "T1: block content missing in $target"
  fi
done

rm -rf "$T1_HOME"; rm -f "$PLANMODE_SRC" "$SERIALIZATION_SRC" "$GATE_WIRING_SRC"

# ---------------------------------------------------------------------------
# T2 — idempotent second run (byte-identical)
# ---------------------------------------------------------------------------
T2_HOME=$(new_home)
PLANMODE_SRC=$(make_src '<!-- plan-mode:start -->' '<!-- plan-mode:end -->' "PLANMODE-T2")
SERIALIZATION_SRC=$(make_src '<!-- serialization:start -->' '<!-- serialization:end -->' "SERIALIZATION-T2")
GATE_WIRING_SRC=$(make_src '<!-- gate-wiring:start -->' '<!-- gate-wiring:end -->' "GATEWIRING-T2")
T2_DEST="$T2_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$T2_DEST")"
printf 'preamble\n' > "$T2_DEST"

(
  export_fixture_env "$T2_HOME"
  PLANMODE_SRC="$PLANMODE_SRC" SERIALIZATION_SRC="$SERIALIZATION_SRC" GATE_WIRING_SRC="$GATE_WIRING_SRC"
  source "$HERE/common.sh"
  source "$HERE/planmode.sh"
  phase_planmode
) >/dev/null 2>&1

cp "$T2_DEST" "${T2_DEST}.after_run1"

(
  export_fixture_env "$T2_HOME"
  PLANMODE_SRC="$PLANMODE_SRC" SERIALIZATION_SRC="$SERIALIZATION_SRC" GATE_WIRING_SRC="$GATE_WIRING_SRC"
  source "$HERE/common.sh"
  source "$HERE/planmode.sh"
  phase_planmode
) >/dev/null 2>&1

if cmp -s "${T2_DEST}.after_run1" "$T2_DEST"; then
  pass "T2: second run is idempotent (file byte-identical)"
else
  fail "T2: file changed between run 1 and run 2"
fi

rm -rf "$T2_HOME"; rm -f "$PLANMODE_SRC" "$SERIALIZATION_SRC" "$GATE_WIRING_SRC"

# ---------------------------------------------------------------------------
# T3 — replace in place
# ---------------------------------------------------------------------------
T3_HOME=$(new_home)
PLANMODE_SRC=$(make_src '<!-- plan-mode:start -->' '<!-- plan-mode:end -->' "NEW-PLANMODE-T3")
SERIALIZATION_SRC=$(make_src '<!-- serialization:start -->' '<!-- serialization:end -->' "NEW-SERIALIZATION-T3")
GATE_WIRING_SRC=$(make_src '<!-- gate-wiring:start -->' '<!-- gate-wiring:end -->' "NEW-GATEWIRING-T3")
T3_DEST="$T3_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$T3_DEST")"
printf 'HEAD\n<!-- plan-mode:start -->\nOLD-PLANMODE\n<!-- plan-mode:end -->\nMID\n<!-- gate-wiring:start -->\nOLD-GATEWIRING\n<!-- gate-wiring:end -->\nTAIL\n' > "$T3_DEST"

(
  export_fixture_env "$T3_HOME"
  PLANMODE_SRC="$PLANMODE_SRC" SERIALIZATION_SRC="$SERIALIZATION_SRC" GATE_WIRING_SRC="$GATE_WIRING_SRC"
  source "$HERE/common.sh"
  source "$HERE/planmode.sh"
  phase_planmode
) >/dev/null 2>&1

if grep -q 'NEW-PLANMODE-T3' "$T3_DEST" && grep -q 'NEW-GATEWIRING-T3' "$T3_DEST"; then
  pass "T3: existing blocks replaced with new content"
else
  fail "T3: existing blocks were not replaced"
fi

if ! grep -q '^OLD-PLANMODE$' "$T3_DEST" && ! grep -q '^OLD-GATEWIRING$' "$T3_DEST"; then
  pass "T3: old block content removed"
else
  fail "T3: old block content still present"
fi

if grep -q '^HEAD$' "$T3_DEST" && grep -q '^MID$' "$T3_DEST" && grep -q '^TAIL$' "$T3_DEST"; then
  pass "T3: content outside markers preserved (HEAD/MID/TAIL intact)"
else
  fail "T3: content outside markers was lost"
fi

if grep -q 'NEW-SERIALIZATION-T3' "$T3_DEST"; then
  pass "T3: serialization block appended (was previously absent)"
else
  fail "T3: serialization block missing after run"
fi

rm -rf "$T3_HOME"; rm -f "$PLANMODE_SRC" "$SERIALIZATION_SRC" "$GATE_WIRING_SRC"

# ---------------------------------------------------------------------------
# T4 — dry-run: no file mutation
# ---------------------------------------------------------------------------
T4_HOME=$(new_home)
PLANMODE_SRC=$(make_src '<!-- plan-mode:start -->' '<!-- plan-mode:end -->' "PLANMODE-T4")
SERIALIZATION_SRC=$(make_src '<!-- serialization:start -->' '<!-- serialization:end -->' "SERIALIZATION-T4")
GATE_WIRING_SRC=$(make_src '<!-- gate-wiring:start -->' '<!-- gate-wiring:end -->' "GATEWIRING-T4")

T4_OUT=$(
  export HOME="$T4_HOME" DRY_RUN=1
  export PLANMODE_SRC SERIALIZATION_SRC GATE_WIRING_SRC
  source "$HERE/common.sh"
  source "$HERE/planmode.sh"
  phase_planmode
) 2>&1

T4_DEST_CLAUDE="$T4_HOME/.claude/CLAUDE.md"
T4_DEST_CODEX="$T4_HOME/.codex/AGENTS.override.md"
T4_DEST_OPENCODE="$T4_HOME/.config/opencode/AGENTS.md"

if [ ! -e "$T4_DEST_CLAUDE" ] && [ ! -e "$T4_DEST_CODEX" ] && [ ! -e "$T4_DEST_OPENCODE" ]; then
  pass "T4: no destination files created or modified in dry-run"
else
  fail "T4: dry-run should not create or modify destination files"
fi

case "$T4_OUT" in
  *"[dry-run]"*) pass "T4: dry-run log output present" ;;
  *) fail "T4: dry-run should produce [dry-run] log lines (got: $T4_OUT)" ;;
esac

rm -rf "$T4_HOME"; rm -f "$PLANMODE_SRC" "$SERIALIZATION_SRC" "$GATE_WIRING_SRC"

# ---------------------------------------------------------------------------
# T5 — no-touch foreign (gentle-ai) markers
# ---------------------------------------------------------------------------
T5_HOME=$(new_home)
PLANMODE_SRC=$(make_src '<!-- plan-mode:start -->' '<!-- plan-mode:end -->' "NEW-PLANMODE-T5")
SERIALIZATION_SRC=$(make_src '<!-- serialization:start -->' '<!-- serialization:end -->' "NEW-SERIALIZATION-T5")
GATE_WIRING_SRC=$(make_src '<!-- gate-wiring:start -->' '<!-- gate-wiring:end -->' "NEW-GATEWIRING-T5")
T5_DEST="$T5_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$T5_DEST")"
cat > "$T5_DEST" <<'ENDOFFILE'
preamble line
<!-- gentle-ai:sdd-orchestrator -->
gentle-ai sdd-orchestrator content line 1
gentle-ai sdd-orchestrator content line 2
<!-- /gentle-ai:sdd-orchestrator -->
middle line
<!-- plan-mode:start -->
OLD-PLANMODE
<!-- plan-mode:end -->
trailing line
ENDOFFILE

GENTLE_BEFORE=$(awk '/<!-- gentle-ai:sdd-orchestrator -->/{found=1} found{print} /<!-- \/gentle-ai:sdd-orchestrator -->/{found=0}' "$T5_DEST")

(
  export_fixture_env "$T5_HOME"
  PLANMODE_SRC="$PLANMODE_SRC" SERIALIZATION_SRC="$SERIALIZATION_SRC" GATE_WIRING_SRC="$GATE_WIRING_SRC"
  source "$HERE/common.sh"
  source "$HERE/planmode.sh"
  phase_planmode
) >/dev/null 2>&1

GENTLE_AFTER=$(awk '/<!-- gentle-ai:sdd-orchestrator -->/{found=1} found{print} /<!-- \/gentle-ai:sdd-orchestrator -->/{found=0}' "$T5_DEST")

if [ "$GENTLE_BEFORE" = "$GENTLE_AFTER" ]; then
  pass "T5: gentle-ai:sdd-orchestrator block unchanged after upsert"
else
  fail "T5: gentle-ai:sdd-orchestrator block was modified (should be untouched)"
fi

if grep -q 'NEW-PLANMODE-T5' "$T5_DEST" && grep -q 'NEW-SERIALIZATION-T5' "$T5_DEST" && grep -q 'NEW-GATEWIRING-T5' "$T5_DEST"; then
  pass "T5: all 3 blocks present after upsert"
else
  fail "T5: not all blocks present after upsert"
fi

rm -rf "$T5_HOME"; rm -f "$PLANMODE_SRC" "$SERIALIZATION_SRC" "$GATE_WIRING_SRC"

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
