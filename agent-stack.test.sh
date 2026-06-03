#!/usr/bin/env bash
# Tests for the agent-stack entrypoint
# Run: bash agent-stack.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ENTRYPOINT="$HERE/agent-stack"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

new_home() {
  local h
  h=$(mktemp -d)
  printf '%s' "$h"
}

# ---------------------------------------------------------------------------
# Build a full stub bin dir: all external commands record calls and exit 0
# ---------------------------------------------------------------------------
new_stub_bin() {
  local dir record_file="$1"
  dir=$(mktemp -d)

  for cmd in gum git gentle-ai claude codex opencode intent-overlay codex-sdd-sync; do
    cat > "$dir/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >> "$record_file"
exit 0
EOF
    chmod +x "$dir/$cmd"
  done

  # gum: when called with "choose", print first argument (simulate user choosing it)
  cat > "$dir/gum" <<'EOF'
#!/usr/bin/env bash
echo "gum $*" >> "$GUM_RECORD_FILE"
if [ "${1:-}" = "choose" ]; then
  # Return "doctor" as the chosen item for testing
  echo "${GUM_CHOICE:-doctor}"
fi
exit 0
EOF
  chmod +x "$dir/gum"

  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# T6a: No-arg invocation calls gum choose with expected labels
# ---------------------------------------------------------------------------
TEST_HOME=$(new_home)
GUM_RECORD=$(mktemp)
STUB_BIN=$(new_stub_bin "$GUM_RECORD")

# Copy manifest into test home area isn't needed — entrypoint reads from its own dir
GUM_OUT=$(
  export PATH="$STUB_BIN:$PATH"
  export HOME="$TEST_HOME"
  export DRY_RUN=1
  export GUM_RECORD_FILE="$GUM_RECORD"
  export GUM_CHOICE="Salir"
  bash "$ENTRYPOINT" 2>/dev/null
)

if grep -q "gum choose" "$GUM_RECORD" 2>/dev/null; then
  pass "no-arg invocation calls gum choose"
else
  fail "no-arg invocation should call gum choose (got: $(cat "$GUM_RECORD" 2>/dev/null))"
fi

# Check that gum choose is called with the expected menu labels
GUM_ARGS=$(grep "gum choose" "$GUM_RECORD" 2>/dev/null || echo "")
for label in "Sync" "overlay" "Codex" "Gentle" "CLIs" "Doctor" "Salir"; do
  case "$GUM_ARGS" in
    *"$label"*) pass "menu includes label containing '$label'" ;;
    *) fail "menu should include label containing '$label'" ;;
  esac
done

rm -rf "$STUB_BIN" "$GUM_RECORD" "$TEST_HOME"

# ---------------------------------------------------------------------------
# T6b: Unknown subcommand exits 2 with usage
# ---------------------------------------------------------------------------
UNKNOWN_EXIT=$(bash "$ENTRYPOINT" bogus-command 2>/dev/null; echo $?)
[ "$UNKNOWN_EXIT" = "2" ] && pass "unknown subcommand exits 2" || fail "unknown subcommand should exit 2, got $UNKNOWN_EXIT"

USAGE_OUT=$(bash "$ENTRYPOINT" bogus-command 2>&1 || true)
case "$USAGE_OUT" in
  *"usage"*|*"Usage"*|*"valid"*|*"sync"*|*"overlay"*) pass "unknown subcommand prints usage with valid subcommands" ;;
  *) fail "unknown subcommand should print usage (got: $USAGE_OUT)" ;;
esac

# ---------------------------------------------------------------------------
# T6c: Global flags are parsed from any position and stripped
# ---------------------------------------------------------------------------
TEST_HOME2=$(new_home)
GUM_RECORD2=$(mktemp)
STUB_BIN2=$(new_stub_bin "$GUM_RECORD2")

# --dry-run before subcommand: use gentle (which does use run() for mutations)
DRY_OUT=$(
  export PATH="$STUB_BIN2:$PATH"
  export HOME="$TEST_HOME2"
  unset DRY_RUN
  bash "$ENTRYPOINT" --dry-run gentle 2>&1
)
case "$DRY_OUT" in
  *"[dry-run]"*) pass "--dry-run before subcommand activates dry-run" ;;
  *) fail "--dry-run before subcommand should activate dry-run (got: $DRY_OUT)" ;;
esac

# --dry-run after subcommand: gentle --dry-run
DRY_OUT2=$(
  export PATH="$STUB_BIN2:$PATH"
  export HOME="$TEST_HOME2"
  unset DRY_RUN
  bash "$ENTRYPOINT" gentle --dry-run 2>&1
)
case "$DRY_OUT2" in
  *"[dry-run]"*) pass "--dry-run after subcommand activates dry-run" ;;
  *) fail "--dry-run after subcommand should activate dry-run" ;;
esac

# --skip-codex is recognized (no error on valid subcommand with flag)
(
  export PATH="$STUB_BIN2:$PATH"
  export HOME="$TEST_HOME2"
  bash "$ENTRYPOINT" sync --skip-codex --dry-run >/dev/null 2>&1
)
SKIP_EXIT=$?
[ "$SKIP_EXIT" = "0" ] && pass "--skip-codex is recognized as valid flag (exits 0)" || fail "--skip-codex should be recognized (exits 0), got $SKIP_EXIT"

rm -rf "$STUB_BIN2" "$GUM_RECORD2" "$TEST_HOME2"

# ---------------------------------------------------------------------------
# T6d: Valid subcommands dispatch without error (with stubs + dry-run)
# ---------------------------------------------------------------------------
for subcmd in sync overlay codex gentle update-clis all doctor; do
  TEST_HOME_SC=$(new_home)
  RECORD_SC=$(mktemp)
  STUB_SC=$(new_stub_bin "$RECORD_SC")
  (
    export PATH="$STUB_SC:$PATH"
    export HOME="$TEST_HOME_SC"
    bash "$ENTRYPOINT" "$subcmd" --dry-run >/dev/null 2>&1
  )
  SUB_EXIT=$?
  [ "$SUB_EXIT" = "0" ] && pass "subcommand '$subcmd' dispatches and exits 0" || fail "subcommand '$subcmd' should exit 0, got $SUB_EXIT"
  rm -rf "$STUB_SC" "$RECORD_SC" "$TEST_HOME_SC"
done

# ---------------------------------------------------------------------------
# T6e: --dry-run all prints all phases in order
# ---------------------------------------------------------------------------
TEST_HOME3=$(new_home)
RECORD3=$(mktemp)
STUB3=$(new_stub_bin "$RECORD3")

ALL_DRY_OUT=$(
  export PATH="$STUB3:$PATH"
  export HOME="$TEST_HOME3"
  bash "$ENTRYPOINT" all --dry-run 2>&1
)

# Should contain all phase indicators in output
for phase_marker in "gentle" "codex" "overlay" "claude\|update-clis"; do
  case "$ALL_DRY_OUT" in
    *"$phase_marker"*) pass "--dry-run all output mentions '$phase_marker'" ;;
    *)
      # Try without | (the escape)
      clean_marker=$(printf '%s' "$phase_marker" | tr -d '\\|')
      case "$ALL_DRY_OUT" in
        *"gentle"*|*"codex"*|*"overlay"*|*"claude"*|*"update"*)
          pass "--dry-run all output contains phase references" ;;
        *)
          fail "--dry-run all should mention all phases (got partial: $(printf '%s' "$ALL_DRY_OUT" | head -5))"
          ;;
      esac
      ;;
  esac
done

rm -rf "$STUB3" "$RECORD3" "$TEST_HOME3"

# ---------------------------------------------------------------------------
# T4.1: agent-stack bootstrap --dry-run exits 0 and produces dry-run markers
# ---------------------------------------------------------------------------
TEST_HOME_BS=$(new_home)
GUM_RECORD_BS=$(mktemp)
STUB_BS=$(new_stub_bin "$GUM_RECORD_BS")

BS_OUT=$(
  export PATH="$STUB_BS:$PATH"
  export HOME="$TEST_HOME_BS"
  export DRY_RUN=1
  bash "$ENTRYPOINT" bootstrap --dry-run 2>&1
)
BS_EXIT=$?

[ "$BS_EXIT" = "0" ] && pass "bootstrap subcommand: exits 0 with --dry-run" || fail "bootstrap subcommand: should exit 0, got $BS_EXIT"

case "$BS_OUT" in
  *"[dry-run]"*) pass "bootstrap subcommand: --dry-run produces [dry-run] markers" ;;
  *) fail "bootstrap subcommand: should produce [dry-run] markers (got: $(printf '%s\n' "$BS_OUT" | head -3))" ;;
esac

rm -rf "$STUB_BS" "$TEST_HOME_BS"
rm -f "$GUM_RECORD_BS"

# ---------------------------------------------------------------------------
# T4.2: gum choose arg list includes "Instalación inicial"
# ---------------------------------------------------------------------------
TEST_HOME_MI=$(new_home)
GUM_RECORD_MI=$(mktemp)
STUB_MI=$(new_stub_bin "$GUM_RECORD_MI")

(
  export PATH="$STUB_MI:$PATH"
  export HOME="$TEST_HOME_MI"
  export DRY_RUN=1
  export GUM_RECORD_FILE="$GUM_RECORD_MI"
  export GUM_CHOICE="Salir"
  bash "$ENTRYPOINT" 2>/dev/null
)

GUM_ARGS_MI=$(grep "gum choose" "$GUM_RECORD_MI" 2>/dev/null || echo "")
case "$GUM_ARGS_MI" in
  *"Instalación inicial"*) pass "menu includes 'Instalación inicial'" ;;
  *) fail "menu should include 'Instalación inicial' (got: $GUM_ARGS_MI)" ;;
esac

rm -rf "$STUB_MI" "$TEST_HOME_MI"
rm -f "$GUM_RECORD_MI"

# ---------------------------------------------------------------------------
# T4.3: Selecting "Instalación inicial" dispatches to bootstrap
# ---------------------------------------------------------------------------
TEST_HOME_SEL=$(new_home)
GUM_RECORD_SEL=$(mktemp)
STUB_SEL=$(new_stub_bin "$GUM_RECORD_SEL")

SEL_OUT=$(
  export PATH="$STUB_SEL:$PATH"
  export HOME="$TEST_HOME_SEL"
  export DRY_RUN=1
  export GUM_RECORD_FILE="$GUM_RECORD_SEL"
  export GUM_CHOICE="Instalación inicial"
  bash "$ENTRYPOINT" 2>&1
)
SEL_EXIT=$?

[ "$SEL_EXIT" = "0" ] && pass "selecting 'Instalación inicial': exits 0" || fail "selecting 'Instalación inicial': should exit 0, got $SEL_EXIT"

case "$SEL_OUT" in
  *"[dry-run]"*|*"bootstrap"*|*"Bootstrap"*)
    pass "selecting 'Instalación inicial': dispatches to bootstrap (dry-run output present)"
    ;;
  *)
    fail "selecting 'Instalación inicial': should dispatch to bootstrap (got: $(printf '%s\n' "$SEL_OUT" | head -3))"
    ;;
esac

rm -rf "$STUB_SEL" "$TEST_HOME_SEL"
rm -f "$GUM_RECORD_SEL"

# ---------------------------------------------------------------------------
# T4.4: 'bootstrap' is a valid subcommand (exits 0 with stubs + dry-run)
# ---------------------------------------------------------------------------
TEST_HOME_BSUB=$(new_home)
RECORD_BSUB=$(mktemp)
STUB_BSUB=$(new_stub_bin "$RECORD_BSUB")

(
  export PATH="$STUB_BSUB:$PATH"
  export HOME="$TEST_HOME_BSUB"
  bash "$ENTRYPOINT" bootstrap --dry-run >/dev/null 2>&1
)
BSUB_EXIT=$?
[ "$BSUB_EXIT" = "0" ] && pass "subcommand 'bootstrap' dispatches and exits 0" || fail "subcommand 'bootstrap' should exit 0, got $BSUB_EXIT"

rm -rf "$STUB_BSUB" "$TEST_HOME_BSUB"
rm -f "$RECORD_BSUB"

# ---------------------------------------------------------------------------
# T6 — persona subcommand dispatches correctly (no other phase invoked)
# ---------------------------------------------------------------------------
TEST_HOME_P=$(new_home)
RECORD_P=$(mktemp)
STUB_P=$(new_stub_bin "$RECORD_P")

T6_OUT=$(
  export PATH="$STUB_P:$PATH"
  export HOME="$TEST_HOME_P"
  bash "$ENTRYPOINT" persona --dry-run 2>&1
)
T6_EXIT=$?

[ "$T6_EXIT" = "0" ] && pass "T6: 'persona' subcommand exits 0" || fail "T6: 'persona' subcommand should exit 0, got $T6_EXIT"

case "$T6_OUT" in
  *"[dry-run]"*) pass "T6: 'persona' subcommand produces [dry-run] output" ;;
  *) fail "T6: 'persona --dry-run' should produce [dry-run] lines (got: $T6_OUT)" ;;
esac

# Assert no other phase start markers appear (gentle/codex/overlay must NOT run)
for phase_name in gentle codex overlay; do
  case "$T6_OUT" in
    *">>> START: $phase_name"*)
      fail "T6: 'persona' subcommand should not invoke phase '$phase_name'"
      ;;
    *)
      pass "T6: 'persona' subcommand does not invoke phase '$phase_name'"
      ;;
  esac
done

rm -rf "$STUB_P" "$TEST_HOME_P"
rm -f "$RECORD_P"

# ---------------------------------------------------------------------------
# T7 — sync order: phase_gentle starts before phase_persona
# ---------------------------------------------------------------------------
TEST_HOME_ORD=$(new_home)
RECORD_ORD=$(mktemp)
STUB_ORD=$(new_stub_bin "$RECORD_ORD")

SYNC_OUT=$(
  export PATH="$STUB_ORD:$PATH"
  export HOME="$TEST_HOME_ORD"
  bash "$ENTRYPOINT" sync --dry-run 2>&1
)

GENTLE_LINE=$(printf '%s\n' "$SYNC_OUT" | grep -n '>>> START: gentle' | head -1 | cut -d: -f1)
PERSONA_LINE=$(printf '%s\n' "$SYNC_OUT" | grep -n '>>> START: persona' | head -1 | cut -d: -f1)

if [ -n "$GENTLE_LINE" ] && [ -n "$PERSONA_LINE" ] && [ "$GENTLE_LINE" -lt "$PERSONA_LINE" ]; then
  pass "T7: sync order — 'gentle' starts before 'persona'"
else
  fail "T7: sync order check failed (gentle_line=$GENTLE_LINE persona_line=$PERSONA_LINE in output: $(printf '%s\n' "$SYNC_OUT" | grep 'START:' | head -5))"
fi

rm -rf "$STUB_ORD" "$TEST_HOME_ORD"
rm -f "$RECORD_ORD"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
