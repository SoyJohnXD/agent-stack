#!/usr/bin/env bash
# Tests for lib/overlay.sh
# Run: bash lib/overlay.test.sh
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

  for cmd in git intent-overlay; do
    cat > "$dir/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >> "$record_file"
# simulate clone: create the target dir when clone is called
if [ "$cmd" = "git" ] && [ "\${1:-}" = "clone" ]; then
  mkdir -p "\${!#}"
fi
exit 0
EOF
    chmod +x "$dir/$cmd"
  done
  printf '%s' "$dir"
}

make_manifest() {
  local home="$1"
  local manifest; manifest=$(mktemp)
  cat > "$manifest" <<EOF
overlay | $home/Documents/personal/clean-code-lab | https://github.com/SoyJohnXD/clean-code-lab.git | main
EOF
  printf '%s' "$manifest"
}

# ---------------------------------------------------------------------------
# T14a: phase_overlay pulls clean-code-lab then runs intent-overlay install (not dry-run)
# ---------------------------------------------------------------------------
TEST_HOME=$(new_home)
RECORD=$(mktemp)
STUB=$(new_stub_bin "$RECORD")
MANIFEST=$(make_manifest "$TEST_HOME")

# Pre-create the repo dir so ensure_repo pulls instead of cloning
mkdir -p "$TEST_HOME/Documents/personal/clean-code-lab/.git"

(
  export PATH="$STUB:$PATH"
  export HOME="$TEST_HOME"
  export DRY_RUN=0
  export MANIFEST_FILE="$MANIFEST"
  source "$HERE/common.sh"
  source "$HERE/overlay.sh"
  phase_overlay
) >/dev/null 2>&1

GIT_PULL=$(grep "git.*pull" "$RECORD" | head -1)
OVERLAY_INSTALL=$(grep "intent-overlay install" "$RECORD" | head -1)

[ -n "$GIT_PULL" ] && pass "phase_overlay runs git pull" || fail "phase_overlay should run git pull (record: $(cat "$RECORD"))"
[ -n "$OVERLAY_INSTALL" ] && pass "phase_overlay runs intent-overlay install" || fail "phase_overlay should run intent-overlay install"

# Order: pull before install
PULL_NUM=$(grep -n "git.*pull" "$RECORD" | head -1 | cut -d: -f1)
INSTALL_NUM=$(grep -n "intent-overlay install" "$RECORD" | head -1 | cut -d: -f1)
if [ -n "$PULL_NUM" ] && [ -n "$INSTALL_NUM" ] && [ "$PULL_NUM" -lt "$INSTALL_NUM" ]; then
  pass "phase_overlay pulls BEFORE installing"
else
  fail "phase_overlay should pull before installing"
fi

rm -rf "$STUB" "$TEST_HOME"
rm -f "$RECORD" "$MANIFEST"

# ---------------------------------------------------------------------------
# T14b: --dry-run executes nothing (no real git or intent-overlay calls)
# ---------------------------------------------------------------------------
TEST_HOME2=$(new_home)
RECORD2=$(mktemp)
STUB2=$(new_stub_bin "$RECORD2")
MANIFEST2=$(make_manifest "$TEST_HOME2")

DRY_OUT=$(
  export PATH="$STUB2:$PATH"
  export HOME="$TEST_HOME2"
  export DRY_RUN=1
  export MANIFEST_FILE="$MANIFEST2"
  source "$HERE/common.sh"
  source "$HERE/overlay.sh"
  phase_overlay
)

# dry-run output should mention the planned commands
case "$DRY_OUT" in
  *"[dry-run]"*) pass "--dry-run prints planned actions" ;;
  *) fail "--dry-run should print planned actions (got: $DRY_OUT)" ;;
esac

# No mutation calls in record file (rev-parse is a read, not a mutation — allowed)
RECORD2_MUTATION=$(grep -v "rev-parse" "$RECORD2" 2>/dev/null || echo "")
[ -z "$RECORD2_MUTATION" ] && pass "--dry-run executes no mutation git or intent-overlay commands" || fail "--dry-run should not execute mutation commands (got: $RECORD2_MUTATION)"

rm -rf "$STUB2" "$TEST_HOME2"
rm -f "$RECORD2" "$MANIFEST2"

# ---------------------------------------------------------------------------
# T14c: idempotence intent — running twice with stubs produces same plan
# ---------------------------------------------------------------------------
TEST_HOME3=$(new_home)
RECORD3=$(mktemp)
STUB3=$(new_stub_bin "$RECORD3")
MANIFEST3=$(make_manifest "$TEST_HOME3")

mkdir -p "$TEST_HOME3/Documents/personal/clean-code-lab/.git"

(
  export PATH="$STUB3:$PATH"
  export HOME="$TEST_HOME3"
  export DRY_RUN=1
  export MANIFEST_FILE="$MANIFEST3"
  source "$HERE/common.sh"
  source "$HERE/overlay.sh"
  phase_overlay
  phase_overlay
) >/dev/null 2>&1

# No mutation calls in dry-run (rev-parse reads are fine)
RECORD3_MUTATIONS=$(grep -v "rev-parse" "$RECORD3" 2>/dev/null || echo "")
[ -z "$RECORD3_MUTATIONS" ] && pass "phase_overlay is idempotent in dry-run (no mutations)" || fail "phase_overlay dry-run should mutate nothing on second run (got: $RECORD3_MUTATIONS)"

rm -rf "$STUB3" "$TEST_HOME3"
rm -f "$RECORD3" "$MANIFEST3"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
