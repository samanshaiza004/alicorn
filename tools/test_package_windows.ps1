param([string]$Odin)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$OutRoot = Join-Path $RepoRoot 'out\native-package'
$Executable = Join-Path $OutRoot 'AlicornHello.exe'
$SDKRoot = Split-Path -Parent $Odin
$SDLRuntime = Join-Path $SDKRoot 'vendor\sdl3\SDL3.dll'
$SDLLicense = Join-Path $SDKRoot 'vendor\sdl3\LICENSE.txt'
foreach ($Path in @($Executable, $SDLRuntime, $SDLLicense)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required packaging regression-test input is missing: '$Path'." }
}

$TestRoot = Join-Path $OutRoot ('negative-audit-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TestRoot | Out-Null
$ResolvedOut = [IO.Path]::GetFullPath($OutRoot) + [IO.Path]::DirectorySeparatorChar
$ResolvedTestRoot = [IO.Path]::GetFullPath($TestRoot)
if (-not $ResolvedTestRoot.StartsWith($ResolvedOut, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use test fixture outside native-package output: '$ResolvedTestRoot'."
}

function Set-TestUInt16([byte[]]$Bytes, [int]$Offset, [uint16]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value), 0, $Bytes, $Offset, 2)
}

function Set-TestUInt32([byte[]]$Bytes, [int]$Offset, [uint32]$Value) {
    [Array]::Copy([BitConverter]::GetBytes($Value), 0, $Bytes, $Offset, 4)
}

function New-TestPeWithImports([string]$Path, [string[]]$ImportNames) {
    # A minimal PE32+ image is enough for package_app.ps1's architecture and
    # import readers; no loader or linker is involved in this negative audit.
    [byte[]]$Bytes = New-Object byte[] 1024
    $Bytes[0] = 0x4d; $Bytes[1] = 0x5a
    Set-TestUInt32 $Bytes 0x3c 0x80
    Set-TestUInt32 $Bytes 0x80 0x00004550
    Set-TestUInt16 $Bytes 0x84 0x8664
    Set-TestUInt16 $Bytes 0x86 1
    Set-TestUInt16 $Bytes 0x94 0x00f0

    $Optional = 0x98
    Set-TestUInt16 $Bytes $Optional 0x020b
    Set-TestUInt32 $Bytes ($Optional + 108) 16
    Set-TestUInt32 $Bytes ($Optional + 120) 0x1000
    Set-TestUInt32 $Bytes ($Optional + 124) 40

    $Section = $Optional + 0x00f0
    [byte[]]$SectionName = [Text.Encoding]::ASCII.GetBytes('.rdata')
    [Array]::Copy($SectionName, 0, $Bytes, $Section, $SectionName.Length)
    Set-TestUInt32 $Bytes ($Section + 8) 0x200
    Set-TestUInt32 $Bytes ($Section + 12) 0x1000
    Set-TestUInt32 $Bytes ($Section + 16) 0x200
    Set-TestUInt32 $Bytes ($Section + 20) 0x200

    for ($Index = 0; $Index -lt $ImportNames.Count; $Index++) {
        $Descriptor = 0x200 + 20 * $Index
        $NameRva = 0x1060 + 0x40 * $Index
        $NameOffset = 0x260 + 0x40 * $Index
        Set-TestUInt32 $Bytes ($Descriptor + 12) $NameRva
        [byte[]]$ImportBytes = [Text.Encoding]::ASCII.GetBytes($ImportNames[$Index] + [char]0)
        [Array]::Copy($ImportBytes, 0, $Bytes, $NameOffset, $ImportBytes.Length)
    }
    [IO.File]::WriteAllBytes($Path, $Bytes)
}

try {
    Copy-Item -LiteralPath $SDLRuntime -Destination (Join-Path $TestRoot 'SDL3.dll')
    $Metadata = Get-Content -LiteralPath (Join-Path $RepoRoot 'examples\01_hello\package.json') -Raw | ConvertFrom-Json
    $Metadata.privateLibraries = @('SDL3.dll')
    $MetadataPath = Join-Path $TestRoot 'package.json'
    $Metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $MetadataPath -Encoding utf8

    $Arguments = @{
        Executable = $Executable
        Metadata = $MetadataPath
        SDLLinkage = 'Static'
        OutputDirectory = (Join-Path $TestRoot 'package')
        SDLLicense = $SDLLicense
    }
    $Rejected = $false
    try {
        & (Join-Path $PSScriptRoot 'package_app.ps1') @Arguments
    } catch {
        if ($_.Exception.Message -match 'Static packages must not include Alicorn/SDL host DLLs') {
            $Rejected = $true
        } else {
            throw
        }
    }
    if (-not $Rejected) { throw 'The static package auditor accepted an unexpected SDL3.dll.' }
    Write-Host 'Negative audit regression passed: static mode rejects a bundled SDL3.dll.'

    $FakeSystemRoot = Join-Path $TestRoot 'synthetic-system'
    $FakeSystem32 = Join-Path $FakeSystemRoot 'System32'
    New-Item -ItemType Directory -Path $FakeSystem32 -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $FakeSystem32 'VCRUNTIME140.dll'), [byte[]]@(0x4d, 0x5a))
    $VCRuntimeExecutable = Join-Path $TestRoot 'imports-vcruntime.exe'
    New-TestPeWithImports $VCRuntimeExecutable @('VCRUNTIME140.dll', 'AlicornAuditMissing.dll')
    $RuntimeMetadataPath = Join-Path $TestRoot 'vcruntime-package.json'
    $RuntimeMetadata = Get-Content -LiteralPath (Join-Path $RepoRoot 'examples\01_hello\package.json') -Raw | ConvertFrom-Json
    $RuntimeMetadata.privateLibraries = @()
    $RuntimeMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RuntimeMetadataPath -Encoding utf8

    $OriginalSystemRoot = $env:SystemRoot
    try {
        $env:SystemRoot = $FakeSystemRoot
        $Rejected = $false
        try {
            $RuntimeArguments = @{
                Executable = $VCRuntimeExecutable
                Metadata = $RuntimeMetadataPath
                SDLLinkage = 'Static'
                OutputDirectory = (Join-Path $TestRoot 'vcruntime-package')
                SDLLicense = $SDLLicense
            }
            & (Join-Path $PSScriptRoot 'package_app.ps1') @RuntimeArguments
        } catch {
            if ($_.Exception.Message -match "Unresolved non-system import 'VCRUNTIME140\.dll'") {
                $Rejected = $true
            } else {
                throw
            }
        }
        if (-not $Rejected) {
            throw 'The package auditor treated VCRUNTIME140.dll as OS-owned because it existed in synthetic System32.'
        }

        $DeclaredRuntimeExecutable = Join-Path $TestRoot 'imports-declared-vcruntime.exe'
        New-TestPeWithImports $DeclaredRuntimeExecutable @('VCRUNTIME140.dll')
        $RuntimeMetadata.executableName = 'VCRuntimeDeclaredFixture'
        $RuntimeMetadata | Add-Member -NotePropertyName runtimePrerequisites -NotePropertyValue @('VCRUNTIME140.dll') -Force
        $RuntimeMetadataPath = Join-Path $TestRoot 'declared-vcruntime-package.json'
        $RuntimeMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RuntimeMetadataPath -Encoding utf8
        $DeclaredRuntimeOutput = Join-Path $TestRoot 'declared-vcruntime-package'
        & (Join-Path $PSScriptRoot 'package_app.ps1') @{
            Executable = $DeclaredRuntimeExecutable
            Metadata = $RuntimeMetadataPath
            SDLLinkage = 'Static'
            OutputDirectory = $DeclaredRuntimeOutput
            SDLLicense = $SDLLicense
        }
        $Manifest = Get-Content -LiteralPath (Join-Path $DeclaredRuntimeOutput 'alicorn-package.json') -Raw | ConvertFrom-Json
        if (@($Manifest.dependencies.runtimePrerequisites) -notcontains 'VCRUNTIME140.dll') {
            throw 'The package manifest omitted its explicitly declared VCRUNTIME140.dll prerequisite.'
        }
    } finally {
        if ($null -eq $OriginalSystemRoot) {
            Remove-Item Env:SystemRoot -ErrorAction SilentlyContinue
        } else {
            $env:SystemRoot = $OriginalSystemRoot
        }
    }
    Write-Host 'Negative audit regression passed: synthetic System32 presence does not classify VCRUNTIME140.dll as an OS dependency.'
} finally {
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}
