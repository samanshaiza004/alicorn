param(
    [string]$Odin,
    [string]$Metadata = 'examples/01_hello/package.json',
    [ValidateSet('Static', 'Shared')][string]$SDLLinkage = 'Static',
    [string]$OutputDirectory = 'out/native-package/windows-x86_64',
    [switch]$SkipSmokeTest
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$MetadataPath = Join-Path $RepoRoot $Metadata
if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { throw "Metadata file not found: '$MetadataPath'." }
$App = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$App.odinPackage)) { throw 'Metadata must define odinPackage for the build helper.' }
$AppPackage = Join-Path $RepoRoot ([string]$App.odinPackage)
$OutRoot = Join-Path $RepoRoot 'out\native-package'
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$SDLRuntime = $null
$SDLVersion = ''
$SDLLicense = Join-Path (Split-Path -Parent $Odin) 'vendor\sdl3\LICENSE.txt'
$NativeRecipe = $null
$AccessKit = $null
$AccessKitLicenseApache = $null
$AccessKitLicenseMIT = $null
$PreviousOdinRoot = $env:ODIN_ROOT
try {
    if ($SDLLinkage -eq 'Static') {
        Import-Module (Join-Path $PSScriptRoot 'native_link.psm1') -Force -ErrorAction Stop
        $NativeRecipe = New-AlicornWindowsStaticLinkRecipe -Odin $Odin
        $SDLVersion = $NativeRecipe.artifacts.sdl.version
        $SDLLicense = $NativeRecipe.artifacts.sdl.license
        $AccessKitLicenseApache = $NativeRecipe.artifacts.accesskit.licenses[0]
        $AccessKitLicenseMIT = $NativeRecipe.artifacts.accesskit.licenses[1]
        $env:ODIN_ROOT = $NativeRecipe.environment.ODIN_ROOT
    } else {
        $AccessKit = Get-AlicornAccessKit
        $AccessKitLicenseApache = Join-Path $AccessKit.Root 'LICENSE-APACHE'
        $AccessKitLicenseMIT = Join-Path $AccessKit.Root 'LICENSE-MIT'
        $SDLRuntime = Join-Path (Split-Path -Parent $Odin) 'vendor\sdl3\SDL3.dll'
        if (-not (Test-Path -LiteralPath $SDLRuntime -PathType Leaf)) { throw "SDL3.dll not found at '$SDLRuntime'." }
        if ((Get-Item -LiteralPath $SDLRuntime).Length -lt 100000) { throw 'SDK SDL3.dll is a Git LFS pointer, not a runtime.' }
        $VersionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($SDLRuntime)
        if ($VersionInfo.ProductMajorPart -lt 1) { throw "Cannot determine SDL version from '$SDLRuntime'." }
        $SDLVersion = '{0}.{1}.{2}' -f $VersionInfo.ProductMajorPart, $VersionInfo.ProductMinorPart, $VersionInfo.ProductBuildPart
        if (-not (Test-Path -LiteralPath $SDLLicense -PathType Leaf)) { throw "SDL license missing from '$SDLLicense'." }
    }

    Push-Location $RepoRoot
    try {
        $BuiltExecutable = Join-Path $OutRoot ($App.executableName + '.exe')
        $BuildArgs = @('build', $AppPackage, "-collection:alicorn=$RepoRoot", "-out:$BuiltExecutable", '-o:speed')
        if ($SDLLinkage -eq 'Static') {
            $BuildArgs += @($NativeRecipe.odin.compilerArguments)
        } elseif ($AccessKit.LinkerFlags) {
            $BuildArgs += "-extra-linker-flags:$($AccessKit.LinkerFlags)"
        }
        & $Odin @BuildArgs
        if ($LASTEXITCODE -ne 0) { throw "Odin release build failed (exit $LASTEXITCODE)." }

        $PackageArgs = @{
            Executable = $BuiltExecutable
            Metadata = $MetadataPath
            SDLLinkage = $SDLLinkage
            SDLVersion = $SDLVersion
            OutputDirectory = (Join-Path $RepoRoot $OutputDirectory)
            SDLLicense = $SDLLicense
            AccessKitLicenseApache = $AccessKitLicenseApache
            AccessKitLicenseMIT = $AccessKitLicenseMIT
        }
        if ($SDLRuntime) { $PackageArgs['SDLRuntime'] = $SDLRuntime }
        if (-not $SkipSmokeTest) { $PackageArgs['SmokeTest'] = $true }
        & (Join-Path $PSScriptRoot 'package_app.ps1') @PackageArgs
        if ($LASTEXITCODE -ne 0) { throw "Package creation/verification failed (exit $LASTEXITCODE)." }
    } finally { Pop-Location }
} finally {
    if ($null -eq $PreviousOdinRoot) { Remove-Item Env:ODIN_ROOT -ErrorAction SilentlyContinue }
    else { $env:ODIN_ROOT = $PreviousOdinRoot }
}
