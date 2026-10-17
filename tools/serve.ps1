$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
        throw "Rojo CLI not found. Install it and reopen PowerShell."
    }
    & rojo serve default.project.json
    if ($LASTEXITCODE -ne 0) { throw "Rojo serve failed." }
} finally {
    Pop-Location
}
