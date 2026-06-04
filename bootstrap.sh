#!/usr/bin/env bash
# bootstrap.sh — install and configure all agents from scratch
# Usage: bash bootstrap.sh [--dry-run] [--yes] [--skip-codex] [--with-claude]
# Safe to pipe from curl: bash <(curl -fsSL https://raw.githubusercontent.com/SoyJohnXD/agent-stack/main/bootstrap.sh)
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve lib/common.sh: use local copy if run from inside the repo, else
# self-clone agent-stack to ~/.agent-stack first.
# ---------------------------------------------------------------------------
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SELF_DIR="$(dirname "$SELF")"
AGENT_STACK_REMOTE="https://github.com/SoyJohnXD/agent-stack.git"
AGENT_STACK_LOCAL="${HOME}/.agent-stack"

# Minimal inline run() for the self-clone step only (before lib/common.sh is sourced)
_DRY_RUN_EARLY="${DRY_RUN:-0}"
_run_early() {
  if [ "$_DRY_RUN_EARLY" = "1" ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

if [ -f "$SELF_DIR/lib/common.sh" ]; then
  # Running from inside the repo clone (subcommand path or local dev)
  source "$SELF_DIR/lib/common.sh"
else
  # curl-pipe path: self-clone agent-stack, then source from there
  if [ -d "$AGENT_STACK_LOCAL/.git" ]; then
    _run_early git -C "$AGENT_STACK_LOCAL" pull origin main
  else
    _run_early git clone --branch main "$AGENT_STACK_REMOTE" "$AGENT_STACK_LOCAL"
  fi
  source "$AGENT_STACK_LOCAL/lib/common.sh"
fi

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
SKIP_CODEX="${SKIP_CODEX:-0}"
WITH_CLAUDE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --yes)        ASSUME_YES=1 ;;
    --skip-codex) SKIP_CODEX=1 ;;
    --with-claude) WITH_CLAUDE=1 ;;
  esac
done
export DRY_RUN ASSUME_YES SKIP_CODEX

# ---------------------------------------------------------------------------
# detect_platform — sets PLATFORM_OS (Linux|Darwin) and PLATFORM_ARCH (x86_64|arm64)
# Uses uname -s and uname -m. Defaults to Linux/x86_64 on unknown systems.
# WSL2 is Linux (correct: Linux x86_64 gum binary works there).
# ---------------------------------------------------------------------------
PLATFORM_OS=""
PLATFORM_ARCH=""

detect_platform() {
  case "$(uname -s)" in
    Darwin) PLATFORM_OS="Darwin" ;;
    Linux)  PLATFORM_OS="Linux"  ;;
    *)      PLATFORM_OS="Linux"  ;;  # safe default for unknown/WSL edge cases
  esac
  case "$(uname -m)" in
    arm64|aarch64) PLATFORM_ARCH="arm64"  ;;
    *)             PLATFORM_ARCH="x86_64" ;;
  esac
}

# ---------------------------------------------------------------------------
# gum_latest_version — echoes the latest gum version tag (no v prefix).
# Queries GitHub API; falls back to GUM_FALLBACK_VERSION if unavailable.
# ---------------------------------------------------------------------------
GUM_FALLBACK_VERSION="0.17.0"

gum_latest_version() {
  local ver
  ver=$(curl -fsSL https://api.github.com/repos/charmbracelet/gum/releases/latest 2>/dev/null \
    | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
  if [ -z "$ver" ]; then
    ver="$GUM_FALLBACK_VERSION"
  fi
  printf '%s' "$ver"
}

# ---------------------------------------------------------------------------
# install_gum — best-effort; returns 0 on failure
# ---------------------------------------------------------------------------
install_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  printf '>>> Installing gum (interactive menu helper)...\n'

  # macOS/Linux — brew (primary path; unchanged)
  if command -v brew >/dev/null 2>&1; then
    run brew install gum && return 0 || true
  fi

  # Debian/Ubuntu
  if command -v apt-get >/dev/null 2>&1; then
    run apt-get install -y gum 2>/dev/null && return 0 || true
  fi

  # RHEL/Fedora
  if command -v yum >/dev/null 2>&1; then
    run yum install -y gum 2>/dev/null && return 0 || true
  fi

  # Arch
  if command -v pacman >/dev/null 2>&1; then
    run pacman -S --noconfirm gum 2>/dev/null && return 0 || true
  fi

  # GitHub binary fallback — platform-aware versioned URL
  # gum assets use: gum_<VERSION>_<OS>_<ARCH>.tar.gz  (OS=Darwin|Linux, ARCH=arm64|x86_64)
  # The release tag path uses v<VERSION>; the filename does NOT.
  if command -v curl >/dev/null 2>&1; then
    detect_platform
    local gum_ver; gum_ver=$(gum_latest_version)
    local gum_url="https://github.com/charmbracelet/gum/releases/download/v${gum_ver}/gum_${gum_ver}_${PLATFORM_OS}_${PLATFORM_ARCH}.tar.gz"
    local gum_tmp; gum_tmp=$(mktemp -d)
    run curl -fsSL "$gum_url" -o "$gum_tmp/gum.tar.gz" 2>/dev/null \
      && run tar -xzf "$gum_tmp/gum.tar.gz" -C "$gum_tmp" 2>/dev/null \
      && run mkdir -p "${HOME}/.local/bin" \
      && run mv "$gum_tmp/gum" "${HOME}/.local/bin/gum" 2>/dev/null \
      && return 0 || true
    rm -rf "$gum_tmp" 2>/dev/null || true
  fi

  printf 'warning: gum not available; interactive menu will fall back to usage output\n'
  return 0
}

# ---------------------------------------------------------------------------
# ensure_symlink <target> <link>
# Creates or updates a symlink. Idempotent.
# ---------------------------------------------------------------------------
ensure_symlink() {
  local target="$1"
  local link="$2"
  local link_dir; link_dir="$(dirname "$link")"

  run mkdir -p "$link_dir"

  if [ -L "$link" ]; then
    run ln -sf "$target" "$link"
  elif [ -e "$link" ]; then
    printf 'warning: %s exists and is not a symlink; skipping\n' "$link"
  else
    run ln -s "$target" "$link"
  fi
}

# ---------------------------------------------------------------------------
# print_auth_steps — what to do after bootstrap completes
# ---------------------------------------------------------------------------
print_auth_steps() {
  printf '\n=== Bootstrap complete! ===\n'
  printf '\nManual auth steps:\n'
  printf '  claude    : claude login\n'
  printf '  codex     : codex login\n'
  printf '  opencode  : opencode login\n'
  printf '  gentle-ai : gentle-ai login\n'
  printf '\nUsage:\n'
  printf '  agent-stack          # interactive menu\n'
  printf '  agent-stack all      # update everything non-interactively\n'
  printf '  agent-stack --help   # full usage\n'
  printf '\nIf agent-stack is not found, add ~/.local/bin to PATH (zsh):\n'
  printf '  export PATH="$HOME/.local/bin:$PATH"\n'
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  log_start "bootstrap"

  # Step 1: gum (best-effort)
  install_gum

  # Step 2: ensure agent-stack repo + entrypoint symlink
  ensure_repo "$AGENT_STACK_LOCAL" "$AGENT_STACK_REMOTE" "main"
  ensure_symlink "$AGENT_STACK_LOCAL/agent-stack" "${HOME}/.local/bin/agent-stack"

  # Step 3: ensure codex repo
  local codex_remote="https://github.com/SoyJohnXD/codex-sdd-gentle-installer.git"
  local codex_local="$AGENT_STACK_LOCAL/repos/codex-sdd-gentle-installer"
  ensure_repo "$codex_local" "$codex_remote" "main"

  # Step 4: ensure overlay repo
  local overlay_remote="https://github.com/SoyJohnXD/clean-code-lab.git"
  local overlay_local="$AGENT_STACK_LOCAL/repos/clean-code-lab"
  ensure_repo "$overlay_local" "$overlay_remote" "main"

  # Step 5: install codex (unless --skip-codex)
  if [ "${SKIP_CODEX}" = "1" ]; then
    printf '[skip] codex install (--skip-codex)\n'
  else
    local install_full="$codex_local/install-full.sh"
    if [ -f "$install_full" ]; then
      if [ "$ASSUME_YES" = "1" ]; then
        run "$install_full" --yes
      else
        run "$install_full"
      fi
    else
      printf '[skip] install-full.sh not found in codex repo\n'
    fi
  fi

  # Step 6: intent-overlay install
  local overlay_script="$overlay_local/overlay/intent-overlay"
  if command -v intent-overlay >/dev/null 2>&1; then
    run intent-overlay install
  elif [ -f "$overlay_script" ]; then
    run "$overlay_script" install
  else
    printf '[skip] intent-overlay not found\n'
  fi

  # Step 7: apply Gentleman-CO persona override to all three agent configs
  source "$AGENT_STACK_LOCAL/lib/persona.sh"
  phase_persona

  # Step 8: Claude Code install (opt-in only)
  if [ "$WITH_CLAUDE" = "1" ]; then
    printf '>>> Installing Claude Code...\n'
    run bash -c "curl -fsSL https://claude.ai/install.sh | bash"
  fi

  # Step 9: symlink to entrypoint (refreshed)
  ensure_symlink "$AGENT_STACK_LOCAL/agent-stack" "${HOME}/.local/bin/agent-stack"

  if [ "$DRY_RUN" = "0" ]; then
    print_auth_steps
  fi

  log_finish "bootstrap"
}

[ "${BASH_SOURCE[0]}" = "$0" ] && main "$@"
