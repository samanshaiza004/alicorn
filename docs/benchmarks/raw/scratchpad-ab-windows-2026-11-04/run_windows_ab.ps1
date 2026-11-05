param(
    [Parameter(Mandatory = $true)][string]$BenchmarkRoot,
    [Parameter(Mandatory = $true)][string]$ScratchpadRoot,
    [Parameter(Mandatory = $true)][string]$BaselineExe,
    [Parameter(Mandatory = $true)][string]$CandidateExe,
    [Parameter(Mandatory = $true)][string]$ResultsDirectory,
    [int]$Runs = 7,
    [int]$Warmups = 1,
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$BenchmarkRoot = [System.IO.Path]::GetFullPath($BenchmarkRoot)
$ScratchpadRoot = [System.IO.Path]::GetFullPath($ScratchpadRoot)
$ResultsDirectory = [System.IO.Path]::GetFullPath($ResultsDirectory)
$BaselineExe = [System.IO.Path]::GetFullPath($BaselineExe)
$CandidateExe = [System.IO.Path]::GetFullPath($CandidateExe)
if ($Runs -lt 1 -or $Warmups -lt 0 -or $TimeoutSeconds -lt 1) { throw 'Invalid run, warmup, or timeout count.' }
New-Item -ItemType Directory -Force -Path $ResultsDirectory | Out-Null

$workspace = Join-Path $ResultsDirectory 'workspace'
New-Item -ItemType Directory -Force -Path $workspace | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $workspace 'README.md'), "# Scratchpad Windows A/B fixture`n`nGenerated disposable benchmark workspace.`n", $utf8)
$folders = @('application', 'editor', 'document', 'runtime', 'tests', 'docs', 'themes', 'tools')
$extensions = @('.go', '.odin', '.md', '.json', '.txt', '.ts')
foreach ($folderIndex in 0..($folders.Length - 1)) {
    $folder = $folders[$folderIndex]
    $directory = Join-Path $workspace $folder
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    foreach ($fileIndex in 0..23) {
        $extension = $extensions[($folderIndex + $fileIndex) % $extensions.Length]
        $name = 'sample_{0:D2}{1}' -f $fileIndex, $extension
        $path = Join-Path $directory $name
        if ($folder -eq 'application' -and $fileIndex -eq 0) {
            $builder = [System.Text.StringBuilder]::new()
            [void]$builder.AppendLine('package sample')
            [void]$builder.AppendLine()
            foreach ($lineIndex in 0..4999) {
                $lineText = 'func GeneratedRow{0:D5}() int {{ return {1} }}' -f $lineIndex, $lineIndex
                [void]$builder.Append($lineText)
                [void]$builder.AppendLine()
            }
            [System.IO.File]::WriteAllText($path, $builder.ToString(), $utf8)
        } else {
            $builder = [System.Text.StringBuilder]::new()
            foreach ($lineIndex in 0..31) {
                $lineText = '// fixture {0}/{1} row {2:D2}' -f $folder, $name, $lineIndex
                [void]$builder.AppendLine($lineText)
            }
            [System.IO.File]::WriteAllText($path, $builder.ToString(), $utf8)
        }
    }
}

function Get-KeyValues([string]$line, [int]$start) {
    $tokens = $line -split '\s+'
    $values = @{}
    for ($i = $start; $i + 1 -lt $tokens.Length; $i += 2) { $values[$tokens[$i]] = $tokens[$i + 1] }
    return $values
}

function Invoke-BenchmarkSample([string]$Label, [string]$Executable, [string]$RunName) {
    $binDirectory = Split-Path -Parent $Executable
    $profile = Join-Path $ResultsDirectory ('profile-{0}-{1}' -f $Label, $RunName)
    New-Item -ItemType Directory -Force -Path $profile | Out-Null
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $binDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['SCRATCHPAD_ALICORN_SMOKE'] = '1'
    $startInfo.Environment['SCRATCHPAD_ALICORN_PERF_SEQUENCE'] = '1'
    $startInfo.Environment['SCRATCHPAD_ALICORN_WORKSPACE'] = $workspace
    $startInfo.Environment['APPDATA'] = $profile
    $startInfo.Environment['LOCALAPPDATA'] = $profile
    $startInfo.Environment['PATH'] = $binDirectory + ';' + $env:PATH
    $startInfo.Environment.Remove('SCRATCHPAD_BACKEND_LIBRARY')
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not $process.Start()) { throw "Could not start $Label $RunName." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $peakWorkingSet = [int64]0
    $timedOut = $false
    while (-not $process.HasExited) {
        $process.Refresh()
        try { $peakWorkingSet = [Math]::Max($peakWorkingSet, [int64]$process.PeakWorkingSet64) } catch { }
        if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $timedOut = $true
            $process.Kill($true)
            break
        }
        Start-Sleep -Milliseconds 10
    }
    $process.WaitForExit()
    $watch.Stop()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $log = $stdout + $stderr
    $logPath = Join-Path $ResultsDirectory ('{0}-{1}.log' -f $Label, $RunName)
    [System.IO.File]::WriteAllText($logPath, $log, $utf8)
    if ($timedOut) { throw "$Label $RunName timed out; see $logPath`n$($log.Substring([Math]::Max(0, $log.Length - 3000)))" }
    if ($process.ExitCode -ne 0) { throw "$Label $RunName exited $($process.ExitCode); see $logPath`n$($log.Substring([Math]::Max(0, $log.Length - 3000)))" }

    $hostLine = @($log -split "`r?`n" | Where-Object { $_.StartsWith('SDL application PASS ') } | Select-Object -Last 1)
    $smokeLine = @($log -split "`r?`n" | Where-Object { $_.StartsWith('alicorn-smoke ') } | Select-Object -Last 1)
    $sequenceLine = @($log -split "`r?`n" | Where-Object { $_.StartsWith('alicorn-performance-sequence ') } | Select-Object -Last 1)
    if ($hostLine.Count -eq 0 -or $smokeLine.Count -eq 0 -or $sequenceLine.Count -eq 0) { throw "$Label $RunName omitted host or sequence acceptance output; see $logPath" }
    $hostFields = Get-KeyValues $hostLine[0] 3
    $smoke = Get-KeyValues $smokeLine[0] 1
    $sequence = Get-KeyValues $sequenceLine[0] 1
    if ($smoke.publication_rendered -ne 'true' -or $smoke.wake_observed -ne 'true' -or $smoke.ordered_shutdown -ne 'true') { throw "$Label $RunName failed smoke acceptance; see $logPath" }
    if ($sequence.steps -ne '9' -or $sequence.complete -ne 'true' -or $sequence.passed -ne 'true') { throw "$Label $RunName failed interaction sequence: $($sequence | ConvertTo-Json -Compress); see $logPath" }
    foreach ($required in @('wall_ns', 'application_build_ns', 'application_build_max_ns', 'first_application_submit_ns', 'primary_gpu_submissions')) {
        if (-not $hostFields.ContainsKey($required)) { throw "$Label $RunName missing host metric $required; see $logPath" }
    }
    if ([int64]$hostFields.first_application_submit_ns -le 0 -or [int64]$hostFields.application_build_max_ns -le 0) { throw "$Label $RunName has zero first-submit or build timing; see $logPath" }
    $process.Refresh()
    $peakWorkingSet = [Math]::Max($peakWorkingSet, [int64]$process.PeakWorkingSet64)
    return [pscustomobject]@{
        candidate = $Label
        run = $RunName
        exit_code = $process.ExitCode
        elapsed_ns = [int64]($watch.Elapsed.TotalMilliseconds * 1000000)
        cpu_total_ns = [int64]($process.TotalProcessorTime.TotalMilliseconds * 1000000)
        peak_working_set_bytes = $peakWorkingSet
        application_build_ns = [int64]$hostFields.application_build_ns
        application_build_max_ns = [int64]$hostFields.application_build_max_ns
        first_application_submit_ns = [int64]$hostFields.first_application_submit_ns
        host_wall_ns = [int64]$hostFields.wall_ns
        gpu_submissions = [int64]$hostFields.primary_gpu_submissions
        log = $logPath
    }
}

$candidates = @(
    [pscustomobject]@{ label = 'v020'; exe = $BaselineExe },
    [pscustomobject]@{ label = 'v021'; exe = $CandidateExe }
)
$samples = [System.Collections.Generic.List[object]]::new()
for ($warmup = 1; $warmup -le $Warmups; $warmup++) {
    foreach ($candidate in $candidates) { $null = Invoke-BenchmarkSample $candidate.label $candidate.exe ('warmup-{0:D2}' -f $warmup) }
}
foreach ($round in 0..($Runs - 1)) {
    $order = if (($round % 2) -eq 0) { $candidates } else { @($candidates[1], $candidates[0]) }
    foreach ($candidate in $order) {
        $sample = Invoke-BenchmarkSample $candidate.label $candidate.exe ('run-{0:D2}' -f ($round + 1))
        $samples.Add($sample)
        Write-Output ('completed {0} {1}: {2:N0} ms, {3:N0} ms app build' -f $sample.candidate, $sample.run, ($sample.elapsed_ns / 1e6), ($sample.application_build_ns / 1e6))
    }
}

$metrics = @('elapsed_ns', 'cpu_total_ns', 'peak_working_set_bytes', 'application_build_ns', 'application_build_max_ns', 'first_application_submit_ns', 'host_wall_ns', 'gpu_submissions')
$summaries = @{}
$sampleArray = [System.Collections.Generic.List[object]]::new()
for ($sampleIndex = 0; $sampleIndex -lt $samples.Count; $sampleIndex++) { [void]$sampleArray.Add($samples[$sampleIndex]) }
foreach ($candidate in $candidates) {
    $own = [System.Collections.Generic.List[object]]::new()
    for ($sampleIndex = 0; $sampleIndex -lt $sampleArray.Count; $sampleIndex++) {
        $sample = $sampleArray[$sampleIndex]
        if ($sample.candidate -eq $candidate.label) { [void]$own.Add($sample) }
    }
    $summary = @{}
    foreach ($metric in $metrics) {
        $ordered = [System.Collections.Generic.List[double]]::new()
        for ($sampleIndex = 0; $sampleIndex -lt $own.Count; $sampleIndex++) {
            $sample = $own[$sampleIndex]
            [void]$ordered.Add([double]($sample.$metric))
        }
        $orderedValues = $ordered.ToArray()
        [Array]::Sort($orderedValues)
        $middle = [int][Math]::Floor($orderedValues.Length / 2)
        $median = if (($orderedValues.Length % 2) -eq 1) { $orderedValues[$middle] } else { ($orderedValues[$middle - 1] + $orderedValues[$middle]) / 2 }
        $summary[$metric] = [pscustomobject]@{ min = $orderedValues[0]; median = $median; max = $orderedValues[-1] }
    }
    $summaries[$candidate.label] = $summary
}
$paired = @{}
foreach ($metric in $metrics) {
    $changes = [System.Collections.Generic.List[double]]::new()
    foreach ($round in 1..$Runs) {
        $runName = 'run-{0:D2}' -f $round
        $beforeSample = $null
        $afterSample = $null
        for ($sampleIndex = 0; $sampleIndex -lt $sampleArray.Count; $sampleIndex++) {
            $sample = $sampleArray[$sampleIndex]
            if ($sample.run -eq $runName -and $sample.candidate -eq 'v020') { $beforeSample = $sample }
            if ($sample.run -eq $runName -and $sample.candidate -eq 'v021') { $afterSample = $sample }
        }
        if ($null -eq $beforeSample -or $null -eq $afterSample) { throw "Missing paired sample for $runName ($metric)" }
        $before = [double]($beforeSample.$metric)
        $after = [double]($afterSample.$metric)
        if ($before -ne 0) { [void]$changes.Add(($after - $before) * 100.0 / $before) }
    }
    $sortedChanges = $changes.ToArray()
    [Array]::Sort($sortedChanges)
    $middle = [int][Math]::Floor($sortedChanges.Length / 2)
    $medianChange = if (($sortedChanges.Length % 2) -eq 1) { $sortedChanges[$middle] } else { ($sortedChanges[$middle - 1] + $sortedChanges[$middle]) / 2 }
    $paired[$metric] = [pscustomobject]@{ median_percent_change = $medianChange; changes = $changes.ToArray() }
}
$hostFacts = [pscustomobject]@{ os = 'Windows 10 Home 22H2'; build = '19045'; computer = $env:COMPUTERNAME; processor = 'AMD Ryzen 5 7600X (12 logical processors)'; gpu = 'NVIDIA GeForce RTX 2080 SUPER' }
try {
    $osFacts = Get-CimInstance Win32_OperatingSystem
    $cpuFacts = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpuFacts = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $hostFacts = [pscustomobject]@{ os = $osFacts.Caption; build = $osFacts.BuildNumber; computer = $env:COMPUTERNAME; processor = $cpuFacts.Name; gpu = $gpuFacts.Name }
} catch { }
$odin = Join-Path $BenchmarkRoot 'toolchain\odin-dev-2026-11\dist\odin.exe'
$report = [pscustomobject]@{
    schema = 1
    scenario = 'nine-action large-document interaction'
    host = $hostFacts
    scratchpad_revision = '751f949c24c0ad3108c201358f7a65b740cd951a'
    caliber_revision = '197cd964cc7265bc60df599a6b8562eac7c75f3a'
    odin_path = $odin
    odin_version = (& $odin version | Out-String).Trim()
    workspace = $workspace
    workspace_file_count = 193
    large_document_lines = 5002
    runs_per_candidate = $Runs
    warmups_per_candidate = $Warmups
    sequence = @('open README.md', 'open application/sample_00.go', 'switch back to README.md', 'open Quick Open', 'close Quick Open after index ready', 'open Settings', 'close Settings', 'close README.md', 'close the remaining Go document')
    candidate_revisions = [pscustomobject]@{ v020 = '24a881590b249c5c166c7864482886fb5aa41653'; v021 = '736277f899b7777d0cf907a1b7c962370d7217b0' }
    build_profile = '-o:speed / release'
    artifacts = [pscustomobject]@{
        v020 = [pscustomobject]@{ binary_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $BaselineExe).Hash; path = $BaselineExe }
        v021 = [pscustomobject]@{ binary_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateExe).Hash; path = $CandidateExe }
    }
    summaries = $summaries
    paired_comparison = $paired
    samples = $samples
}
$jsonPath = Join-Path $ResultsDirectory 'summary.json'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$csvPath = Join-Path $ResultsDirectory 'samples.csv'
$csvColumns = @('candidate', 'run', 'exit_code', 'elapsed_ns', 'cpu_total_ns', 'peak_working_set_bytes', 'application_build_ns', 'application_build_max_ns', 'first_application_submit_ns', 'host_wall_ns', 'gpu_submissions', 'log_file')
$csvRows = [System.Collections.Generic.List[string]]::new()
[void]$csvRows.Add((($csvColumns | ForEach-Object { '"' + $_ + '"' }) -join ','))
for ($sampleIndex = 0; $sampleIndex -lt $sampleArray.Count; $sampleIndex++) {
    $sample = $sampleArray[$sampleIndex]
    $values = @($sample.candidate, $sample.run, $sample.exit_code, $sample.elapsed_ns, $sample.cpu_total_ns, $sample.peak_working_set_bytes, $sample.application_build_ns, $sample.application_build_max_ns, $sample.first_application_submit_ns, $sample.host_wall_ns, $sample.gpu_submissions, [System.IO.Path]::GetFileName($sample.log))
    $cells = @()
    foreach ($value in $values) { $cells += '"' + ([string]$value).Replace('"', '""') + '"' }
    [void]$csvRows.Add(($cells -join ','))
}
[System.IO.File]::WriteAllLines($csvPath, $csvRows, [System.Text.UTF8Encoding]::new($false))
Write-Output "summary: $jsonPath"
