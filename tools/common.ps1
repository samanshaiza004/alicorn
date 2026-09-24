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
