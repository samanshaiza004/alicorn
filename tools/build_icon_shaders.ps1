param(
    [string]$Dxc = '.deps/icon-tools/dxc/bin/x64/dxc.exe',
    [string]$Glslang = '.deps/icon-tools/glslang/bin/glslang.exe',
    [switch]$Verify
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $RepoRoot
try {
    $Source = 'native/sdl_gpu/icon_shaders'
    $Stage = 'out/icon-generation'
    $Manifest = Get-Content "$Source/manifest.json" -Raw | ConvertFrom-Json
    $DxcVersion = (& $Dxc --version | Out-String)
    $GlslangVersion = (& $Glslang --version | Out-String)
    if (-not $DxcVersion.Contains([string]$Manifest.dxc) -or -not $GlslangVersion.Contains([string]$Manifest.glslang)) {
        throw 'Icon shader compilation requires the tool versions pinned in manifest.json.'
    }
    New-Item -ItemType Directory -Force $Stage | Out-Null
    & $Dxc -T ps_6_0 -E PSMain -Qstrip_debug -Qstrip_reflect -Fo "$Stage/icon.frag.dxil" "$Source/icon.frag.hlsl"
    if ($LASTEXITCODE -ne 0) { throw 'Icon DXIL compilation failed.' }
    & $Glslang -V -S frag -o "$Stage/icon.frag.spv" "$Source/icon.frag.glsl"
    if ($LASTEXITCODE -ne 0) { throw 'Icon SPIR-V compilation failed.' }
    foreach ($Name in @('icon.frag.dxil', 'icon.frag.spv')) {
        if ($Verify) {
            if ((Get-FileHash "$Stage/$Name").Hash -ne (Get-FileHash "$Source/$Name").Hash) {
                throw "Generated icon shader differs: $Name"
            }
        } else { Copy-Item -LiteralPath "$Stage/$Name" -Destination "$Source/$Name" -Force }
    }
    foreach ($Name in @('icon.frag.hlsl', 'icon.frag.glsl', 'icon.frag.metal', 'icon.frag.dxil', 'icon.frag.spv')) {
        $Hash = (Get-FileHash "$Source/$Name" -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Verify -and $Manifest.sha256.$Name -ne $Hash) { throw "Icon shader manifest differs: $Name" }
        $Manifest.sha256.$Name = $Hash
    }
    if (-not $Verify) {
        $ManifestPath = Join-Path $RepoRoot "$Source/manifest.json"
        [IO.File]::WriteAllText($ManifestPath, (($Manifest | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    }
}
finally { Pop-Location }
