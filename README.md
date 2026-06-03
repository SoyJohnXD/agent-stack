# agent-stack

A single bash orchestrator for keeping AI agent CLIs and their configurations up to date.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/SoyJohnXD/agent-stack/main/bootstrap.sh | bash
```

This one-liner:
- Clones agent-stack to `~/.agent-stack/`
- Clones codex-sdd-gentle-installer and runs its full install
- Clones clean-code-lab and runs intent-overlay install
- Applies the Gentleman-CO persona override to Claude Code, Codex, and Opencode
- Creates `~/.local/bin/agent-stack` symlink
- Installs gum (interactive menu, best-effort)

**Not installed by default**: Claude Code. Add `--with-claude` to include it:

```bash
curl -fsSL https://raw.githubusercontent.com/SoyJohnXD/agent-stack/main/bootstrap.sh | bash -s -- --with-claude
```

### Bootstrap flags

| Flag | Effect |
|------|--------|
| `--dry-run` | Print planned actions; execute nothing |
| `--yes` | Forward `--yes` to install-full.sh (non-interactive) |
| `--skip-codex` | Skip codex install-full.sh step |
| `--with-claude` | Also install Claude Code (opt-in) |

## Manual auth steps

After bootstrap completes, log in to each CLI:

```bash
claude login
codex login
opencode login
gentle-ai login
```

## Daily usage

```bash
# Interactive menu (requires gum)
agent-stack

# Direct subcommands (script/cron safe)
agent-stack sync              # gentle -> persona -> codex -> overlay
agent-stack persona           # upsert Gentleman-CO override into the 3 agent configs
agent-stack overlay           # pull clean-code-lab + intent-overlay install
agent-stack codex             # pull codex repo + install.sh
agent-stack gentle            # gentle-ai upgrade && sync
agent-stack update-clis       # update all 4 CLI binaries
agent-stack all               # update-clis -> gentle -> persona -> codex -> overlay
agent-stack doctor            # aggregated health report
agent-stack bootstrap         # re-run the full bootstrap
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
| Instalación inicial | `bootstrap` | Full install from scratch |
| Sync completo (configs) | `sync` | gentle → persona → codex → overlay |
| Solo overlay | `overlay` | pull clean-code-lab + intent-overlay install |
| Solo Codex (SDD/MCP) | `codex` | pull codex repo + install.sh |
| Solo Gentle | `gentle` | gentle-ai upgrade && sync |
| Actualizar CLIs (binarios) | `update-clis` | 4 CLI updates |
| TODO (CLIs + sync) | `all` | update-clis → sync |
| Doctor | `doctor` | health report |
| Salir / Exit | — | exit 0 |

## What gets updated

| Phase | Commands run |
|-------|-------------|
| `bootstrap` | gum → agent-stack repo → codex install → intent-overlay install → **persona** → symlink |
| `gentle` | `gentle-ai upgrade`, `gentle-ai sync` |
| `persona` | Upserts `<!-- persona-co:start/end -->` block from `persona/gentleman-co.md` into `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.override.md`, `~/.config/opencode/AGENTS.md`. Idempotent. Run automatically after `gentle` in every `sync`. |
| `codex` | `git pull` → `install.sh` → `codex-sdd-sync --mcp-audit` |
| `overlay` | `git pull` → `intent-overlay install` |
| `update-clis` | `claude update` (if present), `codex update` (if present), `opencode upgrade` (if present), `gentle-ai upgrade` (if present) |

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

## Manifest

`repos.manifest` defines managed repos (one per line):

```
# name | local_path | remote | branch
codex   | ~/.agent-stack/repos/codex-sdd-gentle-installer | https://github.com/SoyJohnXD/codex-sdd-gentle-installer.git | main
overlay | ~/.agent-stack/repos/clean-code-lab             | https://github.com/SoyJohnXD/clean-code-lab.git             | main
```

- Lines starting with `#` and blank lines are ignored.
- `~` in `local_path` is expanded to `$HOME`.
- If `local_path` does not exist, it is cloned from `remote` at `branch`.
- If it exists, `git pull origin <branch>` is run.

## Tests

```bash
bash agent-stack.test.sh
bash lib/common.test.sh
bash lib/gentle.test.sh
bash lib/persona.test.sh
bash lib/overlay.test.sh
bash lib/codex.test.sh
bash lib/clis.test.sh
bash lib/doctor.test.sh
bash bootstrap.test.sh
```

All tests use a throwaway `$HOME` via `mktemp -d` and stubbed binaries on PATH — no real mutations occur during testing.
