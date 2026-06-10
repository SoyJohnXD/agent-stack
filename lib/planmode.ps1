Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($script:_PlanmodePs1Loaded) { return }
$script:_PlanmodePs1Loaded = $true

$Script:PLANMODE_START = '<!-- plan-mode:start -->'
$Script:PLANMODE_END   = '<!-- plan-mode:end -->'

$Script:SERIALIZATION_START = '<!-- serialization:start -->'
$Script:SERIALIZATION_END   = '<!-- serialization:end -->'

$Script:GATE_WIRING_START = '<!-- gate-wiring:start -->'
$Script:GATE_WIRING_END   = '<!-- gate-wiring:end -->'

function phase_planmode {
    $personaDir = Join-Path $PSScriptRoot '..\persona'
    $blocks = @(
        @{ Start = $Script:PLANMODE_START;      End = $Script:PLANMODE_END;      Src = (Join-Path $personaDir 'plan-mode-contract.md') },
        @{ Start = $Script:SERIALIZATION_START; End = $Script:SERIALIZATION_END; Src = (Join-Path $personaDir 'serialization.md') },
        @{ Start = $Script:GATE_WIRING_START;   End = $Script:GATE_WIRING_END;   Src = (Join-Path $personaDir 'gate-wiring.md') }
    )

    $targets = @(
        (Join-Path (Get-AgentStackPath 'claude-config')    'CLAUDE.md'),
        (Join-Path (Get-AgentStackPath 'codex-root')       'AGENTS.override.md'),
        (Join-Path (Get-AgentStackPath 'opencode-config')  'AGENTS.md')
    )

    foreach ($target in $targets) {
        $dir = Split-Path -Parent $target
        if (-not (Test-Path $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        foreach ($block in $blocks) {
            if (-not (Test-Path $block.Src -PathType Leaf)) {
                Write-Warning "phase_planmode: block source not found at $($block.Src)"
                continue
            }
            Set-ManagedBlock -TargetPath $target -StartMarker $block.Start -EndMarker $block.End -SourcePath $block.Src
        }
        Write-Host "  planmode applied: $target"
    }
}
