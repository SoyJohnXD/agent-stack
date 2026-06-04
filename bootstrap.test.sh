#!/usr/bin/env bash
# Tests for bootstrap.sh
# Run: bash bootstrap.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP="$HERE/bootstrap.sh"
BASH_BIN=$(command -v bash)

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

new_home() {
  local h; h=$(mktemp -d); printf '%s' "$h"
}

# Build a stub bin dir: all external commands record calls and exit 0
# $1 = record file, $2 = optional list of commands to OMIT (space-separated)
new_stub_bin() {
  local record_file="$1"
  local omit="${2:-}"
  local dir; dir=$(mktemp -d)

  for cmd in git gum brew apt-get yum pacman curl; do
    # shellcheck disable=SC2076
    if [[ " $omit " =~ " $cmd " ]]; then
      continue
    fi
    cat > "$dir/$cmd" <<EOF
#!$BASH_BIN
echo "$cmd \$*" >> "$record_file"
exit 0
EOF
    chmod +x "$dir/$cmd"
  done

  # git: simulate clone by creating the target dir
  if [[ ! " $omit " =~ " git " ]]; then
    cat > "$dir/git" <<EOF
#!$BASH_BIN
echo "git \$*" >> "$record_file"
if [ "\${1:-}" = "clone" ]; then
  mkdir -p "\${!#}"
  # put a fake lib/common.sh in the cloned repo
  mkdir -p "\${!#}/lib"
  cp "$HERE/lib/common.sh" "\${!#}/lib/common.sh" 2>/dev/null || true
  cp "$HERE/bootstrap.sh" "\${!#}/bootstrap.sh" 2>/dev/null || true
fi
exit 0
EOF
    chmod +x "$dir/git"
  fi

  # install-full.sh stub
  cat > "$dir/install-full.sh" <<EOF
#!$BASH_BIN
echo "install-full.sh \$*" >> "$record_file"
exit 0
EOF
  chmod +x "$dir/install-full.sh"

  # intent-overlay stub
  cat > "$dir/intent-overlay" <<EOF
#!$BASH_BIN
echo "intent-overlay \$*" >> "$record_file"
exit 0
EOF
  chmod +x "$dir/intent-overlay"

  # claude-installer stub (for --with-claude)
  cat > "$dir/claude-install" <<EOF
#!$BASH_BIN
echo "claude-install \$*" >> "$record_file"
exit 0
EOF
  chmod +x "$dir/claude-install"

  printf '%s' "$dir"
}

# ===========================================================================
# Unit tests (source-mode): detect_platform, gum_latest_version, PATH guidance
# These load bootstrap.sh in isolation — main() is guarded, will not execute.
# ===========================================================================

# ---------------------------------------------------------------------------
# U1.1: detect_platform — Darwin arm64
# ---------------------------------------------------------------------------
(
  # Stub uname before sourcing so detect_platform uses the stub
  uname() { case "$1" in -s) echo "Darwin";; -m) echo "arm64";; esac }
  export -f uname
  # Source bootstrap.sh; main will not execute (source guard)
  # shellcheck disable=SC1090
  source "$BOOTSTRAP" 2>/dev/null || true
  PLATFORM_OS=""; PLATFORM_ARCH=""
  detect_platform
  if [ "$PLATFORM_OS" = "Darwin" ] && [ "$PLATFORM_ARCH" = "arm64" ]; then
    printf 'ok   - detect_platform: Darwin arm64 -> PLATFORM_OS=Darwin PLATFORM_ARCH=arm64\n'
  else
    printf 'FAIL - detect_platform: Darwin arm64 -> expected PLATFORM_OS=Darwin PLATFORM_ARCH=arm64, got PLATFORM_OS=%s PLATFORM_ARCH=%s\n' "$PLATFORM_OS" "$PLATFORM_ARCH"
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# U1.2: detect_platform — Darwin x86_64
# ---------------------------------------------------------------------------
(
  uname() { case "$1" in -s) echo "Darwin";; -m) echo "x86_64";; esac }
  export -f uname
  source "$BOOTSTRAP" 2>/dev/null || true
  PLATFORM_OS=""; PLATFORM_ARCH=""
  detect_platform
  if [ "$PLATFORM_OS" = "Darwin" ] && [ "$PLATFORM_ARCH" = "x86_64" ]; then
    printf 'ok   - detect_platform: Darwin x86_64 -> PLATFORM_OS=Darwin PLATFORM_ARCH=x86_64\n'
  else
    printf 'FAIL - detect_platform: Darwin x86_64 -> expected PLATFORM_OS=Darwin PLATFORM_ARCH=x86_64, got PLATFORM_OS=%s PLATFORM_ARCH=%s\n' "$PLATFORM_OS" "$PLATFORM_ARCH"
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# U1.3: detect_platform — Linux x86_64
# ---------------------------------------------------------------------------
(
  uname() { case "$1" in -s) echo "Linux";; -m) echo "x86_64";; esac }
  export -f uname
  source "$BOOTSTRAP" 2>/dev/null || true
  PLATFORM_OS=""; PLATFORM_ARCH=""
  detect_platform
  if [ "$PLATFORM_OS" = "Linux" ] && [ "$PLATFORM_ARCH" = "x86_64" ]; then
    printf 'ok   - detect_platform: Linux x86_64 -> PLATFORM_OS=Linux PLATFORM_ARCH=x86_64\n'
  else
    printf 'FAIL - detect_platform: Linux x86_64 -> expected PLATFORM_OS=Linux PLATFORM_ARCH=x86_64, got PLATFORM_OS=%s PLATFORM_ARCH=%s\n' "$PLATFORM_OS" "$PLATFORM_ARCH"
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# U2.1: gum_latest_version — returns tag from stubbed curl (no v prefix)
# ---------------------------------------------------------------------------
(
  uname() { case "$1" in -s) echo "Linux";; -m) echo "x86_64";; esac }
  export -f uname
  curl() {
    # Simulate GitHub API response with tag_name
    echo '{"tag_name": "v0.17.0", "name": "v0.17.0"}'
  }
  export -f curl
  source "$BOOTSTRAP" 2>/dev/null || true
  VER=$(gum_latest_version)
  if [ "$VER" = "0.17.0" ]; then
    printf 'ok   - gum_latest_version: stubbed curl returns 0.17.0 (no v prefix)\n'
  else
    printf 'FAIL - gum_latest_version: expected 0.17.0, got %s\n' "$VER"
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# U2.2: gum_latest_version — falls back to GUM_FALLBACK_VERSION when curl fails
# ---------------------------------------------------------------------------
(
  uname() { case "$1" in -s) echo "Linux";; -m) echo "x86_64";; esac }
  export -f uname
  curl() { return 1; }
  export -f curl
  source "$BOOTSTRAP" 2>/dev/null || true
  VER=$(gum_latest_version)
  if [ -n "$VER" ]; then
    printf 'ok   - gum_latest_version: curl failure falls back to GUM_FALLBACK_VERSION (%s)\n' "$VER"
  else
    printf 'FAIL - gum_latest_version: expected fallback version, got empty string\n'
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# U3.1: install_gum URL contains Darwin_arm64 on Darwin arm64 (brew absent)
# ---------------------------------------------------------------------------
(
  uname() { case "$1" in -s) echo "Darwin";; -m) echo "arm64";; esac }
  export -f uname
  # gum not installed
  command() {
    case "$*" in
      "-v gum")  return 1 ;;
      "-v brew") return 1 ;;
      "-v curl") return 0 ;;
      "-v apt-get") return 1 ;;
      "-v yum") return 1 ;;
      "-v pacman") return 1 ;;
      *) builtin command "$@" ;;
    esac
  }
  export -f command
  CAPTURED_URL=""
  curl() {
    for arg in "$@"; do
      case "$arg" in
        https://github.com/charmbracelet/gum*) CAPTURED_URL="$arg" ;;
        https://api.github.com*) echo '{"tag_name": "v0.17.0"}' ; return 0 ;;
      esac
    done
    # For the tar download, return 0 silently (we only care about URL capture)
    return 0
  }
  export -f curl
  tar() { return 0; }
  export -f tar
  mkdir() { builtin mkdir -p "$@" 2>/dev/null || true; }
  export -f mkdir
  mv() { return 0; }
  export -f mv
  source "$BOOTSTRAP" 2>/dev/null || true
  install_gum 2>/dev/null || true
  if printf '%s' "$CAPTURED_URL" | grep -q "Darwin_arm64"; then
    printf 'ok   - install_gum: Darwin arm64 URL contains Darwin_arm64\n'
  else
    printf 'FAIL - install_gum: Darwin arm64 URL should contain Darwin_arm64 (got: %s)\n' "$CAPTURED_URL"
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# U3.2: install_gum URL contains Darwin_x86_64 on Darwin x86_64 (brew absent)
# ---------------------------------------------------------------------------
(
  uname() { case "$1" in -s) echo "Darwin";; -m) echo "x86_64";; esac }
  export -f uname
  command() {
    case "$*" in
      "-v gum")  return 1 ;;
      "-v brew") return 1 ;;
      "-v curl") return 0 ;;
      "-v apt-get") return 1 ;;
      "-v yum") return 1 ;;
      "-v pacman") return 1 ;;
      *) builtin command "$@" ;;
    esac
  }
  export -f command
  CAPTURED_URL=""
  curl() {
    for arg in "$@"; do
      case "$arg" in
        https://github.com/charmbracelet/gum*) CAPTURED_URL="$arg" ;;
        https://api.github.com*) echo '{"tag_name": "v0.17.0"}' ; return 0 ;;
      esac
    done
    return 0
  }
  export -f curl
  tar() { return 0; }
  export -f tar
  mkdir() { builtin mkdir -p "$@" 2>/dev/null || true; }
  export -f mkdir
  mv() { return 0; }
  export -f mv
  source "$BOOTSTRAP" 2>/dev/null || true
  install_gum 2>/dev/null || true
  if printf '%s' "$CAPTURED_URL" | grep -q "Darwin_x86_64"; then
    printf 'ok   - install_gum: Darwin x86_64 URL contains Darwin_x86_64\n'
  else
    printf 'FAIL - install_gum: Darwin x86_64 URL should contain Darwin_x86_64 (got: %s)\n' "$CAPTURED_URL"
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# U3.3: install_gum URL contains Linux_x86_64 on Linux x86_64 (brew absent) — regression
# ---------------------------------------------------------------------------
(
  uname() { case "$1" in -s) echo "Linux";; -m) echo "x86_64";; esac }
  export -f uname
  command() {
    case "$*" in
      "-v gum")  return 1 ;;
      "-v brew") return 1 ;;
      "-v curl") return 0 ;;
      "-v apt-get") return 1 ;;
      "-v yum") return 1 ;;
      "-v pacman") return 1 ;;
      *) builtin command "$@" ;;
    esac
  }
  export -f command
  CAPTURED_URL=""
  curl() {
    for arg in "$@"; do
      case "$arg" in
        https://github.com/charmbracelet/gum*) CAPTURED_URL="$arg" ;;
        https://api.github.com*) echo '{"tag_name": "v0.17.0"}' ; return 0 ;;
      esac
    done
    return 0
  }
  export -f curl
  tar() { return 0; }
  export -f tar
  mkdir() { builtin mkdir -p "$@" 2>/dev/null || true; }
  export -f mkdir
  mv() { return 0; }
  export -f mv
  source "$BOOTSTRAP" 2>/dev/null || true
  install_gum 2>/dev/null || true
  if printf '%s' "$CAPTURED_URL" | grep -q "Linux_x86_64"; then
    printf 'ok   - install_gum: Linux x86_64 URL contains Linux_x86_64 (regression)\n'
  else
    printf 'FAIL - install_gum: Linux x86_64 URL should contain Linux_x86_64 (got: %s)\n' "$CAPTURED_URL"
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# U4.1: print_auth_steps stdout contains export PATH and .local/bin
# ---------------------------------------------------------------------------
(
  uname() { case "$1" in -s) echo "Linux";; -m) echo "x86_64";; esac }
  export -f uname
  source "$BOOTSTRAP" 2>/dev/null || true
  OUT=$(print_auth_steps 2>&1)
  if printf '%s' "$OUT" | grep -q 'export PATH' && printf '%s' "$OUT" | grep -q '\.local/bin'; then
    printf 'ok   - print_auth_steps: output contains export PATH and .local/bin\n'
  else
    printf 'FAIL - print_auth_steps: output should contain export PATH and .local/bin (got: %s)\n' "$OUT"
    exit 1
  fi
) || fails=$((fails + 1))

# ---------------------------------------------------------------------------
# T3.2: --dry-run: output has [dry-run] lines, exit 0, no mutations in HOME
# ---------------------------------------------------------------------------
TEST_HOME_DR=$(new_home)
RECORD_DR=$(mktemp)
STUB_DR=$(new_stub_bin "$RECORD_DR")

DR_OUT=$(
  export PATH="$STUB_DR:$PATH"
  export HOME="$TEST_HOME_DR"
  export DRY_RUN=1
  "$BASH_BIN" "$BOOTSTRAP" --dry-run 2>&1
)
DR_EXIT=$?

[ "$DR_EXIT" = "0" ] && pass "--dry-run exits 0" || fail "--dry-run should exit 0, got $DR_EXIT"

case "$DR_OUT" in
  *"[dry-run]"*) pass "--dry-run output contains '[dry-run]' markers" ;;
  *) fail "--dry-run should output '[dry-run]' markers (got: $(printf '%s\n' "$DR_OUT" | head -5))" ;;
esac

# No real dir created under HOME (only mktemp dirs created by test infra, not by bootstrap)
AGENT_STACK_DIR="$TEST_HOME_DR/.agent-stack"
if [ ! -d "$AGENT_STACK_DIR" ]; then
  pass "--dry-run: no ~/.agent-stack dir created"
else
  fail "--dry-run: ~/.agent-stack should NOT be created (it was created at $AGENT_STACK_DIR)"
fi

LOCAL_BIN_LINK="$TEST_HOME_DR/.local/bin/agent-stack"
if [ ! -e "$LOCAL_BIN_LINK" ]; then
  pass "--dry-run: no symlink created"
else
  fail "--dry-run: symlink should NOT be created"
fi

rm -rf "$STUB_DR" "$TEST_HOME_DR"
rm -f "$RECORD_DR"

# ---------------------------------------------------------------------------
# T3.3: --skip-codex: install-full.sh absent, overlay + symlink still present
# ---------------------------------------------------------------------------
TEST_HOME_SC=$(new_home)
RECORD_SC=$(mktemp)
STUB_SC=$(new_stub_bin "$RECORD_SC")

# Pre-create agent-stack dir so bootstrap skips clone and goes straight to steps
mkdir -p "$TEST_HOME_SC/.agent-stack"
mkdir -p "$TEST_HOME_SC/.agent-stack/lib"
cp "$HERE/lib/common.sh" "$TEST_HOME_SC/.agent-stack/lib/common.sh"
cp "$HERE/bootstrap.sh"  "$TEST_HOME_SC/.agent-stack/bootstrap.sh"
chmod +x "$TEST_HOME_SC/.agent-stack/bootstrap.sh"
mkdir -p "$TEST_HOME_SC/.agent-stack/.git"
# Pre-create codex repo too
mkdir -p "$TEST_HOME_SC/.agent-stack/repos/codex-sdd-gentle-installer/.git"
cat > "$TEST_HOME_SC/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh" <<EOF
#!$BASH_BIN
echo "install-full.sh \$*" >> "$RECORD_SC"
exit 0
EOF
chmod +x "$TEST_HOME_SC/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh"
# Pre-create overlay repo
mkdir -p "$TEST_HOME_SC/.agent-stack/repos/clean-code-lab/.git"

SC_OUT=$(
  export PATH="$STUB_SC:$PATH"
  export HOME="$TEST_HOME_SC"
  export DRY_RUN=0
  "$BASH_BIN" "$BOOTSTRAP" --skip-codex 2>&1
)
SC_EXIT=$?

[ "$SC_EXIT" = "0" ] && pass "--skip-codex exits 0" || fail "--skip-codex should exit 0, got $SC_EXIT"

INSTALL_FULL_RAN=$(grep "install-full.sh" "$RECORD_SC" 2>/dev/null || true)
if [ -z "$INSTALL_FULL_RAN" ]; then
  pass "--skip-codex: install-full.sh not executed"
else
  fail "--skip-codex: install-full.sh should NOT execute (record: $INSTALL_FULL_RAN)"
fi

OVERLAY_RAN=$(grep "intent-overlay install" "$RECORD_SC" 2>/dev/null || true)
[ -n "$OVERLAY_RAN" ] && pass "--skip-codex: intent-overlay install still runs" || fail "--skip-codex: intent-overlay install should still run (record: $(cat "$RECORD_SC"))"

SYMLINK="$TEST_HOME_SC/.local/bin/agent-stack"
[ -L "$SYMLINK" ] && pass "--skip-codex: symlink created" || fail "--skip-codex: symlink should be created at $SYMLINK"

rm -rf "$STUB_SC" "$TEST_HOME_SC"
rm -f "$RECORD_SC"

# ---------------------------------------------------------------------------
# T3.4: --with-claude adds a Claude step; without it, no Claude step
# ---------------------------------------------------------------------------
TEST_HOME_WC=$(new_home)
RECORD_WC=$(mktemp)
STUB_WC=$(new_stub_bin "$RECORD_WC")

# Pre-create repos to skip git clone
mkdir -p "$TEST_HOME_WC/.agent-stack/.git"
mkdir -p "$TEST_HOME_WC/.agent-stack/lib"
cp "$HERE/lib/common.sh" "$TEST_HOME_WC/.agent-stack/lib/common.sh"
cp "$HERE/bootstrap.sh"  "$TEST_HOME_WC/.agent-stack/bootstrap.sh"
chmod +x "$TEST_HOME_WC/.agent-stack/bootstrap.sh"
mkdir -p "$TEST_HOME_WC/.agent-stack/repos/codex-sdd-gentle-installer/.git"
cat > "$TEST_HOME_WC/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh" <<EOF
#!$BASH_BIN
echo "install-full.sh \$*" >> "$RECORD_WC"
exit 0
EOF
chmod +x "$TEST_HOME_WC/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh"
mkdir -p "$TEST_HOME_WC/.agent-stack/repos/clean-code-lab/.git"

"$BASH_BIN" "$BOOTSTRAP" --with-claude >"$TEST_HOME_WC/out_with.txt" 2>&1 \
  HOME="$TEST_HOME_WC" DRY_RUN=0 || true
WC_OUT=$(
  export PATH="$STUB_WC:$PATH"
  export HOME="$TEST_HOME_WC"
  export DRY_RUN=0
  "$BASH_BIN" "$BOOTSTRAP" --with-claude 2>&1
)

case "$WC_OUT" in
  *"claude"*) pass "--with-claude: output mentions claude install step" ;;
  *) fail "--with-claude: output should mention claude step (got: $(printf '%s\n' "$WC_OUT" | head -5))" ;;
esac

# Without --with-claude, no claude install step
WO_OUT=$(
  export PATH="$STUB_WC:$PATH"
  export HOME="$TEST_HOME_WC"
  export DRY_RUN=0
  "$BASH_BIN" "$BOOTSTRAP" --skip-codex 2>&1
)

# Claude install command should NOT appear in the without-claude run record
# (note: record may have earlier --with-claude runs; reset it first for clean check)
RECORD_WC2=$(mktemp)
STUB_WC2=$(new_stub_bin "$RECORD_WC2")

WO_CLEAN=$(
  export PATH="$STUB_WC2:$PATH"
  export HOME="$TEST_HOME_WC"
  export DRY_RUN=1
  "$BASH_BIN" "$BOOTSTRAP" 2>&1
)

# Without --with-claude the dry-run output should NOT contain a claude install line
case "$WO_CLEAN" in
  *"claude install"*|*"install claude"*)
    fail "without --with-claude: output should NOT contain claude install"
    ;;
  *)
    pass "without --with-claude: no claude install step in output"
    ;;
esac

rm -rf "$STUB_WC" "$STUB_WC2" "$TEST_HOME_WC"
rm -f "$RECORD_WC" "$RECORD_WC2"

# ---------------------------------------------------------------------------
# T3.5: --yes / ASSUME_YES=1 forwards --yes to install-full.sh
# ---------------------------------------------------------------------------
TEST_HOME_YES=$(new_home)
RECORD_YES=$(mktemp)
STUB_YES=$(new_stub_bin "$RECORD_YES")

mkdir -p "$TEST_HOME_YES/.agent-stack/.git"
mkdir -p "$TEST_HOME_YES/.agent-stack/lib"
cp "$HERE/lib/common.sh" "$TEST_HOME_YES/.agent-stack/lib/common.sh"
cp "$HERE/bootstrap.sh"  "$TEST_HOME_YES/.agent-stack/bootstrap.sh"
chmod +x "$TEST_HOME_YES/.agent-stack/bootstrap.sh"
mkdir -p "$TEST_HOME_YES/.agent-stack/repos/codex-sdd-gentle-installer/.git"
cat > "$TEST_HOME_YES/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh" <<EOF
#!$BASH_BIN
echo "install-full.sh \$*" >> "$RECORD_YES"
exit 0
EOF
chmod +x "$TEST_HOME_YES/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh"
mkdir -p "$TEST_HOME_YES/.agent-stack/repos/clean-code-lab/.git"

(
  export PATH="$STUB_YES:$PATH"
  export HOME="$TEST_HOME_YES"
  export DRY_RUN=0
  "$BASH_BIN" "$BOOTSTRAP" --yes 2>&1
) >/dev/null 2>&1

INSTALL_FULL_YES=$(grep "install-full.sh" "$RECORD_YES" 2>/dev/null || true)
case "$INSTALL_FULL_YES" in
  *"--yes"*) pass "--yes: install-full.sh invoked with --yes" ;;
  *) fail "--yes: install-full.sh should be called with --yes (got: $INSTALL_FULL_YES)" ;;
esac

rm -rf "$STUB_YES" "$TEST_HOME_YES"
rm -f "$RECORD_YES"

# ---------------------------------------------------------------------------
# T3.6: gum install failure → warning, continues (exit 0)
# ---------------------------------------------------------------------------
TEST_HOME_GF=$(new_home)
RECORD_GF=$(mktemp)
# Stub dir WITHOUT a working gum installer (brew exits non-zero)
STUB_GF=$(new_stub_bin "$RECORD_GF")
# Override brew to fail
cat > "$STUB_GF/brew" <<EOF
#!$BASH_BIN
echo "brew \$*" >> "$RECORD_GF"
exit 1
EOF
chmod +x "$STUB_GF/brew"
# Also make apt-get/yum/pacman fail
for fail_cmd in apt-get yum pacman; do
  cat > "$STUB_GF/$fail_cmd" <<EOF
#!$BASH_BIN
echo "$fail_cmd \$*" >> "$RECORD_GF"
exit 1
EOF
  chmod +x "$STUB_GF/$fail_cmd"
done
# And make curl/binary approach fail
cat > "$STUB_GF/curl" <<EOF
#!$BASH_BIN
echo "curl \$*" >> "$RECORD_GF"
exit 1
EOF
chmod +x "$STUB_GF/curl"

GF_OUT=$(
  export PATH="$STUB_GF:$PATH"
  export HOME="$TEST_HOME_GF"
  export DRY_RUN=1
  "$BASH_BIN" "$BOOTSTRAP" --dry-run 2>&1
)
GF_EXIT=$?

[ "$GF_EXIT" = "0" ] && pass "gum install failure: exit 0 (continues)" || fail "gum install failure: should exit 0, got $GF_EXIT"

case "$GF_OUT" in
  *"warning"*|*"warn"*|*"gum not"*|*"gum unavailable"*|*"skip"*)
    pass "gum install failure: warning message printed"
    ;;
  *)
    fail "gum install failure: should print a warning (got: $(printf '%s\n' "$GF_OUT" | head -5))"
    ;;
esac

rm -rf "$STUB_GF" "$TEST_HOME_GF"
rm -f "$RECORD_GF"

# ---------------------------------------------------------------------------
# T3.7: Idempotent re-run: second run pulls (not re-clones) and refreshes symlink
# ---------------------------------------------------------------------------
TEST_HOME_ID=$(new_home)
RECORD_ID=$(mktemp)
STUB_ID=$(new_stub_bin "$RECORD_ID")

# First run: repos absent → clone
mkdir -p "$TEST_HOME_ID/.agent-stack/lib"
cp "$HERE/lib/common.sh" "$TEST_HOME_ID/.agent-stack/lib/common.sh"
cp "$HERE/bootstrap.sh"  "$TEST_HOME_ID/.agent-stack/bootstrap.sh"
chmod +x "$TEST_HOME_ID/.agent-stack/bootstrap.sh"
mkdir -p "$TEST_HOME_ID/.agent-stack/.git"
mkdir -p "$TEST_HOME_ID/.agent-stack/repos/codex-sdd-gentle-installer/.git"
cat > "$TEST_HOME_ID/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh" <<EOF
#!$BASH_BIN
echo "install-full.sh \$*" >> "$RECORD_ID"
exit 0
EOF
chmod +x "$TEST_HOME_ID/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh"
mkdir -p "$TEST_HOME_ID/.agent-stack/repos/clean-code-lab/.git"

(
  export PATH="$STUB_ID:$PATH"
  export HOME="$TEST_HOME_ID"
  export DRY_RUN=0
  "$BASH_BIN" "$BOOTSTRAP" --skip-codex 2>&1
) >/dev/null 2>&1

# Second run: all repos already present → pull
RECORD_ID2=$(mktemp)
STUB_ID2=$(new_stub_bin "$RECORD_ID2")
ID2_EXIT=0
(
  export PATH="$STUB_ID2:$PATH"
  export HOME="$TEST_HOME_ID"
  export DRY_RUN=0
  "$BASH_BIN" "$BOOTSTRAP" --skip-codex 2>&1
) >/dev/null 2>&1 || ID2_EXIT=$?

[ "$ID2_EXIT" = "0" ] && pass "idempotent re-run: exits 0" || fail "idempotent re-run: should exit 0, got $ID2_EXIT"

PULL_CALLS=$(grep "git.*pull" "$RECORD_ID2" 2>/dev/null || true)
[ -n "$PULL_CALLS" ] && pass "idempotent re-run: git pull called (not clone)" || fail "idempotent re-run: should call git pull on second run (record: $(cat "$RECORD_ID2"))"

rm -rf "$STUB_ID" "$STUB_ID2" "$TEST_HOME_ID"
rm -f "$RECORD_ID" "$RECORD_ID2"

# ---------------------------------------------------------------------------
# T3.8: Symlink created at correct path; second run does not error on existing symlink
# ---------------------------------------------------------------------------
TEST_HOME_SL=$(new_home)
RECORD_SL=$(mktemp)
STUB_SL=$(new_stub_bin "$RECORD_SL")

mkdir -p "$TEST_HOME_SL/.agent-stack/.git"
mkdir -p "$TEST_HOME_SL/.agent-stack/lib"
cp "$HERE/lib/common.sh" "$TEST_HOME_SL/.agent-stack/lib/common.sh"
cp "$HERE/bootstrap.sh"  "$TEST_HOME_SL/.agent-stack/bootstrap.sh"
chmod +x "$TEST_HOME_SL/.agent-stack/bootstrap.sh"
mkdir -p "$TEST_HOME_SL/.agent-stack/repos/codex-sdd-gentle-installer/.git"
cat > "$TEST_HOME_SL/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh" <<EOF
#!$BASH_BIN
echo "install-full.sh \$*" >> "$RECORD_SL"
exit 0
EOF
chmod +x "$TEST_HOME_SL/.agent-stack/repos/codex-sdd-gentle-installer/install-full.sh"
mkdir -p "$TEST_HOME_SL/.agent-stack/repos/clean-code-lab/.git"

(
  export PATH="$STUB_SL:$PATH"
  export HOME="$TEST_HOME_SL"
  export DRY_RUN=0
  "$BASH_BIN" "$BOOTSTRAP" --skip-codex 2>&1
) >/dev/null 2>&1

SYMLINK_SL="$TEST_HOME_SL/.local/bin/agent-stack"
if [ -L "$SYMLINK_SL" ]; then
  SYMLINK_TARGET=$(readlink "$SYMLINK_SL")
  case "$SYMLINK_TARGET" in
    *"/.agent-stack/agent-stack"|*"/.agent-stack/bootstrap.sh")
      pass "symlink points to agent-stack under ~/.agent-stack"
      ;;
    "$TEST_HOME_SL/.agent-stack/agent-stack")
      pass "symlink points to ~/.agent-stack/agent-stack exactly"
      ;;
    *)
      fail "symlink target should be ~/.agent-stack/agent-stack, got $SYMLINK_TARGET"
      ;;
  esac
else
  fail "symlink $SYMLINK_SL should exist after bootstrap run"
fi

# Second run — should not fail on existing symlink
RECORD_SL2=$(mktemp)
STUB_SL2=$(new_stub_bin "$RECORD_SL2")
SL2_EXIT=0
(
  export PATH="$STUB_SL2:$PATH"
  export HOME="$TEST_HOME_SL"
  export DRY_RUN=0
  "$BASH_BIN" "$BOOTSTRAP" --skip-codex 2>&1
) >/dev/null 2>&1 || SL2_EXIT=$?
[ "$SL2_EXIT" = "0" ] && pass "symlink: second run (existing symlink) exits 0" || fail "symlink: second run should exit 0, got $SL2_EXIT"

rm -rf "$STUB_SL" "$STUB_SL2" "$TEST_HOME_SL"
rm -f "$RECORD_SL" "$RECORD_SL2"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [ "$fails" -eq 0 ]; then
  printf '\nAll tests passed.\n'
else
  printf '\n%d test(s) failed.\n' "$fails"
  exit 1
fi
