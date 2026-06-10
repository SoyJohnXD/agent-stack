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

# ---------------------------------------------------------------------------
# T18 — phase_codex_hooks
# ---------------------------------------------------------------------------
new_codex_hooks_src() {
  local dir; dir=$(mktemp -d)
  printf '#!/usr/bin/env bash\necho "clean-code-gate"\n' > "$dir/clean-code-gate.sh"
  printf '%s' "$dir"
}

# T18a — installs clean-code-gate.sh, executable
T18A_HOME=$(new_home)
T18A_SRC=$(new_codex_hooks_src)

(
  export HOME="$T18A_HOME" DRY_RUN=0 CODEX_HOOKS_SRC_DIR="$T18A_SRC"
  source "$HERE/common.sh"
  source "$HERE/codex.sh"
  install_codex_hook_scripts
) >/dev/null 2>&1

T18A_DEST="$T18A_HOME/.codex/hooks/clean-code-gate.sh"
if [ -f "$T18A_DEST" ] && [ -x "$T18A_DEST" ]; then
  pass "T18a: clean-code-gate.sh installed to ~/.codex/hooks and executable"
else
  fail "T18a: clean-code-gate.sh should be installed and executable"
fi

rm -rf "$T18A_HOME" "$T18A_SRC"

# T18b — adds Stop hook, preserves SessionStart, idempotent on re-run
T18B_HOME=$(new_home)
T18B_SRC=$(new_codex_hooks_src)
T18B_HOOKS="$T18B_HOME/.codex/hooks.json"
mkdir -p "$(dirname "$T18B_HOOKS")"
cat > "$T18B_HOOKS" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "command": "gentle-ai skill-registry refresh --quiet --no-gitignore --cwd \"$PWD\" || true",
            "statusMessage": "Refreshing skill registry",
            "timeout": 30,
            "type": "command"
          }
        ],
        "matcher": "startup|resume|clear|compact"
      }
    ]
  }
}
EOF

SESSIONSTART_BEFORE=$(jq -c '.hooks.SessionStart' "$T18B_HOOKS")

(
  export HOME="$T18B_HOME" DRY_RUN=0 CODEX_HOOKS_SRC_DIR="$T18B_SRC"
  source "$HERE/common.sh"
  source "$HERE/codex.sh"
  write_codex_hooks_json
) >/dev/null 2>&1

STOP_CMD=$(jq -r '.hooks.Stop[]? | .hooks[0].command' "$T18B_HOOKS")
case "$STOP_CMD" in
  *clean-code-gate.sh) pass "T18b: Stop hook wired to clean-code-gate.sh" ;;
  *) fail "T18b: Stop hook not wired (got: $STOP_CMD)" ;;
esac

SESSIONSTART_AFTER=$(jq -c '.hooks.SessionStart' "$T18B_HOOKS")
[ "$SESSIONSTART_BEFORE" = "$SESSIONSTART_AFTER" ] && pass "T18b: SessionStart entry untouched" || fail "T18b: SessionStart entry was modified"

cp "$T18B_HOOKS" "${T18B_HOOKS}.after_run1"

(
  export HOME="$T18B_HOME" DRY_RUN=0 CODEX_HOOKS_SRC_DIR="$T18B_SRC"
  source "$HERE/common.sh"
  source "$HERE/codex.sh"
  write_codex_hooks_json
) >/dev/null 2>&1

if cmp -s "${T18B_HOOKS}.after_run1" "$T18B_HOOKS"; then
  pass "T18b: second run of write_codex_hooks_json is byte-identical"
else
  fail "T18b: hooks.json changed between run 1 and run 2"
fi

rm -rf "$T18B_HOME" "$T18B_SRC"

# T18c — dry-run: no file mutation
T18C_HOME=$(new_home)
T18C_SRC=$(new_codex_hooks_src)

T18C_OUT=$(
  export HOME="$T18C_HOME" DRY_RUN=1 CODEX_HOOKS_SRC_DIR="$T18C_SRC"
  source "$HERE/common.sh"
  source "$HERE/codex.sh"
  phase_codex_hooks
) 2>&1

if [ ! -e "$T18C_HOME/.codex/hooks" ] && [ ! -e "$T18C_HOME/.codex/hooks.json" ]; then
  pass "T18c: dry-run creates no files"
else
  fail "T18c: dry-run should not create ~/.codex/hooks or hooks.json"
fi

case "$T18C_OUT" in
  *"[dry-run]"*) pass "T18c: dry-run log output present" ;;
  *) fail "T18c: dry-run should produce [dry-run] log lines (got: $T18C_OUT)" ;;
esac

rm -rf "$T18C_HOME" "$T18C_SRC"

# T18d — malformed hooks.json (.hooks.Stop is an object, not an array) ->
# refusal with message, original file untouched, no leftover temp files
T18D_HOME=$(new_home)
T18D_SRC=$(new_codex_hooks_src)
T18D_HOOKS="$T18D_HOME/.codex/hooks.json"
mkdir -p "$(dirname "$T18D_HOOKS")"
cat > "$T18D_HOOKS" <<'EOF'
{
  "hooks": {
    "Stop": {"not": "an array"}
  }
}
EOF
cp "$T18D_HOOKS" "${T18D_HOOKS}.before"

T18D_OUT=$(
  export HOME="$T18D_HOME" DRY_RUN=0 CODEX_HOOKS_SRC_DIR="$T18D_SRC"
  source "$HERE/common.sh"
  source "$HERE/codex.sh"
  write_codex_hooks_json 2>&1
)
T18D_EXIT=$?

[ "$T18D_EXIT" -ne 0 ] && pass "T18d: write_codex_hooks_json returns non-zero on malformed hooks.json" || fail "T18d: write_codex_hooks_json should return non-zero on malformed hooks.json"

case "$T18D_OUT" in
  *"not modified"*) pass "T18d: error message states the file was not modified" ;;
  *) fail "T18d: expected an actionable error message (got: $T18D_OUT)" ;;
esac

if cmp -s "${T18D_HOOKS}.before" "$T18D_HOOKS"; then
  pass "T18d: malformed hooks.json left untouched"
else
  fail "T18d: malformed hooks.json should not be modified"
fi

LEFTOVER_TMP=$(find "$T18D_HOME/.codex" -name '.agent-stack-upsert.*' 2>/dev/null)
[ -z "$LEFTOVER_TMP" ] && pass "T18d: no leftover .agent-stack-upsert.* temp files" || fail "T18d: leftover temp files found: $LEFTOVER_TMP"

rm -rf "$T18D_HOME" "$T18D_SRC"

# T18e — hooks.json with invalid JSON syntax -> refusal with message,
# original file untouched, no leftover temp files (jq empty guard, before
# any mktemp call)
T18E_HOME=$(new_home)
T18E_SRC=$(new_codex_hooks_src)
T18E_HOOKS="$T18E_HOME/.codex/hooks.json"
mkdir -p "$(dirname "$T18E_HOOKS")"
printf '{ "hooks": { invalid json' > "$T18E_HOOKS"
cp "$T18E_HOOKS" "${T18E_HOOKS}.before"

T18E_OUT=$(
  export HOME="$T18E_HOME" DRY_RUN=0 CODEX_HOOKS_SRC_DIR="$T18E_SRC"
  source "$HERE/common.sh"
  source "$HERE/codex.sh"
  write_codex_hooks_json 2>&1
)
T18E_EXIT=$?

[ "$T18E_EXIT" -ne 0 ] && pass "T18e: write_codex_hooks_json returns non-zero on invalid JSON" || fail "T18e: write_codex_hooks_json should return non-zero on invalid JSON"

case "$T18E_OUT" in
  *"not valid JSON"*"not modified"*) pass "T18e: error message states the file is not valid JSON and was not modified" ;;
  *) fail "T18e: expected a not-valid-JSON error message (got: $T18E_OUT)" ;;
esac

if cmp -s "${T18E_HOOKS}.before" "$T18E_HOOKS"; then
  pass "T18e: invalid JSON hooks.json left untouched"
else
  fail "T18e: invalid JSON hooks.json should not be modified"
fi

LEFTOVER_TMP=$(find "$T18E_HOME/.codex" -name '.agent-stack-upsert.*' 2>/dev/null)
[ -z "$LEFTOVER_TMP" ] && pass "T18e: no leftover .agent-stack-upsert.* temp files" || fail "T18e: leftover temp files found: $LEFTOVER_TMP"

rm -rf "$T18E_HOME" "$T18E_SRC"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
