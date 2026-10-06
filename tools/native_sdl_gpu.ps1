param(
    [string]$Odin,
    [switch]$ManualIme,
    [switch]$SurfaceStress,
    [switch]$SurfaceGeometryTest,
    [switch]$Diagnostics,
    [switch]$DebugBounds,
    [switch]$Inspector,
    [switch]$InspectorOpen,
    [switch]$MillionRowAccessibility,
    [switch]$Smoke,
    [int]$CaptureAfter = 2,
    [string]$CaptureDir = 'out\diagnostics'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin

New-Item -ItemType Directory -Force -Path 'out' | Out-Null
$AccessKit = Get-AlicornAccessKit
$Entry = 'native\sdl_gpu_entry'
$Executable = '.\out\alicorn_sdl_gpu.exe'
if ($MillionRowAccessibility) {
    $Entry = 'native\semantic_virtualization_entry'
    $Executable = '.\out\alicorn_semantic_virtualization.exe'
}
& $Odin build $Entry "-extra-linker-flags:$($AccessKit.LinkerFlags)" -out:$Executable
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The Odin SDK vendor directory carries the SDL3 DLL used by this fixture.
$odin_root = Split-Path -Parent $Odin
$sdl_dll = Join-Path $odin_root 'vendor\sdl3\SDL3.dll'
if (-not (Test-Path -LiteralPath $sdl_dll -PathType Leaf)) {
    throw @"
SDL3.dll was not found.

Expected:
$sdl_dll

Use an Odin distribution containing vendor/sdl3,
or run git lfs pull in your Odin checkout.
"@
}

$sdl_info = Get-Item -LiteralPath $sdl_dll
if ($sdl_info.Length -lt 100000) {
    throw @"
SDL3.dll appears invalid or is a Git LFS pointer:
$sdl_dll
Size: $($sdl_info.Length) bytes

Run:
git lfs install
git lfs pull
"@
}

Copy-Item -LiteralPath $sdl_dll -Destination 'out\SDL3.dll' -Force
$arguments = @()
if ($ManualIme) { $arguments += '--manual-ime' }
if ($SurfaceStress) { $arguments += '--surface-stress' }
if ($SurfaceGeometryTest) { $arguments += '--surface-geometry-test' }
if ($Diagnostics) {
    $arguments += '--diagnostics'
    $arguments += "--capture-after=$CaptureAfter"
    $arguments += "--capture-dir=$CaptureDir"
}
if ($DebugBounds) { $arguments += '--debug-bounds' }
if ($Inspector) { $arguments += '--inspector' }
if ($InspectorOpen) { $arguments += '--inspector-open' }
if ($Smoke) { $arguments += '--smoke' }
& $Executable @arguments
exit $LASTEXITCODE
