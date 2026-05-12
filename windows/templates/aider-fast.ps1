# Launch Aider routed to NVIDIA Qwen3-Next 80B via local LiteLLM proxy.
# Use for: routine coding, HTML/CSS, scripts, small fixes, exploration.
$ErrorActionPreference = 'Stop'

$InstallDir = if ($env:LITELLM_INSTALL_DIR) { $env:LITELLM_INSTALL_DIR } else { "$env:USERPROFILE\litellm-proxy" }

if (-not (Test-Path "$InstallDir\env.ps1")) {
    Write-Error "$InstallDir\env.ps1 not found. Did you run install.ps1?"
    exit 1
}
. "$InstallDir\env.ps1"
$port = if ($env:LITELLM_PORT) { $env:LITELLM_PORT } else { '4000' }
$ProxyUrl = "http://127.0.0.1:$port"

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

Write-Host "→ Aider → LiteLLM → NVIDIA Qwen3-Next 80B (fast)"
& aider --model openai/qwen3-next $args
