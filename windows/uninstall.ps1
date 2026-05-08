$ErrorActionPreference = 'Stop'

$InstallDir = if ($env:LITELLM_INSTALL_DIR) { $env:LITELLM_INSTALL_DIR } else { "$env:USERPROFILE\litellm-proxy" }
$BinDir     = if ($env:LITELLM_BIN_DIR)     { $env:LITELLM_BIN_DIR }     else { "$env:USERPROFILE\bin" }

Write-Host "claude-fallback-nvidia uninstaller"
Write-Host "  install dir: $InstallDir"
Write-Host "  bin dir:     $BinDir"
Write-Host ""

if (Test-Path "$InstallDir\stop.ps1") {
    Write-Host "stopping proxy..."
    & "$InstallDir\stop.ps1"
}

$ans = Read-Host "Remove $InstallDir ? [y/N]"
if ($ans -match '^(y|yes)$') {
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    Write-Host "removed $InstallDir"
}

$ans = Read-Host "Remove wrappers? [y/N]"
if ($ans -match '^(y|yes)$') {
    Remove-Item -Force "$BinDir\claude-deep.ps1" -ErrorAction SilentlyContinue
    Remove-Item -Force "$BinDir\claude-fast.ps1" -ErrorAction SilentlyContinue
    Write-Host "removed wrappers"
}

Write-Host "done."
