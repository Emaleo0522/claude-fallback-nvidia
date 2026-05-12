# Launch Aider routed to NVIDIA Kimi K2.6 via local LiteLLM proxy.
# Use for: complex debugging, architecture, refactors, decisions.
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

if (-not (Get-Command aider -ErrorAction SilentlyContinue)) {
    Write-Error "aider not in PATH. Install with: pipx install aider-chat"
    exit 1
}

$env:OPENAI_API_BASE = $ProxyUrl
$env:OPENAI_API_KEY  = $env:LITELLM_MASTER_KEY

Write-Host "→ Aider → LiteLLM → NVIDIA Kimi K2.6 (deep / high quality)"
& aider --model openai/kimi-k2 $args
