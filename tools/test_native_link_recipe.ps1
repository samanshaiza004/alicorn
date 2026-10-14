$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'native_link.psm1') -Force -ErrorAction Stop

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -cne $Actual) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
    try { & $Action }
    catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw "$Message Unexpected error: $($_.Exception.Message)"
    }
    throw "$Message Expected the operation to fail."
}

$link = ConvertFrom-AlicornCMakeLinkInterface `
    -Directories @('C:\Alicorn Native SDK\SDL\lib', 'C:\Alicorn Native SDK\SDL\lib') `
    -Options @('/NODEFAULTLIB:LIBCMT') `
    -Libraries @('bcrypt', 'bcrypt', '$<LINK_ONLY:ws2_32>', 'SDL3::SDL3-static')
Assert-Equal '/LIBPATH:"C:\Alicorn Native SDK\SDL\lib"' $link.directories[0] 'Paths with spaces must remain one quoted linker input.'
Assert-Equal $link.directories[0] $link.directories[1] 'Repeated search paths must be preserved in source order.'
Assert-Equal '/NODEFAULTLIB:LIBCMT' $link.options[0] 'MSVC linker options must remain options.'
Assert-Equal '/DEFAULTLIB:bcrypt.lib' $link.libraries[0] 'CMake library names must map to MSVC default libraries.'
Assert-Equal '/DEFAULTLIB:bcrypt.lib' $link.libraries[1] 'Repeated libraries must not be deduplicated.'
Assert-Equal '/DEFAULTLIB:ws2_32.lib' $link.libraries[2] 'LINK_ONLY entries must be unwrapped.'
Assert-Throws { ConvertFrom-AlicornCMakeLinkInterface -Libraries @('Unknown::Target') } 'Unresolved SDL CMake target' 'Unknown imported targets must fail.'
Assert-Throws { ConvertFrom-AlicornCMakeLinkInterface -Options @('$<$<CONFIG:Debug>:/DEBUG>') } 'generator expression' 'Unresolved generator expressions must fail.'
Assert-Throws { ConvertFrom-AlicornCMakeLinkInterface -Libraries @('C:\missing\library.lib') } 'missing library' 'Missing absolute link inputs must fail.'

$oldGeneratorPlatform = $env:CMAKE_GENERATOR_PLATFORM
try {
    $env:CMAKE_GENERATOR_PLATFORM = 'Win32'
    Assert-Throws { Get-AlicornCMakeGeneratorArguments 'Visual Studio 17 2022' } 'supports the x64 target' 'A 32-bit Visual Studio target must fail before SDL configuration.'
} finally {
    if ($null -eq $oldGeneratorPlatform) { Remove-Item Env:CMAKE_GENERATOR_PLATFORM -ErrorAction SilentlyContinue }
    else { $env:CMAKE_GENERATOR_PLATFORM = $oldGeneratorPlatform }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outRoot = Join-Path $repoRoot 'out\native-link\staging'
$toolchainFixtureRoot = Join-Path $outRoot ('toolchain-fixture-' + [guid]::NewGuid().ToString('N'))
$fixtureBoundary = [IO.Path]::GetFullPath((Join-Path $repoRoot 'out\native-link')).TrimEnd('\') + '\'
if (-not ([IO.Path]::GetFullPath($toolchainFixtureRoot)).StartsWith($fixtureBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create toolchain fixture outside generated output: '$toolchainFixtureRoot'."
}
try {
    New-Item -ItemType Directory -Path $toolchainFixtureRoot -Force | Out-Null
    foreach ($name in @('cl.exe', 'link.exe')) {
        [IO.File]::WriteAllBytes((Join-Path $toolchainFixtureRoot $name), [byte[]]@(0, 1, 2, 3))
    }
    $cachePath = Join-Path $toolchainFixtureRoot 'CMakeCache.txt'
    $compiler = Join-Path $toolchainFixtureRoot 'cl.exe'
    $linker = Join-Path $toolchainFixtureRoot 'link.exe'
    $cacheLines = @(
        'CMAKE_GENERATOR:INTERNAL=Ninja',
        "CMAKE_C_COMPILER:FILEPATH=$compiler",
        "CMAKE_CXX_COMPILER:FILEPATH=$compiler",
        "CMAKE_LINKER:FILEPATH=$linker"
    )
    Set-Content -LiteralPath $cachePath -Value $cacheLines
    $reportPath = Join-Path $toolchainFixtureRoot 'alicorn-toolchain-report.json'
    $report = [ordered]@{
        schemaVersion=1; pointerSize=4; cCompiler=$compiler; cCompilerId='MSVC'; cCompilerVersion='19.40'
        cxxCompiler=$compiler; cxxCompilerId='MSVC'; cxxCompilerVersion='19.40'; targetSystem='Windows'
        targetProcessor='AMD64'; generator='Ninja'; generatorPlatform=''; visualStudioPlatform=''; crt='MultiThreaded'
    }
    Set-Content -LiteralPath $reportPath -Value (ConvertTo-Json -InputObject $report -Compress)
    Assert-Throws { Get-AlicornCMakeCompilerFacts $toolchainFixtureRoot } '64-bit Windows' 'A non-x64 compiler must fail validation.'
    $report.pointerSize = 8
    $report.crt = 'MultiThreadedDLL'
    Set-Content -LiteralPath $reportPath -Value (ConvertTo-Json -InputObject $report -Compress)
    Assert-Throws { Get-AlicornCMakeCompilerFacts $toolchainFixtureRoot } 'static MSVC CRT' 'A dynamic-CRT toolchain must fail validation.'
    $report.crt = 'MultiThreaded'
    $report.targetSystem = 'Linux'
    Set-Content -LiteralPath $reportPath -Value (ConvertTo-Json -InputObject $report -Compress)
    Assert-Throws { Get-AlicornCMakeCompilerFacts $toolchainFixtureRoot } 'Windows target' 'A non-Windows target must fail validation.'
    $report.targetSystem = 'Windows'
    Set-Content -LiteralPath $reportPath -Value (ConvertTo-Json -InputObject $report -Compress)
    $toolchainFacts = Get-AlicornCMakeCompilerFacts $toolchainFixtureRoot
    if ($toolchainFacts.pointerSize -ne '8' -or $toolchainFacts.crt -ne 'MultiThreaded' -or $toolchainFacts.targetSystem -ne 'Windows' -or
        $toolchainFacts.cCompiler -ne $compiler -or $toolchainFacts.cxxCompiler -ne $compiler) {
        throw 'The accepted MSVC toolchain facts were not preserved.'
    }
} finally {
    if (Test-Path -LiteralPath $toolchainFixtureRoot) {
        if (-not ([IO.Path]::GetFullPath($toolchainFixtureRoot)).StartsWith($fixtureBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove toolchain fixture outside generated output: '$toolchainFixtureRoot'." }
        Remove-Item -LiteralPath $toolchainFixtureRoot -Recurse -Force
    }
}

$fixtureRoot = Join-Path $outRoot ('validator-fixture-' + [guid]::NewGuid().ToString('N'))
$junctionTarget = Join-Path $outRoot ('junction-target-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
if (-not ([IO.Path]::GetFullPath($fixtureRoot)).StartsWith($fixtureBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create validator fixture outside Alicorn output: '$fixtureRoot'."
}
try {
    New-Item -ItemType Directory -Path $junctionTarget | Out-Null
    $inputs = [ordered]@{ test='native-link-generation'; schema=1 }
    $inputJson = ConvertTo-Json -InputObject $inputs -Depth 10 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($inputJson))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $fixtureFiles = [ordered]@{
        'recipe.json' = '{}'
        'odin/vendor/sdl3/SDL3.lib' = 'sdl artifact'
        'accesskit/lib/accesskit.lib' = 'accesskit artifact'
        'licenses/SDL-LICENSE.txt' = 'SDL license'
        'licenses/AccessKit-LICENSE-APACHE.txt' = 'AccessKit Apache license'
        'licenses/AccessKit-LICENSE-MIT.txt' = 'AccessKit MIT license'
        'payload.lib' = 'valid artifact'
    }
    $artifactRecords = [Collections.Generic.List[object]]::new()
    foreach ($relativePath in $fixtureFiles.Keys) {
        $path = Join-Path $fixtureRoot ($relativePath -replace '/', '\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllBytes($path, [Text.Encoding]::UTF8.GetBytes($fixtureFiles[$relativePath]))
        $artifactRecords.Add([ordered]@{ path=$relativePath; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() })
    }
    $junctionPath = Join-Path $fixtureRoot 'odin\base'
    New-Item -ItemType Directory -Path (Split-Path -Parent $junctionPath) -Force | Out-Null
    New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget | Out-Null
    $artifact = Join-Path $fixtureRoot 'payload.lib'
    $manifest = [ordered]@{
        schemaVersion=1
        provenance=[ordered]@{ fingerprint=$fingerprint }
        inputs=$inputs
        artifacts=@($artifactRecords.ToArray())
        junctions=@([ordered]@{ path='odin/base'; target=$junctionTarget })
    }
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'manifest.json') -Value (ConvertTo-Json -InputObject $manifest -Depth 10) -Encoding utf8
    $validation = Test-AlicornNativeLinkGeneration -GenerationRoot $fixtureRoot -ExpectedFingerprint $fingerprint
    if (-not $validation.valid) { throw "Valid content-addressed generation was rejected: $($validation.reason)." }
    $manifest.junctions[0].target = Join-Path $outRoot 'wrong-junction-target'
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'manifest.json') -Value (ConvertTo-Json -InputObject $manifest -Depth 10) -Encoding utf8
    $validation = Test-AlicornNativeLinkGeneration -GenerationRoot $fixtureRoot -ExpectedFingerprint $fingerprint
    if ($validation.valid -or $validation.reason -notmatch 'wrong Odin SDK directory') { throw 'A junction pointed at the wrong SDK directory must be rejected.' }
    $manifest.junctions[0].target = $junctionTarget
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'manifest.json') -Value (ConvertTo-Json -InputObject $manifest -Depth 10) -Encoding utf8
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'unexpected.txt'), 'unmanifested')
    $validation = Test-AlicornNativeLinkGeneration -GenerationRoot $fixtureRoot -ExpectedFingerprint $fingerprint
    if ($validation.valid -or $validation.reason -notmatch 'inventory') { throw 'Unmanifested generated files must be rejected.' }
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'unexpected.txt') -Force
    [IO.File]::WriteAllBytes($artifact, [Text.Encoding]::UTF8.GetBytes('corrupt artifact'))
    $validation = Test-AlicornNativeLinkGeneration -GenerationRoot $fixtureRoot -ExpectedFingerprint $fingerprint
    if ($validation.valid -or $validation.reason -notmatch 'hash mismatch') { throw 'Corrupt prepared artifacts must be rejected by hash validation.' }
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        if (-not ([IO.Path]::GetFullPath($fixtureRoot)).StartsWith($fixtureBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove fixture outside generated output: '$fixtureRoot'." }
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $junctionTarget) {
        if (-not ([IO.Path]::GetFullPath($junctionTarget)).StartsWith($fixtureBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove junction target outside generated output: '$junctionTarget'." }
        Remove-Item -LiteralPath $junctionTarget -Recurse -Force
    }
}

Write-Host 'Native-link recipe contract tests passed.'
