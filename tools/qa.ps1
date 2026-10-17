$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 tools/qa.py
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        & python tools/qa.py
    } else {
        throw "Python 3 is required for the lightweight QA checks."
    }
    if ($LASTEXITCODE -ne 0) { throw "Project contract QA failed." }
    if (Get-Command rojo -ErrorAction SilentlyContinue) {
        & rojo build default.project.json -o Flowers.rbxl
        if ($LASTEXITCODE -ne 0) { throw "Rojo build failed." }
        Write-Host "[PASS] Rojo build"
    } else {
        Write-Warning "Rojo is not installed/in PATH: build test skipped."
    }
} finally {
    Pop-Location
}
