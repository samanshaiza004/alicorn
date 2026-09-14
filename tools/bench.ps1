param(
    [string]$Odin = $env:ALICORN_ODIN
)

if (-not $Odin) { $Odin = 'C:\Users\saman\Documents\odin\dist\odin.exe' }
if ([IO.Path]::IsPathRooted($Odin)) {
    if (-not (Test-Path -LiteralPath $Odin)) { throw "Odin executable not found: $Odin. Set ALICORN_ODIN." }
} else {
    $command = Get-Command $Odin -ErrorAction SilentlyContinue
    if (-not $command) { throw "Odin executable not found on PATH: $Odin. Set ALICORN_ODIN." }
    $Odin = $command.Source
}

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path 'out' | Out-Null
& $Odin build benchmarks -out:out\alicorn_benchmarks.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_benchmarks.exe
exit $LASTEXITCODE
