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

The initial attempt submitted 172 frames in 25 seconds and used 8.831% of one
core between seconds 5 and 20. It was visibly active according to its own
counters, so it is retained as an uncontrolled attempt rather than used as
idle evidence. It had no flight-recorder capture; the trigger for those
updates was not established.

A second run requested existing diagnostics no earlier than 20 host-loop seconds:

```sh
./out/alicorn_native_hello_perf --idle-validation-seconds=25 \
    --capture-after=20 --capture-dir=out/native-hello-idle-perf
```

The capture request does not add its own event-loop wake deadline. In this
idle run it was processed near the final 25-second timeout, rather than
waking the app at exactly 20 seconds.

The flight recorder at capture contained one application build, one GPU
submission, and 11 pointer events. Those pointer events caused no additional
application builds or submissions. At normal shutdown, the host reported
**one submitted frame, one retired frame, one text-mesh rebuild, and zero
application ticks** over 25.002 seconds. There were 26 event waits and no
application wake events. The diagnostic offscreen screenshot is separate
work and is excluded from the host's swapchain submission counter.

`ps -p <pid> -o rss=,time=` sampled resident size and aggregate process CPU
time, which has centisecond precision. CPU percentage below is the change
in process CPU time divided by wall time, with 100% meaning one core. Samples
were taken before the diagnostic capture, avoiding its cost in this interval.

| Elapsed from process launch | Resident size | Process CPU time |
|---|---:|---:|
| 5.064 s | 74,352 KiB (72.61 MiB) | 0.99 s |
| 19.071 s | 26,864 KiB (26.23 MiB) | 1.13 s |

The measured interval used **0.9995% of one core**. RSS did not increase
between these samples. RSS is neither physical footprint nor Alicorn-owned
live allocation accounting; macOS reclamation/compression and framework
memory can change it. This short sample does not certify long-term memory
stability or zero idle wakeups.

## Startup observation

A separate fresh process requested diagnostics immediately after its first
submitted-frame iteration and exited after three host-loop seconds:

```sh
./out/alicorn_native_hello_perf --idle-validation-seconds=3 \
    --capture-after=0 --capture-dir=out/native-hello-startup-perf
```

An external monotonic clock measured process launch to stdout markers:

| Marker | Time |
|---|---:|
| GPU driver selected | 1.049 s |
| First-frame diagnostics log | 1.730 s |

The second marker follows the first swapchain submission and includes
diagnostic serialization and file-output overhead. It precedes the separate
offscreen screenshot. It is **not time to the first visible pixel**. This was
one launch with uncontrolled OS/driver cache state; no cold-start or median
startup claim is made. The host passed normal shutdown with one submitted
and retired application frame.

## Raw evidence

- [Both idle attempts and the startup probe](raw/native-hello-macos-m1-2026-10-02.txt)
- [Idle diagnostics JSON](raw/native-hello-idle-macos-m1-2026-10-02.json)
- [Idle flight-recorder timeline](raw/native-hello-idle-timeline-macos-m1-2026-10-02.json)

Frame and event-pump wall times include time spent waiting for input. They
must not be interpreted as active CPU render cost during idle. The native
sample supports one bounded idle submission path and provides an explicitly
limited CPU/RSS/startup baseline; the separate
[wrapped-text benchmark](text-layout.md) measures headless layout work.
