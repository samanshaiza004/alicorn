# Windows static native-link recipe

Alicorn can prepare the native inputs for an external Odin application that
uses the SDL3 host. The first recipe supports Windows x64 with the MSVC
toolchain and static MSVC runtime. It statically links SDL3 and AccessKit into
the application executable; the application still owns its other languages,
libraries, and packaging choices.

## Request a recipe

From any working directory, invoke the Alicorn script and capture its JSON
output:

```powershell
$recipeJson = & pwsh -NoLogo -NoProfile -File C:\src\alicorn\tools\native_link_recipe.ps1 `
    -Odin C:\Odin\odin.exe `
    -Target windows-x86_64
$recipe = $recipeJson | ConvertFrom-Json
```

The command emits only the recipe on stdout. Build progress and diagnostics go
to stderr. The JSON is a versioned build contract containing:

- `environment.ODIN_ROOT`, the prepared Odin overlay for this generation.
- `odin.executable` and `odin.compilerArguments`, which the caller passes as
  ordinary process arguments without a shell. The argument array includes both
  `-collection:accesskit=<pinned checkout>`,
  `-collection:accesskit_c=<prepared library directory>`, and the native linker flags.
- `odin.collections.accesskit` and `odin.collections.accesskit_c`, the absolute
  binding checkout and prepared native library directory.
- `linkRequirements`, the evaluated SDL directories, options, and ordered
  library inputs plus AccessKit's native system libraries.
- `artifacts`, including absolute library and license paths and SHA-256 hashes.
  `artifacts.accesskit.licenses` retains Apache/MIT order; the additional
  `artifacts.accesskit.notices` object supplies `chromium`, `authors`, and
  `bindingLicense` paths for packaging. All five texts are staged in the
  prepared generation and checked by its manifest.
- `provenance.fingerprint` and `provenance.manifest`, identifying the
  validated prepared generation.

An Odin build driver should set `ODIN_ROOT` only in the Odin child process,
append `recipe.odin.compilerArguments` to its own argument array, and retain
its own working directory and collection arguments, including
`-collection:alicorn=<Alicorn checkout>`. Scratchpad and other external native
consumers must forward the entire compiler argument array: forwarding only
`odin.extraLinkerFlags` omits the required binding and native library collections. No Alicorn
command-line string needs to be parsed or evaluated. The binding checkout must
remain available while compiling; it is prepared automatically from
[`dependencies/odin-accesskit.json`](../dependencies/odin-accesskit.json).

Consumer validators must accept both collection arguments and the linker argument.
Scratchpad's `cmd/alicorn-dev/native_link_recipe.go` currently requires exactly
one linker argument and therefore needs updating before adopting this
extraction. Its static frontend builder already appends the complete argument
array without splitting strings. Shared-SDL consumers must also prepare both
collections even when the native C library is already cached, and add
them to every native build and test invocation.

## Prepared generations

Outputs are stored under `out/native-link/generations/<fingerprint>`. Each
generation records the pinned SDL source hash, SDL options, CMake and MSVC
toolchain identity, target architecture and CRT, Odin executable and SDL
binding identity, standalone odin-accesskit repository, commit, collection path
and package file hashes, AccessKit archive and library hashes, and preparation
code identity. The recipe includes validated artifact hashes and the intended
targets of its Odin SDK junctions.

Preparation uses a per-fingerprint lock, builds into a unique staging
directory, validates the complete file inventory and hashes, and publishes the
generation with a same-volume directory rename. Published generations are
never edited. A cache hit checks its manifest, artifacts, and junction targets
before returning a recipe. A corrupt generation is rejected with its exact
path; remove that generated directory to request a clean preparation.
Different compiler, SDK, or preparation inputs produce a new generation.

The overlay reuses Odin's `base`, `core`, `shared`, `bin`, and non-SDL vendor
packages through checked junctions. It copies the SDK's `vendor/sdl3` binding,
replacing its SDL library with the pinned static build. The installed Odin SDK
is never modified. Paths in the recipe are absolute and quoted for MSVC where
needed, including paths containing spaces.

## Link-interface rules

CMake evaluates the SDL static target's Release link directories, options, and
libraries separately. Alicorn preserves each list's order and repetitions,
converts library names into MSVC default-library inputs, and rejects unknown
imported targets, unresolved generator expressions, unsupported flags, and
missing absolute libraries. The independent Odin consumer build is the final
check that these inputs preserve the actual SDL link semantics.

## Validation

`tools/test_native_link_recipe.ps1` checks path quoting, link ordering,
duplicate preservation, unsupported CMake expressions, invalid x86/CRT
toolchains, unmanifested files, and artifact corruption.
`tools/test_cmake_toolchain_probe.ps1` configures the real CMake toolchain
probe on Windows and validates its machine-readable report. The report records
the resolved pointer size and compiler paths, compiler IDs and versions,
target system, generator platform, and CRT selection; the recipe does not
assume configure-time CMake variables appear in `CMakeCache.txt`.
`tools/test_external_native_link.ps1` starts two cold recipe requests at once,
checks that they publish and reuse one generation, then builds a small Alicorn
app from a temporary external directory whose path contains spaces. It packages
and launches the app from an unrelated empty working directory. The existing
static package auditor rejects unresolved private DLL imports, including an
`SDL3.dll` dependency.

`tools/build_native_release.ps1 -SDLLinkage Static` uses the same preparation
function for Alicorn's `01_hello` example. The ordinary shared-SDL development
flow and the macOS packaging path are unchanged. Static SDL removes the
load-time SDL DLL dependency; it does not by itself make a mixed Go/Rust/Odin
application a single-file executable.

## Measured Windows result

The [Windows static-link job](https://github.com/samanshaiza004/alicorn/actions/runs/38638367490)
ran on Windows Server 2025, image `windows-2025-vs2026` (`20260925.250.1`),
with Odin `dev-2026-10-nightly:e87445a`, CMake 4.4.3, Visual Studio generator
18 2026, MSVC 19.51.36260.0, linker 14.51.36260.0, Windows SDK
10.0.26100.0, and the static MSVC CRT (`/MT`).

| Measurement | Result |
| --- | ---: |
| Cold concurrent SDL preparation and recipe requests | 77.88 s |
| Warm recipe request | 4.19 s |
| External Odin compile and link | 1.91 s |
| External static consumer executable | 10,243,584 bytes |
| Static `01_hello` package build | 23.25 s |
| Static `01_hello` executable | 9,225,728 bytes |
| Shared `01_hello` package build | 19.14 s |
| Shared executable | 6,422,528 bytes |
| `SDL3.dll` | 2,790,400 bytes |
| Shared executable plus `SDL3.dll` | 9,212,928 bytes |

For this example, the static executable is 12,800 bytes (about 0.14%) larger
than the shared executable and SDL DLL combined. Both packages passed the
empty-directory launch smoke test; the static package had no private DLL
imports, while the shared baseline contained only `SDL3.dll`.
