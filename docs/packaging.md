# Native application packaging

Alicorn owns the deployment mechanics of its SDL3 native host. The application
still owns its product metadata and policy: display name, version, bundle ID,
icon, extra resources/libraries, signing, notarization, installers, update
channels, and publication.

The tools intentionally stay small and platform-specific. The regular
`native_hello` scripts remain the fast shared-SDL development path. Release
packaging can build the pinned SDL source statically, build `01_hello`, create a
Windows folder package or macOS `.app`, audit native dependencies, and optionally
launch the finished artifact from an empty working directory.

## Prerequisites

- A complete Odin distribution and the platform prerequisites from
  [Getting Started](getting-started.md).
- CMake 3.24 or newer and a C compiler supported by SDL. Windows needs MSVC and
  the Windows SDK; macOS needs Xcode Command Line Tools.
- macOS packaging additionally uses Python 3, `pkg-config` (for SDL's exported
  static link flags), `otool`, `install_name_tool`, and `plutil` (provided by the
  Apple developer tools).
- The release helper downloads SDL `3.4.18` from the official release asset and
  verifies its pinned SHA-256 before using it. It does not modify the installed
  Odin SDK. Static SDL outputs and the SDK overlay live under ignored `out/`.

## Build the proof application

The checked-in metadata for the minimal starter is
[`examples/01_hello/package.json`](../examples/01_hello/package.json). Copy and
edit that small file for another Odin application. Paths for `icon`, `resources`,
and `privateLibraries` are relative to the metadata file. On macOS,
`privateLibraries` entries must be standalone `.dylib` files; frameworks can be
provided as resources but are not rewritten or audited as private dylib bundles
by this first version.

Windows, from PowerShell:

```powershell
.\tools\build_native_release.ps1 -Odin odin -SDLLinkage Static
```

macOS, from the repository root:

```sh
bash tools/build_native_release.sh --odin "$(command -v odin)" --sdl-linkage static
```

The ordinary `01_hello` remains the minimal learning application. The
interactive macOS direct-launch/Launch Services acceptance protocol lives in
[`tests/fixtures/macos_desktop_launch`](../tests/fixtures/macos_desktop_launch),
so validation-only arguments and controls do not leak into beginner code. On
macOS, build the fixture with both SDL linkages and pass those bundles to the
desktop validator:

```sh
bash tools/build_native_release.sh --metadata tests/fixtures/macos_desktop_launch/package.json --sdl-linkage static --output "out/native-package/desktop fixture static"
bash tools/build_native_release.sh --metadata tests/fixtures/macos_desktop_launch/package.json --sdl-linkage shared --output "out/native-package/desktop fixture shared"
python3 tools/validate_macos_package_desktop.py \
  --static "out/native-package/desktop fixture static/Alicorn macOS Desktop Validation.app" \
  --shared "out/native-package/desktop fixture shared/Alicorn macOS Desktop Validation.app" \
  --results-dir "out/native-package/desktop fixture results"
```

The default output is under `out/native-package/`. It includes the app,
`SDL-LICENSE.txt`, the AccessKit Apache-2.0 and MIT license texts,
`AccessKit-LICENSE.chromium.txt`, `AccessKit-AUTHORS.txt`, the standalone
wrapper's `odin-accesskit-LICENSE.txt`, and
`alicorn-package.json` with the app/build identity, target architecture,
SDL/AccessKit versions and licenses, system dependencies, and hashes for the
executable and bundled native libraries. The result is unsigned.
Windows packages also include `Windows-Caption-LICENSE.txt`, the notice for
the Chromium/Electron geometric conventions used by integrated captions.

For shared SDL packaging, use `-SDLLinkage Shared` on Windows or
`--sdl-linkage shared` on macOS. Shared mode copies SDL beside the Windows EXE
or into `Contents/Frameworks/SDL3.dylib` in the macOS bundle and rewrites the
macOS install name to a bundle-relative `@rpath`. The ordinary development
commands remain unchanged:

```powershell
.\tools\native_hello.ps1
```

```sh
./tools/native_hello.sh
```

## Package an existing application binary

The packagers also accept a built executable, separate from the Odin build
helper. This is the seam for applications whose executable is produced by Go,
Rust, or another toolchain. Windows:

```powershell
.\tools\package_app.ps1 `
  -Executable out\Scratchpad.exe `
  -Metadata path\to\scratchpad-package.json `
  -SDLLinkage Static `
  -SDLLicense path\to\SDL-LICENSE.txt `
  -AccessKitLicenseApache path\to\LICENSE-APACHE `
  -AccessKitLicenseMIT path\to\LICENSE-MIT `
  -AccessKitLicenseChromium path\to\LICENSE.chromium `
  -AccessKitAuthors path\to\AUTHORS `
  -AccessKitBindingLicense path\to\odin-accesskit\LICENSE `
  -OutputDirectory out\package\windows-x86_64
```

For shared SDL, also pass `-SDLRuntime path\to\SDL3.dll`.

macOS:

```sh
python3 tools/package_macos.py \
  --executable out/Scratchpad \
  --metadata path/to/scratchpad-package.json \
  --linkage static \
  --sdl-license path/to/SDL-LICENSE.txt \
  --accesskit-license-apache path/to/LICENSE-APACHE \
  --accesskit-license-mit path/to/LICENSE-MIT \
  --accesskit-license-chromium path/to/LICENSE.chromium \
  --accesskit-authors path/to/AUTHORS \
  --accesskit-binding-license path/to/odin-accesskit/LICENSE \
  --output out/package/macos
```

For shared SDL, also pass `--sdl-runtime path/to/libSDL3.dylib`. Both packagers
refuse to overwrite a non-empty output, assemble into a staging directory, and
publish the completed package only after verification succeeds. Shared macOS
packages also require `--sdl-version major.minor.patch` so the manifest records
the exact runtime version rather than the statically pinned release.

Release helpers forward all AccessKit notices automatically. For an existing
binary, pass all five notice inputs shown above. The wrapper's zlib text is
separate from upstream AccessKit's notices; source redistributions must retain
it. Alicorn also includes it in binary packages and records supplemental notice
hashes under `host.accesskit.notices`. The static native-link recipe exposes
the three supplemental paths under `artifacts.accesskit.notices`, while its
existing two-entry `licenses` array remains Apache/MIT.

## What verification checks

The Windows packager reads PE import tables for the executable and recursively
for every bundled DLL. Windows 10+ inbox DLLs and API-set imports are listed
separately; the packager uses an explicit inbox DLL list rather than treating
any DLL installed on the build machine as an OS dependency. Other imports must
be bundled or declared as an installer-provided runtime prerequisite. For
example, metadata can declare a dynamic Microsoft runtime only when the
installer guarantees that prerequisite on target machines:

```json
{
  "runtimePrerequisites": ["VCRUNTIME140.dll"]
}
```

Declared prerequisites must be imported, cannot be inbox DLLs, and are recorded
in the package manifest. Static mode rejects an SDL3 or Alicorn host DLL
dependency (and stray host DLL files). Shared mode requires `SDL3.dll` to
resolve from the package. The optional smoke test launches the package with an
empty current working directory and a bounded idle-validation timeout.

The macOS packager validates the `.app` structure and `Info.plist`, audits
`otool -L` dependencies and `LC_RPATH` entries for the executable and bundled
dylibs, and rejects non-system absolute build-machine paths. Static mode rejects
dynamic SDL references. Shared mode rewrites SDL to a bundled `@rpath` dylib.
Its optional smoke test also launches from a newly-created empty working
directory.

These are import/load-path audits, not a complete supply-chain scanner: runtime
`LoadLibrary`/`dlopen` calls and app-specific plugin systems need their own
manifest and verification. Add every private Windows DLL to `privateLibraries`
and every private macOS dylib likewise; do not rely on a developer machine's
search path.

The macOS helper ad-hoc signs relocated Mach-O images and the completed app
bundle so the local artifact passes macOS signature verification and its launch
smoke test. This local signature is not a distribution identity. Application CI
remains responsible for Developer ID signing, notarization, stapling, DMG
creation, and release publication. Caliber and language-specific linkage remain
application concerns.
