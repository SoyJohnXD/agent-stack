<#
.SYNOPSIS
  Windows foundation primitives for agent-stack.

.DESCRIPTION
  Reusable PowerShell primitives that port the bash install/symlink/path logic
  to native Windows. Dot-source this module from bootstrap.ps1 and lib/*.ps1:

      . "$PSScriptRoot\platform-windows.ps1"

  This file defines functions ONLY. It performs no work at source time and has
  no top-level side effects. PowerShell 5.1+ compatible (no PS7 features).

  Primitive groups:
    1. PATH shim   — Install/Remove/Test-PathShimInstalled (launcher + user PATH)
    2. Junctions   — New/Remove/Get-JunctionTarget/Test-JunctionValid (mklink /J)
    3. Path map    — Get-AgentStackPaths / Get-AgentStackPath (config registry)
#>

Set-StrictMode -Version Latest

# ===========================================================================
# GROUP 3 — Config path registry
# (defined first; the PATH shim reuses launcher-dir from here)
# ===========================================================================

function Get-AgentStackPaths {
    <#
    .SYNOPSIS
      Returns the full hashtable of canonical Windows config paths for agent-stack.
    .DESCRIPTION
      Single source of truth mirroring the bash HOME-relative paths. OpenCode is
      configurable via $env:AGENT_STACK_OPENCODE_DIR (overrides the APPDATA default).
    .OUTPUTS
      [hashtable] key -> absolute path string.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $userProfile = $env:USERPROFILE
    $appData     = $env:APPDATA
    $localAppData = $env:LOCALAPPDATA

    $opencodeDir = if ($env:AGENT_STACK_OPENCODE_DIR) {
        $env:AGENT_STACK_OPENCODE_DIR
    } else {
        Join-Path $appData 'opencode'
    }

    return @{
        'claude-config'     = Join-Path $userProfile '.claude'
        'codex-root'        = Join-Path $userProfile '.codex'
        'opencode-config'   = $opencodeDir
        'launcher-dir'      = Join-Path $localAppData 'Programs\agent-stack'
        'agent-stack-local' = Join-Path $userProfile '.agent-stack'
        'agents-skills'     = Join-Path $userProfile '.agents\skills'
        'pi-skills'         = Join-Path $userProfile '.pi\agent\skills'
        'claude-skills'     = Join-Path $userProfile '.claude\skills'
    }
}

function Get-AgentStackPath {
    <#
    .SYNOPSIS
      Returns a single canonical path by key. One-call interface for callers.
    .PARAMETER Key
      One of the keys defined by Get-AgentStackPaths.
    .OUTPUTS
      [string] absolute path.
    .EXAMPLE
      Get-AgentStackPath 'claude-config'   # -> C:\Users\me\.claude
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Key
    )

    $paths = Get-AgentStackPaths
    if (-not $paths.ContainsKey($Key)) {
        throw "Get-AgentStackPath: unknown path key '$Key'. Valid keys: $($paths.Keys -join ', ')"
    }
    return $paths[$Key]
}

# ===========================================================================
# GROUP 2 — Junction module (replaces ln -s / rm -rf / readlink for dirs)
# ===========================================================================

function Get-JunctionTarget {
    <#
    .SYNOPSIS
      Returns the target path of a junction (equivalent of bash readlink), or $null.
    .DESCRIPTION
      Uses (Get-Item -Force).Target. -Force is required so hidden/system reparse
      points are read. Returns $null when the path does not exist or is not a
      reparse point (not a junction).
    .PARAMETER Path
      The junction (link) path to inspect.
    .OUTPUTS
      [string] target path, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }

    # ReparsePoint attribute distinguishes a junction from a plain directory.
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        return $null
    }

    if ([string]::IsNullOrEmpty($item.Target)) { return $null }
    return $item.Target
}

function Test-JunctionValid {
    <#
    .SYNOPSIS
      True when Path is a junction pointing at Target (idempotency check).
    .DESCRIPTION
      Mirrors the bash check: [ -L "$link" ] && [ "$(readlink)" == "$canon" ].
      Comparison is case-insensitive and trailing-separator tolerant.
    .PARAMETER Path
      The link path.
    .PARAMETER Target
      The expected target path.
    .OUTPUTS
      [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Target
    )

    $current = Get-JunctionTarget -Path $Path
    if ($null -eq $current) { return $false }

    $normCurrent = $current.TrimEnd('\', '/')
    $normTarget  = $Target.TrimEnd('\', '/')
    return [string]::Equals($normCurrent, $normTarget, [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-Junction {
    <#
    .SYNOPSIS
      Removes a junction, but ONLY if it is actually a junction (safety).
    .DESCRIPTION
      Replaces `rm -rf "$link"` guarded by the symlink check. Refuses to delete a
      plain directory so a misconfigured call cannot wipe real content. Deleting a
      junction does NOT touch the target's contents (uses [Directory]::Delete,
      recurse=$false — only the reparse point is removed).
    .PARAMETER Path
      The junction path to remove.
    .OUTPUTS
      [bool] $true if a junction was removed, $false if nothing to remove.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $target = Get-JunctionTarget -Path $Path
    if ($null -eq $target) {
        throw "Remove-Junction: '$Path' exists but is not a junction; refusing to delete."
    }

    # recurse=$false removes only the reparse point, never the target contents.
    [System.IO.Directory]::Delete($Path, $false)
    return $true
}

function New-Junction {
    <#
    .SYNOPSIS
      Creates a directory junction at Path pointing to Target. Idempotent.
    .DESCRIPTION
      Replaces `ln -s "$canon" "$link"`. Uses `cmd /c mklink /J` which creates a
      junction WITHOUT requiring admin or Developer Mode. Idempotency mirrors the
      bash check: if Path is already a junction to Target, returns without work.
      If Path exists pointing elsewhere (or is a stale junction), it is removed and
      recreated. The parent directory of Path is created if missing.
    .PARAMETER Path
      The link path to create.
    .PARAMETER Target
      The existing directory the junction points to.
    .OUTPUTS
      [bool] $true if created/recreated, $false if already valid (no-op).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Target
    )

    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        throw "New-Junction: target directory does not exist: $Target"
    }

    # Idempotent: already linked to the right target.
    if (Test-JunctionValid -Path $Path -Target $Target) {
        return $false
    }

    # Clear an existing junction (wrong target) or fail loudly on a real dir/file.
    if (Test-Path -LiteralPath $Path) {
        $existingTarget = Get-JunctionTarget -Path $Path
        if ($null -eq $existingTarget) {
            throw "New-Junction: '$Path' exists and is not a junction; refusing to overwrite."
        }
        [void](Remove-Junction -Path $Path)
    }

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # mklink /J creates a junction with no privilege requirement.
    $output = cmd /c mklink /J "`"$Path`"" "`"$Target`"" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "New-Junction: mklink failed for '$Path' -> '$Target': $output"
    }
    return $true
}

# ===========================================================================
# GROUP 1 — PATH shim (replaces ensure_symlink for the CLI entrypoint)
# ===========================================================================

function Test-PathShimInstalled {
    <#
    .SYNOPSIS
      True when the launcher file exists AND its dir is on the user PATH.
    .OUTPUTS
      [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $launcherDir = Get-AgentStackPath 'launcher-dir'
    $launcher    = Join-Path $launcherDir 'agent-stack.ps1'

    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { return $false }

    $userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
    if ([string]::IsNullOrEmpty($userPath)) { return $false }

    $entries = $userPath.Split(';') | ForEach-Object { $_.TrimEnd('\') }
    return $entries -contains $launcherDir.TrimEnd('\')
}

function Install-PathShim {
    <#
    .SYNOPSIS
      Installs the agent-stack launcher and registers its dir on the user PATH.
    .DESCRIPTION
      Windows equivalent of `ensure_symlink "$AGENT_STACK_LOCAL/agent-stack"
      "~/.local/bin/agent-stack"`. Because mklink to a *file* needs Developer Mode,
      this writes a real `.ps1` launcher instead of a symlink. The launcher is a
      STUB in this SDD; actual bash-invocation logic is deferred to SDD-3.

      PATH is updated without duplication: read current user PATH, append the
      launcher dir only if absent, then SetEnvironmentVariable at User scope.
    .OUTPUTS
      [string] full path to the launcher file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $launcherDir = Get-AgentStackPath 'launcher-dir'
    if (-not (Test-Path -LiteralPath $launcherDir)) {
        New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
    }

    $launcher = Join-Path $launcherDir 'agent-stack.ps1'

    # STUB launcher — SDD-3 replaces the body with real bash forwarding.
    $stub = @'
#!/usr/bin/env pwsh
# agent-stack launcher (STUB - SDD-2). Real bash-forwarding lands in SDD-3.
Write-Error 'agent-stack launcher is not yet implemented (SDD-2 stub).'
exit 1
'@
    Set-Content -LiteralPath $launcher -Value $stub -Encoding UTF8

    # Add to user PATH without duplicating.
    $userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
    if ([string]::IsNullOrEmpty($userPath)) { $userPath = '' }

    $entries = @($userPath.Split(';') | Where-Object { $_ -ne '' })
    $already = $entries | Where-Object { $_.TrimEnd('\') -eq $launcherDir.TrimEnd('\') }

    if (-not $already) {
        $newPath = if ($userPath -eq '') { $launcherDir } else { "$userPath;$launcherDir" }
        [Environment]::SetEnvironmentVariable('Path', $newPath, [EnvironmentVariableTarget]::User)
    }

    return $launcher
}

function Remove-PathShim {
    <#
    .SYNOPSIS
      Removes the launcher file and de-registers its dir from the user PATH.
    .DESCRIPTION
      PATH removal: split current user PATH, filter out the launcher dir
      (case-insensitive, separator-tolerant), set the rebuilt value.
    .OUTPUTS
      [bool] $true if anything was removed/changed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $changed = $false
    $launcherDir = Get-AgentStackPath 'launcher-dir'
    $launcher    = Join-Path $launcherDir 'agent-stack.ps1'

    if (Test-Path -LiteralPath $launcher -PathType Leaf) {
        Remove-Item -LiteralPath $launcher -Force
        $changed = $true
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
    if (-not [string]::IsNullOrEmpty($userPath)) {
        $target = $launcherDir.TrimEnd('\')
        $kept = @($userPath.Split(';') | Where-Object {
            $_ -ne '' -and $_.TrimEnd('\') -ne $target
        })
        $newPath = $kept -join ';'
        if ($newPath -ne $userPath) {
            [Environment]::SetEnvironmentVariable('Path', $newPath, [EnvironmentVariableTarget]::User)
            $changed = $true
        }
    }

    return $changed
}
