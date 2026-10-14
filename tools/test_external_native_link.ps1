param([string]$Odin)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Fixture = Join-Path $RepoRoot 'tests\fixtures\external_odin_consumer'
$RecipeCommand = Join-Path $PSScriptRoot 'native_link_recipe.ps1'
$PowerShell = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$TempRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('Alicorn External Consumer ' + [guid]::NewGuid().ToString('N'))))
$TempBoundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (-not $TempRoot.StartsWith($TempBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create external fixture outside the temporary directory: '$TempRoot'."
}
New-Item -ItemType Directory -Path $TempRoot | Out-Null
$OldOdinRoot = $env:ODIN_ROOT
$PreparationProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()
try {
    $recipeRuns = [Collections.Generic.List[object]]::new()
    $coldPreparationTimer = [Diagnostics.Stopwatch]::StartNew()
    for ($index = 1; $index -le 2; $index++) {
        $stdoutPath = Join-Path $TempRoot "recipe-$index.json"
        $stderrPath = Join-Path $TempRoot "recipe-$index.log"
        $argumentLine = @('-NoLogo', '-NoProfile', '-File', ('"{0}"' -f $RecipeCommand), '-Odin', ('"{0}"' -f $Odin), '-Target', 'windows-x86_64') -join ' '
        $process = Start-Process -FilePath $PowerShell -ArgumentList $argumentLine -WorkingDirectory $TempRoot `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
        $PreparationProcesses.Add($process)
        $recipeRuns.Add([pscustomobject]@{ process=$process; stdout=$stdoutPath; stderr=$stderrPath })
    }
    foreach ($run in $recipeRuns) {
        if (-not $run.process.WaitForExit(1800000)) {
            $run.process.Kill()
            throw 'A concurrent native-link recipe request exceeded 30 minutes.'
        }
        if ($run.process.ExitCode -ne 0) {
            $diagnostics = if (Test-Path -LiteralPath $run.stderr) { Get-Content -LiteralPath $run.stderr -Raw } else { '' }
            throw "Native link recipe command failed with exit $($run.process.ExitCode).`n$diagnostics"
        }
    }
    $coldPreparationTimer.Stop()
    $coldPreparationSeconds = [Math]::Round($coldPreparationTimer.Elapsed.TotalSeconds, 2)
    $recipeCandidates = @($recipeRuns | ForEach-Object { Get-Content -LiteralPath $_.stdout -Raw | ConvertFrom-Json })
    if ($recipeCandidates.Count -ne 2 -or $recipeCandidates[0].provenance.fingerprint -ne $recipeCandidates[1].provenance.fingerprint) {
        throw 'Concurrent cold-cache recipe requests did not publish and reuse one validated generation.'
    }
    $recipe = $recipeCandidates[0]
    $nativeManifest = Get-Content -LiteralPath $recipe.provenance.manifest -Raw | ConvertFrom-Json
    $toolchain = $nativeManifest.toolchain
    $measurementContext = "Runner: $env:ImageOS $env:ImageVersion; Odin: $($recipe.provenance.odinVersion); CMake: $($nativeManifest.inputs.cmake.version); generator: $($toolchain.generator); C/C++ compiler: $($toolchain.cCompilerVersion) / $($toolchain.cxxCompilerVersion) ($($toolchain.cCompilerFileVersion)); linker: $($toolchain.linkerVersion); Windows SDK: $($toolchain.windowsSdkVersion); CRT: $($toolchain.crt)."
    Write-Host "Native-link validation environment: $measurementContext"
    if ($recipe.schemaVersion -ne 1 -or $recipe.linkage -ne 'static' -or $recipe.target -ne 'windows-x86_64-msvc') {
        throw 'The native-link recipe returned an unsupported or malformed contract.'
    }
    if (-not [IO.Directory]::Exists($recipe.environment.ODIN_ROOT)) { throw "Recipe ODIN_ROOT does not exist: '$($recipe.environment.ODIN_ROOT)'." }
    if (-not (Test-Path -LiteralPath $recipe.artifacts.sdl.library -PathType Leaf)) { throw 'Recipe SDL artifact is missing.' }
    if (-not (Test-Path -LiteralPath $recipe.artifacts.accesskit.library -PathType Leaf)) { throw 'Recipe AccessKit artifact is missing.' }
    if (@($recipe.odin.compilerArguments).Count -ne 1 -or $recipe.odin.compilerArguments[0] -notlike '-extra-linker-flags:*') {
        throw 'Recipe compiler arguments must be an Odin argument array, not a shell command.'
    }

    $warmRecipeTimer = [Diagnostics.Stopwatch]::StartNew()
    $warmJson = & $PowerShell -NoLogo -NoProfile -File $RecipeCommand -Odin $Odin -Target windows-x86_64
    $warmRecipeTimer.Stop()
    if ($LASTEXITCODE -ne 0) { throw "Warm native link recipe request failed with exit $LASTEXITCODE." }
    $warmRecipeSeconds = [Math]::Round($warmRecipeTimer.Elapsed.TotalSeconds, 2)
    $warmRecipe = ($warmJson -join "`n") | ConvertFrom-Json
    if ($warmRecipe.provenance.fingerprint -ne $recipe.provenance.fingerprint -or $warmRecipe.environment.ODIN_ROOT -ne $recipe.environment.ODIN_ROOT) {
        throw 'A repeated recipe request did not validate and reuse the same immutable generation.'
    }

    Copy-Item -LiteralPath (Join-Path $Fixture 'main.odin') -Destination (Join-Path $TempRoot 'main.odin')
    $metadata = Get-Content -LiteralPath (Join-Path $Fixture 'package.json') -Raw
    Set-Content -LiteralPath (Join-Path $TempRoot 'package.json') -Value $metadata -Encoding utf8
    $executable = Join-Path $TempRoot 'AlicornExternalConsumer.exe'
    $buildArgs = @(
        'build', $TempRoot, '-target:windows_amd64',
        "-collection:alicorn=$RepoRoot", "-out:$executable"
    ) + @($recipe.odin.compilerArguments)

    $env:ODIN_ROOT = [string]$recipe.environment.ODIN_ROOT
    Push-Location $TempRoot
    try {
        $externalBuildTimer = [Diagnostics.Stopwatch]::StartNew()
        & $recipe.odin.executable @buildArgs
        $externalBuildTimer.Stop()
        if ($LASTEXITCODE -ne 0) { throw "External Odin/Alicorn consumer build failed (exit $LASTEXITCODE)." }
    } finally { Pop-Location }
    if (-not [IO.File]::Exists($executable)) { throw 'External consumer build reported success without producing its executable.' }
    $externalBuildSeconds = [Math]::Round($externalBuildTimer.Elapsed.TotalSeconds, 2)
    $externalExecutableBytes = (Get-Item -LiteralPath $executable).Length

    $packageArgs = @{
        Executable=$executable
        Metadata=(Join-Path $TempRoot 'package.json')
        SDLLinkage='Static'
        SDLVersion=$recipe.artifacts.sdl.version
        SDLLicense=$recipe.artifacts.sdl.license
        AccessKitLicenseApache=$recipe.artifacts.accesskit.licenses[0]
        AccessKitLicenseMIT=$recipe.artifacts.accesskit.licenses[1]
        OutputDirectory=(Join-Path $TempRoot 'package')
        SmokeTest=$true
    }
    & (Join-Path $PSScriptRoot 'package_app.ps1') @packageArgs
    if ($LASTEXITCODE -ne 0) { throw "External consumer package audit/smoke failed (exit $LASTEXITCODE)." }
    $packageManifest = Get-Content -LiteralPath (Join-Path $TempRoot 'package\alicorn-package.json') -Raw | ConvertFrom-Json
    if ($packageManifest.dependencies.bundled.Count -ne 0) { throw 'The external static SDL fixture unexpectedly requires bundled private DLLs.' }
    Write-Host "External static Alicorn consumer passed from '$TempRoot'."
    $measurements = @"
| Measurement | Result |
| --- | ---: |
| Cold concurrent SDL preparation and recipe requests | $coldPreparationSeconds s |
| Warm recipe request | $warmRecipeSeconds s |
| External Odin compile and link | $externalBuildSeconds s |
| External static consumer executable | $externalExecutableBytes bytes |
"@
    Write-Host "Native-link measurements:`n$measurements"
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        $summary = "## Windows static SDL recipe measurements`n`n$measurementContext Target: ``$($recipe.target)``.`n`n$measurements`n"
        [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $summary, [Text.UTF8Encoding]::new($false))
    }
} finally {
    foreach ($process in $PreparationProcesses) {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
    if ($null -eq $OldOdinRoot) { Remove-Item Env:ODIN_ROOT -ErrorAction SilentlyContinue }
    else { $env:ODIN_ROOT = $OldOdinRoot }
    if (Test-Path -LiteralPath $TempRoot) {
        if (-not $TempRoot.StartsWith($TempBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove external fixture outside temp root: '$TempRoot'." }
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}
