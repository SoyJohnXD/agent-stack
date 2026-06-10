Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($script:_PersonaPs1Loaded) { return }
$script:_PersonaPs1Loaded = $true

$Script:PERSONA_START = '<!-- persona-co:start -->'
$Script:PERSONA_END   = '<!-- persona-co:end -->'

function phase_persona {
    $personaSrc = Join-Path $PSScriptRoot '..\persona\gentleman-co.md'
    if (-not (Test-Path $personaSrc -PathType Leaf)) {
        Write-Warning "phase_persona: persona source not found at $personaSrc"
        return
    }

    $targets = @(
        (Join-Path (Get-AgentStackPath 'claude-config')    'CLAUDE.md'),
        (Join-Path (Get-AgentStackPath 'codex-root')       'AGENTS.override.md'),
        (Join-Path (Get-AgentStackPath 'opencode-config')  'AGENTS.md')
    )
    foreach ($target in $targets) {
        $dir = Split-Path -Parent $target
        if (-not (Test-Path $dir -PathType Container)) { continue }
        Set-ManagedBlock -TargetPath $target -StartMarker $Script:PERSONA_START -EndMarker $Script:PERSONA_END -SourcePath $personaSrc
        Write-Host "  persona applied: $target"
    }
}
