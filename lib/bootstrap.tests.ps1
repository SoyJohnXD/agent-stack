<#
.SYNOPSIS
  Pester test stubs for lib/bootstrap.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.

  Run on Windows:
      Invoke-Pester -Path .\lib\bootstrap.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\..\lib\platform-windows.ps1"
    . "$PSScriptRoot\..\lib\common.ps1"
    . "$PSScriptRoot\bootstrap.ps1"
}

# ---------------------------------------------------------------------------
# phase_bootstrap — delegation
# ---------------------------------------------------------------------------
Describe 'phase_bootstrap - delegation to top-level bootstrap.ps1' -Skip:(-not $script:IsWindowsHost) {

    It 'phase_bootstrap function is available after dot-sourcing' {
        Get-Command phase_bootstrap -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'phase_bootstrap delegates to bootstrap.ps1 in the parent directory' {
        # Verify the target script exists relative to lib/
        $target = Join-Path $PSScriptRoot '..\bootstrap.ps1'
        Test-Path $target -PathType Leaf | Should -BeTrue
    }

    It 'phase_bootstrap forwards arguments to bootstrap.ps1 (dry-run smoke)' {
        $savedDryRun = $env:DRY_RUN
        try {
            $env:DRY_RUN = '1'
            # With --dry-run, bootstrap.ps1 should print [dry-run] lines and not throw.
            { phase_bootstrap '--dry-run' } | Should -Not -Throw
        } finally {
            $env:DRY_RUN = $savedDryRun
        }
    }
}
