Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($script:_PersonaPs1Loaded) { return }
$script:_PersonaPs1Loaded = $true

$Script:PERSONA_START = '<!-- persona-co:start -->'
$Script:PERSONA_END   = '<!-- persona-co:end -->'

function Invoke-BlockUpsert {
    # Replace existing START..END span, or append if absent. Mirrors the awk logic in persona.sh.
    param(
        [Parameter(Mandatory)][string]   $FilePath,
        [Parameter(Mandatory)][string[]] $Block
    )
    $parent = Split-Path -Parent $FilePath
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $lines = if (Test-Path $FilePath) { @(Get-Content -LiteralPath $FilePath) } else { @() }
    $n = $lines.Count; $s = -1; $e = -1
    for ($i = 0; $i -lt $n; $i++) {
        if ($lines[$i] -eq $Script:PERSONA_START -and $s -lt 0) { $s = $i }
        if ($lines[$i] -eq $Script:PERSONA_END   -and $s -ge 0) { $e = $i; break }
    }

    $out = [System.Collections.Generic.List[string]]::new()
    if ($s -ge 0 -and $e -ge 0) {
        # Replace existing span
        for ($i = 0; $i -lt $s; $i++)    { $out.Add($lines[$i]) }
        foreach ($l in $Block)             { $out.Add($l) }
        for ($i = $e + 1; $i -lt $n; $i++) { $out.Add($lines[$i]) }
    } else {
        # Append at EOF
        foreach ($l in $lines) { $out.Add($l) }
        $out.Add('')
        foreach ($l in $Block) { $out.Add($l) }
    }
    Set-Content -LiteralPath $FilePath -Value $out.ToArray() -Encoding UTF8
}

function phase_persona {
    $personaSrc = Join-Path $PSScriptRoot '..\persona\gentleman-co.md'
    if (-not (Test-Path $personaSrc -PathType Leaf)) {
        Write-Warning "phase_persona: persona source not found at $personaSrc"
        return
    }
    $block = @(Get-Content -LiteralPath $personaSrc)

    $targets = @(
        (Join-Path (Get-AgentStackPath 'claude-config')    'CLAUDE.md'),
        (Join-Path (Get-AgentStackPath 'codex-root')       'AGENTS.override.md'),
        (Join-Path (Get-AgentStackPath 'opencode-config')  'AGENTS.md')
    )
    foreach ($target in $targets) {
        $dir = Split-Path -Parent $target
        if (-not (Test-Path $dir -PathType Container)) { continue }
        Invoke-BlockUpsert -FilePath $target -Block $block
        Write-Host "  persona applied: $target"
    }
}
