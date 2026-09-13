param(
    [string]$Odin = $env:ALICORN_ODIN
)

if (-not $Odin) { $Odin = 'C:\Users\saman\Documents\odin\dist\odin.exe' }
if (-not (Test-Path -LiteralPath $Odin)) { throw "Odin executable not found: $Odin. Set ALICORN_ODIN." }

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path 'out' | Out-Null

# Odin's current CLI has no separate formatter command. `git diff --check` is
# the non-mutating style gate; the package builds below are the syntax/type gate.
& git diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$targets = @(
    @('tests', 'out\alicorn_tests.exe'),
    @('benchmarks', 'out\alicorn_benchmarks.exe'),
    @('examples\identity_torture', 'out\identity_torture.exe'),
    @('examples\crucible', 'out\crucible.exe')
)
foreach ($target in $targets) {
    & $Odin build $target[0] -out:$target[1]
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& .\out\alicorn_tests.exe
exit $LASTEXITCODE

