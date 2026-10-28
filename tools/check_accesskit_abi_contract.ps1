param(
    [string]$Compiler = 'cl'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
Initialize-AlicornMsvcEnvironment
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$HeaderDir = Join-Path $RepoRoot '.deps\accesskit\accesskit-c-0.23.1\include'
$Source = Join-Path $RepoRoot 'tests\accesskit_abi_contract\accesskit_abi_contract.c'

$CompilerCommand = Get-Command $Compiler -ErrorAction SilentlyContinue
$CompilerPath = if ($CompilerCommand) { $CompilerCommand.Source } else { $null }
if (-not $CompilerPath -and $env:VCToolsInstallDir) {
    $Candidate = Join-Path $env:VCToolsInstallDir 'bin\Hostx64\x64\cl.exe'
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) { $CompilerPath = $Candidate }
}
if (-not $CompilerPath) {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $VsWhere -PathType Leaf) {
        $Install = & $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -eq 0 -and $Install) {
            $ToolsRoot = Join-Path $Install 'VC\Tools\MSVC'
            $Toolset = Get-ChildItem -LiteralPath $ToolsRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
                Select-Object -First 1
            if ($Toolset) {
                $Candidate = Join-Path $Toolset.FullName 'bin\Hostx64\x64\cl.exe'
                if (Test-Path -LiteralPath $Candidate -PathType Leaf) { $CompilerPath = $Candidate }
            }
        }
    }
}
if (-not $CompilerPath) {
    throw "AccessKit ABI contract: MSVC C compiler not found. Run from a Visual Studio Developer PowerShell, install the Visual C++ build tools, or pass -Compiler with the cl.exe path."
}

if (-not (Test-Path -LiteralPath (Join-Path $HeaderDir 'accesskit.h') -PathType Leaf)) {
    throw "AccessKit ABI contract: pinned header not found: $(Join-Path $HeaderDir 'accesskit.h'). Run the repository AccessKit dependency bootstrap first; this checker does not download dependencies."
}

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("alicorn-accesskit-abi-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempDir | Out-Null
try {
    $Executable = Join-Path $TempDir 'accesskit_abi_contract.exe'
    $CompilerArgs = @(
        '/nologo',
        '/std:c11',
        '/W4',
        '/WX',
        "/I$HeaderDir",
        $Source,
        "/Fe:$Executable"
    )
    & $CompilerPath @CompilerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "AccessKit ABI contract: MSVC compile failed with exit code $LASTEXITCODE."
    }

    & $Executable
    if ($LASTEXITCODE -ne 0) {
        throw "AccessKit ABI contract: probe failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
