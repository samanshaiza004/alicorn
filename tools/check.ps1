param(
    [string]$Odin
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
New-Item -ItemType Directory -Force -Path 'out' | Out-Null

# Odin's current CLI has no separate formatter command. `git diff --check` is
# the non-mutating style gate; the package builds below are the syntax/type gate.
& git diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Odin build benchmarks -out:out\alicorn_benchmarks.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& "$PSScriptRoot\build_examples.ps1" -Odin $Odin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Reuse the canonical test path; it stages SDL3 before running native tests.
& "$PSScriptRoot\test.ps1" -Odin $Odin
exit $LASTEXITCODE
