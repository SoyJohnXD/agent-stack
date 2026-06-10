<#
.SYNOPSIS
  Pester test stubs for lib/overlay.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.

  Mirrors lib/overlay.test.sh T14d: when intent-overlay is not on PATH,
  phase_overlay falls back to the repo-local intent-overlay.ps1 script.

  Run on Windows:
      Invoke-Pester -Path .\lib\overlay.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\common.ps1"
    . "$PSScriptRoot\overlay.ps1"
}

# ---------------------------------------------------------------------------
# phase_overlay — repo-path fallback when intent-overlay is not on PATH
# ---------------------------------------------------------------------------
Describe 'phase_overlay - intent-overlay fallback' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun = $env:DRY_RUN
        $script:savedManifest = $env:MANIFEST_FILE
        $env:DRY_RUN = '0'

        $script:tmpHome = Join-Path $env:TEMP ("overlay-test-" + [guid]::NewGuid().ToString('N'))
        $script:overlayLocal = Join-Path $script:tmpHome 'clean-code-lab'
        New-Item -ItemType Directory -Path (Join-Path $script:overlayLocal '.git') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:overlayLocal 'overlay') -Force | Out-Null

        $script:intentOverlayScript = Join-Path $script:overlayLocal 'overlay\intent-overlay.ps1'
        Set-Content -LiteralPath $script:intentOverlayScript -Value 'Write-Host "intent-overlay $($args -join \" \")"' -Encoding UTF8

        $script:manifestPath = Join-Path $script:tmpHome 'repos.manifest'
        @("overlay | $script:overlayLocal | https://example.com/clean-code-lab.git | main") |
            Set-Content -LiteralPath $script:manifestPath -Encoding UTF8

        $env:MANIFEST_FILE = $script:manifestPath
    }

    AfterEach {
        $env:DRY_RUN = $script:savedDryRun
        $env:MANIFEST_FILE = $script:savedManifest
        Remove-Item $script:tmpHome -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'falls back to the repo-local intent-overlay.ps1 when the binary is not on PATH' {
        if (Get-Command intent-overlay -ErrorAction SilentlyContinue) {
            Set-ItResult -Skipped -Because 'intent-overlay is installed; cannot test absent-PATH fallback'
            return
        }

        $output = phase_overlay 6>&1 | Out-String
        $output | Should -Match 'intent-overlay'
    }

    It 'prints [skip] when neither PATH binary nor repo script is available' {
        if (Get-Command intent-overlay -ErrorAction SilentlyContinue) {
            Set-ItResult -Skipped -Because 'intent-overlay is installed; cannot test absent-PATH fallback'
            return
        }

        Remove-Item -LiteralPath $script:intentOverlayScript -Force

        $output = phase_overlay 6>&1 | Out-String
        $output | Should -Match '\[skip\]'
    }
}
