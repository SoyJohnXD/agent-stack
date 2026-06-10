<#
.SYNOPSIS
  Pester test stubs for lib/planmode.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.
  Mirrors lib/planmode.test.sh (T1-T5).

  Run on Windows:
      Invoke-Pester -Path .\lib\planmode.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\platform-windows.ps1"
    . "$PSScriptRoot\common.ps1"
    . "$PSScriptRoot\planmode.ps1"
}

Describe 'phase_planmode - block upsert across the 3 targets' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun = $env:DRY_RUN
        $script:savedHome   = $env:USERPROFILE
        $env:DRY_RUN = '0'

        $script:tmpHome = Join-Path $env:TEMP ("planmode-home-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tmpHome -Force | Out-Null
        $env:USERPROFILE = $script:tmpHome
        $env:AGENT_STACK_OPENCODE_DIR = Join-Path $script:tmpHome 'opencode-config'

        $script:claudeMd  = Join-Path $script:tmpHome '.claude\CLAUDE.md'
        $script:codexMd   = Join-Path $script:tmpHome '.codex\AGENTS.override.md'
        $script:opencodeMd = Join-Path $env:AGENT_STACK_OPENCODE_DIR 'AGENTS.md'

        foreach ($f in @($script:claudeMd, $script:codexMd, $script:opencodeMd)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $f) -Force | Out-Null
        }
    }
    AfterEach {
        $env:DRY_RUN = $script:savedDryRun
        $env:USERPROFILE = $script:savedHome
        Remove-Item Env:\AGENT_STACK_OPENCODE_DIR -ErrorAction SilentlyContinue
        Remove-Item $script:tmpHome -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'inserts plan-mode, serialization and gate-wiring blocks into all 3 targets' {
        'preamble' | Set-Content -LiteralPath $script:claudeMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:codexMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:opencodeMd -Encoding UTF8

        phase_planmode

        foreach ($f in @($script:claudeMd, $script:codexMd, $script:opencodeMd)) {
            $content = Get-Content -LiteralPath $f -Raw
            $content | Should -Match '<!-- plan-mode:start -->'
            $content | Should -Match '<!-- serialization:start -->'
            $content | Should -Match '<!-- gate-wiring:start -->'
        }
    }

    It 'is idempotent on a second run (CLAUDE.md byte-identical)' {
        'preamble' | Set-Content -LiteralPath $script:claudeMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:codexMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:opencodeMd -Encoding UTF8

        phase_planmode
        $afterRun1 = Get-Content -LiteralPath $script:claudeMd -Raw

        phase_planmode
        $afterRun2 = Get-Content -LiteralPath $script:claudeMd -Raw

        $afterRun2 | Should -Be $afterRun1
    }

    It 'replaces existing blocks in place, preserving surrounding content' {
        @(
            'HEAD'
            '<!-- plan-mode:start -->'
            'OLD-PLANMODE'
            '<!-- plan-mode:end -->'
            'TAIL'
        ) | Set-Content -LiteralPath $script:claudeMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:codexMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:opencodeMd -Encoding UTF8

        phase_planmode

        $lines = Get-Content -LiteralPath $script:claudeMd
        $lines | Should -Contain 'HEAD'
        $lines | Should -Contain 'TAIL'
        $lines | Should -Not -Contain 'OLD-PLANMODE'
        ($lines | Where-Object { $_ -eq '<!-- plan-mode:start -->' }).Count | Should -Be 1
    }

    It 'does not create or modify destination files in dry-run mode' {
        $env:DRY_RUN = '1'

        phase_planmode

        Test-Path -LiteralPath $script:claudeMd | Should -Be $false
        Test-Path -LiteralPath $script:codexMd | Should -Be $false
        Test-Path -LiteralPath $script:opencodeMd | Should -Be $false
    }

    It 'leaves a foreign gentle-ai marker block untouched' {
        @(
            'preamble line'
            '<!-- gentle-ai:sdd-orchestrator -->'
            'gentle-ai sdd-orchestrator content line 1'
            'gentle-ai sdd-orchestrator content line 2'
            '<!-- /gentle-ai:sdd-orchestrator -->'
            'middle line'
            '<!-- plan-mode:start -->'
            'OLD-PLANMODE'
            '<!-- plan-mode:end -->'
            'trailing line'
        ) | Set-Content -LiteralPath $script:claudeMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:codexMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:opencodeMd -Encoding UTF8

        phase_planmode

        $lines = Get-Content -LiteralPath $script:claudeMd
        $lines | Should -Contain '<!-- gentle-ai:sdd-orchestrator -->'
        $lines | Should -Contain 'gentle-ai sdd-orchestrator content line 1'
        $lines | Should -Contain 'gentle-ai sdd-orchestrator content line 2'
        $lines | Should -Contain '<!-- /gentle-ai:sdd-orchestrator -->'
    }

    It 'creates a missing target parent directory instead of skipping it' {
        Remove-Item (Split-Path -Parent $script:codexMd) -Recurse -Force
        'preamble' | Set-Content -LiteralPath $script:claudeMd -Encoding UTF8
        'preamble' | Set-Content -LiteralPath $script:opencodeMd -Encoding UTF8

        phase_planmode

        Test-Path -LiteralPath $script:codexMd | Should -Be $true
        $content = Get-Content -LiteralPath $script:codexMd -Raw
        $content | Should -Match '<!-- plan-mode:start -->'
    }
}
