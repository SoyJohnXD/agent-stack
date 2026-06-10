Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($script:_CodexPs1Loaded) { return }
$script:_CodexPs1Loaded = $true

# Hook scripts installed into ~/.codex/hooks and wired into hooks.json.
$Script:CODEX_HOOK_SCRIPTS = @('clean-code-gate.sh')

function phase_codex {
    $manifest = $env:MANIFEST_FILE
    if (-not $manifest) { $manifest = Join-Path $PSScriptRoot '..\repos.manifest' }

    $entry = Invoke-ParseManifest -ManifestPath $manifest | Where-Object { $_.Name -eq 'codex' } | Select-Object -First 1
    if (-not $entry) { Write-Warning 'phase_codex: codex entry not found in repos.manifest'; return }

    Invoke-EnsureRepo -LocalPath $entry.LocalPath -Remote $entry.Remote -Branch $entry.Branch
    Invoke-AgentRun powershell -NonInteractive -File (Join-Path $entry.LocalPath 'install.ps1')
    Invoke-AgentRun codex-sdd-sync --mcp-audit
}

function Get-CodexHooksDir {
    Join-Path (Get-AgentStackPath 'codex-root') 'hooks'
}

function Get-CodexHooksFile {
    Join-Path (Get-AgentStackPath 'codex-root') 'hooks.json'
}

# ---------------------------------------------------------------------------
# Install-CodexHookScripts — copy hooks/clean-code-gate.sh into ~/.codex/hooks
# ---------------------------------------------------------------------------
function Install-CodexHookScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourceDir
    )

    $destDir = Get-CodexHooksDir

    if ($env:DRY_RUN -eq '1') {
        foreach ($script in $Script:CODEX_HOOK_SCRIPTS) {
            Write-Host "[dry-run] would install $destDir/$script"
        }
        return
    }

    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    foreach ($script in $Script:CODEX_HOOK_SCRIPTS) {
        Copy-Item -LiteralPath (Join-Path $SourceDir $script) -Destination (Join-Path $destDir $script) -Force
    }
}

# ---------------------------------------------------------------------------
# Set-CodexHooksJson — idempotent merge adding a Stop hook for
# clean-code-gate.sh into ~/.codex/hooks.json. Never touches SessionStart.
# ---------------------------------------------------------------------------
function Set-CodexHooksJson {
    [CmdletBinding()]
    param()

    $target   = Get-CodexHooksFile
    $hooksDir = (Get-CodexHooksDir) -replace '\\', '/'

    if ($env:DRY_RUN -eq '1') {
        Write-Host "[dry-run] would wire codex hooks into $target"
        return
    }

    $parent = Split-Path -Parent $target
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $config = if (Test-Path $target) {
        Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{}
    }

    if (-not $config.PSObject.Properties['hooks']) {
        $config | Add-Member -MemberType NoteProperty -Name 'hooks' -Value ([pscustomobject]@{})
    }
    $hooks = $config.hooks

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

    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $target -Encoding UTF8
}

# ---------------------------------------------------------------------------
# phase_codex_hooks — public entry point called by run_sync / dispatch
# ---------------------------------------------------------------------------
function phase_codex_hooks {
    $hooksSrc = Join-Path $PSScriptRoot '..\hooks'
    Install-CodexHookScripts -SourceDir $hooksSrc
    Set-CodexHooksJson
    Write-Host 'NOTE: ~/.codex/hooks.json changed -- Codex will ask to re-trust hooks once (trusted_hash update).'
}
