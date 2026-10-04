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
} finally {
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}
