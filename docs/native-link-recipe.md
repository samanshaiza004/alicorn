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
  ordinary process arguments without a shell.
- `linkRequirements`, the evaluated SDL directories, options, and ordered
  library inputs plus AccessKit's native system libraries.
- `artifacts`, including absolute library and license paths and SHA-256 hashes.
- `provenance.fingerprint` and `provenance.manifest`, identifying the
  validated prepared generation.

An Odin build driver should set `ODIN_ROOT` only in the Odin child process,
append `recipe.odin.compilerArguments` to its own argument array, and retain
its own working directory and collection arguments. No Alicorn command-line
string needs to be parsed or evaluated.

## Prepared generations

Outputs are stored under `out/native-link/generations/<fingerprint>`. Each
generation records the pinned SDL source hash, SDL options, CMake and MSVC
toolchain identity, target architecture and CRT, Odin executable and SDL
binding identity, AccessKit archive and library hashes, and preparation code
identity. The recipe includes validated artifact hashes and the intended
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
the resolved pointer size, compiler IDs and versions, target system, generator
platform, and CRT selection; the recipe does not assume configure-time CMake
variables appear in `CMakeCache.txt`.
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
