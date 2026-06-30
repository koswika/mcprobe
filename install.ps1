$ErrorActionPreference = "Stop"

$url = "https://raw.githubusercontent.com/koswika/mcprobe/main/mcprobe.sh"
$installDir = "$env:USERPROFILE\bin"
$installPath = "$installDir\mcprobe.sh"
$shimPath = "$installDir\mcprobe.cmd"

$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bashCmd) {
    Write-Host "Error: 'bash' was not found on PATH."
    Write-Host "Install Git Bash (https://git-scm.com/downloads) or enable WSL, then re-run this installer."
    exit 1
}

if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}

Write-Host "Downloading mcprobe..."
try {
    Invoke-WebRequest -Uri $url -OutFile $installPath -UseBasicParsing
} catch {
    Write-Host "Error: failed to download mcprobe from $url"
    Write-Host $_.Exception.Message
    exit 1
}

if (-not (Test-Path $installPath) -or (Get-Item $installPath).Length -eq 0) {
    Write-Host "Error: downloaded file is missing or empty. Aborting install."
    exit 1
}

$shimContent = "@echo off`r`nbash `"%~dp0mcprobe.sh`" %*`r`n"
Set-Content -Path $shimPath -Value $shimContent -Encoding ASCII

$path = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($path -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$path;$installDir", "User")
    Write-Host "Added $installDir to PATH (restart your terminal to apply)"
}

Write-Host "mcprobe installed to $installPath"
Write-Host "Run it with: mcprobe <server>"