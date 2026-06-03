#!/usr/bin/env bash
# Tests for lib/clis.sh
# Run: bash lib/clis.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

new_home() {
  local h; h=$(mktemp -d); printf '%s' "$h"
}

new_stub_bin() {
  local record_file="$1"
  local dir; dir=$(mktemp -d)

  for cmd in claude codex opencode gentle-ai; do
    cat > "$dir/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >> "$record_file"
exit 0
EOF
    chmod +x "$dir/$cmd"
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# T20a: phase_update_clis runs all 4 update commands (not dry-run)
# ---------------------------------------------------------------------------
TEST_HOME=$(new_home)
RECORD=$(mktemp)
STUB=$(new_stub_bin "$RECORD")

(
  export PATH="$STUB:$PATH"
  export HOME="$TEST_HOME"
  export DRY_RUN=0
  source "$HERE/common.sh"
  source "$HERE/clis.sh"
  phase_update_clis
) >/dev/null 2>&1

CLAUDE_UPDATE=$(grep "^claude update$" "$RECORD" | head -1)
CODEX_UPDATE=$(grep "^codex update$" "$RECORD" | head -1)
OPENCODE_UPGRADE=$(grep "^opencode upgrade$" "$RECORD" | head -1)
GENTLEAI_UPGRADE=$(grep "^gentle-ai upgrade$" "$RECORD" | head -1)

[ -n "$CLAUDE_UPDATE" ]    && pass "phase_update_clis runs 'claude update'" || fail "phase_update_clis should run 'claude update' (record: $(cat "$RECORD"))"
[ -n "$CODEX_UPDATE" ]     && pass "phase_update_clis runs 'codex update'" || fail "phase_update_clis should run 'codex update'"
[ -n "$OPENCODE_UPGRADE" ] && pass "phase_update_clis runs 'opencode upgrade'" || fail "phase_update_clis should run 'opencode upgrade'"
[ -n "$GENTLEAI_UPGRADE" ] && pass "phase_update_clis runs 'gentle-ai upgrade'" || fail "phase_update_clis should run 'gentle-ai upgrade'"

rm -rf "$STUB" "$TEST_HOME"
rm -f "$RECORD"

# ---------------------------------------------------------------------------
# T20b: --dry-run prints all 4 commands, executes none
# ---------------------------------------------------------------------------
TEST_HOME2=$(new_home)
RECORD2=$(mktemp)
STUB2=$(new_stub_bin "$RECORD2")

DRY_OUT=$(
  export PATH="$STUB2:$PATH"
  export HOME="$TEST_HOME2"
  export DRY_RUN=1
  source "$HERE/common.sh"
  source "$HERE/clis.sh"
  phase_update_clis
)

# All 4 should appear in dry-run output
case "$DRY_OUT" in
  *"claude update"*) pass "--dry-run output contains 'claude update'" ;;
  *) fail "--dry-run should output 'claude update' (got: $DRY_OUT)" ;;
esac
case "$DRY_OUT" in
  *"codex update"*) pass "--dry-run output contains 'codex update'" ;;
  *) fail "--dry-run should output 'codex update'" ;;
esac
case "$DRY_OUT" in
  *"opencode upgrade"*) pass "--dry-run output contains 'opencode upgrade'" ;;
  *) fail "--dry-run should output 'opencode upgrade'" ;;
esac
case "$DRY_OUT" in
  *"gentle-ai upgrade"*) pass "--dry-run output contains 'gentle-ai upgrade'" ;;
  *) fail "--dry-run should output 'gentle-ai upgrade'" ;;
esac

# No actual executions
RECORD2_CONTENT=$(cat "$RECORD2" 2>/dev/null || echo "")
[ -z "$RECORD2_CONTENT" ] && pass "--dry-run executes none of the 4 commands" || fail "--dry-run should execute none of the commands (got: $RECORD2_CONTENT)"

rm -rf "$STUB2" "$TEST_HOME2"
rm -f "$RECORD2"

# ---------------------------------------------------------------------------
# T20c: verify sync and all ordering via spot check on the record
#   sync: gentle -> codex -> overlay
#   all: update-clis -> gentle -> codex -> overlay
# (high-level ordering tested in agent-stack.test.sh; here just validate clis runs first in all)
# ---------------------------------------------------------------------------
HERE_ROOT="$(dirname "$HERE")"
TEST_HOME3=$(new_home)
RECORD3=$(mktemp)
STUB3=$(new_stub_bin "$RECORD3")

# Add stubs for git, gentle-ai, intent-overlay, codex-sdd-sync
for extra in git gentle-ai intent-overlay codex-sdd-sync; do
  cat > "$STUB3/$extra" <<EOF
#!/usr/bin/env bash
echo "$extra \$*" >> "$RECORD3"
if [ "$extra" = "git" ] && [ "\${1:-}" = "clone" ]; then
  mkdir -p "\${!#}"
fi
exit 0
EOF
  chmod +x "$STUB3/$extra"
done

# Make fake install.sh for codex path
CODEX_PATH="$TEST_HOME3/Documents/osoria/codex-sdd-gentle-installer"
mkdir -p "$CODEX_PATH/.git"
cat > "$CODEX_PATH/install.sh" <<EOF
#!/usr/bin/env bash
echo "install.sh \$*" >> "$RECORD3"
exit 0
EOF
chmod +x "$CODEX_PATH/install.sh"

(
  export PATH="$STUB3:$PATH"
  export HOME="$TEST_HOME3"
  export DRY_RUN=0
  export MANIFEST_FILE="$HERE_ROOT/repos.manifest"
  source "$HERE/common.sh"
  source "$HERE/gentle.sh"
  source "$HERE/codex.sh"
  source "$HERE/overlay.sh"
  source "$HERE/clis.sh"
  phase_update_clis
  phase_gentle
) >/dev/null 2>&1

CLAUDE_LINE=$(grep -n "^claude update$" "$RECORD3" | head -1 | cut -d: -f1)
GENTLE_UPGRADE=$(grep -n "^gentle-ai upgrade$" "$RECORD3" | head -1 | cut -d: -f1)
GENTLE_SYNC=$(grep -n "^gentle-ai sync$" "$RECORD3" | head -1 | cut -d: -f1)

if [ -n "$CLAUDE_LINE" ] && [ -n "$GENTLE_SYNC" ] && [ "$CLAUDE_LINE" -lt "$GENTLE_SYNC" ]; then
  pass "in 'all' order: update-clis runs before gentle sync"
else
  fail "update-clis (claude update) should run before gentle sync"
fi

rm -rf "$STUB3" "$TEST_HOME3"
rm -f "$RECORD3"

# ---------------------------------------------------------------------------
# T2.1: absent claude → skip message, exit 0
# T2.2: present codex/opencode/gentle-ai → update/upgrade called
# T2.3: absent claude → claude update NOT in record
# ---------------------------------------------------------------------------
TEST_HOME4=$(new_home)
RECORD4=$(mktemp)

# Stub bin WITHOUT claude, but WITH the other three
# Use a wrapper script rather than subshell PATH isolation so bash built-ins remain available.
# Place a fake 'claude' that exits 1 (simulates command-not-found) in the stub dir using a
# sentinel approach: wrap in a helper script that resets PATH for command -v resolution only.
BASH_BIN=$(command -v bash)
STUB4=$(mktemp -d)
for cmd in codex opencode gentle-ai; do
  # Use absolute shebang so stub works even with minimal PATH
  cat > "$STUB4/$cmd" <<EOF
#!$BASH_BIN
echo "$cmd \$*" >> "$RECORD4"
exit 0
EOF
  chmod +x "$STUB4/$cmd"
done

# Run via a wrapper that exposes only STUB4 on PATH (so system claude is invisible)
WRAPPER4=$(mktemp)
cat > "$WRAPPER4" <<WRAPPER
#!$BASH_BIN
set -u
export PATH="$STUB4"
export HOME="$TEST_HOME4"
export DRY_RUN=0
source "$HERE/common.sh"
source "$HERE/clis.sh"
phase_update_clis
WRAPPER
chmod +x "$WRAPPER4"

SKIP_OUT=$("$BASH_BIN" "$WRAPPER4")

case "$SKIP_OUT" in
  *"[skip] claude not installed"*)
    pass "absent claude: output contains '[skip] claude not installed'"
    ;;
  *)
    fail "absent claude: should print '[skip] claude not installed' (got: $SKIP_OUT)"
    ;;
esac

# T2.2: other three were still invoked
CODEX_CALLED=$(grep "^codex update$" "$RECORD4" | head -1)
OPENCODE_CALLED=$(grep "^opencode upgrade$" "$RECORD4" | head -1)
GENTLE_CALLED=$(grep "^gentle-ai upgrade$" "$RECORD4" | head -1)

[ -n "$CODEX_CALLED" ]   && pass "absent claude: codex update still runs" || fail "absent claude: codex update should still run (record: $(cat "$RECORD4"))"
[ -n "$OPENCODE_CALLED" ] && pass "absent claude: opencode upgrade still runs" || fail "absent claude: opencode upgrade should still run"
[ -n "$GENTLE_CALLED" ]   && pass "absent claude: gentle-ai upgrade still runs" || fail "absent claude: gentle-ai upgrade should still run"

# T2.3: claude update NOT in record (binary was absent, only skip message printed)
CLAUDE_IN_RECORD=$(grep "^claude" "$RECORD4" 2>/dev/null || true)
if [ -z "$CLAUDE_IN_RECORD" ]; then
  pass "absent claude: 'claude update' was NOT executed (not in record)"
else
  fail "absent claude: 'claude update' should NOT be in record, got: $CLAUDE_IN_RECORD"
fi

rm -rf "$STUB4" "$TEST_HOME4"
rm -f "$RECORD4"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
