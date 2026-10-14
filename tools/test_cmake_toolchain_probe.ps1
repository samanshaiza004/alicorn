$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'native_link.psm1') -Force -ErrorAction Stop

if ($env:OS -ne 'Windows_NT') { throw 'The real MSVC toolchain probe integration test requires Windows.' }
$cmakeCommand = Get-Command cmake.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'out\native-link\toolchain-integration'))
$probeRoot = Join-Path $outRoot ([guid]::NewGuid().ToString('N'))
$buildDirectory = Join-Path $probeRoot 'build'
$boundary = [IO.Path]::GetFullPath((Join-Path $repoRoot 'out\native-link')).TrimEnd('\') + '\'
if (-not ([IO.Path]::GetFullPath($probeRoot)).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create toolchain integration output outside generated output: '$probeRoot'."
}

try {
    New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
    $generator = Get-AlicornCMakeDefaultGenerator $cmakeCommand.Source
    $arguments = @('-S', (Join-Path $PSScriptRoot 'cmake_toolchain_probe'), '-B', $buildDirectory) +
        (Get-AlicornCMakeGeneratorArguments $generator) + @('-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded')
    & $cmakeCommand.Source @arguments *> (Join-Path $probeRoot 'configure.log')
    if ($LASTEXITCODE -ne 0) {
        $tail = Get-Content -LiteralPath (Join-Path $probeRoot 'configure.log') -Tail 40
        throw "CMake toolchain probe configuration failed (exit $LASTEXITCODE).`n$($tail -join "`n")"
    }

    $facts = Get-AlicornCMakeCompilerFacts $buildDirectory
    if ($facts.pointerSize -ne '8' -or $facts.targetSystem -ne 'Windows' -or $facts.crt -ne 'MultiThreaded') {
        throw 'The real CMake probe returned an incompatible Windows x64/static-CRT toolchain.'
    }
    if ($facts.cCompilerId -ne 'MSVC' -or $facts.cxxCompilerId -ne 'MSVC') {
        throw 'The real CMake probe did not report MSVC for both C and C++.'
    }
    if ($generator -match '^Visual Studio' -and $facts.platform -notin @('x64', 'amd64', 'AMD64')) {
        throw "The real Visual Studio generator did not target x64 (reported '$($facts.platform)')."
    }
    Write-Host "Real CMake toolchain probe passed: $($facts.generator), target $($facts.targetSystem) $($facts.targetProcessor), pointer size $($facts.pointerSize), CRT $($facts.crt)."
} finally {
    if (Test-Path -LiteralPath $probeRoot) {
        if (-not ([IO.Path]::GetFullPath($probeRoot)).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove toolchain integration output outside generated output: '$probeRoot'."
        }
        Remove-Item -LiteralPath $probeRoot -Recurse -Force
    }
}
