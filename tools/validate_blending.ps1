param([string]$Odin)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $RepoRoot
try {
    New-Item -ItemType Directory -Force out | Out-Null
    if ($env:OS -ne 'Windows_NT') { throw 'Use tools/validate_blending.sh on macOS.' }
    $AccessKit = Get-AlicornAccessKit
    & $Odin build native\blend_validation_entry @($AccessKit.CompilerArguments) -out:out\alicorn_blend_validation.exe
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $SDL3 = Join-Path (Split-Path -Parent $Odin) 'vendor\sdl3\SDL3.dll'
    if (-not (Test-Path -LiteralPath $SDL3 -PathType Leaf) -or (Get-Item -LiteralPath $SDL3).Length -lt 100000) { throw "Valid SDL3.dll not found at '$SDL3'." }
    Copy-Item -LiteralPath $SDL3 -Destination out\SDL3.dll -Force
    & .\out\alicorn_blend_validation.exe
    exit $LASTEXITCODE
}
finally { Pop-Location }
