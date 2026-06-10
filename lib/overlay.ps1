Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($script:_OverlayPs1Loaded) { return }
$script:_OverlayPs1Loaded = $true

function phase_overlay {
    $manifest = $env:MANIFEST_FILE
    if (-not $manifest) { $manifest = Join-Path $PSScriptRoot '..\repos.manifest' }

    $entry = Invoke-ParseManifest -ManifestPath $manifest | Where-Object { $_.Name -eq 'overlay' } | Select-Object -First 1
    if (-not $entry) { Write-Warning 'phase_overlay: overlay entry not found in repos.manifest'; return }

    Invoke-EnsureRepo -LocalPath $entry.LocalPath -Remote $entry.Remote -Branch $entry.Branch

    $intentOverlay = Join-Path $entry.LocalPath 'overlay\intent-overlay.ps1'

    if (Test-Path -LiteralPath $intentOverlay -PathType Leaf) {
        Invoke-AgentRun powershell -NonInteractive -File $intentOverlay install
    } elseif (Get-Command intent-overlay -ErrorAction SilentlyContinue) {
        Invoke-AgentRun intent-overlay install
    } else {
        Write-Host '[skip] intent-overlay not found'
    }
}
