param(
    [int]$FrontendPort = 57717,
    [switch]$SkipDocker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot

& (Join-Path $scriptDir "frontend-web-down.ps1") -Port $FrontendPort
& (Join-Path $scriptDir "dev-down.ps1")

if ($SkipDocker) {
    & (Join-Path $scriptDir "dev-up.ps1") -SkipDocker
} else {
    & (Join-Path $scriptDir "dev-up.ps1")
}

& (Join-Path $scriptDir "dev-health.ps1")
& (Join-Path $scriptDir "frontend-web-up.ps1") -Port $FrontendPort

Write-Host "All services restarted."
Write-Host "- Backend health checked"
Write-Host "- Frontend web: http://127.0.0.1:$FrontendPort"
