param(
    [string]$Odin = $env:ALICORN_ODIN,
    [Parameter(Mandatory=$true)][string]$Font
)

if (-not $Odin) { $Odin = 'C:\Users\saman\Documents\odin\dist\odin.exe' }
if (-not (Test-Path -LiteralPath $Odin)) { throw "Odin executable not found: $Odin. Set ALICORN_ODIN." }
if (-not (Test-Path -LiteralPath $Font)) { throw "Font not found: $Font" }

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path 'out' | Out-Null
& $Odin build examples\runa_text -out:out\runa_text.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\runa_text.exe $Font
exit $LASTEXITCODE
