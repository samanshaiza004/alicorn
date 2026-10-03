[CmdletBinding()]
param(
    [string]$OutputPath = 'out\perf-100k-trace.json',
    [int]$EventCount = 100000
)

$ErrorActionPreference = 'Stop'
if ($EventCount -lt 1) { throw 'EventCount must be positive.' }

if ([IO.Path]::IsPathRooted($OutputPath)) {
    $path = [IO.Path]::GetFullPath($OutputPath)
} else {
    $path = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
}
$parent = Split-Path -Parent $path
New-Item -ItemType Directory -Force -Path $parent | Out-Null

$writer = [IO.StreamWriter]::new($path, $false, [Text.UTF8Encoding]::new($false))
try {
    $writer.Write('{"traceEvents":[')
    for ($timestamp = $EventCount; $timestamp -ge 1; $timestamp--) {
        if ($timestamp -ne $EventCount) { $writer.Write(',') }
        $writer.Write('{"ph":"X","name":"Repeated","cat":"render","ts":')
        $writer.Write($timestamp.ToString([Globalization.CultureInfo]::InvariantCulture))
        $writer.Write(',"dur":2,"pid":1,"tid":1}')
    }
    $writer.Write(']}')
} finally {
    $writer.Dispose()
}

Get-FileHash -LiteralPath $path -Algorithm SHA256
