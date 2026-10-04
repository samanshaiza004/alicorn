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
$SDLRoot = Join-Path $OutRoot 'sdl-3.4.16'
$SourceArchive = Join-Path $SDLRoot 'SDL3-3.4.16.tar.gz'
$SourceDirectory = Join-Path $SDLRoot 'source'
$BuildDirectory = Join-Path $SDLRoot 'build'
$Prefix = Join-Path $SDLRoot 'prefix'
$SDLURL = 'https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz'
$SDLSHA256 = '7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68'
New-Item -ItemType Directory -Force -Path $OutRoot, $SDLRoot | Out-Null

$SDLRuntime = $null
$SDLVersion = '3.4.16'
$SDLLicense = Join-Path (Split-Path -Parent $Odin) 'vendor\sdl3\LICENSE.txt'
$SDLLinkFlags = ''
$PreviousOdinRoot = $env:ODIN_ROOT
try {
    if ($SDLLinkage -eq 'Static') {
        foreach ($Tool in @('cmake.exe', 'tar.exe')) {
            if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) { throw "Required tool '$Tool' was not found." }
        }
        if (-not (Test-Path -LiteralPath $SourceArchive -PathType Leaf)) {
            Invoke-WebRequest -Uri $SDLURL -OutFile $SourceArchive
        }
        $ActualHash = (Get-FileHash -LiteralPath $SourceArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ActualHash -ne $SDLSHA256) { throw "Pinned SDL source checksum mismatch. Expected $SDLSHA256; got $ActualHash." }
        if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory 'CMakeLists.txt'))) {
            New-Item -ItemType Directory -Force -Path $SourceDirectory | Out-Null
            & tar.exe -xf $SourceArchive -C $SourceDirectory --strip-components=1
            if ($LASTEXITCODE -ne 0) { throw "SDL source extraction failed (exit $LASTEXITCODE)." }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $BuildDirectory 'CMakeCache.txt'))) {
            & cmake -S $SourceDirectory -B $BuildDirectory `
                "-DCMAKE_INSTALL_PREFIX=$Prefix" `
                '-DCMAKE_BUILD_TYPE=Release' `
                '-DSDL_SHARED=OFF' '-DSDL_STATIC=ON' `
                '-DSDL_TEST_LIBRARY=OFF' '-DSDL_TESTS=OFF' `
                '-DSDL_INSTALL_TESTS=OFF' '-DSDL_DISABLE_INSTALL_DOCS=ON' `
                '-DSDL_FRAMEWORK=OFF'
            if ($LASTEXITCODE -ne 0) { throw "SDL CMake configure failed (exit $LASTEXITCODE)." }
        }
        & cmake --build $BuildDirectory --config Release --target SDL3-static
        if ($LASTEXITCODE -ne 0) { throw "SDL static build failed (exit $LASTEXITCODE)." }
        & cmake --install $BuildDirectory --config Release
        if ($LASTEXITCODE -ne 0) { throw "SDL install failed (exit $LASTEXITCODE)." }

        $ProbeDirectory = Join-Path $SDLRoot 'link-probe'
        & cmake -S (Join-Path $RepoRoot 'tools\sdl_link_probe') -B $ProbeDirectory "-DCMAKE_PREFIX_PATH=$Prefix"
        if ($LASTEXITCODE -ne 0) { throw "SDL link-interface probe failed (exit $LASTEXITCODE)." }
        $LinkInterface = Join-Path $ProbeDirectory 'sdl3-static-link-interface.txt'
        if (-not (Test-Path -LiteralPath $LinkInterface -PathType Leaf)) { throw 'SDL CMake package did not emit static link requirements.' }
        $LinkItems = @((Get-Content -LiteralPath $LinkInterface -Raw) -split '[\r\n;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $NativeLibraries = [Collections.Generic.List[string]]::new()
        foreach ($Item in $LinkItems) {
            if ($Item -in @('SDL3::Headers', 'SDL3::SDL3-static', 'SDL3::SDL3')) { continue }
            if ($Item -match '^\$<') { throw "Unresolved SDL CMake link expression: '$Item'." }
            if ($Item.StartsWith('-')) { $NativeLibraries.Add($Item); continue }
            if ($Item -match '^[A-Za-z0-9_.+-]+::') { throw "Unresolved SDL CMake target dependency '$Item'." }
            if ($Item -match '[/\\]') { throw "Unsupported non-system SDL link dependency '$Item'; inspect the generated CMake target." }
            $LibraryName = $Item -replace '\.lib$', ''
            $NativeLibraries.Add("/DEFAULTLIB:$LibraryName.lib")
        }
        $SDLLinkFlags = ($NativeLibraries | Select-Object -Unique) -join ' '

        $StaticLibrary = Get-ChildItem -LiteralPath $Prefix -Filter 'SDL3-static.lib' -File -Recurse | Select-Object -First 1
        if (-not $StaticLibrary) { throw "SDL3-static.lib was not installed under '$Prefix'." }
        $SDKRoot = Split-Path -Parent $Odin
        $OverlayRoot = Join-Path $OutRoot 'odin-static-overlay'
        New-Item -ItemType Directory -Force -Path $OverlayRoot, (Join-Path $OverlayRoot 'vendor') | Out-Null
        foreach ($SdkDirectory in @('base', 'core', 'shared')) {
            $LinkPath = Join-Path $OverlayRoot $SdkDirectory
            if (-not (Test-Path -LiteralPath $LinkPath)) {
                New-Item -ItemType Junction -Path $LinkPath -Target (Join-Path $SDKRoot $SdkDirectory) | Out-Null
            }
        }
        $VendorOverlay = Join-Path $OverlayRoot 'vendor'
        foreach ($VendorPackage in Get-ChildItem -LiteralPath (Join-Path $SDKRoot 'vendor') -Directory) {
            if ($VendorPackage.Name -eq 'sdl3') { continue }
            $LinkPath = Join-Path $VendorOverlay $VendorPackage.Name
            if (-not (Test-Path -LiteralPath $LinkPath)) {
                New-Item -ItemType Junction -Path $LinkPath -Target $VendorPackage.FullName | Out-Null
            }
        }
        $SDLPackage = Join-Path $VendorOverlay 'sdl3'
        if (-not (Test-Path -LiteralPath $SDLPackage)) {
            Copy-Item -LiteralPath (Join-Path $SDKRoot 'vendor\sdl3') -Destination $SDLPackage -Recurse
        }
        Copy-Item -LiteralPath $StaticLibrary.FullName -Destination (Join-Path $SDLPackage 'SDL3.lib') -Force
        $SDLLicense = Join-Path $SourceDirectory 'LICENSE.txt'
        if (-not (Test-Path -LiteralPath $SDLLicense -PathType Leaf)) { throw 'Pinned SDL source did not contain LICENSE.txt.' }
        $env:ODIN_ROOT = $OverlayRoot
    } else {
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
        $BuildArgs = @('build', $AppPackage, "-out:$BuiltExecutable", '-o:speed')
        if ($SDLLinkage -eq 'Static' -and $SDLLinkFlags) { $BuildArgs += "-extra-linker-flags:$SDLLinkFlags" }
        & $Odin @BuildArgs
        if ($LASTEXITCODE -ne 0) { throw "Odin release build failed (exit $LASTEXITCODE)." }

        $PackageArgs = @{
            Executable = $BuiltExecutable
            Metadata = $MetadataPath
            SDLLinkage = $SDLLinkage
            SDLVersion = $SDLVersion
            OutputDirectory = (Join-Path $RepoRoot $OutputDirectory)
            SDLLicense = $SDLLicense
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
