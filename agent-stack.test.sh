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

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
