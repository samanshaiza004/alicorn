param(
    [string]$Odin = 'C:\Users\saman\Documents\odin\dist\odin.exe',
    [string]$Executable = 'out\secondary-motion-validation\AlicornMotionSecondaryValidation.exe',
    [int]$QuietSeconds = 2,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $exePath = Join-Path $repo $Executable
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Validation executable not found: $exePath"
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class SecondaryMotionWin32 {
    private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    public static IntPtr FindWindow(int wantedProcessId, string wantedTitle) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hwnd, ignored) => {
            uint processId;
            GetWindowThreadProcessId(hwnd, out processId);
            if ((int)processId != wantedProcessId) return true;
            StringBuilder text = new StringBuilder(512);
            GetWindowText(hwnd, text, text.Capacity);
            if (String.Equals(text.ToString(), wantedTitle, StringComparison.Ordinal)) {
                found = hwnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static bool ArrangeSideBySide(IntPtr primary, IntPtr secondary) {
        int screenWidth = GetSystemMetrics(0);
        int screenHeight = GetSystemMetrics(1);
        RECT primaryRect, secondaryRect;
        if (primary == IntPtr.Zero || secondary == IntPtr.Zero || !GetWindowRect(primary, out primaryRect) || !GetWindowRect(secondary, out secondaryRect)) return false;
        int primaryWidth = primaryRect.Right-primaryRect.Left;
        int primaryHeight = primaryRect.Bottom-primaryRect.Top;
        int secondaryWidth = secondaryRect.Right-secondaryRect.Left;
        int secondaryHeight = secondaryRect.Bottom-secondaryRect.Top;
        const uint flags = 0x0001 | 0x0004 | 0x0010; // SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
        int secondaryX = 8+primaryWidth+8;
        int secondaryY = 8;
        if (secondaryX+secondaryWidth > screenWidth-8) {
            if (primaryHeight+secondaryHeight+24 > screenHeight) return false;
            secondaryX = 8;
            secondaryY = 8+primaryHeight+8;
        }
        bool first = SetWindowPos(primary, IntPtr.Zero, 8, 8, 0, 0, flags);
        bool second = SetWindowPos(secondary, IntPtr.Zero, secondaryX, secondaryY, 0, 0, flags);
        return first && second;
    }
}
'@

    function Read-Events([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { return @() }
        $items = @()
        foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $items += ($line | ConvertFrom-Json -ErrorAction Stop) } catch { }
        }
        return $items
    }

    function Wait-Event([System.Diagnostics.Process]$Process, [string]$EventsPath, [string]$Name, [int]$TimeoutSeconds, [int]$WindowId = -1) {
        $until = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $until) {
            $all = Read-Events $EventsPath
            $found = @($all | Where-Object {
                $_.event -eq $Name -and ($WindowId -lt 0 -or [int]$_.window.id -eq $WindowId)
            })
            if ($found.Count -gt 0) { return $found[-1] }
            if ($Process.HasExited) {
                $out = Get-Content -LiteralPath $script:stdoutPath -Raw -ErrorAction SilentlyContinue
                $err = Get-Content -LiteralPath $script:stderrPath -Raw -ErrorAction SilentlyContinue
                throw "Fixture exited with code $($Process.ExitCode) while waiting for '$Name'.`n$out`n$err"
            }
            Start-Sleep -Milliseconds 100
        }
        throw "Timed out waiting for event '$Name'."
    }

    function Get-AppValue([object[]]$Events, [string]$Name) {
        $match = @($Events | Where-Object { $_.source -eq 'application' -and $_.event -eq $Name })
        if ($match.Count -eq 0) { return $null }
        return [uint64]$match[-1].request_id
    }

    function Wait-AppValue([System.Diagnostics.Process]$Process, [string]$EventsPath, [string]$Name, [int]$TimeoutSeconds) {
        $until = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $until) {
            $events = Read-Events $EventsPath
            $value = Get-AppValue $events $Name
            if ($null -ne $value) { return [uint64]$value }
            if ($Process.HasExited) {
                $out = Get-Content -LiteralPath $script:stdoutPath -Raw -ErrorAction SilentlyContinue
                $err = Get-Content -LiteralPath $script:stderrPath -Raw -ErrorAction SilentlyContinue
                throw "Fixture exited with code $($Process.ExitCode) while waiting for '$Name'.`n$out`n$err"
            }
            Start-Sleep -Milliseconds 100
        }
        throw "Timed out waiting for application event '$Name'."
    }

    function Start-Scenario([ValidateSet('restore', 'close')][string]$Mode) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $scenarioRoot = Join-Path $repo "out\issue-146\secondary-windows\$stamp-$Mode"
        $captureRoot = Join-Path $scenarioRoot 'capture'
        New-Item -ItemType Directory -Force -Path $captureRoot | Out-Null
        $script:stdoutPath = Join-Path $scenarioRoot 'stdout.txt'
        $script:stderrPath = Join-Path $scenarioRoot 'stderr.txt'
        $arguments = @('--diagnostic-events', "--capture-dir=$captureRoot")
        if ($Mode -eq 'close') { $arguments += '--validation-mode=close' }
        $process = Start-Process -FilePath $exePath -ArgumentList $arguments -WorkingDirectory (Split-Path $exePath) -PassThru -RedirectStandardOutput $script:stdoutPath -RedirectStandardError $script:stderrPath
        try {
            $eventsPath = $null
            $until = [DateTime]::UtcNow.AddSeconds(15)
            while ([DateTime]::UtcNow -lt $until -and -not $process.HasExited) {
                $candidate = @(Get-ChildItem -LiteralPath $captureRoot -Filter events.jsonl -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($candidate.Count -gt 0) { $eventsPath = $candidate[0].FullName; break }
                Start-Sleep -Milliseconds 100
            }
            if (-not $eventsPath) { throw 'Breadcrumb event log was not created.' }

            $primaryReady = Wait-AppValue $process $eventsPath 'motion.validation.primary.ready.samples' 15
            $secondaryReady = Wait-AppValue $process $eventsPath 'motion.validation.secondary.ready.samples' 15
            if ($primaryReady -le 0 -or $secondaryReady -le 0) { throw 'Both windows must be actively sampling before minimization.' }

            $primaryHwnd = [SecondaryMotionWin32]::FindWindow($process.Id, 'Alicorn #146 Primary')
            $secondaryHwnd = [SecondaryMotionWin32]::FindWindow($process.Id, 'Alicorn #146 Secondary')
            if (-not [SecondaryMotionWin32]::ArrangeSideBySide($primaryHwnd, $secondaryHwnd)) {
                throw 'Could not place both fixture windows visibly side by side on this display.'
            }
            [void][SecondaryMotionWin32]::ShowWindow($secondaryHwnd, 6) # SW_MINIMIZE
            $suspended = Wait-Event $process $eventsPath 'motion.window.suspended' 10
            $childId = [int]$suspended.window.id
            if (-not $suspended.scheduler.suspended -or -not $suspended.window.native_minimized) {
                throw 'The secondary window did not report active-motion suspension with native minimized state.'
            }

            $primaryHidden = Wait-AppValue $process $eventsPath 'motion.validation.primary.hidden.samples' 10
            $secondaryHidden = Wait-AppValue $process $eventsPath 'motion.validation.secondary.hidden.samples' 10
            $suspendedSamples = [uint64]$suspended.scheduler.samples
            if ($primaryHidden -le $primaryReady) { throw 'The primary window did not continue sampling while the secondary was minimized.' }
            $summary = [ordered]@{
                mode = $Mode
                process_id = $process.Id
                events = $eventsPath
                secondary_window_id = $childId
                primary_samples_ready = $primaryReady
                primary_samples_hidden = $primaryHidden
                secondary_samples_ready = $secondaryReady
                secondary_samples_at_suspend = $suspendedSamples
                secondary_runtime_sample_ticks_hidden = $secondaryHidden
                secondary_scheduler_samples_at_suspend = $suspendedSamples
                secondary_restore_samples = $null
                outcome = $null
            }

            if ($Mode -eq 'restore') {
                if (-not [SecondaryMotionWin32]::IsWindow($secondaryHwnd)) { throw 'Secondary window disappeared before restore.' }
                [void][SecondaryMotionWin32]::ShowWindow($secondaryHwnd, 9) # SW_RESTORE
                $restored = Wait-Event $process $eventsPath 'motion.window.restored' 10 $childId
                $summary.secondary_restore_samples = [uint64]$restored.scheduler.restore_samples
                if ($summary.secondary_restore_samples -ne 1) { throw "Expected exactly one restore sample, got $($summary.secondary_restore_samples)." }
                if ([uint64]$restored.scheduler.samples -ne ($suspendedSamples + 1)) {
                    throw 'Restore did not take exactly one current-time sample.'
                }

                $idleDeadline = [DateTime]::UtcNow.AddSeconds(30)
                $idleById = @{}
                while ([DateTime]::UtcNow -lt $idleDeadline -and $idleById.Count -lt 2) {
                    foreach ($event in (Read-Events $eventsPath | Where-Object { $_.event -eq 'motion.window.idle' })) {
                        $idleById[[string]$event.window.id] = $event
                    }
                    if ($process.HasExited) { throw 'Fixture exited before both windows reached motion idle.' }
                    Start-Sleep -Milliseconds 100
                }
                if ($idleById.Count -lt 2) { throw 'Both independent windows did not emit a motion-idle snapshot.' }
                $secondaryIdle = $idleById[[string]$childId]
                if ($null -eq $secondaryIdle -or $secondaryIdle.scheduler.active) { throw 'The restored secondary has no settled idle snapshot.' }
                $primaryIdle = $idleById.Values | Where-Object { [int]$_.window.id -ne $childId } | Select-Object -Last 1
                if ($null -eq $primaryIdle -or $primaryIdle.scheduler.active) { throw 'The primary has no settled idle snapshot.' }
                $summary.primary_window_id = [int]$primaryIdle.window.id
                $summary.primary_idle_samples = [uint64]$primaryIdle.scheduler.samples
                $summary.primary_idle_submissions = [uint64]$primaryIdle.scheduler.host_gpu_submissions
                $summary.secondary_idle_samples = [uint64]$secondaryIdle.scheduler.samples
                $summary.secondary_idle_submissions = [uint64]$secondaryIdle.scheduler.host_gpu_submissions
                $summary.outcome = 'secondary restored with one current-time sample; both windows settled independently'
            } else {
                if (-not [SecondaryMotionWin32]::IsWindow($secondaryHwnd) -or -not [SecondaryMotionWin32]::IsIconic($secondaryHwnd)) {
                    throw 'Secondary must remain minimized when it is closed during active motion.'
                }
                [void][SecondaryMotionWin32]::PostMessage($secondaryHwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) # WM_CLOSE
                $null = Wait-Event $process $eventsPath 'motion.validation.secondary.stopped' 10
                $closed = Wait-Event $process $eventsPath 'motion.window.closed' 5 $childId
                if ([int]$closed.runtime.active_owners -ne 1 -or -not $closed.scheduler.suspended -or -not $closed.window.native_minimized) {
                    throw 'The close snapshot did not capture one active owner in a suspended, natively minimized secondary.'
                }
                if ([uint64]$closed.scheduler.samples -ne $suspendedSamples) {
                    throw 'The minimized secondary took a scheduler sample after suspension and before close.'
                }
                $summary.secondary_close_active_owners = [int]$closed.runtime.active_owners
                $summary.secondary_close_samples = [uint64]$closed.scheduler.samples
                $summary.secondary_close_submissions = [uint64]$closed.scheduler.host_gpu_submissions
                $all = Read-Events $eventsPath
                if (@($all | Where-Object { $_.event -eq 'motion.window.restored' -and [int]$_.window.id -eq $childId }).Count -gt 0) {
                    throw 'Closed secondary unexpectedly emitted a restore event.'
                }
                $primarySettled = $false
                $settleDeadline = [DateTime]::UtcNow.AddSeconds(20)
                while ([DateTime]::UtcNow -lt $settleDeadline) {
                    $all = Read-Events $eventsPath
                    $latestOwners = Get-AppValue $all 'motion.validation.primary.post_close.owners'
                    if ($null -ne $latestOwners -and $latestOwners -eq 0) { $primarySettled = $true; break }
                    if ($process.HasExited) { throw 'Fixture exited before the primary completed its post-close checkpoints.' }
                    Start-Sleep -Milliseconds 100
                }
                if (-not $primarySettled) { throw 'Primary motion remained active after closing the secondary.' }
                $primaryIdle = Wait-Event $process $eventsPath 'motion.window.idle' 5
                while ([int]$primaryIdle.window.id -eq $childId) {
                    Start-Sleep -Milliseconds 100
                    $primaryIdle = Wait-Event $process $eventsPath 'motion.window.idle' 2
                }
                if ($primaryIdle.scheduler.active) { throw 'Primary did not reach motion idle after child shutdown.' }
                $summary.primary_idle_samples = [uint64]$primaryIdle.scheduler.samples
                $summary.primary_idle_submissions = [uint64]$primaryIdle.scheduler.host_gpu_submissions
                $summary.outcome = 'minimized secondary closed during motion; primary continued to settle'
            }

            $eventCountBeforeQuiet = (Read-Events $eventsPath).Count
            Start-Sleep -Seconds $QuietSeconds
            $eventsBeforeClose = Read-Events $eventsPath
            if ($eventsBeforeClose.Count -ne $eventCountBeforeQuiet) {
                throw 'A diagnostic event arrived during the post-settlement quiet interval.'
            }
            if ($Mode -eq 'restore') {
                foreach ($windowId in @($idleById.Keys)) {
                    $latest = @($eventsBeforeClose | Where-Object { $_.event -eq 'motion.window.idle' -and [string]$_.window.id -eq [string]$windowId })[-1]
                    if ($null -eq $latest -or $latest.scheduler.active) { throw "Window $windowId was not idle during the quiet interval." }
                }
            }
            $summary.quiet_seconds = $QuietSeconds
            $summary.event_count_after_quiet = $eventsBeforeClose.Count
            $summary.outcome += '; quiet interval completed'

            $primaryHwnd = [SecondaryMotionWin32]::FindWindow($process.Id, 'Alicorn #146 Primary')
            if ($primaryHwnd -ne [IntPtr]::Zero) {
                [void][SecondaryMotionWin32]::PostMessage($primaryHwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
            }
            if (-not $process.WaitForExit(10000)) {
                $process.Kill()
                throw 'Fixture did not shut down after closing the primary window.'
            }
            $stdout = Get-Content -LiteralPath $script:stdoutPath -Raw -ErrorAction SilentlyContinue
            if ($stdout -notmatch 'SDL application PASS') { throw "Native host did not report a clean PASS exit.`n$stdout" }
            $summary.host_exit_code = $process.ExitCode
            $summary.host_summary = ($stdout -split "`r?`n" | Where-Object { $_ -match 'SDL application PASS' } | Select-Object -Last 1)
            if ($summary.host_summary -notmatch 'primary_gpu_submissions (\d+)') { throw 'Could not parse the primary-window GPU-submission total.' }
            $hostSubmissions = [uint64]$Matches[1]
            if ($summary.host_summary -notmatch 'motion_samples (\d+)') { throw 'Could not parse the host motion-sample total.' }
            $hostMotionSamples = [uint64]$Matches[1]
            if ($summary.primary_idle_submissions -ne $hostSubmissions -or $summary.primary_idle_samples -ne $hostMotionSamples) {
                throw 'Primary idle snapshot counters do not match the final native host totals.'
            }
            $summary.outcome += '; clean host shutdown'
            $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'result.json') -Encoding utf8
            Write-Output ($summary | ConvertTo-Json -Depth 6)
            Write-Output "Artifacts: $scenarioRoot"
        } catch {
            $primaryHwnd = [SecondaryMotionWin32]::FindWindow($process.Id, 'Alicorn #146 Primary')
            if ($primaryHwnd -ne [IntPtr]::Zero) { [void][SecondaryMotionWin32]::PostMessage($primaryHwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
            if (-not $process.HasExited -and -not $process.WaitForExit(3000)) { $process.Kill() }
            throw
        } finally {
            $process.Dispose()
        }
    }

    if (-not $SkipBuild) {
        . .\tools\common.ps1
        $odinPath = Resolve-AlicornOdin -Requested $Odin
        $accesskit = Get-AlicornAccessKit
        $buildOutput = Split-Path $exePath
        New-Item -ItemType Directory -Force -Path $buildOutput | Out-Null
        & $odinPath build tests\fixtures\secondary_motion "-collection:alicorn=$repo" @($accesskit.CompilerArguments) "-out:$exePath" -o:speed
        if ($LASTEXITCODE -ne 0) { throw "Secondary motion fixture build failed: $LASTEXITCODE" }
        $sdl3Path = Join-Path (Split-Path -Parent $odinPath) 'vendor\sdl3\SDL3.dll'
        if (-not (Test-Path -LiteralPath $sdl3Path -PathType Leaf)) { throw "SDL3.dll not found at '$sdl3Path'." }
        Copy-Item -LiteralPath $sdl3Path -Destination $buildOutput -Force
    }

    Start-Scenario 'restore'
    Start-Scenario 'close'
} finally {
    Pop-Location
}
