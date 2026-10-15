param(
    [string]$Odin = 'odin',
    [ValidateRange(1, 20)][int]$Runs = 5,
    [string]$Output = (Join-Path $PSScriptRoot '../../docs/benchmarks/raw/history-real-patch-projection-windows-2026-10-14.txt')
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$buildDir = Join-Path $repoRoot 'out/history-patch-research'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$binary = Join-Path $buildDir 'history-patch-projection.exe'
& $Odin build $PSScriptRoot "-out:$binary" '-o:speed' '-thread-count:1'
if ($LASTEXITCODE -ne 0) { throw 'Odin research build failed' }
$capturePath = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path (Split-Path $capturePath) | Out-Null
$compiler = & $Odin version
Set-Content -LiteralPath $capturePath -Encoding utf8NoBOM -Value @(
    "History real-patch projection; $compiler",
    "Windows $([Environment]::OSVersion.Version); -o:speed -thread-count:1; $Runs sequential fresh processes",
    'Both index layouts use identical inline 16-byte spans; no full projection-record table.',
    'Amplified case repeats/renumbers real hunk bodies; it is a scale test, not a captured History workload.',
    'Index memory is requested heap bytes; allocator bookkeeping and process overhead are excluded.'
)
$sources = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.odin' | Sort-Object Name
foreach ($source in $sources) {
    $hash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
    Add-Content -LiteralPath $capturePath -Encoding utf8NoBOM -Value "source_sha256 $($source.Name) $hash"
}
$checksums = @{}
for ($run = 1; $run -le $Runs; $run++) {
    $lines = & $binary '--bench'
    if ($LASTEXITCODE -ne 0) { throw "Research process $run failed" }
    foreach ($line in $lines) {
        if ($line -match '^real_patch (\S+) backend \S+ .* checksum (\d+)$') {
            $fixture = $Matches[1]
            $checksum = $Matches[2]
            if ($checksums.ContainsKey($fixture) -and $checksums[$fixture] -ne $checksum) { throw "Checksum mismatch for $fixture" }
            $checksums[$fixture] = $checksum
        }
    }
    Add-Content -LiteralPath $capturePath -Encoding utf8NoBOM -Value "process $run"
    Add-Content -LiteralPath $capturePath -Encoding utf8NoBOM -Value $lines
}
Write-Output "Captured $Runs passing processes in $capturePath"
