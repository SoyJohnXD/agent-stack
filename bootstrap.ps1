<#
.SYNOPSIS
  Windows install flow for agent-stack.

.DESCRIPTION
  Mirrors bootstrap.sh for native Windows (PowerShell 5.1+).
  Dot-sources lib/platform-windows.ps1 and lib/common.ps1.

  Steps:
    1. Self-clone / update agent-stack repo.
    2. Install gum.exe (GitHub Releases API -> zip -> launcher-dir).
    3. Install launcher shim via Install-PathShim (SDD-2).
    4. Clone / pull every repo listed in repos.manifest.
    5. Codex install — clone/update repo, run install.ps1, run codex-sdd-sync.
    6. Overlay install — clone/update repo, run intent-overlay.ps1 install.
    7. Persona apply — upsert persona block into claude/codex/opencode config files.
    8. Print auth steps.

  Flags (any position):
    --dry-run      Set $env:DRY_RUN=1   (all mutations become [dry-run] prints)
    --yes          Set $env:ASSUME_YES=1
    --skip-codex   Set $env:SKIP_CODEX=1
    --with-claude  Print Claude Code Windows installation instructions

  Entry guard: if this file is dot-sourced (. .\bootstrap.ps1), main() is NOT
  called automatically, so the file is safe to dot-source for testing.

  Usage:
    .\bootstrap.ps1 [--dry-run] [--yes] [--skip-codex] [--with-claude]
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\platform-windows.ps1"
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\persona.ps1"
. "$PSScriptRoot\lib\codex.ps1"
. "$PSScriptRoot\lib\overlay.ps1"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:AgentStackRemote  = 'https://github.com/SoyJohnXD/agent-stack.git'
$script:GumFallbackVersion = '0.17.0'

# ---------------------------------------------------------------------------
# Install-GumWindows
# ---------------------------------------------------------------------------
function Install-GumWindows {
    <#
    .SYNOPSIS
      Downloads and installs gum.exe from GitHub Releases into launcher-dir.
    .DESCRIPTION
      Skips silently if gum is already on PATH. Queries the GitHub Releases API
      for the latest version when $Version is not provided. Downloads the
      Windows_x86_64.zip asset, extracts gum.exe, copies to launcher-dir.
      Invoke-WebRequest is wrapped in Invoke-AgentRun for dry-run safety.
    .PARAMETER Version
      Optional explicit version string (no 'v' prefix). Defaults to latest via API.
    #>
    [CmdletBinding()]
    param(
        [string] $Version = ''
    )

    if (Get-Command gum -ErrorAction SilentlyContinue) {
        Write-Host '[skip] gum already installed'
        return
    }

    Write-Host '>>> Installing gum (interactive menu helper)...'

    if (-not $Version) {
        try {
            $rel     = Invoke-RestMethod -Uri 'https://api.github.com/repos/charmbracelet/gum/releases/latest'
            $Version = $rel.tag_name.TrimStart('v')
        } catch {
            Write-Warning "Could not query GitHub API for gum version; falling back to $script:GumFallbackVersion"
            $Version = $script:GumFallbackVersion
        }
    }

    $asset   = "gum_${Version}_Windows_x86_64.zip"
    $url     = "https://github.com/charmbracelet/gum/releases/download/v$Version/$asset"
    $tmp     = Join-Path ([System.IO.Path]::GetTempPath()) ("gum_" + [guid]::NewGuid().ToString('N'))

    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    $zip = Join-Path $tmp $asset

    if ($env:DRY_RUN -eq '1') {
        Write-Host "[dry-run] Invoke-WebRequest -Uri $url -OutFile $zip"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    Invoke-WebRequest -Uri $url -OutFile $zip

    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force

    $exe = Get-ChildItem -Path $tmp -Recurse -Filter 'gum.exe' | Select-Object -First 1
    if (-not $exe) {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw "Install-GumWindows: gum.exe not found in extracted archive."
    }

    $dest = Get-AgentStackPath 'launcher-dir'
    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    Copy-Item $exe.FullName (Join-Path $dest 'gum.exe') -Force
    Remove-Item $tmp -Recurse -Force

    Write-Host "[ok] gum.exe installed to $dest"
}

# ---------------------------------------------------------------------------
# Write-BootstrapAuthSteps
# ---------------------------------------------------------------------------
function Write-BootstrapAuthSteps {
    Write-Host ''
    Write-Host '=== Bootstrap complete! ==='
    Write-Host ''
    Write-Host 'Manual auth steps:'
    Write-Host '  claude    : claude login'
    Write-Host '  codex     : codex login'
    Write-Host '  opencode  : opencode login'
    Write-Host '  gentle-ai : gentle-ai login'
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  agent-stack           # interactive menu'
    Write-Host '  agent-stack all       # update everything non-interactively'
    Write-Host ''
    $launcherDir = Get-AgentStackPath 'launcher-dir'
    Write-Host "If agent-stack is not found, ensure $launcherDir is on your PATH."
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `$env:PATH + ';$launcherDir', 'User')"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
function main {
    param([string[]] $Argv)

    # Parse flags
    $env:DRY_RUN    = if ($env:DRY_RUN)    { $env:DRY_RUN }    else { '0' }
    $env:ASSUME_YES = if ($env:ASSUME_YES) { $env:ASSUME_YES } else { '0' }
    $env:SKIP_CODEX = if ($env:SKIP_CODEX) { $env:SKIP_CODEX } else { '0' }
    $withClaude = $false

    foreach ($arg in $Argv) {
        switch ($arg) {
            '--dry-run'     { $env:DRY_RUN    = '1' }
            '--yes'         { $env:ASSUME_YES = '1' }
            '--skip-codex'  { $env:SKIP_CODEX = '1' }
            '--with-claude' { $withClaude = $true   }
        }
    }

    Write-AgentLog -Phase start -Action 'bootstrap'

    # Step 1: self-clone / update agent-stack repo
    $agentStackLocal = Get-AgentStackPath 'agent-stack-local'
    Invoke-EnsureRepo -LocalPath $agentStackLocal -Remote $script:AgentStackRemote -Branch 'main'

    # Step 2: install gum.exe (skip if already present)
    Install-GumWindows

    # Step 3: install launcher shim (SDD-2 function)
    Install-PathShim | Out-Null

    # Step 4: clone / pull each repo from manifest
    $manifestPath = Join-Path $PSScriptRoot 'repos.manifest'
    if (Test-Path $manifestPath) {
        Invoke-ParseManifest -ManifestPath $manifestPath | ForEach-Object {
            Invoke-EnsureRepo -LocalPath $_.LocalPath -Remote $_.Remote -Branch $_.Branch
        }
    } else {
        Write-Warning "repos.manifest not found at $manifestPath — skipping repo clones."
    }

    # Step 5: codex install
    phase_codex

    # Step 6: overlay install
    phase_overlay

    # Step 7: persona apply
    phase_persona

    # Step 8: Claude Code install (opt-in only)
    if ($withClaude) {
        Write-Host ''
        Write-Host '>>> Claude Code for Windows installation instructions:'
        Write-Host '  Visit: https://claude.ai/download'
        Write-Host '  Or run the official installer when available for your platform.'
        Write-Host '  After install: claude login'
    }

    if ($env:DRY_RUN -ne '1') {
        Write-BootstrapAuthSteps
    }

    Write-AgentLog -Phase finish -Action 'bootstrap'
}

# Entry guard: run main only when executed directly, not when dot-sourced.
if ($MyInvocation.InvocationName -ne '.') { main @args }
