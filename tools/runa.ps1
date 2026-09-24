param(
    [string]$Odin,
    [Parameter(Mandatory=$true)][string]$Font
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
if (-not (Test-Path -LiteralPath $Font)) { throw "Font not found: $Font" }

New-Item -ItemType Directory -Force -Path 'out' | Out-Null
& $Odin build examples\runa_text -out:out\runa_text.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\runa_text.exe $Font
exit $LASTEXITCODE
