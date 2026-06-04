<#
.SYNOPSIS
  agent-stack dispatcher for Windows — orchestrate AI agent CLI updates and config syncs.

.DESCRIPTION
  PowerShell equivalent of the bash 'agent-stack' entrypoint.
  Dot-sources all lib modules, parses flags, presents a TUI menu (gum or numbered
  fallback), and dispatches to the appropriate phase function.

  Flags (any position):
    --dry-run      Set $env:DRY_RUN=1
    --yes          Set $env:ASSUME_YES=1
    --skip-codex   Set $env:SKIP_CODEX=1

  Subcommands:
    bootstrap     Windows install flow
    sync          gentle -> persona -> codex -> overlay
    gentle        gentle-ai upgrade + sync
    update-clis   Update claude, codex, opencode, gentle-ai
    all           update-clis -> sync
    doctor        Aggregated health report
    persona       Apply persona config to claude/codex/opencode config files
    codex         Clone/update codex repo, run install.ps1, run codex-sdd-sync
    overlay       Clone/update overlay repo, run intent-overlay.ps1 install
    exit|salir    Exit cleanly

  Entry guard: main() is only called when the script is executed directly.
  Dot-sourcing (. .\agent-stack.ps1) loads all functions without running main.

  PowerShell 5.1+ compatible.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source lib modules in dependency order.
. "$PSScriptRoot\lib\platform-windows.ps1"
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\gentle.ps1"
. "$PSScriptRoot\lib\clis.ps1"
. "$PSScriptRoot\lib\doctor.ps1"
. "$PSScriptRoot\lib\bootstrap.ps1"
. "$PSScriptRoot\lib\persona.ps1"
. "$PSScriptRoot\lib\codex.ps1"
. "$PSScriptRoot\lib\overlay.ps1"

# Point phases at the manifest sitting next to this script.
$env:MANIFEST_FILE = Join-Path $PSScriptRoot 'repos.manifest'

# ---------------------------------------------------------------------------
# Get-PositionalArgs — flag parsing
# Sets $env:DRY_RUN / ASSUME_YES / SKIP_CODEX and returns non-flag args.
# ,$pos forces array return even for 0 or 1 elements.
# ---------------------------------------------------------------------------
function Get-PositionalArgs {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Argv
    )

    $env:DRY_RUN    = if ($env:DRY_RUN)    { $env:DRY_RUN }    else { '0' }
    $env:ASSUME_YES = if ($env:ASSUME_YES) { $env:ASSUME_YES } else { '0' }
    $env:SKIP_CODEX = if ($env:SKIP_CODEX) { $env:SKIP_CODEX } else { '0' }

    $pos = @()
    foreach ($a in $Argv) {
        switch ($a) {
            '--dry-run'    { $env:DRY_RUN    = '1' }
            '--yes'        { $env:ASSUME_YES = '1' }
            '--skip-codex' { $env:SKIP_CODEX = '1' }
            default        { $pos += $a }
        }
    }

    # ,$pos ensures an array is always returned, never unwrapped to a scalar.
    return , $pos
}

# ---------------------------------------------------------------------------
# Menu — ordered label -> subcommand map
# ---------------------------------------------------------------------------
$script:Menu = [ordered]@{
    'Instalación inicial'        = 'bootstrap'
    'Sync completo (configs)'    = 'sync'
    'Solo overlay'               = 'overlay'
    'Solo Codex (SDD/MCP)'       = 'codex'
    'Solo Gentle'                = 'gentle'
    'Actualizar CLIs (binarios)' = 'update-clis'
    'TODO (CLIs + sync)'         = 'all'
    'Doctor'                     = 'doctor'
    'Salir'                      = 'exit'
}

function Show-Menu {
    <#
    .SYNOPSIS
      Presents an interactive menu. Uses gum if available, numbered Read-Host otherwise.
    .OUTPUTS
      [string] Selected subcommand key, or $null if selection fails.
    #>

    $labels = @($script:Menu.Keys)

    if (Get-Command gum -ErrorAction SilentlyContinue) {
        $chosen = & gum choose @labels
    } else {
        for ($i = 0; $i -lt $labels.Count; $i++) {
            Write-Host "$($i + 1)) $($labels[$i])"
        }
        $sel = Read-Host 'Choose'
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $labels.Count) {
            $chosen = $labels[[int]$sel - 1]
        } else {
            return $null
        }
    }

    if ($chosen) {
        return $script:Menu[$chosen]
    }
    return $null
}

# ---------------------------------------------------------------------------
# Composite runners
# ---------------------------------------------------------------------------
function Invoke-RunSync {
    phase_gentle
    phase_persona
    if ($env:SKIP_CODEX -eq '1') {
        Write-Host '[skip] codex phase skipped (--skip-codex)'
    } else {
        phase_codex
    }
    phase_overlay
}

function Invoke-RunAll {
    phase_update_clis
    Invoke-RunSync
}

# ---------------------------------------------------------------------------
# Invoke-Dispatch — subcommand router
# ---------------------------------------------------------------------------
function Invoke-Dispatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Subcommand
    )

    switch ($Subcommand) {
        'bootstrap'                         { phase_bootstrap }
        'persona'                           { phase_persona }
        'sync'                              { Invoke-RunSync }
        'overlay'                           { phase_overlay }
        'codex'                             { phase_codex }
        'gentle'                            { phase_gentle }
        'update-clis'                       { phase_update_clis }
        'all'                               { Invoke-RunAll }
        'doctor'                            { phase_doctor }
        { $_ -in @('exit', 'salir', 'Salir') } { exit 0 }
        default {
            Write-Error "Unknown subcommand: $Subcommand"
            exit 2
        }
    }
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
function main {
    $pos = Get-PositionalArgs @args
    $sub = if ($pos.Count -gt 0) { $pos[0] } else { $null }

    if (-not $sub) {
        $sub = Show-Menu
    }

    if (-not $sub) {
        exit 0
    }

    Invoke-Dispatch -Subcommand $sub
}

# Entry guard: run main only when executed directly, not when dot-sourced.
if ($MyInvocation.InvocationName -ne '.') { main @args }
