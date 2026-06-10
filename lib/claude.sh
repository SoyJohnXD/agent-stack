#!/usr/bin/env bash
# lib/claude.sh — claude-hooks phase: install agent-stack hook scripts and
# wire them into ~/.claude/settings.json
[ "${_CLAUDE_SH_LOADED:-}" = "1" ] && return 0
_CLAUDE_SH_LOADED=1

# Source directory resolved relative to repo root. Overridable via env so
# tests can point at a fixture without touching the real hooks/ dir.
: "${CLAUDE_HOOKS_SRC_DIR:=$(dirname "$(dirname "${BASH_SOURCE[0]}")")/hooks}"

CLAUDE_HOOK_SCRIPTS="check-plan-contract.sh clean-code-gate.sh skill-registry-refresh.sh"

# ---------------------------------------------------------------------------
# claude_hooks_dir / claude_settings_file — HOME-relative destination paths
# ---------------------------------------------------------------------------
claude_hooks_dir() {
  printf '%s/.claude/hooks' "$HOME"
}

claude_settings_file() {
  printf '%s/.claude/settings.json' "$HOME"
}

# ---------------------------------------------------------------------------
# install_claude_hook_scripts — copy hooks/*.sh into ~/.claude/hooks/,
# preserving the executable bit. DRY_RUN gated.
# ---------------------------------------------------------------------------
install_claude_hook_scripts() {
  local dest_dir
  dest_dir=$(claude_hooks_dir)

  if [ "${DRY_RUN:-0}" = "1" ]; then
    local script
    for script in $CLAUDE_HOOK_SCRIPTS; do
      printf '[dry-run] would install %s/%s\n' "$dest_dir" "$script"
    done
    return 0
  fi

  mkdir -p "$dest_dir"

  local script
  for script in $CLAUDE_HOOK_SCRIPTS; do
    cp "$CLAUDE_HOOKS_SRC_DIR/$script" "$dest_dir/$script"
    chmod +x "$dest_dir/$script"
  done
}

# ---------------------------------------------------------------------------
# claude_settings_merge_filter — jq filter wiring the 3 hooks into
# ~/.claude/settings.json without clobbering unrelated keys.
#
#   PreToolUse (matcher ExitPlanMode) -> check-plan-contract.sh
#   Stop                              -> clean-code-gate.sh
#   UserPromptSubmit                  -> swap existing skill-registry refresh
#                                         command for skill-registry-refresh.sh
#
# Idempotent: re-running the filter on its own output is a no-op.
# ---------------------------------------------------------------------------
claude_settings_merge_filter() {
  cat <<'JQ'
.hooks //= {} |
.hooks.PreToolUse //= [] |
.hooks.PreToolUse |= (
  if any(.[]; .matcher == "ExitPlanMode") then .
  else . + [{"matcher": "ExitPlanMode", "hooks": [{"type": "command", "command": ($hooksDir + "/check-plan-contract.sh")}]}]
  end
) |
.hooks.Stop //= [] |
.hooks.Stop |= (
  if any(.[]; (.hooks // []) | any(.command? // "" | test("clean-code-gate.sh"))) then .
  else . + [{"matcher": "", "hooks": [{"type": "command", "command": ($hooksDir + "/clean-code-gate.sh")}]}]
  end
) |
.hooks.UserPromptSubmit |= (
  (. // [])
  # Convert any raw gentle-ai skill-registry refresh command (or a previously
  # converted one) to point at our skill-registry-refresh.sh.
  #
  # The skill-registry-refresh.sh check is anchored to a path component
  # (preceded by "/") so it only matches commands that INVOKE the script
  # (e.g. "/home/user/.claude/hooks/skill-registry-refresh.sh"), not
  # arbitrary commands that merely mention the filename mid-string
  # (e.g. "echo skill-registry-refresh.sh deprecated && /opt/custom.sh").
  | map(
    .hooks |= map(
      if (.command? // "" | test("skill-registry refresh|/skill-registry-refresh\\.sh")) then
        .command = ($hooksDir + "/skill-registry-refresh.sh")
      else . end
    )
  )
  # Dedupe: gentle-ai re-appends its raw entry on every sync, and the
  # conversion above turns each one into another skill-registry-refresh.sh
  # hook. Keep only the FIRST such hook across the whole array (and drop
  # entries that become empty), so the file stays bounded at one entry no
  # matter how many times agent-stack and gentle-ai sync run.
  | reduce .[] as $entry (
      {seen: false, out: []};
      ($entry.hooks // []) as $hooks
      | reduce $hooks[] as $hook (
          {seen: .seen, kept: []};
          if (.seen | not) and ($hook.command? // "" | test("/skill-registry-refresh\\.sh")) then
            {seen: true, kept: (.kept + [$hook])}
          elif ($hook.command? // "" | test("/skill-registry-refresh\\.sh")) then
            .
          else
            {seen: .seen, kept: (.kept + [$hook])}
          end
        ) as $reduced
      | {
          seen: $reduced.seen,
          out: (
            if ($reduced.kept | length) > 0 then
              .out + [($entry | .hooks = $reduced.kept)]
            else .out end
          )
        }
    )
  | .out
)
JQ
}

# ---------------------------------------------------------------------------
# write_claude_settings_hooks — apply claude_settings_merge_filter to
# ~/.claude/settings.json. DRY_RUN gated. Creates an empty settings.json
# ({}) if absent.
# ---------------------------------------------------------------------------
write_claude_settings_hooks() {
  local target hooks_dir tmp dir
  target=$(claude_settings_file)
  hooks_dir=$(claude_hooks_dir)

  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '[dry-run] would wire claude hooks into %s\n' "$target"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  [ -e "$target" ] || printf '{}' > "$target"

  if ! jq empty "$target" >/dev/null 2>&1; then
    printf 'ERROR: %s is not valid JSON; not modified — fix it manually\n' "$target" >&2
    return 1
  fi

  dir=$(dirname "$target")
  tmp=$(mktemp "$dir/.agent-stack-upsert.XXXXXX")
  trap 'rm -f "$tmp"' RETURN

  if ! jq --arg hooksDir "$hooks_dir" "$(claude_settings_merge_filter)" "$target" > "$tmp" 2>/dev/null; then
    printf 'ERROR: %s has an unexpected shape; not modified — fix it manually\n' "$target" >&2
    return 1
  fi

  mv "$tmp" "$target"
  trap - RETURN
}

# ---------------------------------------------------------------------------
# phase_claude_hooks — public entry point called by the dispatcher / run_sync
# ---------------------------------------------------------------------------
phase_claude_hooks() {
  log_start "claude-hooks"

  install_claude_hook_scripts
  write_claude_settings_hooks

  log_finish "claude-hooks"
}
