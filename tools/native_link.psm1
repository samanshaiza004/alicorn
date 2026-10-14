Set-StrictMode -Version Latest

$script:NativeLinkSchemaVersion = 1
$script:PreparationVersion = 1
$script:SDLVersion = '3.4.16'
$script:SDLURL = 'https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz'
$script:SDLSHA256 = '7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68'

. (Join-Path $PSScriptRoot 'common.ps1')

function Get-AlicornFullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-AlicornPathWithin([string]$Path, [string]$Root) {
    $fullPath = Get-AlicornFullPath $Path
    $fullRoot = (Get-AlicornFullPath $Root) + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Get-AlicornFileHash([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { throw "Required file does not exist: '$Path'." }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-AlicornTreeInventory([string]$Root) {
    if (-not [IO.Directory]::Exists($Root)) { throw "Required directory does not exist: '$Root'." }
    $fullRoot = Get-AlicornFullPath $Root
    $inventory = [Collections.Generic.List[object]]::new()
    foreach ($file in (Get-ChildItem -LiteralPath $fullRoot -File -Recurse | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($fullRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $inventory.Add([ordered]@{ path=$relative; sha256=(Get-AlicornFileHash $file.FullName) })
    }
    return ,$inventory.ToArray()
}

function Get-AlicornObjectHash($Value) {
    $json = ConvertTo-Json -InputObject $Value -Depth 40 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-AlicornNativeLogged {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Description
    )
    $parent = Split-Path -Parent $LogPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    & $Executable @Arguments *> $LogPath
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $tail = @()
        if (Test-Path -LiteralPath $LogPath -PathType Leaf) { $tail = @(Get-Content -LiteralPath $LogPath -Tail 40) }
        throw "$Description failed (exit $exitCode).`n$($tail -join "`n")"
    }
}

function Get-AlicornCMakeDefaultGenerator([string]$CMake) {
    if (-not [string]::IsNullOrWhiteSpace($env:CMAKE_GENERATOR)) { return $env:CMAKE_GENERATOR.Trim() }
    $help = @(& $CMake --help 2>$null)
    $line = $help | Where-Object { $_ -match '^\s*\*\s+' } | Select-Object -First 1
    if (-not $line) { throw 'Could not determine the CMake default generator. Set CMAKE_GENERATOR explicitly.' }
    return (($line -replace '^\s*\*\s+', '') -replace '\s*=\s*.*$', '').Trim()
}

function Get-AlicornCMakeGeneratorArguments([string]$Generator) {
    $arguments = [Collections.Generic.List[string]]::new()
    $arguments.Add('-G')
    $arguments.Add($Generator)
    if ($Generator -match '^Visual Studio') {
        $platform = if ([string]::IsNullOrWhiteSpace($env:CMAKE_GENERATOR_PLATFORM)) { 'x64' } else { $env:CMAKE_GENERATOR_PLATFORM.Trim() }
        if ($platform -notin @('x64', 'amd64', 'AMD64')) {
            throw "Static native linking supports the x64 target. CMAKE_GENERATOR_PLATFORM is '$platform'."
        }
        $arguments.Add('-A')
        $arguments.Add('x64')
        if (-not [string]::IsNullOrWhiteSpace($env:CMAKE_GENERATOR_TOOLSET)) {
            $arguments.Add('-T')
            $arguments.Add($env:CMAKE_GENERATOR_TOOLSET.Trim())
        }
        if (-not [string]::IsNullOrWhiteSpace($env:CMAKE_GENERATOR_INSTANCE)) {
            $arguments.Add("-DCMAKE_GENERATOR_INSTANCE=$($env:CMAKE_GENERATOR_INSTANCE.Trim())")
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($env:CMAKE_GENERATOR_PLATFORM)) {
        throw "CMAKE_GENERATOR_PLATFORM is only supported with Visual Studio generators; selected '$Generator'."
    }
    return ,$arguments.ToArray()
}

function Get-AlicornCMakeCache([string]$Path) {
    $values = @{}
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^(?<key>[^#/:]+):[^=]*=(?<value>.*)$') { $values[$Matches.key] = $Matches.value }
    }
    return $values
}

function Resolve-AlicornToolFile([string]$Requested, [string]$Name, [string[]]$Candidates = @()) {
    if (-not [string]::IsNullOrWhiteSpace($Requested) -and [IO.File]::Exists($Requested)) {
        return Get-AlicornFullPath $Requested
    }
    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and [IO.File]::Exists($candidate)) {
            return Get-AlicornFullPath $candidate
        }
    }
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return Get-AlicornFullPath $command.Source }
    throw "Could not resolve the selected MSVC tool '$Name'. Run the recipe from a Visual Studio developer environment or repair the CMake toolchain."
}

function Get-AlicornCMakeCompilerFacts([string]$BuildDirectory) {
    $cachePath = Join-Path $BuildDirectory 'CMakeCache.txt'
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) { throw "CMake toolchain probe did not write '$cachePath'." }
    $cache = Get-AlicornCMakeCache $cachePath
    $compilerFiles = Get-ChildItem -LiteralPath (Join-Path $BuildDirectory 'CMakeFiles') -Filter 'CMakeCCompiler.cmake' -File -Recurse | Select-Object -First 1
    $cxxCompilerFiles = Get-ChildItem -LiteralPath (Join-Path $BuildDirectory 'CMakeFiles') -Filter 'CMakeCXXCompiler.cmake' -File -Recurse | Select-Object -First 1
    if (-not $compilerFiles -or -not $cxxCompilerFiles) { throw 'CMake did not identify both C and C++ compiler toolchains.' }
    $cText = Get-Content -LiteralPath $compilerFiles.FullName -Raw
    $cxxText = Get-Content -LiteralPath $cxxCompilerFiles.FullName -Raw
    $cId = [regex]::Match($cText, 'set\(CMAKE_C_COMPILER_ID "([^"]+)"\)').Groups[1].Value
    $cVersion = [regex]::Match($cText, 'set\(CMAKE_C_COMPILER_VERSION "([^"]+)"\)').Groups[1].Value
    $cxxId = [regex]::Match($cxxText, 'set\(CMAKE_CXX_COMPILER_ID "([^"]+)"\)').Groups[1].Value
    $cxxVersion = [regex]::Match($cxxText, 'set\(CMAKE_CXX_COMPILER_VERSION "([^"]+)"\)').Groups[1].Value
    if ($cId -ne 'MSVC' -or $cxxId -ne 'MSVC') {
        throw "Static native linking requires the MSVC C and C++ compilers; C='$cId', C++='$cxxId'."
    }
    if ($cache['CMAKE_SIZEOF_VOID_P'] -ne '8') { throw 'The selected MSVC toolchain does not target 64-bit Windows.' }
    if ($cache['CMAKE_MSVC_RUNTIME_LIBRARY'] -ne 'MultiThreaded') {
        $crt = $cache['CMAKE_MSVC_RUNTIME_LIBRARY']
        throw "The SDL static build must use the static MSVC CRT (/MT); CMake reported '$crt'."
    }
    $platform = $cache['CMAKE_GENERATOR_PLATFORM']
    if ([string]::IsNullOrWhiteSpace($platform)) { $platform = $cache['CMAKE_VS_PLATFORM_NAME'] }
    if ($cache['CMAKE_GENERATOR'] -match '^Visual Studio' -and $platform -notin @('x64', 'amd64', 'AMD64')) {
        throw "The selected Visual Studio generator is not targeting x64 (platform='$platform')."
    }
    $vsTools = $env:VCToolsInstallDir
    $cCompilerCandidate = if ($vsTools) { Join-Path $vsTools 'bin\Hostx64\x64\cl.exe' } else { $null }
    $cxxCompilerCandidate = $cCompilerCandidate
    $cCompiler = Resolve-AlicornToolFile $cache['CMAKE_C_COMPILER'] 'cl.exe' @($cCompilerCandidate)
    $cxxCompiler = Resolve-AlicornToolFile $cache['CMAKE_CXX_COMPILER'] 'cl.exe' @($cxxCompilerCandidate)
    $linkerCandidates = [Collections.Generic.List[string]]::new()
    if ($cCompiler) { $linkerCandidates.Add((Join-Path (Split-Path -Parent $cCompiler) 'link.exe')) }
    if ($vsTools) { $linkerCandidates.Add((Join-Path $vsTools 'bin\Hostx64\x64\link.exe')) }
    $linker = Resolve-AlicornToolFile $cache['CMAKE_LINKER'] 'link.exe' $linkerCandidates.ToArray()
    $cCompilerInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($cCompiler)
    $cxxCompilerInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($cxxCompiler)
    $linkerInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($linker)
    return [ordered]@{
        generator = $cache['CMAKE_GENERATOR']
        platform = $platform
        toolset = $cache['CMAKE_GENERATOR_TOOLSET']
        cCompiler = $cCompiler
        cCompilerId = $cId
        cCompilerVersion = $cVersion
        cCompilerFileVersion = $cCompilerInfo.FileVersion
        cCompilerSha256 = (Get-AlicornFileHash $cCompiler)
        cxxCompiler = $cxxCompiler
        cxxCompilerId = $cxxId
        cxxCompilerVersion = $cxxVersion
        cxxCompilerFileVersion = $cxxCompilerInfo.FileVersion
        cxxCompilerSha256 = (Get-AlicornFileHash $cxxCompiler)
        linker = $linker
        linkerVersion = $linkerInfo.FileVersion
        linkerSha256 = (Get-AlicornFileHash $linker)
        pointerSize = $cache['CMAKE_SIZEOF_VOID_P']
        crt = $cache['CMAKE_MSVC_RUNTIME_LIBRARY']
        visualStudioVersion = $cache['CMAKE_VS_VERSION_BUILD_NUMBER']
        windowsSdkVersion = $env:WindowsSDKVersion
        vcToolsInstallDir = $env:VCToolsInstallDir
    }
}

function Get-AlicornToolchainProbe {
    param([string]$CMake, [string[]]$GeneratorArguments, [string]$ProbeRoot)
    $probeBuild = Join-Path $ProbeRoot 'build'
    New-Item -ItemType Directory -Path $ProbeRoot -Force | Out-Null
    $arguments = @('-S', (Join-Path $PSScriptRoot 'cmake_toolchain_probe'), '-B', $probeBuild) + $GeneratorArguments + @(
        '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded'
    )
    Invoke-AlicornNativeLogged -Executable $CMake -Arguments $arguments -LogPath (Join-Path $ProbeRoot 'configure.log') -Description 'CMake MSVC x64 toolchain probe'
    return Get-AlicornCMakeCompilerFacts $probeBuild
}

function ConvertTo-AlicornMsvcPathArgument([string]$Prefix, [string]$Path) {
    if ($Path.Contains('"')) { throw "Native library paths cannot contain a quote character: '$Path'." }
    if ($Path -match '\s') { return "$Prefix`"$Path`"" }
    return "$Prefix$Path"
}

function ConvertFrom-AlicornCMakeLinkInterface {
    param(
        [string[]]$Directories = @(),
        [string[]]$Options = @(),
        [string[]]$Libraries = @()
    )
    $convertedDirectories = [Collections.Generic.List[string]]::new()
    $convertedOptions = [Collections.Generic.List[string]]::new()
    $convertedLibraries = [Collections.Generic.List[string]]::new()
    foreach ($item in $Directories) {
        $value = $item.Trim()
        if (-not $value) { continue }
        if ($value.Contains('$<')) { throw "Unresolved SDL link-directory generator expression: '$value'." }
        if (-not [IO.Path]::IsPathRooted($value)) { throw "SDL exported a relative link directory that cannot be resolved safely: '$value'." }
        $convertedDirectories.Add((ConvertTo-AlicornMsvcPathArgument '/LIBPATH:' $value))
    }
    foreach ($item in $Options) {
        $value = $item.Trim()
        if (-not $value) { continue }
        if ($value -match '^\$<LINK_ONLY:(.*)>$') { $value = $Matches[1] }
        if ($value.Contains('$<')) { throw "Unresolved SDL link-option generator expression: '$value'." }
        if ($value.StartsWith('-')) { throw "Unsupported non-MSVC SDL link option '$value'." }
        $convertedOptions.Add($value)
    }
    foreach ($item in $Libraries) {
        $value = $item.Trim()
        if (-not $value) { continue }
        if ($value -match '^\$<LINK_ONLY:([^<>]+)>$') { $value = $Matches[1] }
        if ($value -in @('SDL3::Headers', 'SDL3::SDL3-static', 'SDL3::SDL3')) { continue }
        if ($value -match '^[A-Za-z0-9_.+-]+::') { throw "Unresolved SDL CMake target dependency '$value'." }
        if ($value.Contains('$<')) { throw "Unresolved SDL link-library generator expression: '$value'." }
        if ($value.StartsWith('-')) { throw "Unsupported non-MSVC SDL link dependency '$value'." }
        if ([IO.Path]::IsPathRooted($value)) {
            if (-not [IO.File]::Exists($value)) { throw "SDL link interface references a missing library: '$value'." }
            $convertedLibraries.Add((ConvertTo-AlicornMsvcPathArgument '' $value))
            continue
        }
        if ($value -match '[/\\]') { throw "Unsupported relative SDL link dependency '$value'." }
        if ($value -notmatch '^[A-Za-z0-9_.+-]+(?:\.lib)?$') { throw "Invalid SDL link dependency '$value'." }
        if ($value -notmatch '\.lib$') { $value += '.lib' }
        $convertedLibraries.Add("/DEFAULTLIB:$value")
    }
    return [ordered]@{
        directories = @($convertedDirectories.ToArray())
        options = @($convertedOptions.ToArray())
        libraries = @($convertedLibraries.ToArray())
        arguments = @($convertedDirectories.ToArray()) + @($convertedOptions.ToArray()) + @($convertedLibraries.ToArray())
    }
}

function Get-AlicornTextList([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "CMake did not emit expected link interface file '$Path'." }
    return ,@((Get-Content -LiteralPath $Path) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-AlicornRecipeManifest([string]$GenerationRoot) {
    $manifestPath = Join-Path $GenerationRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Prepared generation has no manifest: '$manifestPath'." }
    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Test-AlicornNativeLinkGeneration {
    param([Parameter(Mandatory)][string]$GenerationRoot, [Parameter(Mandatory)][string]$ExpectedFingerprint)
    try {
        $root = Get-AlicornFullPath $GenerationRoot
        $manifest = Get-AlicornRecipeManifest $root
        if ($manifest.schemaVersion -ne $script:NativeLinkSchemaVersion) { throw 'Manifest schema version mismatch.' }
        if ($manifest.provenance.fingerprint -ne $ExpectedFingerprint) { throw 'Manifest fingerprint mismatch.' }
        if ((Get-AlicornObjectHash $manifest.inputs) -ne $ExpectedFingerprint) { throw 'Manifest input fingerprint does not match its recorded inputs.' }
        $recordedArtifacts = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($artifact in $manifest.artifacts) {
            $relativePath = ([string]$artifact.path) -replace '\\', '/'
            if ([string]::IsNullOrWhiteSpace($relativePath) -or -not $recordedArtifacts.Add($relativePath)) {
                throw "Manifest contains an empty or duplicate artifact path: '$relativePath'."
            }
            $path = Join-Path $root $artifact.path
            if (-not (Test-AlicornPathWithin $path $root)) { throw "Artifact escapes the prepared generation: '$($artifact.path)'." }
            if (-not [IO.File]::Exists($path)) { throw "Prepared artifact is missing: '$($artifact.path)'." }
            if ((Get-AlicornFileHash $path) -ne $artifact.sha256) { throw "Prepared artifact hash mismatch: '$($artifact.path)'." }
        }
        foreach ($requiredArtifact in @('recipe.json', 'odin/vendor/sdl3/SDL3.lib', 'accesskit/lib/accesskit.lib', 'licenses/SDL-LICENSE.txt', 'licenses/AccessKit-LICENSE-APACHE.txt', 'licenses/AccessKit-LICENSE-MIT.txt')) {
            if (-not $recordedArtifacts.Contains($requiredArtifact)) { throw "Manifest does not validate required artifact '$requiredArtifact'." }
        }
        $actualArtifacts = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in (Get-ChildItem -LiteralPath $root -File -Recurse)) {
            $relativePath = $file.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
            if ($relativePath -ne 'manifest.json') { [void]$actualArtifacts.Add($relativePath) }
        }
        if ($actualArtifacts.Count -ne $recordedArtifacts.Count) { throw 'Prepared generation file inventory does not match its manifest.' }
        foreach ($relativePath in $actualArtifacts) {
            if (-not $recordedArtifacts.Contains($relativePath)) { throw "Prepared generation contains an unrecorded artifact '$relativePath'." }
        }
        foreach ($junction in $manifest.junctions) {
            $path = Join-Path $root $junction.path
            if (-not [IO.Directory]::Exists($path)) { throw "SDK overlay junction is missing: '$($junction.path)'." }
            $target = (Get-Item -LiteralPath $path -Force).Target
            if ($target -is [array]) { $target = $target[0] }
            if (-not $target -or (Get-AlicornFullPath $target) -ne (Get-AlicornFullPath $junction.target)) {
                throw "SDK overlay junction points to the wrong Odin SDK directory: '$($junction.path)'."
            }
        }
        return [pscustomobject]@{ valid=$true; reason='' }
    } catch {
        return [pscustomobject]@{ valid=$false; reason=$_.Exception.Message }
    }
}

function Enter-AlicornGenerationLock([string]$LockPath) {
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        try { return [IO.File]::Open($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] { Start-Sleep -Milliseconds 250 }
    }
    throw "Timed out waiting for another process to prepare native-link generation '$([IO.Path]::GetFileNameWithoutExtension($LockPath))'."
}

function New-AlicornWindowsStaticLinkRecipe {
    [CmdletBinding()]
    param([string]$Odin, [string]$OdinRoot)

    if ($env:OS -ne 'Windows_NT') { throw 'The initial static native-link recipe supports Windows x64 only.' }
    if ($env:PROCESSOR_ARCHITECTURE -notin @('AMD64', 'ARM64')) { throw "The recipe requires a 64-bit Windows host; reported architecture '$env:PROCESSOR_ARCHITECTURE'." }
    $Odin = Resolve-AlicornOdin -Requested $Odin
    if ([string]::IsNullOrWhiteSpace($OdinRoot)) { $OdinRoot = Split-Path -Parent $Odin }
    $OdinRoot = (Resolve-Path -LiteralPath $OdinRoot).Path
    foreach ($required in @('base', 'core', 'shared', 'bin', 'vendor\sdl3')) {
        if (-not [IO.Directory]::Exists((Join-Path $OdinRoot $required))) { throw "Odin SDK root '$OdinRoot' is missing '$required'." }
    }

    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $outRoot = Join-Path $repoRoot 'out\native-link'
    $generationRootParent = Join-Path $outRoot 'generations'
    $lockRoot = Join-Path $outRoot 'locks'
    $stagingRoot = Join-Path $outRoot 'staging'
    $sourceRoot = Join-Path $outRoot 'sources'
    foreach ($path in @($generationRootParent, $lockRoot, $stagingRoot, $sourceRoot)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    $outRoot = Get-AlicornFullPath $outRoot

    $cmakeCommand = Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $tarCommand = Get-Command tar.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmakeCommand) { throw "Required tool 'cmake.exe' was not found. Install CMake and add it to PATH." }
    if (-not $tarCommand) { throw "Required tool 'tar.exe' was not found. Install Windows tar and add it to PATH." }
    $cmake = $cmakeCommand.Source
    $cmakeVersion = ((& $cmake --version 2>$null) | Select-Object -First 1).Trim()
    $generator = Get-AlicornCMakeDefaultGenerator $cmake
    $generatorArguments = Get-AlicornCMakeGeneratorArguments $generator

    $probeRoot = Join-Path $outRoot ('.toolchain-probe-' + [guid]::NewGuid().ToString('N'))
    try {
        $toolchain = Get-AlicornToolchainProbe -CMake $cmake -GeneratorArguments $generatorArguments -ProbeRoot $probeRoot
    } finally {
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force }
    }
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { throw 'A 64-bit host is not sufficient: the initial recipe requires an x64 MSVC host toolchain.' }

    $accessKit = Get-AlicornAccessKit
    $accessKitArchive = Join-Path $accessKit.Root "accesskit-c-0.23.1.zip"
    $accessKitLibrary = $accessKit.Library
    $accessKitLicenseApache = Join-Path $accessKit.Root 'LICENSE-APACHE'
    $accessKitLicenseMIT = Join-Path $accessKit.Root 'LICENSE-MIT'
    foreach ($path in @($accessKitLibrary, $accessKitArchive, $accessKitLicenseApache, $accessKitLicenseMIT)) {
        if (-not [IO.File]::Exists($path)) { throw "AccessKit static input is missing: '$path'." }
    }

    $archive = Join-Path $sourceRoot "SDL3-$($script:SDLVersion).tar.gz"
    if (-not [IO.File]::Exists($archive)) {
        $download = Join-Path $sourceRoot ('.download-' + [guid]::NewGuid().ToString('N') + '.tar.gz')
        try {
            Invoke-WebRequest -Uri $script:SDLURL -OutFile $download
            $downloadHash = Get-AlicornFileHash $download
            if ($downloadHash -ne $script:SDLSHA256) { throw "Pinned SDL source SHA-256 mismatch. Expected $($script:SDLSHA256); got $downloadHash." }
            try { [IO.File]::Move($download, $archive) }
            catch {
                if (-not [IO.File]::Exists($archive) -or (Get-AlicornFileHash $archive) -ne $script:SDLSHA256) { throw }
            }
        } finally {
            if ([IO.File]::Exists($download)) { Remove-Item -LiteralPath $download -Force }
        }
    }
    $actualSDLHash = Get-AlicornFileHash $archive
    if ($actualSDLHash -ne $script:SDLSHA256) { throw "Pinned SDL source SHA-256 mismatch. Expected $($script:SDLSHA256); got $actualSDLHash. Remove the invalid archive '$archive' and retry." }

    $odinVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($Odin)
    $odinVersionOutput = (@(& $Odin version 2>$null) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($odinVersionOutput)) { throw "Could not determine the Odin compiler/SDK identity from '$Odin version'." }
    $sdkSdlInventory = Get-AlicornTreeInventory (Join-Path $OdinRoot 'vendor\sdl3')
    $inputs = [ordered]@{
        contractVersion = $script:NativeLinkSchemaVersion
        preparationVersion = $script:PreparationVersion
        preparationCodeSha256 = (Get-AlicornFileHash (Join-Path $PSScriptRoot 'native_link.psm1'))
        cmakeProbeSha256 = (Get-AlicornFileHash (Join-Path $PSScriptRoot 'cmake_toolchain_probe\CMakeLists.txt'))
        sdlLinkProbeSha256 = (Get-AlicornFileHash (Join-Path $PSScriptRoot 'sdl_link_probe\CMakeLists.txt'))
        target = 'windows-x86_64-msvc'
        sdl = [ordered]@{ version=$script:SDLVersion; url=$script:SDLURL; sourceSha256=$actualSDLHash; options=@('Release', 'SDL_SHARED=OFF', 'SDL_STATIC=ON', 'SDL_TEST_LIBRARY=OFF', 'SDL_TESTS=OFF', 'SDL_INSTALL_TESTS=OFF', 'SDL_DISABLE_INSTALL_DOCS=ON', 'SDL_FRAMEWORK=OFF', 'CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded') }
        cmake = [ordered]@{ executable=(Get-AlicornFullPath $cmake); executableSha256=(Get-AlicornFileHash $cmake); version=$cmakeVersion; generatorArguments=@($generatorArguments); toolchain=$toolchain }
        odin = [ordered]@{ executable=(Get-AlicornFullPath $Odin); executableSha256=(Get-AlicornFileHash $Odin); fileVersion=$odinVersion.FileVersion; version=$odinVersionOutput; sdkRoot=(Get-AlicornFullPath $OdinRoot); vendorSdl=$sdkSdlInventory }
        accesskit = [ordered]@{ version='0.23.1'; archiveSha256=(Get-AlicornFileHash $accessKitArchive); librarySha256=(Get-AlicornFileHash $accessKitLibrary) }
        environment = [ordered]@{ windowsSdkVersion=$env:WindowsSDKVersion; vcToolsInstallDir=$env:VCToolsInstallDir; generatorInstance=$env:CMAKE_GENERATOR_INSTANCE }
    }
    $fingerprint = Get-AlicornObjectHash $inputs
    $generationRoot = Join-Path $generationRootParent $fingerprint
    $lockPath = Join-Path $lockRoot ($fingerprint + '.lock')
    $lock = Enter-AlicornGenerationLock $lockPath
    try {
        if ([IO.Directory]::Exists($generationRoot)) {
            $validation = Test-AlicornNativeLinkGeneration -GenerationRoot $generationRoot -ExpectedFingerprint $fingerprint
            if (-not $validation.valid) { throw "Refusing to reuse corrupted immutable native-link generation '$generationRoot': $($validation.reason). Remove this generated directory and request the recipe again." }
            $existingRecipePath = Join-Path $generationRoot 'recipe.json'
            if (-not [IO.File]::Exists($existingRecipePath)) { throw "Validated generation is missing its recipe: '$existingRecipePath'." }
            return (Get-Content -LiteralPath $existingRecipePath -Raw | ConvertFrom-Json)
        }

        $stage = Join-Path $stagingRoot ($fingerprint + '-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage | Out-Null
        if (-not (Test-AlicornPathWithin $stage $outRoot)) { throw "Refusing to prepare outside Alicorn output root: '$stage'." }
        try {
            $source = Join-Path $stage 'source'
            $build = Join-Path $stage 'build'
            $prefix = Join-Path $stage 'prefix'
            $probe = Join-Path $stage 'link-probe'
            New-Item -ItemType Directory -Path $source, $prefix | Out-Null
            Invoke-AlicornNativeLogged -Executable $tarCommand.Source -Arguments @('-xf', $archive, '-C', $source, '--strip-components=1') -LogPath (Join-Path $stage 'extract.log') -Description 'Pinned SDL source extraction'
            $runtime = '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded'
            $configure = @('-S', $source, '-B', $build) + $generatorArguments + @(
                "-DCMAKE_INSTALL_PREFIX=$prefix", '-DCMAKE_BUILD_TYPE=Release', $runtime,
                '-DSDL_SHARED=OFF', '-DSDL_STATIC=ON', '-DSDL_TEST_LIBRARY=OFF', '-DSDL_TESTS=OFF',
                '-DSDL_INSTALL_TESTS=OFF', '-DSDL_DISABLE_INSTALL_DOCS=ON', '-DSDL_FRAMEWORK=OFF'
            )
            Invoke-AlicornNativeLogged -Executable $cmake -Arguments $configure -LogPath (Join-Path $stage 'configure.log') -Description 'SDL static configuration'
            Invoke-AlicornNativeLogged -Executable $cmake -Arguments @('--build', $build, '--config', 'Release', '--target', 'SDL3-static', '--parallel', '2') -LogPath (Join-Path $stage 'build.log') -Description 'SDL3 static build'
            Invoke-AlicornNativeLogged -Executable $cmake -Arguments @('--install', $build, '--config', 'Release') -LogPath (Join-Path $stage 'install.log') -Description 'SDL3 static install'

            $probeConfigure = @('-S', (Join-Path $PSScriptRoot 'sdl_link_probe'), '-B', $probe) + $generatorArguments + @('-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_PREFIX_PATH=$prefix")
            Invoke-AlicornNativeLogged -Executable $cmake -Arguments $probeConfigure -LogPath (Join-Path $stage 'link-probe.log') -Description 'SDL static link-interface probe'
            $linkRequirements = ConvertFrom-AlicornCMakeLinkInterface `
                -Directories (Get-AlicornTextList (Join-Path $probe 'sdl3-static-link-directories-Release.txt')) `
                -Options (Get-AlicornTextList (Join-Path $probe 'sdl3-static-link-options-Release.txt')) `
                -Libraries (Get-AlicornTextList (Join-Path $probe 'sdl3-static-link-libraries-Release.txt'))

            $staticLibrary = Get-ChildItem -LiteralPath $prefix -Filter 'SDL3-static.lib' -File -Recurse | Select-Object -First 1
            if (-not $staticLibrary) { throw "SDL3-static.lib was not installed under '$prefix'." }
            $sdlLicenseSource = Join-Path $source 'LICENSE.txt'
            if (-not [IO.File]::Exists($sdlLicenseSource)) { throw 'Pinned SDL source did not contain LICENSE.txt.' }

            $odinOverlay = Join-Path $stage 'odin'
            $vendorOverlay = Join-Path $odinOverlay 'vendor'
            New-Item -ItemType Directory -Path $odinOverlay, $vendorOverlay | Out-Null
            $junctions = [Collections.Generic.List[object]]::new()
            foreach ($sdkDirectory in @('base', 'core', 'shared', 'bin')) {
                $target = Join-Path $OdinRoot $sdkDirectory
                $linkPath = Join-Path $odinOverlay $sdkDirectory
                New-Item -ItemType Junction -Path $linkPath -Target $target | Out-Null
                $junctions.Add([ordered]@{ path=(Join-Path 'odin' $sdkDirectory); target=(Get-AlicornFullPath $target) })
            }
            foreach ($vendorPackage in (Get-ChildItem -LiteralPath (Join-Path $OdinRoot 'vendor') -Directory)) {
                if ($vendorPackage.Name -eq 'sdl3') { continue }
                $target = $vendorPackage.FullName
                $linkPath = Join-Path $vendorOverlay $vendorPackage.Name
                New-Item -ItemType Junction -Path $linkPath -Target $target | Out-Null
                $junctions.Add([ordered]@{ path=(Join-Path 'odin\vendor' $vendorPackage.Name); target=(Get-AlicornFullPath $target) })
            }
            $sdlPackage = Join-Path $vendorOverlay 'sdl3'
            Copy-Item -LiteralPath (Join-Path $OdinRoot 'vendor\sdl3') -Destination $sdlPackage -Recurse
            Copy-Item -LiteralPath $staticLibrary.FullName -Destination (Join-Path $sdlPackage 'SDL3.lib') -Force

            $accessKitDirectory = Join-Path $stage 'accesskit\lib'
            $licenseDirectory = Join-Path $stage 'licenses'
            New-Item -ItemType Directory -Path $accessKitDirectory, $licenseDirectory | Out-Null
            Copy-Item -LiteralPath $accessKitLibrary -Destination (Join-Path $accessKitDirectory 'accesskit.lib')
            Copy-Item -LiteralPath $accessKitLicenseApache -Destination (Join-Path $licenseDirectory 'AccessKit-LICENSE-APACHE.txt')
            Copy-Item -LiteralPath $accessKitLicenseMIT -Destination (Join-Path $licenseDirectory 'AccessKit-LICENSE-MIT.txt')
            Copy-Item -LiteralPath $sdlLicenseSource -Destination (Join-Path $licenseDirectory 'SDL-LICENSE.txt')

            $finalOverlay = Join-Path $generationRoot 'odin'
            $finalAccessKitDirectory = Join-Path $generationRoot 'accesskit\lib'
            $accessKitFlags = @((ConvertTo-AlicornMsvcPathArgument '/LIBPATH:' $finalAccessKitDirectory), 'bcrypt.lib', 'ntdll.lib', 'propsys.lib', 'runtimeobject.lib', 'uiautomationcore.lib', 'userenv.lib', 'ws2_32.lib')
            $extraLinkerFlags = (@($accessKitFlags) + @($linkRequirements.arguments)) -join ' '
            $compilerArguments = @("-extra-linker-flags:$extraLinkerFlags")
            $sdlLibraryRelative = 'odin/vendor/sdl3/SDL3.lib'
            $accessKitLibraryRelative = 'accesskit/lib/accesskit.lib'
            $sdlLicenseRelative = 'licenses/SDL-LICENSE.txt'
            $accessKitApacheRelative = 'licenses/AccessKit-LICENSE-APACHE.txt'
            $accessKitMitRelative = 'licenses/AccessKit-LICENSE-MIT.txt'
            $recipe = [ordered]@{
                schemaVersion = $script:NativeLinkSchemaVersion
                target = 'windows-x86_64-msvc'
                linkage = 'static'
                environment = [ordered]@{ ODIN_ROOT=$finalOverlay }
                odin = [ordered]@{
                    executable=(Get-AlicornFullPath $Odin)
                    compilerArguments=@($compilerArguments)
                    extraLinkerFlags=$extraLinkerFlags
                }
                linkRequirements = [ordered]@{
                    accesskit=@($accessKitFlags)
                    sdl=[ordered]@{ directories=@($linkRequirements.directories); options=@($linkRequirements.options); libraries=@($linkRequirements.libraries) }
                }
                artifacts = [ordered]@{
                    sdl=[ordered]@{ version=$script:SDLVersion; sourceUrl=$script:SDLURL; sourceSha256=$actualSDLHash; library=(Join-Path $generationRoot $sdlLibraryRelative); sha256=(Get-AlicornFileHash (Join-Path $stage $sdlLibraryRelative)); license=(Join-Path $generationRoot $sdlLicenseRelative) }
                    accesskit=[ordered]@{ version='0.23.1'; library=(Join-Path $generationRoot $accessKitLibraryRelative); sha256=(Get-AlicornFileHash (Join-Path $stage $accessKitLibraryRelative)); licenses=@((Join-Path $generationRoot $accessKitApacheRelative), (Join-Path $generationRoot $accessKitMitRelative)) }
                }
                provenance = [ordered]@{ fingerprint=$fingerprint; manifest=(Join-Path $generationRoot 'manifest.json'); odinVersion=$odinVersionOutput }
            }

            foreach ($temporary in @($source, $build, $prefix, $probe, (Join-Path $stage 'extract.log'), (Join-Path $stage 'configure.log'), (Join-Path $stage 'build.log'), (Join-Path $stage 'install.log'), (Join-Path $stage 'link-probe.log'))) {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
            }
            $artifactRecords = [Collections.Generic.List[object]]::new()
            foreach ($file in (Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName)) {
                $relative = $file.FullName.Substring($stage.Length).TrimStart('\', '/') -replace '\\', '/'
                $artifactRecords.Add([ordered]@{ path=$relative; sha256=(Get-AlicornFileHash $file.FullName) })
            }
            $manifest = [ordered]@{
                schemaVersion=$script:NativeLinkSchemaVersion
                target='windows-x86_64-msvc'
                provenance=[ordered]@{ fingerprint=$fingerprint; preparationVersion=$script:PreparationVersion }
                inputs=$inputs
                toolchain=$toolchain
                artifacts=@($artifactRecords.ToArray())
                junctions=@($junctions.ToArray())
            }
            $recipeJson = ConvertTo-Json -InputObject $recipe -Depth 40
            Set-Content -LiteralPath (Join-Path $stage 'recipe.json') -Value $recipeJson -Encoding utf8
            $artifactRecords.Add([ordered]@{ path='recipe.json'; sha256=(Get-AlicornFileHash (Join-Path $stage 'recipe.json')) })
            $manifest.artifacts = @($artifactRecords.ToArray())
            Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Value (ConvertTo-Json -InputObject $manifest -Depth 40) -Encoding utf8
            $stageValidation = Test-AlicornNativeLinkGeneration -GenerationRoot $stage -ExpectedFingerprint $fingerprint
            if (-not $stageValidation.valid) { throw "Staged native-link generation failed validation: $($stageValidation.reason)." }
            [IO.Directory]::Move($stage, $generationRoot)
        } catch {
            if (Test-Path -LiteralPath $stage) {
                if (-not (Test-AlicornPathWithin $stage $outRoot)) { throw "Refusing to remove staging path outside output root: '$stage'." }
                Remove-Item -LiteralPath $stage -Recurse -Force
            }
            throw
        }
        return (Get-Content -LiteralPath (Join-Path $generationRoot 'recipe.json') -Raw | ConvertFrom-Json)
    } finally {
        $lock.Dispose()
    }
}

Export-ModuleMember -Function New-AlicornWindowsStaticLinkRecipe, ConvertFrom-AlicornCMakeLinkInterface, Test-AlicornNativeLinkGeneration, Get-AlicornCMakeGeneratorArguments, Get-AlicornCMakeCompilerFacts
