function Resolve-AlicornOdin {
    param(
        [AllowNull()]
        [string]$Requested
    )

    $candidate = $Requested
    $source = '-Odin'
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:ALICORN_ODIN
        $source = 'ALICORN_ODIN'
    }

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = 'odin'
        $source = 'PATH'
    }

    $hasPathSeparator = $candidate.Contains([IO.Path]::DirectorySeparatorChar) -or
        $candidate.Contains([IO.Path]::AltDirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($candidate) -or $hasPathSeparator) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Odin executable not found at '$candidate' (from $source)."
        }

        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    if ($source -eq 'PATH') {
        throw @"
Odin was not found.

Install Odin: https://odin-lang.org/docs/install/
Then add the Odin directory to PATH, or set ALICORN_ODIN to the compiler executable.
"@
    }

    throw "Odin executable '$candidate' was not found (from $source)."
}

function Get-AlicornAccessKit {
    $version = '0.23.1'
    $url = "https://github.com/AccessKit/accesskit-c/releases/download/$version/accesskit-c-$version.zip"
    $sha256 = '35b7ca8a6f1e038b5da35e1e9e5a0adaed9bfcf21e1496d29598fbbadcc7043f'
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $cacheRoot = Join-Path $repoRoot '.deps\accesskit'
    $archive = Join-Path $cacheRoot "accesskit-c-$version.zip"
    $distribution = Join-Path $cacheRoot "accesskit-c-$version"

    $architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    if ($env:OS -ne 'Windows_NT') { throw "AccessKit static bootstrap does not support this OS in PowerShell: '$env:OS'." }
    if ($architecture -ne 'X64') { throw "AccessKit $version Windows static library is only configured here for x86_64 MSVC; process architecture is '$architecture'." }

    if (-not [IO.Directory]::Exists($cacheRoot)) {
        New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
    }
    if (-not [IO.File]::Exists($archive)) {
        $curl = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $curl) { throw 'AccessKit bootstrap requires curl.exe to download the pinned release archive.' }
        & $curl.Source --fail --location --silent --show-error --output $archive $url
        if ($LASTEXITCODE -ne 0) { throw "AccessKit $version download failed (curl exit $LASTEXITCODE): $url" }
    }

    $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $sha256) {
        throw "AccessKit $version archive SHA-256 mismatch. Expected $sha256; got $actualHash. Cached archive: '$archive'."
    }

    $relativeLibrary = 'lib\windows\x86_64\msvc\static\accesskit.lib'
    $library = Join-Path $distribution $relativeLibrary
    if (-not [IO.File]::Exists($library)) {
        if ([IO.Directory]::Exists($distribution)) {
            throw "AccessKit $version cache exists but the required library is missing: '$library'. Remove only that versioned cache directory and retry."
        }
        $stage = Join-Path $cacheRoot ('.extract-' + [guid]::NewGuid().ToString('N'))
        try {
            Expand-Archive -LiteralPath $archive -DestinationPath $stage
            $stagedDistribution = Join-Path $stage "accesskit-c-$version"
            $stagedLibrary = Join-Path $stagedDistribution $relativeLibrary
            if (-not [IO.File]::Exists($stagedLibrary)) {
                throw "Verified AccessKit archive does not contain the expected Windows x86_64 MSVC static library: '$relativeLibrary'."
            }
            Move-Item -LiteralPath $stagedDistribution -Destination $distribution
        } finally {
            if ([IO.Directory]::Exists($stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
        }
    }

    $libraryDirectory = ".deps\accesskit\accesskit-c-$version\lib\windows\x86_64\msvc\static"
    $linkerFlags = "/LIBPATH:$libraryDirectory bcrypt.lib ntdll.lib propsys.lib runtimeobject.lib uiautomationcore.lib userenv.lib ws2_32.lib"
    return [pscustomobject]@{ Root = $distribution; Library = $library; LinkerFlags = $linkerFlags }
}
