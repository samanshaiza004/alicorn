param(
    [string]$Odin
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
New-Item -ItemType Directory -Force -Path 'out' | Out-Null
& $Odin build tests -out:out\alicorn_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin build native\sdl_gpu_entry -out:out\alicorn_sdl_gpu.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The text-input contract executable links SDL3 even though this mode does not
# create a window. Stage the runtime DLL just as the native smoke runners do.
$OdinRoot = Split-Path -Parent $Odin
$SDL3 = Join-Path $OdinRoot 'vendor\sdl3\SDL3.dll'
if (-not (Test-Path -LiteralPath $SDL3 -PathType Leaf)) {
    throw "SDL3.dll not found at '$SDL3'. Use an Odin distribution that includes vendor/sdl3."
}
if ((Get-Item -LiteralPath $SDL3).Length -lt 100000) {
    throw "SDL3.dll at '$SDL3' appears to be a Git LFS pointer. Run 'git lfs pull' in the Odin checkout."
}
Copy-Item -LiteralPath $SDL3 -Destination 'out\SDL3.dll' -Force

& $Odin test runtime
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin test native\sdl_gpu -out:out\alicorn_native_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& .\out\alicorn_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_sdl_gpu.exe --text-input-contract-test
exit $LASTEXITCODE
