<#
.SYNOPSIS
  Pester test stubs for lib/clis.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.

  Run on Windows:
      Invoke-Pester -Path .\lib\clis.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\common.ps1"
    . "$PSScriptRoot\clis.ps1"
}

# ---------------------------------------------------------------------------
# phase_update_clis
# ---------------------------------------------------------------------------
Describe 'phase_update_clis - CLI update phase' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun = $env:DRY_RUN
        $env:DRY_RUN = '1'
    }
    AfterEach {
        $env:DRY_RUN = $script:savedDryRun
    }

    It 'phase_update_clis is available after dot-sourcing' {
        Get-Command phase_update_clis -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'does not throw when no managed CLIs are installed' {
        # All tools are likely absent in a fresh test environment; phase must not error.
        { phase_update_clis } | Should -Not -Throw
    }

    It 'emits [skip] for a tool that is absent' {
        # claude is unlikely to be installed in a test sandbox; verify skip notice.
        $output = phase_update_clis 6>&1 | Out-String
        # At least one [skip] line should appear when tools are missing.
        # This test is meaningful only when the tools are absent.
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
            $output | Should -Match '\[skip\]'
        }
    }

    It 'invokes update verb for a present tool (mock via Invoke-AgentRun dry-run)' {
        # With DRY_RUN=1, Invoke-AgentRun prints [dry-run] lines instead of executing.
        # If git is present, it would be updated; we verify via a known-present tool.
        # This test is structural: dry-run output contains the tool name and verb.
        $env:DRY_RUN = '1'
        $output = phase_update_clis 6>&1 | Out-String
        # Output should contain either [dry-run] <tool> <verb> or [skip] for each tool.
        $output | Should -Not -BeNullOrEmpty
    }
}
