<#
.SYNOPSIS
  CLI update phase for agent-stack on Windows.

.DESCRIPTION
  Dot-source this module after lib/common.ps1 to make phase_update_clis available.

  phase_update_clis iterates over the four managed CLIs and issues the appropriate
  update command via Invoke-AgentRun. Each tool is guarded by Get-Command so
  absent tools are skipped without error.

  Tool -> update verb mapping (parity with bash lib/clis.sh):
    claude     -> update
    codex      -> update
    opencode   -> upgrade
    gentle-ai  -> upgrade

  PowerShell 5.1+ compatible.
#>

if ($script:_ClisPs1Loaded) { return }
$script:_ClisPs1Loaded = $true

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function phase_update_clis {
    <#
    .SYNOPSIS
      Updates all managed agent CLI binaries.
    .DESCRIPTION
      Each tool is checked with Get-Command first. Present tools are updated
      via Invoke-AgentRun; absent tools emit a [skip] notice and continue.
      Respects $env:DRY_RUN via Invoke-AgentRun.
    #>

    Write-AgentLog -Phase start -Action 'update-clis'

    $tools = @(
        [pscustomobject]@{ Cmd = 'claude';    Verb = @('update')  },
        [pscustomobject]@{ Cmd = 'codex';     Verb = @('update')  },
        [pscustomobject]@{ Cmd = 'opencode';  Verb = @('upgrade') },
        [pscustomobject]@{ Cmd = 'gentle-ai'; Verb = @('upgrade') }
    )

    foreach ($tool in $tools) {
        if (Get-Command $tool.Cmd -ErrorAction SilentlyContinue) {
            Invoke-AgentRun $tool.Cmd @($tool.Verb)
        } else {
            Write-Host "[skip] $($tool.Cmd) not found"
        }
    }

    Write-AgentLog -Phase finish -Action 'update-clis'
}
