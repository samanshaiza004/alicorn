param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Metadata,
    [Parameter(Mandatory)][ValidateSet('Shared', 'Static')][string]$SDLLinkage,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$SDLRuntime,
    [string]$SDLVersion,
    [Parameter(Mandatory)][string]$SDLLicense,
    [string]$AccessKitLicenseApache,
    [string]$AccessKitLicenseMIT,
    [string]$AccessKitLicenseChromium,
    [string]$AccessKitAuthors,
    [string]$AccessKitBindingLicense,
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$Metadata = (Resolve-Path -LiteralPath $Metadata).Path
$SDLLicense = (Resolve-Path -LiteralPath $SDLLicense).Path
if ([string]::IsNullOrWhiteSpace($AccessKitLicenseApache) -ne [string]::IsNullOrWhiteSpace($AccessKitLicenseMIT)) {
    throw 'AccessKit distribution requires both -AccessKitLicenseApache and -AccessKitLicenseMIT.'
}
if (-not [string]::IsNullOrWhiteSpace($AccessKitLicenseApache)) {
    $AccessKitLicenseApache = (Resolve-Path -LiteralPath $AccessKitLicenseApache).Path
    $AccessKitLicenseMIT = (Resolve-Path -LiteralPath $AccessKitLicenseMIT).Path
}
$AccessKitNotices = [ordered]@{}
foreach ($Notice in @(
    @{ Source=$AccessKitLicenseChromium; Name='AccessKit-LICENSE.chromium.txt' },
    @{ Source=$AccessKitAuthors; Name='AccessKit-AUTHORS.txt' },
    @{ Source=$AccessKitBindingLicense; Name='odin-accesskit-LICENSE.txt' }
)) {
    if ([string]::IsNullOrWhiteSpace($Notice.Source)) { continue }
    if ([string]::IsNullOrWhiteSpace($AccessKitLicenseApache)) { throw 'AccessKit notices require the Apache and MIT license inputs.' }
    $AccessKitNotices[$Notice.Name] = (Resolve-Path -LiteralPath $Notice.Source).Path
}
if ($SDLLinkage -eq 'Shared') {
    if ([string]::IsNullOrWhiteSpace($SDLRuntime)) { throw 'Shared SDL packaging requires -SDLRuntime.' }
    $SDLRuntime = (Resolve-Path -LiteralPath $SDLRuntime).Path
}
if ([string]::IsNullOrWhiteSpace($SDLVersion)) {
    if ($SDLLinkage -eq 'Static') {
        $SDLVersion = '3.4.18'
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

# This is a conservative Windows 10+ inbox DLL list for the native host's
# supported OS dependencies. Builder filesystem contents are not evidence that
# an imported DLL is available on a target machine. Add non-inbox imports to
# metadata.runtimePrerequisites only when the installer explicitly requires
# the user to install them; otherwise bundle them in privateLibraries.
$WindowsInboxDlls = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
    'advapi32.dll', 'avrt.dll', 'bcrypt.dll', 'bcryptprimitives.dll', 'cfgmgr32.dll',
    'combase.dll', 'comctl32.dll', 'comdlg32.dll', 'crypt32.dll', 'd2d1.dll',
    'd3d12.dll', 'd3dcompiler_47.dll', 'dwmapi.dll', 'dwrite.dll', 'dxgi.dll',
    'dxguid.dll', 'gdi32.dll', 'gdi32full.dll', 'hid.dll', 'imm32.dll',
    'iphlpapi.dll', 'kernel32.dll', 'kernelbase.dll', 'msvcrt.dll', 'mswsock.dll',
    'netapi32.dll', 'ntdll.dll', 'ole32.dll', 'oleaut32.dll', 'opengl32.dll',
    'powrprof.dll', 'propsys.dll', 'rpcrt4.dll', 'sechost.dll', 'secur32.dll',
    'setupapi.dll', 'shell32.dll', 'shcore.dll', 'shlwapi.dll', 'user32.dll',
    'uiautomationcore.dll', 'userenv.dll', 'uxtheme.dll', 'version.dll', 'windowscodecs.dll', 'winhttp.dll',
    'wininet.dll', 'winmm.dll', 'winspool.drv', 'wintrust.dll', 'ws2_32.dll',
    'wtsapi32.dll', 'xinput1_4.dll', 'xinput9_1_0.dll'
) | ForEach-Object { [void]$WindowsInboxDlls.Add($_) }

function Test-IsSystemDll([string]$Name) {
    if ($Name -match '^(api-ms-win-|ext-ms-win-)') { return $true }
    return $WindowsInboxDlls.Contains($Name)
}

$DeclaredRuntimePrerequisites = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($Prerequisite in @($App.runtimePrerequisites)) {
    if ($null -eq $Prerequisite) { continue }
    $Name = [string]$Prerequisite
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\\/:]' -or $Name -match '[<>"|?*]') {
        throw "runtimePrerequisites entries must be DLL basenames, got '$Name'."
    }
    if (Test-IsSystemDll $Name) { throw "Windows inbox dependency '$Name' must not be listed in runtimePrerequisites." }
    if (-not $DeclaredRuntimePrerequisites.Add($Name)) { throw "Duplicate runtimePrerequisites entry '$Name'." }
}

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
Copy-PackageFile (Join-Path $RepoRoot 'assets/icons/reicon/LICENSE') (Join-Path $PackageRoot 'Reicon-LICENSE.txt')
Copy-PackageFile (Join-Path $RepoRoot 'third_party/windows_caption/LICENSE') (Join-Path $PackageRoot 'Windows-Caption-LICENSE.txt')
if (-not [string]::IsNullOrWhiteSpace($AccessKitLicenseApache)) {
    Copy-PackageFile $AccessKitLicenseApache (Join-Path $PackageRoot 'AccessKit-LICENSE-APACHE.txt')
    Copy-PackageFile $AccessKitLicenseMIT (Join-Path $PackageRoot 'AccessKit-LICENSE-MIT.txt')
    foreach ($Name in $AccessKitNotices.Keys) { Copy-PackageFile $AccessKitNotices[$Name] (Join-Path $PackageRoot $Name) }
}
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

$SystemImports = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$RuntimePrerequisiteImports = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
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
        if (Test-IsSystemDll $Import) {
            $SystemImports.Add($Import) | Out-Null
            continue
        }
        $BundledPath = Join-Path $PackageRoot $Import
        if (-not (Test-Path -LiteralPath $BundledPath -PathType Leaf)) {
            if ($DeclaredRuntimePrerequisites.Contains($Import)) {
                $RuntimePrerequisiteImports.Add($Import) | Out-Null
                continue
            }
            throw "Unresolved non-system import '$Import' required by '$([IO.Path]::GetFileName($Image))'. Bundle it in privateLibraries, declare it in runtimePrerequisites, or link it statically."
        }
        $PrivateImports.Add($Import) | Out-Null
        $Pending.Enqueue($BundledPath)
    }
}
foreach ($Prerequisite in $DeclaredRuntimePrerequisites) {
    if (-not $RuntimePrerequisiteImports.Contains($Prerequisite)) {
        throw "Declared runtime prerequisite '$Prerequisite' is not imported by the application or its bundled DLLs."
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
        sdlSource = $(if ($SDLLinkage -eq 'Static') { 'https://github.com/libsdl-org/SDL/releases/download/release-3.4.18/SDL3-3.4.18.tar.gz' } else { $null })
        sdlSourceSha256 = $(if ($SDLLinkage -eq 'Static') { '9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3' } else { $null })
        license = [ordered]@{ path='SDL-LICENSE.txt'; sha256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot 'SDL-LICENSE.txt') -Algorithm SHA256).Hash.ToLowerInvariant() }
        reiconIcons = [ordered]@{
            weight='filled'
            sourceRevision=(Get-Content -LiteralPath (Join-Path $RepoRoot 'assets/icons/reicon/sources.json') -Raw | ConvertFrom-Json).revision
            license=[ordered]@{ path='Reicon-LICENSE.txt'; sha256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot 'Reicon-LICENSE.txt') -Algorithm SHA256).Hash.ToLowerInvariant() }
        }
        accesskit = $(if (-not [string]::IsNullOrWhiteSpace($AccessKitLicenseApache)) {
            [ordered]@{
                version='0.23.1'
                licenses=@(
                    [ordered]@{ path='AccessKit-LICENSE-APACHE.txt'; sha256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot 'AccessKit-LICENSE-APACHE.txt') -Algorithm SHA256).Hash.ToLowerInvariant() },
                    [ordered]@{ path='AccessKit-LICENSE-MIT.txt'; sha256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot 'AccessKit-LICENSE-MIT.txt') -Algorithm SHA256).Hash.ToLowerInvariant() }
                )
                notices=@(foreach ($Name in $AccessKitNotices.Keys) {
                    [ordered]@{ path=$Name; sha256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot $Name) -Algorithm SHA256).Hash.ToLowerInvariant() }
                })
            }
        } else { $null })
    }
    dependencies = [ordered]@{
        system = @($SystemImports | Sort-Object)
        runtimePrerequisites = @($RuntimePrerequisiteImports | Sort-Object)
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
