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

# ---------------------------------------------------------------------------
# upsert_block_by_markers / write_managed_block
# Lifted from lib/persona.test.sh T1-T5, generalized to arbitrary markers.
# ---------------------------------------------------------------------------
UB_START='<!-- upsert-test:start -->'
UB_END='<!-- upsert-test:end -->'

# Write a block fixture to a temp file. Usage: make_block <inner_content>
# The temp file contains the full block including both markers.
make_block() {
  local content="$1"
  local src
  src=$(mktemp)
  printf '%s\n%s\n%s\n' "$UB_START" "$content" "$UB_END" > "$src"
  printf '%s' "$src"
}

# T2.1 — insert when absent
TB1_HOME=$(new_home)
TB1_SRC=$(make_block "CONTENT-B1")
TB1_DEST="$TB1_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$TB1_DEST")"
printf 'existing prose\n' > "$TB1_DEST"

(
  export HOME="$TB1_HOME" DRY_RUN=0
  source "$COMMON"
  write_managed_block "$TB1_DEST" "$UB_START" "$UB_END" "$TB1_SRC"
) >/dev/null 2>&1

START_COUNT_B1=$(grep -c "$UB_START" "$TB1_DEST" 2>/dev/null || echo 0)
[ "$START_COUNT_B1" = "1" ] && pass "write_managed_block: block inserted (exactly one start marker)" || fail "write_managed_block: expected one start marker, got $START_COUNT_B1"

if grep -q 'existing prose' "$TB1_DEST" 2>/dev/null; then
  pass "write_managed_block: pre-existing content preserved"
else
  fail "write_managed_block: pre-existing content was lost"
fi

rm -rf "$TB1_HOME"; rm -f "$TB1_SRC"

# T2.2 — idempotent second run
TB2_HOME=$(new_home)
TB2_SRC=$(make_block "CONTENT-B2")
TB2_DEST="$TB2_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$TB2_DEST")"
printf 'preamble\n' > "$TB2_DEST"

(
  export HOME="$TB2_HOME" DRY_RUN=0
  source "$COMMON"
  write_managed_block "$TB2_DEST" "$UB_START" "$UB_END" "$TB2_SRC"
) >/dev/null 2>&1

cp "$TB2_DEST" "${TB2_DEST}.after_run1"

(
  export HOME="$TB2_HOME" DRY_RUN=0
  source "$COMMON"
  write_managed_block "$TB2_DEST" "$UB_START" "$UB_END" "$TB2_SRC"
) >/dev/null 2>&1

if cmp -s "${TB2_DEST}.after_run1" "$TB2_DEST"; then
  pass "write_managed_block: second run is idempotent (file byte-identical)"
else
  fail "write_managed_block: file changed between run 1 and run 2"
fi

COUNT_B2=$(grep -c "$UB_START" "$TB2_DEST" 2>/dev/null || echo 0)
[ "$COUNT_B2" = "1" ] && pass "write_managed_block: exactly one block after two runs" || fail "write_managed_block: expected one start marker, got $COUNT_B2"

rm -rf "$TB2_HOME"; rm -f "$TB2_SRC"

# T2.3 — replace in place
TB3_HOME=$(new_home)
TB3_SRC=$(make_block "NEW-CONTENT-B3")
TB3_DEST="$TB3_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$TB3_DEST")"
printf 'HEAD\n%s\nOLD\n%s\nTAIL\n' "$UB_START" "$UB_END" > "$TB3_DEST"

(
  export HOME="$TB3_HOME" DRY_RUN=0
  source "$COMMON"
  write_managed_block "$TB3_DEST" "$UB_START" "$UB_END" "$TB3_SRC"
) >/dev/null 2>&1

COUNT_B3=$(grep -c "$UB_START" "$TB3_DEST" 2>/dev/null || echo 0)
[ "$COUNT_B3" = "1" ] && pass "write_managed_block: exactly one start marker after replace" || fail "write_managed_block: expected one start marker, got $COUNT_B3"

if grep -q 'NEW-CONTENT-B3' "$TB3_DEST" 2>/dev/null; then
  pass "write_managed_block: new block content present"
else
  fail "write_managed_block: new block content missing"
fi

if ! grep -q '^OLD$' "$TB3_DEST" 2>/dev/null; then
  pass "write_managed_block: old block content removed"
else
  fail "write_managed_block: old block content still present"
fi

if grep -q '^HEAD$' "$TB3_DEST" && grep -q '^TAIL$' "$TB3_DEST"; then
  pass "write_managed_block: content outside markers preserved (HEAD and TAIL intact)"
else
  fail "write_managed_block: content outside markers was lost (HEAD/TAIL missing)"
fi

rm -rf "$TB3_HOME"; rm -f "$TB3_SRC"

# T2.4 — dry-run: no file mutation
TB4_HOME=$(new_home)
TB4_SRC=$(make_block "CONTENT-B4")
TB4_DEST="$TB4_HOME/.claude/CLAUDE.md"
# Intentionally do NOT create the destination file — it must remain absent

TB4_OUT=$(
  export HOME="$TB4_HOME" DRY_RUN=1
  source "$COMMON"
  write_managed_block "$TB4_DEST" "$UB_START" "$UB_END" "$TB4_SRC"
) 2>&1

if [ ! -e "$TB4_DEST" ]; then
  pass "write_managed_block: no destination file created or modified in dry-run"
else
  fail "write_managed_block: dry-run should not create or modify the destination file"
fi

case "$TB4_OUT" in
  *"[dry-run]"*) pass "write_managed_block: dry-run log output present" ;;
  *) fail "write_managed_block: dry-run should produce [dry-run] log lines (got: $TB4_OUT)" ;;
esac

rm -rf "$TB4_HOME"; rm -f "$TB4_SRC"

# T2.5 — no-touch foreign markers
TB5_HOME=$(new_home)
TB5_SRC=$(make_block "NEW-CONTENT-B5")
TB5_DEST="$TB5_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$TB5_DEST")"
cat > "$TB5_DEST" <<EOF
preamble line
<!-- gentle-ai:sdd-orchestrator -->
gentle-ai sdd-orchestrator content line 1
gentle-ai sdd-orchestrator content line 2
<!-- /gentle-ai:sdd-orchestrator -->
middle line
$UB_START
OLD-BLOCK-B5
$UB_END
trailing line
EOF

# Snapshot the gentle-ai block
GENTLE_BEFORE_B5=$(awk '/<!-- gentle-ai:sdd-orchestrator -->/{found=1} found{print} /<!-- \/gentle-ai:sdd-orchestrator -->/{found=0}' "$TB5_DEST")

(
  export HOME="$TB5_HOME" DRY_RUN=0
  source "$COMMON"
  write_managed_block "$TB5_DEST" "$UB_START" "$UB_END" "$TB5_SRC"
) >/dev/null 2>&1

GENTLE_AFTER_B5=$(awk '/<!-- gentle-ai:sdd-orchestrator -->/{found=1} found{print} /<!-- \/gentle-ai:sdd-orchestrator -->/{found=0}' "$TB5_DEST")

if [ "$GENTLE_BEFORE_B5" = "$GENTLE_AFTER_B5" ]; then
  pass "write_managed_block: gentle-ai:sdd-orchestrator block unchanged after upsert"
else
  fail "write_managed_block: gentle-ai:sdd-orchestrator block was modified (should be untouched)"
fi

if grep -q 'NEW-CONTENT-B5' "$TB5_DEST" 2>/dev/null; then
  pass "write_managed_block: managed block updated with new content"
else
  fail "write_managed_block: managed block was not updated"
fi

rm -rf "$TB5_HOME"; rm -f "$TB5_SRC"

# T2.6 — orphaned start marker (no matching end marker) -> refuse, file unchanged
TB6_HOME=$(new_home)
TB6_SRC=$(make_block "NEW-CONTENT-B6")
TB6_DEST="$TB6_HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$TB6_DEST")"
cat > "$TB6_DEST" <<EOF
preamble line
$UB_START
ORPHANED-CONTENT
trailing line
EOF

cp "$TB6_DEST" "${TB6_DEST}.before"

TB6_OUT=$(
  export HOME="$TB6_HOME" DRY_RUN=0
  source "$COMMON"
  write_managed_block "$TB6_DEST" "$UB_START" "$UB_END" "$TB6_SRC" 2>&1
)
TB6_EXIT=$?

[ "$TB6_EXIT" -ne 0 ] && pass "write_managed_block: orphaned start marker returns non-zero" || fail "write_managed_block: orphaned start marker should return non-zero"

case "$TB6_OUT" in
  *"unbalanced"*"marker"*) pass "write_managed_block: orphaned start marker prints a clear error naming the markers" ;;
  *) fail "write_managed_block: expected an unbalanced-markers error message (got: $TB6_OUT)" ;;
esac

if cmp -s "${TB6_DEST}.before" "$TB6_DEST"; then
  pass "write_managed_block: orphaned start marker leaves the file unchanged"
else
  fail "write_managed_block: orphaned start marker should not modify the file"
fi

rm -rf "$TB6_HOME"; rm -f "$TB6_SRC"

# ---------------------------------------------------------------------------
# ensure_symlink() — create, idempotent re-link, warn-and-skip on non-symlink
# Moved from bootstrap.sh into common.sh (canonical shared seam).
# ---------------------------------------------------------------------------

# T-ES1: creates the symlink when the link path is absent
TES1_HOME=$(new_home)
TES1_TARGET="$TES1_HOME/target-file"
TES1_LINK="$TES1_HOME/.local/bin/agent-stack"
printf 'target content\n' > "$TES1_TARGET"

(
  export HOME="$TES1_HOME" DRY_RUN=0
  source "$COMMON"
  ensure_symlink "$TES1_TARGET" "$TES1_LINK"
) >/dev/null 2>&1

if [ -L "$TES1_LINK" ] && [ "$(readlink "$TES1_LINK")" = "$TES1_TARGET" ]; then
  pass "ensure_symlink: creates a symlink pointing at target"
else
  fail "ensure_symlink: should create a symlink pointing at $TES1_TARGET"
fi

rm -rf "$TES1_HOME"

# T-ES2: idempotent re-run — second call on an existing symlink stays a
# symlink pointing at the (possibly updated) target, and does not error
TES2_HOME=$(new_home)
TES2_TARGET="$TES2_HOME/target-file"
TES2_LINK="$TES2_HOME/.local/bin/agent-stack"
printf 'target content\n' > "$TES2_TARGET"

(
  export HOME="$TES2_HOME" DRY_RUN=0
  source "$COMMON"
  ensure_symlink "$TES2_TARGET" "$TES2_LINK"
  ensure_symlink "$TES2_TARGET" "$TES2_LINK"
) >/dev/null 2>&1
TES2_EXIT=$?

[ "$TES2_EXIT" = "0" ] && pass "ensure_symlink: second run on existing symlink exits 0" || fail "ensure_symlink: second run should exit 0, got $TES2_EXIT"

if [ -L "$TES2_LINK" ] && [ "$(readlink "$TES2_LINK")" = "$TES2_TARGET" ]; then
  pass "ensure_symlink: idempotent re-run keeps symlink pointing at target"
else
  fail "ensure_symlink: idempotent re-run should keep symlink pointing at $TES2_TARGET"
fi

rm -rf "$TES2_HOME"

# T-ES3: warns and skips when the link path exists as a non-symlink
TES3_HOME=$(new_home)
TES3_TARGET="$TES3_HOME/target-file"
TES3_LINK="$TES3_HOME/.local/bin/agent-stack"
printf 'target content\n' > "$TES3_TARGET"
mkdir -p "$(dirname "$TES3_LINK")"
printf 'pre-existing real file\n' > "$TES3_LINK"

TES3_OUT=$(
  export HOME="$TES3_HOME" DRY_RUN=0
  source "$COMMON"
  ensure_symlink "$TES3_TARGET" "$TES3_LINK"
) 2>&1

case "$TES3_OUT" in
  *"warning"*"$TES3_LINK"*) pass "ensure_symlink: warns when link path exists as a non-symlink" ;;
  *) fail "ensure_symlink: should warn when link path exists as a non-symlink (got: $TES3_OUT)" ;;
esac

if [ ! -L "$TES3_LINK" ] && grep -q 'pre-existing real file' "$TES3_LINK" 2>/dev/null; then
  pass "ensure_symlink: leaves pre-existing non-symlink file untouched"
else
  fail "ensure_symlink: should leave the pre-existing non-symlink file untouched"
fi

rm -rf "$TES3_HOME"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
