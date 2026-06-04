<#
.SYNOPSIS
  Shared seam for agent-stack: logging, dry-run gate, manifest parsing, repo management.

.DESCRIPTION
  Dot-source this module from lib/*.ps1 and top-level scripts.
  This is a leaf module — it does NOT dot-source platform-windows.ps1 itself;
  callers must dot-source platform-windows.ps1 first when they need path helpers.

  Exported functions:
    Invoke-AgentRun        — universal mutation seam (dry-run gate)
    Write-AgentLog         — phase start/finish banners
    Expand-AgentPath       — ~ expansion to USERPROFILE
    Invoke-ParseManifest   — parse repos.manifest into pscustomobjects
    Invoke-EnsureRepo      — idempotent clone-or-pull via Invoke-AgentRun

  PowerShell 5.1+ compatible. No PS7-only features.
#>

if ($script:_CommonPs1Loaded) { return }
$script:_CommonPs1Loaded = $true

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Invoke-AgentRun — SINGLE mutation seam
# All commands that mutate machine state MUST go through this function.
# Pure reads (existence checks, version queries) bypass it.
# ---------------------------------------------------------------------------
function Invoke-AgentRun {
    <#
    .SYNOPSIS
      Dry-run–aware executor for external commands.
    .DESCRIPTION
      When $env:DRY_RUN equals '1', prints "[dry-run] <cmd>" and returns without
      executing. Otherwise executes via & and propagates the exit code.
      Only wraps external executables (git, gentle-ai, claude, etc.) — NOT PS cmdlets.
    .PARAMETER Args
      Command and its arguments. First element is the executable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Args
    )

    if ($env:DRY_RUN -eq '1') {
        Write-Host "[dry-run] $($Args -join ' ')"
        return
    }

    $exe  = $Args[0]
    $rest = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }
    & $exe @rest
}

# ---------------------------------------------------------------------------
# Write-AgentLog — phase start/finish banners
# ---------------------------------------------------------------------------
function Write-AgentLog {
    <#
    .SYNOPSIS
      Emits a phase-start or phase-finish banner.
    .PARAMETER Phase
      'start' prints ">>> START: <action>"; 'finish' prints "<<< DONE: <action>".
    .PARAMETER Action
      Human-readable name of the phase or action.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('start', 'finish')]
        [string] $Phase,

        [Parameter(Mandatory)]
        [string] $Action
    )

    if ($Phase -eq 'start') {
        Write-Host "`n>>> START: $Action"
    } else {
        Write-Host "<<< DONE: $Action"
    }
}

# ---------------------------------------------------------------------------
# Expand-AgentPath — ~ expansion to USERPROFILE
# ---------------------------------------------------------------------------
function Expand-AgentPath {
    <#
    .SYNOPSIS
      Expands a leading ~ (or ~/) to $env:USERPROFILE.
    .PARAMETER Path
      A path that may begin with ~ or ~/ (or ~\).
    .OUTPUTS
      [string] absolute path with ~ replaced.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($Path -eq '~') {
        return $env:USERPROFILE
    }
    if ($Path -like '~/*' -or $Path -like '~\*') {
        return Join-Path $env:USERPROFILE $Path.Substring(2)
    }
    return $Path
}

# ---------------------------------------------------------------------------
# Invoke-ParseManifest — parse repos.manifest
# ---------------------------------------------------------------------------
function Invoke-ParseManifest {
    <#
    .SYNOPSIS
      Parses a repos.manifest file into pscustomobjects.
    .DESCRIPTION
      Skips blank lines and lines whose first non-whitespace character is '#'.
      Splits on '|', trims each field, expands leading '~' in LocalPath.
      Returns objects with Name, LocalPath, Remote, Branch properties.
    .PARAMETER ManifestPath
      Absolute path to the manifest file.
    .OUTPUTS
      [pscustomobject[]] collection of repo descriptors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    Get-Content -LiteralPath $ManifestPath | ForEach-Object {
        $line = $_.Trim()

        # Skip blank lines and comment lines
        if ($line -eq '' -or $line.StartsWith('#')) { return }

        $parts = $line.Split('|')
        if ($parts.Count -lt 4) { return }

        [pscustomobject]@{
            Name      = $parts[0].Trim()
            LocalPath = Expand-AgentPath $parts[1].Trim()
            Remote    = $parts[2].Trim()
            Branch    = $parts[3].Trim()
        }
    }
}

# ---------------------------------------------------------------------------
# Invoke-EnsureRepo — idempotent clone-or-pull
# ---------------------------------------------------------------------------
function Invoke-EnsureRepo {
    <#
    .SYNOPSIS
      Clones a repo if absent, or pulls if already present.
    .DESCRIPTION
      Detects the presence of a .git directory via Test-Path and git rev-parse.
      All mutating commands go through Invoke-AgentRun so --dry-run is safe.
      Read-only checks (Test-Path, git rev-parse) bypass the gate.
    .PARAMETER LocalPath
      The local directory where the repo should live.
    .PARAMETER Remote
      The remote URL to clone from.
    .PARAMETER Branch
      The branch to clone or pull.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $LocalPath,
        [Parameter(Mandatory)] [string] $Remote,
        [Parameter(Mandatory)] [string] $Branch
    )

    $isRepo = Test-Path (Join-Path $LocalPath '.git')

    if (-not $isRepo -and (Test-Path $LocalPath)) {
        # Directory exists but no obvious .git — try git rev-parse (bare/worktree)
        & git -C $LocalPath rev-parse --git-dir 2>$null | Out-Null
        $isRepo = ($LASTEXITCODE -eq 0)
    }

    if ($isRepo) {
        Invoke-AgentRun git -C $LocalPath pull origin $Branch
    } else {
        Invoke-AgentRun git clone --branch $Branch $Remote $LocalPath
    }
}
