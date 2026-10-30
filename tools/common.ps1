function Initialize-AlicornMsvcEnvironment {
    if ($env:INCLUDE -and $env:LIB -and $env:VSCMD_VER) { return }

    $VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $VsWhere -PathType Leaf)) {
        if ($env:INCLUDE -and $env:LIB) { return }
        throw 'MSVC environment is not initialized and vswhere.exe was not found. Install the Visual C++ build tools or run from a Visual Studio Developer PowerShell.'
    }

    $Install = & $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $Install) {
        throw 'MSVC environment is not initialized and vswhere could not find Visual Studio with the x64 C++ toolchain.'
    }
    $VsDevCmd = Join-Path $Install 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $VsDevCmd -PathType Leaf)) {
        throw "MSVC environment setup script was not found: '$VsDevCmd'. Repair the Visual Studio C++ build tools installation."
    }

    $CommandShell = if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' }
    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = $CommandShell
    $StartInfo.Arguments = "/d /c call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $StartInfo
    try {
        if (-not $Process.Start()) { throw 'cmd.exe did not start.' }
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.WaitForExit()
        $EnvironmentOutput = $OutputTask.GetAwaiter().GetResult()
        $ErrorOutput = $ErrorTask.GetAwaiter().GetResult()
        if ($Process.ExitCode -ne 0) {
            throw "VsDevCmd.bat failed to initialize the x64 C++ environment (exit code $($Process.ExitCode)): $ErrorOutput"
        }
    }
    finally {
        $Process.Dispose()
    }
    $EnvironmentLines = $EnvironmentOutput -split "`r?`n"
    foreach ($Line in $EnvironmentLines) {
        $Separator = $Line.IndexOf('=')
        if ($Separator -le 0) { continue }
        $Name = $Line.Substring(0, $Separator)
        $Value = $Line.Substring($Separator + 1)
        [System.Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
    if (-not ($env:INCLUDE -and $env:LIB -and $env:VSCMD_VER)) {
        throw 'VsDevCmd.bat completed without exporting the expected INCLUDE, LIB, and VSCMD_VER variables.'
    }
}

function Resolve-AlicornOdin {
    param(
        [AllowNull()]
        [string]$Requested
    )

    $candidate = $Requested
    $source = '-Odin'
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:ALICORN_ODIN
        $source = 'ALICORN_ODIN'
    }

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = 'odin'
        $source = 'PATH'
    }

    $hasPathSeparator = $candidate.Contains([IO.Path]::DirectorySeparatorChar) -or
        $candidate.Contains([IO.Path]::AltDirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($candidate) -or $hasPathSeparator) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Odin executable not found at '$candidate' (from $source)."
        }

        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    if ($source -eq 'PATH') {
        throw @"
Odin was not found.

Install Odin: https://odin-lang.org/docs/install/
Then add the Odin directory to PATH, or set ALICORN_ODIN to the compiler executable.
"@
    }

    throw "Odin executable '$candidate' was not found (from $source)."
}

function Get-AlicornAccessKitBinding {
    $ErrorActionPreference = 'Stop'
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $pin = Get-Content -LiteralPath (Join-Path $repoRoot 'dependencies\odin-accesskit.json') -Raw | ConvertFrom-Json
    if ($pin.commit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'dependencies/odin-accesskit.json must pin a full standalone commit SHA; PENDING_STANDALONE_SHA cannot be built.'
    }
    if ([string]::IsNullOrWhiteSpace($pin.repository)) { throw 'Missing odin-accesskit repository in dependency pin.' }
    $depsRoot = Join-Path $repoRoot '.deps'
    $checkout = Join-Path $depsRoot 'odin-accesskit'
    New-Item -ItemType Directory -Path $depsRoot -Force | Out-Null
    $lockPath = Join-Path $depsRoot 'odin-accesskit.checkout.lock'
    $lock = $null
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    while (-not $lock) {
        try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) { throw "Timed out waiting for the binding checkout lock: '$lockPath'." }
            Start-Sleep -Milliseconds 250
        }
    }
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $checkout '.git') -PathType Container)) {
            if ((Test-Path -LiteralPath $checkout) -and @(Get-ChildItem -LiteralPath $checkout -Force).Count) {
                throw "Refusing to initialize a nonempty binding checkout: '$checkout'."
            }
            & git init --quiet $checkout
            if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the standalone binding checkout.' }
            & git -C $checkout remote add origin $pin.repository
            if ($LASTEXITCODE -ne 0) { throw 'Could not set the standalone binding remote.' }
        }
        $remote = & git -C $checkout remote get-url origin
        if ($LASTEXITCODE -ne 0 -or $remote -cne $pin.repository) { throw "Binding checkout origin does not match the pin: '$checkout'." }
        $changes = & git -C $checkout status --porcelain --untracked-files=normal
        if ($LASTEXITCODE -ne 0 -or $changes) { throw "Binding checkout must be clean: '$checkout'." }
        $head = & git -C $checkout rev-parse --verify --quiet HEAD
        if ($LASTEXITCODE -ne 0 -or $head -cne $pin.commit) {
            & git -C $checkout fetch --quiet --depth 1 origin $pin.commit
            if ($LASTEXITCODE -ne 0) { throw "Could not fetch pinned odin-accesskit commit '$($pin.commit)'." }
            & git -C $checkout -c advice.detachedHead=false checkout --quiet --detach $pin.commit
            if ($LASTEXITCODE -ne 0) { throw 'Could not check out the pinned standalone binding.' }
        }
        $head = & git -C $checkout rev-parse --verify HEAD
        if ($LASTEXITCODE -ne 0 -or $head -cne $pin.commit) { throw 'Standalone binding HEAD does not match the pin.' }
        return [pscustomobject]@{ Root = $checkout; Repository = $pin.repository; Commit = $pin.commit }
    } finally { $lock.Dispose() }
}

function Get-AlicornAccessKit {
    $ErrorActionPreference = 'Stop'
    $binding = Get-AlicornAccessKitBinding
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $native = & (Join-Path $binding.Root 'tools\bootstrap.ps1') -CacheRoot (Join-Path $repoRoot '.deps\accesskit')
    if (-not $native -or -not $native.Root -or -not $native.Archive -or -not $native.Library -or
        -not $native.LibraryDirectory -or -not $native.CompilerArguments) {
        throw 'Standalone AccessKit bootstrap must return Root, Archive, Library, LibraryDirectory, LinkerFlags, and CompilerArguments.'
    }
    $native | Add-Member -NotePropertyName BindingRoot -NotePropertyValue $binding.Root
    $native | Add-Member -NotePropertyName BindingRepository -NotePropertyValue $binding.Repository
    $native | Add-Member -NotePropertyName BindingCommit -NotePropertyValue $binding.Commit
    $native.CompilerArguments = @("-collection:accesskit=$($binding.Root)") + @($native.CompilerArguments)
    return $native
}
