<#
.SYNOPSIS
  Health-check phase for agent-stack on Windows.

.DESCRIPTION
  Dot-source this module after lib/common.ps1 to make phase_doctor and
  Test-AgentTool available.

  Test-AgentTool checks a single tool:
    - Required tools: FAIL banner + counter increment when absent/error.
    - Optional tools: WARN banner only, counter NOT incremented.

  phase_doctor checks six tools in order:
    claude, codex, opencode, gentle-ai, git  (required)
    gum                                       (optional)

  Returns the total failure count (0 = healthy).

  PowerShell 5.1+ compatible.
#>

if ($script:_DoctorPs1Loaded) { return }
$script:_DoctorPs1Loaded = $true

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-scoped failure counter. Reset at the start of each phase_doctor call
# so the function is safe for repeated invocations in the same session.
$script:_DoctorFails = 0

function Test-AgentTool {
    <#
    .SYNOPSIS
      Checks a single CLI tool and reports PASS / FAIL / WARN.
    .PARAMETER Cmd
      Array where [0] is the executable and [1..n] are its arguments
      (typically @('tool', '--version')).
    .PARAMETER Label
      Human-readable name shown in the output line.
    .PARAMETER Optional
      When set, absence or errors emit WARN and do NOT increment the fail counter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Cmd,

        [Parameter(Mandatory)]
        [string] $Label,

        [switch] $Optional
    )

    $exe = $Cmd[0]

    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        if ($Optional) {
            Write-Host "[WARN] $Label not installed (optional)"
        } else {
            Write-Host "[FAIL] $Label not installed"
            $script:_DoctorFails++
        }
        return
    }

    $cmdArgs = if ($Cmd.Count -gt 1) { $Cmd[1..($Cmd.Count - 1)] } else { @() }
    try {
        & $exe @cmdArgs 2>&1 | Out-Null
        Write-Host "[PASS] $Label"
    } catch {
        if ($Optional) {
            Write-Host "[WARN] $Label errored (optional)"
        } else {
            Write-Host "[FAIL] $Label errored"
            $script:_DoctorFails++
        }
    }
}

function Test-DuplicateBinaries {
    <#
    .SYNOPSIS
      Warn-only: detects when a managed binary resolves to more than one
      location on PATH.

    .DESCRIPTION
      Decision Ledger: the bash check is hardcoded to ~/.local/bin vs
      ~/go/bin because that's agent-stack's fixed install layout on
      Linux/macOS. Windows has no equivalent fixed pair of directories
      (no ~/.local/bin convention), so instead this checks PATH directly
      via Get-Command -All: if a binary name resolves to more than one
      executable on PATH, that's the same class of problem (duplicate
      install, ambiguous which one runs) and is reported the same way.

      Never increments $script:_DoctorFails.
    #>
    [CmdletBinding()]
    param()

    foreach ($name in @('gentle-ai', 'engram')) {
        $matches = @(Get-Command $name -All -ErrorAction SilentlyContinue)
        if ($matches.Count -gt 1) {
            Write-Host "[WARN] duplicate binary: $name"
            foreach ($m in $matches) {
                $version = try { & $m.Source --version 2>&1 } catch { '(unknown version)' }
                Write-Host "       $($m.Source) -> $version"
            }
            $extra = $matches | Select-Object -Skip 1
            foreach ($m in $extra) {
                Write-Host "       suggested: remove `"$($m.Source)`""
            }
        }
    }
}

function Test-PathDuplicates {
    <#
    .SYNOPSIS
      Warn-only: detects duplicate directory entries in $env:PATH.

    .DESCRIPTION
      Decision Ledger: the bash check scans ~/.bashrc for repeated PATH=
      assignment lines because that's where Linux/macOS shells accumulate
      duplicates across re-installs. Windows has no ~/.bashrc; PATH is
      assembled from Machine + User environment variables and is the
      directly observable artifact, so this checks $env:PATH itself for
      duplicate entries and suggests deduplicating the User PATH via
      Environment Variables settings (or `setx PATH`) so it doesn't keep
      growing on every re-install.

      Never increments $script:_DoctorFails.
    #>
    [CmdletBinding()]
    param()

    $entries = $env:PATH -split ';' | Where-Object { $_ -ne '' }
    $seen = @{}
    $warned = @{}

    foreach ($entry in $entries) {
        $key = $entry.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            if (-not $warned.ContainsKey($key)) {
                Write-Host "[WARN] PATH contains '$entry' more than once"
                Write-Host "       suggested: remove the duplicate entry from the User PATH (Environment Variables) so it doesn't keep growing on every re-install"
                $warned[$key] = $true
            }
        } else {
            $seen[$key] = $true
        }
    }
}

function phase_doctor {
    <#
    .SYNOPSIS
      Runs health checks against all required and optional agent tools.
    .DESCRIPTION
      Checks claude, codex, opencode, gentle-ai, git (required) and gum (optional).
      Then runs warn-only environment checks (duplicate binaries, duplicate
      PATH entries) that never affect the failure counter.
      Resets the failure counter at entry for idempotent re-runs.
    .OUTPUTS
      [int] Number of failures (0 = all required tools healthy).
    #>

    Write-AgentLog -Phase start -Action 'doctor'

    # Reset counter so repeated calls don't accumulate across invocations.
    $script:_DoctorFails = 0

    Test-AgentTool -Cmd @('claude',    '--version') -Label 'Claude Code'
    Test-AgentTool -Cmd @('codex',     '--version') -Label 'Codex'
    Test-AgentTool -Cmd @('opencode',  '--version') -Label 'OpenCode'
    Test-AgentTool -Cmd @('gentle-ai', '--version') -Label 'gentle-ai'
    Test-AgentTool -Cmd @('git',       '--version') -Label 'git'
    Test-AgentTool -Cmd @('gum',       '--version') -Label 'gum' -Optional

    Test-DuplicateBinaries
    Test-PathDuplicates

    Write-Host "`nFailures: $script:_DoctorFails"

    Write-AgentLog -Phase finish -Action 'doctor'

    return $script:_DoctorFails
}
