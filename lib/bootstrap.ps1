<#
.SYNOPSIS
  Thin delegator to the top-level bootstrap.ps1.

.DESCRIPTION
  Dot-source this module to make phase_bootstrap available.
  phase_bootstrap forwards all arguments to the top-level bootstrap.ps1
  via call (&), NOT dot-source, so bootstrap.ps1 runs its own main.

  PowerShell 5.1+ compatible.
#>

if ($script:_BootstrapLibPs1Loaded) { return }
$script:_BootstrapLibPs1Loaded = $true

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function phase_bootstrap {
    <#
    .SYNOPSIS
      Delegates to the top-level bootstrap.ps1 with all forwarded arguments.
    #>
    & "$PSScriptRoot\..\bootstrap.ps1" @args
}
