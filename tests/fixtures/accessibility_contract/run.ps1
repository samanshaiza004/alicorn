param([string]$Odin)

$ErrorActionPreference = 'Stop'
$Fixture = $PSScriptRoot
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $Fixture '..\..\..')).Path
. (Join-Path $RepoRoot 'tools\common.ps1')
$Odin = Resolve-AlicornOdin -Requested $Odin
$AccessKit = Get-AlicornAccessKit
$OutputDirectory = Join-Path $RepoRoot 'out\fixtures\accessibility_contract'
$Executable = Join-Path $OutputDirectory 'accessibility_contract.exe'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

& $Odin build (Join-Path $Fixture '.') "-collection:alicorn=$RepoRoot" `
	@($AccessKit.CompilerArguments) "-out:$Executable"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Match the native fixture runner's SDL staging behavior.
$OdinRoot = Split-Path -Parent $Odin
$SdlDll = Join-Path $OdinRoot 'vendor\sdl3\SDL3.dll'
if (-not (Test-Path -LiteralPath $SdlDll -PathType Leaf)) {
	throw "SDL3.dll was not found at '$SdlDll'. Use an Odin distribution containing vendor/sdl3."
}
if ((Get-Item -LiteralPath $SdlDll).Length -lt 100000) {
	throw "SDL3.dll appears invalid or is an LFS pointer: '$SdlDll'. Run git lfs pull in the Odin checkout."
}
Copy-Item -LiteralPath $SdlDll -Destination (Join-Path $OutputDirectory 'SDL3.dll') -Force
& $Executable
exit $LASTEXITCODE
