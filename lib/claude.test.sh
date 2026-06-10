#!/usr/bin/env bash
# Tests for lib/claude.sh
# Run: bash lib/claude.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

new_home() {
  local h; h=$(mktemp -d); printf '%s' "$h"
}

# Throwaway hooks/ source dir with the 3 expected scripts (non-executable
# fixtures — install_claude_hook_scripts must set the exec bit itself).
new_hooks_src() {
  local dir; dir=$(mktemp -d)
  for script in check-plan-contract.sh clean-code-gate.sh skill-registry-refresh.sh; do
    printf '#!/usr/bin/env bash\necho "%s"\n' "$script" > "$dir/$script"
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# T1 — install_claude_hook_scripts copies all 3 scripts, executable
# ---------------------------------------------------------------------------
T1_HOME=$(new_home)
T1_SRC=$(new_hooks_src)

(
  export HOME="$T1_HOME" DRY_RUN=0 CLAUDE_HOOKS_SRC_DIR="$T1_SRC"
  source "$HERE/common.sh"
  source "$HERE/claude.sh"
  install_claude_hook_scripts
) >/dev/null 2>&1

T1_DEST="$T1_HOME/.claude/hooks"
ALL_PRESENT=1
ALL_EXEC=1
for script in check-plan-contract.sh clean-code-gate.sh skill-registry-refresh.sh; do
  [ -f "$T1_DEST/$script" ] || ALL_PRESENT=0
  [ -x "$T1_DEST/$script" ] || ALL_EXEC=0
done

[ "$ALL_PRESENT" = "1" ] && pass "T1: all 3 hook scripts copied to ~/.claude/hooks" || fail "T1: not all hook scripts were copied"
[ "$ALL_EXEC" = "1" ] && pass "T1: copied hook scripts are executable" || fail "T1: copied hook scripts should be executable"

rm -rf "$T1_HOME" "$T1_SRC"

# ---------------------------------------------------------------------------
# T2 — write_claude_settings_hooks wires PreToolUse/Stop/UserPromptSubmit,
# preserves unrelated keys, swaps the existing skill-registry command
# ---------------------------------------------------------------------------
T2_HOME=$(new_home)
T2_SRC=$(new_hooks_src)
T2_SETTINGS="$T2_HOME/.claude/settings.json"
mkdir -p "$(dirname "$T2_SETTINGS")"
cat > "$T2_SETTINGS" <<'EOF'
{
  "permissions": {
    "deny": ["Bash(rm -rf /)"],
    "defaultMode": "bypassPermissions"
  },
  "model": "claude-fable-5[1m]",
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "gentle-ai skill-registry refresh --quiet --no-gitignore --cwd \"${CLAUDE_PROJECT_DIR:-$PWD}\" || true"
          }
        ]
      }
    ]
  },
  "outputStyle": "Gentleman"
}
EOF

(
  export HOME="$T2_HOME" DRY_RUN=0 CLAUDE_HOOKS_SRC_DIR="$T2_SRC"
  source "$HERE/common.sh"
  source "$HERE/claude.sh"
  write_claude_settings_hooks
) >/dev/null 2>&1

PRETOOLUSE=$(jq -r '.hooks.PreToolUse[]? | select(.matcher == "ExitPlanMode") | .hooks[0].command' "$T2_SETTINGS")
case "$PRETOOLUSE" in
  *check-plan-contract.sh) pass "T2: PreToolUse[ExitPlanMode] wired to check-plan-contract.sh" ;;
  *) fail "T2: PreToolUse[ExitPlanMode] not wired (got: $PRETOOLUSE)" ;;
esac

STOP_CMD=$(jq -r '.hooks.Stop[]? | .hooks[0].command' "$T2_SETTINGS")
case "$STOP_CMD" in
  *clean-code-gate.sh) pass "T2: Stop wired to clean-code-gate.sh" ;;
  *) fail "T2: Stop not wired (got: $STOP_CMD)" ;;
esac

UPS_CMD=$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$T2_SETTINGS")
case "$UPS_CMD" in
  *skill-registry-refresh.sh) pass "T2: UserPromptSubmit command swapped to skill-registry-refresh.sh" ;;
  *) fail "T2: UserPromptSubmit command not swapped (got: $UPS_CMD)" ;;
esac

UPS_MATCHER=$(jq -r '.hooks.UserPromptSubmit[0].matcher' "$T2_SETTINGS")
[ "$UPS_MATCHER" = "" ] && pass "T2: UserPromptSubmit matcher/event preserved" || fail "T2: UserPromptSubmit matcher changed (got: $UPS_MATCHER)"

DENY_RULE=$(jq -r '.permissions.deny[0]' "$T2_SETTINGS")
[ "$DENY_RULE" = "Bash(rm -rf /)" ] && pass "T2: unrelated permissions key preserved" || fail "T2: permissions.deny was clobbered"

OUTPUT_STYLE=$(jq -r '.outputStyle' "$T2_SETTINGS")
[ "$OUTPUT_STYLE" = "Gentleman" ] && pass "T2: unrelated outputStyle key preserved" || fail "T2: outputStyle was clobbered"

# ---------------------------------------------------------------------------
# T3 — second run is byte-identical (idempotent)
# ---------------------------------------------------------------------------
cp "$T2_SETTINGS" "${T2_SETTINGS}.after_run1"

(
  export HOME="$T2_HOME" DRY_RUN=0 CLAUDE_HOOKS_SRC_DIR="$T2_SRC"
  source "$HERE/common.sh"
  source "$HERE/claude.sh"
  write_claude_settings_hooks
) >/dev/null 2>&1

if cmp -s "${T2_SETTINGS}.after_run1" "$T2_SETTINGS"; then
  pass "T3: second run of write_claude_settings_hooks is byte-identical"
else
  fail "T3: settings.json changed between run 1 and run 2"
fi

rm -rf "$T2_HOME" "$T2_SRC"

# ---------------------------------------------------------------------------
# T4 — dry-run: no file mutation, no hook scripts installed
# ---------------------------------------------------------------------------
T4_HOME=$(new_home)
T4_SRC=$(new_hooks_src)

T4_OUT=$(
  export HOME="$T4_HOME" DRY_RUN=1 CLAUDE_HOOKS_SRC_DIR="$T4_SRC"
  source "$HERE/common.sh"
  source "$HERE/claude.sh"
  phase_claude_hooks
) 2>&1

if [ ! -e "$T4_HOME/.claude/hooks" ] && [ ! -e "$T4_HOME/.claude/settings.json" ]; then
  pass "T4: dry-run creates no files"
else
  fail "T4: dry-run should not create ~/.claude/hooks or settings.json"
fi

case "$T4_OUT" in
  *"[dry-run]"*) pass "T4: dry-run log output present" ;;
  *) fail "T4: dry-run should produce [dry-run] log lines (got: $T4_OUT)" ;;
esac

rm -rf "$T4_HOME" "$T4_SRC"

# ---------------------------------------------------------------------------
# T5 — malformed settings.json (.hooks.PreToolUse is an object, not an
# array) -> refusal with message, original file untouched, no leftover
# temp files
# ---------------------------------------------------------------------------
T5_HOME=$(new_home)
T5_SRC=$(new_hooks_src)
T5_SETTINGS="$T5_HOME/.claude/settings.json"
mkdir -p "$(dirname "$T5_SETTINGS")"
cat > "$T5_SETTINGS" <<'EOF'
{
  "hooks": {
    "PreToolUse": {"not": "an array"}
  }
}
EOF
cp "$T5_SETTINGS" "${T5_SETTINGS}.before"

T5_OUT=$(
  export HOME="$T5_HOME" DRY_RUN=0 CLAUDE_HOOKS_SRC_DIR="$T5_SRC"
  source "$HERE/common.sh"
  source "$HERE/claude.sh"
  write_claude_settings_hooks 2>&1
)
T5_EXIT=$?

[ "$T5_EXIT" -ne 0 ] && pass "T5: write_claude_settings_hooks returns non-zero on malformed settings.json" || fail "T5: write_claude_settings_hooks should return non-zero on malformed settings.json"

case "$T5_OUT" in
  *"not modified"*) pass "T5: error message states the file was not modified" ;;
  *) fail "T5: expected an actionable error message (got: $T5_OUT)" ;;
esac

if cmp -s "${T5_SETTINGS}.before" "$T5_SETTINGS"; then
  pass "T5: malformed settings.json left untouched"
else
  fail "T5: malformed settings.json should not be modified"
fi

LEFTOVER_TMP=$(find "$T5_HOME/.claude" -name '.agent-stack-upsert.*' 2>/dev/null)
[ -z "$LEFTOVER_TMP" ] && pass "T5: no leftover .agent-stack-upsert.* temp files" || fail "T5: leftover temp files found: $LEFTOVER_TMP"

rm -rf "$T5_HOME" "$T5_SRC"

# ---------------------------------------------------------------------------
# T6 — settings.json with invalid JSON syntax -> refusal with message,
# original file untouched, no leftover temp files (jq empty guard, before
# any mktemp call)
# ---------------------------------------------------------------------------
T6_HOME=$(new_home)
T6_SRC=$(new_hooks_src)
T6_SETTINGS="$T6_HOME/.claude/settings.json"
mkdir -p "$(dirname "$T6_SETTINGS")"
printf '{ "hooks": { invalid json' > "$T6_SETTINGS"
cp "$T6_SETTINGS" "${T6_SETTINGS}.before"

T6_OUT=$(
  export HOME="$T6_HOME" DRY_RUN=0 CLAUDE_HOOKS_SRC_DIR="$T6_SRC"
  source "$HERE/common.sh"
  source "$HERE/claude.sh"
  write_claude_settings_hooks 2>&1
)
T6_EXIT=$?

[ "$T6_EXIT" -ne 0 ] && pass "T6: write_claude_settings_hooks returns non-zero on invalid JSON" || fail "T6: write_claude_settings_hooks should return non-zero on invalid JSON"

case "$T6_OUT" in
  *"not valid JSON"*"not modified"*) pass "T6: error message states the file is not valid JSON and was not modified" ;;
  *) fail "T6: expected a not-valid-JSON error message (got: $T6_OUT)" ;;
esac

if cmp -s "${T6_SETTINGS}.before" "$T6_SETTINGS"; then
  pass "T6: invalid JSON settings.json left untouched"
else
  fail "T6: invalid JSON settings.json should not be modified"
fi

LEFTOVER_TMP=$(find "$T6_HOME/.claude" -name '.agent-stack-upsert.*' 2>/dev/null)
[ -z "$LEFTOVER_TMP" ] && pass "T6: no leftover .agent-stack-upsert.* temp files" || fail "T6: leftover temp files found: $LEFTOVER_TMP"

rm -rf "$T6_HOME" "$T6_SRC"

if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
