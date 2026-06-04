<#
.SYNOPSIS
  gentle-ai upgrade and sync phase for agent-stack on Windows.

.DESCRIPTION
  Dot-source this module after lib/common.ps1 to make phase_gentle available.

  phase_gentle calls:
    1. gentle-ai upgrade
    2. gentle-ai sync
  Both via Invoke-AgentRun so $env:DRY_RUN is respected.
  If gentle-ai is not on PATH, the phase is skipped without error.

  PowerShell 5.1+ compatible.
#>

if ($script:_GentlePs1Loaded) { return }
$script:_GentlePs1Loaded = $true

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function phase_gentle {
    <#
    .SYNOPSIS
      Runs gentle-ai upgrade then gentle-ai sync.
    .DESCRIPTION
      Guarded by Get-Command so a missing gentle-ai is a silent skip.
      Both calls go through Invoke-AgentRun (dry-run safe).
    #>

    Write-AgentLog -Phase start -Action 'gentle'

    if (Get-Command 'gentle-ai' -ErrorAction SilentlyContinue) {
        Invoke-AgentRun gentle-ai upgrade
        Invoke-AgentRun gentle-ai sync
    } else {
        Write-Host '[skip] gentle-ai not found'
    }

    Write-AgentLog -Phase finish -Action 'gentle'
}
