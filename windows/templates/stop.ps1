$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidPath = Join-Path $ScriptDir 'proxy.pid'

if (Test-Path $pidPath) {
    $pidValue = Get-Content $pidPath
    try {
        $proc = Get-Process -Id $pidValue -ErrorAction Stop
        Stop-Process -Id $pidValue -Force
        Write-Host "stopped PID=$pidValue"
    } catch {
        Write-Host "PID $pidValue not running"
    }
    Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
} else {
    Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='litellm.exe'" |
        Where-Object { $_.CommandLine -match [regex]::Escape("$ScriptDir\config.yaml") } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force
            Write-Host "stopped via process scan: PID=$($_.ProcessId)"
        }
}
