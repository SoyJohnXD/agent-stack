Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($script:_ClaudePs1Loaded) { return }
$script:_ClaudePs1Loaded = $true

# Hook scripts installed into ~/.claude/hooks and wired into settings.json.
$Script:CLAUDE_HOOK_SCRIPTS = @('check-plan-contract.sh', 'clean-code-gate.sh', 'skill-registry-refresh.sh')

function Get-ClaudeHooksDir {
    Join-Path (Get-AgentStackPath 'claude-config') 'hooks'
}

function Get-ClaudeSettingsFile {
    Join-Path (Get-AgentStackPath 'claude-config') 'settings.json'
}

# ---------------------------------------------------------------------------
# Install-ClaudeHookScripts — copy hooks/*.sh into ~/.claude/hooks
# ---------------------------------------------------------------------------
function Install-ClaudeHookScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourceDir
    )

    $destDir = Get-ClaudeHooksDir

    if ($env:DRY_RUN -eq '1') {
        foreach ($script in $Script:CLAUDE_HOOK_SCRIPTS) {
            Write-Host "[dry-run] would install $destDir/$script"
        }
        return
    }

    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    foreach ($script in $Script:CLAUDE_HOOK_SCRIPTS) {
        Copy-Item -LiteralPath (Join-Path $SourceDir $script) -Destination (Join-Path $destDir $script) -Force
    }
}

# ---------------------------------------------------------------------------
# Set-ClaudeSettingsHooks — idempotent jq-equivalent merge into settings.json
#
#   PreToolUse (matcher ExitPlanMode) -> check-plan-contract.sh
#   Stop                              -> clean-code-gate.sh
#   UserPromptSubmit                  -> swap existing skill-registry refresh
#                                         command for skill-registry-refresh.sh
#
# Never clobbers unrelated keys. Re-running on its own output is a no-op.
# ---------------------------------------------------------------------------
function Set-ClaudeSettingsHooks {
    [CmdletBinding()]
    param()

    $target   = Get-ClaudeSettingsFile
    $hooksDir = (Get-ClaudeHooksDir) -replace '\\', '/'

    if ($env:DRY_RUN -eq '1') {
        Write-Host "[dry-run] would wire claude hooks into $target"
        return
    }

    $parent = Split-Path -Parent $target
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $settings = if (Test-Path $target) {
        Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{}
    }

    if (-not $settings.PSObject.Properties['hooks']) {
        $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value ([pscustomobject]@{})
    }
    $hooks = $settings.hooks

    # PreToolUse[ExitPlanMode] -> check-plan-contract.sh
    if (-not $hooks.PSObject.Properties['PreToolUse']) {
        $hooks | Add-Member -MemberType NoteProperty -Name 'PreToolUse' -Value @()
    }
    $hasExitPlanMode = @($hooks.PreToolUse | Where-Object { $_.matcher -eq 'ExitPlanMode' }).Count -gt 0
    if (-not $hasExitPlanMode) {
        $entry = [pscustomobject]@{
            matcher = 'ExitPlanMode'
            hooks   = @([pscustomobject]@{ type = 'command'; command = "$hooksDir/check-plan-contract.sh" })
        }
        $hooks.PreToolUse = @($hooks.PreToolUse) + @($entry)
    }

    # Stop -> clean-code-gate.sh
    if (-not $hooks.PSObject.Properties['Stop']) {
        $hooks | Add-Member -MemberType NoteProperty -Name 'Stop' -Value @()
    }
    $hasCleanCodeGate = @($hooks.Stop | Where-Object {
        @($_.hooks | Where-Object { $_.command -match 'clean-code-gate\.sh' }).Count -gt 0
    }).Count -gt 0
    if (-not $hasCleanCodeGate) {
        $entry = [pscustomobject]@{
            matcher = ''
            hooks   = @([pscustomobject]@{ type = 'command'; command = "$hooksDir/clean-code-gate.sh" })
        }
        $hooks.Stop = @($hooks.Stop) + @($entry)
    }

    # UserPromptSubmit -> swap skill-registry refresh command
    #
    # PARITY NOTE: lib/claude.sh dedupes the skill-registry-refresh.sh entries
    # after conversion (gentle-ai re-appends its raw entry on every sync,
    # otherwise causing unbounded duplicate hook entries). This PowerShell
    # path does not yet implement that dedup — port the same fix here if this
    # path is exercised on Windows.
    if ($hooks.PSObject.Properties['UserPromptSubmit']) {
        foreach ($entry in @($hooks.UserPromptSubmit)) {
            foreach ($hook in @($entry.hooks)) {
                if ($hook.command -match 'skill-registry refresh|skill-registry-refresh\.sh') {
                    $hook.command = "$hooksDir/skill-registry-refresh.sh"
                }
            }
        }
    }

    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $target -Encoding UTF8
}

# ---------------------------------------------------------------------------
# phase_claude_hooks — public entry point called by run_sync / dispatch
# ---------------------------------------------------------------------------
function phase_claude_hooks {
    $hooksSrc = Join-Path $PSScriptRoot '..\hooks'
    Install-ClaudeHookScripts -SourceDir $hooksSrc
    Set-ClaudeSettingsHooks
    Write-Host '  claude hooks wired'
}
