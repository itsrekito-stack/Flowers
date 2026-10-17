$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        throw "Rojo CLI not found. Install it and reopen PowerShell."
    }
    & rojo build default.project.json -o Flowers.rbxl
    if ($LASTEXITCODE -ne 0) { throw "Rojo build failed." }
    Write-Host "[PASS] $root/Flowers.rbxl"
} finally {
    Pop-Location
}
