param(
    [string]$Odin = $env:ALICORN_ODIN,
    [switch]$ManualIme,
    [switch]$SurfaceStress,
    [switch]$Diagnostics,
    [int]$CaptureAfter = 2,
    [string]$CaptureDir = 'out\diagnostics'
)

$ErrorActionPreference = 'Stop'
if (-not $Odin) { $Odin = 'odin' }
if ([IO.Path]::IsPathRooted($Odin)) {
    if (-not (Test-Path -LiteralPath $Odin)) { throw "Odin executable not found: $Odin" }
} else {
    $command = Get-Command $Odin -ErrorAction SilentlyContinue
    if (-not $command) { throw "Odin executable not found on PATH: $Odin" }
    $Odin = $command.Source
}

New-Item -ItemType Directory -Force -Path 'out' | Out-Null
& $Odin build native\sdl_gpu_entry -out:out\alicorn_sdl_gpu.exe
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
if ($Diagnostics) {
    $arguments += '--diagnostics'
    $arguments += "--capture-after=$CaptureAfter"
    $arguments += "--capture-dir=$CaptureDir"
}
& .\out\alicorn_sdl_gpu.exe @arguments
exit $LASTEXITCODE
