<#
.SYNOPSIS
  Pester test stubs for bootstrap.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.

  Run on Windows:
      Invoke-Pester -Path .\bootstrap.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    # Dot-source bootstrap.ps1 so main() and Install-GumWindows are available
    # without triggering the entry guard.
    . "$PSScriptRoot\bootstrap.ps1"
}

# ---------------------------------------------------------------------------
# Install-GumWindows
# ---------------------------------------------------------------------------
Describe 'Install-GumWindows - gum installation' -Skip:(-not $script:IsWindowsHost) {

    It 'Install-GumWindows is available after dot-sourcing' {
        Get-Command Install-GumWindows -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'skips silently when gum is already on PATH' {
        if (Get-Command gum -ErrorAction SilentlyContinue) {
            $output = Install-GumWindows 6>&1 | Out-String
            $output | Should -Match '\[skip\]'
        } else {
            Set-ItResult -Skipped -Because 'gum not on PATH; cannot test skip path'
        }
    }

    It 'does not throw in dry-run mode (download step is skipped)' {
        if (-not (Get-Command gum -ErrorAction SilentlyContinue)) {
            $savedDryRun = $env:DRY_RUN
            try {
                $env:DRY_RUN = '1'
                { Install-GumWindows -Version '0.17.0' } | Should -Not -Throw
            } finally {
                $env:DRY_RUN = $savedDryRun
            }
        } else {
            Set-ItResult -Skipped -Because 'gum already installed; dry-run install path not exercised'
        }
    }
}

# ---------------------------------------------------------------------------
# bootstrap.ps1 end-to-end (dry-run)
# ---------------------------------------------------------------------------
Describe 'bootstrap.ps1 - dry-run end-to-end' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun    = $env:DRY_RUN
        $script:savedAssumeYes = $env:ASSUME_YES
        $script:savedSkipCodex = $env:SKIP_CODEX
        $env:DRY_RUN    = '1'
        $env:ASSUME_YES = '0'
        $env:SKIP_CODEX = '0'
    }
    AfterEach {
        $env:DRY_RUN    = $script:savedDryRun
        $env:ASSUME_YES = $script:savedAssumeYes
        $env:SKIP_CODEX = $script:savedSkipCodex
    }

    It 'main --dry-run completes without throwing' {
        { main @('--dry-run') } | Should -Not -Throw
    }

    It 'dry-run output contains [dry-run] lines for git operations' {
        $output = main @('--dry-run') 6>&1 2>&1 | Out-String
        $output | Should -Match '\[dry-run\]'
    }

    It '--with-claude prints installation instructions without throwing' {
        { main @('--dry-run', '--with-claude') } | Should -Not -Throw
    }

    It 'repos from manifest are processed in dry-run (git clone/pull lines)' {
        $manifestPath = Join-Path $PSScriptRoot 'repos.manifest'
        if (Test-Path $manifestPath) {
            $output = main @('--dry-run') 6>&1 2>&1 | Out-String
            # At least one [dry-run] git line should appear for manifest repos.
            $output | Should -Match '\[dry-run\] git'
        } else {
            Set-ItResult -Skipped -Because 'repos.manifest not found'
        }
    }
}
