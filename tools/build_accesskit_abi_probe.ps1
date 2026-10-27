param(
	[string]$OutputDirectory = 'out\accesskit_abi_probe',
	[string]$Compiler = 'cl'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
Initialize-AlicornMsvcEnvironment
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$HeaderDir = Join-Path $RepoRoot '.deps\accesskit\accesskit-c-0.23.1\include'
$Source = Join-Path $RepoRoot 'tests\accesskit_abi_contract\accesskit_abi_round_trip.c'
$CompilerCommand = Get-Command $Compiler -ErrorAction SilentlyContinue
$CompilerPath = if ($CompilerCommand) { $CompilerCommand.Source } else { $null }
if (-not $CompilerPath) {
	throw "AccessKit ABI probe: MSVC C compiler not found. Run from a Visual Studio Developer PowerShell or pass -Compiler with the cl.exe path."
}
if (-not (Test-Path -LiteralPath (Join-Path $HeaderDir 'accesskit.h') -PathType Leaf)) {
	throw "AccessKit ABI probe: pinned AccessKit header not found at '$HeaderDir'."
}

$OutputDirectory = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDirectory))
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$Object = Join-Path $OutputDirectory 'accesskit_abi_round_trip.obj'
$Library = Join-Path $OutputDirectory 'alicorn_accesskit_abi_probe.lib'
& $CompilerPath /nologo /std:c11 /W4 /WX "/I$HeaderDir" /c $Source "/Fo$Object"
if ($LASTEXITCODE -ne 0) { throw "AccessKit ABI probe: C compilation failed with exit code $LASTEXITCODE." }
$LibCommand = Get-Command 'lib' -ErrorAction SilentlyContinue
if (-not $LibCommand) { throw 'AccessKit ABI probe: MSVC lib.exe was not found in PATH.' }
& $LibCommand.Source /nologo "/OUT:$Library" $Object
if ($LASTEXITCODE -ne 0) { throw "AccessKit ABI probe: library creation failed with exit code $LASTEXITCODE." }
"/LIBPATH:$OutputDirectory"
