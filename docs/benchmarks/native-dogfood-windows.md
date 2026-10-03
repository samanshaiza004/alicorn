# Native and dogfood performance sample: Windows

Captured 2026-10-03 on the v0.1.0 candidate. This report separates the
current Alicorn native host from three independently versioned dogfood apps.
All measurements were produced by the project author; they are reproducible
local evidence, not independent validation or a cross-framework comparison.

## Environment

| Item | Environment |
|---|---|
| OS | Windows 10 Home 22H2, build 19045.6466 |
| CPU / logical processors | AMD Ryzen 5 7600X / 12 |
| Installed memory visible to Monitor | 15.2 GB |
| Odin | `dev-2026-09-nightly:a2fb372` |
| Native host | SDL 3.4.2, Direct3D 12 |
| Alicorn candidate for the core samples | `7c5e812` |
| Native hello build | `-o:speed`; 720 × 480 logical/pixel window; display scale 1.0 |

The native hello executable was 3,876,352 bytes (3.70 MiB). Its adjacent
`SDL3.dll` was 2,790,400 bytes (2.66 MiB); the executable size excludes that
dynamic dependency, Windows system libraries, and packaging. Monitor and
History used their checked-in default Odin profile; Scope's frontend used
`-o:speed` after its Go/Rust dependencies were built. These app builds are not
equivalent to the headless benchmark executables.

## Native hello: idle, memory, startup

The untouched app ran for the host's bounded 25-second validation interval.
Process CPU time and resident/private bytes were sampled externally with
`Get-Process` at two elapsed times. The reported CPU clock has 10 ms
resolution, so a zero delta only yields an upper bound. Working set is
resident memory; private bytes are private committed memory and should not be
read as an equivalent physical-memory measure.

The process counters can be sampled with this PowerShell pattern while the
25-second process is running:

```powershell
$process = Start-Process .\out\alicorn_native_hello_perf.exe -ArgumentList '--idle-validation-seconds=25' -PassThru
$started = [DateTimeOffset]::Now
foreach ($target in @(5, 20)) {
    $remaining = $target - ([DateTimeOffset]::Now - $started).TotalSeconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int]($remaining * 1000)) }
    $sample = Get-Process -Id $process.Id
    [pscustomobject]@{
        Elapsed = ([DateTimeOffset]::Now - $started).TotalSeconds
        WorkingSetBytes = $sample.WorkingSet64
        PrivateBytes = $sample.PrivateMemorySize64
        CpuSeconds = $sample.CPU
    }
}
$process.WaitForExit()
```

| Elapsed | Working set | Private bytes | Process CPU time |
|---:|---:|---:|---:|
| 5.085 s | 116,363,264 B (111.0 MiB) | 161,488,896 B (154.0 MiB) | 0.297 s |
| 20.009 s | 113,983,488 B (108.7 MiB) | 159,977,472 B (152.6 MiB) | 0.297 s |

The 14.924-second interval had no visible CPU-time change. At the process
counter's 10 ms resolution this is **less than 0.07% of one core**, not proof
of literally zero CPU use. At normal shutdown the host reported one submitted
and retired GPU frame, zero input events, zero application ticks, zero
application wake events, and one event wait over 25 seconds. It therefore
made no further GPU submissions during this idle interval.

Three fresh short launches measured time from `Start-Process` to creation of
the first-frame diagnostics JSON. That marker occurs after the first GPU
submission and includes diagnostic output; it is not first visible pixel or
cold-start-to-interactive latency.

| Probe | Launch to post-submit diagnostics marker |
|---:|---:|
| 1 | 0.416 s |
| 2 | 0.379 s |
| 3 | 0.363 s |

Median: 0.379 s; range: 0.363–0.416 s. Cache state was uncontrolled, so this
is a small set of observations rather than a startup distribution.

## Dogfood applications

Each run used the repository's bounded `--smoke` path on the same Windows
host. Process counters are external snapshots during app startup/load; these
short runs are not steady-state memory or idle CPU tests. The Monitor workload
observes the live process table and system, so its row counts and CPU values
are expected to vary. History and Scope use bounded, reproducible input sizes.

| App / source revision | Workload and result | Process samples (working set / private bytes) |
|---|---|---|
| Monitor `16e5cfc`; Alicorn dependency `71b6213` | Live system/process snapshot; 111 rows in the last sample; 12 samples; 16 GPU submissions in a 3.0 s host interval; clean exit in 3.67 s | 1.02 s: 114,434,048 / 154,578,944 B; 2.21 s: 115,855,360 / 155,971,584 B |
| History `87250cb`; Alicorn dependency `cc0274b` | Local repository with 27 commits; selected first commit; 8 builds, 1 result; 7 submissions in a 3.0 s host interval; clean exit in 3.76 s | 1.02 s: 121,536,512 / 170,262,528 B; 2.21 s: unchanged |
| Scope `e80d800`; Alicorn dependency `5147a63` | Deterministic 100,000-event Chrome Trace fixture (7,888,912 B); 512 events cached; 5 builds, 4 resource copies; 4 submissions in a 3.02 s host interval; clean exit in 4.02 s | 1.12 s: 155,836,416 / 250,339,328 B; 2.21 s: unchanged |

Each dogfood app pins a different Alicorn revision, recorded in the linked raw
capture. Those app numbers describe the checked-in dogfood revisions; they
must not be attributed to Alicorn `7c5e812` or compared directly against the
native hello sample. The short Monitor/History/Scope smokes end while their
initial workload is still active. Only native hello above is used for the
controlled idle CPU/submission claim. Monitor's scheduled sampling is part of
the workload rather than an idle/no-sampler condition: this run recorded 12
process snapshots in about three seconds (roughly 4 Hz). The app runs recorded
no input, so they do not characterize interactive deferral or lateness.

## Reproduce

From a fresh Alicorn checkout, build and run the current native hello app:

```powershell
New-Item -ItemType Directory -Force out | Out-Null
odin build examples/01_hello -o:speed -out:out/alicorn_native_hello_perf.exe
Copy-Item (Join-Path (Split-Path -Parent (Get-Command odin).Source) 'vendor\sdl3\SDL3.dll') out\SDL3.dll -Force
.\out\alicorn_native_hello_perf.exe --idle-validation-seconds=25
```

For startup probes, run three fresh processes with a five-second limit and
distinct capture directories:

```powershell
1..3 | ForEach-Object {
    $capture = "out/native-hello-startup-$_"
    .\out\alicorn_native_hello_perf.exe --idle-validation-seconds=5 --capture-after=0 "--capture-dir=$capture"
}
```

Monitor's documented Windows command is `tools/run.ps1 -Smoke`. History's
captured command rebuilds using the launcher's profile and runs the executable
with the repository root, `--select-first --smoke`:

```powershell
odin build . -out:out\alicorn-history.exe
Copy-Item (Join-Path (Split-Path -Parent (Get-Command odin).Source) 'vendor\sdl3\SDL3.dll') out\SDL3.dll -Force
.\out\alicorn-history.exe (Get-Location).Path --select-first --smoke
```

To collect process memory/CPU snapshots while a smoke runs, launch the built
executable with `Start-Process -PassThru`, sample
`Get-Process -Id $process.Id` at elapsed seconds 1 and 2.2, then wait for its
exit code. Raw captures below include the exact app revisions, arguments,
sample counters, and captured stdout.

The Scope fixture can be recreated from the Scope repository root with the
script added for this report:

```powershell
& 'C:\path\to\alicorn\tools\bench_scope_fixture.ps1' -OutputPath 'out\perf-100k-trace.json'
Get-FileHash out\perf-100k-trace.json -Algorithm SHA256
```

It writes a compact trace with 100,000 `X` events and no timestamps outside
the event records. The expected SHA-256 is
`199679E2DCAA39FD94EEDC2E0B3B0C05D55A06DAB53E6BEC1AD688ADBC4695CB`.

Build the Go/Rust dependencies and optimized frontend from the Scope repository
root, using the locked Alicorn collection path returned by
`tools/bootstrap.ps1`:

```powershell
.\tools\build.ps1
$deps = & .\tools\bootstrap.ps1
odin build . "-collection:alicorn=$($deps.AlicornRoot)" -o:speed -out:out\alicorn-scope-perf.exe
.\out\alicorn-scope-perf.exe --smoke .\out\perf-100k-trace.json
```

## Raw evidence

- [Native hello 25-second run](raw/native-hello-windows-2026-10-03.txt)
- [Three startup probes](raw/native-hello-startup-windows-2026-10-03.txt)
- [First-frame diagnostics JSON](raw/native-hello-windows-diagnostics-2026-10-03.json)
- [Monitor smoke](raw/monitor-windows-2026-10-03.txt)
- [History smoke](raw/history-windows-2026-10-03.txt)
- [Scope smoke](raw/scope-windows-2026-10-03.txt)
