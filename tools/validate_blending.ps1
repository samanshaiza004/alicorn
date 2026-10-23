param([string]$Odin)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $RepoRoot
try {
    New-Item -ItemType Directory -Force out | Out-Null
    # Use existing dependencies; this validation runner never downloads them.
    if ($env:OS -ne 'Windows_NT') { throw 'Use tools/validate_blending.sh on macOS/Linux.' }
    $AccessKitDir = Join-Path $RepoRoot '.deps\accesskit\accesskit-c-0.23.1\lib\windows\x86_64\msvc\static'
    if (-not (Test-Path -LiteralPath (Join-Path $AccessKitDir 'accesskit.lib'))) {
        throw "Existing AccessKit static library required: $AccessKitDir\accesskit.lib"
    }
    $QuotedAccessKitDir = if ($AccessKitDir -match '\s') { "`"$AccessKitDir`"" } else { $AccessKitDir }
    $LinkerFlags = "/LIBPATH:$QuotedAccessKitDir bcrypt.lib ntdll.lib propsys.lib runtimeobject.lib uiautomationcore.lib userenv.lib ws2_32.lib"
    & $Odin build native\blend_validation_entry "-extra-linker-flags:$LinkerFlags" -out:out\alicorn_blend_validation.exe
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $SDL3 = Join-Path (Split-Path -Parent $Odin) 'vendor\sdl3\SDL3.dll'
    if (-not (Test-Path out\SDL3.dll)) { Copy-Item -LiteralPath $SDL3 -Destination out\SDL3.dll }
    & .\out\alicorn_blend_validation.exe
    exit $LASTEXITCODE
}
finally { Pop-Location }
