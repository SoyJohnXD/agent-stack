<#
.SYNOPSIS
  Pester test stubs for agent-stack.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.

  Run on Windows:
      Invoke-Pester -Path .\agent-stack.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    # Dot-source so all functions load without triggering main().
    . "$PSScriptRoot\agent-stack.ps1"
}

# ---------------------------------------------------------------------------
# Get-PositionalArgs — flag parsing
# ---------------------------------------------------------------------------
Describe 'Get-PositionalArgs - flag parsing' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun    = $env:DRY_RUN
        $script:savedAssumeYes = $env:ASSUME_YES
        $script:savedSkipCodex = $env:SKIP_CODEX
    }
    AfterEach {
        $env:DRY_RUN    = $script:savedDryRun
        $env:ASSUME_YES = $script:savedAssumeYes
        $env:SKIP_CODEX = $script:savedSkipCodex
    }

    It '--dry-run sets DRY_RUN to 1 and removes the flag from positionals' {
        $pos = Get-PositionalArgs '--dry-run' 'sync'
        $env:DRY_RUN | Should -Be '1'
        $pos | Should -Contain 'sync'
        $pos | Should -Not -Contain '--dry-run'
    }

    It '--yes sets ASSUME_YES to 1' {
        Get-PositionalArgs '--yes' | Out-Null
        $env:ASSUME_YES | Should -Be '1'
    }

    It '--skip-codex sets SKIP_CODEX to 1' {
        Get-PositionalArgs '--skip-codex' | Out-Null
        $env:SKIP_CODEX | Should -Be '1'
    }

    It 'returns non-flag arguments as positionals' {
        $pos = Get-PositionalArgs 'doctor'
        $pos | Should -Contain 'doctor'
    }

    It 'multiple flags + subcommand: only subcommand in positionals' {
        $pos = Get-PositionalArgs '--dry-run' '--yes' 'gentle'
        $pos | Should -Contain 'gentle'
        $pos.Count | Should -Be 1
    }
}

# ---------------------------------------------------------------------------
# Show-Menu
# ---------------------------------------------------------------------------
Describe 'Show-Menu - TUI menu' -Skip:(-not $script:IsWindowsHost) {

    It 'Show-Menu is available after dot-sourcing' {
        Get-Command Show-Menu -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Menu map contains all expected subcommands' {
        $values = @($script:Menu.Values)
        $values | Should -Contain 'bootstrap'
        $values | Should -Contain 'sync'
        $values | Should -Contain 'doctor'
        $values | Should -Contain 'all'
        $values | Should -Contain 'exit'
    }
}

# ---------------------------------------------------------------------------
# Invoke-Dispatch — subcommand routing
# ---------------------------------------------------------------------------
Describe 'Invoke-Dispatch - subcommand routing' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun = $env:DRY_RUN
        $env:DRY_RUN = '1'
    }
    AfterEach {
        $env:DRY_RUN = $script:savedDryRun
    }

    It 'dispatches doctor to phase_doctor without throwing' {
        { Invoke-Dispatch -Subcommand 'doctor' } | Should -Not -Throw
    }

    It 'dispatches gentle to phase_gentle without throwing' {
        { Invoke-Dispatch -Subcommand 'gentle' } | Should -Not -Throw
    }

    It 'dispatches update-clis to phase_update_clis without throwing' {
        { Invoke-Dispatch -Subcommand 'update-clis' } | Should -Not -Throw
    }

    It 'stub subcommand persona emits a warning and does not throw' {
        $output = Invoke-Dispatch -Subcommand 'persona' 3>&1 | Out-String
        $output | Should -Match 'not yet implemented on Windows'
    }

    It 'stub subcommand codex emits a warning and does not throw' {
        $output = Invoke-Dispatch -Subcommand 'codex' 3>&1 | Out-String
        $output | Should -Match 'not yet implemented on Windows'
    }

    It 'stub subcommand overlay emits a warning and does not throw' {
        $output = Invoke-Dispatch -Subcommand 'overlay' 3>&1 | Out-String
        $output | Should -Match 'not yet implemented on Windows'
    }

    It 'unknown subcommand throws or exits non-zero' {
        # Invoke-Dispatch writes an error for unknown subcommands.
        { Invoke-Dispatch -Subcommand 'foobar-unknown' } | Should -Throw
    }
}
