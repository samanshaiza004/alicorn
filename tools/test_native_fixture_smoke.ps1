param(
	[string]$Odin,
	[int]$TimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$Odin = Resolve-AlicornOdin -Requested $Odin
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Wrapper = Join-Path $PSScriptRoot 'native_sdl_gpu.ps1'
$PowerShell = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
if ($TimeoutSeconds -lt 1) { throw 'TimeoutSeconds must be positive.' }

$cases = @(
	[pscustomobject]@{ Name = 'windows-titlebar'; Flags = @('-WindowsTitlebarFixture', '-Smoke') },
	[pscustomobject]@{ Name = 'million-row-accessibility'; Flags = @('-MillionRowAccessibility', '-Smoke') }
)
$logRoot = Join-Path $RepoRoot 'out\native-fixture-smoke'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

foreach ($case in $cases) {
	$startInfo = [Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $PowerShell
	$startInfo.WorkingDirectory = $RepoRoot
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $false
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $Wrapper, '-Odin', $Odin) + $case.Flags) {
		$startInfo.ArgumentList.Add($argument)
	}
	$process = [Diagnostics.Process]::new()
	$process.StartInfo = $startInfo
	$stdoutPath = Join-Path $logRoot "$($case.Name).stdout.log"
	$stderrPath = Join-Path $logRoot "$($case.Name).stderr.log"
	$timer = [Diagnostics.Stopwatch]::StartNew()
	try {
		if (-not $process.Start()) { throw "Could not start $($case.Name) smoke fixture." }
		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()
		if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
			$process.Kill($true)
			$process.WaitForExit()
			throw "$($case.Name) smoke fixture exceeded $TimeoutSeconds seconds and was terminated."
		}
		$process.WaitForExit()
		$timer.Stop()
		$stdout = $stdoutTask.GetAwaiter().GetResult()
		$stderr = $stderrTask.GetAwaiter().GetResult()
		[IO.File]::WriteAllText($stdoutPath, $stdout)
		[IO.File]::WriteAllText($stderrPath, $stderr)
		if ($process.ExitCode -ne 0) {
			throw "$($case.Name) smoke fixture exited $($process.ExitCode). Logs: $stdoutPath, $stderrPath"
		}
		Write-Host "$($case.Name) smoke fixture passed in $([Math]::Round($timer.Elapsed.TotalSeconds, 2))s."
	} finally {
		if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
		$process.Dispose()
	}
}
