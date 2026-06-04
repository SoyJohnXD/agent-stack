Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($script:_CodexPs1Loaded) { return }
$script:_CodexPs1Loaded = $true

function phase_codex {
    $manifest = $env:MANIFEST_FILE
    if (-not $manifest) { $manifest = Join-Path $PSScriptRoot '..\repos.manifest' }

    $entry = Invoke-ParseManifest -ManifestPath $manifest | Where-Object { $_.Name -eq 'codex' } | Select-Object -First 1
    if (-not $entry) { Write-Warning 'phase_codex: codex entry not found in repos.manifest'; return }

    Invoke-EnsureRepo -LocalPath $entry.LocalPath -Remote $entry.Remote -Branch $entry.Branch
    Invoke-AgentRun powershell -NonInteractive -File (Join-Path $entry.LocalPath 'install.ps1')
    Invoke-AgentRun codex-sdd-sync --mcp-audit
}
