param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('01_hello', '02_form', '03_async_list', '04_custom_surface', '05_inspector', '06_secondary_windows', '07_simple_appearance', '08_control_gallery', '09_retained_motion')]
    [string]$Example,
    [string]$Odin,
    [switch]$Speed,
    [string[]]$AppArgs = @()
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$OutputRoot = Join-Path $RepoRoot 'out\examples'
$Executable = Join-Path $OutputRoot ($Example + '.exe')
$AccessKit = Get-AlicornAccessKit

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
Push-Location $RepoRoot
try {
    $BuildArgs = @('build', (Join-Path 'examples' $Example), "-collection:alicorn=$RepoRoot", "-out:$Executable") + @($AccessKit.CompilerArguments)
    if ($Speed) { $BuildArgs += '-o:speed' }
    & $Odin @BuildArgs
    if ($LASTEXITCODE -ne 0) { throw "Example build failed: $Example (exit $LASTEXITCODE)" }

    $OdinRoot = Split-Path -Parent $Odin
    $SDL3 = Join-Path $OdinRoot 'vendor\sdl3\SDL3.dll'
    if (-not (Test-Path -LiteralPath $SDL3 -PathType Leaf)) { throw "SDL3.dll not found at '$SDL3'. Use an Odin distribution that includes vendor/sdl3." }
    if ((Get-Item -LiteralPath $SDL3).Length -lt 100000) { throw "SDL3.dll at '$SDL3' appears to be a Git LFS pointer. Run 'git lfs pull' in the Odin checkout." }
    Copy-Item -LiteralPath $SDL3 -Destination (Join-Path $OutputRoot 'SDL3.dll') -Force

    & $Executable @AppArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
