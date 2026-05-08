# Start LiteLLM proxy in background. Idempotent.
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Load env vars
. "$ScriptDir\env.ps1"

# Already running?
$existing = Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='litellm.exe'" |
  Where-Object { $_.CommandLine -match [regex]::Escape("$ScriptDir\config.yaml") }

if ($existing) {
    Write-Host "litellm proxy already running. PID(s): $($existing.ProcessId -join ', ')"
    exit 0
}

$litellm = Join-Path $ScriptDir '.venv\Scripts\litellm.exe'
if (-not (Test-Path $litellm)) {
    Write-Error "litellm.exe not found at $litellm. Run install.ps1 first."
    exit 1
}

$logPath = Join-Path $ScriptDir 'proxy.log'
$pidPath = Join-Path $ScriptDir 'proxy.pid'

$port = if ($env:LITELLM_PORT) { $env:LITELLM_PORT } else { '4000' }
$bindHost = if ($env:LITELLM_HOST) { $env:LITELLM_HOST } else { '127.0.0.1' }

# Make custom_boost.py importable as a module (LiteLLM resolves callbacks
# via sys.path, which doesn't include cwd by default).
$existingPyPath = if ($env:PYTHONPATH) { $env:PYTHONPATH } else { '' }
$env:PYTHONPATH = "$ScriptDir;$existingPyPath"

$proc = Start-Process -FilePath $litellm `
    -ArgumentList '--config', "$ScriptDir\config.yaml", '--port', $port, '--host', $bindHost `
    -RedirectStandardOutput $logPath `
    -RedirectStandardError "$logPath.err" `
    -WindowStyle Hidden `
    -PassThru

Set-Content -Path $pidPath -Value $proc.Id

Start-Sleep -Seconds 2
if ($proc.HasExited) {
    Write-Host "FAILED to start. Last 20 lines of proxy.log:"
    Get-Content $logPath -Tail 20
    exit 1
}
Write-Host "litellm proxy started. PID=$($proc.Id)  URL=http://${bindHost}:${port}  log=$logPath"

# ─── Connection warmup (async background) ─────────────────────────────────
# Fire a tiny request once the server is up so the upstream TLS handshake
# to NVIDIA is paid by the warmup, not by the user's first real prompt.
$warmup = {
    param($Url, $Token)
    foreach ($i in 1..10) {
        try {
            Invoke-WebRequest -Uri "$Url/health/liveness" -TimeoutSec 1 -UseBasicParsing | Out-Null
            break
        } catch { Start-Sleep -Milliseconds 500 }
    }
    $body = '{"model":"qwen3-next","max_tokens":1,"messages":[{"role":"user","content":"ok"}]}'
    try {
        Invoke-RestMethod -Method POST -Uri "$Url/v1/messages" `
            -Headers @{ 'Content-Type'='application/json'; 'x-api-key'=$Token; 'anthropic-version'='2023-06-01' } `
            -Body $body -TimeoutSec 30 | Out-Null
    } catch {}
}
Start-Job -ScriptBlock $warmup -ArgumentList "http://${bindHost}:${port}", $env:LITELLM_MASTER_KEY | Out-Null
Write-Host "warmup dispatched in background"
