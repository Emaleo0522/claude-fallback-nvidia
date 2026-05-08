# Launch Claude Code routed to NVIDIA Kimi K2.6 via local LiteLLM proxy.
$ErrorActionPreference = 'Stop'

$InstallDir = if ($env:LITELLM_INSTALL_DIR) { $env:LITELLM_INSTALL_DIR } else { "$env:USERPROFILE\litellm-proxy" }

if (-not (Test-Path "$InstallDir\env.ps1")) {
    Write-Error "$InstallDir\env.ps1 not found. Did you run install.ps1?"
    exit 1
}
. "$InstallDir\env.ps1"
$port = if ($env:LITELLM_PORT) { $env:LITELLM_PORT } else { '4000' }
$ProxyUrl = "http://127.0.0.1:$port"

# Probe + auto-start
try {
    Invoke-WebRequest -Uri "$ProxyUrl/health/liveness" -TimeoutSec 2 -UseBasicParsing | Out-Null
} catch {
    Write-Host "litellm proxy not reachable. starting it..."
    & "$InstallDir\start.ps1"
    foreach ($i in 1..8) {
        Start-Sleep -Seconds 1
        try {
            Invoke-WebRequest -Uri "$ProxyUrl/health/liveness" -TimeoutSec 2 -UseBasicParsing | Out-Null
            break
        } catch {}
    }
}

$env:ANTHROPIC_BASE_URL          = $ProxyUrl
$env:ANTHROPIC_AUTH_TOKEN        = $env:LITELLM_MASTER_KEY
$env:ANTHROPIC_MODEL             = 'kimi-k2'
$env:ANTHROPIC_SMALL_FAST_MODEL  = 'qwen3-next'
Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

Write-Host "→ Claude Code → LiteLLM → NVIDIA Kimi K2.6 (deep / high quality)"
Write-Host "  small/fast slot: qwen3-next"
& claude $args
