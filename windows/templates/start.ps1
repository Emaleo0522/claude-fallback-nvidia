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

$proc = Start-Process -FilePath $litellm `
    -ArgumentList '--config', "$ScriptDir\config.yaml", '--port', $port, '--host', $bindHost `
    -RedirectStandardOutput $logPath `
    -RedirectStandardError "$logPath.err" `
    -WindowStyle Hidden `
    -PassThru

Set-Content -Path $pidPath -Value $proc.Id

Start-Sleep -Seconds 2
if (-not $proc.HasExited) {
    Write-Host "litellm proxy started. PID=$($proc.Id)  URL=http://${bindHost}:${port}  log=$logPath"
} else {
    Write-Host "FAILED to start. Last 20 lines of proxy.log:"
    Get-Content $logPath -Tail 20
    exit 1
}
