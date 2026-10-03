param(
    [string]$Odin
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
New-Item -ItemType Directory -Force -Path 'out' | Out-Null
& $Odin build benchmarks/text_layout -o:speed -out:out\alicorn_text_layout_benchmark.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_text_layout_benchmark.exe
exit $LASTEXITCODE
