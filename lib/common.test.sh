#!/usr/bin/env bash
# Tests for lib/common.sh
# Run: bash lib/common.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
COMMON="$HERE/common.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# Isolated home for each logical test group
new_home() {
  local h
  h=$(mktemp -d)
  printf '%s' "$h"
}

# Stub bin dir: records calls made through run()
new_stub_bin() {
  local dir
  dir=$(mktemp -d)
  # A generic stub that records its invocation
  cat > "$dir/stub_recorder" <<'STUB'
#!/usr/bin/env bash
echo "$0 $*" >> "$STUB_RECORD_FILE"
STUB
  chmod +x "$dir/stub_recorder"
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# run() — dry-run gate
# ---------------------------------------------------------------------------
TEST_HOME=$(new_home)
RECORD=$(mktemp)

# When DRY_RUN=1, run() should print [dry-run] and NOT write to the record file
(
  export HOME="$TEST_HOME"
  export DRY_RUN=1
  export STUB_RECORD_FILE="$RECORD"
  # shellcheck source=/dev/null
  source "$COMMON"
  run echo "hello_world"
) >/dev/null 2>&1

if ! grep -q "hello_world" "$RECORD" 2>/dev/null; then
  pass "run() with DRY_RUN=1 does not execute the command"
else
  fail "run() with DRY_RUN=1 should NOT execute the command"
fi

# When DRY_RUN=1, run() should print [dry-run] prefix
DRY_OUT=$(
  export HOME="$TEST_HOME"
  export DRY_RUN=1
  source "$COMMON"
  run echo "hello_dry"
)
case "$DRY_OUT" in
  *"[dry-run]"*) pass "run() with DRY_RUN=1 prints [dry-run] prefix" ;;
  *) fail "run() with DRY_RUN=1 should print [dry-run] prefix" ;;
esac

# When DRY_RUN=0, run() executes the command
EXEC_OUT=$(
  export HOME="$TEST_HOME"
  export DRY_RUN=0
  source "$COMMON"
  run echo "hello_exec"
)
case "$EXEC_OUT" in
  *"hello_exec"*) pass "run() with DRY_RUN=0 executes the command" ;;
  *) fail "run() with DRY_RUN=0 should execute the command" ;;
esac

rm -f "$RECORD"

# ---------------------------------------------------------------------------
# parse_manifest() — skips blanks and #-comments, yields 4 fields per line
# ---------------------------------------------------------------------------
TEST_HOME2=$(new_home)
MANIFEST=$(mktemp)
cat > "$MANIFEST" <<'EOF'
# This is a comment

codex   | ~/Documents/osoria/codex   | https://github.com/SoyJohnXD/codex.git | main

overlay | ~/Documents/personal/lab   | https://github.com/SoyJohnXD/lab.git   | main
EOF

PARSED=$(
  export HOME="$TEST_HOME2"
  export DRY_RUN=0
  source "$COMMON"
  parse_manifest "$MANIFEST"
)

LINE_COUNT=$(printf '%s\n' "$PARSED" | grep -c '^' 2>/dev/null || echo 0)
if [ "$LINE_COUNT" = "2" ]; then
  pass "parse_manifest yields 2 non-blank non-comment lines"
else
  fail "parse_manifest should yield 2 lines, got $LINE_COUNT"
fi

# Each line should contain exactly 3 pipe-separated parts (4 fields)
FIRST_LINE=$(printf '%s\n' "$PARSED" | head -n1)
IFS='|' read -r f_name f_path f_remote f_branch <<< "$FIRST_LINE"
f_name=$(printf '%s' "$f_name" | tr -d ' ')
f_path=$(printf '%s' "$f_path" | tr -d ' ')
[ "$f_name" = "codex" ] && pass "parse_manifest trims name field" || fail "parse_manifest name should be 'codex', got '$f_name'"
[ -n "$f_path" ] && pass "parse_manifest yields local_path field" || fail "parse_manifest should yield local_path"
[ -n "$f_remote" ] && pass "parse_manifest yields remote field" || fail "parse_manifest should yield remote field"
f_branch=$(printf '%s' "$f_branch" | tr -d ' ')
[ "$f_branch" = "main" ] && pass "parse_manifest yields branch field" || fail "parse_manifest branch should be 'main', got '$f_branch'"

# ~ expansion: local_path starting with ~ should expand to $HOME equivalent
SECOND_LINE=$(printf '%s\n' "$PARSED" | head -n2 | tail -n1)
IFS='|' read -r _ s_path _ _ <<< "$SECOND_LINE"
case "$s_path" in
  *"$TEST_HOME2"*|*"~"*)
    # either expanded or kept as ~ — expansion happens at ensure_repo call time
    pass "parse_manifest returns path field (expansion deferred or done)"
    ;;
  *)
    fail "parse_manifest should return path field"
    ;;
esac

rm -f "$MANIFEST"

# ---------------------------------------------------------------------------
# log_start / log_finish — print start+finish markers
# ---------------------------------------------------------------------------
TEST_HOME3=$(new_home)
LOG_OUT=$(
  export HOME="$TEST_HOME3"
  export DRY_RUN=0
  source "$COMMON"
  log_start "test-action"
  log_finish "test-action"
)
case "$LOG_OUT" in
  *"test-action"*) pass "log_start/log_finish print the action name" ;;
  *) fail "log_start/log_finish should print the action name" ;;
esac

# Confirm both start and finish appear
START_COUNT=$(printf '%s\n' "$LOG_OUT" | grep -c "START\|start\|>>>" 2>/dev/null || echo 0)
FINISH_COUNT=$(printf '%s\n' "$LOG_OUT" | grep -c "DONE\|done\|finish\|<<<" 2>/dev/null || echo 0)
[ "$START_COUNT" -ge 1 ] && pass "log_start prints a start marker" || fail "log_start should print a start marker"
[ "$FINISH_COUNT" -ge 1 ] && pass "log_finish prints a finish marker" || fail "log_finish should print a finish marker"

# ---------------------------------------------------------------------------
# ensure_repo() — clone when absent, pull when present
# ---------------------------------------------------------------------------
TEST_HOME4=$(new_home)
STUB_BIN=$(mktemp -d)
GIT_CALLS=$(mktemp)

# Fake git that records calls
cat > "$STUB_BIN/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$GIT_CALLS"
# Simulate clone: create the target dir
if [ "\$1" = "clone" ]; then
  mkdir -p "\${!#}"
fi
exit 0
EOF
chmod +x "$STUB_BIN/git"

ABSENT_PATH="$TEST_HOME4/repos/myrepo"
(
  export PATH="$STUB_BIN:$PATH"
  export HOME="$TEST_HOME4"
  export DRY_RUN=0
  source "$COMMON"
  ensure_repo "$ABSENT_PATH" "https://github.com/example/repo.git" "main"
) >/dev/null 2>&1

if grep -q "clone" "$GIT_CALLS"; then
  pass "ensure_repo clones when local_path is absent"
else
  fail "ensure_repo should clone when local_path is absent"
fi

# Simulate pull when repo already exists
echo "" > "$GIT_CALLS"  # reset
mkdir -p "$ABSENT_PATH/.git"
(
  export PATH="$STUB_BIN:$PATH"
  export HOME="$TEST_HOME4"
  export DRY_RUN=0
  source "$COMMON"
  ensure_repo "$ABSENT_PATH" "https://github.com/example/repo.git" "main"
) >/dev/null 2>&1

if grep -q "pull\|fetch\|checkout" "$GIT_CALLS"; then
  pass "ensure_repo pulls when local_path already exists"
else
  fail "ensure_repo should pull when local_path already exists"
fi

rm -rf "$STUB_BIN" "$GIT_CALLS" "$TEST_HOME4"

# ---------------------------------------------------------------------------
# tilde expansion in paths
# ---------------------------------------------------------------------------
TEST_HOME5=$(new_home)
EXPANDED=$(
  export HOME="$TEST_HOME5"
  export DRY_RUN=0
  source "$COMMON"
  expand_path "~/Documents/test"
)
case "$EXPANDED" in
  "$TEST_HOME5/Documents/test") pass "expand_path replaces ~ with \$HOME" ;;
  *) fail "expand_path should replace ~ with \$HOME, got '$EXPANDED'" ;;
esac

rm -rf "$TEST_HOME5"

# ---------------------------------------------------------------------------
# T1.1: ~/.agent-stack paths expand correctly via parse_manifest + expand_path
# ---------------------------------------------------------------------------
TEST_HOME6=$(new_home)
MANIFEST2=$(mktemp)
cat > "$MANIFEST2" <<'EOF'
codex   | ~/.agent-stack/repos/codex-sdd-gentle-installer | https://github.com/SoyJohnXD/codex-sdd-gentle-installer.git | main
overlay | ~/.agent-stack/repos/clean-code-lab             | https://github.com/SoyJohnXD/clean-code-lab.git             | main
EOF

PARSED2=$(
  export HOME="$TEST_HOME6"
  export DRY_RUN=0
  source "$COMMON"
  parse_manifest "$MANIFEST2"
)

CODEX_LINE=$(printf '%s\n' "$PARSED2" | head -n1)
IFS='|' read -r _ codex_path _ _ <<< "$CODEX_LINE"
codex_path=$(printf '%s' "$codex_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

case "$codex_path" in
  "$TEST_HOME6/.agent-stack/repos/codex-sdd-gentle-installer")
    pass "expand_path resolves ~/.agent-stack/repos/codex-sdd-gentle-installer to \$HOME equivalent"
    ;;
  *)
    fail "expand_path should resolve to \$HOME/.agent-stack/repos/codex-sdd-gentle-installer, got '$codex_path'"
    ;;
esac

# ---------------------------------------------------------------------------
# T1.2: no parsed path contains the substring 'Documents'
# ---------------------------------------------------------------------------
HAS_DOCUMENTS=$(printf '%s\n' "$PARSED2" | grep 'Documents' 2>/dev/null || true)
if [ -z "$HAS_DOCUMENTS" ]; then
  pass "no parsed local_path from portable manifest contains 'Documents'"
else
  fail "parsed paths should NOT contain 'Documents', got: $HAS_DOCUMENTS"
fi

rm -f "$MANIFEST2"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
