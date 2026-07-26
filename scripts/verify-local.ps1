# Verify Ad-infinitum can run locally (Windows PowerShell)
# Usage: .\scripts\verify-local.ps1

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

Write-Host ""
Write-Host "=== Ad-infinitum Local Verification ===" -ForegroundColor Cyan
$pass = 0
$fail = 0

function Test-ItemExists($path, $label) {
    if (Test-Path $path) {
        Write-Host "[OK]   $label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "[FAIL] $label - missing: $path" -ForegroundColor Red
        $script:fail++
    }
}

Test-ItemExists "docs\index.html" "Landing page"
Test-ItemExists "docs\assets\hero-2026.png" "Hero image"
Test-ItemExists "fs\f2fs\gc.c" "Kernel sources"
Test-ItemExists "tools\run-experiment.sh" "Experiment runner"
Test-ItemExists "docker-compose.yml" "Docker Compose"

if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dv = docker --version 2>&1
    Write-Host "[OK]   Docker: $dv" -ForegroundColor Green
    $pass++
    $daemon = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Docker installed but daemon not running - start Docker Desktop" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SKIP] Docker not found - use python -m http.server for docs" -ForegroundColor Yellow
}

if (Get-Command wsl -ErrorAction SilentlyContinue) {
    Write-Host "[OK]   WSL available (for F2FS experiments)" -ForegroundColor Green
    $pass++
} else {
    Write-Host "[INFO] WSL not detected" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- What you can run on Windows ---" -ForegroundColor Cyan
Write-Host "  1. Docs only:     python -m http.server 8080 --directory docs"
Write-Host "                    -> http://localhost:8080"
Write-Host "  2. Docs (Docker): docker compose up docs  (start Docker Desktop first)"
Write-Host "  3. F2FS lab:      docker compose --profile lab run --rm lab"
Write-Host "  4. Kernel build:  WSL2 Ubuntu + make"
Write-Host ""

if ($fail -eq 0) {
    Write-Host "Project structure: OK - $pass checks passed" -ForegroundColor Green
} else {
    Write-Host "Project structure: $fail issue(s) found" -ForegroundColor Red
}
