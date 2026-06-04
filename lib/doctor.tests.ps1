<#
.SYNOPSIS
  Pester test stubs for lib/doctor.ps1.

.DESCRIPTION
  WINDOWS-CI-ONLY. Every Describe block carries -Skip:(-not $script:IsWindowsHost)
  so this file is parsed on Linux (CI stays green) but all tests are skipped.

  Run on Windows:
      Invoke-Pester -Path .\lib\doctor.tests.ps1

  Pester v5 syntax. PowerShell 5.1+ compatible.
#>

# PS 5.1 lacks the automatic $IsWindows variable; derive it portably.
$script:IsWindowsHost =
    ($null -eq (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) -or $IsWindows

BeforeAll {
    . "$PSScriptRoot\common.ps1"
    . "$PSScriptRoot\doctor.ps1"
}

# ---------------------------------------------------------------------------
# Test-AgentTool
# ---------------------------------------------------------------------------
Describe 'Test-AgentTool - individual tool check' -Skip:(-not $script:IsWindowsHost) {

    It 'Test-AgentTool is available after dot-sourcing' {
        Get-Command Test-AgentTool -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'emits [PASS] for git which is always present on Windows CI' {
        $output = Test-AgentTool -Cmd @('git', '--version') -Label 'git' 6>&1 | Out-String
        $output | Should -Match '\[PASS\]'
    }

    It 'emits [FAIL] for a required tool that does not exist' {
        $script:_DoctorFails = 0
        $output = Test-AgentTool -Cmd @('nonexistent-tool-xyz', '--version') -Label 'fake-tool' 6>&1 | Out-String
        $output | Should -Match '\[FAIL\]'
        $script:_DoctorFails | Should -BeGreaterThan 0
    }

    It 'emits [WARN] for an optional tool that does not exist' {
        $script:_DoctorFails = 0
        $output = Test-AgentTool -Cmd @('nonexistent-tool-xyz', '--version') -Label 'fake-optional' -Optional 6>&1 | Out-String
        $output | Should -Match '\[WARN\]'
        $script:_DoctorFails | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# phase_doctor
# ---------------------------------------------------------------------------
Describe 'phase_doctor - aggregated health check' -Skip:(-not $script:IsWindowsHost) {

    It 'phase_doctor is available after dot-sourcing' {
        Get-Command phase_doctor -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'returns an integer failure count' {
        $result = phase_doctor
        $result | Should -BeOfType [int]
    }

    It 'returns 0 failure count for git (which is present)' {
        # git is always available on a Windows CI runner.
        # We test this sub-check via Test-AgentTool directly.
        $script:_DoctorFails = 0
        Test-AgentTool -Cmd @('git', '--version') -Label 'git' | Out-Null
        $script:_DoctorFails | Should -Be 0
    }

    It 'does not increment failure counter for missing gum (optional)' {
        if (-not (Get-Command gum -ErrorAction SilentlyContinue)) {
            $script:_DoctorFails = 0
            Test-AgentTool -Cmd @('gum', '--version') -Label 'gum' -Optional | Out-Null
            $script:_DoctorFails | Should -Be 0
        } else {
            Set-ItResult -Skipped -Because 'gum is installed; cannot test absent-gum path'
        }
    }

    It 'resets the failure counter at each phase_doctor call' {
        # First call may set failures; second call should start fresh.
        phase_doctor | Out-Null
        $firstCount = $script:_DoctorFails
        phase_doctor | Out-Null
        $script:_DoctorFails | Should -Be $firstCount
    }
}
