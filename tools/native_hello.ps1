param(
    [string]$Odin
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$OutDir = Join-Path $RepoRoot 'out'
$Executable = Join-Path $OutDir 'alicorn_native_hello.exe'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $RepoRoot
try {
    & $Odin build examples\native_hello "-out:$Executable"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $OdinRoot = Split-Path -Parent $Odin
    $SDL3 = Join-Path $OdinRoot 'vendor\sdl3\SDL3.dll'
    if (-not (Test-Path -LiteralPath $SDL3 -PathType Leaf)) {
        throw "SDL3.dll not found at '$SDL3'. Use an Odin distribution that includes vendor/sdl3."
    }
    if ((Get-Item -LiteralPath $SDL3).Length -lt 100000) {
        throw "SDL3.dll at '$SDL3' appears to be a Git LFS pointer. Run 'git lfs pull' in the Odin checkout."
    }
    Copy-Item -LiteralPath $SDL3 -Destination (Join-Path $OutDir 'SDL3.dll') -Force

    & $Executable
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
