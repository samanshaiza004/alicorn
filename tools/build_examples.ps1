param([string]$Odin)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$ExampleRoot = Join-Path $RepoRoot 'examples'
$OutputRoot = Join-Path $RepoRoot 'out\examples'
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

Push-Location $RepoRoot
try {
	$Examples = Get-ChildItem -LiteralPath $ExampleRoot -Directory |
		Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'main.odin') } |
		Sort-Object -Property Name
	foreach ($Example in $Examples) {
		$Output = Join-Path $OutputRoot ($Example.Name + '.exe')
		Write-Host "Building example $($Example.Name)"
		& $Odin build (Join-Path 'examples' $Example.Name) "-out:$Output"
		if ($LASTEXITCODE -ne 0) { throw "Example build failed: $($Example.Name) (exit $LASTEXITCODE)" }
	}
}
finally {
	Pop-Location
}
