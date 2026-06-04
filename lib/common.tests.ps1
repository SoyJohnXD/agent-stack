<#
.SYNOPSIS
  Pester test stubs for lib/common.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.
  On a Windows runner these stubs act as the RED scaffold: they will fail until
  the corresponding implementation satisfies each scenario.

  Run on Windows:
      Invoke-Pester -Path .\lib\common.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\common.ps1"
}

# ---------------------------------------------------------------------------
# Invoke-AgentRun — dry-run gate
# ---------------------------------------------------------------------------
Describe 'Invoke-AgentRun - dry-run gate' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun = $env:DRY_RUN
    }
    AfterEach {
        $env:DRY_RUN = $script:savedDryRun
    }

    It 'prints [dry-run] prefix and does NOT execute the command' {
        $env:DRY_RUN = '1'
        $output = Invoke-AgentRun git --version 6>&1 | Out-String
        $output | Should -Match '\[dry-run\]'
        # If git actually ran, output would include version info not "[dry-run]"
        $output | Should -Not -Match 'git version'
    }

    It 'executes the command when DRY_RUN is unset' {
        $env:DRY_RUN = '0'
        # git --version exits 0 and produces output; should not throw
        { Invoke-AgentRun git --version } | Should -Not -Throw
    }

    It 'dry-run prints all provided arguments in the output line' {
        $env:DRY_RUN = '1'
        $output = Invoke-AgentRun git clone https://example.com C:\dest 6>&1 | Out-String
        $output | Should -Match 'git'
        $output | Should -Match 'clone'
        $output | Should -Match 'https://example.com'
    }
}

# ---------------------------------------------------------------------------
# Write-AgentLog — banners
# ---------------------------------------------------------------------------
Describe 'Write-AgentLog - phase banners' -Skip:(-not $script:IsWindowsHost) {

    It 'start phase emits >>> START banner' {
        $output = Write-AgentLog -Phase start -Action 'test-phase' 6>&1 | Out-String
        $output | Should -Match '>>> START'
        $output | Should -Match 'test-phase'
    }

    It 'finish phase emits <<< DONE banner' {
        $output = Write-AgentLog -Phase finish -Action 'test-phase' 6>&1 | Out-String
        $output | Should -Match '<<< DONE'
        $output | Should -Match 'test-phase'
    }
}

# ---------------------------------------------------------------------------
# Expand-AgentPath — ~ expansion
# ---------------------------------------------------------------------------
Describe 'Expand-AgentPath - tilde expansion' -Skip:(-not $script:IsWindowsHost) {

    It 'expands bare ~ to USERPROFILE' {
        Expand-AgentPath '~' | Should -Be $env:USERPROFILE
    }

    It 'expands ~/subpath to USERPROFILE\subpath' {
        $result = Expand-AgentPath '~/agent-stack'
        $result | Should -Be (Join-Path $env:USERPROFILE 'agent-stack')
    }

    It 'returns absolute paths unchanged' {
        Expand-AgentPath 'C:\absolute\path' | Should -Be 'C:\absolute\path'
    }

    It 'returns relative paths unchanged' {
        Expand-AgentPath 'relative\path' | Should -Be 'relative\path'
    }
}

# ---------------------------------------------------------------------------
# Invoke-ParseManifest — manifest parsing
# ---------------------------------------------------------------------------
Describe 'Invoke-ParseManifest - manifest parsing' -Skip:(-not $script:IsWindowsHost) {

    BeforeAll {
        $script:fixturePath = Join-Path $env:TEMP ("common-test-manifest-" + [guid]::NewGuid().ToString('N') + ".manifest")
    }
    AfterAll {
        if (Test-Path $script:fixturePath) { Remove-Item $script:fixturePath -Force }
    }

    It 'skips blank lines and comment lines' {
        @(
            '# this is a comment'
            ''
            'my-repo | ~/repos/my-repo | https://example.com/my-repo.git | main'
        ) | Set-Content -LiteralPath $script:fixturePath -Encoding UTF8

        $results = @(Invoke-ParseManifest -ManifestPath $script:fixturePath)
        $results.Count | Should -Be 1
        $results[0].Name | Should -Be 'my-repo'
    }

    It 'expands ~ in LocalPath to USERPROFILE' {
        @('my-repo | ~/agent-stack | https://example.com/repo.git | main') |
            Set-Content -LiteralPath $script:fixturePath -Encoding UTF8

        $result = Invoke-ParseManifest -ManifestPath $script:fixturePath
        $result.LocalPath | Should -Be (Join-Path $env:USERPROFILE 'agent-stack')
    }

    It 'trims whitespace from all pipe-delimited fields' {
        @('my-repo | ~/repos/my-repo | https://example.com/my-repo.git | main') |
            Set-Content -LiteralPath $script:fixturePath -Encoding UTF8

        $result = Invoke-ParseManifest -ManifestPath $script:fixturePath
        $result.Name   | Should -Be 'my-repo'
        $result.Remote | Should -Be 'https://example.com/my-repo.git'
        $result.Branch | Should -Be 'main'
    }

    It 'returns objects with Name, LocalPath, Remote, Branch properties' {
        @('repo | ~/path | https://example.com/repo.git | develop') |
            Set-Content -LiteralPath $script:fixturePath -Encoding UTF8

        $result = Invoke-ParseManifest -ManifestPath $script:fixturePath
        $result.PSObject.Properties.Name | Should -Contain 'Name'
        $result.PSObject.Properties.Name | Should -Contain 'LocalPath'
        $result.PSObject.Properties.Name | Should -Contain 'Remote'
        $result.PSObject.Properties.Name | Should -Contain 'Branch'
    }
}

# ---------------------------------------------------------------------------
# Invoke-EnsureRepo — idempotent clone-or-pull
# ---------------------------------------------------------------------------
Describe 'Invoke-EnsureRepo - clone vs pull' -Skip:(-not $script:IsWindowsHost) {

    BeforeEach {
        $script:savedDryRun = $env:DRY_RUN
        $env:DRY_RUN = '1'
    }
    AfterEach {
        $env:DRY_RUN = $script:savedDryRun
    }

    It 'emits git clone when no .git directory exists (dry-run)' {
        $tmpDir = Join-Path $env:TEMP ("ensure-repo-test-" + [guid]::NewGuid().ToString('N'))
        $output = Invoke-EnsureRepo -LocalPath $tmpDir -Remote 'https://example.com/repo.git' -Branch 'main' 6>&1 | Out-String
        $output | Should -Match 'clone'
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'emits git pull when .git directory is present (dry-run)' {
        $tmpDir = Join-Path $env:TEMP ("ensure-repo-pull-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmpDir '.git') -Force | Out-Null
        $output = Invoke-EnsureRepo -LocalPath $tmpDir -Remote 'https://example.com/repo.git' -Branch 'main' 6>&1 | Out-String
        $output | Should -Match 'pull'
        Remove-Item $tmpDir -Recurse -Force
    }
}
