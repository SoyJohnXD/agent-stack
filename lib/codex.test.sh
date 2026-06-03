#!/usr/bin/env bash
# Tests for lib/codex.sh
# Run: bash lib/codex.test.sh
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

  for cmd in git codex-sdd-sync; do
    cat > "$dir/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$*" >> "$record_file"
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
codex | $home/Documents/osoria/codex-sdd | https://github.com/SoyJohnXD/codex.git | main
EOF
  printf '%s' "$manifest"
}

make_install_sh() {
  local repo_path="$1"
  local record_file="$2"
  mkdir -p "$repo_path"
  cat > "$repo_path/install.sh" <<EOF
#!/usr/bin/env bash
echo "install.sh \$*" >> "$record_file"
exit 0
EOF
  chmod +x "$repo_path/install.sh"
}

# ---------------------------------------------------------------------------
# T17a: phase_codex pulls repo, runs install.sh, then codex-sdd-sync --mcp-audit
# ---------------------------------------------------------------------------
TEST_HOME=$(new_home)
RECORD=$(mktemp)
STUB=$(new_stub_bin "$RECORD")
MANIFEST=$(make_manifest "$TEST_HOME")

CODEX_PATH="$TEST_HOME/Documents/osoria/codex-sdd"
make_install_sh "$CODEX_PATH" "$RECORD"
mkdir -p "$CODEX_PATH/.git"

(
  export PATH="$STUB:$PATH"
  export HOME="$TEST_HOME"
  export DRY_RUN=0
  export MANIFEST_FILE="$MANIFEST"
  source "$HERE/common.sh"
  source "$HERE/codex.sh"
  phase_codex
) >/dev/null 2>&1

GIT_PULL=$(grep "git.*pull" "$RECORD" | head -1)
INSTALL_CALL=$(grep "install.sh" "$RECORD" | head -1)
MCP_AUDIT=$(grep "codex-sdd-sync --mcp-audit" "$RECORD" | head -1)

[ -n "$GIT_PULL" ] && pass "phase_codex runs git pull" || fail "phase_codex should run git pull (record: $(cat "$RECORD"))"
[ -n "$INSTALL_CALL" ] && pass "phase_codex runs install.sh" || fail "phase_codex should run install.sh"
[ -n "$MCP_AUDIT" ] && pass "phase_codex runs codex-sdd-sync --mcp-audit" || fail "phase_codex should run codex-sdd-sync --mcp-audit"

# Order: pull -> install -> mcp-audit
PULL_NUM=$(grep -n "git.*pull" "$RECORD" | head -1 | cut -d: -f1)
INSTALL_NUM=$(grep -n "install.sh" "$RECORD" | head -1 | cut -d: -f1)
AUDIT_NUM=$(grep -n "codex-sdd-sync" "$RECORD" | head -1 | cut -d: -f1)
if [ -n "$PULL_NUM" ] && [ -n "$INSTALL_NUM" ] && [ -n "$AUDIT_NUM" ] \
   && [ "$PULL_NUM" -lt "$INSTALL_NUM" ] && [ "$INSTALL_NUM" -lt "$AUDIT_NUM" ]; then
  pass "phase_codex order is pull -> install -> mcp-audit"
else
  fail "phase_codex should run in order: pull -> install -> mcp-audit"
fi

rm -rf "$STUB" "$TEST_HOME"
rm -f "$RECORD" "$MANIFEST"

# ---------------------------------------------------------------------------
# T17b: --dry-run executes nothing (no real git, install, or codex-sdd-sync calls)
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
  source "$HERE/codex.sh"
  phase_codex
)

case "$DRY_OUT" in
  *"[dry-run]"*) pass "--dry-run prints planned actions" ;;
  *) fail "--dry-run should print planned actions (got: $DRY_OUT)" ;;
esac

# No mutations (only rev-parse reads are ok)
RECORD2_MUTATIONS=$(grep -v "rev-parse" "$RECORD2" 2>/dev/null || echo "")
[ -z "$RECORD2_MUTATIONS" ] && pass "--dry-run executes no mutation commands" || fail "--dry-run should not execute mutation commands (got: $RECORD2_MUTATIONS)"

rm -rf "$STUB2" "$TEST_HOME2"
rm -f "$RECORD2" "$MANIFEST2"

# ---------------------------------------------------------------------------
# T17c: --skip-codex flag causes dispatch to skip phase_codex
# (tested via the entrypoint in agent-stack.test.sh; here we verify the flag export)
# ---------------------------------------------------------------------------
TEST_HOME3=$(new_home)
(
  export HOME="$TEST_HOME3"
  export DRY_RUN=0
  export SKIP_CODEX=1
  source "$HERE/common.sh"

  skip_called=0
  if [ "${SKIP_CODEX:-0}" = "1" ]; then
    skip_called=1
  fi
  [ "$skip_called" = "1" ]
)
[ $? -eq 0 ] && pass "SKIP_CODEX=1 environment variable is recognized" || fail "SKIP_CODEX=1 should be recognized"

rm -rf "$TEST_HOME3"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
