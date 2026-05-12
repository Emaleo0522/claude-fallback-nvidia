# claude-fallback-nvidia — interactive installer for Windows (PowerShell 5.1+)
#
# Sets up a local LiteLLM proxy that routes to NVIDIA-hosted free-tier models.
# Adapts to what's installed:
#   Mode A — claude:     installs claude-deep.ps1 / claude-fast.ps1
#   Mode B — aider:      installs aider-deep.ps1 / aider-fast.ps1  (no Anthropic account)
#   Mode C — both
#   Mode D — proxy-only
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

# ── 1. Pre-flight (Python + port) ─────────────────────────────────────────
Say "checking dependencies..."

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) { $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $pythonCmd) { Fail "python not found in PATH. Install from python.org with 'Add to PATH' checked." }
$pyVer = & $pythonCmd.Name --version
OK "found python: $pyVer"

# Port check
$portUsed = (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
if ($portUsed) {
    Fail "port $Port is already in use. Free it or set `$env:LITELLM_PORT before running."
}
OK "port $Port is free"

# ── 2. Detect CLI clients + decide install mode ──────────────────────────
HR
$HasClaude = [bool](Get-Command claude -ErrorAction SilentlyContinue)
$HasAider  = [bool](Get-Command aider  -ErrorAction SilentlyContinue)
$InstallClaude = $false
$InstallAider  = $false

if ($HasClaude -and $HasAider) {
    OK "found Claude Code: $((Get-Command claude).Source)"
    OK "found Aider:       $((Get-Command aider).Source)"
    Write-Host "Both clients available. Will install wrappers for both."
    $InstallClaude = $true
    $InstallAider  = $true
}
elseif ($HasClaude -and -not $HasAider) {
    OK "found Claude Code: $((Get-Command claude).Source)"
    $InstallClaude = $true
    $ans = Read-Host "Also install Aider (open-source CLI alternative)? [y/N]"
    if ($ans -match '^(y|yes)$') { $InstallAider = $true }
}
elseif (-not $HasClaude -and $HasAider) {
    Warn "Claude Code not found; Aider is available."
    OK "found Aider: $((Get-Command aider).Source)"
    $InstallAider = $true
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  1) Continue with Aider only (recommended if you don't want an Anthropic account)"
    Write-Host "  2) Also install Claude Code (you'll be told to install it manually)"
    $choice = Read-Host "Choice [1/2, default 1]"
    if ($choice -eq '2') {
        Warn "Claude Code can't be auto-installed on Windows from this script."
        Warn "Please install it manually from https://docs.anthropic.com/en/docs/claude-code"
        Warn "Then re-run this installer. Continuing with Aider only for now."
    }
}
else {
    Warn "Neither Claude Code nor Aider found in PATH."
    Write-Host ""
    Write-Host "Pick an install mode:"
    Write-Host "  1) Install Aider           — open-source, NO Anthropic account required (recommended)"
    Write-Host "  2) Install Claude Code     — requires an Anthropic account (manual install)"
    Write-Host "  3) Install both"
    Write-Host "  4) Proxy only              — bring your own client (Cline, OpenCode, etc.)"
    Write-Host ""
    Write-Host "If you don't have an Anthropic account and just want the free NVIDIA models,"
    Write-Host "press Enter (defaults to 1)."
    $choice = Read-Host "Choice [1/2/3/4, default 1]"
    if ([string]::IsNullOrEmpty($choice)) { $choice = '1' }
    switch ($choice) {
        '1' { $InstallAider = $true }
        '2' {
            Warn "Claude Code can't be auto-installed on Windows by this script."
            Warn "Please install it manually from https://docs.anthropic.com/en/docs/claude-code,"
            Warn "then re-run 'powershell -ExecutionPolicy Bypass -File windows\install.ps1'."
            exit 0
        }
        '3' {
            $InstallAider = $true
            Warn "Claude Code can't be auto-installed on Windows; install it manually later"
            Warn "from https://docs.anthropic.com/en/docs/claude-code and re-run this installer"
            Warn "to add claude-deep.ps1 / claude-fast.ps1."
        }
        '4' { Warn "proxy-only mode — no CLI wrappers will be installed." }
        default { Fail "invalid choice." }
    }
}

# ── 2b. Install Aider via pipx if needed ─────────────────────────────────
if ($InstallAider -and -not (Get-Command aider -ErrorAction SilentlyContinue)) {
    $AiderInstalled = $false

    # Attempt 1: pipx (the modern, isolated way)
    if (-not (Get-Command pipx -ErrorAction SilentlyContinue)) {
        Say "pipx not found; installing it via pip --user ..."
        try {
            & $pythonCmd.Name -m pip install --user --quiet pipx
            # Add %USERPROFILE%\.local\bin (pipx's default) to current-session PATH
            $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
            # Also try the Scripts dir of the user-site (where pipx.exe lands on Windows)
            $userBase = & $pythonCmd.Name -c "import site; print(site.USER_BASE)"
            if ($userBase) { $env:Path = "$userBase\Scripts;$env:Path" }
        } catch {
            Warn "could not install pipx automatically: $_"
        }
    }

    if (Get-Command pipx -ErrorAction SilentlyContinue) {
        Say "installing Aider via pipx (this may take a minute) ..."
        try {
            & pipx install aider-chat | Out-Null
            & pipx ensurepath | Out-Null
            # Refresh current-session PATH so subsequent checks find aider
            $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
            $userBase = & $pythonCmd.Name -c "import site; print(site.USER_BASE)"
            if ($userBase) { $env:Path = "$userBase\Scripts;$env:Path" }
            if (Get-Command aider -ErrorAction SilentlyContinue) {
                OK "aider installed via pipx"
                $AiderInstalled = $true
            }
        } catch {
            Warn "pipx install aider-chat failed: $_"
        }
    }

    # Attempt 2: plain pip --user as fallback
    if (-not $AiderInstalled) {
        Say "trying pip --user install of aider-chat ..."
        try {
            & $pythonCmd.Name -m pip install --user --quiet aider-chat
            $userBase = & $pythonCmd.Name -c "import site; print(site.USER_BASE)"
            if ($userBase) { $env:Path = "$userBase\Scripts;$env:Path" }
            if (Get-Command aider -ErrorAction SilentlyContinue) {
                OK "aider installed via pip --user"
                $AiderInstalled = $true
            }
        } catch {
            Warn "pip --user install failed: $_"
        }
    }

    if (-not $AiderInstalled) {
        if ($InstallClaude) {
            Warn "could not install Aider. Continuing with Claude wrappers only."
            $InstallAider = $false
        } else {
            Fail @"
could not install Aider, and no other CLI was selected.

Try installing manually, then re-run this script:
    python -m pip install --user pipx
    python -m pipx ensurepath
    pipx install aider-chat

If 'pipx' is still not found after that, close PowerShell, open a new window,
and re-run the installer.
"@
        }
    }
}

# ── 3. Existing install? ──────────────────────────────────────────────────
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

# ── 4. NVIDIA API key ─────────────────────────────────────────────────────
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

# ── 5. Create venv + install LiteLLM ──────────────────────────────────────
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

# ── 6. Generate master key + write env.ps1 ────────────────────────────────
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

# ── 7. Install templates ──────────────────────────────────────────────────
Say "installing config + scripts + boost ..."
$LinuxTemplates = Join-Path $RepoDir 'linux\templates'  # boost files are OS-agnostic
Copy-Item $ConfigSrc                            "$InstallDir\config.yaml"     -Force
Copy-Item "$TemplatesDir\start.ps1"             "$InstallDir\start.ps1"       -Force
Copy-Item "$TemplatesDir\stop.ps1"              "$InstallDir\stop.ps1"        -Force
Copy-Item "$LinuxTemplates\custom_boost.py"     "$InstallDir\custom_boost.py" -Force
Copy-Item "$LinuxTemplates\system_boost.md"     "$InstallDir\system_boost.md" -Force
OK "installed to $InstallDir (config + scripts + system prompt boost)"

# ── 8. Install wrappers ───────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$InstalledWrappers = @()
if ($InstallClaude) {
    Copy-Item "$TemplatesDir\claude-deep.ps1"  "$BinDir\claude-deep.ps1"  -Force
    Copy-Item "$TemplatesDir\claude-fast.ps1"  "$BinDir\claude-fast.ps1"  -Force
    $InstalledWrappers += 'claude-deep.ps1','claude-fast.ps1'
}
if ($InstallAider) {
    Copy-Item "$TemplatesDir\aider-deep.ps1"   "$BinDir\aider-deep.ps1"   -Force
    Copy-Item "$TemplatesDir\aider-fast.ps1"   "$BinDir\aider-fast.ps1"   -Force
    $InstalledWrappers += 'aider-deep.ps1','aider-fast.ps1'
}
if ($InstalledWrappers.Count -gt 0) {
    OK "installed wrappers to $BinDir`: $($InstalledWrappers -join ', ')"
} else {
    OK "no CLI wrappers installed (proxy-only mode)"
}

if ($InstalledWrappers.Count -gt 0 -and $env:Path -notlike "*$BinDir*") {
    Warn "$BinDir is NOT in PATH"
    Write-Host "    Add it permanently with (PowerShell, one time):"
    Write-Host "      [Environment]::SetEnvironmentVariable('Path', `"`$env:Path;$BinDir`", 'User')"
    Write-Host "    Then close and re-open PowerShell."
}

# ── 9. Start proxy ────────────────────────────────────────────────────────
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

# ── 10. Smoke test ────────────────────────────────────────────────────────
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

# ── 11. Done ──────────────────────────────────────────────────────────────
HR
OK "install complete"
Write-Host ""
if ($InstallClaude) {
    Write-Host "  Claude wrappers:"
    Write-Host "    claude-deep.ps1   →  Kimi K2.6 (high quality)"
    Write-Host "    claude-fast.ps1   →  Qwen3-Next 80B (fast)"
}
if ($InstallAider) {
    Write-Host "  Aider wrappers (no Anthropic account needed):"
    Write-Host "    aider-deep.ps1    →  Kimi K2.6"
    Write-Host "    aider-fast.ps1    →  Qwen3-Next 80B"
}
if (-not $InstallClaude -and -not $InstallAider) {
    Write-Host "  Proxy-only. Point any OpenAI/Anthropic-compatible client at:"
    Write-Host "    base URL: http://127.0.0.1:$Port"
    Write-Host "    api key:  (in $InstallDir\env.ps1 as LITELLM_MASTER_KEY)"
    Write-Host "    models:   kimi-k2, qwen3-next"
}
Write-Host ""
Write-Host "  Proxy:"
Write-Host "    start: $InstallDir\start.ps1"
Write-Host "    stop:  $InstallDir\stop.ps1"
Write-Host "    log:   $InstallDir\proxy.log"
Write-Host ""
Write-Host "  Open a new PowerShell window and run one of the wrappers above."
Write-Host ""
