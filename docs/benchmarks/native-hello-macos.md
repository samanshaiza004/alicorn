# Native hello: macOS performance sample

Captured 2026-10-02 CDT at Alicorn
`f35c2a02e5359d5346a05dad6cc5e11965c2c812` on a MacBookAir10,1 with Apple M1,
8 logical CPUs, 8 GiB RAM, and macOS 27.0 (26A428). Odin was
`dev-2026-09-nightly:a2fb372`. The actual linked SDL version was 3.4.16 and the
requested and selected GPU driver was Metal.

This is a small physical-Mac sample of the existing native counter. It is not
a Scratchpad benchmark, a resource soak, or a general latency guarantee.

## Build and run

```sh
odin build examples/native_hello -o:speed -out:out/alicorn_native_hello_perf
./out/alicorn_native_hello_perf --idle-validation-seconds=25
```

The 25-second limit is the existing host validation deadline and exits through
normal shutdown. Compilation was completed before measurement. The window
was 720 × 480 logical units, with a 1440 × 960 drawable and density/display
scale 2. The developer desktop remained running; other system load was not
controlled. The executable was **3,492,344 bytes (3.33 MiB)**. It dynamically
links `/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib` and system frameworks, so
that size excludes those dependencies and packaging.

## Idle observation

The first attempt submitted 172 frames in 25 seconds and used 8.831% of one
core between seconds 5 and 20. The operator later confirmed they were
interacting with the window, so this was not an idle run and is excluded from
the idle result. It remains in the raw log only for traceability.

A second run requested existing diagnostics no earlier than 20 host-loop seconds:

```sh
./out/alicorn_native_hello_perf --idle-validation-seconds=25 \
    --capture-after=20 --capture-dir=out/native-hello-idle-perf
```

The capture request does not add its own event-loop wake deadline. It was
processed near the final 25-second timeout, rather than waking the app at
exactly 20 seconds.

This run recorded 11 pointer events, so it also is not used as the no-input
idle result. It is retained as an auxiliary diagnostic trace: those events
caused no additional application builds or submissions. At shutdown, the
host reported one submitted and retired frame, one text-mesh rebuild, zero
application ticks, and 26 event waits over 25.002 seconds.

The final 25-second run was made with the window left untouched and without
diagnostic capture:

```sh
./out/alicorn_native_hello_perf --idle-validation-seconds=25
```

`ps -p <pid> -o rss=,time=` sampled resident size and aggregate process CPU
time, which has centisecond precision. CPU percentage below is the change in
process CPU time divided by wall time, with 100% meaning one core.

| Elapsed from process launch | Resident size | Process CPU time |
|---|---:|---:|
| 5.066 s | 89,520 KiB (87.42 MiB) | 0.54 s |
| 20.006 s | 84,016 KiB (82.05 MiB) | 0.54 s |

`ps` reports CPU time to centiseconds. No CPU-time change was visible over
14.940 seconds, corresponding to **less than 0.07% of one core at this
measurement resolution**, not proof of literally zero CPU use. RSS fell by
5.38 MiB. At shutdown, this untouched run reported one submitted and retired
frame, one text-mesh rebuild, zero input events, zero application ticks, and
two event waits over 25.000 seconds. RSS is neither physical footprint nor
Alicorn-owned live allocation accounting; this short sample does not certify
long-term memory stability or zero idle wakeups.

## Startup observation

A separate fresh process requested diagnostics after its first submitted
frame and exited after three host-loop seconds. Two launches were observed
with an external monotonic clock; cache state was not controlled, so these
are individual observations, not a benchmark distribution:

| Marker | Earlier run | Repeat run |
|---|---:|---:|
| GPU driver selected | 1.049 s | 0.228 s |
| First-frame diagnostics log | 1.730 s | 0.668 s |

The second marker follows the first swapchain submission and includes
diagnostic serialization and file-output overhead. It precedes the separate
offscreen screenshot. It is **not time to the first visible pixel**. These
observations support no cold-start or median startup claim. Both hosts passed
normal shutdown with one submitted and retired application frame, and the
repeat was left untouched and recorded zero input events.

## Raw evidence

- [Idle attempts and both startup probes](raw/native-hello-macos-m1-2026-10-02.txt)
- [Auxiliary diagnostic JSON (11 pointer events; not no-input idle evidence)](raw/native-hello-idle-macos-m1-2026-10-02.json)
- [Auxiliary flight-recorder timeline](raw/native-hello-idle-timeline-macos-m1-2026-10-02.json)

Frame and event-pump wall times include time spent waiting for input. They
must not be interpreted as active CPU render cost during idle. The native
sample supports one bounded idle submission path and provides an explicitly
limited CPU/RSS/startup baseline; the separate
[wrapped-text benchmark](text-layout.md) measures headless layout work.
