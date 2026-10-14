[CmdletBinding()]
param(
    [string]$Odin,
    [string]$OdinRoot,
    [ValidateSet('windows-x86_64')][string]$Target = 'windows-x86_64'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'native_link.psm1') -Force -ErrorAction Stop
$recipe = New-AlicornWindowsStaticLinkRecipe -Odin $Odin -OdinRoot $OdinRoot
[Console]::Out.WriteLine((ConvertTo-Json -InputObject $recipe -Depth 40))
