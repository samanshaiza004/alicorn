param(
    [string]$Odin,
    [switch]$LifecycleSmoke,
    [switch]$GpuStress,
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$OutputRoot = Join-Path $RepoRoot 'out\secondary-window-acceptance'
$Executable = Join-Path $OutputRoot 'AlicornSecondaryWindowAcceptance.exe'
$AccessKit = Get-AlicornAccessKit

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
Push-Location $RepoRoot
try {
    Write-Host 'Building the public-API secondary-window acceptance application'
    & $Odin build tests\fixtures\secondary_windows "-collection:alicorn=$RepoRoot" @($AccessKit.CompilerArguments) "-out:$Executable"
    if ($LASTEXITCODE -ne 0) { throw "Secondary-window fixture build failed (exit $LASTEXITCODE)." }

    $OdinRoot = Split-Path -Parent $Odin
    $SDL = Join-Path $OdinRoot 'vendor\sdl3\SDL3.dll'
    if (-not (Test-Path -LiteralPath $SDL -PathType Leaf)) { throw "SDL3.dll not found at '$SDL'." }
    if ((Get-Item -LiteralPath $SDL).Length -lt 100000) { throw "SDL3.dll at '$SDL' appears to be a Git LFS pointer." }
    Copy-Item -LiteralPath $SDL -Destination (Join-Path $OutputRoot 'SDL3.dll') -Force

    Write-Host "Built: $Executable"
    if ($BuildOnly) { exit 0 }

    $Arguments = @()
    if ($LifecycleSmoke) { $Arguments += '--lifecycle-smoke' }
    if ($GpuStress) { $Arguments += '--gpu-stress' }
    & $Executable @Arguments
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
