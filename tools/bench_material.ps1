param(
    [string]$Odin
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
New-Item -ItemType Directory -Force -Path 'out' | Out-Null
& $Odin build benchmarks/native_material -o:speed -out:out\alicorn_material_benchmark.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The renderer package imports SDL3 for its normal host path. The benchmark
# calls only CPU geometry routines, but Windows still needs the vendor DLL to
# load the executable.
$OdinRoot = Split-Path -Parent $Odin
$SDL3 = Join-Path $OdinRoot 'vendor\sdl3\SDL3.dll'
if (Test-Path -LiteralPath $SDL3 -PathType Leaf) {
    Copy-Item -LiteralPath $SDL3 -Destination 'out\SDL3.dll' -Force
}
& .\out\alicorn_material_benchmark.exe
exit $LASTEXITCODE
