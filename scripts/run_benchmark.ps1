<#
.SYNOPSIS
  Reproducible FPS benchmark for the FoveaSplat3D render path (Phase 0, C6).

.DESCRIPTION
  Launches Godot WINDOWED (real rendering — not headless) on fps_benchmark.gd,
  which generates N splats, orbits a camera for a fixed duration, and writes a
  JSON report. Prints the report and the 90 FPS verdict.

.EXAMPLE
  pwsh scripts/run_benchmark.ps1 -Splats 1000000 -Duration 12
  pwsh scripts/run_benchmark.ps1 -Splats 200000 -Duration 8 -Godot "F:\Godot_v4.7-dev5_mono_win64\...\Godot_..._console.exe"
#>
param(
    [int]    $Splats   = 1000000,
    [double] $Duration = 12.0,
    [string] $Godot    = $env:GODOT_BIN,
    [string] $Out      = (Join-Path $PSScriptRoot "..\benchmark_report.json")
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Out = [System.IO.Path]::GetFullPath($Out)

if (-not $Godot) {
    # Best-effort autodetect of a local Godot 4.7 mono build.
    $Godot = Get-ChildItem "F:\", "C:\Tools", "$env:USERPROFILE\Downloads" -Recurse -Filter "Godot_v4.7*_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Godot -or -not (Test-Path $Godot)) {
    Write-Error "Godot binary not found. Pass -Godot <path> or set `$env:GODOT_BIN."
}

Write-Host "Benchmark: $Splats splats, ${Duration}s — $Godot" -ForegroundColor Cyan

& $Godot --path $ProjectRoot -s res://addons/foveacore/test/fps_benchmark.gd -- `
    "--splats=$Splats" "--duration=$Duration" "--out=$Out"

if (Test-Path $Out) {
    Write-Host "`n=== benchmark_report.json ===" -ForegroundColor Green
    Get-Content $Out
} else {
    Write-Warning "No report produced at $Out"
}
