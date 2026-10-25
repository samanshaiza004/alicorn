param([string]$Odin)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $Root
try {
    New-Item -ItemType Directory -Force -Path 'out' | Out-Null
    & $Odin build tests\fixtures\durable_restoration -out:out\durable-restoration.exe
    if ($LASTEXITCODE -ne 0) { throw 'Restoration fixture build failed.' }
    $Session = Join-Path $Root 'out\restoration-session.json'
    # Each invocation is a new process with an independently created Runtime.
    foreach ($Mode in @('--write', '--read', '--narrow', '--short')) {
        & .\out\durable-restoration.exe $Mode $Session
        if ($LASTEXITCODE -ne 0) { throw "Restoration check failed: $Mode" }
    }
    $Missing = Join-Path $Root ('out\missing-session-' + [Guid]::NewGuid().ToString('N') + '.json')
    & .\out\durable-restoration.exe --defaults $Missing
    if ($LASTEXITCODE -ne 0) { throw 'Missing session fallback failed.' }
    $Invalid = Join-Path $Root 'out\invalid-restoration-session.json'
    foreach ($Data in @('{broken', '{"version":999}', '{"version":1,"split_ratio":1e40}')) {
        [IO.File]::WriteAllText($Invalid, $Data)
        & .\out\durable-restoration.exe --defaults $Invalid
        if ($LASTEXITCODE -ne 0) { throw 'Invalid session fallback failed.' }
    }
} finally { Pop-Location }
