param(
    [string]$Odin
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
New-Item -ItemType Directory -Force -Path 'out' | Out-Null
& $Odin build benchmarks -out:out\alicorn_benchmarks.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_benchmarks.exe
exit $LASTEXITCODE
