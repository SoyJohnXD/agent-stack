#!/usr/bin/env bash
# Tests for lib/doctor.sh
# Run: bash lib/doctor.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

new_home() {
  local h; h=$(mktemp -d); printf '%s' "$h"
}

new_stub_bin_all_pass() {
  local record_file="$1"
  local dir; dir=$(mktemp -d)

  for cmd in intent-overlay codex-sdd-sync claude codex opencode gentle-ai gum git; do
    cat > "$dir/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >> "$record_file"
exit 0
EOF
    chmod +x "$dir/$cmd"
  done
  printf '%s' "$dir"
}

new_stub_bin_required_fail() {
  local record_file="$1"
  local failing_cmd="$2"
  local dir; dir=$(mktemp -d)

  for cmd in intent-overlay codex-sdd-sync claude codex opencode gentle-ai gum git; do
    if [ "$cmd" = "$failing_cmd" ]; then
      cat > "$dir/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >> "$record_file"
exit 1
EOF
    else
      cat > "$dir/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >> "$record_file"
exit 0
EOF
    fi
    chmod +x "$dir/$cmd"
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# T23a: phase_doctor invokes all expected checks
# ---------------------------------------------------------------------------
TEST_HOME=$(new_home)
RECORD=$(mktemp)
STUB=$(new_stub_bin_all_pass "$RECORD")

(
  export PATH="$STUB:$PATH"
  export HOME="$TEST_HOME"
  export DRY_RUN=0
  source "$HERE/common.sh"
  source "$HERE/doctor.sh"
  phase_doctor
) >/dev/null 2>&1

# All required checks should be invoked
OVERLAY_DOCTOR=$(grep "intent-overlay doctor" "$RECORD" | head -1)
MCP_AUDIT=$(grep "codex-sdd-sync --mcp-audit" "$RECORD" | head -1)
CLAUDE_CHECK=$(grep "claude --version" "$RECORD" | head -1)
CODEX_CHECK=$(grep "codex --version" "$RECORD" | head -1)
OPENCODE_CHECK=$(grep "opencode --version" "$RECORD" | head -1)
GENTLEAI_CHECK=$(grep "gentle-ai --version" "$RECORD" | head -1)
GIT_CHECK=$(grep "git --version" "$RECORD" | head -1)
GUM_CHECK=$(grep "gum --version" "$RECORD" | head -1)

[ -n "$OVERLAY_DOCTOR" ]   && pass "doctor invokes intent-overlay doctor" || fail "doctor should invoke intent-overlay doctor"
[ -n "$MCP_AUDIT" ]        && pass "doctor invokes codex-sdd-sync --mcp-audit" || fail "doctor should invoke codex-sdd-sync --mcp-audit"
[ -n "$CLAUDE_CHECK" ]     && pass "doctor checks claude version" || fail "doctor should check claude version"
[ -n "$CODEX_CHECK" ]      && pass "doctor checks codex version" || fail "doctor should check codex version"
[ -n "$OPENCODE_CHECK" ]   && pass "doctor checks opencode version" || fail "doctor should check opencode version"
[ -n "$GENTLEAI_CHECK" ]   && pass "doctor checks gentle-ai version" || fail "doctor should check gentle-ai version"
[ -n "$GIT_CHECK" ]        && pass "doctor checks git version" || fail "doctor should check git version"
[ -n "$GUM_CHECK" ]        && pass "doctor checks gum version" || fail "doctor should check gum version"

rm -rf "$STUB" "$TEST_HOME"
rm -f "$RECORD"

# ---------------------------------------------------------------------------
# T23b: phase_doctor exits 0 when all required checks pass
# ---------------------------------------------------------------------------
TEST_HOME2=$(new_home)
RECORD2=$(mktemp)
STUB2=$(new_stub_bin_all_pass "$RECORD2")

(
  export PATH="$STUB2:$PATH"
  export HOME="$TEST_HOME2"
  export DRY_RUN=0
  source "$HERE/common.sh"
  source "$HERE/doctor.sh"
  phase_doctor
) >/dev/null 2>&1
DOCTOR_EXIT=$?

[ "$DOCTOR_EXIT" = "0" ] && pass "doctor exits 0 when all required checks pass" || fail "doctor should exit 0 when all required checks pass (got: $DOCTOR_EXIT)"

rm -rf "$STUB2" "$TEST_HOME2"
rm -f "$RECORD2"

# ---------------------------------------------------------------------------
# T23c: per-check pass/fail summary is printed
# ---------------------------------------------------------------------------
TEST_HOME3=$(new_home)
RECORD3=$(mktemp)
STUB3=$(new_stub_bin_all_pass "$RECORD3")

SUMMARY=$(
  export PATH="$STUB3:$PATH"
  export HOME="$TEST_HOME3"
  export DRY_RUN=0
  source "$HERE/common.sh"
  source "$HERE/doctor.sh"
  phase_doctor
)

case "$SUMMARY" in
  *"[PASS]"*) pass "doctor prints [PASS] summary entries" ;;
  *) fail "doctor should print [PASS] summary entries (got: $SUMMARY)" ;;
esac

rm -rf "$STUB3" "$TEST_HOME3"
rm -f "$RECORD3"

# ---------------------------------------------------------------------------
# T23d: doctor exits non-zero when a required check fails (not gum, gum is optional)
# ---------------------------------------------------------------------------
for required_check in claude codex opencode gentle-ai git; do
  TEST_HOME_F=$(new_home)
  RECORD_F=$(mktemp)
  STUB_F=$(new_stub_bin_required_fail "$RECORD_F" "$required_check")

  (
    export PATH="$STUB_F:$PATH"
    export HOME="$TEST_HOME_F"
    export DRY_RUN=0
    source "$HERE/common.sh"
    source "$HERE/doctor.sh"
    phase_doctor
  ) >/dev/null 2>&1
  FAIL_EXIT=$?

  [ "$FAIL_EXIT" -ne 0 ] && pass "doctor exits non-zero when required '$required_check' check fails" || fail "doctor should exit non-zero when '$required_check' fails"

  rm -rf "$STUB_F" "$TEST_HOME_F"
  rm -f "$RECORD_F"
done

# ---------------------------------------------------------------------------
# T23e: gum is optional — doctor exits 0 when gum is missing
# ---------------------------------------------------------------------------
TEST_HOME4=$(new_home)
RECORD4=$(mktemp)
STUB4=$(new_stub_bin_required_fail "$RECORD4" "gum")

(
  export PATH="$STUB4:$PATH"
  export HOME="$TEST_HOME4"
  export DRY_RUN=0
  source "$HERE/common.sh"
  source "$HERE/doctor.sh"
  phase_doctor
) >/dev/null 2>&1
GUM_FAIL_EXIT=$?

[ "$GUM_FAIL_EXIT" = "0" ] && pass "doctor exits 0 when optional 'gum' check fails" || fail "doctor should exit 0 when 'gum' (optional) fails"

rm -rf "$STUB4" "$TEST_HOME4"
rm -f "$RECORD4"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
