param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Metadata,
    [Parameter(Mandatory)][ValidateSet('Shared', 'Static')][string]$SDLLinkage,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$SDLRuntime,
    [string]$SDLVersion,
    [Parameter(Mandatory)][string]$SDLLicense,
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$Metadata = (Resolve-Path -LiteralPath $Metadata).Path
$SDLLicense = (Resolve-Path -LiteralPath $SDLLicense).Path
if ($SDLLinkage -eq 'Shared') {
    if ([string]::IsNullOrWhiteSpace($SDLRuntime)) { throw 'Shared SDL packaging requires -SDLRuntime.' }
    $SDLRuntime = (Resolve-Path -LiteralPath $SDLRuntime).Path
}
if ([string]::IsNullOrWhiteSpace($SDLVersion)) {
    if ($SDLLinkage -eq 'Static') {
        $SDLVersion = '3.4.16'
    } else {
        $VersionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($SDLRuntime)
        if ($VersionInfo.ProductMajorPart -lt 1) { throw "Cannot determine SDL version from '$SDLRuntime'; pass -SDLVersion." }
        $SDLVersion = '{0}.{1}.{2}' -f $VersionInfo.ProductMajorPart, $VersionInfo.ProductMinorPart, $VersionInfo.ProductBuildPart
    }
}
if ($SDLVersion -notmatch '^\d+\.\d+\.\d+$') { throw "SDL version must use major.minor.patch form, got '$SDLVersion'." }

$App = Get-Content -LiteralPath $Metadata -Raw | ConvertFrom-Json
foreach ($Field in @('name', 'version', 'bundleIdentifier', 'executableName')) {
    if ([string]::IsNullOrWhiteSpace([string]$App.$Field)) { throw "Package metadata is missing '$Field'." }
}
if ($App.executableName -match '[\\/:<>"|?*]') { throw 'executableName must be a filename, not a path.' }
$FinalPackageRoot = [IO.Path]::GetFullPath($OutputDirectory)
$CreatedFinalPackageRoot = $false
if (Test-Path -LiteralPath $FinalPackageRoot) {
    if (@(Get-ChildItem -LiteralPath $FinalPackageRoot -Force).Count -ne 0) {
        throw "Refusing to overwrite non-empty package directory '$FinalPackageRoot'."
    }
} else {
    New-Item -ItemType Directory -Path $FinalPackageRoot -Force | Out-Null
    $CreatedFinalPackageRoot = $true
}
$PackageRoot = $FinalPackageRoot + '.staging-' + [guid]::NewGuid().ToString('N')
New-Item -ItemType Directory -Path $PackageRoot | Out-Null
try {

function Copy-PackageFile([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Package input does not exist: '$Source'." }
    $Parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination
}

Copy-PackageFile $Executable (Join-Path $PackageRoot ($App.executableName + '.exe'))
Copy-PackageFile $SDLLicense (Join-Path $PackageRoot 'SDL-LICENSE.txt')
if ($SDLLinkage -eq 'Shared') {
    if ((Split-Path -Leaf $SDLRuntime) -ine 'SDL3.dll') { throw 'The shared SDL runtime must be named SDL3.dll.' }
    Copy-PackageFile $SDLRuntime (Join-Path $PackageRoot 'SDL3.dll')
}

$ResourcesRoot = Join-Path $PackageRoot 'Resources'
$CopiedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($null -ne $App.icon -and -not [string]::IsNullOrWhiteSpace([string]$App.icon)) {
    $IconPath = Join-Path (Split-Path -Parent $Metadata) ([string]$App.icon)
    $IconPath = (Resolve-Path -LiteralPath $IconPath).Path
    $IconName = Split-Path -Leaf $IconPath
    if (-not $CopiedNames.Add($IconName)) { throw "Duplicate resource basename '$IconName'." }
    Copy-PackageFile $IconPath (Join-Path $ResourcesRoot $IconName)
}
foreach ($Resource in @($App.resources)) {
    $ResourcePath = Join-Path (Split-Path -Parent $Metadata) ([string]$Resource)
    $ResourcePath = (Resolve-Path -LiteralPath $ResourcePath).Path
    $ResourceName = Split-Path -Leaf $ResourcePath
    if (-not $CopiedNames.Add($ResourceName)) { throw "Duplicate resource basename '$ResourceName'." }
    Copy-PackageFile $ResourcePath (Join-Path $ResourcesRoot $ResourceName)
}

foreach ($PrivateLibrary in @($App.privateLibraries)) {
    $LibraryPath = Join-Path (Split-Path -Parent $Metadata) ([string]$PrivateLibrary)
    $LibraryPath = (Resolve-Path -LiteralPath $LibraryPath).Path
    if ((Split-Path -Extension $LibraryPath) -ine '.dll') { throw "Windows privateLibraries entries must be DLLs: '$PrivateLibrary'." }
    Copy-PackageFile $LibraryPath (Join-Path $PackageRoot (Split-Path -Leaf $LibraryPath))
}
if ($SDLLinkage -eq 'Static') {
    $UnexpectedHostLibraries = @(Get-ChildItem -LiteralPath $PackageRoot -File -Filter '*.dll' |
        Where-Object { $_.Name -ieq 'SDL3.dll' -or $_.Name -match '^(?i:alicorn).*\.dll$' })
    if ($UnexpectedHostLibraries.Count -gt 0) {
        throw "Static packages must not include Alicorn/SDL host DLLs: $($UnexpectedHostLibraries.Name -join ', ')."
    }
}

function Convert-RvaToOffset([uint32]$Rva, [object[]]$Sections, [long]$FileLength) {
    foreach ($Section in $Sections) {
        $Span = [Math]::Max([long]$Section.VirtualSize, [long]$Section.RawSize)
        if ([long]$Rva -ge [long]$Section.VirtualAddress -and [long]$Rva -lt ([long]$Section.VirtualAddress + $Span)) {
            $Offset = [long]$Section.RawPointer + ([long]$Rva - [long]$Section.VirtualAddress)
            if ($Offset -lt 0 -or $Offset -ge $FileLength) { throw 'PE import RVA points outside the file.' }
            return $Offset
        }
    }
    throw ('PE import RVA 0x{0:X} is not mapped by a section.' -f $Rva)
}

function Get-PeImports([string]$Path) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    $Stream = [IO.MemoryStream]::new($Bytes, $false)
    $Reader = [IO.BinaryReader]::new($Stream)
    try {
        if ($Bytes.Length -lt 128 -or $Reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE image: '$Path'." }
        $Stream.Position = 0x3c
        $PeOffset = $Reader.ReadUInt32()
        if ($PeOffset + 24 -gt $Bytes.Length) { throw "Invalid PE header in '$Path'." }
        $Stream.Position = $PeOffset
        if ($Reader.ReadUInt32() -ne 0x00004550) { throw "Invalid PE signature in '$Path'." }
        $Stream.Position = $PeOffset + 6
        $SectionCount = $Reader.ReadUInt16()
        $Stream.Position = $PeOffset + 20
        $OptionalSize = $Reader.ReadUInt16()
        $OptionalStart = $PeOffset + 24
        $Stream.Position = $OptionalStart
        $Magic = $Reader.ReadUInt16()
        if ($Magic -eq 0x20b) { $DirectoryOffset = 112 }
        elseif ($Magic -eq 0x10b) { $DirectoryOffset = 96 }
        else { throw "Unsupported PE optional-header format in '$Path'." }
        if ($OptionalSize -lt ($DirectoryOffset + 16)) { throw "PE import directory is missing in '$Path'." }
        $Stream.Position = $OptionalStart + $DirectoryOffset + 8
        $ImportRva = $Reader.ReadUInt32()
        if ($ImportRva -eq 0) { return @() }

        $Stream.Position = $OptionalStart + $OptionalSize
        $Sections = @()
        for ($Index = 0; $Index -lt $SectionCount; $Index++) {
            $Stream.Position += 8
            $VirtualSize = $Reader.ReadUInt32()
            $VirtualAddress = $Reader.ReadUInt32()
            $RawSize = $Reader.ReadUInt32()
            $RawPointer = $Reader.ReadUInt32()
            $Stream.Position += 16
            $Sections += [pscustomobject]@{ VirtualSize=$VirtualSize; VirtualAddress=$VirtualAddress; RawSize=$RawSize; RawPointer=$RawPointer }
        }
        $DescriptorOffset = Convert-RvaToOffset $ImportRva $Sections $Bytes.Length
        $Imports = [Collections.Generic.List[string]]::new()
        for ($Index = 0; $Index -lt 4096; $Index++) {
            $Stream.Position = $DescriptorOffset + 20 * $Index
            if ($Stream.Position + 20 -gt $Stream.Length) { throw "Truncated PE import table in '$Path'." }
            $OriginalThunk = $Reader.ReadUInt32()
            $Reader.ReadUInt32() | Out-Null
            $Reader.ReadUInt32() | Out-Null
            $NameRva = $Reader.ReadUInt32()
            $Reader.ReadUInt32() | Out-Null
            if (($OriginalThunk -bor $NameRva) -eq 0) { break }
            $NameOffset = Convert-RvaToOffset $NameRva $Sections $Bytes.Length
            $Stream.Position = $NameOffset
            $NameBytes = [Collections.Generic.List[byte]]::new()
            while ($Stream.Position -lt $Stream.Length) {
                $Byte = $Reader.ReadByte()
                if ($Byte -eq 0) { break }
                $NameBytes.Add($Byte)
            }
            $Imports.Add([Text.Encoding]::ASCII.GetString($NameBytes.ToArray()))
        }
        if ($Imports.Count -eq 0 -and $Index -ge 4096) { throw "Unterminated PE import table in '$Path'." }
        return $Imports.ToArray()
    } finally {
        $Reader.Dispose()
        $Stream.Dispose()
    }
}

function Get-PeArchitecture([string]$Path) {
    $Bytes = [IO.File]::ReadAllBytes($Path)
    $Stream = [IO.MemoryStream]::new($Bytes, $false)
    $Reader = [IO.BinaryReader]::new($Stream)
    try {
        if ($Bytes.Length -lt 64 -or $Reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE image: '$Path'." }
        $Stream.Position = 0x3c
        $PeOffset = $Reader.ReadUInt32()
        if ($PeOffset + 6 -gt $Bytes.Length) { throw "Invalid PE header in '$Path'." }
        $Stream.Position = $PeOffset + 4
        switch ($Reader.ReadUInt16()) {
            0x8664 { return 'x86_64' }
            0xAA64 { return 'arm64' }
            0x014c { return 'x86' }
            default { throw "Unsupported PE machine in '$Path'." }
        }
    } finally {
        $Reader.Dispose()
        $Stream.Dispose()
    }
}

function Test-IsSystemDll([string]$Name, [string]$Architecture) {
    if ($Name -match '^(api-ms-win-|ext-ms-win-)') { return $true }
    $SystemDirectories = @((Join-Path $env:SystemRoot 'System32'))
    if ($Architecture -eq 'x86') { $SystemDirectories += (Join-Path $env:SystemRoot 'SysWOW64') }
    foreach ($Directory in $SystemDirectories) {
        if (Test-Path -LiteralPath (Join-Path $Directory $Name) -PathType Leaf) { return $true }
    }
    return $false
}

$SystemImports = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$PrivateImports = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$SeenImages = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$Pending = [Collections.Generic.Queue[string]]::new()
$ExecutablePath = Join-Path $PackageRoot ($App.executableName + '.exe')
$PackageArchitecture = Get-PeArchitecture $ExecutablePath
$Pending.Enqueue($ExecutablePath)
while ($Pending.Count -gt 0) {
    $Image = $Pending.Dequeue()
    if (-not $SeenImages.Add($Image)) { continue }
    $ImageArchitecture = Get-PeArchitecture $Image
    if ($ImageArchitecture -ne $PackageArchitecture) {
        throw "PE architecture mismatch: '$([IO.Path]::GetFileName($Image))' is $ImageArchitecture, package is $PackageArchitecture."
    }
    foreach ($Import in (Get-PeImports $Image)) {
        if ($Import -match '[/\\:]') { throw "Invalid PE import name '$Import' in '$([IO.Path]::GetFileName($Image))'." }
        if ($SDLLinkage -eq 'Static' -and ($Import -ieq 'SDL3.dll' -or $Import -match '^(?i:alicorn).*\.dll$')) {
            throw "Static package unexpectedly imports '$Import' (from '$([IO.Path]::GetFileName($Image))')."
        }
        if (Test-IsSystemDll $Import $PackageArchitecture) {
            $SystemImports.Add($Import) | Out-Null
            continue
        }
        $BundledPath = Join-Path $PackageRoot $Import
        if (-not (Test-Path -LiteralPath $BundledPath -PathType Leaf)) {
            throw "Unresolved non-system import '$Import' required by '$([IO.Path]::GetFileName($Image))'. Bundle the private DLL or link it statically."
        }
        $PrivateImports.Add($Import) | Out-Null
        $Pending.Enqueue($BundledPath)
    }
}
if ($SDLLinkage -eq 'Shared' -and -not $PrivateImports.Contains('SDL3.dll')) {
    throw 'Shared SDL package does not resolve SDL3.dll as a bundled dependency.'
}

$PrivateDependencyManifest = foreach ($Library in (Get-ChildItem -LiteralPath $PackageRoot -File -Filter '*.dll' | Sort-Object Name)) {
    [ordered]@{ name=$Library.Name; sha256=(Get-FileHash -LiteralPath $Library.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$ResourceManifest = foreach ($Resource in (Get-ChildItem -LiteralPath $ResourcesRoot -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    [ordered]@{ name=('Resources/' + $Resource.Name); sha256=(Get-FileHash -LiteralPath $Resource.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$AlicornRevision = (& git -C $RepoRoot rev-parse HEAD).Trim()
$Manifest = [ordered]@{
    schema = 1
    application = [ordered]@{
        name = [string]$App.name
        version = [string]$App.version
        bundleIdentifier = [string]$App.bundleIdentifier
        executable = ($App.executableName + '.exe')
        sha256 = (Get-FileHash -LiteralPath (Join-Path $PackageRoot ($App.executableName + '.exe')) -Algorithm SHA256).Hash.ToLowerInvariant()
        resources = @($ResourceManifest)
    }
    target = ('windows-' + $PackageArchitecture)
    host = [ordered]@{
        alicornRevision = $AlicornRevision
        sdlVersion = $SDLVersion
        sdlLinkage = $SDLLinkage.ToLowerInvariant()
        sdlSource = $(if ($SDLLinkage -eq 'Static') { 'https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz' } else { $null })
        sdlSourceSha256 = $(if ($SDLLinkage -eq 'Static') { '7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68' } else { $null })
        license = [ordered]@{ path='SDL-LICENSE.txt'; sha256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot 'SDL-LICENSE.txt') -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    dependencies = [ordered]@{
        system = @($SystemImports | Sort-Object)
        bundled = @($PrivateDependencyManifest)
    }
}
$ManifestPath = Join-Path $PackageRoot 'alicorn-package.json'
$Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
Write-Host "System imports: $($SystemImports.Count); bundled private DLLs: $($PrivateImports.Count)"

if ($SmokeTest) {
    $EmptyDirectory = Join-Path ([IO.Path]::GetTempPath()) ('alicorn-package-smoke-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $EmptyDirectory | Out-Null
    $Process = $null
    try {
        $Process = Start-Process -FilePath (Join-Path $PackageRoot ($App.executableName + '.exe')) `
            -ArgumentList '--idle-validation-seconds=2' -WorkingDirectory $EmptyDirectory -PassThru
        if (-not $Process.WaitForExit(30000)) {
            $Process.Kill()
            throw 'Packaged application did not exit within 30 seconds from an empty working directory.'
        }
        if ($Process.ExitCode -ne 0) { throw "Packaged application smoke test exited with code $($Process.ExitCode)." }
        Write-Host 'Empty-directory launch smoke passed.'
    } finally {
        if ($null -ne $Process -and -not $Process.HasExited) { $Process.Kill() }
        Remove-Item -LiteralPath $EmptyDirectory -Force
    }
}

if (Test-Path -LiteralPath $FinalPackageRoot) {
    Remove-Item -LiteralPath $FinalPackageRoot -Force
}
Move-Item -LiteralPath $PackageRoot -Destination $FinalPackageRoot
Write-Host "Verified package: $FinalPackageRoot"
} catch {
    if (Test-Path -LiteralPath $PackageRoot) { Remove-Item -LiteralPath $PackageRoot -Recurse -Force }
    if ($CreatedFinalPackageRoot -and (Test-Path -LiteralPath $FinalPackageRoot)) {
        Remove-Item -LiteralPath $FinalPackageRoot -Force
    }
    throw
}
