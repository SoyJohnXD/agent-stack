<#
.SYNOPSIS
  Pester test stubs for lib/claude.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.
  Mirrors lib/claude.test.sh.

  Run on Windows:
      Invoke-Pester -Path .\lib\claude.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\platform-windows.ps1"
    . "$PSScriptRoot\common.ps1"
    . "$PSScriptRoot\claude.ps1"
}

Describe 'phase_claude_hooks - hook script install + settings.json wiring' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun = $env:DRY_RUN
        $script:savedHome   = $env:USERPROFILE
        $env:DRY_RUN = '0'

        $script:tmpHome = Join-Path $env:TEMP ("claude-home-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tmpHome -Force | Out-Null
        $env:USERPROFILE = $script:tmpHome

        $script:hooksSrc = Join-Path $env:TEMP ("claude-hooks-src-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:hooksSrc -Force | Out-Null
        foreach ($script_ in @('check-plan-contract.sh', 'clean-code-gate.sh', 'skill-registry-refresh.sh')) {
            "#!/usr/bin/env bash`necho `"$script_`"" | Set-Content -LiteralPath (Join-Path $script:hooksSrc $script_) -Encoding UTF8
        }
    }
    AfterEach {
        $env:DRY_RUN = $script:savedDryRun
        $env:USERPROFILE = $script:savedHome
        Remove-Item $script:tmpHome -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $script:hooksSrc -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'copies all 3 hook scripts into ~/.claude/hooks' {
        Install-ClaudeHookScripts -SourceDir $script:hooksSrc

        $destDir = Get-ClaudeHooksDir
        foreach ($script_ in @('check-plan-contract.sh', 'clean-code-gate.sh', 'skill-registry-refresh.sh')) {
            Test-Path -LiteralPath (Join-Path $destDir $script_) | Should -Be $true
        }
    }

    It 'wires PreToolUse, Stop and UserPromptSubmit while preserving unrelated keys' {
        $settingsFile = Get-ClaudeSettingsFile
        New-Item -ItemType Directory -Path (Split-Path -Parent $settingsFile) -Force | Out-Null
        @'
{
  "permissions": { "deny": ["Bash(rm -rf /)"], "defaultMode": "bypassPermissions" },
  "model": "claude-fable-5[1m]",
  "hooks": {
    "UserPromptSubmit": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "gentle-ai skill-registry refresh --quiet --no-gitignore --cwd \"$PWD\" || true" } ] }
    ]
  },
  "outputStyle": "Gentleman"
}
'@ | Set-Content -LiteralPath $settingsFile -Encoding UTF8

        Set-ClaudeSettingsHooks

        $settings = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json

        ($settings.hooks.PreToolUse | Where-Object { $_.matcher -eq 'ExitPlanMode' }).hooks[0].command | Should -Match 'check-plan-contract\.sh'
        $settings.hooks.Stop[0].hooks[0].command | Should -Match 'clean-code-gate\.sh'
        $settings.hooks.UserPromptSubmit[0].hooks[0].command | Should -Match 'skill-registry-refresh\.sh'
        $settings.permissions.deny[0] | Should -Be 'Bash(rm -rf /)'
        $settings.outputStyle | Should -Be 'Gentleman'
    }

    It 'is idempotent on a second run (settings.json content equal)' {
        $settingsFile = Get-ClaudeSettingsFile
        New-Item -ItemType Directory -Path (Split-Path -Parent $settingsFile) -Force | Out-Null
        '{}' | Set-Content -LiteralPath $settingsFile -Encoding UTF8

        Set-ClaudeSettingsHooks
        $afterRun1 = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20

        Set-ClaudeSettingsHooks
        $afterRun2 = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20

        $afterRun2 | Should -Be $afterRun1
    }

    It 'does not create files in dry-run mode' {
        $env:DRY_RUN = '1'

        phase_claude_hooks

        Test-Path -LiteralPath (Get-ClaudeHooksDir) | Should -Be $false
        Test-Path -LiteralPath (Get-ClaudeSettingsFile) | Should -Be $false
    }
}
