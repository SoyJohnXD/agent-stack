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
    Invoke-BlockUpsert     — replace/insert a marker-delimited block in a file
    Set-ManagedBlock       — DRY_RUN-aware wrapper around Invoke-BlockUpsert

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

# ---------------------------------------------------------------------------
# Invoke-BlockUpsert — replace/insert a marker-delimited block in a file
# ---------------------------------------------------------------------------
function Invoke-BlockUpsert {
    <#
    .SYNOPSIS
      Replaces an existing Start..End marker span with Block, or appends Block
      (with its own markers) at EOF when the markers are absent.
    .DESCRIPTION
      Mirrors the awk logic in upsert_block_by_markers (lib/common.sh). Content
      outside the marker span — including foreign marker blocks such as
      gentle-ai's — is preserved verbatim.
    .PARAMETER FilePath
      The file to update. Created (with parent dirs) if missing.
    .PARAMETER StartMarker
      The exact line that opens the managed block.
    .PARAMETER EndMarker
      The exact line that closes the managed block.
    .PARAMETER Block
      The full replacement block, markers included, one element per line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $FilePath,
        [Parameter(Mandatory)] [string]   $StartMarker,
        [Parameter(Mandatory)] [string]   $EndMarker,
        [Parameter(Mandatory)] [string[]] $Block
    )

    $parent = Split-Path -Parent $FilePath
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $lines = if (Test-Path $FilePath) { @(Get-Content -LiteralPath $FilePath) } else { @() }
    $n = $lines.Count; $s = -1; $e = -1
    for ($i = 0; $i -lt $n; $i++) {
        if ($lines[$i] -eq $StartMarker -and $s -lt 0) { $s = $i }
        if ($lines[$i] -eq $EndMarker   -and $s -ge 0) { $e = $i; break }
    }

    # Refuse when the start marker has no matching end marker: replacing the
    # span would be impossible and appending would duplicate the block.
    if ($s -ge 0 -and $e -lt 0) {
        throw "Invoke-BlockUpsert: $FilePath has unbalanced managed-block markers ($StartMarker / $EndMarker); fix the file manually"
    }

    $out = [System.Collections.Generic.List[string]]::new()
    if ($s -ge 0 -and $e -ge 0) {
        # Replace existing span
        for ($i = 0; $i -lt $s; $i++)    { $out.Add($lines[$i]) }
        foreach ($l in $Block)             { $out.Add($l) }
        for ($i = $e + 1; $i -lt $n; $i++) { $out.Add($lines[$i]) }
    } else {
        # Append at EOF
        foreach ($l in $lines) { $out.Add($l) }
        $out.Add('')
        foreach ($l in $Block) { $out.Add($l) }
    }
    Set-Content -LiteralPath $FilePath -Value $out.ToArray() -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Set-ManagedBlock — DRY_RUN-aware wrapper around Invoke-BlockUpsert
# ---------------------------------------------------------------------------
function Set-ManagedBlock {
    <#
    .SYNOPSIS
      Upserts a marker-delimited block read from SourcePath into TargetPath,
      honoring $env:DRY_RUN.
    .DESCRIPTION
      When $env:DRY_RUN equals '1', logs the intended action and returns without
      writing. Otherwise reads SourcePath (the block, markers included) and
      delegates to Invoke-BlockUpsert.
    .PARAMETER TargetPath
      The file to update.
    .PARAMETER StartMarker
      The exact line that opens the managed block.
    .PARAMETER EndMarker
      The exact line that closes the managed block.
    .PARAMETER SourcePath
      Path to the block source file (markers included).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TargetPath,
        [Parameter(Mandatory)] [string] $StartMarker,
        [Parameter(Mandatory)] [string] $EndMarker,
        [Parameter(Mandatory)] [string] $SourcePath
    )

    if ($env:DRY_RUN -eq '1') {
        Write-Host "[dry-run] would upsert $StartMarker..$EndMarker block into $TargetPath"
        return
    }

    $block = @(Get-Content -LiteralPath $SourcePath)
    Invoke-BlockUpsert -FilePath $TargetPath -StartMarker $StartMarker -EndMarker $EndMarker -Block $block
}
