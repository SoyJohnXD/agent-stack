<#
.SYNOPSIS
  Pester test stubs for lib/gentle.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.

  Run on Windows:
      Invoke-Pester -Path .\lib\gentle.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\common.ps1"
    . "$PSScriptRoot\gentle.ps1"
}

# ---------------------------------------------------------------------------
# phase_gentle
# ---------------------------------------------------------------------------
Describe 'phase_gentle - gentle-ai upgrade and sync' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun = $env:DRY_RUN
        $env:DRY_RUN = '1'
    }
    AfterEach {
        $env:DRY_RUN = $script:savedDryRun
    }

    It 'phase_gentle is available after dot-sourcing' {
        Get-Command phase_gentle -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'does not throw when gentle-ai is absent' {
        # gentle-ai is likely absent in a fresh test environment.
        { phase_gentle } | Should -Not -Throw
    }

    It 'emits [skip] when gentle-ai is not on PATH' {
        if (-not (Get-Command 'gentle-ai' -ErrorAction SilentlyContinue)) {
            $output = phase_gentle 6>&1 | Out-String
            $output | Should -Match '\[skip\]'
        }
    }

    It 'emits both upgrade and sync in dry-run output when gentle-ai is present' {
        if (Get-Command 'gentle-ai' -ErrorAction SilentlyContinue) {
            $env:DRY_RUN = '1'
            $output = phase_gentle 6>&1 | Out-String
            $output | Should -Match 'upgrade'
            $output | Should -Match 'sync'
        } else {
            Set-ItResult -Skipped -Because 'gentle-ai not on PATH in this environment'
        }
    }

    It 'invokes upgrade before sync (order check, dry-run)' {
        if (Get-Command 'gentle-ai' -ErrorAction SilentlyContinue) {
            $env:DRY_RUN = '1'
            $output = phase_gentle 6>&1 | Out-String
            $upgradeIndex = $output.IndexOf('upgrade')
            $syncIndex    = $output.IndexOf('sync')
            $upgradeIndex | Should -BeLessThan $syncIndex
        } else {
            Set-ItResult -Skipped -Because 'gentle-ai not on PATH in this environment'
        }
    }
}
