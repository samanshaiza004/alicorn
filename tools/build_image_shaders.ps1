param(
    [string]$Dxc = '.deps/icon-tools/dxc/bin/x64/dxc.exe',
    [string]$Glslang = '.deps/icon-tools/glslang/bin/glslang.exe',
    [switch]$Verify
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $RepoRoot
try {
    $Source = 'native/sdl_gpu/image_shaders'
    $Stage = 'out/image-shader-generation'
    $Manifest = Get-Content "$Source/manifest.json" -Raw | ConvertFrom-Json
    $DxcVersion = (& $Dxc --version | Out-String)
    $GlslangVersion = (& $Glslang --version | Out-String)
    if (-not $DxcVersion.Contains([string]$Manifest.dxc) -or -not $GlslangVersion.Contains([string]$Manifest.glslang)) {
        throw 'Image shader compilation requires the tool versions pinned in manifest.json.'
    }
    New-Item -ItemType Directory -Force $Stage | Out-Null
    & $Dxc -T ps_6_0 -E PSMain -Qstrip_debug -Qstrip_reflect -Fo "$Stage/image.frag.dxil" "$Source/image.frag.hlsl"
    if ($LASTEXITCODE -ne 0) { throw 'Image DXIL compilation failed.' }
    & $Glslang -V -S frag -o "$Stage/image.frag.spv" "$Source/image.frag.glsl"
    if ($LASTEXITCODE -ne 0) { throw 'Image SPIR-V compilation failed.' }
    foreach ($Name in @('image.frag.dxil', 'image.frag.spv')) {
        if ($Verify) {
            if ((Get-FileHash "$Stage/$Name").Hash -ne (Get-FileHash "$Source/$Name").Hash) {
                throw "Generated image shader differs: $Name"
            }
        } else { Copy-Item -LiteralPath "$Stage/$Name" -Destination "$Source/$Name" -Force }
    }
    foreach ($Name in @('image.frag.hlsl', 'image.frag.glsl', 'image.frag.metal', 'image.frag.dxil', 'image.frag.spv')) {
        $Path = Join-Path $Source $Name
        if ([IO.Path]::GetExtension($Name) -in @('.hlsl', '.glsl', '.metal')) {
            $Content = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path).Replace("`r`n", "`n")
            $Hasher = [Security.Cryptography.SHA256]::Create()
            try {
                $Hash = [BitConverter]::ToString($Hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Content))).Replace('-', '').ToLowerInvariant()
            } finally { $Hasher.Dispose() }
        } else {
            $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        if ($Verify -and $Manifest.sha256.$Name -ne $Hash) { throw "Image shader manifest differs: $Name" }
        $Manifest.sha256.$Name = $Hash
    }
    if (-not $Verify) {
        $ManifestPath = Join-Path $RepoRoot "$Source/manifest.json"
        [IO.File]::WriteAllText($ManifestPath, (($Manifest | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    }
}
finally { Pop-Location }
