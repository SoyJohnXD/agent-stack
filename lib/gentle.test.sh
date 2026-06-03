#!/usr/bin/env bash
# Tests for lib/gentle.sh
# Run: bash lib/gentle.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

new_home() {
  local h; h=$(mktemp -d); printf '%s' "$h"
}

# Build stub bin dir with a recorder file
new_stub_bin() {
  local record_file="$1"
  local dir; dir=$(mktemp -d)

  cat > "$dir/gentle-ai" <<EOF
#!/usr/bin/env bash
echo "gentle-ai \$*" >> "$record_file"
exit 0
EOF
  chmod +x "$dir/gentle-ai"
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# T11a: phase_gentle runs gentle-ai upgrade then gentle-ai sync (not dry-run)
# ---------------------------------------------------------------------------
TEST_HOME=$(new_home)
RECORD=$(mktemp)
STUB=$(new_stub_bin "$RECORD")

(
  export PATH="$STUB:$PATH"
  export HOME="$TEST_HOME"
  export DRY_RUN=0
  source "$HERE/common.sh"
  source "$HERE/gentle.sh"
  phase_gentle
) >/dev/null 2>&1

UPGRADE_LINE=$(grep "gentle-ai upgrade" "$RECORD" | head -1)
SYNC_LINE=$(grep "gentle-ai sync" "$RECORD" | head -1)

[ -n "$UPGRADE_LINE" ] && pass "phase_gentle runs 'gentle-ai upgrade'" || fail "phase_gentle should run 'gentle-ai upgrade'"
[ -n "$SYNC_LINE" ] && pass "phase_gentle runs 'gentle-ai sync'" || fail "phase_gentle should run 'gentle-ai sync'"

# Verify order: upgrade comes before sync in the record file
UPGRADE_NUM=$(grep -n "gentle-ai upgrade" "$RECORD" | head -1 | cut -d: -f1)
SYNC_NUM=$(grep -n "gentle-ai sync" "$RECORD" | head -1 | cut -d: -f1)
if [ -n "$UPGRADE_NUM" ] && [ -n "$SYNC_NUM" ] && [ "$UPGRADE_NUM" -lt "$SYNC_NUM" ]; then
  pass "phase_gentle runs upgrade BEFORE sync"
else
  fail "phase_gentle should run upgrade before sync"
fi

rm -rf "$STUB" "$TEST_HOME"
rm -f "$RECORD"

# ---------------------------------------------------------------------------
# T11b: --dry-run prints both commands, executes neither
# ---------------------------------------------------------------------------
TEST_HOME2=$(new_home)
RECORD2=$(mktemp)
STUB2=$(new_stub_bin "$RECORD2")

DRY_OUT=$(
  export PATH="$STUB2:$PATH"
  export HOME="$TEST_HOME2"
  export DRY_RUN=1
  source "$HERE/common.sh"
  source "$HERE/gentle.sh"
  phase_gentle
)

# Should print dry-run plans
case "$DRY_OUT" in
  *"[dry-run]"*"gentle-ai upgrade"*) pass "--dry-run prints 'gentle-ai upgrade' plan" ;;
  *) fail "--dry-run should print 'gentle-ai upgrade' plan (got: $DRY_OUT)" ;;
esac
case "$DRY_OUT" in
  *"[dry-run]"*"gentle-ai sync"*) pass "--dry-run prints 'gentle-ai sync' plan" ;;
  *) fail "--dry-run should print 'gentle-ai sync' plan" ;;
esac

# Should NOT have written to the record file (no actual execution)
RECORD_CONTENT=$(cat "$RECORD2" 2>/dev/null || echo "")
[ -z "$RECORD_CONTENT" ] && pass "--dry-run executes neither gentle-ai command" || fail "--dry-run should not execute any gentle-ai command (got: $RECORD_CONTENT)"

rm -rf "$STUB2" "$TEST_HOME2"
rm -f "$RECORD2"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
