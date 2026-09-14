param(
    [string]$Odin = $env:ALICORN_ODIN
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
& $Odin build native\sdl_gpu -out:out\alicorn_sdl_gpu.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The Odin SDK vendor directory carries the SDL3 DLL used by this fixture.
$odin_dist = Split-Path -Parent $Odin
$sdl_dir = Join-Path $odin_dist 'vendor\sdl3'
if (Test-Path -LiteralPath $sdl_dir) { $env:PATH = "$sdl_dir;$env:PATH" }
& .\out\alicorn_sdl_gpu.exe
exit $LASTEXITCODE
