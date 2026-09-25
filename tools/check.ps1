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

$targets = @(
    @('tests', 'out\alicorn_tests.exe'),
    @('benchmarks', 'out\alicorn_benchmarks.exe'),
    @('examples\identity_torture', 'out\identity_torture.exe'),
    @('examples\crucible', 'out\crucible.exe'),
    @('examples\runa_text', 'out\runa_text.exe'),
    @('examples\hello', 'out\hello.exe'),
    @('examples\counter', 'out\counter.exe'),
    @('examples\text_input', 'out\text_input.exe'),
    @('examples\keyed_list', 'out\keyed_list.exe'),
    @('examples\advanced_identity', 'out\advanced_identity.exe')
)
foreach ($target in $targets) {
    & $Odin build $target[0] -out:$target[1]
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& .\out\alicorn_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Odin test native\sdl_gpu -out:out\alicorn_native_tests.exe
exit $LASTEXITCODE
