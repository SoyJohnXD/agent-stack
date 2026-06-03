#!/usr/bin/env bash
# Tests for lib/persona.sh
# Run: bash lib/persona.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# Create a throwaway HOME directory
new_home() {
  local h; h=$(mktemp -d); printf '%s' "$h"
}

# Write a persona-co block fixture to a temp file and export PERSONA_SRC.
# Usage: make_src <inner_content>
# The temp file contains the full block including both markers.
make_src() {
  local content="$1"
  local src
  src=$(mktemp)
  printf '<!-- persona-co:start -->\n%s\n<!-- persona-co:end -->\n' "$content" > "$src"
  export PERSONA_SRC="$src"
  printf '%s' "$src"
}

# ---------------------------------------------------------------------------
# T1 — insert when absent
# ---------------------------------------------------------------------------
T1_HOME=$(new_home)
T1_SRC=$(make_src "CONTENT-T1")
T1_DEST="$T1_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$T1_DEST")"
printf 'existing prose\n' > "$T1_DEST"

(
  export HOME="$T1_HOME" DRY_RUN=0 PERSONA_SRC="$T1_SRC"
  source "$HERE/common.sh"
  source "$HERE/persona.sh"
  phase_persona
) >/dev/null 2>&1

START_COUNT=$(grep -c '<!-- persona-co:start -->' "$T1_DEST" 2>/dev/null || echo 0)
[ "$START_COUNT" = "1" ] && pass "T1: block inserted (exactly one start marker)" || fail "T1: expected one start marker, got $START_COUNT"

if grep -q 'existing prose' "$T1_DEST" 2>/dev/null; then
  pass "T1: pre-existing content preserved"
else
  fail "T1: pre-existing content was lost"
fi

rm -rf "$T1_HOME"; rm -f "$T1_SRC"

# ---------------------------------------------------------------------------
# T2 — idempotent second run
# ---------------------------------------------------------------------------
T2_HOME=$(new_home)
T2_SRC=$(make_src "CONTENT-T2")
T2_DEST="$T2_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$T2_DEST")"
printf 'preamble\n' > "$T2_DEST"

(
  export HOME="$T2_HOME" DRY_RUN=0 PERSONA_SRC="$T2_SRC"
  source "$HERE/common.sh"
  source "$HERE/persona.sh"
  phase_persona
) >/dev/null 2>&1

cp "$T2_DEST" "${T2_DEST}.after_run1"

(
  export HOME="$T2_HOME" DRY_RUN=0 PERSONA_SRC="$T2_SRC"
  source "$HERE/common.sh"
  source "$HERE/persona.sh"
  phase_persona
) >/dev/null 2>&1

if cmp -s "${T2_DEST}.after_run1" "$T2_DEST"; then
  pass "T2: second run is idempotent (file byte-identical)"
else
  fail "T2: file changed between run 1 and run 2"
fi

COUNT_T2=$(grep -c '<!-- persona-co:start -->' "$T2_DEST" 2>/dev/null || echo 0)
[ "$COUNT_T2" = "1" ] && pass "T2: exactly one block after two runs" || fail "T2: expected one start marker, got $COUNT_T2"

rm -rf "$T2_HOME"; rm -f "$T2_SRC"

# ---------------------------------------------------------------------------
# T3 — replace in place
# ---------------------------------------------------------------------------
T3_HOME=$(new_home)
T3_SRC=$(make_src "NEW-CONTENT-T3")
T3_DEST="$T3_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$T3_DEST")"
printf 'HEAD\n<!-- persona-co:start -->\nOLD\n<!-- persona-co:end -->\nTAIL\n' > "$T3_DEST"

(
  export HOME="$T3_HOME" DRY_RUN=0 PERSONA_SRC="$T3_SRC"
  source "$HERE/common.sh"
  source "$HERE/persona.sh"
  phase_persona
) >/dev/null 2>&1

COUNT_T3=$(grep -c '<!-- persona-co:start -->' "$T3_DEST" 2>/dev/null || echo 0)
[ "$COUNT_T3" = "1" ] && pass "T3: exactly one start marker after replace" || fail "T3: expected one start marker, got $COUNT_T3"

if grep -q 'NEW-CONTENT-T3' "$T3_DEST" 2>/dev/null; then
  pass "T3: new block content present"
else
  fail "T3: new block content missing"
fi

if ! grep -q '^OLD$' "$T3_DEST" 2>/dev/null; then
  pass "T3: old block content removed"
else
  fail "T3: old block content still present"
fi

if grep -q '^HEAD$' "$T3_DEST" && grep -q '^TAIL$' "$T3_DEST"; then
  pass "T3: content outside markers preserved (HEAD and TAIL intact)"
else
  fail "T3: content outside markers was lost (HEAD/TAIL missing)"
fi

rm -rf "$T3_HOME"; rm -f "$T3_SRC"

# ---------------------------------------------------------------------------
# T4 — dry-run: no file mutation
# ---------------------------------------------------------------------------
T4_HOME=$(new_home)
T4_SRC=$(make_src "CONTENT-T4")
# Intentionally do NOT create any destination files — they must remain absent

T4_OUT=$(
  export HOME="$T4_HOME" DRY_RUN=1 PERSONA_SRC="$T4_SRC"
  source "$HERE/common.sh"
  source "$HERE/persona.sh"
  phase_persona
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

rm -rf "$T4_HOME"; rm -f "$T4_SRC"

# ---------------------------------------------------------------------------
# T5 — no-touch gentle-ai markers
# ---------------------------------------------------------------------------
T5_HOME=$(new_home)
T5_SRC=$(make_src "NEW-CONTENT-T5")
T5_DEST="$T5_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$T5_DEST")"
cat > "$T5_DEST" <<'ENDOFFILE'
preamble line
<!-- gentle-ai:persona -->
gentle-ai persona content line 1
gentle-ai persona content line 2
<!-- /gentle-ai:persona -->
middle line
<!-- persona-co:start -->
OLD-PERSONA-CO
<!-- persona-co:end -->
trailing line
ENDOFFILE

# Snapshot the gentle-ai block
GENTLE_BEFORE=$(awk '/<!-- gentle-ai:persona -->/{found=1} found{print} /<!-- \/gentle-ai:persona -->/{found=0}' "$T5_DEST")

(
  export HOME="$T5_HOME" DRY_RUN=0 PERSONA_SRC="$T5_SRC"
  source "$HERE/common.sh"
  source "$HERE/persona.sh"
  phase_persona
) >/dev/null 2>&1

GENTLE_AFTER=$(awk '/<!-- gentle-ai:persona -->/{found=1} found{print} /<!-- \/gentle-ai:persona -->/{found=0}' "$T5_DEST")

if [ "$GENTLE_BEFORE" = "$GENTLE_AFTER" ]; then
  pass "T5: gentle-ai:persona block unchanged after upsert"
else
  fail "T5: gentle-ai:persona block was modified (should be untouched)"
fi

if grep -q 'NEW-CONTENT-T5' "$T5_DEST" 2>/dev/null; then
  pass "T5: persona-co block updated with new content"
else
  fail "T5: persona-co block was not updated"
fi

rm -rf "$T5_HOME"; rm -f "$T5_SRC"

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
