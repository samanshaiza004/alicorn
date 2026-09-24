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
& .\out\alicorn_tests.exe
exit $LASTEXITCODE
