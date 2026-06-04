<#
.SYNOPSIS
  Pester tests for lib/platform-windows.ps1.

.DESCRIPTION
  Windows-environment tests for the foundation primitives. These exercise real
  filesystem junctions and the real user PATH/env surface, so they ONLY run on
  Windows. On non-Windows hosts every block is skipped via the $script:IsWindowsHost
  guard, so the bash CI on Linux stays green while the Windows runner (SDD-6)
  executes them for real.

  Run on Windows:
      Invoke-Pester -Path .\lib\platform-windows.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\platform-windows.ps1"
}

Describe 'Group 3 - Config path registry' -Skip:(-not $script:IsWindowsHost) {

    It 'Get-AgentStackPaths returns all expected keys' {
        $paths = Get-AgentStackPaths
        $expected = @(
            'claude-config', 'codex-root', 'opencode-config', 'launcher-dir',
            'agent-stack-local', 'agents-skills', 'pi-skills', 'claude-skills'
        )
        foreach ($k in $expected) { $paths.ContainsKey($k) | Should -BeTrue }
    }

    It 'claude-config maps under USERPROFILE\.claude' {
        Get-AgentStackPath 'claude-config' | Should -Be (Join-Path $env:USERPROFILE '.claude')
    }

    It 'opencode-config defaults to APPDATA\opencode' {
        $saved = $env:AGENT_STACK_OPENCODE_DIR
        try {
            $env:AGENT_STACK_OPENCODE_DIR = $null
            Get-AgentStackPath 'opencode-config' | Should -Be (Join-Path $env:APPDATA 'opencode')
        } finally { $env:AGENT_STACK_OPENCODE_DIR = $saved }
    }

    It 'opencode-config honors AGENT_STACK_OPENCODE_DIR override' {
        $saved = $env:AGENT_STACK_OPENCODE_DIR
        try {
            $env:AGENT_STACK_OPENCODE_DIR = 'D:\custom\opencode'
            Get-AgentStackPath 'opencode-config' | Should -Be 'D:\custom\opencode'
        } finally { $env:AGENT_STACK_OPENCODE_DIR = $saved }
    }

    It 'Get-AgentStackPath throws on unknown key' {
        { Get-AgentStackPath 'does-not-exist' } | Should -Throw
    }
}

Describe 'Group 2 - Junction module' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:root   = Join-Path $env:TEMP ("aswin-" + [guid]::NewGuid().ToString('N'))
        $script:target = Join-Path $script:root 'target'
        $script:link   = Join-Path $script:root 'link'
        New-Item -ItemType Directory -Path $script:target -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:root) {
            Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'New-Junction creates a junction to target' {
        New-Junction -Path $script:link -Target $script:target | Should -BeTrue
        Test-JunctionValid -Path $script:link -Target $script:target | Should -BeTrue
    }

    It 'New-Junction is idempotent (no-op on second call)' {
        New-Junction -Path $script:link -Target $script:target | Out-Null
        New-Junction -Path $script:link -Target $script:target | Should -BeFalse
    }

    It 'New-Junction throws when target missing' {
        { New-Junction -Path $script:link -Target (Join-Path $script:root 'nope') } | Should -Throw
    }

    It 'New-Junction repoints a junction aimed elsewhere' {
        $other = Join-Path $script:root 'other'
        New-Item -ItemType Directory -Path $other -Force | Out-Null
        New-Junction -Path $script:link -Target $other | Out-Null
        New-Junction -Path $script:link -Target $script:target | Should -BeTrue
        Test-JunctionValid -Path $script:link -Target $script:target | Should -BeTrue
    }

    It 'New-Junction refuses to overwrite a real directory' {
        New-Item -ItemType Directory -Path $script:link -Force | Out-Null
        { New-Junction -Path $script:link -Target $script:target } | Should -Throw
    }

    It 'Get-JunctionTarget returns null for a plain directory' {
        Get-JunctionTarget -Path $script:target | Should -BeNullOrEmpty
    }

    It 'Get-JunctionTarget returns null for a missing path' {
        Get-JunctionTarget -Path (Join-Path $script:root 'ghost') | Should -BeNullOrEmpty
    }

    It 'Remove-Junction removes only the junction, not the target contents' {
        $sentinel = Join-Path $script:target 'keep.txt'
        Set-Content -LiteralPath $sentinel -Value 'data'
        New-Junction -Path $script:link -Target $script:target | Out-Null
        Remove-Junction -Path $script:link | Should -BeTrue
        Test-Path -LiteralPath $script:link | Should -BeFalse
        Test-Path -LiteralPath $sentinel | Should -BeTrue
    }

    It 'Remove-Junction refuses to delete a real directory' {
        New-Item -ItemType Directory -Path $script:link -Force | Out-Null
        { Remove-Junction -Path $script:link } | Should -Throw
    }

    It 'Remove-Junction returns false when nothing exists' {
        Remove-Junction -Path (Join-Path $script:root 'ghost') | Should -BeFalse
    }
}

Describe 'Group 1 - PATH shim' -Skip:(-not $script:IsWindowsHost) {

    # These tests mutate the real user PATH. Save and restore around each test
    # to avoid leaking state on the CI runner.
    BeforeEach {
        $script:savedPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
        $script:savedLocalAppData = $env:LOCALAPPDATA
        $script:sandbox = Join-Path $env:TEMP ("aswin-path-" + [guid]::NewGuid().ToString('N'))
        $env:LOCALAPPDATA = $script:sandbox
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable('Path', $script:savedPath, [EnvironmentVariableTarget]::User)
        $env:LOCALAPPDATA = $script:savedLocalAppData
        if (Test-Path -LiteralPath $script:sandbox) {
            Remove-Item -LiteralPath $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Test-PathShimInstalled is false before install' {
        Test-PathShimInstalled | Should -BeFalse
    }

    It 'Install-PathShim writes launcher and registers PATH' {
        $launcher = Install-PathShim
        Test-Path -LiteralPath $launcher -PathType Leaf | Should -BeTrue
        Test-PathShimInstalled | Should -BeTrue
    }

    It 'Install-PathShim does not duplicate the PATH entry' {
        Install-PathShim | Out-Null
        Install-PathShim | Out-Null
        $launcherDir = Get-AgentStackPath 'launcher-dir'
        $userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
        $count = @($userPath.Split(';') | Where-Object { $_.TrimEnd('\') -eq $launcherDir.TrimEnd('\') }).Count
        $count | Should -Be 1
    }

    It 'Remove-PathShim deletes launcher and de-registers PATH' {
        Install-PathShim | Out-Null
        Remove-PathShim | Should -BeTrue
        Test-PathShimInstalled | Should -BeFalse
    }

    It 'Remove-PathShim returns false when nothing installed' {
        Remove-PathShim | Should -BeFalse
    }
}
