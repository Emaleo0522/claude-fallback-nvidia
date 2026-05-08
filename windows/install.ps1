# claude-fallback-nvidia — interactive installer for Windows (PowerShell 5.1+)
# Sets up a local LiteLLM proxy + claude-deep.ps1 / claude-fast.ps1 wrappers.
$ErrorActionPreference = 'Stop'

$RepoDir      = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TemplatesDir = Join-Path $RepoDir 'windows\templates'
$ConfigSrc    = Join-Path $RepoDir 'linux\templates\config.yaml'  # YAML is OS-agnostic

$InstallDir = if ($env:LITELLM_INSTALL_DIR) { $env:LITELLM_INSTALL_DIR } else { "$env:USERPROFILE\litellm-proxy" }
$BinDir     = if ($env:LITELLM_BIN_DIR)     { $env:LITELLM_BIN_DIR }     else { "$env:USERPROFILE\bin" }
$Port       = if ($env:LITELLM_PORT)        { $env:LITELLM_PORT }        else { 4000 }

function Say   { Write-Host "→ $args" -ForegroundColor Cyan }
function OK    { Write-Host "✓ $args" -ForegroundColor Green }
function Warn  { Write-Host "! $args" -ForegroundColor Yellow }
function Fail  { Write-Host "✗ $args" -ForegroundColor Red; exit 1 }
function HR    { Write-Host ('─' * 44) -ForegroundColor DarkGray }

HR
Say "claude-fallback-nvidia installer (Windows)"
HR

# ── 1. Pre-flight ─────────────────────────────────────────────────────────
Say "checking dependencies..."

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Fail "Claude Code (claude) is not in PATH. Install it first: https://docs.anthropic.com/en/docs/claude-code"
}
$claudeBin = (Get-Command claude).Source
OK "found claude: $claudeBin"

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) { $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $pythonCmd) { Fail "python not found in PATH. Install from python.org with 'Add to PATH' checked." }
$pyVer = & $pythonCmd.Name --version
OK "found python: $pyVer"

# port check
$portUsed = (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
if ($portUsed) {
    Fail "port $Port is already in use. Free it or set `$env:LITELLM_PORT before running."
}
OK "port $Port is free"

# ── 2. Existing install? ──────────────────────────────────────────────────
if (Test-Path $InstallDir) {
    Warn "an install already exists at $InstallDir"
    $ans = Read-Host "Overwrite? [y/N]"
    if ($ans -match '^(y|yes)$') {
        $backup = "$InstallDir.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item $InstallDir $backup
        OK "moved existing install to $backup"
    } else {
        Write-Host "aborted."; exit 0
    }
}

# ── 3. NVIDIA API key ─────────────────────────────────────────────────────
HR
Write-Host "Get a free NVIDIA API key at: https://build.nvidia.com  (~5000 credits/month)"
Write-Host "It must start with 'nvapi-'. Input is hidden."
do {
    $sec = Read-Host "NVIDIA_API_KEY" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $NvidiaKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    if ($NvidiaKey -match '^nvapi-.+$') { break }
    Warn "invalid format — must start with 'nvapi-'. try again."
} while ($true)
OK "API key recorded (length: $($NvidiaKey.Length))"

# ── 4. Create venv + install LiteLLM ──────────────────────────────────────
HR
Say "creating venv at $InstallDir\.venv ..."
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
& $pythonCmd.Name -m venv "$InstallDir\.venv"
OK "venv created"

Say "installing LiteLLM (1-2 minutes) ..."
& "$InstallDir\.venv\Scripts\pip.exe" install --quiet --upgrade pip
& "$InstallDir\.venv\Scripts\pip.exe" install --quiet 'litellm[proxy]'
$litellmVer = & "$InstallDir\.venv\Scripts\litellm.exe" --version 2>&1 | Select-Object -First 1
OK "$litellmVer"

# ── 5. Generate master key + write env.ps1 ────────────────────────────────
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 16
$rng.GetBytes($bytes)
$MasterKey = "sk-litellm-" + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')

$envScript = @"
# claude-fallback-nvidia — generated $(Get-Date -Format 'o')
`$env:NVIDIA_API_KEY      = '$NvidiaKey'
`$env:LITELLM_MASTER_KEY  = '$MasterKey'
`$env:LITELLM_PORT        = '$Port'
"@
Set-Content -Path "$InstallDir\env.ps1" -Value $envScript -Encoding UTF8

# Lock down ACL: only current user can read
icacls "$InstallDir\env.ps1" /inheritance:r /grant:r "$($env:USERNAME):R" | Out-Null
OK "wrote env.ps1 (ACL: read-only for $env:USERNAME)"

# ── 6. Install templates ──────────────────────────────────────────────────
Say "installing config + scripts ..."
Copy-Item $ConfigSrc                            "$InstallDir\config.yaml" -Force
Copy-Item "$TemplatesDir\start.ps1"             "$InstallDir\start.ps1"   -Force
Copy-Item "$TemplatesDir\stop.ps1"              "$InstallDir\stop.ps1"    -Force
OK "installed to $InstallDir"

# ── 7. Install wrappers ───────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Copy-Item "$TemplatesDir\claude-deep.ps1"  "$BinDir\claude-deep.ps1"  -Force
Copy-Item "$TemplatesDir\claude-fast.ps1"  "$BinDir\claude-fast.ps1"  -Force
OK "installed claude-deep.ps1, claude-fast.ps1 to $BinDir"

if ($env:Path -notlike "*$BinDir*") {
    Warn "$BinDir is NOT in PATH"
    Write-Host "    Add it via System → Environment Variables, or run for current user:"
    Write-Host "      [Environment]::SetEnvironmentVariable('Path', `"`$env:Path;$BinDir`", 'User')"
}

# ── 8. Start proxy ────────────────────────────────────────────────────────
HR
Say "starting proxy..."
& "$InstallDir\start.ps1"

Say "waiting for proxy to come up..."
$alive = $false
foreach ($i in 1..10) {
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health/liveness" -TimeoutSec 2 -UseBasicParsing | Out-Null
        $alive = $true
        OK "proxy is alive"
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}
if (-not $alive) {
    Fail "proxy failed to come up. Check $InstallDir\proxy.log"
}

# ── 9. Smoke test ─────────────────────────────────────────────────────────
Say "smoke-testing qwen3-next route..."
$body = '{"model":"qwen3-next","max_tokens":10,"messages":[{"role":"user","content":"reply ok"}]}'
try {
    $resp = Invoke-RestMethod -Method POST -Uri "http://127.0.0.1:$Port/v1/messages" `
        -ContentType 'application/json' `
        -Headers @{ 'x-api-key' = $MasterKey; 'anthropic-version' = '2023-06-01' } `
        -Body $body -TimeoutSec 60
    if ($resp.type -eq 'message') { OK "qwen3-next responded" }
    else { Warn "qwen3-next response unexpected: $($resp | ConvertTo-Json -Depth 3)" }
} catch {
    Fail "qwen3-next test failed: $_"
}

# ── 10. Done ──────────────────────────────────────────────────────────────
HR
OK "install complete"
Write-Host ""
Write-Host "  Use:"
Write-Host "    claude-deep.ps1   →  Kimi K2.6 (high quality)"
Write-Host "    claude-fast.ps1   →  Qwen3-Next 80B (fast)"
Write-Host "    claude            →  your normal Anthropic plan"
Write-Host ""
Write-Host "  Proxy:"
Write-Host "    start: $InstallDir\start.ps1"
Write-Host "    stop:  $InstallDir\stop.ps1"
Write-Host "    log:   $InstallDir\proxy.log"
Write-Host ""
Write-Host "  Open a new PowerShell window and try:"
Write-Host "    claude-fast.ps1"
Write-Host ""
