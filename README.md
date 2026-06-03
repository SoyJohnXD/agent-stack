# agent-stack

A single bash orchestrator for keeping AI agent CLIs and their configurations up to date.
Runs an interactive menu (requires `gum`) or dispatches directly via subcommands (cron/script safe).

## Install

```bash
# Clone or copy the repo
git clone https://github.com/SoyJohnXD/agent-stack.git ~/Documents/personal/agent-stack
cd ~/Documents/personal/agent-stack

# Make the entrypoint executable
chmod +x agent-stack

# Optional: add to PATH or create a symlink
ln -s "$PWD/agent-stack" ~/.local/bin/agent-stack
```

## Usage

```bash
# Interactive menu (requires gum)
agent-stack

# Direct subcommands (script/cron safe)
agent-stack sync              # gentle -> codex -> overlay
agent-stack overlay           # pull clean-code-lab + intent-overlay install
agent-stack codex             # pull codex repo + install.sh
agent-stack gentle            # gentle-ai upgrade && sync
agent-stack update-clis       # update all 4 CLI binaries
agent-stack all               # update-clis -> gentle -> codex -> overlay
agent-stack doctor            # aggregated health report
```

## Global Flags

All flags work from any position before or after the subcommand.

| Flag | Effect |
|------|--------|
| `--dry-run` | Print planned actions; execute nothing |
| `--yes` | Skip any interactive confirmation prompts |
| `--skip-codex` | Omit the codex phase from `sync` or `all` |

```bash
# Safe preview
agent-stack --dry-run all

# Sync without codex
agent-stack sync --skip-codex
```

## Menu

When run without arguments and `gum` is installed:

| Label | Subcommand | Action |
|-------|-----------|--------|
| Sync completo (configs) | `sync` | gentle → codex → overlay |
| Solo overlay | `overlay` | pull clean-code-lab + intent-overlay install |
| Solo Codex (SDD/MCP) | `codex` | pull codex repo + install.sh |
| Solo Gentle | `gentle` | gentle-ai upgrade && sync |
| Actualizar CLIs (binarios) | `update-clis` | 4 CLI updates |
| TODO (CLIs + sync) | `all` | update-clis → sync |
| Doctor | `doctor` | health report |
| Salir / Exit | — | exit 0 |

## Manifest Format

`repos.manifest` defines managed repos (one per line):

```
# name | local_path | remote | branch
codex   | ~/Documents/osoria/codex-sdd-gentle-installer    | https://github.com/SoyJohnXD/codex-sdd-gentle-installer.git | main
overlay | ~/Documents/personal/clean-code-lab              | https://github.com/SoyJohnXD/clean-code-lab.git             | main
```

- Lines starting with `#` and blank lines are ignored.
- `~` in `local_path` is expanded to `$HOME`.
- If `local_path` does not exist, it is cloned from `remote` at `branch`.
- If it exists, `git pull origin <branch>` is run before the installer.

## What gets updated

| Phase | Commands run |
|-------|-------------|
| `gentle` | `gentle-ai upgrade`, `gentle-ai sync` |
| `codex` | `git pull` → `install.sh` → `codex-sdd-sync --mcp-audit` |
| `overlay` | `git pull` → `intent-overlay install` |
| `update-clis` | `claude update`, `codex update`, `opencode upgrade`, `gentle-ai upgrade` |

## Doctor checks

`agent-stack doctor` runs:

- `intent-overlay doctor` (required)
- `codex-sdd-sync --mcp-audit` (required)
- `claude --version` (required)
- `codex --version` (required)
- `opencode --version` (required)
- `gentle-ai --version` (required)
- `git --version` (required)
- `gum --version` (optional — menu won't work without it but all subcommands still work)

## Codex repo migration note

The codex installer repo was migrated from `nicolasvosoria/codex-sdd-gentle-installer` to
`SoyJohnXD/codex-sdd-gentle-installer`.

If you have the original repo cloned locally, update its remote:

```bash
git -C ~/Documents/osoria/codex-sdd-gentle-installer \
  remote set-url origin https://github.com/SoyJohnXD/codex-sdd-gentle-installer.git
```

Deleting the original `nicolasvosoria`-owned repo is an external manual action and requires
owner-level access to that GitHub account (out of scope here).

## Tests

```bash
bash agent-stack.test.sh
bash lib/common.test.sh
bash lib/gentle.test.sh
bash lib/overlay.test.sh
bash lib/codex.test.sh
bash lib/clis.test.sh
bash lib/doctor.test.sh
```

All tests use a throwaway `$HOME` via `mktemp -d` and stubbed binaries on PATH — no real mutations occur during testing.
