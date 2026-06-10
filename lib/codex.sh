#!/usr/bin/env bash
# lib/codex.sh — codex phase: pull codex repo + install + mcp-audit
[ "${_CODEX_SH_LOADED:-}" = "1" ] && return 0
_CODEX_SH_LOADED=1

# MANIFEST_FILE must be set by the entrypoint before sourcing
: "${MANIFEST_FILE:=$(dirname "$(dirname "${BASH_SOURCE[0]}")")/repos.manifest}"

# Source directory for hook scripts. Overridable via env so tests can point
# at a fixture without touching the real hooks/ dir.
: "${CODEX_HOOKS_SRC_DIR:=$(dirname "$(dirname "${BASH_SOURCE[0]}")")/hooks}"

CODEX_HOOK_SCRIPTS="clean-code-gate.sh"

phase_codex() {
  log_start "codex"

  local local_path remote branch
  while IFS='|' read -r _name local_path remote branch; do
    _name=$(printf '%s' "$_name" | tr -d ' ')
    local_path=$(printf '%s' "$local_path" | tr -d ' ')
    remote=$(printf '%s' "$remote" | tr -d ' ')
    branch=$(printf '%s' "$branch" | tr -d ' ')
    [ "$_name" = "codex" ] && break
  done < <(parse_manifest "$MANIFEST_FILE")

  ensure_repo "$local_path" "$remote" "$branch"
  run bash "$local_path/install.sh"
  run codex-sdd-sync --mcp-audit
  log_finish "codex"
}

# ---------------------------------------------------------------------------
# codex_hooks_dir / codex_hooks_file — HOME-relative destination paths
# ---------------------------------------------------------------------------
codex_hooks_dir() {
  printf '%s/.codex/hooks' "$HOME"
}

codex_hooks_file() {
  printf '%s/.codex/hooks.json' "$HOME"
}

# ---------------------------------------------------------------------------
# install_codex_hook_scripts — copy hooks/clean-code-gate.sh into
# ~/.codex/hooks/, preserving the executable bit. DRY_RUN gated.
# ---------------------------------------------------------------------------
install_codex_hook_scripts() {
  local dest_dir
  dest_dir=$(codex_hooks_dir)

  if [ "${DRY_RUN:-0}" = "1" ]; then
    local script
    for script in $CODEX_HOOK_SCRIPTS; do
      printf '[dry-run] would install %s/%s\n' "$dest_dir" "$script"
    done
    return 0
  fi

  mkdir -p "$dest_dir"

  local script
  for script in $CODEX_HOOK_SCRIPTS; do
    cp "$CODEX_HOOKS_SRC_DIR/$script" "$dest_dir/$script"
    chmod +x "$dest_dir/$script"
  done
}

# ---------------------------------------------------------------------------
# codex_hooks_merge_filter — jq filter adding a Stop hook for
# clean-code-gate.sh into ~/.codex/hooks.json without touching the existing
# SessionStart entry. Idempotent: re-running on its own output is a no-op.
# ---------------------------------------------------------------------------
codex_hooks_merge_filter() {
  cat <<'JQ'
.hooks //= {} |
.hooks.Stop //= [] |
.hooks.Stop |= (
  if any(.[]; (.hooks // []) | any(.command? // "" | test("clean-code-gate.sh"))) then .
  else . + [{"matcher": "", "hooks": [{"type": "command", "command": ($hooksDir + "/clean-code-gate.sh")}]}]
  end
)
JQ
}

# ---------------------------------------------------------------------------
# write_codex_hooks_json — apply codex_hooks_merge_filter to
# ~/.codex/hooks.json. DRY_RUN gated. Creates an empty hooks.json ({}) if
# absent. Adding/changing hooks changes Codex's trusted_hash, so it will
# re-prompt for hook trust once.
# ---------------------------------------------------------------------------
write_codex_hooks_json() {
  local target hooks_dir tmp dir
  target=$(codex_hooks_file)
  hooks_dir=$(codex_hooks_dir)

  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '[dry-run] would wire codex hooks into %s\n' "$target"
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

  if ! jq --arg hooksDir "$hooks_dir" "$(codex_hooks_merge_filter)" "$target" > "$tmp" 2>/dev/null; then
    printf 'ERROR: %s has an unexpected shape; not modified — fix it manually\n' "$target" >&2
    return 1
  fi

  mv "$tmp" "$target"
  trap - RETURN
}

# ---------------------------------------------------------------------------
# phase_codex_hooks — public entry point called by the dispatcher / run_sync
# ---------------------------------------------------------------------------
phase_codex_hooks() {
  log_start "codex-hooks"

  install_codex_hook_scripts
  write_codex_hooks_json

  printf 'NOTE: ~/.codex/hooks.json changed — Codex will ask to re-trust hooks once (trusted_hash update).\n'

  log_finish "codex-hooks"
}
