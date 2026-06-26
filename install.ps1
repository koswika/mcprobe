$ErrorActionPreference = "Stop"

$url = "https://raw.githubusercontent.com/koswika/mcprobe/main/mcprobe.sh"
$installDir = "$env:USERPROFILE\bin"
$installPath = "$installDir\mcprobe.sh"

if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}

Write-Host "Downloading mcprobe..."
Invoke-WebRequest -Uri $url -OutFile $installPath

$path = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($path -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$path;$installDir", "User")
    Write-Host "Added $installDir to PATH (restart your terminal to apply)"
}

Write-Host "mcprobe installed to $installPath"
Write-Host "Run it with: bash mcprobe.sh <server>  (requires Git Bash or WSL)"