param(
    [string]$Odin
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot 'out') | Out-Null

# Odin's current CLI has no separate formatter command. `git diff --check` is
# the non-mutating style gate; the package builds below are the syntax/type gate.
& git diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Odin build benchmarks -out:out\alicorn_benchmarks.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& "$PSScriptRoot\build_examples.ps1" -Odin $Odin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$FixtureOutput = Join-Path $RepoRoot 'out\fixtures'
New-Item -ItemType Directory -Force -Path $FixtureOutput | Out-Null
$AccessKit = Get-AlicornAccessKit
$FixturePackages = @(
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'tests\fixtures') -Directory
    Get-Item -LiteralPath (Join-Path $RepoRoot 'tools\runa_text')
)
foreach ($Fixture in $FixturePackages) {
    $Main = Join-Path $Fixture.FullName 'main.odin'
    if (-not (Test-Path -LiteralPath $Main -PathType Leaf)) { continue }
    $Output = Join-Path $FixtureOutput ($Fixture.Name + '.exe')
    & $Odin build $Fixture.FullName "-collection:alicorn=$RepoRoot" "-extra-linker-flags:$($AccessKit.LinkerFlags)" "-out:$Output"
    if ($LASTEXITCODE -ne 0) { throw "Fixture build failed: $($Fixture.Name)" }
}

# Reuse the canonical test path; it stages SDL3 before running native tests.
& "$PSScriptRoot\test.ps1" -Odin $Odin
exit $LASTEXITCODE
