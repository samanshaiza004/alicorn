param(
    [string]$Odin
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
New-Item -ItemType Directory -Force -Path 'out' | Out-Null
$AccessKit = Get-AlicornAccessKit

& "$PSScriptRoot\check_accesskit_abi_contract.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$AccessKitAbiProbeFlags = & "$PSScriptRoot\build_accesskit_abi_probe.ps1" -OutputDirectory 'out\accesskit_abi_probe'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$AccessKitTestLinkFlags = "$($AccessKit.LinkerFlags) $AccessKitAbiProbeFlags"
& $Odin check accesskit -no-entry-point
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin test accesskit "-extra-linker-flags:$AccessKitTestLinkFlags" -out:out\alicorn_accesskit_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin build accesskit\consumer "-collection:accesskit=$RepoRoot" "-extra-linker-flags:$($AccessKit.LinkerFlags)" -out:out\accesskit_external_consumer.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\accesskit_external_consumer.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Odin build tests -out:out\alicorn_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin build native\sdl_gpu_entry "-extra-linker-flags:$($AccessKit.LinkerFlags)" -out:out\alicorn_sdl_gpu.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Native tests and the text-input contract executable link SDL3 even when they
# do not create a window. Stage the runtime DLL as the native smoke runners do.
$OdinRoot = Split-Path -Parent $Odin
$SDL3 = Join-Path $OdinRoot 'vendor\sdl3\SDL3.dll'
if (-not (Test-Path -LiteralPath $SDL3 -PathType Leaf)) {
    throw "SDL3.dll not found at '$SDL3'. Use an Odin distribution that includes vendor/sdl3."
}
if ((Get-Item -LiteralPath $SDL3).Length -lt 100000) {
    throw "SDL3.dll at '$SDL3' appears to be a Git LFS pointer. Run 'git lfs pull' in the Odin checkout."
}
Copy-Item -LiteralPath $SDL3 -Destination 'out\SDL3.dll' -Force

# Keep the native accessibility contract fixture compiling on Windows even
# though it is launched manually for UIA and Narrator/NVDA validation.
$AccessibilityFixture = Join-Path $RepoRoot 'tests\fixtures\accessibility_contract'
$AccessibilityFixtureOutput = Join-Path $RepoRoot 'out\fixtures\accessibility_contract.exe'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $AccessibilityFixtureOutput) | Out-Null
& $Odin build $AccessibilityFixture "-collection:alicorn=$RepoRoot" `
	"-extra-linker-flags:$($AccessKit.LinkerFlags)" "-out:$AccessibilityFixtureOutput"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Odin test runtime
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin test tests\fixtures\accessibility_contract "-collection:alicorn=$RepoRoot" `
	"-extra-linker-flags:$($AccessKit.LinkerFlags)" -out:out\accessibility_contract_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin test ui "-collection:alicorn=$RepoRoot" "-extra-linker-flags:$($AccessKit.LinkerFlags)" -out:out\alicorn_ui_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin test theme
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin build tools\theme -out:out\alicorn_theme.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_theme.exe check theme\testdata\minimal.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_theme.exe check theme\testdata\extends_base.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
New-Item -ItemType Directory -Force -Path 'out\theme_codegen_smoke' | Out-Null
& .\out\alicorn_theme.exe compile theme\testdata\minimal.json --output out\theme_codegen_smoke\generated.odin --symbol TEST_THEME --runtime-import ../../runtime
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin check out\theme_codegen_smoke -no-entry-point
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_theme.exe explain theme\testdata\minimal.json color.primary
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_theme.exe check theme\testdata\invalid.json
if ($LASTEXITCODE -eq 0) { throw "Theme CLI accepted an unsupported length unit." }
& $Odin test native\sdl_gpu "-extra-linker-flags:$($AccessKit.LinkerFlags)" -out:out\alicorn_native_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Odin test native\scroll_capture_tests "-extra-linker-flags:$($AccessKit.LinkerFlags)" -out:out\alicorn_scroll_capture_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& .\out\alicorn_tests.exe
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot\test_restoration.ps1" -Odin $Odin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& .\out\alicorn_sdl_gpu.exe --text-input-contract-test
exit $LASTEXITCODE
