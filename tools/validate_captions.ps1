param([string]$Odin)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $RepoRoot
try {
    New-Item -ItemType Directory -Force out\caption-fixtures | Out-Null
    $AccessKit = Get-AlicornAccessKit
    & $Odin build native\caption_validation_entry @($AccessKit.CompilerArguments) -out:out\alicorn_caption_validation.exe
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $SDL3 = Join-Path (Split-Path -Parent $Odin) 'vendor\sdl3\SDL3.dll'
    Copy-Item -LiteralPath $SDL3 -Destination out\SDL3.dll -Force
    & .\out\alicorn_caption_validation.exe
    exit $LASTEXITCODE
}
finally { Pop-Location }
